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

	-- new statusbar
	self.status = gtk.statusbar_new()
	self.context_id = self.status:get_context_id("bufpos")
	vbox:pack_start(self.status, false, true, 0)

	-- Callback to update cursor position.
	self.buffer = self.view:get_buffer()
	self.buffer:connect_after('mark-set', update_status)

	self.w:show_all()
	return self
end

function update_status()
	local win = mainwin
	local mark = win.buffer:get_insert()
	local iter = gtk.new "GtkTextIter"
	win.buffer:get_iter_at_mark(iter, mark)
	win.status:pop(win.context_id)
	win.status:push(win.context_id, string.format("Line %d, Column %d",
		iter:get_line() + 1, iter:get_line_offset() + 1))

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
mainwin = Mainwin.new()
update_status()
gtk.main()

