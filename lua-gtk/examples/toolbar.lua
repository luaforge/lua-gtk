#! /usr/bin/env lua

-- Demonstrate a toolbar, callbacks, and a text view.

Mainwin = {}
Mainwin.__index = Mainwin

function Mainwin.new()
	local self = {}
	setmetatable(self, Mainwin)

	self.w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
	self.w:set_title("Toolbar Demo")
	self.w:connect('destroy', function() gtk.main_quit() end)
	self.w:set_default_size(450, 400)

	local vbox = gtk.vbox_new(false, 0)
	self.w:add(vbox)

	local handle = gtk.handle_box_new()
	vbox:pack_start(handle, false, true, 0)

	local toolbar = gtk.toolbar_new()
	self.toolbar = toolbar
	handle:add(toolbar)

	local items = {
		{ "gtk-close", Mainwin.on_tool_close },
		{ "gtk-go-back", Mainwin.on_tool_back },
		{ "gtk-go-forward", Mainwin.on_tool_forward },
		{ "gtk-help", Mainwin.on_tool_help },
		{ "SEPARATOR", nil },
		{ "gtk-quit", Mainwin.on_tool_quit } }
	for _, item in pairs(items) do
		local stock = item[1]
		local handler = item[2]
		local button, id

		if stock == 'SEPARATOR' then
			button = gtk.separator_tool_item_new()
		else
			button = gtk.tool_button_new_from_stock(stock)
			id = button:connect("clicked", handler, self)
			-- print("connect id is", id)
			-- button:disconnect(id)
		end
		toolbar:insert(button, -1)
	end

	local sv = gtk.scrolled_window_new(nil, nil)
	vbox:pack_start(sv, true, true, 0)
	self.view = gtk.text_view_new()
	sv:add_with_viewport(self.view)
	self.buffer = self.view:get_buffer()


	self.w:show_all()
	return self
end

-- NOTE: for callbacks, self is the calling widget, i.e. the GtkToolButton.
--
-- insert a word at cursor position
function Mainwin:on_tool_close(mainwin)
	mainwin.buffer:insert_at_cursor("close\n")
end

-- append something
function Mainwin:on_tool_back(mainwin)
	local iter = gtk.new("GtkTextIter")
	mainwin.buffer:get_end_iter(iter)
	mainwin.buffer:insert(iter, "back\n")
end

function Mainwin:on_tool_forward()
	print "forward"
end

function Mainwin:on_tool_help()
	print "help"
end

function Mainwin:on_tool_quit()
	gtk.main_quit()
end

-- main --
require "gtk"
gtk.init(nil, nil)
mainwin = Mainwin.new()
print(gtk.widgets)
gtk.main()

