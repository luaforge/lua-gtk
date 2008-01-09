#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Simple Example for the Glade library.

require "gtk"
require "gtk.glade"

-- Signal handlers for Menu
function on_quit1_activate()
    gtk.main_quit()
end

function main()
    local tree, widgets, fname

    fname = arg[1] or string.gsub(arg[0], "%.lua", ".glade")
    tree = gtk.glade.read(fname)
    widgets = gtk.glade.create(tree, "window1")
    gtk.main()
end

main()

-- Show widgets that are still referenced.  The list should be empty, at
-- least after the garbage collection has run.

print(collectgarbage("count"), "kB")
collectgarbage("collect")
print(collectgarbage("count"), "kB")

-- print "** WIDGETS **"
-- for k, v in pairs(gtk.widgets) do print(v) end
-- print "** END OF WIDGETS **"

