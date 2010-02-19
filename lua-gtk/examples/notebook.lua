#! /usr/bin/env lua

-- demonstrate a Notebook with two pages.

require "gtk"

function build_ui()
	local win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
	win:connect('delete-event', gtk.main_quit)
	win:set_title "Notebook test"
	win:set_default_size(450, 400)

	local note = gtk.notebook_new()
	note:connect('switch-page', on_switch_page)
	win:add(note)

	note:append_page(gtk.label_new"Page 1", gtk.label_new"Page 1")
	note:append_page(gtk.label_new"Page 2", gtk.label_new"Page 2")

	win:show_all()
	return win
end

function on_switch_page(note, page, page_nr)
	print("on_switch_page", note, page, page_nr)
end

local win = build_ui()
gtk.main()

