#! /usr/bin/lua
require "gtk"
gtk.init()

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

-- integer constants
v = gtk.G_TYPE_INT
assert(type(v) == "number")

-- string constants
v = gtk.GTK_STOCK_OPEN
assert(v == "gtk-open")

