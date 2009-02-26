#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Show an entry field.  Click on it, type something and press enter.
-- by Michal Kolodziejczyk, Wolfgang Oertl
--

require 'clutter'

-- click on the entry - focus it.
function on_button_cb(entry, event)
    local stage = entry:get_stage()
    stage:set_key_focus(entry)
    return false
end

-- press enter - read the entered text and unfocus.
function on_activated_cb(entry)
    print('Entered text was: ' .. entry:get_text())
    entry:get_stage():set_key_focus(nil)
    return false
end

-- set the active or inactive color.
function on_focus(entry, mode)
    if mode == 1 then
	entry:set_opacity(255)
	entry:set_visible_cursor(true)
    else
	entry:set_opacity(127)
	entry:set_visible_cursor(false)
    end
end

function main()
    local bg, field, entry

    clutter.init(0, nil)

    stage = clutter.stage_get_default()
    stage:set_size(320, 240)
    stage:set_title"Clutter Entry Demo"
    -- stage:connect('unrealize', quit) -- does not work?

    -- define a blue foreground color
    fg = clutter.new "Color"
    fg:from_pixel(0x000044ff)

    -- define a light yellow as background
    bg = clutter.new "Color"
    bg:from_pixel(0xffff88dd)

    -- an entry
    entry = clutter.entry_new()
    entry:set_text("Click and type to modify!")

    -- get the height and use it for the background, too.
    local layout = entry:get_layout()
    local x, y = layout:get_pixel_size(0, 0)
    entry:set_size(300, y)

    -- the background
    field = clutter.rectangle_new_with_color(bg)
    field:set_position(10, 10)
    field:set_size(300, y)
    stage:add_actor(field)
    entry:set_color(fg)
    entry:set_position(10, 10)
    entry:set_visibility(true)
    entry:set_reactive(true)
    entry:connect("button-press-event", on_button_cb, nil)
    entry:connect("activate", on_activated_cb, nil)
    entry:connect("focus-in", on_focus, 1)
    entry:connect("focus-out", on_focus, 0)
    on_focus(entry, 0)

    stage:add_actor(entry)

    stage:show_all()

    clutter.main()
end

main()

