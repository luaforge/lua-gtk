#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Another simple example for the Glade library.
-- by Wolfgang Oertl

require "gtk"
require "gtk.glade"

local widgets

-- Signal handlers for Menu
function window1_destroy_cb()
    gtk.main_quit()
end

function on_menu_quit()
    gtk.main_quit()
end

function on_comboboxentry1_changed(entry)
    local s = entry:get_active_text()
    widgets.comboboxentry_entry1:set_text(s)
end

function on_spinbutton1_value_changed(spin)
    local v = spin:get_value()
    widgets.progressbar1:set_fraction(v/100.0)
end

function main()
    local tree, file

    gtk.init()
    file = string.gsub(arg[0], ".lua", ".glade")
    tree = gtk.glade.read(file)
    widgets = gtk.glade.create(tree, "window1")
    gtk.main()
end

main()
widgets = nil

-- Show widgets that are still referenced.  The list should be empty, at
-- least after the garbage collection has run.

print(collectgarbage("count"), "kB")
collectgarbage("collect")
print(collectgarbage("count"), "kB")

print "** WIDGETS **"
for k, v in pairs(gtk.widgets) do print(v) end
print "** END OF WIDGETS **"

