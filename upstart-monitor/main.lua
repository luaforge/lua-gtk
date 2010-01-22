#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf-8

require "gtk"

local main

function build_ui()
    local b, rc, err, main

    b = gtk.builder_new()
    rc, err = b:add_from_file("main.ui", nil)
    if err then print(err.message); return end
    b:connect_signals_full(_G)

    main = {}

    for _, name in ipairs { "service_list", "service_view" } do
	main[name] = assert(b:get_object(name))
    end

    return main
end

function load_status()
    local list, name, status, rest, pos, running, pid

    list = main.service_list
    f = io.popen("/sbin/initctl list")

    pos = 0
    for l in f:lines() do
	name, status, rest = string.match(l, "^(%S+) (%S+)(.*)")
	print(name, status)
	if string.match(status, "running") then
	    running = true
	    pid = string.match(rest, "(%d+)$")
	else
	    running = false
	    pid = 0
	end

	list:insert_with_values(nil, pos,
	    0, tostring(name),
	    1, tonumber(pid),
	    2, running,
	    -1)
	pos = pos + 1
    end

    f:close()

    -- activate sorting
    list:set_sort_column_id(0, gtk.SORT_ASCENDING)
end

main = build_ui()
load_status()
gtk.main()

