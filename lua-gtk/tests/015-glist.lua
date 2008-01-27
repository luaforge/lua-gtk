#! /usr/bin/env lua
require "gtk"

-- create a new g_list with one element
ls = gtk.g_list_append(nil, 10)
assert(ls:length() == 1)

-- append returns the extended list, but (looking at the C source for
-- g_list_append) this is exactly the list that was passed in.
ls:append(20)
ls:append(30)

-- test the foreach function, which requires callbacks from C to Lua,
-- which requires closures; this is actually tricky, but works :)
sum = 0
ls:foreach(function(x) sum = sum + x end, nil)
assert(sum == 60)

-- ok

