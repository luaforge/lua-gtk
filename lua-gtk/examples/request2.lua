#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Same example as request.lua, but this time use a Glade XML file to create
-- the interface.
-- Copyright (C) 2007 Wolfgang Oertl
--

require "gtk"
require "gtk.strict"
require "gtk.http_co"
require "gtkhtml"

local download_running = false
local statusbar, statusbar_ctx, view

function set_status(s)
    statusbar:pop(statusbar_ctx)
    statusbar:push(statusbar_ctx, s)
end

output_text = {
    create = function(self)
	return gtk.text_view_new()
    end,
    open = function(self)
	local buf = view:get_buffer()
	buf:clear()
	self.buf = {}
    end,
    add = function(self, s)
	self.buf[#self.buf + 1] = s
    end,
    close = function(self)
	local buf = view:get_buffer()
	local s = table.concat(self.buf, "")
	local buf2, read, written, error = gtk.g_convert(s,
	    -1, "utf8", "latin1", nil, nil, nil)
	buf:set_text(buf2, #buf2)
	self.buf = nil
    end,
}

output_html = {
    create = function(self)
	local view = gtkhtml.view_new()
	local doc = gtkhtml.document_new()
	view:set_document(doc)
	return view
    end,
    open = function(self)
	htmldoc = gtkhtml.document_new()
	htmldoc:open_stream "text/html"
	view:set_document(htmldoc)
    end,
    add = function(self, s)
	htmldoc:write_stream(s, #s)
    end,
    done = function(self)
	print "DONE"
	htmldoc:close_stream()
    end,
}


---
-- This callback is invoked on each event during the download.
--
-- arg: the table passed to request_co
-- ev: the event; may be "progress", "headers", "done", "error".
-- data1..3: depends on the event.
--
function download_callback(arg, ev, data1, data2, data3)
    if ev == 'done' then
	download_running = false
	set_status("Done")
	output:done()
    elseif ev == 'error' then
	download_running = 0
	set_status("Error: " .. data2)
    elseif ev == 'headers' then
	output:open()
    end
end

function download_sink(arg, buf)
    if buf then
	output:add(buf)
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
	callback = download_callback,
	sink = download_sink }
	
end

function build_gui()
    local fname, builder, rc, err, sw

    fname = arg[1] or string.gsub(arg[0], "%.lua", ".ui")
    builder = gtk.builder_new()
    rc, err = builder:add_from_file(fname, nil)
    if rc == 0 then error(err.message) end

    builder:connect_signals_full(_G)

    -- statusbar
    statusbar = builder:get_object "statusbar1"
    statusbar_ctx = statusbar:get_context_id("progress")
    statusbar:push(statusbar_ctx, "idle")

    -- result display
    sw = builder:get_object "scrolledwindow1"
    view = output:create()
    sw:add(view)
    view:show()
end

-- Main
output = output_html
build_gui()
gtk.main()

