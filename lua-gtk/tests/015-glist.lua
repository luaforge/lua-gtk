#! /usr/bin/env lua
require "glib"

-- Helper to show the elements of a list.  It uses the foreach function, which
-- requires callbacks from C to Lua, which requires closures (automatically
-- generated, so you don't have to worry).
function list2string(ls)
   local t = {}
   ls:foreach(function(x) t[#t + 1] = tostring(x.value) end, nil)
   return table.concat(t, ' ')
end


-- create a new g_list with one element
ls = glib.list_append(nil, 10)
assert(ls:length() == 1)

-- append returns the extended list, but (looking at the C source for
-- g_list_append) this is exactly the list that was passed in.
ls:append(20)
ls:append(30)

assert(list2string(ls) == "10 20 30")

x = ls:nth(1)
assert(x.data == 20)

-- test reversal
ls = ls:reverse()
assert(list2string(ls) == "30 20 10")


-- test removal
ls:delete_link(x)
assert(list2string(ls) == "30 10")

-- add some more
ls:append(15)
ls:append(3)
ls:append(94)

-- sort using a callback (in a closure)
ls = ls:sort(function(a, b) return a.value - b.value end)
assert(list2string(ls) == "3 10 15 30 94")


