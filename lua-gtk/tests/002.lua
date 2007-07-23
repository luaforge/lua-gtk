#! /usr/bin/lua
require "gtk2"
gtk.init(nil, nil)

-- test access to widget functions
win = gtk.window_new(0)
win:set_title("Hello")


