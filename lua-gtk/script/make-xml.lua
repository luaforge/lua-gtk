#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Run gccxml on a simple C file to generate a huge XML file with all the
-- type information.

-- configuration --

tmp_file = "tmpfile.c"

-- end --

function generate_object(ofname, platform)
    local defs, ofile, s = ""

    if not ofname then
	print "Parameter: output file name"
	return
    end

    ofile = io.open(tmp_file, "w")
    if not ofile then
	print("Can't open output file " .. tmp_file)
	return
    end

    if platform == "WIN32" then
	defs = "#define G_OS_WIN32\n"
	    .. "#define GDKVAR extern\n"
	    .. "#define __GTK_DEBUG_H__\n"
    end

    -- #undef __OPTIMIZE_: Avoid trouble with -O regarding __builtin_clzl.
    -- Seems to have no other side effects (XML file exactly the same).
    -- Suggested by Michael Kolodziejczyk on 2007-10-23

    s = [[#undef __OPTIMIZE__
#define GTK_DISABLE_DEPRECATED 1
#define GDK_PIXBUF_ENABLE_BACKEND 1
]] .. defs .. [[
#include <gdk/gdktypes.h>
]] .. defs .. [[
#include <gtk/gtk.h>
#include <cairo/cairo.h>
]]

    ofile:write(s)
    ofile:close()
    s = string.format("gccxml \$(pkg-config --cflags gtk+-2.0) -fxml=%s %s",
	ofname, tmp_file)
    os.execute(s)
    os.execute("unlink " .. tmp_file)
end

generate_object(arg[1], arg[2])

