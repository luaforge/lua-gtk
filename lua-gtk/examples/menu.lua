#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate the use of a callback that returns values for output
-- arguments.
--

require "gtk"

menu = gtk.menu_new()
menuItem = gtk.image_menu_item_new_from_stock(gtk.STOCK_ABOUT, nil)
menuItem:connect('activate', gtk.main_quit)
menu:append(menuItem)

menuItem = gtk.image_menu_item_new_from_stock(gtk.STOCK_QUIT, nil)
menuItem:connect('activate', gtk.main_quit)
menu:append(menuItem)

---
-- Function is called to compute the popup position.
-- Note: x, y, and push_in are output arguments (int *, boolean *).  You
-- have to return them in this order after the function's return
-- value (in this case, none, because it returns void).
--
function position_func(menu, x, y, push_in, user_data)
    x = x - 100
    return x, y, push_in
end
menu:show_all()

now = gtk.get_current_event_time()
menu:popup(nil, nil, position_func, nil, 3, now)

gtk.main()

