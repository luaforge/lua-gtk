#! /usr/bin/env lua
-- Test reference counting and memory management.
-- NOTE: only works when debugging functions are available.

require "gtk"

f, msg = pcall(function() return gtk.get_refcount end)
if not f then return end

-- create a new region
r = gtk.new("GdkRegion")
assert(gtk.get_refcount(r) == 0)

-- another method to allocate a region.
r = gtk.gdk_region_new()
assert(gtk.get_refcount(r) == 0)

-- allocated using the "gobject" handler.
w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
assert(gtk.get_refcount(w) == 2)
w:destroy()

-- Gtk now doesn't have a reference to this object anymore, just Lua.
-- Note that it still is a valid object at this point.
assert(gtk.get_refcount(w) == 1)

-- creating a GdkEvent requires a parameter.  It is handled by
-- the "malloc" widget type, which calls gtk_event_free to release it.
e = gtk.new("GdkEvent", gtk.GDK_SCROLL)
assert(gtk.get_refcount(e) == 0)


