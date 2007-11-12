#! /usr/bin/lua
-- vim:sw=4:sts=4

require "gtk"
require "gtk.socket_co"
require "gtk.watches"

function get_time(gio, condition)
    local val, msg, sock

    gio, msg = gtk.socket_co.connect("www.google.com", 80, false)
    -- print("connect returned", gio, msg)
    if not gio then return gio, msg end
    print "connected."
    sock = msg

    gtk.socket_co.write_chars(gio, "GET / HTTP/1.1\nConnection:close\n\n")

    while true do
	val, msg = gtk.socket_co.read_chars(gio, 5000)
	if not val then break end
	print("got the data", #val)
    end

    print("end", msg)
    gtk.main_quit()
end

function init_gui()
    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:connect('destroy', function() gtk.main_quit() end)
    w:show()
end

gtk.init()
init_gui()
local thread = coroutine.create(get_time)
gtk.watches.start_watch(thread)
gtk.main()

