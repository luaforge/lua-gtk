name="GIO"
pkg_config_name="gio-2.0"
--STOP--

libraries = {}
libraries.linux = { "/usr/lib/libgio-2.0.so" }
libraries.win32 = { "libgio-2.0-0.dll" }

include_dirs = { "gio" }

includes = {}
includes.all = {
	"<gio/gio.h>",
}
