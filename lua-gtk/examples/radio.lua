#! /usr/bin/env lua
-- vim:sw=4:sts=4
require "gtk"

-- Example how to use GtkRadioButton, and shows some GSList functions, too.

function build_gui()
    local w, vbox, grp, r, b

    w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    vbox = gtk.vbox_new(true, 2)
    w:add(vbox)

    -- a GSList that contains all radio buttons of a group.
    grp = nil

    -- Create a few radio buttons.  The Lua proxy object gets the
    -- attribute "_id" set, an arbitrary key.
    for id, lbl in ipairs { "One", "Two", "Three", "Four" } do
	r = gtk.radio_button_new_with_label(grp, lbl)
	r._id = id
	vbox:pack_start_defaults(r)
	-- get the start of the list.
	grp = r:get_group()
    end

    -- Add a button that, when clicked, shows which radio button is selected,
    -- then exits.
    b = gtk.button_new_from_stock(gtk.GTK_STOCK_OK)
    b:connect('clicked', function()
	-- the custom function returns 0 if found, 1 otherwise.
	item = grp:find_custom(nil, function(a, the_nil)
	    return a:get_active() and 0 or 1
	end)
	if item then
	    r = item.data:cast("GtkRadioButton")
	    print("You selected", r._id)
	end
	gtk.main_quit()
    end)

    vbox:pack_start_defaults(b)

    w:show_all()
end


build_gui()
gtk.main()

