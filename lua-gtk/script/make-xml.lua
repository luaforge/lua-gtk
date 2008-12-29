#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Run gccxml on a simple C file to generate a huge XML file with all the
-- type information.

-- configuration --

config = {}

-- end --

tmp_file = "tmpfile.c"
tmp_content = nil
dump_c = false
require "script/util"

---
-- Call pkg-config and retrieve the answer
-- Returns nil on error
--
function pkg_config(package, option)
    local s, fhandle, version 

    s = string.format("pkg-config %s %s", option, package)
    fhandle = io.popen(s)

    if not fhandle then
	-- pkg-config not available?
	return nil
    end

    s = fhandle:read("*l")
    fhandle:close()
    return s
end

function add_defs(tbl)
    if not tbl then return "" end
    return table.concat(tbl, "\n") .. "\n"
end

function add_includes(tbl)
    if not tbl then return "" end
    local tbl2 = {}
    for i, inc in ipairs(tbl) do
	tbl2[#tbl2 + 1] = "#include " .. inc
    end
    return table.concat(tbl2, "\n") .. "\n"
end

---
-- Try to generate the XML file.  Returns 0 if ok, non-zero otherwise.
--
function generate_xml(ofname, platform)
    local ofile, s, rc
    local pkgs = {}		-- pkg-config package list
    local arch_os = config.arch_os
    local defs = ""
    local includes = ""

    cfg_file = string.format("%s/spec.lua", config.srcdir)
    cfg = load_spec(cfg_file)
    pkgs[#pkgs + 1] = cfg.pkg_config_name
    if cfg.defs then
	defs = defs .. add_defs(cfg.defs.all)
	defs = defs .. add_defs(cfg.defs[arch_os])
    end
    if cfg.includes then
	includes = includes .. add_includes(cfg.includes.all)
	    .. add_includes(cfg.includes[arch_os])
    end
    
    -- XXX this could already be done by configure, thus obviating the
    -- need to call pkg-config at all.
    flags = pkg_config(table.concat(pkgs, " "), "--cflags")
    if config.cc_flags then
	flags = flags .. " " ..config.cc_flags
    end

    tmp_content = defs .. includes

    if dump_c then
	print(tmp_content)
	os.exit(0)
    end

    ofile = io.open(tmp_file, "w")
    if not ofile then
	print("Can't open output file " .. tmp_file)
	return 1
    end

    ofile:write(tmp_content)
    ofile:close()
    s = string.format("gccxml %s -fxml=%s %s %s", flags, ofname,
	"--gccxml-compiler " .. config.cc,
	tmp_file)
    rc = os.execute(s)
    os.remove(tmp_file)

    return rc
end


---
-- Generation of the XML file failed.  Try to download it, but this requires
-- the Gtk version to be known.  If pkg-config doesn't exist, ask the user.
--
function download_interactive(ofname, platform)
    local version

    version = pkg_config("gtk+-2.0", "--modversion")
    if not version then
	-- pkg-config not available?
	print "make-xml.lua: What is your Gtk version?"
	version = io.read()
	if not version then return 3 end
    end

    print("Your Gtk Version is " .. tostring(version))
    return download_types_xml(ofname, platform, version)
end


-- List of supported Gtk versions.  Unfortunately, on luaforge a new
-- subdirectory (real or virtual, don't know) is created for each file
-- release, so the URL can't be derived automatically from the version.
urls = {
    ['2.12.1-linux']
	= "http://luaforge.net/frs/download.php/3040/types.xml-2.12.1-linux.gz",
    ['2.12.1-win32']
	= "http://luaforge.net/frs/download.php/3041/types.xml-2.12.1-win32.gz",
}


---
-- If gccxml is not available or fails, try to download with wget or curl.
--
function download_types_xml(ofname, platform, version)

    local s, url, rc, key

    key = string.format("%s-%s", version, platform)
    url = urls[key]
    if not url then
	print("Version " .. key .. " not supported; can't download.")
	return 1
    end

    s = string.format("wget -O %s.gz %s", ofname, url)
    print(s)
    rc = os.execute(s)

    if rc ~= 0 then
	s = string.format("curl -o %s.gz %s", ofname, url)
	print(s)
	rc = os.execute(s)
	if rc ~= 0 then
	    print "Downloading failed!"
	    return 2
	end
    end

    -- unpack the gzip file.
    s = string.format("gunzip -f %s.gz", ofname)
    print(s)
    return os.execute(s)
end


-- MAIN --
-- arguments: output_file_name, lua_config_file

if arg[1] == "--dump-c" then
    dump_c = true
    table.remove(arg, 1)
end

if not arg[1] then
    print "Parameters: build directory."
    return
end

config = load_config(arg[1] .. "/config.lua")
assert(config.arch, "No architecture defined in config file")
assert(config.module, "No module defined in config file")
config.arch = string.lower(config.arch)
config.arch_os = string.match(config.arch, "^[^-]+")
ofname = arg[1] .. "/types.xml"

rc = generate_xml(ofname, config.arch)
if rc ~= 0 then
    rc = download_interactive(ofname, config.arch)
end

if rc ~= 0 then
    print(string.format("%s failed.  The C file content is:\n%s", arg[0],
	tmp_content))
end
os.exit(rc)

