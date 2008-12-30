name = "GIO"
pkg_config_name = "gio-2.0"

libraries = {}
libraries.linux = { "/usr/lib/libgio-2.0.so" }
libraries.win32 = { "libgio-2.0-0.dll" }

include_dirs = { "gio" }

includes = {}
includes.all = {
	"<gio/gio.h>",
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"g_"',
    prefix_constant = '"G_"',
    prefix_type = '"G"',
    depends = '"glib\\0"',
}

