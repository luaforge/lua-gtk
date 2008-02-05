#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Example by Michael Kolodziejczyk

require "gtk"

win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
win:set_size_request(400, 300)
win:set_title("Clock")
win:connect('destroy', gtk.main_quit)

function onTimeout(lbl)
    lbl:set_text(os.date('%H:%M:%S'))
    return true
end

lbl = gtk.label_new('')
onTimeout(lbl)
timer = gtk.g_timeout_add(1000, onTimeout, lbl)

win:add(lbl)
win:show_all()
gtk.main()

