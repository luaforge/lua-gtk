#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Simple example of a window with one button that is destoyed when clicked.
-- It adds another one instead that quits the application.

require "gtk"

--
-- Destroy the button on click, and add a Quit button instead.
-- Note that a Window can only contain one child widget; to have two or more
-- another container would have to be used (like GtkVBox).
--
function make_quit_button_a(button)
    button:destroy()
    button = gtk.button_new_with_label("Quit")
    win:add(button)
    button:show()
    button:connect('clicked', gtk.main_quit)
end

-- Change the button on click; same effect as the above function.
function make_quit_button_b(button)
    button:set_label("Quit")
    button:connect('clicked', gtk.main_quit)
end


-- Create the main window.
win = gtk.window_new(gtk.WINDOW_TOPLEVEL)
win:set_title("Button Demo")
win:connect('destroy', gtk.main_quit)
win:show()

-- a button that will destroy itself when clicked.
button = gtk.button_new_with_label("Click me")
win:add(button)
button:show()
button:connect('clicked', make_quit_button_a)

gtk.main()

