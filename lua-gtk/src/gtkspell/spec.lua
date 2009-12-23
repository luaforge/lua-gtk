-- vim:sw=4:sts=4

name = "gtkspell"
pkg_config_name = "gtkspell-2.0"

libraries = {
    linux = { "/usr/lib/libgtkspell.so.0" },
    win32 = { "libgtkspell.dll" },
}

include_dirs = { "gtkspell-2.0" }

includes = {}
includes.all = {
    "<gtk/gtk.h>",
    "<gtkspell/gtkspell.h>",
}

-- build time dependencies on other modules
--moddep = {
--    "glib",
--}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"gtkspell_"',
    prefix_constant = '"GTKSPELL_"',
    prefix_type = '"GtkSpell"',
    depends = '""',
}

