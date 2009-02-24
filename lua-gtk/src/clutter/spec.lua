-- vim:sw=4:sts=4

name = "Clutter"
pkg_config_name = "clutter-0.8"

include_dirs = { "clutter" }

libraries = {}
libraries.linux = { "/usr/lib/libclutter-glx-0.8.so" }
libraries.win32 = { "libclutter-glx-0.8.dll" }

includes = {}
includes.all = {
    "<clutter/clutter.h>",
    "<clutter/glx/clutter-glx.h>",
    "<clutter/x11/clutter-x11.h>",
    "<clutter/json/json-glib.h>",
    "<clutter/json/json-marshal.h>",
    "<cogl/cogl.h>",
}

function_flags = {
    clutter_status_to_string = CONST_CHAR_PTR,
    clutter_version_string = CONST_CHAR_PTR,
}

moddep = {
    "glib",
}

-- extra settings for the module_info structure
module_info = {

    prefix_func = '"clutter_"',
    prefix_constant = '"CLUTTER_"',
    prefix_type = '"clutter_"',
    depends = '""',
}

