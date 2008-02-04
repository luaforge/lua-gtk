#! /usr/bin/env lua
require "gtk"
-- test enum* and enum** types

-- enum* as output parameter
img = gtk.image_new_from_stock(gtk.GTK_STOCK_OPEN, gtk.GTK_ICON_SIZE_BUTTON)
assert(img)

stock_id, size = img:get_stock(nil, 0)
assert(stock_id == gtk.GTK_STOCK_OPEN)
assert(size == gtk.GTK_ICON_SIZE_BUTTON)


-- enum* as input (array of enums)
set = gtk.atk_state_set_new()
assert(set:is_empty())

set:add_states({gtk.ATK_STATE_ACTIVE, gtk.ATK_STATE_ENABLED,
	gtk.ATK_STATE_FOCUSABLE}, 3)

-- exercise the atk_state_set API
assert(not set:is_empty())
assert(set:contains_state(gtk.ATK_STATE_ENABLED))
assert(set:contains_states({gtk.ATK_STATE_ACTIVE, gtk.ATK_STATE_ENABLED}, 2))
set:remove_state(gtk.ATK_STATE_ACTIVE)
assert(not set:contains_state(gtk.ATK_STATE_ACTIVE))
set:clear_states()
assert(set:is_empty())


ar = {}
gtk.gdk_query_visual_types(ar, 0)
assert(#ar > 0)

-- enum** as output.  existing values in the output table are removed.
icon_set = gtk.icon_factory_lookup_default(gtk.GTK_STOCK_OPEN)
sizes = {1, 2, 3, 4, 5, 6, 7, 8, ["test"] = 9}
gtk.icon_set_get_sizes(icon_set, sizes, 0)

assert(#sizes == 6)
assert(sizes[1] == gtk.GTK_ICON_SIZE_MENU)


