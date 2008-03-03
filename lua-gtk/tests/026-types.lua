#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Check that certain types are present.

require "gtk"

test_performance = false

-- The top level windows (FileChooser and InputDialog) take quite some time
-- to create.  I analyzed this using valgrind (callgrind) and kcachegrind.
if test_performance then
    gtk.set_debug_flags("valgrind")
    loops = 10
else
    loops = 1
end

list = {
    { "GtkWindow", gtk.GTK_WINDOW_TOPLEVEL },
    { "GtkFileChooserWidget", gtk.GTK_FILE_CHOOSER_ACTION_OPEN },
    { "AtkAttribute" },
    { "GtkInputDialog" },
    { "GSList" },
    { "GParameter" },
    { "GtkAccelGroup" },
    { "GtkVBox", false, 10 },
}

for _, args in ipairs(list) do
    print(args[1])
    for i = 1, loops do
	x = gtk.new(unpack(args))
    end
end

