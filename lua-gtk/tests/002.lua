#! /usr/bin/lua
require "gtk"
gtk.init(nil, nil)

-- test access to widget functions
win = gtk.window_new(0)
win:set_title("Hello")


