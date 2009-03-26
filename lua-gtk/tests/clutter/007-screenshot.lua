#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Example to make a screenshot of another window and display it in
-- our own window with automatic update.
--

require 'clutter'
require 'gdk'		-- required for the "Window" data type.


-- get the XID, which is an unsigned long.
win_remote = arg[1]
if not win_remote then
   print('Usage: '..arg[0]..' <windowid>  (can be found with xwininfo)')
   return
end
win_remote = tonumber(win_remote)


clutter.init(0, nil)

stage = clutter.stage_get_default()
stage:set_size(300, 300)
stage:set_title"Clutter Window Hijack Demo"

color = clutter.new "Color"
color:from_pixel(0x999999ff)
stage:set_color(color)

-- tex=clutter.glx_texture_pixmap_new_with_window(win_remote)
tex = clutter.x11_texture_pixmap_new_with_window(win_remote)
tex:set_filter_quality(clutter.TEXTURE_QUALITY_MEDIUM)
tex:set_automatic(true)
-- print(tex, tex:get"window")
stage:add_actor(tex)
stage:show_all()

clutter.main()

