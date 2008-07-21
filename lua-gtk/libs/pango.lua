name="Pango"
pkg_config_name="pango"
--STOP--

libraries = {}
libraries.win32 = { "libpango-1.0-0.dll" }

include_dirs = { "pango-1.0" }

