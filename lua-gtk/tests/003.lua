#! /usr/bin/lua
require "gtk"
gtk.init(nil, nil)

-- test ENUMs

v = gtk.GTK_CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default")

-- the addition is really a bitwise or
v = v + gtk.GTK_CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default")
v = v + gtk.GTK_REALIZED
assert(tostring(v) == "GtkWidgetFlags:realized|can-default")

-- can't add flags of different types
v = v + gtk.GTK_STATE_NORMAL
assert(v == nil)

