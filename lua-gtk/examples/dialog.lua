#! /usr/bin/env lua
-- Show a dialog

require "gtk"

dialog = gtk.dialog_new_with_buttons ("Message", nil,
	gtk.GTK_DIALOG_DESTROY_WITH_PARENT,
	gtk.GTK_STOCK_OK, gtk.GTK_RESPONSE_ACCEPT,
	gtk.GTK_STOCK_CANCEL, gtk.GTK_RESPONSE_CANCEL,
	nil)
entry = gtk.entry_new()
entry:set_alignment(0.9)

--  Add the label, and show everything we've added to the dialog.
dialog.vbox:add(entry)
dialog:set_default_response(gtk.GTK_RESPONSE_ACCEPT)
dialog:show_all()

-- Run the dialog, print the response.
rc = dialog:run()
print(rc, rc == gtk.GTK_RESPONSE_ACCEPT:tonumber() and entry:get_text() or "")
dialog:destroy()

