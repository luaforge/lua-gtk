#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

if not pcall(require, "gtksourceview") then
    print "GtkSourceView not available, skipping"
    os.exit(0)
end

w = gtk.window_new(gtk.WINDOW_TOPLEVEL)

vbox = gtk.vbox_new(false, 10)
w:add(vbox)

sc = gtk.scrolled_window_new(nil, nil)
sc:set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
vbox:pack_start(sc, true, true, 0)

-- create a GtkSourceView widget with Lua highlighting
manager = gtksourceview.language_manager_get_default()
lang = manager:get_language("lua")
assert(lang)
buf = gtksourceview.buffer_new_with_language(lang)
buf:set_highlight_syntax(true)
view = gtksourceview.view_new_with_buffer(buf)
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
w:connect('delete-event', gtk.main_quit)
w:set_title("GtkSourceView Demo")
w:show_all()
gtk.main()

