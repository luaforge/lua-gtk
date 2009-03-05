#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- This is the "test-actors.c" example from the clutter-0.8 source.
--

require "clutter"

n_hands = 6
stage_w = 800
stage_h = 800
radius = math.sqrt(stage_w * stage_h) / 3
hands = {}
mydir = string.gsub(arg[0], "/[^/]+$", "")

-- Input handler
function input_cb(stage, event)
    local x, y, e, name

    if event.type == clutter.BUTTON_PRESS then
	x, y = event:get_coords(0, 0)
	e = stage:get_actor_at_pos(x, y)
	if e then
	    name = e:get_type()
	    if name == "ClutterTexture" or name == "ClutterCloneTexture" then
		e:hide()
		return true
	    end
	end
    end

    if event.type == clutter.KEY_RELEASE then
	event = gnome.cast(event, "ClutterKeyEvent")
	sym = event:symbol()

	if sym == string.byte"q" then
	    clutter.main_quit()
	    return true
	end

	if sym == string.byte"r" then
	    for _, hand in ipairs(hands) do
		hand:show()
	    end
	    return true
	end

	if sym == string.byte" " then
	    if timeline:is_playing() then
		timeline:pause()
	    else
		timeline:start()
	    end
	end

    end
end

-- Update the rotation of the whole group and the individual hands.
function frame_cb(timeline, frame_nr)
    group:set_rotation(clutter.Z_AXIS, frame_nr, stage_w/2, stage_h/2, 0)
    for i, hand in ipairs(hands) do
	local x, y = hand:get_scale(0, 0)
	hand:set_rotation(clutter.Z_AXIS, -6 * frame_nr, 0, 0, 0)
    end
    -- show the hands after the first update.
    group:show()
end


function test_actors_main()
    local w, h, hand, d, x, y

    stage = clutter.stage_get_default()
    stage:set_size(800, 800)
    stage:set_title("Actors Test")
    local stage_color = clutter.new "Color"
    stage_color:from_pixel(0x61648cff)
    stage:set_color(stage_color)

    timeline = clutter.timeline_new(360, 10);	    -- num frames, fps
    timeline:set("loop", true, nil)
    timeline:connect('new-frame', frame_cb)

    stage:connect('button-press-event', input_cb)
    stage:connect('key-release-event', input_cb)

    cl = gnome.closure(clutter.sine_func)
    alpha = clutter.alpha_new_full(timeline, cl, nil, nil)
    scaler_1 = clutter.behaviour_scale_new(alpha, 0.5, 0.5, 1.0, 1.0)
    scaler_2 = clutter.behaviour_scale_new(alpha, 1.0, 1.0, 0.5, 0.5)

    -- group to hold multiple actors
    group = clutter.group_new()

    for i = 1, n_hands do
	if i == 1 then
	    hand, err = clutter.texture_new_from_file(mydir .. "/redhand.png",
		gnome.NIL)
	    if not hand then error(err.message) end
	    w = hand:get_width()
	    h = hand:get_height()
	else
	    hand = clutter.clone_texture_new(hands[1])
	end

	d = (i-1) * math.pi / (n_hands / 2)
	x = stage_w / 2 + radius * math.cos(d) - w / 2
	y = stage_h / 2 + radius * math.sin(d) - h / 2
	hand:set_position(x, y)
	hand:move_anchor_point_from_gravity(clutter.GRAVITY_CENTER)
	group:add_actor(hand)

	if i % 2 == 0 then
	    scaler_1:apply(hand)
	else
	    scaler_2:apply(hand)
	end

	hands[i] = hand
    end

    stage:add_actor(group)

    -- don't initially show the hands.
    group:hide()
    timeline:start()
    stage:show()
end

function main()
    clutter.init(0, nil)
    test_actors_main()
    clutter.main()
end

main()

