#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate how to manually run the main loop
--

require "gtk"
-- gnome.set_debug_flags("memory", "trace")

function my_main()

    local ctx, ok, cnt

    ctx = glib.main_context_default()
    ok = glib.main_context_acquire(ctx)
    assert(ok)

    cnt = 5
    local pfd = glib.new_array("PollFD", cnt)
    local n, timeout = glib.main_context_query(ctx, 1000, 0, pfd, cnt)
    glib.main_context_release(ctx)

    print("timeout is", timeout)
    for i = 1, n do
	print(string.format("File descriptor #%d is %d", i, pfd[i].fd))
    end

end

-- add another file descriptor, so that the _query function will return
-- more than one, just to demonstrate the array-of-objects feature.
function add_a_source()
    local ctx = glib.main_context_default()
    local pfd = glib.new "PollFD"
    pfd.fd = 90
    pfd.events = 3
    glib.main_context_add_poll(ctx, pfd, 10)
end

add_a_source()
my_main()

