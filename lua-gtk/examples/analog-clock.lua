#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf-8
--
-- This is a demonstration similar to the "Clock.lua" example of the lgob
-- bindings.
--

require "gtk"
require "cairo"

gnome.set_debug_flags "memory"

function clock_new()
    local clock = gtk.drawing_area_new()
    clock_paint_c = gnome.closure(clock_paint)
    glib.timeout_add_full(glib.PRIORITY_HIGH_IDLE, 1000, clock_paint_c, clock,
	nil)
    clock:connect('expose-event', clock_expose, clock)
    clock._bg_color = { 0, 0, 0, 0.1 }
    clock._hand_color = { 0.2, 0.2, 0.4, 0.9 }
    clock._alloc = gtk.new "Allocation"
    return clock
end

function clock_paint(clock)
    clock:queue_draw()
    return true
end

function clock_expose(clock)
    local cr, r, line_width, pos, date

    cr = gdk.cairo_create(clock:get_window())
    clock:get_allocation(clock._alloc)
    r = math.min(clock._alloc.width, clock._alloc.height) / 2
    line_width = r / 80

    -- move origin to center; set clip region
    cr:translate(r, r)
    -- cr:rectangle(-r, -r, r*2, r*2)
    -- cr:clip()
    r = r * 0.95

    cr:set_line_cap(cairo.LINE_CAP_ROUND)

    -- circle & fill clock face
    cr:set_line_width(line_width * 4)
    cr:arc(0, 0, r, 0, 2 * math.pi)
    cr:set_source_rgba(unpack(clock._bg_color))
    cr:fill_preserve()
    cr:set_source_rgb(0, 0, 0)
    cr:stroke()

    -- ticks
    cr:save()
    for i = 0, 11 do
	if i % 3 == 0 then
	    pos = -r / 1.3
	    cr:set_line_width(line_width * 3)
	else
	    pos = -r / 1.15
	    cr:set_line_width(line_width)
	end

	cr:move_to(0, pos)
	cr:line_to(0, -r)
	cr:stroke()
	cr:rotate(2 * math.pi / 12)
    end
    cr:restore()

    -- pos: 0..1
    -- width: relative to line_width
    -- length: relative to the clock radius
    function paint_hand(cr, pos, width, length)
	cr:save()
	cr:rotate(pos * 2 * math.pi)
	cr:set_line_width(line_width * width)
	cr:move_to(0, 0)
	cr:line_to(0, -r * length)
	cr:stroke()
	cr:restore()
    end

    -- clock hands
    date = os.date("*t")
    cr:set_source_rgba(unpack(clock._hand_color))
    paint_hand(cr, date.hour / 12 + date.min / 60 / 12, 5, 0.5)
    paint_hand(cr, date.min / 60 + date.sec / 60 / 60, 3.5, 0.66)
    paint_hand(cr, date.sec / 60, 2, 0.833)

    -- optional - eventually happens automatically.
    -- cr:destroy()
end

function build_ui()
    local win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    win:set_title"Clock Demonstration"
    win:connect('delete-event', gtk.main_quit)
    win:set_default_size(200, 200)

    local clock = clock_new()
    win:add(clock)
    win:show_all()
    return win
end

local mainwin = build_ui()
gtk.main()

