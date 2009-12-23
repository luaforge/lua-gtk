-- vim:sw=4:sts=4
--
-- Binding to the Gtk+ OpenGL Extension (libgtkglext1)
--
-- Homepage: http://gtkglext.sourcefourge.net/
-- Documentation: http://gtkglext.sourceforge.net/reference/gtkglext/
--

name = "GtkGLExt"
pkg_config_name = "gtkglext-1.0"
required = false

libraries = {
    linux = { "/usr/lib/libgtkglext-x11-1.0.so.0" },
    win32 = { "?" },
}

include_dirs = { "gtkglext-1.0" }

-- import the constants from header files
local p = "/usr/include/gtkglext-1.0"
headers = {
    { p .. "/gdk/gdkglconfig.h", false },
    { p .. "/gdk/gdkgldebug.h", false },
    { p .. "/gdk/gdkglversion.h", false },
    { p .. "/gdk/gdkgltokens.h", true },
    { p .. "/gdk/glext/glext-extra.h", false },
    { p .. "/gdk/glext/glext.h", false },
    { p .. "/gdk/glext/glxext.h", false },
    { p .. "/gtk/gtkgldebug.h", false },
}

includes = { all = { "<gdk/gdkgl.h>", "<gtk/gtkgl.h>" } }

aliases = {
    -- XXX alias is not enough. must cast to GdkGLDrawable.
    gtk_widget_get_gl_drawable = "gtk_widget_get_gl_window",
}


-- Defines for make-xml.lua

-- entry: function name = { [arg_nr]=flags, ... }
-- arg_nr start with 1 for the return value.  If only the return value is
-- specified, can be just "flags".
function_flags = {
}

-- flags that can be used by name in the function_flags table
flag_table = {
}



-- extra types to include even though they are not used in functions
-- or structures:
include_types = {
}

-- Functions used from the dynamic libraries (GLib, GDK, Gtk)
linklist = {
    "gtk_gl_init",
}

-- extra settings for the module_info structure
-- we have multiple namespaces in this module with different prefixes:
--
--   func gtk_widget_, var gtkglext_, const GTKGLEXT_
--   func gdk_gl_, var gdkglext_, const GDKGLEXT_
--
module_info = {
--    allocate_object = "gtk_allocate_object",
    call_hook = "gtkglext_call_hook",
    prefix_func = '""',
    prefix_constant = '""',
    prefix_type = '""',
    depends = '"gtk\\0"',
--    overrides = 'gtk_overrides',
}


