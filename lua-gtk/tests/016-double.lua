#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Example by Miles Bader <miles@gnu.org>

require "gtk"
require "cairo"

assert(cairo.version_string())

w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
w:realize()

c = gdk.cairo_create(w.window)

str = "hello"
t_ext = cairo.new 'text_extents_t'
c:text_extents (str, t_ext)

-- look at the structure
-- gtk.dump_struct(t_ext)

-- read double elements of structures

a = t_ext.width
b = t_ext.height
c = t_ext.x_advance


-- write
t_ext.height = 95.5

-- and read again.  Check that the surrounding fields haven't changed.
assert(t_ext.width == a)
assert(t_ext.height == 95.5)
assert(t_ext.x_advance == c)


