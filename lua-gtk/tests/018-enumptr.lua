#! /usr/bin/env lua
require "gtk"
require "atk"

-- test enum* and enum** types

-- enum* as output parameter
img = gtk.image_new_from_stock(gtk.STOCK_OPEN, gtk.ICON_SIZE_BUTTON)
assert(img)

stock_id, size = img:get_stock(gnome.NIL, 0)
assert(stock_id == gtk.STOCK_OPEN)
assert(size == gtk.ICON_SIZE_BUTTON)


-- enum* as input (array of enums)
set = atk.state_set_new()
assert(set:is_empty())

set:add_states({atk.STATE_ACTIVE, atk.STATE_ENABLED, atk.STATE_FOCUSABLE}, 3)

-- exercise the atk_state_set API
assert(not set:is_empty())
assert(set:contains_state(atk.STATE_ENABLED))
assert(set:contains_states({atk.STATE_ACTIVE, atk.STATE_ENABLED}, 2))
set:remove_state(atk.STATE_ACTIVE)
assert(not set:contains_state(atk.STATE_ACTIVE))
set:clear_states()
assert(set:is_empty())


ar = {}
gdk.query_visual_types(ar, 0)
assert(#ar > 0)

-- enum** as output.  existing values in the output table are removed.
icon_set = gtk.icon_factory_lookup_default(gtk.STOCK_OPEN)
sizes = {1, 2, 3, 4, 5, 6, 7, 8, ["test"] = 9}
gtk.icon_set_get_sizes(icon_set, sizes, 0)

assert(#sizes == 6)
assert(sizes[1] == gtk.ICON_SIZE_MENU)


