#! /usr/bin/env lua
require "gtk"

gtk.set_debug_flags("valgrind")
w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
layout = w:create_pango_layout("Demo Message")

