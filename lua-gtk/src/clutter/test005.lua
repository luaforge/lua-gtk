#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Draw a number of overlapping rectangles to show alpha blending.
--

require 'clutter'

-- verify that this callback is called
n = 0
function on_stage_add(group, element)
    n = n + 1
end

function on_button_press_event(stage, event)
    print(string.format('Button press at (x:%d, y:%d): %d',
	event.button.x, event.button.y, event.button.button))

    -- exercise clutter_container_foreach
    local m = 0
    stage:foreach(function(actor, data)
	m = m + 1
	assert(data.value == "hello")
    end, "hello")
    assert(m == 9)
    clutter.main_quit()
end

function main()
    local stage, color, border_color, rect, border_color, nc

    clutter.init(0, nil)

    stage = clutter.stage_get_default()
    stage:set_size(800, 600)
    stage:set_title"Clutter Rectangles Demo"

    color = clutter.new "Color"
    clutter.color_parse("DarkSlateGray", color)
    stage:set_color(color)
    stage:connect('add', on_stage_add)
    stage:connect('button-press-event', on_button_press_event)

    stage:get_color(color)
    assert(color:to_string() == "#2f4f4fff")

    color:from_pixel(0x3f992a66)
    border_color = clutter.new "Color"
    color:lighten(border_color)

    nc = clutter.new "Color"
    nc:from_pixel(0x35992a33)

    for i = 1, 9 do
	rect = clutter.rectangle_new_with_color(math.fmod(i, 2) == 0 and
	    color or nc)

	rect:set_position((800-(80*i))/2, (600-(60*i))/2)
	rect:set_size(80 * i, 60 * i)
	rect:set_border_width(10)
	rect:set_border_color(border_color)
	stage:add_actor(rect)    
	rect:show()
    end

    stage:show()

    clutter.main()
end

main()

assert(n == 9)

