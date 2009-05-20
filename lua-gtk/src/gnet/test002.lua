#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gnet"

s = "Hello, World!"
x = gnet.md5_new(s, #s)
x:final()
s2 = x:get_digest()
print(s2, #s2)
print(x:get_string())


