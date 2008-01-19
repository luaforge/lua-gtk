#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Dump a list of function signatures of all supported functions to stdout.
-- by Wolfgang Oertl 2007
--


require "gtk"

function main(ifname)
    local fname

    for line in io.lines(ifname) do
	fname = line:match("^([^,]+)")
	print(gtk.function_sig(fname) or "not found: " .. fname)
    end
end

if not arg[1] then
    print "Parameter: the gtkdata.funcs.txt file as generated during building."
    os.exit(1)
end

main(arg[1])

