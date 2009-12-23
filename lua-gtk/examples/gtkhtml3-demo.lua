#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate the use of libgtkhtml-3
--

require "gtk"
require "gtkhtml3"

function build_gui()
    local w, doc, stream, view, s

    w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    w:set_title('GtkHTML Demo')

    -- create an HtmlDocument
    doc = gtkhtml3.gtk_html_new()
    -- doc:enable_debug(true)

    stream = doc:begin()
    s = '<html><body><p>Hello, <span style="color:#f00;">World!</span></p></body></html>'
    doc:write(stream, s, #s)
    doc:gtk_html_end(stream, gtkhtml3.GTK_HTML_STREAM_OK)

    -- create a HtmlView and set the document; note that it segfaults
    -- if no document is set and the mouse leaves the widget.
--    view = gtkhtml3.view_new()
--    view:set_document(doc)

    w:add(doc)

    w:show_all()
end


build_gui()
gtk.main()

