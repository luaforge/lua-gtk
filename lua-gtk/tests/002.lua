#! /usr/bin/lua
require "gtk"
gtk.init(nil, nil)

-- test access to widget functions
win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
win:set_title("Hello")


