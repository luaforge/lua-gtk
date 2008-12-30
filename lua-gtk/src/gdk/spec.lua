-- vim:sw=4:sts=4

name = "GDK"
pkg_config_name = "gtk+-2.0"
required = true

libraries = {}
libraries.linux = { "/usr/lib/libgtk-x11-2.0.so" }
libraries.win32 = { "libgdk-win32-2.0-0.dll", "libgdk_pixbuf-2.0-0.dll" }

include_dirs = { "gtk-2.0/gdk", "gtk-2.0/gdk-pixbuf",
	"gtk-2.0/gdk-pixbuf-xlib" }

path_gdk = "/usr/include/gtk-2.0/gdk"

headers = {
    { path_gdk .. "/gdkkeysyms.h", true },
    { path_gdk .. "/gdkselection.h", false },
    { path_gdk .. "/gdktypes.h", false },
}

includes = {}
includes.all = {
    "<gdk/gdk.h>",
}
includes.linux = {
    "<gdk/gdkx.h>",
}

-- Defines for make-xml.lua

-- #undef __OPTIMIZE_: Avoid trouble with -O regarding __builtin_clzl.
-- Seems to have no other side effects (XML file exactly the same).
-- Suggested by Michael Kolodziejczyk on 2007-10-23

defs = {}
defs.all = {
    "#define GTK_DISABLE_DEPRECATED 1",
    "#define GDK_DISABLE_DEPRECATED 1",
    "#define GDK_PIXBUF_ENABLE_BACKEND 1",
}
defs.win32 = {
    --"#define G_OS_WIN32",
    -- workaround for compilation error in gtk-2.0/gdk/gdk.h:189
    "#define __declspec(x)",
    "#define dllexport",
    "#define __GTK_DEBUG_H__",
}
-- defs.linux = {
-- 	"#define G_STDIO_NO_WRAP_ON_UNIX",
-- }


-- List of types to include as native, even though they normally wouldn't.
-- When a module is written that provides that, it should be removed and
-- a dependency added on the new module.
native_types = {
    XID = true,
}

include_types = {
    "GdkDrawable",
    "GdkAtom",

    -- types that some GDK functions use.
    "Atom",
    "Colormap",
    "Display*",
    "GC",
    "XImage*",
    "Screen*",
    "Visual*",
    "VisualID",
    "Cursor",
    "Window",
    "XExtData*",

    "GdkAtom**",		-- gtk
    "GdkColor**",		-- gtk
    "GdkEventExpose*",		-- gtk
    "GdkEventKey*",		-- gtk
    "GdkEventKey*",		-- gtk
    "GdkImage**",		-- gtk
    "GdkPoint**",		-- gtk


}

function_flags = {
    -- not verified!
    gdk_drawable_get_display = CONST_OBJECT,		-- don't free retval
    gdk_atom_name = CHAR_PTR,
    gdk_color_to_string = CHAR_PTR,
    gdk_display_get_name = CONST_CHAR_PTR,
    gdk_get_display = CHAR_PTR,
    gdk_get_display_arg_name = CONST_CHAR_PTR,
    gdk_get_program_class = CONST_CHAR_PTR,
    gdk_keyval_name = CHAR_PTR,
    gdk_pixbuf_format_get_description = CHAR_PTR,
    gdk_pixbuf_format_get_license = CHAR_PTR,
    gdk_pixbuf_format_get_name = CHAR_PTR,
    gdk_pixbuf_get_option = CONST_CHAR_PTR,
    gdk_screen_make_display_name = CHAR_PTR,
    gdk_set_locale = CHAR_PTR,
    gdk_utf8_to_string_target = CHAR_PTR,
    gdk_wcstombs = CHAR_PTR,
    gdk_display_get_default_screen = CONST_OBJECT,	-- don't free retval
}

-- Gdk has a few functions named gdk_draw_xxx, which would logically be named
-- gdk_drawable_draw_xxx, as they operate on the class GdkDrawable.  Add
-- aliases to make drawable:draw_arc() etc. possible.
aliases = {
  gdk_drawable_draw_arc = "gdk_draw_arc",
  gdk_drawable_draw_drawable = "gdk_draw_drawable",
  gdk_drawable_draw_glyphs = "gdk_draw_glyphs",
  gdk_drawable_draw_glyphs_transformed = "gdk_draw_glyphs_transformed",
  gdk_drawable_draw_gray_image = "gdk_draw_gray_image",
  gdk_drawable_draw_image = "gdk_draw_image",
  gdk_drawable_draw_indexed_image = "gdk_draw_indexed_image",
  gdk_drawable_draw_layout = "gdk_draw_layout",
  gdk_drawable_draw_layout_line = "gdk_draw_layout_line",
  gdk_drawable_draw_layout_line_with_colors = "gdk_draw_layout_line_with_colors",
  gdk_drawable_draw_layout_with_colors = "gdk_draw_layout_with_colors",
  gdk_drawable_draw_line = "gdk_draw_line",
  gdk_drawable_draw_lines = "gdk_draw_lines",
  gdk_drawable_draw_pixbuf = "gdk_draw_pixbuf",
  gdk_drawable_draw_point = "gdk_draw_point",
  gdk_drawable_draw_points = "gdk_draw_points",
  gdk_drawable_draw_polygon = "gdk_draw_polygon",
  gdk_drawable_draw_rectangle = "gdk_draw_rectangle",
  gdk_drawable_draw_rgb_32_image = "gdk_draw_rgb_32_image",
  gdk_drawable_draw_rgb_32_image_dithalign = "gdk_draw_rgb_32_image_dithalign",
  gdk_drawable_draw_rgb_image = "gdk_draw_rgb_image",
  gdk_drawable_draw_rgb_image_dithalign = "gdk_draw_rgb_image_dithalign",
  gdk_drawable_draw_segments = "gdk_draw_segments",
  gdk_drawable_draw_trapezoids = "gdk_draw_trapezoids",
}

linklist = {
    "g_free",
    "gdk_pixbuf_save_to_buffer",
    "gdk_init",
}

-- extra settings for the module_info structure
module_info = {
    call_hook = "gdk_call_hook",
    prefix_func = '"gdk_"',
    prefix_constant = '"GDK_"',
    prefix_type = '"Gdk"',
    depends = '"glib\\0"',
    overrides = 'gdk_overrides',
}

