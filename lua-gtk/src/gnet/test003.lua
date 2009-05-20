#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gnet"

s = "Hello, World!"
x = gnet.sha_new(s, #s)
x:final()
s2 = x:get_digest()
print(s2, #s2, gnet.SHA_HASH_LENGTH)
print(x:get_string())


