#! /usr/bin/env lua
-- vim=sw:4:sts=4

require "gtk"

local png = gdk.pixbuf_new_from_file("036.png", nil)
assert(png, "Can't load file 036.png")

local pixmap, bitmap = png:render_pixmap_and_mask(gnome.NIL, gnome.NIL, 128)
assert(pixmap)
assert(pixmap:lg_get_type() == "GdkPixmap")
assert(bitmap)
assert(bitmap:lg_get_type() == "GdkBitmap")

