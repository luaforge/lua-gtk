name = "GtkHTML"
pkg_config_name = "libgtkhtml-2.0"

libraries = {}
libraries.linux = { "/usr/lib/libgtkhtml-2.so" }

-- Note: this library is not available from the precompiled binaries,
-- see script/download-gtk-win.lua.
libraries.win32 = { "libgtkhtml-2.0-0.dll" }

include_dirs = { "gtkhtml-2.0" }

includes = {}
includes.all = {
	"<libgtkhtml/gtkhtml.h>"
}

-- extra settings for the module_info structure
module_info = {


    prefix_func = '"html_"',
    prefix_constant = '""',
    prefix_type = '"Html"',
    depends = '""',
}

