#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test access to non-byte structure members, i.e. bit fields etc.

require "gtk"

c = gtk.hbox_new(false, 0)

-- relevant part of GtkContainer:
-- { 18069, 528, 1, 13, 0 }, /* need_resize */
-- { 18081, 529, 2, 13, 0 }, /* resize_mode */
-- { 18093, 531, 1, 13, 0 }, /* reallocate_redraws */

-- try a 16 bit field
c.border_width = 65535
assert(c.border_width == 65535)

-- initialized to zero.
assert(c.need_resize == 0)
assert(c.resize_mode == 0)
assert(c.reallocate_redraws == 0)

-- set the bit
c.need_resize = 1
assert(c.need_resize == 1)

-- this results in zero, because it's just one bit wide (overflow).
c.need_resize = 2
assert(c.need_resize == 0)

-- two bit wide
c.resize_mode = 3
assert(c.resize_mode == 3)

c.resize_mode = 4
assert(c.resize_mode == 0)

-- mustn't change
assert(c.need_resize == 0)
assert(c.reallocate_redraws == 0)

