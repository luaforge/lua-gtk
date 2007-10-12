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
local progress_label

--
-- This callback is invoked on each event during the download.
--
-- arg: the table passed to request_co
-- ev: the event; may be "progress", "headers", "done", "error".
-- data1..3: depends on the event.
--
function download_callback(arg, ev, data1, data2, data3)
    print(ev, data1, data2, data3)
    if ev == 'done' then
	download_running = 0
	progress_label:set_text("Done, got " .. #arg.sink_data .. " bytes.")
	return
    elseif ev == 'error' then
	download_running = 0
	progress_label:set_text("Error: " .. data2)
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

    progress_label:set_text("Downloading " .. host .. path)

    download_running = 1
    gtk.http_co.request_co{ host = host, uri = path,
	callback = download_callback }
end


--
-- Build a simple GUI
--
function build_gui()

    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:set_title "HTTP Demo"
    w:connect('destroy', function() gtk.main_quit() end)

    local vbox = gtk.vbox_new(false, 10)
    vbox:set_property('border-width', 10)
    w:add(vbox)

    local entry = gtk.entry_new()
    entry:set_text("www.google.at")
    entry:set_activates_default(true)
    vbox:add(entry)

    progress_label = gtk.label_new("idle")
    vbox:add(progress_label)

    -- button box with two buttons
    local hbox = gtk.hbox_new(true, 10)
    vbox:add(hbox)

    local btn = gtk.button_new_with_label("Start")
    btn:connect('clicked', function() start_download(entry) end)
    hbox:add(btn)
    btn.flags = btn.flags + gtk.GTK_CAN_DEFAULT
    btn:grab_default()

    btn = gtk.button_new_with_mnemonic("_Quit")
    btn:connect('clicked', function() gtk.main_quit() end)
    hbox:add(btn)

    w:show_all()
end

--
-- Main
--
gtk.init()
build_gui()
gtk.main()

