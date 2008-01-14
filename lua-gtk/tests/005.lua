#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Test coroutines with sleeping and asynchronous HTTP download, and
-- idle callbacks.
--

require "gtk"
require "gtk.socket_co"
require "gtk.watches"

lbl = nil

function http_download()
    local val, msg, sock, gio, condition

    -- This call blocks, unfortunately, during the DNS lookup.  No GUI updates
    -- during this time.
    lbl:set_text("Connecting...")
    gio, msg = gtk.socket_co.connect("www.google.com", 80, false)
    if not gio then return gio, msg end

    lbl:set_text("Connected!");
    sock = msg

    gtk.socket_co.write_chars(gio, "GET / HTTP/1.1\nConnection:close\n\n")

    -- read the response in many small pieces, with small delays in between.
    while true do
	val, msg = gtk.socket_co.read_chars(gio, 50)
	if not val then break end
	-- print("got data with length", #val)
	lbl:set_text(lbl:get_text() .. val)
	-- coroutine.yield("sleep", 100)
    end

    print("end", msg)
end

-- first, wait for 1.5 seconds, then download something, and exit.
function background_task()
    local cnt = 15

    for i = 1, cnt do
	lbl:set_text(string.format("Sleeping... %d/%d", i, cnt))
	coroutine.yield("sleep", 100)
    end
    http_download()
    coroutine.yield("sleep", 500)
    gtk.main_quit()
end

-- create a minimal GUI: a window with a label in it.
function init_gui()
    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:connect('destroy', function() gtk.main_quit() end)
    lbl = gtk.label_new("")
    w:add(lbl)
    w:show_all()
end

-- return true if to continue calling this idle function; false otherwise.
function idle(a, b, c)
    print("idle", a[1], b, c)
    a[1] = a[1] + 1
    return a[1] < 10
end

gtk.init()
init_gui()
gtk.watches.start_watch(background_task)

gtk.g_idle_add(idle, {1}, 2, 3)
gtk.main()

