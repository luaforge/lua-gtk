-- vim:sw=4:sts=4

name = "gconf"
pkg_config_name = "gconf-2.0"

libraries = {}
libraries.linux = { "/usr/lib/libgconf-2.so.4" }
libraries.win32 = { "libgconf-2.dll" }

include_dirs = { "gconf/2" }

includes = {}
includes.all = {
    "<gconf/gconf.h>",
}

defs = {}
defs.all = {
    "#define GCONF_DISABLE_DEPRECATED 1",
}

linklist = {
    "gconf_engine_ref",
    "gconf_engine_unref",
}

function_flags = {
    gconf_engine_get_default = NOINCREF,
    gconf_value_get_schema = CONST_OBJECT,
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"gconf_"',
    prefix_constant = '"GCONF_"',
    prefix_type = '"GConf"',
    prefix_func_remap = 'gconf_func_remap',
    depends = '"glib\\0"',
}

