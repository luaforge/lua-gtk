#! /usr/bin/lua
-- vim:sw=4:sts=4
-- Demonstrate a GtkFileChooserDialog, how to interpret the response and how to
-- retrieve multiple results.

require "gtk"

w = gtk.file_chooser_dialog_new("Open Files", nil,
    gtk.GTK_FILE_CHOOSER_ACTION_OPEN,
    gtk.GTK_STOCK_CANCEL, gtk.GTK_RESPONSE_CANCEL,
    gtk.GTK_STOCK_OPEN, gtk.GTK_RESPONSE_ACCEPT,
    nil)

w:set_select_multiple(true)

while true do
    rc = w:run()

    if rc == gtk.GTK_RESPONSE_CANCEL:tonumber() then
	print "cancel"
	break
    end

    if rc == gtk.GTK_RESPONSE_ACCEPT:tonumber() then
	print "open"
	list = w:get_filenames()
	while list do
	    -- gtk.dump_struct(list) -- if you're interested.
	    print(list.data:cast("string"))
	    list = list.next
	end
	break
    end

    if rc == gtk.GTK_RESPONSE_DELETE_EVENT:tonumber() then
	print "closed"
	break
    end
end

