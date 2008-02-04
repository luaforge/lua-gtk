#! /usr/bin/env lua
require "gtk"

-- test pango_tab_array functions, especially pango_tab_array_get_tabs,
-- which has a special override function.

ta = gtk.pango_tab_array_new_with_positions(2, true,
	gtk.PANGO_TAB_LEFT, 10,
	gtk.PANGO_TAB_LEFT, 30)
assert(ta:get_size() == 2)

a, b = ta:get_tab(0, 0, nil)
assert(a == gtk.PANGO_TAB_LEFT)
assert(b == 10)

ta:set_tab(0, gtk.PANGO_TAB_LEFT, 15)
-- ta:set_tab(1, gtk.PANGO_TAB_LEFT, 30)

a, b = ta:get_tab(0, 0, nil)
assert(a == gtk.PANGO_TAB_LEFT)
assert(b == 15)

ar1 = {}
ar2 = {}

ta:get_tabs(ar1, ar2)

assert(#ar1 == 2)
assert(#ar2 == 2)

assert(ar1[1] == gtk.PANGO_TAB_LEFT)
assert(ar1[2] == gtk.PANGO_TAB_LEFT)

assert(ar2[1] == 15)
assert(ar2[2] == 30)

