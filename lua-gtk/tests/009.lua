#! /usr/bin/env lua
require "gtk"
require "pango"

-- gtk.set_debug_flags("valgrind")
w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
layout = w:create_pango_layout("Demo Message")

