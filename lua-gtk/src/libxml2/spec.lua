-- vim:sw=4:sts=4

name = "libxml2"
pkg_config_name = "libxml-2.0"

libraries = {}
libraries.linux = { "/usr/lib/libxml2.so" }
libraries.win32 = { "libxml2.dll" }

include_dirs = { "libxml2" }

includes = {}
includes.all = {
    "<libxml/SAX2.h>",
    "<libxml/HTMLparser.h>",
    "<libxml/HTMLtree.h>",
    "<libxml/xmlreader.h>",
    "<libxml/xmlwriter.h>",
    -- maybe more; there is no "include all" file
}

-- build time dependencies on other modules
moddep = {
    "glib",
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"xml"',
    prefix_constant = '"XML_"',
    prefix_type = '"xml"',
    depends = '""',
}

