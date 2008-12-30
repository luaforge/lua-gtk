#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

-- make a new object, get its class and directly call a class method.  This
-- might be useful in some cases?
s = gtk.vscale_new(nil)
cl = glib.object_get_class(s)
cl.grab_focus(s)
