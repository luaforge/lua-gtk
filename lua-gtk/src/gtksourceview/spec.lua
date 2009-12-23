-- vim:sw=4:sts=4

name = "GtkSourceView"
pkg_config_name = "gtksourceview-2.0"

libraries = {
    linux = { "/usr/lib/libgtksourceview-2.0.so.0" },
    win32 = { "libgtksourceview-2.0-0.dll" },
}

include_dirs = { "gtksourceview-2.0" }

includes = {}
includes.all = {
    "<gtksourceview/gtksourceview.h>",
    "<gtksourceview/gtksourcelanguagemanager.h>",
    "<gtksourceview/gtksourcestyleschememanager.h>",
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"gtk_source_"',
    prefix_constant = '"GTK_SOURCE_"',
    prefix_type = '"GtkSource"',
    depends = '"gtk\\0"',
}

