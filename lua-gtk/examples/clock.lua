#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Example by Michael Kolodziejczyk

require "gtk"

win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
win:set_size_request(400, 300)
win:set_title("Clock")
win:connect('destroy', gtk.main_quit)

function onTimeout(ar)
    local lbl = ar.lbl
    lbl:set_text(os.date('%H:%M:%S'))
    return true
end

lbl = gtk.label_new ""
onTimeoutClosure = gnome.closure(onTimeout)
onTimeoutArg = gnome.void_ptr{ lbl=lbl }
onTimeout(onTimeoutArg)
timer = glib.timeout_add(1000, onTimeoutClosure, onTimeoutArg)
collectgarbage "collect"

win:add(lbl)
win:show_all()
gtk.main()

onTimeoutClosure = nil
onTimeoutArg = nil
lbl = nil
win = nil
collectgarbage "collect"
print(gnome.get_vwrapper_count())


