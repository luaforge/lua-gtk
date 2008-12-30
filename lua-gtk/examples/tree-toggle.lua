#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- demonstration of a tree view with a toggle button in it.

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

-- change the state of the toggle
function toggle_func(toggle, path, store)
    local iter = gtk.new "TreeIter"
    if store:get_iter_from_string(iter, path) then
	local val = store:get_value(iter, 2)
	val = 1 - val
	store:set_value(iter, 2, val)
    end
end

function MainWin.new()

    local self = {}
    setmetatable(self, MainWin)

    -- create visible widgets
    self.w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    self.w:connect('destroy', gtk.main_quit)
    self.w:set_default_size(200, 250)
    self.w:set_title("Tree View 2 Demo")
    local sw = gtk.scrolled_window_new(nil, nil)
    sw:set_policy(gtk.POLICY_NEVER, gtk.POLICY_AUTOMATIC)
    self.w:add(sw)
    self.tree_view = gtk.tree_view_new()
    sw:add(self.tree_view)

    -- create store
    self.store = gtk.tree_store_new(3,
	glib.TYPE_INT,	    -- [0] some ID
	glib.TYPE_STRING,   -- [1] label
	glib.TYPE_INT)	    -- [2] checkbox status
    self.tree_view:set_model(self.store)

    -- column with text
    local r, c
    r = gtk.cell_renderer_text_new()
    c = gtk.tree_view_column_new_with_attributes("Name", r, "text", 1, nil)
    self.tree_view:append_column(c)

    -- column with checkbox
    r = gtk.cell_renderer_toggle_new()
    r:set_radio(false)
    r:connect('toggled', toggle_func, self.store)
    c = gtk.tree_view_column_new_with_attributes("Active?",
	    r, "active", 2, nil)
    self.tree_view:append_column(c)

    -- add some items
    local iter1 = gtk.new "TreeIter"
    local pix_open = self.tree_view:render_icon(gtk.STOCK_OPEN,
	gtk.ICON_SIZE_SMALL_TOOLBAR, "")
    local pix_closed = self.tree_view:render_icon(gtk.STOCK_CLOSE,
	gtk.ICON_SIZE_SMALL_TOOLBAR, "")
    for i = 1, 10 do
	self.store:append(iter1, nil)
	self.store:set(iter1,
	    0, i,
	    1, "Item " .. i,
	    2, i % 2,
	    -1)
    end

    self.w:show_all()
    return self
end

-- main --
mw = MainWin.new()
gtk.main()

