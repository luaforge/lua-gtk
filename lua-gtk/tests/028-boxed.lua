#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test that arbitrary Lua values can be stored as boxed values.
require "gtk"

-- create a list store with a column of this boxed type.
store = gtk.list_store_new(1, gtk.boxed_type)
iter = gtk.new "GtkTreeIter"

-- store a value into that.  currently, an explicit cast to boxed is required.
tbl = { _type="boxed" }
store:insert_with_values(iter, 0,
    0, tbl,
    -1)

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

-- explicit boxing
val = gtk.make_boxed_value "The boxed string"
assert(type(val) == "userdata")
val2 = gtk.get_boxed_value(val)
assert(val2 == "The boxed string")

