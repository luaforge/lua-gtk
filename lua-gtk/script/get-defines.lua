#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Certain #defines from the Gtk/Gdk include files are relevant, but not
-- included in types.xml.  Extract them manually and write a list of extra
-- ENUMs.
-- Copyright (C) 2007 Wolfgang Oertl

require "bit"

-- add the directory where this Lua file is in to the package search path.
package.path = package.path .. ";" .. string.gsub(arg[0], "%/[^/]+$", "/?.lua")
require "common"

enums = {}

function parse_file(fname)
    local line2 = ""

    for line in io.lines(fname) do
	-- emulate "continue" command
	while true do
	    -- continuation
	    if string.match(line, "\\$") then
		line2 = line2 .. string.sub(line, 1, -2)
		break
	    end

	    line = line2 .. line
	    line2 = ""

	    -- string defines
	    local name, value = string.match(line,
		"^#define ([A-Z_]+) +\"([^\"]+)\"")
	    if name and value then
		print(encode_enum(name, value, 0))
		break
	    end

	    -- G_TYPE defines
	    name, value = string.match(line,
		"^#define ([A-Z0-9_]+)%s+G_TYPE_MAKE_FUNDAMENTAL%s+%((%d+)%)")
	    if name and value then
		-- *4 is what G_TYPE_MAKE_FUNDAMENTAL does.
		print(encode_enum(name, value * 4, 0))
		break
	    end

	    -- nothing usable in this line, skip.
	    break
	end
    end
end

-- main --
path_gtk = "/usr/include/gtk-2.0"
path_glib = "/usr/include/glib-2.0"
parse_file(path_gtk .. "/gtk/gtkstock.h")
parse_file(path_glib .. "/gobject/gtype.h")

