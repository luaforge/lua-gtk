#! /usr/bin/env lua
-- vim:sw=4:sts=4
require "gtk"

-- Put some text into the selection.  While this program is running, you can
-- paste it somewhere.
atom = gdk.atom_intern("PRIMARY", true)
assert(atom)
clipboard = gtk.clipboard_get(atom)
s = "Clipboard Content from " .. arg[0]
clipboard:set_text(s, #s)

-- show a window with a close button.  The selection will not be available
-- after this program exits.

w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
b = gtk.button_new_with_label "Close"
w:add(b)
b:connect('clicked', gtk.main_quit)
w:connect('destroy', gtk.main_quit)
w:show_all()

gtk.main()

-- to get rid of the warning "GtkClipboard prematurely finalized", the display
-- must be closed before GtkClipboard is (automatically) freed.
display = clipboard:get_display()
display:close()

