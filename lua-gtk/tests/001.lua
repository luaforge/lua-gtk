#! /usr/bin/env lua
require "gtk"

-- test that arbitrary values can be stored in a widget.

win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
win._foo = 1
assert(win._foo == 1)

