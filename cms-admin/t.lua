
require "gtk"
gtk.init()
w = gtk.file_chooser_widget_new(gtk.GTK_FILE_CHOOSER_ACTION_OPEN)
print(w)

