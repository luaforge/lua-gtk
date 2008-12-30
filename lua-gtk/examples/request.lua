#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Download a HTTP page in the background.  Enter an address into the input
-- field, then press Start.  While the download is running, the GUI is not
-- blocked.
--
-- by Wolfgang Oertl
--

require "gtk"
require "gtk.strict"
require "gtk.http_co"


-- Just one download at a time.  Multiple requests can be running in 
-- parallel, but my simple GUI is just for one.
local download_running = 0
local result_buf, statusbar, statusbar_ctx

function set_status(s)
    statusbar:pop(statusbar_ctx)
    statusbar:push(statusbar_ctx, s)
end

--
-- This callback is invoked on each event during the download.
--
-- arg: the table passed to request_co
-- ev: the event; may be "progress", "headers", "done", "error".
-- data1..3: depends on the event.
--
function download_callback(arg, ev, data1, data2, data3)
    -- print(ev, data1, data2, data3)
    if ev == 'done' then
	download_running = 0
	set_status("Done, got " .. #arg.sink_data .. " bytes.")
	local buf, read, written, err = glib.convert(arg.sink_data,
	    -1, "utf8", "latin1", nil, nil, nil)
	if err then
	    buf = err.message
	end
	result_buf:set_text(buf, #buf)
    elseif ev == 'error' then
	download_running = 0
	set_status("Error: " .. data2)
    end
end


--
-- Start the download of the given URL
--
function start_download(entry)
    if download_running == 1 then
	print "Download already running."
	return
    end

    local s = entry:get_text()
    if s == "" then
	print "Please enter an URL"
	return
    end

    if s:match("^http://") then s = s:sub(8) end

    local host, path = s:match("^([^/]+)(.*)$")
    if not host then return end
    if path == "" then path = "/" end

    set_status("Downloading " .. host .. path)

    download_running = 1
    gtk.http_co.request_co{ host = host, uri = path,
	callback = download_callback }
end


--
-- Build a simple GUI
--
function build_gui()

    local w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:set_title "HTTP Demo"
    w:set_default_size(500, 400)
    w:connect('destroy', function() gtk.main_quit() end)

    local vbox = gtk.vbox_new(false, 10)
--    vbox:set_property('border-width', 10)
    w:add(vbox)

    local sw = gtk.scrolled_window_new(nil, nil)
    vbox:pack_start(sw, true, true, 10)

    local txt = gtk.text_view_new()
    txt:set_property('editable', false)
    txt:set_property('cursor-visible', false)
    txt:set_property('wrap-mode', gtk.WRAP_WORD)
    sw:add(txt)
    result_buf = txt:get_buffer()

    local hbox = gtk.hbox_new(false, 10)
    hbox:set_property('border-width', 10)
    vbox:pack_start(hbox, false, false, 10)

    local entry = gtk.entry_new()
    entry:set_text("www.google.at")
    entry:set_activates_default(true)
    hbox:add(entry)

    -- button box with two buttons
    local btn = gtk.button_new_with_label("Start")
    btn:connect('clicked', function() start_download(entry) end)
    hbox:add(btn)
    btn.flags = btn.flags + gtk.CAN_DEFAULT
    btn:grab_default()

    btn = gtk.button_new_with_mnemonic("_Quit")
    btn:connect('clicked', function() gtk.main_quit() end)
    hbox:add(btn)

    -- status bar
    statusbar = gtk.statusbar_new()
    statusbar:set_has_resize_grip(true)
    statusbar_ctx = statusbar:get_context_id("progress")
    statusbar:push(statusbar_ctx, "idle")
    vbox:pack_start(statusbar, false, false, 0)

    w:show_all()
end

--
-- Main
--
-- gtk.set_debug_flags("memory")
build_gui()
gtk.main()

