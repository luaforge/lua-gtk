-- vim:sw=4:sts=4

name = "Cairo"
pkg_config_name = "cairo"

include_dirs = { "cairo" }

libraries = {}
libraries.linux = { "/usr/lib/libcairo.so.2" }
libraries.win32 = { "libcairo-2.dll" }

includes = {}
includes.all = {
    "<cairo.h>",
}

function_flags = {
    cairo_status_to_string = CONST_CHAR_PTR,
    cairo_version_string = CONST_CHAR_PTR,
}

moddep = {
    "glib",
}

-- extra settings for the module_info structure
module_info = {

    prefix_func = '"cairo_"',
    prefix_constant = '"CAIRO_"',
    prefix_type = '"cairo_"',
    depends = '""',
}

