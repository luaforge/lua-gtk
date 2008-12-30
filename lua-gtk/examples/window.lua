#! /usr/bin/env lua

-- The simplest possible Lua-Gtk application.

require "gtk"
require "glib"

win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
t = getmetatable(win)
win:connect('destroy', gtk.main_quit)
win:set_title("Demo Program")
win:show()
gtk.main()

