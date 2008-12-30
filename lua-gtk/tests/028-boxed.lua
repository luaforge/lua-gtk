#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test that arbitrary Lua values can be stored as boxed values.
require "gtk"

-- create a list store with a column of this boxed type.
store = gtk.list_store_new(1, gnome.boxed_type)
iter = gtk.new "TreeIter"

-- store a value into that.  currently, an explicit cast to boxed is required.
tbl = { _type="boxed", name="One" }
store:insert_with_values(iter, 0,
    0, tbl,
    -1)
collectgarbage "collect"

-- retrieve that value again.
if true then
    val = store:get_value(iter, 0)
    assert(type(val) == "table")
    assert(val == tbl)
end

-- set it to something else
store:set_value(iter, 0, 99)

if true then
    val = store:get_value(iter, 0)
    assert(type(val) == "number")
    assert(val == 99)
end

store:set_value(iter, 0, nil)
val = store:get_value(iter, 0)
assert(val == nil)

-- explicit boxing of a string
val = gnome.box "The boxed string"
assert(type(val) == "userdata")
assert(val.value == "The boxed string")
store:set_value(iter, 0, val)
val2 = store:get_value(iter, 0)
assert(type(val2) == "string")
assert(val2 == val.value)

-- same for a table
val = gnome.box { field1=10, field2=20, field3=30 }
assert(val.field1 == 10)
assert(val.field2 == 20)
assert(val.value.field3 == 30)
val.field4 = 40
assert(val.field4 == 40)

-- All GBoxed values must be freed properly by garbage collection; check that.
val = nil
store = nil
collectgarbage "collect"
assert(gnome.box_debug() == 0)

