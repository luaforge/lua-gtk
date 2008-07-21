name="Atk"
pkg_config_name="atk"
--STOP--

libraries = {}
libraries.linux = { "/usr/lib/libatk-1.0.so" }
libraries.win32 = { "libatk-1.0-0.dll" }

include_dirs = { "atk-1.0" }

includes = {}
includes.all = {
	"<atk/atk.h>",
	"<atk/atk-enum-types.h>",
}

