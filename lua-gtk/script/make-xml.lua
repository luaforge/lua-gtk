#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Run gccxml on a simple C file to generate a huge XML file with all the
-- type information.

-- configuration --

tmp_file = "tmpfile.c"

-- end --

function generate_object(ofname)
    local ofile, s

    if not ofname then
	print "Parameter: output file name"
	return
    end

    ofile = io.open(tmp_file, "w")
    if not ofile then
	print("Can't open output file " .. tmp_file)
	return
    end

    s = "#define GTK_DISABLE_DEPRECATED 1\n"
    s = s .. "#define GDK_PIXBUF_ENABLE_BACKEND 1\n"
    s = s .. "#include <gtk/gtk.h>\n"
    s = s .. "#include <cairo/cairo.h>\n"

    ofile:write(s)
    ofile:close()
    s = string.format("gccxml \$(pkg-config --cflags gtk+-2.0) -fxml=%s %s",
	ofname, tmp_file)
    os.execute(s)
    os.execute("unlink " .. tmp_file)
end

generate_object(arg[1])

