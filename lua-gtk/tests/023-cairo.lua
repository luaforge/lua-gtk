#! /usr/bin/env lua
require "gtk"

cs = gtk.cairo_image_surface_create (gtk.CAIRO_FORMAT_RGB24, 100, 100)
assert(cs)

t = cs:get_type()
assert(type(t) == "userdata")

assert(t:tonumber() == 0)

