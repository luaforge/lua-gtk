
require "gtk"

gtk.init(16)

w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
layout = w:create_pango_layout("Demo Message")

