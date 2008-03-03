#! /usr/bin/env lua

require "gtk"

x = gtk.button_new_with_label "hello"

-- flags are not defined as ENUM, but a simple integer.
x.flags = x.flags + gtk.GTK_CAN_DEFAULT
assert(x.flags ~= 0)

