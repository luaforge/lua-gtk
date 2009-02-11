#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- XXX if the order is first gtkspell, then gtk, nothing works.
require "gtk"
require "gtkspell"


win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
win:set_title("Spell Checking Demo")
win:set_default_size(500, 300)
win:connect('delete-event', gtk.main_quit)

scroll = gtk.scrolled_window_new(nil, nil)
scroll:set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
win:add(scroll)

view = gtk.text_view_new()
view:set_wrap_mode(gtk.WRAP_WORD_CHAR)
scroll:add(view)

spell, err = gtkspell.new_attach(view, "en", gnome.NIL)
if not spell then
	print(err)
	os.exit(1)
end

win:show_all()
gtk.main()


