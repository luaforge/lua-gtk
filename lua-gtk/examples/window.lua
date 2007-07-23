#! /usr/bin/env lua

-- The simplest possible Lua-Gtk application.

require "gtk"

gtk.init(nil, nil)
win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
win:connect('destroy', function() gtk.main_quit() end)
win:set_title("Demo Program")
win:show()
gtk.main()

