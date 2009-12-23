#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "glib"

l = nil
for _, item in ipairs { "one", "two", "three", 4, 5 } do
    l = glib.list_prepend(l, item)
end
l = l:reverse()

t = {}
l:foreach(function(x) t[#t+1] = x.value end, nil)

