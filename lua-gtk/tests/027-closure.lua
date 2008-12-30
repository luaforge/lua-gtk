#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Exercise the closure mechanism, i.e. Gtk calling a Lua function via a
-- FFI closure.  At the same time, demonstrate how void* arguments are
-- handled.
--

require "gtk"
-- gtk.set_debug_flags("closure")

compare_count = 0

-- Comparison function for insertion into the g_tree.
function compare_func(a, b, data)
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

-- Destroy a key or value
function destroy_it(v)
    v:destroy()
end

-- has to create a closure
cl = { gnome.closure(compare_func), gnome.closure(destroy_it) }
t = glib.tree_new_full(cl[1], nil, cl[2], cl[2])
t._closures = cl
cl = nil

-- Add some nodes to the tree.  Arguments are "gpointer", i.e. void* wrappers
-- are created for key and value.  Note that gnome.void_ptr is NOT used, so no
-- Lua object is created for the void* wrapper, and the void* wrappers will not
-- be freed automatically.

for i = 1, 100 do
    t:insert(tostring(i), "value " .. tostring(i))
end

-- demonstrate that the wrappers created so far are not freed prematurely.
collectgarbage "collect" 

-- when using an iterator that doesn't return boolean, an error must happen.
rc, msg = pcall(t.foreach, t, traverse_func, gnome.void_ptr(nil))
assert(rc == false)

-- a "good" iterator function returns a boolean.  In the first case, it
-- returns false and thus only touches the first item.
t:foreach(traverse_func, gnome.void_ptr(false))

-- Now traverse all items.
t:foreach(traverse_func, gnome.void_ptr(true))

assert(seen["1"] == 3)
assert(seen["2"] == 1)
assert(seen["100"] == 1)

-- insert some other interesting things
t:insert("key 1", { 1, 3, 4, 5 })
t:insert("key 2", seen)
t:insert("key 3", function() return true end)

-- use the void_ptr wrapper to avoid a missing free() call
assert(t:remove(gnome.void_ptr("3")))
assert(t:remove(gnome.void_ptr("key 2")))

-- destroy all remaining keys and values, and the tree itself.
t:destroy()

-- check that no wrappers remain allocated.
collectgarbage "collect" 
gnome.dump_vwrappers()

-- statistics:
--  number of times the compare_function was called
--  number of void* wrappers still allocated
--  number of void* wrapper allocations in total: number of keys and values
--    + 3 void_ptr calls
--  number of Lua objects created for void* wrappers: lots...
--
-- print(compare_count, gnome.get_vwrapper_count())
assert(gnome.get_vwrapper_count() == 0)

