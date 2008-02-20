#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- demonstration of a tree view

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

function handle_inserted(model, path, iter, data1, data2)
    print("handle_inserted", model, path, iter, data1, data2)
end

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
    self.store = gtk.tree_store_new(5, gtk.G_TYPE_INT,
	gtk.gdk_pixbuf_get_type(), gtk.G_TYPE_STRING, gtk.G_TYPE_STRING,
	gtk.G_TYPE_STRING)
    self.tree_view:set_model(self.store)
    -- self.store:connect('row-inserted', handle_inserted, "a", "b")

    -- first column with icon
    local r = gtk.cell_renderer_pixbuf_new()
    local c = gtk.tree_view_column_new_with_attributes("Icon",
	r, "pixbuf", 1, nil)
    self.tree_view:append_column(c)

    -- second column with text
    r = gtk.cell_renderer_text_new()
    c = gtk.tree_view_column_new_with_attributes("Name",
	    r, "text", 2, "foreground", 4, nil)
    self.tree_view:append_column(c)

    -- third column with text
    r = gtk.cell_renderer_text_new()
    c = gtk.tree_view_column_new_with_attributes("Info",
	    r, "text", 3, "foreground", 4, nil)
    self.tree_view:append_column(c)

    -- add some items
    local iter1, iter2 = gtk.new "GtkTreeIter", gtk.new "GtkTreeIter"
    local pix_open = self.tree_view:render_icon(gtk.GTK_STOCK_OPEN,
	gtk.GTK_ICON_SIZE_SMALL_TOOLBAR, "")
    local pix_closed = self.tree_view:render_icon(gtk.GTK_STOCK_CLOSE,
	gtk.GTK_ICON_SIZE_SMALL_TOOLBAR, "")
    for i = 1, 10 do
	self.store:append1(iter1, nil,
	    i,
	    pix_open,
	    "Item " .. i,
	    "Info " .. i,
	    "green")
	for j = 1, 10 do
	    self.store:append1(iter2, iter1,
		i*10+j-1,
		pix_closed,
		"Subitem " .. j,
		"Subinfo " .. j,
		"blue")
	end
    end

    self.w:show_all()
    return self
end

-- main --
mw = MainWin.new()
gtk.main()

