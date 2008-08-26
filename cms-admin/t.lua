
require "gtk"
gtk.init()
w = gtk.file_chooser_widget_new(gtk.FILE_CHOOSER_ACTION_OPEN)
print(w)

