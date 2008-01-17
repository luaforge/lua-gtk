#! /usr/bin/lua
-- vim:sw=4:sts=4

require "gtk"

w = gtk.combo_box_new()
ls = gtk.list_store_new(2, gtk.G_TYPE_INT, gtk.G_TYPE_STRING)
w:set_model(ls)

-- Creates an alias, because this function returns GtkTreeModel for the
-- existing GtkListStore widget.
ls2 = w:get_model()

