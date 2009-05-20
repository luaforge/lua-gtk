#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gnet"
-- gnome.set_debug_flags "memory"

local loop

function dns_callback(addr, data)
    print("got address", addr:get_canonical_name())
    -- gnet.inetaddr_get_canonical_name(addr))
    loop:quit()
end

-- glib.thread_init(nil)
cl = gnome.closure(dns_callback)
token = gnet.inetaddr_new_async("www.google.com", 80, cl, "data")
assert(type(token.cancel) == "function")

loop = glib.main_loop_new(nil, false)
loop:run()


