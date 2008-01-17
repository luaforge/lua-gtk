#! /usr/bin/lua

require "gtk"

-- let it be called 10 times, then cause the main loop to exit.
function my_idle(data)
	print("my_idle called", data[1])
	n = data[1] + 1
	if n < 10 then
		data[1] = n
		return true
	end
	gtk.main_quit()
	print "exit"
	return false
end

gtk.g_idle_add(my_idle, {0})
gtk.main()

print "ok"

