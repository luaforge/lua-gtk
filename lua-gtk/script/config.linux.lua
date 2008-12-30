-- vim:sw=4:sts=4

if not use_dynlink then
    gtk_libs = pkg_config("--libs", "gtk+-2.0")
end

function detect_ffi()

    if false and pkg_config_exists "libffi" then
	libffi_version, libffi_lib, libffi_inc = pkg_config("--modversion",
	    "--libs", "--cflags", "libffi")
	libffi_inc = libffi_inc or ""
	return
    end

    -- no pkg-config for libffi found (which was added for libffi5)
    local f = find_file("libffi_pic.a", "/usr/" .. arch_cpu .. "-linux-gnu/lib",
	"/usr/lib", "/usr/local/lib")
    if not f then
	f = find_file("libffi.so", "/usr/" .. arch_cpu .. "-linux-gnu/lib",
	    "/usr/lib", "/usr/local/lib")
	if not f then
	    cfg_err("libffi.so not found.")
	    return
	end
    end

    libffi_version = "4"	-- just a guess
    libffi_lib = f
    libffi_inc = ""		-- hopefully in the search path
end

detect_ffi()

-- extra include for libffi when cross compiling
if host_arch ~= arch then
    local ar = {}
    for dir in lfs.dir("/usr") do
	if string.match(dir, "^" .. arch_cpu) and
	    lfs.attribute(dir .. "/include", "mode") then
	    ar[#ar + 1] = dir .. "/include"
	end
    end

    if #ar > 0 then
	local f = find_file("ffi.h", unpack(ar))
	if f then
	    libffi_inc = "-I " .. f
	end
    end
end

-- installation directories
cfg_m("INDIR1", "/usr/local/lib/lua/5.1")
cfg_m("INDIR2", "/usr/local/share/lua/5.1")

-- output file with ".so" extension
cfg_m("O", "o")
cfg_m("DLLEXT", ".so")
-- cfg_m("ODLL", "gtk.so")

-- need to generate "position independent code"
cflags = cflags .. " -fpic"

-- For dynamic linking, need to include the list of libraries.  Otherwise,
-- this is not required.
if use_dynlink then
    use_liblist = true
end

if use_gcov then
    cflags = cflags .. " -fprofile-arcs -ftest-coverage"
    lua_lib = lua_lib .. " -fprofile-arcs"
    summary("GCov code", "enabled")
end

