#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- Fetch definitions fromt he Diccionario de la Lengua Española through a
-- simple GUI.  This is modeled after the gdrae utility written in Perl using
-- Perl-Gtk2, but this implementation uses gtkhtml.
--
-- TODO
--  - provide a progress bar
--  - handle clicking on links
--  - improve layout
--  - translate to Spanish!
--  - fix spurious errors at quit "html_stream_cancel: assertion `stream->cancel_func != NULL' failed".
--
-- by Wolfgang Oertl 2008
--

require "gtk"
require "gtk.http_co"
require "gtkhtml"

rae_host = "buscon.rae.es"
rae_path = "/draeI/SrvltGUIBusUsual?LEMA="

-- Just one download at a time.  Multiple requests can be running in 
-- parallel, but my simple GUI is just for one.
local download_running = 0
local result_buf, statusbar, statusbar_ctx, htmlview, htmldoc

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
	download_running = 0
	set_status("Done")
	htmldoc:close_stream()
    elseif ev == 'error' then
	download_running = 0
	set_status("Error: " .. data2)
    end
end

function download_sink(arg, buf)
    if buf then
	htmldoc:write_stream(buf, #buf)
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
	print "Please enter a search text"
	return
    end

    set_status("Fetching " .. s)

    download_running = 1
    htmldoc = gtkhtml.document_new()
    htmldoc:open_stream("text/html")
    htmlview:set_document(htmldoc)
    gtk.http_co.request_co{ host = rae_host, uri = rae_path .. s,
	callback = download_callback,
	sink = download_sink }
end


--
-- Build a simple GUI
--
function build_gui()

    local w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:set_title "Diccionario de la Real Academia Española"
    w:set_default_size(500, 400)
    w:connect('delete-event', gtk.main_quit)

    local vbox = gtk.vbox_new(false, 10)
    w:add(vbox)

    local sw = gtk.scrolled_window_new(nil, nil)
    sw:set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
    vbox:pack_start(sw, true, true, 10)

    local txt
    txt = gtkhtml.view_new()
    local doc = gtkhtml.document_new()
    txt:set_document(doc)
    htmlview = txt
    sw:add(txt)

    local hbox = gtk.hbox_new(false, 10)
    hbox:set_property('border-width', 10)
    vbox:pack_start(hbox, false, false, 10)

    local entry = gtk.entry_new()
    entry:set_activates_default(true)
    hbox:add(entry)

    -- button box with two buttons
    local btn = gtk.button_new_with_label("Start")
    btn:connect('clicked', function() start_download(entry) end)
    hbox:add(btn)
    btn.flags = btn.flags + gtk.CAN_DEFAULT
    btn:grab_default()

    btn = gtk.button_new_with_mnemonic("_Quit")
    btn:connect('clicked', gtk.main_quit)
    hbox:add(btn)

    -- status bar
    statusbar = gtk.statusbar_new()
    statusbar:set_has_resize_grip(true)
    statusbar_ctx = statusbar:get_context_id("progress")
    statusbar:push(statusbar_ctx, "idle")
    vbox:pack_start(statusbar, false, false, 0)

    w:show_all()
    entry:grab_focus()
end

--
-- Main
--
-- gtk.set_debug_flags("memory")
build_gui()
gtk.main()


