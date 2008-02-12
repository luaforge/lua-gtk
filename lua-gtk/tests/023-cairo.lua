#! /usr/bin/env lua
require "gtk"

cs = gtk.cairo_image_surface_create (gtk.CAIRO_FORMAT_RGB24, 100, 100)
print(cs)
gtk.dump_struct(cs)
t = cs:get_type()
print(t)
print(type(t))
print(t:tonumber())

