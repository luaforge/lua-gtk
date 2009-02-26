#! /usr/bin/env lua
-- vim:sw=4:sts=4

require 'clutter'

message='Hello, Clutter!'


function on_button_press_event(actor, event, self)
    local e = event.button -- in python event, in lua event.button
    print(string.format("mouse button %d pressed at (%d, %d)", e.button,
	e.x, e.y))
end

function quit(...)
   clutter.main_quit()
end

---
-- Set up the stage, a label and a blinking cursor.
--
function main()
    local stage, c, label, lw, lh, lx, ly, cursor, cx, cy
    local closure, behaviour, alpha

    clutter.init(0, nil)

    stage = clutter.stage_get_default()
    stage:set_size(800, 600)
    c = clutter.new "Color"
    clutter.color_parse("DarkSlateGrey", c)
    stage:set_color(c)
    stage:set_title"Clutter Hello Demo"
    stage:connect('key-press-event', quit, stage)
    stage:connect('button-press-event', on_button_press_event, stage)

    c = clutter.new "Color"
    c:from_pixel(0xffccccdd)
    label = clutter.label_new_full("Mono 32", message, c)

    lw, lh = label:get_size(0, 0) -- have to pass 2 args
    lx = stage:get_width() - lw - 50
    ly = stage:get_height() - lh
    label:set_position(lx, ly)
    stage:add_actor(label)

    -- create a rectangle that looks like a cursor
    cursor = clutter.rectangle_new_with_color(c)
    cursor:set_size(20, lh)
    cx =stage:get_width() - 50
    cy =stage:get_height() - lh
    cursor:set_position(cx, cy)
    stage:add_actor(cursor)

    -- add a timeline, alpha, and behaviour to let the cursor blink
    timeline = clutter.timeline_new(20, 30)
    timeline:set_loop(true)

    closure = gnome.closure(clutter.ramp_func)
    alpha = clutter.alpha_new_full(timeline, closure, nil, nil)
    alpha._closure = closure

    behaviour = clutter.behaviour_opacity_new(alpha, 0xdd, 0)
    behaviour:apply(cursor)

    stage:show_all()
    timeline:start()
    clutter.main()
end

main()

-- some things remain in the registry...
-- collectgarbage"collect"
-- gnome.dump_memory()


