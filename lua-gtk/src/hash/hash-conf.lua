-- vim:sw=4:sts=4
-- to be included from src/gnome/configure.lua.

-- hash_func = "hsieh"

---
-- Determine whether to use cmph, where it is installed, what algorithm
-- to use, what the compilation flags are.
--
function setup_cmph()
    local version, f, _

    if not use_cmph then
	version = "disabled"
    elseif cmph_dir then
	_, cmph_incdir = find_file("cmph_types.h", cmph_dir,
	    cmph_dir .. "/include", cmph_dir .. "/src")
	cmph_libs = find_file("libcmph.a", cmph_dir, cmph_dir .. "/lib",
	    cmph_dir .. "/src/.libs")

	if cmph_incdir and cmph_libs then
	    have_cmph = true
	    cmph_cflags = "-I " .. cmph_incdir
	    cmph_libs = cmph_libs .. " -lm"
	else
	    cfg_err("Cmph directory found, but it is not complete.")
	end
	version = "available"
    elseif pkg_config_exists "cmph" then
	version, cmph_libs, cmph_cflags = pkg_config("--modversion",
	    "--libs", "--cflags", "cmph")
	if version < "0.8" then
	    version = version .. " (too old, at least 0.8 required)"
	else
	    have_cmph = true
	    cmph_cflags = cmph_cflags or ""
	    cmph_cflags = string.gsub(cmph_cflags, "^%s*$", "")

	    -- if cmph_cflags is empty, then the includes are in the default
	    -- include path, which is not necessarily used, e.g. for MingW or
	    -- when cross compiling.  Therefore copy the required include file.
	    if cmph_cflags == "" then
		f = find_file("cmph_types.h", "/usr/include",
		    "/usr/local/include")
		if f then
		    os.execute(string.format("cp %s %s", f, odir))
		end
	    end

	    -- What about the private include files?
	    _, dir = find_file("cmph_structs.h",
		"/usr/local/include/cmph/private", "/usr/include/cmph/private")
	    if dir then
		cmph_cflags = cmph_cflags .. " -I " .. dir
		cmph_incdir = dir
	    end
	end
    else
	version = "not available"
    end

    if have_cmph then
	local rc = os.execute(string.format("%s -o %s/hash-cmph-detect "
	    .. "src/hash/hash-cmph-detect.c %s %s",
	    host_cc, odir, cmph_cflags, cmph_libs))
	if rc ~= 0 then
	    summary("Cmph", "unable to compile hash-cmph-detect")
	    have_cmph = false
	    return
	end

	local s = run("*l", odir .. "/hash-cmph-detect")
	if s == nil or s == "" then
	    summary("Cmph", "no useful algorithm detected")
	    have_cmph = false
	    return
	end

	cmph_algo = s

	cfg_m("HAVE_CMPH", 1)
	-- cfg_m("CMPH_ALGO", cmph_algo)
	cfg_m("CMPH_CFLAGS", cmph_cflags)
	cfg_m("CMPH_LIBS", cmph_libs)
	cfg_h("#define CMPH_USE_%s", cmph_algo)
    end

    summary("Cmph Library", version)
    if have_cmph then
	summary("Cmph Lib", cmph_libs)
	summary("Cmph Algorithm", cmph_algo)
    end
end


function configure_hash()
    setup_cmph()
    if have_cmph then
	hash_method = "cmph-" .. cmph_algo
	cfg_h("#define LG_CMPH_ALGO CMPH_" .. string.upper(cmph_algo))
    else
	hash_method = "simple"
    end
    cfg_h("#define LUAGNOME_HASH_METHOD \"%s\"\n", hash_method)
    cfg_m("HASH_METHOD", hash_method)
end

