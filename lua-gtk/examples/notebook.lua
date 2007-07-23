#! /usr/bin/env lua

-- demonstrate a Notebook with two pages.

Mainwin = {}
Mainwin.__index = Mainwin

function Mainwin:add_page(page)

	local label = gtk.label_new(page.title)
	local page_nr = self.notebook:append_page(page.w, label)
	-- self.notebook:set_current_page(page_nr)
	page.w:show_all()

end

function Mainwin.init()

	local self = {}
	setmetatable(self, Mainwin)
	
	self.w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
	local w = self.w
	w:connect('delete-event', Mainwin.on_quit)
	w:set_title('Notebook test')
	w:set_default_size(450, 400)

	local vbox = gtk.vbox_new(false, 0)
	w:add(vbox)

	self.notebook = gtk.notebook_new()
	self.notebook:connect('switch-page', Mainwin.on_switch_page)
	vbox:pack_start_defaults(self.notebook)
	
	self.statusbar = gtk.statusbar_new()
	vbox:pack_start(self.statusbar, false, true, 0)

	local page = { title='first page', w=gtk.label_new('Page 1') }
	self:add_page(page)

	page = { title='second page', w=gtk.label_new('Page 2') }
	self:add_page(page)

	w:show_all()

	return self
end

function Mainwin:on_quit()
	gtk.main_quit()
end

function Mainwin:on_switch_page(page, page_nr)
	print("on_switch_page", self, page, page_nr)
end


-- main --

require "gtk"
gtk.init(nil, nil)
mainwin = Mainwin.init()
gtk.main()

