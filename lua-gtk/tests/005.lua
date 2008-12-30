#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Test coroutines with sleeping and asynchronous HTTP download, and
-- idle callbacks.
--

require "gtk"
require "gtk.socket_co"
require "gtk.watches"

lbl = nil
buf = nil

function http_download()
    local val, msg, sock, gio, condition
    local host = "www.google.at"

    -- This call blocks, unfortunately, during the DNS lookup.  No GUI updates
    -- during this time.
    local s = "Connecting..."
    buf:set_text(s, #s)
    gio, msg = gtk.socket_co.connect(host, 80, false)
    if not gio then return gio, msg end

    s = "Connected!"
    buf:set_text(s, #s)
    sock = msg

    gtk.socket_co.write_chars(gio, "GET / HTTP/1.1\nHost: " .. host
	.. "\nConnection: close\n\n")

    -- set up conversion to utf8
    conv = glib.iconv_open("UTF8", "latin1")

    -- read the response in many small pieces, with small delays in between.
    s = ""
    remainder = ""

    while true do
	val, msg = gtk.socket_co.read_chars(gio, 50)
	if not val then break end

	rc, obuf, remainder = glib.iconv(conv, remainder .. val)
	s = s .. obuf
	buf:set_text(s, #s)

	-- slow it down somewhat
	-- coroutine.yield("sleep", 1)
    end 
    print("end", msg)
end

-- first, wait for 1.5 seconds, then download something, and exit.
function background_task()
    local cnt = 15

    for i = 1, cnt do
	local s = string.format("Sleeping... %d/%d", i, cnt)
	buf:set_text(s, #s)
	coroutine.yield("sleep", 100)
    end
    http_download()
    coroutine.yield("sleep", 1500)
    gtk.main_quit()
end

-- create a minimal GUI: a window with a label in it.
function init_gui()
    local w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:set_title("HTTP GET Test")
    w:connect('destroy', gtk.main_quit)
    w:set_default_size(300, 300)
    local sw = gtk.scrolled_window_new(nil, nil)
    w:add(sw)
    local lbl = gtk.text_view_new()
    buf = lbl:get_buffer()
    sw:add(lbl)
    w:show_all()
end

-- return true if to continue calling this idle function; false otherwise.
idle = gnome.closure(function(tbl)
    print("idle", tbl[1])
    tbl[1] = tbl[1] + 1
    if tbl[1] < 10 then return true end
    tbl:destroy()
    return false
end)

init_gui()
gtk.watches.start_watch(background_task)

-- This function expects a "void*" argument, which will be passed to the
-- callback.  lua-gtk allows nil, widgets and any other data type to be
-- used.
glib.idle_add(idle, {1, 2, 3})
gtk.main()

collectgarbage "collect"
assert(gnome.get_vwrapper_count() == 0)

