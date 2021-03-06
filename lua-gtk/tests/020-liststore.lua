#! /usr/bin/env lua
require "gtk"

ls, x = gtk.list_store_newv(8, { glib.TYPE_INT, glib.TYPE_STRING,
	glib.type_from_name("GtkWindowType"), glib.TYPE_BOOLEAN,
	glib.TYPE_DOUBLE, glib.type_from_name("GtkWidgetFlags"),
	glib.type_from_name("GtkWindow"), gnome.boxed_type })
assert(x == nil, "superfluous return value")

-- varargs, no type checking possible.
iter = gtk.new "TreeIter"
ls:insert_with_values(iter, 1,
	0, 99,
	1, "hello",
	2, gtk.WINDOW_TOPLEVEL,
	3, true,
	4, gnome.box(5, "gdouble"),
	5, gtk.CAN_DEFAULT,
	6, gtk.window_new(gtk.WINDOW_TOPLEVEL),
	7, gnome.box { a=1, b=2, c=3 },
	-1)

---------------------------------------------------------------------------
-- test signed integer

val = ls:get_value(iter, 0)
assert(val == 99)

ls:set_value(iter, 0, -20)
val = ls:get_value(iter, 0)
assert(val == -20)

ls:set_value(iter, 0, "234")
val = ls:get_value(iter, 0)
assert(val == 234)

ls:set_value(iter, 0, "-567890")
val = ls:get_value(iter, 0)
assert(val == -567890)

rc, msg = pcall(function() ls:set_value(iter, 0, "99abc") end)
assert(not rc)

rc, msg = pcall(function() ls:set_value(iter, 0, true) end)
assert(not rc)


---------------------------------------------------------------------------
-- test string

val = ls:get_value(iter, 1)
assert(val == "hello")

ls:set_value(iter, 1, "there")
val = ls:get_value(iter, 1)
assert(val == "there")

ls:set_value(iter, 1, 25)
val = ls:get_value(iter, 1)
assert(val == "25")

---------------------------------------------------------------------------
-- test enum/flags

val = ls:get_value(iter, 2)
assert(val == gtk.WINDOW_TOPLEVEL)
ls:set_value(iter, 2, "GTK_WINDOW_TOPLEVEL")
ls:set_value(iter, 2, 0)
ls:set_value(iter, 2, gtk.WINDOW_TOPLEVEL)

rc, msg = pcall(function() ls:set_value(iter, 2, true) end)
assert(not rc)

-- string not found
rc, msg = pcall(function() ls:set_value(iter, 2, "HARHAR") end)
assert(not rc)

-- mismatch in enum type
rc, msg = pcall(function() ls:set_value(iter, 2, gtk.JUSTIFY_LEFT) end)
assert(not rc)


---------------------------------------------------------------------------
-- test boolean

val = ls:get_value(iter, 3)
assert(val == true)

ls:set_value(iter, 3, false)
val = ls:get_value(iter, 3)
assert(val == false)

-- can set boolean from certain strings
ls:set_value(iter, 3, "true")
ls:set_value(iter, 3, "false")
ls:set_value(iter, 3, "0")
ls:set_value(iter, 3, "1")
val = ls:get_value(iter, 3)
assert(val == true)

-- can't set boolean from this string
rc, msg = pcall(function() ls:set_value(iter, 3, "foo") end)
assert(not rc)

-- can't set boolean from number
rc, msg = pcall(function() ls:set_value(iter, 3, 5) end)
assert(not rc)



---------------------------------------------------------------------------
-- test double

val = ls:get_value(iter, 4)
assert(val == 5)
ls:set_value(iter, 4, 6)
val = ls:get_value(iter, 4)
assert(val == 6)
ls:set_value(iter, 4, "7.05")
val = ls:get_value(iter, 4)
assert(val == 7.05)
rc, msg = pcall(function() ls:set_value(iter, 4, "7.05error") end)
assert(not rc)
rc, msg = pcall(function() ls:set_value(iter, 4, true) end)
assert(not rc)



---------------------------------------------------------------------------
-- test flags

val = ls:get_value(iter, 5)
assert(tostring(val) == "GtkWidgetFlags:can-default")

ls:set_value(iter, 5, "GTK_TOPLEVEL | GTK_NO_WINDOW")
val = ls:get_value(iter, 5)
assert(tostring(val) == "GtkWidgetFlags:toplevel|no-window")

ls:set_value(iter, 5, 16+32+64)
val = ls:get_value(iter, 5)
assert(tostring(val) == "GtkWidgetFlags:toplevel|no-window|realized")

ls:set_value(iter, 5, "128|256")
val = ls:get_value(iter, 5)
assert(tostring(val) == "GtkWidgetFlags:mapped|visible")

rc, msg = pcall(function() ls:set_value(iter, 5, "whatever") end)
assert(not rc)

rc, msg = pcall(function() ls:set_value(iter, 5, true) end)
assert(not rc)

rc, msg = pcall(function() ls:set_value(iter, 5, "GTK_STOCK_OK") end)
assert(not rc)



---------------------------------------------------------------------------
-- test objects

val = ls:get_value(iter, 6)
assert(string.match(tostring(val), "^GtkWindow"))

w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
ls:set_value(iter, 6, w)

val = ls:get_value(iter, 6)
assert(w == val)

-- can't set to NIL
rc, msg = pcall(function() ls:set_value(iter, 6, nil) end)
assert(not rc)

-- can't set to other type of widget
rc, msg = pcall(function() ls:set_value(iter, 6, gtk.button_new()) end)
assert(not rc)


---------------------------------------------------------------------------
-- boxed values

val = ls:get_value(iter, 7)
assert(type(val) == "table")
assert(val.a == 1)


