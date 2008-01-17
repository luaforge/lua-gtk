#! /usr/bin/lua
require "gtk"

-- test ENUMs

v = gtk.GTK_CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default", "v is " .. tostring(v))

-- the addition is really a bitwise or
v = v + gtk.GTK_CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default")
v = v + gtk.GTK_REALIZED
assert(tostring(v) == "GtkWidgetFlags:realized|can-default")

-- assignment
w = v
assert(tostring(w) == "GtkWidgetFlags:realized|can-default")

-- can't add flags of different types - must raise an error
rc, msg = pcall(function() v = v + gtk.GTK_STATE_NORMAL end)
assert(rc == false)

-- unset flags
w = w - gtk.GTK_CAN_DEFAULT
assert(tostring(w) == "GtkWidgetFlags:realized")

-- comparison, conversion to integer (possibly negative)
v = gtk.GTK_CAN_DEFAULT
w = gtk.GTK_REALIZED
assert(v == v)
assert(v ~= w)
assert(v:tonumber() == 8192)
assert(gtk.GTK_RESPONSE_OK:tonumber() == -5)

-- can't compare different enums
rc, msg = pcall(function() return gtk.GTK_STATE_NORMAL == gtk.GTK_WINDOW_TOPLEVEL end)
assert(rc == false)


-- integer constants
v = gtk.G_TYPE_INT
assert(type(v) == "number")

-- string constants
v = gtk.GTK_STOCK_OPEN
assert(v == "gtk-open")

