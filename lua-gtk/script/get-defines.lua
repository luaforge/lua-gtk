#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Certain #defines from the Gtk/Gdk include files are relevant, but not
-- included in types.xml.  Extract them manually and write a list of extra
-- ENUMs.
-- Copyright (C) 2007 Wolfgang Oertl

enums = {}

function parse_file(fname)
    local line2 = ""

    for line in io.lines(fname) do
	if string.match(line, "\\$") then
	    line2 = line2 .. string.sub(line, 1, -2)
	else
	    line = line2 .. line
	    line2 = ""

	    local name, value = string.match(line,
		"^#define ([A-Z_]+) +\"([^\"]+)\"")
	    if name and value then
		enums[name] = encode_value(value)
	    end
	end
    end
end

function encode_value(val)
    local s = ""

    if type(val) == "string" then
	s = '\\000\\000' .. val
    else
	error("unhandled type " .. type(val) .. " in encode_value")
    end

    return s
end

function write_output(ofile)
    for k, v in pairs(enums) do
	print(string.format("%s,%s", k, v))
    end
end

-- main --
path = "/usr/include/gtk-2.0"
parse_file(path .. "/gtk/gtkstock.h")
write_output()

