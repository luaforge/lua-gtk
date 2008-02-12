#! /usr/bin/env lua
require "gtk"

-- Test GSList and gtk_stock_list_ids().

list = gtk.stock_list_ids()
list2 = list

n = 0
while list2 do
	s = list2.data:cast("string")
	assert(type(s) == "string")
	list2 = list2:nth(1)
	n = n + 1
end

-- near 100
assert(n > 50)

-- frees the whole list including the strings in it (handled by an override),
-- and the list itself.
list:free()

-- must now be something like "GSList at 0x80a1cdc/(nil)"
s = tostring(list)
assert(string.find(s, "nil"), "GSList hasn't been freed properly")


