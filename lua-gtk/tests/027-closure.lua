#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Exercise the closure mechanism, i.e. Gtk calling a Lua function via a
-- FFI closure.
--
-- Note: it works, but the numerous warnings about memory leaks etc. indicate
-- that it's not working well.

require "gtk"

function compare_func(a, b)
    a = a.value
    b = b.value
    if a == b then return 0 end
    return a < b and -1 or 1
end

seen = {}

-- The iterator function must return a boolean: false to keep going, true to
-- stop.  If it returns something else, the foreach function aborts with an
-- error.
function traverse_func(key, value, user_data)
    key = key.value
    seen[key] = (seen[key] or 0) + 1
    return user_data.value
end

-- Destroy functions.  They receive the value, not the wrapper, and therefore
-- cannot do anything about the wrapper!
function key_destroy(key)
    key:destroy()
end

function value_destroy(value)
    value:destroy()
end

-- has to create a closure
t = gtk.g_tree_new_full(compare_func, nil, key_destroy, value_destroy)

-- add a node to the tree.  parameter as "gpointer", i.e. a wrapper is created
t:insert("a", "value a")

-- add a second node; has to call the compare_func.  This fails...
t:insert("b", "value b")

-- when using an iterator that doesn't return boolean, an error must happen.
rc, msg = pcall(t.foreach, t, traverse_func, nil)
assert(rc == false)

-- a "good" iterator function must work.
v = gtk.void_ptr(false)
t:foreach(traverse_func, v)
v:destroy() -- should happen automatically??

v = gtk.void_ptr(true)
t:foreach(traverse_func, v)
v:destroy()

assert(seen.a == 3)
assert(seen.b == 1)

t:destroy()

collectgarbage("collect")
collectgarbage("collect")

-- show garbage...

