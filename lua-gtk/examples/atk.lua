#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"
require "atk"

-- Experiment with ATK.  Not yet useful

function build_ui()
    w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    w:set_title("ATK experiment")
    a = w:get_accessible()
    w:show_all()

    print(w, a)
    print("name", a:atk_object_get_name())
    print("description", a:atk_object_get_description())
    print("parent", a:get_parent())
end

build_ui()
gtk.main()

