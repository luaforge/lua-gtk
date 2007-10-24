#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

-- meta class for my window
MYWIN = {}
win_count = 0


function mywin_new(msg)
    local self = { pixmap=nil, msg=msg }
    setmetatable(self, MYWIN)
    self.win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    self.win:connect('destroy', MYWIN.on_destroy, self)
    self.win:set_title('Pixmap Test')
    local da = gtk.drawing_area_new()
    self.win:add(da)
    da:connect('configure-event', MYWIN.on_configure, self)
    da:connect('expose-event', MYWIN.on_expose, self)
    self.win:show_all()
    win_count = win_count + 1
    return self
end

function MYWIN:on_destroy()
    win_count = win_count - 1
    if win_count == 0 then
	gtk.main_quit()
    end
end

--
-- On configure (size change), allocate a pixmap, fill with white and draw
-- something in it.
--
function MYWIN:on_configure(ev, ifo)
    -- print("on_configure", ev, ifo, ifo.win)
    -- print("private_flags", ifo.win.private_flags)   -- this works.
    -- get GdkWindow
    local window = ifo.win.window
    local width, height = window:get_size(0, 0)
    -- deallocate previous pixmap - happens automatically!
    -- if (ifo.pixmap) then ifo.pixmap:unref() end

    -- allocates memory in X server... default drawable, width, height, depth
    -- loses the reference to the previous pixmap, if any.
    ifo.pixmap = gtk.call("gdk_pixmap_new", window, width, height, -1)

    local style = ifo.win:get_style()
    local white_gc = style.white_gc
    local black_gc = style.black_gc

    -- clear the whole pixmap
    ifo.pixmap:draw_rectangle(white_gc, true, 0, 0, width, height)

    -- draw a rectangle
    if width > 20 and height > 20 then
	ifo.pixmap:draw_rectangle(black_gc, false, 10, 10, width - 20,
	    height - 20)
    end

    -- draw a text message
    local message = "Hello, World! " .. ifo.msg
    local layout = ifo.win:create_pango_layout(message)
    ifo.pixmap:draw_layout(black_gc, 15, 15, layout)

    -- get size of message
    local region = layout:get_clip_region(0, 0, {0, string.len(message)}, 1)
    local rect = gtk.new("GdkRectangle")
    region:get_clipbox(rect)
    if rect.width > 0 then
	ifo.pixmap:draw_layout(black_gc, width - 15 - rect.width,
	    height - 15 - rect.height, layout)
    end

    -- Make sure that the unreferenced pixmap is freed NOW and not eventually,
    -- because this can eat up loads of memory of the X server.
    collectgarbage()
    -- print(gcinfo())

    return true
end

-- on expose, copy the newly visible part of the pixmap to the GdkWindow
-- of the drawing area.
function MYWIN:on_expose(ev, ifo)
    -- print "on_expose"
    -- print(ev)
    -- print(ev.expose)
    -- gtk.dump_struct(ev)
    local area = ev.expose.area
    local x, y, w, h = area.x, area.y, area.width, area.height
    local window = self.window
    local style = ifo.win:get_style()
    local white_gc = style.white_gc
    gtk.call("gdk_draw_drawable", window, white_gc, ifo.pixmap,
	x, y, x, y, w, h)
    return false
end

gtk.init()
mywin1 = mywin_new("One")
mywin2 = mywin_new("Two")
gtk.main()

mywin1 = nil
mywin2 = nil

if false then
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("collect")
    gtk.dump_memory()
end

