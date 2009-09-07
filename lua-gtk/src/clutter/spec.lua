-- vim:sw=4:sts=4

name = "Clutter"
pkg_config_name = "clutter-1.0"

include_dirs = { "clutter-1.0" }

libraries = {}
libraries.linux = { "/usr/lib/libclutter-glx-1.0.so",
    "/usr/lib/libclutter-cairo-1.0.so" }
libraries.win32 = { "libclutter-glx-1.0.dll" }

includes = {}
includes.all = {
    "<clutter/clutter.h>",
    "<clutter/glx/clutter-glx.h>",
    "<clutter/x11/clutter-x11.h>",
    "<clutter/json/json-glib.h>",
    "<clutter/json/json-marshal.h>",
    "<clutter-cairo/clutter-cairo.h>",	    -- optional
--    "<clutter-gtk/gtk-clutter-embed.h>",    -- optional
--    "<clutter-gtk/gtk-clutter-util.h>",	    -- optional
    "<cogl/cogl.h>",			    -- optional
}

function_flags = {
    clutter_status_to_string = CONST_CHAR_PTR,
    clutter_version_string = CONST_CHAR_PTR,
    clutter_stage_get_default = CONST_OBJECT,
    clutter_entry_get_layout = CONST_OBJECT,
}

linklist = {
    "g_malloc",
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"clutter_"',
    prefix_constant = '"CLUTTER_"',
    prefix_type = '"Clutter"',
    depends = '"glib\\0"',
    overrides = "clutter_overrides",
}

