#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- based on http://svn.o-hand.com/repos/clutter/trunk/toys/courasel/
-- (http://git.clutter-project.org/cgit.cgi?url=toys/tree/courasel)

require 'clutter'

-- configuration --
local init_duration = 1000  -- in ms
local fps = 20
local items_init = {
    { "accessories-text-editor.png", "Text Editor" },
    { "applications-games.png", "Game" },
    { "dates.png", "Dates" },
    { "im-client.png", "Chat" },
    { "preferences-desktop-theme.png", "Preferences" },
    { "tasks.png", "Todo List" },
    { "utilities-terminal.png", "Terminal" },
    { "web-browser.png", "Browser"},
}
local alpha_low = 0x66
local scale_small = 0.6
local ms_per_step = 400	    -- higher value is lower rotation speed
-- end configuration --

local stage, timeline, csw, csh, label, label_behave
local items = {}	    -- actor, move, opacity, scale, text
local selected_index = 1    -- currently selected item
local STEP = 360 / #items_init
local running = 0	    -- current direction (-1 or 1) or 0 when stopped
local alpha_sine_inc	    -- alpha function for the movement
local stop_from_pos = 0	    -- at which timeline position the stop was initiated
local stopping


---
-- During the intro, all items start at angle -90 and move at different speeds
-- to their target positions.  The selected item will be scaled to 1.0 and
-- have full opacity.
--
function introduce_items()
    for i, item in pairs(items) do
	item.move:set_angle_start(-90)
	item.move:set_angle_end(STEP * i)

	if i == selected_index then
	    item.opacity:set('opacity-end', 0xff)
	    item.scale:set('x-scale-end', 1, 'y-scale-end', 1)
	end
    end

    timeline:start()
end



---
-- Configure the timeline to rotate one item forward or backward, then start
-- it.
--
function rotate_items()
    local from_index, ang, b, scale, opacity
    local step = running
    
    from_index = selected_index
    ang = 360 - from_index * STEP + 90
    selected_index = 1 + (selected_index - step - 1 + #items) % #items

    for i, item in ipairs(items) do
	b = item.move
	b:set_direction(step > 0 and clutter.ROTATE_CW or clutter.ROTATE_CCW)
	b:set_angle_start(ang)
	b:set_angle_end(ang + STEP * step)

	opacity = { alpha_low, alpha_low }
	scale = { scale_small, scale_small }

	if i == from_index then
	    opacity[1] = 0xff
	    scale[1] = 1
	elseif i == selected_index then
	    opacity[2] = 0xff
	    scale[2] = 1
	end

	item.opacity:set('opacity-start', opacity[1], 'opacity-end',
	    opacity[2])
	item.scale:set('x-scale-start', scale[1], 'y-scale-start',
	    scale[1], 'x-scale-end', scale[2], 'y-scale-end', scale[2])

	ang = ang + STEP
   end

    timeline:start()
end


-- Key Symbols are not available... yet?
clutter.Left = 65361
clutter.Right = 65363
clutter.q = 113

local handler_press = {
    [clutter.Left] = function() running=-1; rotate_items() end,
    [clutter.Right] = function() running=1; rotate_items() end,
}

---
-- Respond to some key presses.
--
function on_key_press(actor, event, self)
    local sym = event.key:symbol()
    if sym == clutter.q then
	clutter.main_quit()
	return false
    end

    -- currently stopping - don't disturb that.
    if stopping then
	return false
    end

    -- abort stopping
    stop_from_pos = nil
    if timeline:is_playing() then
	return false
    end

    local fn = handler_press[sym]
    if fn then fn() end
end

-- release: may be followed immediately by press, which means that the
-- key is being held down.
function on_key_release(actor, event, self)
    local sym = event.key:symbol()
    if sym == clutter.Left or sym == clutter.Right then
	if not stopping then
	    stop_from_pos = timeline:get_progress()
	end
    end
end

function on_scroll_event(actor, event)
    if not timeline:is_playing() then
	running = (event.scroll.direction == clutter.SCROLL_UP) and -1 or 1
	rotate_items()
    end
end

function movement_alpha(alpha)
    local tl = alpha:get_timeline()
    local p = tl:get_progress()

    -- continuous operation: linear
    if stop_from_pos == nil then
	return math.floor(p * 65535)
    end

    -- otherwise, gradual stop
    stopping = true
    local range = 1 - stop_from_pos
    local p2 = (p - stop_from_pos) / range
    p = stop_from_pos + range * (math.sin(p2 * math.pi / 2))

    return math.floor(p * 65535)
end


---
-- Change the label text at the middle of the animation, which is when
-- the text has been faded out.
--
function on_timeline_new_frame(timeline, frame_num, app)
    if frame_num == math.floor(timeline:get_n_frames() / 2) then
	label:set_text(items[selected_index].text)
    end
end


---
-- Rotating should be quick, regardless of the intro speed.
--
function on_timeline_completed(timeline, frame_num, app)
    timeline:set_duration(ms_per_step)
    stopping = false
    if not stop_from_pos then
	rotate_items()
    end
end

function init()
    local color, item, alpha_ramp, ac

    stage = clutter.stage_get_default()
    stage:set_size(800, 600)
    stage:set_title"Clutter Carousel Demo"

    color = clutter.new"Color"
    color:from_pixel(0x343939ff)
    stage:set_color(color)

    -- the into should be 1 second long.
    timeline = clutter.timeline_new(init_duration * fps / 1000, fps)

    cl = gnome.closure(movement_alpha)
    alpha_sine_inc = clutter.alpha_new_full(timeline, cl, nil, nil)
    alpha_ramp = clutter.alpha_new_full(timeline, clutter.sine_half_func,
	nil, nil)
    alpha_scale = clutter.alpha_new_full(timeline, clutter.sine_inc_func, nil,
	nil)

    csw = stage:get_width()
    csh = stage:get_height()

    for k, v in pairs(items_init) do
	ac = clutter.texture_new_from_file(v[1], nil)
	assert(ac, "Couldn't load file " .. tostring(v[1]))

	item = {
	    actor = ac,
	    move = clutter.behaviour_ellipse_new(alpha_sine_inc,
		csw/4, csh-(csh/2), csw/2, csh-(csh/4),
		clutter.ROTATE_CW, 0, 360),
	    opacity = clutter.behaviour_opacity_new(alpha_sine_inc,
		alpha_low, alpha_low),
	    scale = clutter.behaviour_scale_new(alpha_scale,
		scale_small, scale_small, scale_small, scale_small),
	    text = v[2]
	}
	item.move:apply(ac)
	item.opacity:apply(ac)
	item.scale:apply(ac)
	stage:add_actor(ac)
	items[#items + 1] = item
    end

    color:from_pixel(0x729fcfff)
    label = clutter.label_new_with_text('Coolvetica 60px', '')
    label:set_color(color)
    label:set_size(300, 200)
    label:set_line_wrap(false)
    label:set_position(csw/2-40, 40)
    stage:add_actor(label)

    label_behave = clutter.behaviour_opacity_new(alpha_ramp, 0xff, 0)
    label_behave:apply(label)

    stage:connect('key-press-event', on_key_press)
    stage:connect('key-release-event', on_key_release)
    stage:connect('scroll-event', on_scroll_event)
    timeline:connect('new-frame', on_timeline_new_frame)
    timeline:connect('completed', on_timeline_completed)
    stage:connect('destroy', clutter.main_quit)
    stage:show_all()

    introduce_items()
end

-- MAIN --
clutter.init(0, nil)
init()
collectgarbage"collect"
collectgarbage"collect"
clutter.main()

