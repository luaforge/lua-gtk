#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

v = gtk.major_version
assert(type(v) == "number")
v = gtk.minor_version
assert(type(v) == "number")
v = gtk.micro_version
assert(type(v) == "number")


