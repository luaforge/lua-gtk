#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Same example as request.lua, but this time use a Glade XML file to create
-- the interface.
-- Copyright (C) 2007 Wolfgang Oertl
--

require "gtk"
require "gtk.glade"
require "gtk.strict"
require "gtk.http_co"

local download_running = false
local statusbar, statusbar_ctx, result_txt

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
    if ev == 'done' then
	download_running = false
	set_status("Done, got " .. #arg.sink_data .. " bytes.")
	local buf = result_txt:get_buffer()
	local buf2, read, written, error = gtk.g_convert(arg.sink_data,
	    -1, "utf8", "latin1", nil, nil, nil)
	buf:set_text(buf2, #buf2)
	return
    elseif ev == 'error' then
	download_running = 0
	progress_label:set_text("Error: " .. data2)
    end
end

function start_download(btn, entry)
    if download_running then
	print "Download already running."
	return
    end

    local s = entry:get_text()
    if s == "" then
	set_status "Please enter an URL"
	return
    end

    if s:match("^http://") then s = s:sub(8) end

    local host, path = s:match("^([^/]+)(.*)$")
    if not host then return end
    if path == "" then path = "/" end

    set_status("Downloading " .. host .. path)

    download_running = true
    gtk.http_co.request_co{ host = host, uri = path,
	callback = download_callback }
	
end

function build_gui()
    local fname, tree, widgets

    fname = arg[1] or string.gsub(arg[0], "%.lua", ".glade")
    tree = gtk.glade.read(fname)
    widgets = gtk.glade.create(tree, "window1")

    statusbar = widgets.statusbar1
    statusbar_ctx = statusbar:get_context_id("progress")
    statusbar:push(statusbar_ctx, "idle")

    result_txt = widgets.result_txt
end

-- Main
build_gui()
gtk.main()

