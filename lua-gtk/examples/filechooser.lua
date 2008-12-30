#! /usr/bin/lua
-- vim:sw=4:sts=4
-- Demonstrate a GtkFileChooserDialog, how to interpret the response and how to
-- retrieve multiple results.

require "gtk"

w = gtk.file_chooser_dialog_new("Open Files", nil,
    gtk.FILE_CHOOSER_ACTION_OPEN,
    gtk.STOCK_CANCEL, gtk.RESPONSE_CANCEL,
    gtk.STOCK_OPEN, gtk.RESPONSE_ACCEPT,
    nil)

w:set_select_multiple(true)

while true do
    rc = w:run()

    if rc == gtk.RESPONSE_CANCEL:tonumber() then
	print "cancel"
	break
    end

    if rc == gtk.RESPONSE_ACCEPT:tonumber() then
	print "open"
	list = w:get_filenames()
	list_head = list
	while list do
	    -- gtk.dump_struct(list) -- if you're interested.
	    print(list.data:cast("string"))
	    list = list.next
	end
	list_head:free()
	break
    end

    if rc == gtk.RESPONSE_DELETE_EVENT:tonumber() then
	print "closed"
	break
    end
end

