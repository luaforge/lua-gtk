#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Check that certain types are present.

test_performance = false

-- The top level windows (FileChooser and InputDialog) take quite some time
-- to create.  I analyzed this using valgrind (callgrind) and kcachegrind.
if test_performance then
    gnome_debug_flags = { "closure" }
    loops = 10
else
    loops = 1
end

require "gtk"
require "atk"

list = {
    { "gtk", "Window", gtk.WINDOW_TOPLEVEL },
    { "gtk", "FileChooserWidget", gtk.FILE_CHOOSER_ACTION_OPEN },
    { "atk", "Attribute" },
    { "gtk", "InputDialog" },
    { "glib", "SList" },
    { "glib", "Parameter" },
    { "gtk", "AccelGroup" },
    { "gtk", "VBox", false, 10 },
}

for _, args in ipairs(list) do
    print(args[1], args[2])
    for i = 1, loops do
	x = _G[args[1]].new(unpack(args, 2))
    end
end

