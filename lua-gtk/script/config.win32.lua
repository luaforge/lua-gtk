-- vim:sw=4:sts=4

local gtk_dir = "mingw/gtk/lib"

if not is_dir(gtk_dir) then
    cfg_err("Gtk not found in %s", gtk_dir)
end

local iconv_dir = "mingw/gtk/include"
if not is_file(iconv_dir .. "/iconv.h") then
    cfg_err("iconv.h not found in %s", iconv_dir)
end

local lua_dir = "mingw/lua5.1"
if not is_dir(lua_dir) or not is_file(lua_dir .. "/lua5.1.dll") then
    cfg_err("Lua 5.1 not found in %s", lua_dir)
end

-- FFI --

local ffi_dir = "mingw/libffi-mingw"
if not is_dir(ffi_dir) or not is_file(ffi_dir .. "/libffi.a") or
    not is_file(ffi_dir .. "/ffi.h") then
    cfg_err("LibFFI not found in %s", ffi_dir)
else
    libffi_lib = ffi_dir .. "/libffi.a"
    libffi_inc = "-I " .. ffi_dir
    libffi_version = ffi_dir
end

-- MINGW --

local mingw = "i586-mingw32msvc-"
local s = find_program(mingw .. "gcc")
if s then
    cc = s
else
    cfg_err("MingW GCC not found.")
end

-- don't use qemu - it can't run windows executables.
cross_run = "wine"

cfg_m("INDIR1", "/usr/local/lib/lua/5.1")
cfg_m("INDIR2", "/usr/local/share/lua/5.1")
cfg_m("DLLEXT", ".dll")
lua_lib = lua_dir .. "/lua5.1.dll"
-- cfg_m("EXTRA_LIB += " .. lua_dir .. "/lua5.1.dll")
cfg_m("LUADIR", lua_dir)
cfg_m("EXESUFFIX", ".exe")
cfg_l('cc_flags = "-I %s"', iconv_dir)
exe_suffix = ".exe"

-- Always require the list of libraries.  This is because the windows library
-- must open all linked libraries by name, even if it is linked with them
-- at compile time.
use_liblist = true

