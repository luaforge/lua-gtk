-- vim:sw=4:sts=4
--
-- This is the module to provide bindings to libgtkhtml3, which should replace
-- libgtkthml2.  Unfortunately, it has a quite different API than the latter,
-- and doesn't support CSS (yet).  It's part of Evolution:
--
-- http://projects.gnome.org/evolution/
-- http://projects.gnome.org/evolution/git.shtml
--
-- Documentation is scarce.  You can look at the include files in
-- /usr/include/libgtkhtml-3.14/gtkhtml at best.
--

name = "GtkHTML"
lib_version = "3.14"
pkg_config_name = "libgtkhtml-" .. lib_version

libraries = {}
libraries.linux = { "/usr/lib/libgtkhtml-" .. lib_version .. ".so.19" }

-- Note: this library is not available from the precompiled binaries,
-- see script/download-gtk-win.lua.
libraries.win32 = { "libgtkhtml-2.0-0.dll" }

include_dirs = { "libgtkhtml-" .. lib_version }

includes = {}
includes.all = {
    "<gtkhtml/gtkhtml.h>"
}

function_flags = {
    gtk_html_begin = CONST_OBJECT,			-- don't free retval
    gtk_html_begin_full = CONST_OBJECT,
    gtk_html_begin_content = CONST_OBJECT,		-- DEPRECATED
}


-- extra settings for the module_info structure
module_info = {
    prefix_func = '"gtk_html_"',
    prefix_constant = '""',
    prefix_type = '"GtkHTML"',
    prefix_func_remap = 'gtkhtml3_func_remap',
    depends = '""',
}

