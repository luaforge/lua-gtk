#! /usr/bin/env lua

-- demonstration of a tree view

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

function MainWin.new()

	local self = {}
	setmetatable(self, MainWin)

	-- create visible widgets
	self.w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
	self.w:connect('destroy', function() gtk.main_quit() end)
	self.w:set_default_size(200, 50)
	self.w:set_title("ComboBox Demo")

	local vbox = gtk.vbox_new(false, 3)
	self.w:add(vbox)

	self.combobox = gtk.combo_box_new()
	vbox:add(self.combobox)

	-- create store
	self.store = gtk.tree_store_new(4, gtk.G_TYPE_INT, gtk.G_TYPE_STRING,
		gtk.G_TYPE_STRING, gtk.G_TYPE_STRING)
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
		self.store:append1(iter1, nil, i, "Item " .. i,
			"Info " .. i, "green")
		for j = 1, 10 do
			self.store:append1(iter2, iter1, i*10+j-1,
				"Subitem " .. j, "Subinfo " .. j, "blue")
		end

	end

	self.w:show_all()
	return self

end

-- main --
mw = MainWin.new()
gtk.main()

