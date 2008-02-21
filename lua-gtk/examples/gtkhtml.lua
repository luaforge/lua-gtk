#! /usr/bin/env lua
-- vim:sw=4:sts=4
require "gtk"

-- Demonstrate the use of libgtkhtml-2.0

function build_gui()
    w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    w:set_title('GtkHTML Demo')

    -- create a HtmlDocument
    doc = gtk.html_document_new()
    doc:open_stream("text/html")
    s = "<html><body><p>Hello, World!</p></body></html>"
    doc:write_stream(s, #s)
    doc:close_stream()

    -- create a HtmlView and set the document; note that it segfaults
    -- if no document is set and the mouse leaves the widget.
    view = gtk.html_view_new()
    view:set_document(doc)

    w:add(view)

    w:show_all()
end


build_gui()
gtk.main()

