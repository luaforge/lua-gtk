#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- Run gccxml on a simple C file to generate a huge XML file with all the
-- type information.

-- configuration --

tmp_file = "tmpfile.c"
enable_gtkhtml = false

-- end --

---
-- Call pkg-config and retrieve the answer
-- Returns nil on error
--
function pkg_config(package, option)
    local s, fhandle, version 

    s = string.format("pkg-config %s %s", option, package)
    fhandle = io.popen(s)

    if not fhandle then
	-- pkg-config not available?
	return nil
    end

    s = fhandle:read("*l")
    fhandle:close()
    return s
end


---
-- Try to generate the XML file.  Returns 0 if ok, non-zero otherwise.
--
function generate_object(ofname, platform)
    local defs, ofile, s, rc = ""
    local flags
    local defs2 = ""

    ofile = io.open(tmp_file, "w")
    if not ofile then
	print("Can't open output file " .. tmp_file)
	return 1
    end

    if string.match(platform, "win32") then
	defs = "#define G_OS_WIN32\n"
	    .. "#define GDKVAR extern\n"
	    .. "#define __GTK_DEBUG_H__\n"
    end

    if string.match(platform, "linux") then
	defs2 = defs2 .. "#include <gdk/gdkx.h>\n"
	defs = defs .. "#define G_STDIO_NO_WRAP_ON_UNIX\n"
    end

    -- if libgtkhtml-2.0 is available, use that
    if enable_gtkhtml then
	s = pkg_config("libgtkhtml-2.0", "--cflags")
	if s then
	    print "Libgtkhtml is available."
	    flags = s
	    defs2 = defs2 .. "#include <libgtkhtml/gtkhtml.h>\n"
	end
    end

    if not flags then
	flags = pkg_config("gtk+-2.0", "--cflags")
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
#include <glib/gstdio.h>
#include <gio/gio.h>
#include <cairo/cairo.h>
#include <atk/atk-enum-types.h>
]] .. defs2

    ofile:write(s)
    ofile:close()
    s = string.format("gccxml %s -fxml=%s %s", flags, ofname, tmp_file)
    rc = os.execute(s)
    os.remove(tmp_file)

    return rc
end


---
-- Generation of the XML file failed.  Try to download it, but this requires
-- the Gtk version to be known.  If pkg-config doesn't exist, ask the user.
--
function download_interactive(ofname, platform)

    local s, fhandle, version 

    s = string.format("pkg-config --modversion gtk+-2.0")
    fhandle = io.popen(s)

    if not fhandle then
	-- pkg-config not available?
	print "make-xml.lua: What is your Gtk version?"
	version = io.read()
	if not version then return 3 end
    else
	version = fhandle:read("*l")
	fhandle:close()
    end

    print("Your Gtk Version is ", version)
    return download_types_xml(ofname, platform, version)
end


-- List of supported Gtk versions.  Unfortunately, on luaforge a new
-- subdirectory (real or virtual, don't know) is created for each file
-- release, so the URL can't be derived automatically from the version.
urls = {
    ['2.12.1-linux']
	= "http://luaforge.net/frs/download.php/3040/types.xml-2.12.1-linux.gz",
    ['2.12.1-win32']
	= "http://luaforge.net/frs/download.php/3041/types.xml-2.12.1-win32.gz",
}


---
-- If gccxml is not available or fails, try to download with wget or curl.
--
function download_types_xml(ofname, platform, version)

    local s, url, rc, key

    key = string.format("%s-%s", version, platform)
    url = urls[key]
    if not url then
	print("Version " .. key .. " not supported; can't download.")
	return 1
    end

    s = string.format("wget -O %s.gz %s", ofname, url)
    print(s)
    rc = os.execute(s)

    if rc ~= 0 then
	s = string.format("curl -o %s.gz %s", ofname, url)
	print(s)
	rc = os.execute(s)
	if rc ~= 0 then
	    print "Downloading failed!"
	    return 2
	end
    end

    -- unpack the gzip file.
    s = string.format("gunzip -f %s.gz", ofname)
    print(s)
    return os.execute(s)
end

-- MAIN --

repeat
    stop = false
    if arg[1] == "--enable-gtkhtml" then
	enable_gtkhtml = true
	table.remove(arg, 1)
    else
	stop = true
    end
until stop

if not arg[1] or not arg[2] then
    print "Parameters: output file name and the platform."
    return
end

arg[2] = string.lower(arg[2])
rc = generate_object(arg[1], arg[2])
if rc ~= 0 then
    rc = download_interactive(arg[1], arg[2])
end
os.exit(rc)



