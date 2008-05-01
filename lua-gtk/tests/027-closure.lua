#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Exercise the closure mechanism, i.e. Gtk calling a Lua function via a
-- FFI closure.  At the same time, demonstrate how void* arguments are
-- handled.
--

require "gtk"

compare_count = 0

-- Comparison function for insertion into the g_tree.
function compare_func(a, b)
    compare_count = compare_count + 1
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

-- Add some nodes to the tree.  Arguments are "gpointer", i.e. void* wrappers
-- are created for key and value.  Note that gtk.void_ptr is NOT used, so no
-- Lua object is created for the void* wrapper, and the void* wrappers will not
-- be freed automatically.

for i = 1, 100 do
    t:insert(tostring(i), "value " .. tostring(i))
end

-- demonstrate that the wrappers created so far are not freed prematurely.
collectgarbage("collect")
collectgarbage("collect")

-- when using an iterator that doesn't return boolean, an error must happen.
rc, msg = pcall(t.foreach, t, traverse_func, gtk.void_ptr(nil))
assert(rc == false)

-- a "good" iterator function returns a boolean.  In the first case, it
-- returns false and thus only touches the first item.
t:foreach(traverse_func, gtk.void_ptr(false))

-- Now traverse all items.
t:foreach(traverse_func, gtk.void_ptr(true))

assert(seen["1"] == 3)
assert(seen["2"] == 1)
assert(seen["100"] == 1)

-- destroy all keys and values.
t:destroy()

-- check that no wrappers remain allocated.
collectgarbage("collect")

-- statistics:
--  number of times the compare_function was called
--  number of void* wrappers still allocated
--  number of void* wrapper allocations in total: number of keys and values
--    + 3 void_ptr calls
--  number of Lua objects created for void* wrappers: lots...
--
print(compare_count, gtk.get_vwrapper_count())
assert(gtk.get_vwrapper_count() == 0)

