#! /usr/bin/env lua
require "gtk"

ls, x = gtk.list_store_newv(3, {gtk.G_TYPE_INT, gtk.G_TYPE_STRING,
	gtk.g_type_from_name("GtkWindowType")})
assert(x == nil, "superfluous return value")

-- varargs, no type checking possible.
iter = gtk.new "GtkTreeIter"
ls:insert_with_values(iter, 1,
	0, 99,
	1, "hello",
	2, gtk.GTK_WINDOW_TOPLEVEL,
	-1)

-- retrieve integer
foo = ls:get_value(iter, 0, nil)
assert(foo == 99)

-- set and retrieve signed integer
ls:set_value(iter, 0, -20)
foo = ls:get_value(iter, 0, nil)
assert(foo == -20)

-- retrieve ENUM
foo = ls:get_value(iter, 2, nil)
assert(foo == gtk.GTK_WINDOW_TOPLEVEL)

-- retrieve string
foo = ls:get_value(iter, 1, nil)
assert(foo == "hello")

-- try to set with wrong ENUM type; must fail
rc, msg = pcall(function() ls:set_value(iter, 2, gtk.GTK_JUSTIFY_LEFT) end)
assert(not rc)

