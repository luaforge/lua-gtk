#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Configure script for lua-gtk
--

require "lfs"

-- default settings

luagtk_version = "0.8"
show_summary = true
hash_func = "hsieh"
debug_funcs = true	    -- include some debugging functions
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
    "mk68k", "mips", "mipsel powerpc", "s390", "sparc" }


-- Globals

err = 0			    -- global error counter
cflags = "-Wall -I src"	    -- cflags setting for the Makefile
without = {}		    -- list of libraries to exclude
programs = {}		    -- key=program name, value=full path or false
arch = nil		    -- architecture to configure for
config_script = nil	    -- architecture specific config file to include
cmph_dir = nil		    -- if a cmph directory was given, this is it
cfg = { h={}, m={}, l={} }
summary_ar = {}
pkgs_cflags = {}	    -- list of packages to get --cflags for
cross_run = nil
libraries = {}		    -- list of libraries to load at runtime
exe_suffix = ""		    -- suffix for executables (cross compiled)
extra_lib = ""

---
-- Output one line of summary
--
function summary(label, s)
    summary_ar[#summary_ar + 1] = string.format("   %-30s %s", label, s)
end

-- List of architectures for help
function _get_arch_list()
    local base, ar

    ar = {}
    for name in lfs.dir("script") do
	base = string.match(name, "^config.(.*)$")
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
    for name in lfs.dir("libs") do
	if string.sub(name, 1, 1) ~= "." then
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
    print(string.format([[Usage: %s [args] [architecture]
Configure lua-gtk for compilation.

  --debug            Compile with debugging information (-g)
  --gcov             Compile with gcov (coverage)
  --verbose          Explain what this script is doing
  --no-summary       Don't show configure results
  --disable-debug    Omit debugging functions like dump_struct
  --disable-dynlink  Build time instead of runtime linking
  --disable-cmph     Don't use cmph even if it is available
  --without LIBRARY  No support for LIBRARY, even if present
  --with-cmph DIR    Use cmph source tree at the given location
  --host [ARCH]      Cross compile to another architecture, see below

Known architectures: %s.
Known CPUs: %s.
Known libraries: %s.

    ]], arg[0], _get_arch_list(), _get_cpu_list(), _get_lib_list()))
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
    without = function(i)
	assert(arg[i], "Provide a library name after --without")
	without[arg[i]] = true
	return 1
    end,
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
    local err = 0

    while i <= #arg do
	s = arg[i]
	i = i + 1

	if string.sub(s, 1, 2) == "--" then
	    h = option_handlers[string.sub(s, 3)]
	    if not h then
		print("Unknown option " .. s)
		err = err + 1
	    else
		i2 = h(i)
		if i2 then i = i + i2 end
	    end
	else
	    print("Unknown option " .. s)
	    err = err + 1
	end
    end

    if do_show_help then
	show_help()
	err = err + 1
    end

    if err > 0 then
	os.exit(1)
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
	    os.exit(1)
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
	ar[#ar + 1] = s
    end
    return unpack(ar)
end

function pkg_config_exists(package)
    s = find_program "pkg-config"
    assert(s, "Can't find pkg-config.")
    s = os.execute(s .. " --exists " .. package)
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
	os.exit(1)
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
	print(string.format("Please specify the CPU part of the architecture, "
	    .. "e.g. %s-i386.\nKnown architectures: %s", arch_os or arch,
	    _get_cpu_list()))
	os.exit(1)
    end

    local ok = false
    for _, cpu in ipairs(arch_cpus) do
	if cpu == arch_cpu then ok = true; break end
    end

    if not ok then
	print(string.format("Unknown CPU %s.  Add it to the script %s if "
	    .. "desired.", arch_cpu, arg[0]))
	os.exit(1)
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
	    os.exit(1)
	end
    end
  
    cfg_l('arch = "%s"', arch)
    summary("Build architecture", arch)
end

function cfg_m(name, value)
    if value then
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

function general_setup()
    odir = "build/" .. arch .. "/"
    err = 0
    if not is_dir("build") then
	assert(lfs.mkdir("build"))
    end
    if not is_dir(odir) then
	assert(lfs.mkdir(odir))
    end

    cfg_m("ARCH", arch)
    cfg_m("VERSION", luagtk_version)
    cfg_m("ODIR", odir)

    cfg_h("#define LUAGTK_VERSION \"%s\"", luagtk_version)
    cfg_h("#define LUAGTK_%s_%s", arch_os, arch_cpu)
    cfg_h("#define LUAGTK_%s", arch_os)
    cfg_h("#define LUAGTK_%s", arch_cpu)
    cfg_h("#define LUAGTK_ARCH_OS \"%s\"", arch_os)
    cfg_h("#define LUAGTK_ARCH_CPU \"%s\"", arch_cpu)
    cfg_h("#define HASHFUNC hash_%s", hash_func)
    cfg_m("HASHF", hash_func)
    cfg_m("HASH", "hash-$(HASHF)")
    if debug_funcs then
	cfg_h("#define LUAGTK_DEBUG_FUNCS")
    end
    summary("Debugging functions", debug_funcs and "enabled" or "disabled")


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
	cfg_h("#define LUAGTK_LIBRARIES " .. table.concat(libraries) .. ";")
    end
    if extra_lib ~= "" then
	cfg_m("EXTRA_LIB", extra_lib)
    end
    write_config_file(odir .. "config.h", cfg.h)
    write_config_file(odir .. "config.make", cfg.m)
    write_config_file(odir .. "config.lua", cfg.l)
    write_config_file("build/make.state", { arch })
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

    if not pkg_config_exists("lua5.1") then
	return cfg_err("Lua 5.1 headers not installed.")
    end

    pkgs_cflags[#pkgs_cflags + 1] = "lua5.1"

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
    summary("LibFFI closure calling", libffi_call)
    print("\nlua-gtk configured successfully.  Settings:\n")
    print(table.concat(summary_ar, "\n"))
    print("\nType make to build.\n")
end


---
-- For each library to include, check for headers and such
--
function setup_libraries()
    local base, cfg

    cfg_l "libs = {"
    for name in lfs.dir("libs") do
	base = string.match(name, "^(%w+)%.lua$")
	if base then
	    cfg = {}
	    chunk = assert(loadfile("libs/" .. name))
	    setfenv(chunk, cfg)
	    chunk()
	    cfg.disabled = without[base] and true or false
	    cfg.basename = base
	    setup_library(cfg)
	end
    end
    cfg_l "}"
end


---
-- Check one library
-- @param cfg  The configuration from the library's config file
--
function setup_library(cfg)

    if cfg.disabled then
	if cfg.required then
	    return cfg_err("You disabled the required library %s", cfg.name)
	end
	return
    end

    if not pkg_config_exists(cfg.pkg_config_name) then
	if cfg.required then
	    return cfg_err("Required library %s doesn't exist.", cfg.name)
	end
	print(string.format("The optional package %s doesn't exist.", cfg.name))
	return
    end

    local libversion = pkg_config("--modversion", cfg.pkg_config_name)
    if cfg.use_cflags then
	pkgs_cflags[#pkgs_cflags + 1] = cfg.pkg_config_name
    end
    cfg_l("  { name=\"%s\" },", cfg.basename)

    -- add libs to library list for LUAGTK_LIBRARIES
    if use_liblist and cfg.libraries and cfg.libraries[arch_os] then
	for _, name in ipairs(cfg.libraries[arch_os]) do
	    libraries[#libraries + 1] = string.format('"%s\\000"\\\n', name)
	end
    end

    summary(cfg.name, libversion)
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
-- Determine whether to use cmph, where it is installed, what algorithm
-- to use, what the compilation flags are.
--
function setup_cmph()
    local version, f, _


    if not use_cmph then
	version = "disabled"
    elseif cmph_dir then
	cmph_bin = find_file("cmph", cmph_dir, cmph_dir .. "/src",
	    cmph_dir .. "/bin")
	_, cmph_incdir = find_file("cmph_types.h", cmph_dir,
	    cmph_dir .. "/include", cmph_dir .. "/src")
	cmph_libs = find_file("libcmph.a", cmph_dir, cmph_dir .. "/lib",
	    cmph_dir .. "/src/.libs")

	if cmph_bin and cmph_incdir and cmph_libs then
	    have_cmph = true
	    cmph_cflags = "-I " .. cmph_incdir
	    cmph_version = run("*l", cmph_bin, "-V")
	    cmph_libs = cmph_libs .. " -lm"
	else
	    cfg_err("Cmph directory found, but it is not complete.")
	end
	version = cmph_version
    elseif pkg_config_exists "cmph" then
	have_cmph = true
	version, cmph_libs, cmph_cflags = pkg_config("--modversion",
	    "--libs", "--cflags", "cmph")
	cmph_cflags = cmph_cflags or ""
	cmph_bin = "cmph"

	if string.match(cmph_cflags, "^%s*$") then cmph_cflags = "" end

	-- if cmph_cflags is empty, then the includes are in the default
	-- include path, which is not necessarily used, e.g. for MingW or
	-- when cross compiling.  Therefore copy the required include file.
	if cmph_cflags == "" then
	    f = find_file("cmph_types.h", "/usr/include", "/usr/local/include")
	    if f then
		os.execute(string.format("cp %s %s", f, odir))
	    end
	end

	-- What about the private include files?
	_, dir = find_file("cmph_structs.h", "/usr/local/include/cmph/private",
	    "/usr/include/cmph/private")
	if dir then
	    cmph_cflags = cmph_cflags .. " -I " .. dir
	    cmph_incdir = dir
	end
    else
	version = "not available"
    end

    if have_cmph then
	local s = run("*l", cmph_bin, "-a bdz 2>&1")
	if string.match(s, "Invalid") then
	    cmph_algo = "fch"
	    cmph_bin = cmph_bin .. " -c 2.0"
	else
	    cmph_algo = "bdz"
	end

	cfg_m("HAVE_CMPH", 1)
	cfg_m("CMPH_ALGO", cmph_algo)
	cfg_m("CMPH_CFLAGS", cmph_cflags)
	cfg_m("CMPH_BIN", cmph_bin)
	cfg_m("CMPH_LIBS", cmph_libs)

	cfg_h("#define CMPH_ALGORITHM %s_search", cmph_algo)
	cfg_h("#define CMPH_USE_%s", cmph_algo)
    end

    summary("Cmph Library", version)
    if have_cmph then
	summary("Cmph Lib", cmph_libs)
	summary("Cmph Algorithm", cmph_algo)
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
-- Determine correct libffi usage
-- The libffi_* variables are set by the arch specific config file.
--
function setup_ffi()
    local rc, cmd, cmd2, cmd3

    cfg_m("LIBFFI_LIB", libffi_lib)
    cmd = string.format("%s -o %s/test-ffi%s -I %s %s src/test-ffi.c %s",
	cc, odir, exe_suffix, odir, libffi_inc, libffi_lib)

    -- try calling the code, which is the logical API
    cmd2 = cmd .. " -D LUAGTK_FFI_CODE"
    if verbose then print(cmd2) end
    rc = os.execute(cmd2)
    if rc ~= 0 then
	return cfg_err("Failed to compile test-ffi (code)")
    end

    cmd3 = string.format("%s%s/test-ffi%s",
	cross_run and (cross_run .. " ") or "", odir, exe_suffix)
    if verbose then print(cmd3) end
    rc = os.execute(cmd3)
    if rc == 0 then
	libffi_call = "code"
	cfg_h("#define LUAGTK_FFI_CODE")
	return
    end

    -- now try calling the closure.
    cmd2 = cmd .. " -D LUAGTK_FFI_CLOSURE"
    if verbose then print(cmd2) end
    rc = os.execute(cmd2)
    if rc ~= 0 then
	return cfg_err("Failed to compile test-ffi (closure)")
    end

    rc = os.execute(cmd3)
    if rc == 0 then
	libffi_call = "closure"
	cfg_h("#define LUAGTK_FFI_CLOSURE")
	return
    end

    cfg_err("Libffi closure calling failed.")
end


---
-- Load and run the architecture specific config file.  It should do the
-- following settings:
--  libffi_*
--  gtk_libs
--  use_liblist
--
function load_arch_config()
    local chunk = assert(loadfile(config_script))
    chunk()

    if not use_dynlink then
	cfg_m("GTK_LIBS", gtk_libs)
    else
	cfg_h("#define RUNTIME_LINKING")
    end

    summary("Runtime linking", use_dynlink and "enabled" or "disabled")
end


-- MAIN --
    
parse_cmdline()
summary("Version", luagtk_version)
summary("Lua Version", _VERSION)
detect_architecture()
arch = arch or host_arch
check_architecture()
general_setup()
setup_lua()
setup_cmph()
load_arch_config()
setup_compilation()
setup_ffi()
setup_libraries()
if err == 0 then
    write_config()
    if show_summary then do_show_summary() end
end


