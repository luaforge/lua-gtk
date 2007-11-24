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
	self.w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
	self.w:connect('destroy', function() gtk.main_quit() end)
	self.w:set_default_size(200, 250)
	self.w:set_title("Tree View Demo")
	local sw = gtk.scrolled_window_new(nil, nil)
	sw:set_policy(gtk.GTK_POLICY_NEVER, gtk.GTK_POLICY_AUTOMATIC)
	self.w:add(sw)
	self.tree_view = gtk.tree_view_new()
	sw:add(self.tree_view)

	-- create store
	self.store = gtk.tree_store_new(4, gtk.G_TYPE_INT, gtk.G_TYPE_STRING,
		gtk.G_TYPE_STRING, gtk.G_TYPE_STRING)
	self.tree_view:set_model(self.store)

	-- define visible columns
	local r = gtk.cell_renderer_text_new()
	local c = gtk.tree_view_column_new_with_attributes("Name",
		r, "text", 1, "foreground", 3, nil)
	self.tree_view:append_column(c)

	r = gtk.cell_renderer_text_new()
	c = gtk.tree_view_column_new_with_attributes("Info",
		r, "text", 2, "foreground", 3, nil)
	self.tree_view:append_column(c)


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

