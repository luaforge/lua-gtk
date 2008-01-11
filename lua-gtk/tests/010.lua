
require "gtk"

-- ENUMs can now be converted to numbers.  Can be useful when trying to
-- compare the result of gtk_dialog_run() with these constants.
assert(gtk.GTK_RESPONSE_OK:tonumber() == -5)

