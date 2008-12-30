#! /usr/bin/env lua
require "cairo"

cs = cairo.image_surface_create (cairo.FORMAT_RGB24, 100, 100)
assert(cs)

t = cs:get_type()
assert(type(t) == "userdata")

assert(t:tonumber() == 0)

