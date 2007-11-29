#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Test coroutines with sleeping and asynchronous HTTP download, and
-- idle callbacks.
--

require "gtk"
require "gtk.socket_co"
require "gtk.watches"

function http_download()
    local val, msg, sock, gio, condition

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
end

function get_time_wrap()
    coroutine.yield("sleep", 1000)
    http_download()
    gtk.main_quit()
    return nil, "finished"
end

function init_gui()
    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:connect('destroy', function() gtk.main_quit() end)
    w:show()
end

function idle(a, b, c)
    print("idle", a[1], b, c)
    a[1] = a[1] + 1
    return a[1] < 10
end

gtk.init()
init_gui()
local thread = coroutine.create(get_time_wrap)
gtk.watches.start_watch(thread)

gtk.g_idle_add(idle, {1}, 2, 3)
gtk.main()

