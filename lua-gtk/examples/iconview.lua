#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Demonstration of the icon view
-- by Wolfgang Oertl on 9.2.2007

require "gtk"

local MainWin = {}
MainWin.__index = MainWin

function MainWin.new()
    local self = {}
    setmetatable(self, MainWin)

    self.w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    self.w:connect('destroy', gtk.main_quit)
    self.w:set_default_size(200, 250)
    self.w:set_title("Icon View Demo")

    local sw = gtk.scrolled_window_new(nil, nil)
    sw:set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
    self.w:add(sw)

    self.icon_view = gtk.icon_view_new()
    sw:add(self.icon_view)

    -- create store
    self.store = gtk.list_store_new(3, glib.TYPE_INT, glib.TYPE_STRING,
	    gdk.pixbuf_get_type())
    self.icon_view:set_model(self.store)
    self.icon_view:set_text_column(1)
    self.icon_view:set_pixbuf_column(2)

    -- insert some items.  see .../gtk/gtkstock.h
    local iter = gtk.new "GtkTreeIter"
    local pix
    local names = { 'quit', 'open', 'redo', 'refresh', 'stop', 'save',
	'save-as', 'select-color', 'yes', 'no', 'zoom-fit' }

    for i, name in ipairs(names) do
	self.store:append(iter)
	pix = self.icon_view:render_icon('gtk-' .. name,
	    gtk.ICON_SIZE_DIALOG, "")
	self.store:set(iter, 0, i, 1, name, 2, pix, -1)
    end

    self.w:show_all()
    return self
end
   
-- main --
mw = MainWin.new()
gtk.main()
