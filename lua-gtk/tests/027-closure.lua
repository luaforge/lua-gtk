#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Exercise the closure mechanism, i.e. Gtk calling a Lua function via a
-- FFI closure.
--
-- Note: it works, but the numerous warnings about memory leaks etc. indicate
-- that it's not working well.

require "gtk"

function compare_func(a, b)
    print("keyfunc", a, b)
    if a == b then return 0 end
    return a < b and -1 or 1
end

function traverse_func(key, value, user_data)
    print("traverse_func", key, value, user_data)
    return nil
end

-- has to create a closure
t = gtk.g_tree_new(compare_func)

t:insert("a", "value a")
t:insert("b", "value b")

t:foreach(traverse_func, 99)

