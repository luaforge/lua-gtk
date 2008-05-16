#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Demonstrate the use of a gdk_x11_xxx function; not portable to Windows!
-- see also http://www.daa.com.au/pipermail/pygtk/2005-March/009720.html

require 'gtk'

function build_gui()
    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:show()
    local xid = gtk.gdk_x11_drawable_get_xid(w.window)
    local lbl = gtk.label_new("This window's XID is " .. xid)
    w:add(lbl)
    w:set_title("XID example")
    w:connect("delete-event", gtk.main_quit)
    w:show_all()
end

build_gui()
gtk.main()

