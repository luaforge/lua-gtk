#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test reading and writing an integer in a structure, and using arbitrary
-- keys.

require "gtk"

x = gtk.new "GtkTreeIter"
y = gtk.new "GtkTreeIter"

-- try to set an existing field of the object
x.stamp = 99
assert(x.stamp == 99)

-- a meta entry must now be present in the metatable
mt = getmetatable(x)
assert(type(mt.stamp) == "userdata")

-- same metatable for same class
assert(mt == getmetatable(y))

-- set to another value
x.stamp = 100
assert(x.stamp == 100)

-- store a non-existing field
x.something = "hello"
assert(x.something == "hello")

-- this value must not be stored in the metatable, which is shared among all
-- objects of this class.  instead, it is stored in the (hidden) environment
-- of the object.
assert(mt.something == nil)

-- not shared between instances; access must fail
rc, msg = pcall(function() foo = y.something end)
assert(rc == false, "y.something must not be set")

