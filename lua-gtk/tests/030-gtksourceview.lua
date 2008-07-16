#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

if not pcall(function() return gtk.source_view_new end) then
    print "GtkSourceView not available, skipping"
    os.exit(0)
end

w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)

vbox = gtk.vbox_new(false, 10)
w:add(vbox)

sc = gtk.scrolled_window_new(nil, nil)
sc:set_policy(gtk.GTK_POLICY_AUTOMATIC, gtk.GTK_POLICY_AUTOMATIC)
vbox:pack_start(sc, true, true, 0)

-- create a GtkSourceView widget with Lua highlighting
manager = gtk.source_language_manager_get_default()
lang = manager:get_language("lua")
assert(lang)
buf = gtk.source_buffer_new_with_language(lang)
buf:set_highlight_syntax(true)
view = gtk.source_view_new_with_buffer(buf)
sc:add(view)

-- add a quit button (required for scripting the test)
btn = gtk.button_new_with_label "Quit"
btn:connect('clicked', gtk.main_quit)
vbox:pack_start(btn, false, true, 0)

-- read this source file as an example
f = io.open(arg[0])
text = f:read "*a"
f:close()
buf:set_text(text, #text)

w:set_default_size(400, 400)
w:show_all()
w:connect('delete-event', gtk.main_quit)
w:set_title("GtkSourceView Demo")
gtk.main()

