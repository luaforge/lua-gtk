#! /usr/bin/env lua
require "gtk"

-- Test GValue handling.

maxint32 = "4294967295"
maxint64a = "1,844674407371e+19"
maxint64b = "1.844674407371e+19"

function assert_ismaxint(v)
    local s = tostring(v)
    assert(s == maxint32 or s == maxint64a or s == maxint64b,
    	"not a maxint: " .. s)
end

v = gtk.new "GValue"

-- initially a GValue is empty.
assert(tostring(v) == "nil")

-- set to a string
v:init(gtk.G_TYPE_STRING)
v:set_string("blah")
assert(tostring(v) == "blah")

-- unset, then set to a boolean
v:unset()
v:init(gtk.G_TYPE_BOOLEAN)
v:set_boolean(true)
assert(tostring(v) == "true")

-- unset, then set to an int
v:unset()
v:init(gtk.G_TYPE_INT)
v:set_int(-99)
assert(tostring(v) == "-99")
assert(tonumber(tostring(v)) == -99)

-- unset, then set to an unsigned int
v:unset()
v:init(gtk.G_TYPE_UINT)
v:set_uint(-1)
assert_ismaxint(v)

-- unset, then set to an unsigned long
v:unset()
v:init(gtk.G_TYPE_ULONG)
v:set_ulong(-1)
assert_ismaxint(v)

-- unset, then set to an unsigned int64
v:unset()
v:init(gtk.G_TYPE_UINT64)
v:set_uint64(-1)
assert_ismaxint(v)

