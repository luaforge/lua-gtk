#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Configure script for the core library and modules.  It is to be called
-- with a "spec.lua" file argument, and accepts optional flags.
--
-- Exit code: 0=ok, 1..9=some error, continue, >10 = stop configuring
--
-- Copyright (C) 2008, 2009 Wolfgang Oertl
--

require "lfs"
require "script.util"

-- default settings

show_summary = true
use_debug = false	    -- compile with "-g"
use_gcov = false	    -- compile with coverage code
use_cmph = true
use_dynlink = true
do_show_help = false
required_lua_libs = { "lxp", "bit", "lfs" }
optional_lua_libs = { "luadoc.lp" }
verbose = false

-- List of Debian supported CPUs
arch_cpus = { "alpha", "amd64", "arm", "arml", "armel", "hppa", "i386", "ia64",
    "mk68k", "mips", "mipsel", "powerpc", "s390", "sparc" }


-- Globals

spec = nil		    -- parsed contents of the module's spec file
err = 0			    -- global error counter
fatal_err = false
cflags = "-Wall -I include" -- cflags setting for the Makefile
-- without = {}		    -- list of libraries to exclude
programs = {}		    -- key=program name, value=full path or false
arch = nil		    -- architecture to configure for (from cmd line)
arch_os = nil		    -- OS part of the target (e.g. linux)
arch_cpu = nil		    -- CPU part of the target (e.g. i386)
config_script = nil	    -- architecture specific config file to include
cmph_dir = nil		    -- if a cmph directory was given, this is it
cfg = { h={}, m={}, l={} }
summary_ar = {}
pkgs_cflags = {}	    -- list of packages to get --cflags for
cross_run = nil
libraries = {}		    -- list of libraries to load at runtime
exe_suffix = ""		    -- suffix for executables (cross compiled)
lua_lib = ""
local logfile		    -- log summary and additional messages here

---
-- Append one line to the summary.
--
function summary(label, s)
    summary_ar[#summary_ar + 1] = string.format("   %-30s %s", label, s)
end

-- List of architectures for help
function _get_arch_list()
    local base, ar

    ar = {}
    for name in lfs.dir("script") do
	base = string.match(name, "^config%.(.*)%.lua$")
	if base then
	    ar[#ar + 1] = base
	end
    end
    table.sort(ar)
    return table.concat(ar, " ")
end

-- List of libraries for help
function _get_lib_list()
    local ar = {}
    for name in lfs.dir("src") do
	if string.sub(name, 1, 1) ~= "." and not string.find(name, "%.")
	    and name ~= "CVS" and name ~= "hash"
	    and lfs.attributes("src/" .. name, "mode") == "directory" then
	    ar[#ar + 1] = string.match(name, "^[^.]+")
	end
    end
    table.sort(ar)
    return table.concat(ar, " ")
end

-- List of CPUs for help
function _get_cpu_list()
    return table.concat(arch_cpus, " ")
end

function show_help()
    print(string.format([[Usage: %s [args] [module]
Configure LuaGnome for compilation.

  --debug            Compile with debugging information (-g)
  --gcov             Compile with gcov (coverage)
  --verbose          Explain what this script is doing
  --no-summary       Don't show configure results
  --disable-debug    Omit debugging functions like dump_struct
  --disable-dynlink  Build time instead of runtime linking
  --disable-cmph     Don't use cmph even if it is available
  --with-cmph DIR    Use cmph source tree at the given location
  --host [ARCH]      Cross compile to another architecture, see below

Known architectures: %s.
Known CPUs: %s.
Known modules: %s.

    ]], arg[0], _get_arch_list(), _get_cpu_list(), _get_lib_list()))
    fatal_err = true
end


-- Command Line Parsing --

option_handlers = {
    debug = function() use_debug=true end,
    summary = function() show_summary=true end,
    verbose = function() verbose=true end,
    ["no-summary"] = function() show_summary=false end,
    ["enable-debug"] = function() debug_funcs=true end,
    ["disable-debug"] = function() debug_funcs=false end,
    ["enable-dynlink"] = function() use_dynlink=true end,
    ["disable-dynlink"] = function() use_dynlink=false end,
    ["enable-cmph"] = function() use_cmph=true end,
    ["disable-cmph"] = function() use_cmph=false end,
    ["enable-gcov"] = function() use_gcov = true end,
    ["disable-gcov"] = function() use_gcov = false end,
    ["with-cmph"] = function(i)
	assert(arg[i], "Provide a path for --with-cmph")
	use_cmph=true
	cmph_dir=arg[i]
	assert(is_dir(cmph_dir), "The path given for --with-cmph doesn't "
	    .. "exist or is not a directory")
	return 1
    end,
    host = function(i)
	assert(not arch, "Unexpected option --host; already set.")
	assert(arg[i], "Please provide an architecture for --host")
	arch = arg[i]
	return 1
    end,
    help = function() do_show_help=true end,
}

function parse_cmdline()
    local i2, s
    local i = 1
    local c_err = 0

    while i <= #arg do
	s = arg[i]
	i = i + 1

	if string.sub(s, 1, 2) == "--" then
	    h = option_handlers[string.sub(s, 3)]
	    if not h then
		print("Unknown option " .. s)
		c_err = c_err + 1
	    else
		i2 = h(i)
		if i2 then i = i + i2 end
	    end
	else
	    print("Unknown option " .. s)
	    c_err = c_err + 1
	end
    end

    if do_show_help then
	show_help()
	c_err = c_err + 1
    end

    if c_err > 0 then
	os.exit(fatal_err and 10 or 1)
    end
end


---
-- Find the program using "which", set the result in the global
-- table "programs", and return the path (or nil if not available).  Because
-- of caching, it is OK to call this often with the same argument.
--
function find_program(prg)
    if not programs[prg] then
	if programs[prg] == false then return end

	fh = io.popen("which " .. prg)
	if not fh then
	    print "Can't run the command \"which\", aborting"
	    os.exit(10)
	end
	s = fh:read "*l"
	fh:close()
	if not s or s == "" then
	    if verbose then print("- program not found: " .. prg) end
	    programs[prg] = false
	    return
	end
	programs[prg] = s
	if verbose then print("- program found: " .. s) end
    end
    return programs[prg]
end


---
-- Try to run the given program, and read its output
-- @param mode  "*a" to read all, or "*l" to read just the first line.
-- @param prg  The name of the program to run (may include absolute path)
-- @param ...  extra arguments
--
function run(mode, prg, ...)
    local fh , s
    s = find_program(prg)
    if not s then return end
    s = table.concat({ s, ... }, " ")
    fh = io.popen(s)
    if not fh then return end
    s = fh:read(mode)
    fh:close()
    return s
end

-- helper function to determine whether a given directory exists.
function is_dir(path)
    return lfs.attributes(path, "mode") == "directory"
end

function is_file(path)
    return lfs.attributes(path, "mode") == "file"
end

---
-- Call pkg-config and retrieve the answer
-- Returns nil on error
--
function pkg_config(...)
    local s, fh, ar

    s = find_program("pkg-config")
    assert(s, "Can't find pkg-config.")
    s = table.concat({s, ...}, " ")
    -- print(s)
    fh = io.popen(s)
    ar = {}
    while true do
	s = fh:read "*l"
	if not s then break end
	ar[#ar + 1] = string.gsub(s, "^%s*", "")
    end
    return unpack(ar)
end

function pkg_config_exists(package)
    s = find_program "pkg-config"
    assert(s, "Can't find pkg-config.")
    s = os.execute(s .. " --print-errors --exists " .. package)
    return s == 0
end

---
-- Try to determine the build architecture.  First, query dpkg-architecture,
-- which works on Debian, else try "uname -m".
--
function detect_architecture()
    local s, arch_os, arch_cpu

    s = run("*a", "dpkg-architecture")
    if s then
	arch_os = string.match(s, "DEB_BUILD_ARCH_OS=(%w*)")
	assert(arch_os, "dpkg-architecture didn't set DEB_BUILD_ARCH_OS")
	arch_cpu = string.match(s, "DEB_BUILD_ARCH_CPU=(%w*)")
	assert(arch_cpu, "dpkg-architecture didn't set DEB_BUILD_ARCH_CPU")
	host_arch=arch_os .. "-" .. arch_cpu
	return
    end

    arch_cpu = run("*l", "uname", "-m")

    if arch_cpu == "x86_64" then
	arch_cpu = "amd64"
    elseif arch_cpu == "i686" then
	arch_cpu = "i386"
    else
	print(string.format("Unsupported result %s from uname -m.  Please "
	    .. "fix the script\n%s and send the patches to the author.",
	    arch_cpu, arg[0]))
	os.exit(10)
    end

    host_arch="linux-" .. arch_cpu
end

---
-- Split host_arch into os and cpu.  This is done because the user can
-- specify that on the command line.
--
function check_architecture()
    arch_os, arch_cpu = string.match(arch, "^(%w-)-(%w-)$")
    if not arch_cpu or arch_cpu == "" then
	print(string.format("Please specify both architecture and CPU parts "
	    .. "of the target, e.g. linux-i386.\nKnown architectures: %s",
	    _get_cpu_list()))
	os.exit(10)
    end

    local ok = false
    for _, cpu in ipairs(arch_cpus) do
	if cpu == arch_cpu then ok = true; break end
    end

    if not ok then
	print(string.format("Unknown CPU %s.  Add it to the script %s if "
	    .. "desired.", arch_cpu, arg[0]))
	os.exit(10)
    end

    -- determine the appropriate config files.
    local script_prefix = "script/config."
    config_script = script_prefix .. arch .. ".lua"
    if not is_file(config_script) then
	config_script = script_prefix .. arch_os .. ".lua"
	if not is_file(config_script) then
	    print(string.format("Unknown architecture %s: neither %s%s.lua "
		.. "nor\n%s%s.lua are available.", arch, script_prefix, arch,
		script_prefix, arch_os))
	    os.exit(10)
	end
    end
  
    cfg_l('arch = "%s"', arch)
    summary("Build architecture", arch)
end

function cfg_m(name, value)
    if value ~= nil then
	if type(value) == "boolean" then
	    value = value and "1" or "0"
	end
	cfg.m[#cfg.m + 1] = string.format("%-20s :=%s", name, value)
    else
	cfg.m[#cfg.m + 1] = name
    end
end

function cfg_h(...)
    cfg.h[#cfg.h + 1] = string.format(...)
end

function cfg_l(...)
    cfg.l[#cfg.l + 1] = string.format(...)
end

function cfg_err(fmt, ...)
    print(string.format(fmt, ...))
    err = err + 1
end

function cfg_fatal(...)
    fatal_err = true
    cfg_err(...)
    os.exit(11)
end

function general_setup(libname)
    local odir1 = "build/" .. arch -- .. "/"

    err = 0
    if not is_dir("build") then
	assert(lfs.mkdir("build"))
    end
    if not is_dir(odir1) then
	assert(lfs.mkdir(odir1))
    end

    if libname then
	odir = odir1 .. "/" .. libname	    --  .. "/"
	if not is_dir(odir) then
	    assert(lfs.mkdir(odir))
	end
    else
	odir = odir1
    end

    logfile = assert(io.open(odir .. "/config.log", "w"))

    cfg_m("ARCH", arch)
    cfg_m("ODIR", odir)
    cfg_h("#define LUAGTK_%s_%s", arch_os, arch_cpu)
    cfg_h("#define LUAGTK_%s", arch_os)
    cfg_h("#define LUAGTK_%s", arch_cpu)
    cfg_h("#define LUAGTK_ARCH_OS \"%s\"", arch_os)
    cfg_h("#define LUAGTK_ARCH_CPU \"%s\"", arch_cpu)

    local name = "script/Makefile." .. arch_os
    if is_file(name) then
	cfg_m("include " .. name)
    end

    name = "script/Makefile." .. arch
    if is_file(name) then
	cfg_m("include " .. name)
    end
end

---
-- Write resulting configuration, but only if the contents has changed.
--
function write_config()
    local flags = pkg_config("--cflags", unpack(pkgs_cflags))
    cfg_m("CFLAGS", cflags .. " " .. flags)
    if use_liblist then
	cfg_l('libraries = { %s }', table.concat(libraries, "," ))
    end
    if lua_lib ~= "" then
	cfg_m("LUA_LIB", lua_lib)
    end
    write_config_file(odir .. "/config.h", cfg.h)
    write_config_file(odir .. "/config.make", cfg.m)
    write_config_file(odir .. "/config.lua", cfg.l)
end

function write_config_file(ofile, ar)
    local fh, old_content, new_content

    new_content = table.concat(ar, "\n") .. "\n"
    fh = io.open(ofile, "r")
    if fh then
	old_content = fh:read "*a"
	fh:close()
	if old_content == new_content then
	    return
	end
    end

    fh = assert(io.open(ofile, "w"))
    fh:write(new_content)
    fh:close()
end


---
-- Check for a working installation of Lua.  Of course the binary runs this
-- script, but additional modules and the header files are required.
--
function setup_lua()
    local flags, rc, msg

    -- detect both lua5.1 (Debian) and lua (Fedora), thanks to Gabriel Ramos.
    if pkg_config_exists"lua5.1" then
	pkgs_cflags[#pkgs_cflags + 1] = "lua5.1"
    elseif pkg_config_exists"'lua >= 5.1'" then
	pkgs_cflags[#pkgs_cflags + 1] = "lua"
    else
	return cfg_err("Lua 5.1 headers not installed.")
    end

    for _, lib in ipairs(required_lua_libs) do
	rc, msg = pcall(function() require(lib) end)
	if not rc then
	    cfg_err("Required Lua package %s not found.", lib)
	end
    end

    for _, lib in ipairs(optional_lua_libs) do
	rc, msg = pcall(function() require(lib) end)
	if not rc then
	    print("Optional Lua package " .. lib .. " not found.")
	end
    end
end


function do_show_summary()
    local s

    s = string.format("\nLuaGnome module %s configured successfully.  "
	.. "Settings:\n", spec.basename)
    print(s)
    logfile:write(s)

    s = table.concat(summary_ar, "\n")
    print(s)
    logfile:write(s .. "\n")

    print(string.format("\nType \"make %s\" to build.\n", spec.basename))
end


---
-- Check one library.
-- @param cfg  The configuration from the library's config file
-- @return  The "cfg" argument, or nil on error.
--
function _setup_library(cfg)

    if not pkg_config_exists(cfg.pkg_config_name) then
	if cfg.required then
	    return cfg_err("Required library %s doesn't exist.", cfg.name)
	end
	print(string.format("The optional package %s (%s) doesn't exist.",
	    cfg.name, cfg.pkg_config_name))
	cfg_m("NOT_AVAILABLE", 1)
	return
    end

    local libversion = pkg_config("--modversion", cfg.pkg_config_name)
    pkgs_cflags[#pkgs_cflags + 1] = cfg.pkg_config_name

    -- add libs to library list
    if use_liblist and cfg.libraries and cfg.libraries[arch_os] then
	for _, name in ipairs(cfg.libraries[arch_os]) do
	    libraries[#libraries + 1] = string.format('"%s"', name)
		-- string.format('"%s\\000"\\\n', name)
	end
    end

    summary(cfg.name, libversion)
    return cfg
end


function find_file(name, ...)
    local s, dir

    for i = 1, select('#', ...) do
	dir = select(i, ...)
	s = dir .. "/" .. name
	if is_file(s) then
	    return s, dir
	end
    end
end



---
-- Determine the compiler, cross compilation, how to run cross compiled
-- test scripts, CFLAGS etc.
--
function setup_compilation()
    local s, qemu

    s = find_program "gcc"
    if not s then
	cfg_err("GCC not found.")
    else
	host_cc = s
	cc = cc or s	    -- might be set by arch specific config
    end

    -- detect speedblue.org cross compilation
    s = string.format("/usr/%s/bin/%s-linux-gcc", arch_cpu, arch_cpu)
    if is_file(s) then
	cc = s
    end

    -- how to run cross-compiled test scripts?
    if arch ~= host_arch and not cross_run then
	if arch_cpu == "powerpc" then
	    qemu = "qemu-pcc"
	else
	    qemu = "qemu-" .. arch_cpu
	end
	s = find_program(qemu)
	if s then
	    cross_run = s
	end
    end

    if libffi_inc then
	cflags = cflags .. " " .. libffi_inc
    end

    -- debugging
    if use_debug then
	cflags = cflags .. " -g"
	cfg_m("LDFLAGS +=-g")
    else
	cflags = cflags .. " -Os -fomit-frame-pointer"
    end
    summary("Debugging symbols", use_debug and "on" or "off")


    cfg_m("CC", cc)
    cfg_l('cc = "%s"', cc)
    cfg_m("HOSTCC", host_cc)
    cfg_m("DYNLINK", use_dynlink)
    if cross_run then
	cfg_m("CROSS_RUN", cross_run)
    end

    local hostcc_version = run("*l", host_cc, "--version")
    summary("C Compiler", hostcc_version)

    if cc ~= host_cc then
	local cc_version = run("*l", cc, "--version")
	summary("Cross compiler", cc_version)
    end

    cflags = cflags .. " -I " .. odir
end


---
-- Load and run the architecture specific config file.  It should do the
-- following settings:
--  libffi_*
--  mod_libs
--  use_liblist
--
function load_arch_config()
    local chunk = assert(loadfile(config_script))
    chunk()

    if not use_dynlink then
	cfg_m("MOD_LIBS", mod_libs or "")
    else
	cfg_h("#define RUNTIME_LINKING")
	cfg_l('runtime_linking = true')
    end

    summary("Runtime linking", use_dynlink and "enabled" or "disabled")
end


function configure_done()
    if err > 0 then os.exit(1) end
    write_config()
    if show_summary then do_show_summary() end
end


---
-- Configure settings required for both the core module and library modules.
-- Modules can provide additional flags, so read the spec file first, and then
-- look at the other arguments.
--
function configure_main()
    local module_name, s

    if #arg == 0 then
	print("configure: missing spec.lua file")
	os.exit(1)
    end

    -- the last argument should be the spec file.  If it is an option,
    -- e.g. "--help", subtitute the core module for it.
    module_name = table.remove(arg)
    if string.sub(module_name, 1, 1) == "-" then
	arg[#arg + 1] = module_name
	module_name = "gnome"
    else
	s = string.match(module_name, "([^/]+)/spec.lua$")
	module_name = s or module_name
    end

    spec = load_spec(string.format("src/%s/spec.lua", module_name))
    spec.basename = module_name

    -- complex modules (i.e. the core module) may provide a configure script.
    s = string.format("src/%s/configure.lua", module_name)
    if lfs.attributes(s, "mode") then
	load_config(s, _G)
	main()
	if err > 0 then
	    os.exit(fatal_err and 10 or 1)
	end
	return
    end

    -- The default action is to call these two functions.  If a module-specific
    -- configure script is available, it will call these two and perform
    -- additional tasks.
    configure_base()
    configure_done()
end

function configure_base()
    local modname, tmp, s

    modname = spec.basename
    parse_cmdline()

    summary("Lua Version", _VERSION)
    cfg_l("prefix = \"%s_\"", modname)
    cfg_l("srcdir = \"src/%s\"", modname)
    cfg_m("CONFIG_ARGS", table.concat(arg, " "))
    detect_architecture()
    arch = arch or host_arch
    check_architecture()
    general_setup(modname)
    setup_lua()
    load_arch_config()
    setup_compilation()
    cfg_l('module = "%s"', modname)
    if not _setup_library(spec) then
	show_summary = false
	configure_done()
	os.exit(2)
    end

    -- don't add libraries from additional module specs, only cflags
    tmp = use_liblist
    use_liblist = false
    for _, modname in ipairs(spec.moddep or {}) do
	s = load_spec(string.format("src/%s/spec.lua", modname))
	s.basename = modname
	_setup_library(s)
    end
    use_liblist = tmp

end

configure_main()

