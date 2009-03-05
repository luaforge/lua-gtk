#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- demonstration of a tree view

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

function handle_inserted(model, path, iter, data1, data2)
    print("handle_inserted", model, path, iter, data1, data2)
end

---
-- Iterate through all selected items
--
function show_selection(btn, mainwin)
    local tv = mainwin.tree_view
    local sel = tv:get_selection()
    local model = tv:get_model()
    local list = sel:get_selected_rows(nil)
    local iter = gtk.new "TreeIter"
    local root = list

    while list do
	local path = list.data:cast("GtkTreePath")
	model:get_iter(iter, path)
	local s = model:get_value(iter, 2)
	print(s)
	path:free()
	list = list.next
    end

    if root then
	root:free()
    end
end

---
-- A simpler version of the above using gtk_tree_selection_selected_foreach.
--
function show_selection_2(btn, mainwin)
    local tv = mainwin.tree_view
    local sel = tv:get_selection()
    sel:selected_foreach(function(model, path, iter, data)
	local s = model:get_value(iter, 2)
	print(s)
	-- demonstrate that the active closure won't be collected
	collectgarbage "collect"
    end, nil)
end

function MainWin.new()

    local self = {}
    setmetatable(self, MainWin)

    -- create visible widgets
    self.w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    self.w:connect('destroy', gtk.main_quit)
    self.w:set_default_size(200, 250)
    self.w:set_title("Tree View Demo")

    local vbox = gtk.vbox_new(false, 10)
    self.w:add(vbox)

    -- list within a scrolled window
    local sw = gtk.scrolled_window_new(nil, nil)
    sw:set_policy(gtk.POLICY_NEVER, gtk.POLICY_AUTOMATIC)
    vbox:pack_start(sw, true, true, 0)
    self.tree_view = gtk.tree_view_new()
    sw:add(self.tree_view)
    local sel = self.tree_view:get_selection()
    sel:set_mode(gtk.SELECTION_MULTIPLE)

    local btn = gtk.button_new_with_label("Show Selection")
    btn:connect('clicked', show_selection_2, self)
    vbox:pack_start(btn, false, true, 10)

    -- create store
    self.store = gtk.tree_store_new(5, glib.TYPE_INT,
	gdk.pixbuf_get_type(), glib.TYPE_STRING, glib.TYPE_STRING,
	glib.TYPE_STRING)
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
    local iter1, iter2 = gtk.new "TreeIter", gtk.new "TreeIter"
    local pix_open = self.tree_view:render_icon(gtk.STOCK_OPEN,
	gtk.ICON_SIZE_SMALL_TOOLBAR, "")
    local pix_closed = self.tree_view:render_icon(gtk.STOCK_CLOSE,
	gtk.ICON_SIZE_SMALL_TOOLBAR, "")
    for i = 1, 10 do
	self.store:append(iter1, nil)
	self.store:set(iter1,
	    0, i,
	    1, pix_open,
	    2, "Item " .. i,
	    3, "Info " .. i,
	    4, "green",
	    -1)
	for j = 1, 10 do
	    self.store:append(iter2, iter1)
	    self.store:set(iter2,
		0, i*10+j-1,
		1, pix_closed,
		2, "Subitem " .. j,
		3, "Subinfo " .. j,
		4, "blue",
		-1)
	end
    end

    self.w:show_all()
    return self
end

-- main --
mw = MainWin.new()
gtk.main()

