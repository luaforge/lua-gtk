#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Configure script for the core module of LuaGnome.
-- Copyright 2007, 2008 Wolfgang Oertl
--

require "src/hash/hash-conf"

-- Default Settings --

lg_version = "1.0-rc3"
debug_funcs = true	    -- include some debugging functions


---
-- Determine correct libffi usage
-- The libffi_* variables are set by the arch specific config file.
--
function setup_ffi()
    local rc, cmd, cmd2, cmd3, ifile
    
    ifile = "src/gnome/test-ffi.c"
    if not lfs.attributes(ifile) then
	cfg_err("Missing source file %s", ifile)
	return
    end

    cfg_m("LIBFFI_LIB", libffi_lib)
    cmd = string.format("%s -o %s/test-ffi%s -I %s %s %s %s",
	cc, odir, exe_suffix, odir, libffi_inc, ifile, libffi_lib)

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
-- Detect settings required to compile the core module.
--
function configure_gnome()
    cfg_m("VERSION", lg_version)
    cfg_h("#define LUAGTK_VERSION \"%s\"", lg_version)
    if debug_funcs then
	cfg_h("#define LUAGTK_DEBUG_FUNCS")
    end
    summary("Debugging functions", debug_funcs and "enabled" or "disabled")

    setup_ffi()
    if libffi_call then
	summary("LibFFI closure calling", libffi_call)
    end

    -- need that library to generate dynamic link information
    cfg_l("is_core = true")
    cfg_l("prefix = \"gnome_\"")

    local ar = {}
    for _, name in ipairs(libraries) do
	ar[#ar + 1] = string.gsub(name, '^"(.*)"$', '%1\\0')
    end
    cfg_h("#define LUAGTK_LIBRARIES \"" .. table.concat(ar) .. '"')
end

-- MAIN --

function main()
    summary("Version", lg_version)
    configure_base()
    configure_gnome()
    configure_hash()
    configure_done()

    -- make.state is used by the toplevel makefile to automatically select the
    -- architecture.
    ar =  { "ARCH=" .. arch }
    write_config_file("build/make.state", ar)
end

