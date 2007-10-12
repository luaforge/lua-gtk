#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Simple example of a window with one button that is destoyed when clicked.
-- It adds another one instead that quits the application.

require "gtk"


-- Avoid main_quit complain about extra parameters.  This would happen if
-- you provide gtk.main_quit as handler for the clicked event.
function quit()
    gtk.main_quit()
end

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
    button:connect('clicked', quit)
end

-- Change the button on click; same effect as the above function.
function make_quit_button_b(button)
    button:set_label("Quit")
    button:connect('clicked', quit)
end


-- Create the main window.
gtk.init()
win = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
win:set_title("Button Demo")
win:connect('destroy', quit)
win:show()

-- a button that will destroy itself when clicked.
button = gtk.button_new_with_label("Click me")
win:add(button)
button:show()
button:connect('clicked', make_quit_button_a)

gtk.main()

