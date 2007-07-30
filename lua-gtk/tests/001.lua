#! /usr/bin/lua
require "gtk"
gtk.init(nil, nil)

-- test that arbitrary values can be stored in a widget.

win = gtk.window_new(0)
win._foo = 1
assert(win._foo == 1)

