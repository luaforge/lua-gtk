name="Gtk"
pkg_config_name="gtk+-2.0"
required=1
use_cflags=1
--STOP--

libraries = {}
libraries.linux = { "/usr/lib/libgtk-x11-2.0.so" }
libraries.win32 = { "libgtk-win32-2.0-0.dll",
	"libgdk-win32-2.0-0.dll",
	"libglib-2.0-0.dll",
	"libgobject-2.0-0.dll",
	"libgdk_pixbuf-2.0-0.dll",
}
include_dirs = { "gtk-2.0", "glib-2.0" }

includes = {}
includes.all = {
	"<gtk/gtk.h>",
	"<glib/gstdio.h>",
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
	"#undef __OPTIMIZE__",
	"#define GTK_DISABLE_DEPRECATED 1",
	"#define GDK_DISABLE_DEPRECATED 1",
	"#define GDK_PIXBUF_ENABLE_BACKEND 1",
}
defs.win32 = {
	"#define G_OS_WIN32",
	-- workaround for compilation error in gtk-2.0/gdk/gdk.h:189
	"#define __declspec(x)",
	"#define dllexport",
	"#define __GTK_DEBUG_H__",
}
defs.linux = {
	"#define G_STDIO_NO_WRAP_ON_UNIX",
}


