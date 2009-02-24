#! /usr/bin/env lua
-- vim:sw=4:sts=4

require 'clutter'
require 'glib'

clutter.init(0, nil)

stage = clutter.stage_get_default()
stage:set_size(300, 300)
print(stage)

-- define a red, somewhat transparent color
red = clutter.new "ClutterColor"
clutter.color_parse("#ff000088", red)

-- add a red rectangle
actor = clutter.rectangle_new_with_color(red)
actor:set_size(100, 30)
actor:set_position(150, 130)
stage:add_actor(actor)

-- and another
actor = clutter.rectangle_new_with_color(red)
actor:set_size(50, 50)
actor:set_position(130, 110)
stage:add_actor(actor)

stage:show_all()

clutter.main()

