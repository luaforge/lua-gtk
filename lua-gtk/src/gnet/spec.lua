-- vim:sw=4:sts=4

name = "GNet"
pkg_config_name = "gnet-2.0"

libraries = {}
libraries.linux = { "/usr/lib/libgnet-2.0.so" }
libraries.win32 = { "libgnet-2.0-0.dll" }

include_dirs = { "gnet-2.0" }

includes = {}
includes.all = {
	"<gnet.h>",
}

headers = {
    { "/usr/include/gnet-2.0/md5.h", true },
    { "/usr/include/gnet-2.0/sha.h", true },
}

linklist = {
    "gnet_inetaddr_ref",
    "gnet_inetaddr_unref",
    "gnet_init",
    "gnet_md5_get_digest",
    "gnet_sha_get_digest",
}

function_flags = {
--    ["gnet_md5_get_digest"] = CONST_CHAR_PTR,
--    ["gnet_sha_get_digest"] = CONST_CHAR_PTR,
}



-- extra settings for the module_info structure
module_info = {
    prefix_func = '"gnet_"',
    prefix_constant = '"GNET_"',
    prefix_type = '"G"',
    prefix_func_remap = 'gnet_func_remap',
    depends = '"glib\\0"',
    overrides = "gnet_overrides",
}

