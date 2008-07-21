name="GtkSourceView"
pkg_config_name="gtksourceview-2.0"
--STOP--

libraries = {}
libraries.linux = { "/usr/lib/libgtksourceview-2.0.so" }
libraries.win32 = { "libgtksourceview-2.0-0.dll" }

include_dirs = { "gtksourceview-2.0" }

includes = {}
includes.all = {
	"<gtksourceview/gtksourceview.h>",
	"<gtksourceview/gtksourcelanguagemanager.h>",
	"<gtksourceview/gtksourcestyleschememanager.h>",
}



