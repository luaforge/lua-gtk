#! /usr/bin/env lua
-- vim:sw=4:sts=4
require "gtk"

ok = false

-- let it be called 10 times, then cause the main loop to exit.
function my_idle(data)
    n = data[1] + 1
    if n < 10 then
	data[1] = n
	return true
    end
    data:destroy()
    gtk.main_quit()
    ok = true
    return false
end

cl = gnome.closure(my_idle)
glib.idle_add(cl, {0})
gtk.main()

assert(ok)

