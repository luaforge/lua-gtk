#! /usr/bin/env lua

-- test pixbuf to resize an image.

require "gtk"
require "lfs"

ifname = "demo.jpg"
ofname = "demo-out.jpg"
osize_target = { [26645]=true, [26615]=true }	-- known valid output sizes
rc = 0

pixbuf = gdk.pixbuf_new_from_file_at_size(ifname, 800, 600, nil)
if not pixbuf then
	print("Can't load image from " .. ifname)
	os.exit(1)
end

buffer = pixbuf:save_to_buffer("jpeg")
ofile = io.open(ofname, "w")
ofile:write(buffer)
ofile:close()

-- if the input file is this known size, then the output size should be
-- as expected.
isize = lfs.attributes(ifname, "size")
if isize == 5770 then
	osize = lfs.attributes(ofname, "size")
	if not osize_target[osize] then
		print(string.format("Output file size is %s, not %s!",
			osize, osize_target))
		rc = 1
	end
end

os.remove(ofname)
os.exit(rc)

