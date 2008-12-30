#! /usr/bin/env lua
-- Test reference counting and memory management.
-- NOTE: only works when debugging functions are available.

require "gtk"

f, msg = pcall(function() return gnome.get_refcount end)
if not f then return end

-- create a new region
r = gdk.new "Region"
assert(gnome.get_refcount(r) == 0)

-- another method to allocate a region.
r = gdk.region_new()
assert(gnome.get_refcount(r) == 0)

-- allocated using the "gobject" handler.
w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
assert(gnome.get_refcount(w) == 2)
w:destroy()

-- Gtk now doesn't have a reference to this object anymore, just Lua.
-- Note that it still is a valid object at this point.
assert(gnome.get_refcount(w) == 1)

-- creating a GdkEvent requires a parameter.  It is handled by
-- the "malloc" widget type, which calls gtk_event_free to release it.
e = gdk.new("Event", gdk.SCROLL)
assert(gnome.get_refcount(e) == 0)


