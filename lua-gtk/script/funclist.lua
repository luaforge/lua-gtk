#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Dump a list of function signatures of all supported functions to stdout.
-- by Wolfgang Oertl 2007
--


require "gtk"

---
-- Generate a function signature
--
-- @param fname    Name of the function
--
function func_sig(fname)
    return gtk.function_sig(fname)
end


function main(ifname)
    local fname

    for line in io.lines(ifname) do
	fname = line:match("^([^,]+)")
	print(func_sig(fname))
    end
end

if not arg[1] then
    print "Parameter: the gtkdata.funcs.txt file as generated during building."
    os.exit(1)
end

main(arg[1])

