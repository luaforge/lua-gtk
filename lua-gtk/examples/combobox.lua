#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- demonstration of a tree view

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

function MainWin.new()

    local self = {}
    setmetatable(self, MainWin)

    -- create visible widgets
    self.w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    self.w:connect('destroy', gtk.main_quit)
    self.w:set_default_size(200, 50)
    self.w:set_title("ComboBox Demo")

    local vbox = gtk.vbox_new(false, 3)
    self.w:add(vbox)

    self.combobox = gtk.combo_box_new()
    vbox:add(self.combobox)

    -- create store
    self.store = gtk.tree_store_new(4, glib.TYPE_INT, glib.TYPE_STRING,
	    glib.TYPE_STRING, glib.TYPE_STRING)
    self.combobox:set_model(self.store)

    -- define visible columns
    local r = gtk.cell_renderer_text_new()
    self.combobox:pack_start(r, false)
    self.combobox:set_attributes(r, 'text', 1, 'foreground', 3, nil)

    r = gtk.cell_renderer_text_new()
    self.combobox:pack_start(r, false)
    self.combobox:set_attributes(r, 'text', 2, nil)


    -- add some items
    local iter1, iter2 = gtk.new "GtkTreeIter", gtk.new "GtkTreeIter"
    for i = 1, 10 do
	self.store:append(iter1, nil)
	self.store:set(iter1,
	    0, i,
	    1, "Item " .. i,
	    2, "Info " .. i,
	    3, "green",
	    -1)
	for j = 1, 10 do
	    self.store:append(iter2, iter1)
	    self.store:set(iter2,
		0, i*10+j-1,
		1, "Subitem " .. j,
		2, "Subinfo " .. j,
		3, "blue",
		-1)
	end

    end

    self.w:show_all()
    return self

end

-- main --
mw = MainWin.new()
gtk.main()

