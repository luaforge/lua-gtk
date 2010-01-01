#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate the use of libgtkhtml-3 including the loading of images
-- and basic editing.
--

require "gtk"
require "gtkhtml3"

local my_dir

-- When a URL is found, this callback should provide the data for this URL
-- by writing it into the provided stream.
function on_url_requested(gtkhtml, url, stream)

    local f, data
    f = io.open(my_dir .. url)

    stream = gnome.cast(stream, "GtkHTMLStream")
    if f then
	data = f:read"*a"
	f:close()
	gtkhtml:write(stream, data, #data)
    else
	print("on_url_requested: Failed to read from file", my_dir .. url)
    end

    gtkhtml:gtk_html_end(stream, gtkhtml3.GTK_HTML_STREAM_OK)
end

function build_gui()
    local w, doc, stream, view, s

    w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    w:set_title('GtkHTML Demo')

    -- create an HtmlDocument.  Note that the function "new" would be the
    -- one provided by LuaGnome to allocate a structure, so the full function
    -- name has to be used instead.
    doc = gtkhtml3.gtk_html_new()
    w:add(doc)
    doc:connect('url-requested', on_url_requested)
    -- doc:enable_debug(true)

    -- embedded images seem not to work.  I haven't found any documentation
    -- on how to do this.

    s = [[<html><body>
    <p>Hello, <span style="color:#f00;">World!</span></p>
    <img src="demo1.png" />
    </body></html>
]]

    -- The HTML text can be transmitted via the streaming interface, or by
    -- the convenience function load_from_string.
    if true then
	stream = doc:begin()
	doc:write(stream, s, #s)
	-- Again, just "end" as function name can't be used, because it is a
	-- reserved Lua statement.
	doc:gtk_html_end(stream, gtkhtml3.GTK_HTML_STREAM_OK)
    else
	doc:load_from_string(s, #s)
    end

    -- The big advantage of libgtkhtml3 over libgtkhtml2 is editing.  So,
    -- show this.
    doc:set_editable(true)
    doc:set_inline_spelling(true)

    w:show_all()
end

my_dir = string.gsub(arg[0], "[^/]*$", "")
build_gui()
gtk.main()

