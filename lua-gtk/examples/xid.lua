#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demonstrate the use of a gdk_x11_xxx function; not portable to Windows!
-- see also http://www.daa.com.au/pipermail/pygtk/2005-March/009720.html
--
-- Further a method to replace the __index function of GdkWindow's metatable
-- is shown to add an attribute to GdkWindow, as suggested by Michal
-- Kolodziejczyk, similar to the API presented by PyGTK.
--

require 'gtk'

function create_window()
    local w = gtk.window_new(gtk.GTK_WINDOW_TOPLEVEL)
    w:show()
    -- local xid = gtk.gdk_x11_drawable_get_xid(w.window)
    local xid = w.window.xid
    local lbl = gtk.label_new("This window's XID is " .. xid)
    w:add(lbl)
    w:set_title("XID example")
    w:connect("delete-event", gtk.main_quit)
    w:show_all()
end

-- Install a new metatable for GdkWindow.  The first function called is used
-- just to obtain an arbitrary GdkWindow to modify its metatable.
function add_window_metatable()
    local __MT = getmetatable(gtk.gdk_get_default_root_window())
    local oldindex = __MT.__index
    __MT.__index = function(w, k)
	if k == 'xid' then return gtk.gdk_x11_drawable_get_xid(w) end
	return oldindex(k, v)
    end
end

add_window_metatable()
create_window()
create_window()
create_window()
gtk.main()

