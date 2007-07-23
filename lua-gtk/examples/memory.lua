#! /usr/bin/env lua

-- exercise reference counting

require "gtk"

gtk.init(nil, nil)

-- Does this leak memory?  Apparently not.  Don't try this with window_new(),
-- as this is a special case (see documentation for GtkObject)
if true then
	for i = 1, 100 do
		btn = gtk.button_new_with_label("Hello")
	end
end
collectgarbage()

function myclick(btn)
	print("hello button ", btn)
	gtk.main_quit()
end

function build_ui()
	-- wait for user input so the memory can be examined
	local win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
	local btn = gtk.button_new_with_label("Close")
	win:add(btn)
	win:connect('destroy', function() gtk.main_quit() end)
	btn:connect('clicked', myclick)
	win:show_all()
end


build_ui()
gtk.main()

