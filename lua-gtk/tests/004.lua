#! /usr/bin/lua

-- test pixbuf to resize an image.

require "gtk"

ifile = "demo.jpg"
ofile = "demo-out.jpg"

gtk.init()
pixbuf = gtk.gdk_pixbuf_new_from_file_at_size(ifile, 800, 600, nil)
if not pixbuf then
	print("Can't load image from " .. ifile)
	os.exit(1)
end

buffer = pixbuf:save_to_buffer("jpeg")
ofile = io.open(ofile, "w")
ofile:write(buffer)
ofile:close()

