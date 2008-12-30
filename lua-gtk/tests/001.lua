#! /usr/bin/env lua
require "gtk"

-- test that arbitrary values can be stored in a widget.

win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
win._foo = 1
win._bar = "a string"
win._baz = { 1, 2, 3 }
assert(win._foo == 1)
assert(win._bar == "a string")
assert(win._baz[2] == 2)

