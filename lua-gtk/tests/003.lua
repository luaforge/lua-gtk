#! /usr/bin/env lua
require "gtk"

-- test ENUMs

v = gtk.CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default", "v is " .. tostring(v))

-- the addition is really a bitwise or
v = v + gtk.CAN_DEFAULT
assert(tostring(v) == "GtkWidgetFlags:can-default")
v = v + gtk.REALIZED
assert(tostring(v) == "GtkWidgetFlags:realized|can-default")

-- assignment
w = v
assert(tostring(w) == "GtkWidgetFlags:realized|can-default")

-- can't add flags of different types - must raise an error
rc, msg = pcall(function() v = v + gtk.STATE_NORMAL end)
assert(rc == false)

-- unset flags
w = w - gtk.CAN_DEFAULT
assert(tostring(w) == "GtkWidgetFlags:realized")

-- comparison, conversion to integer (possibly negative)
v = gtk.CAN_DEFAULT
w = gtk.REALIZED
assert(v == v)
assert(v ~= w)
assert(v:tonumber() == 8192)
assert(gtk.RESPONSE_OK:tonumber() == -5)

-- can't compare different enums
rc, msg = pcall(function() return gtk.STATE_NORMAL == gtk.WINDOW_TOPLEVEL end)
assert(rc == false)


-- integer constants
v = glib.TYPE_INT
assert(type(v) == "number")

-- string constants
v = gtk.STOCK_OPEN
assert(v == "gtk-open")

-- access a structure with ENUMs in it.  accessor function should be used,
-- though.
tree = gtk.tree_view_new()
sel = tree:get_selection()
assert(sel.type == gtk.SELECTION_SINGLE)

sel.type = gtk.SELECTION_BROWSE
assert(sel.type == gtk.SELECTION_BROWSE)

rc, msg = pcall(function() sel.type = gtk.WINDOW_TOPLEVEL end)
assert(not rc)



