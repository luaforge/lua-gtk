#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate how to manually run the main loop
--

require "gtk"
-- gtk.set_debug_flags("memory", "trace")

function my_main()

    local ctx, ok, cnt

    ctx = gtk.g_main_context_default()
    ok = gtk.g_main_context_acquire(ctx)
    assert(ok)

    cnt = 5
    local pfd = gtk.new_array("GPollFD", cnt)
    local n, timeout = gtk.g_main_context_query(ctx, 1000, 0, pfd, cnt)
    gtk.g_main_context_release(ctx)

    print("timeout is", timeout)
    for i = 1, n do
	print(string.format("File descriptor #%d is %d", i, pfd[i].fd))
    end

end

-- add another file descriptor, so that the _query function will return
-- more than one, just to demonstrate the array-of-objects feature.
function add_a_source()
    local ctx = gtk.g_main_context_default()
    local pfd = gtk.new "GPollFD"
    pfd.fd = 90
    pfd.events = 3
    gtk.g_main_context_add_poll(ctx, pfd, 10)
end

add_a_source()
my_main()

