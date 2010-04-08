
require "gdk"

display = gdk.display_get_default()
screen = display:get_default_screen()
x = gdk.x11_screen_get_xscreen(screen)
assert(x)

