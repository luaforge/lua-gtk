#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Dump a list of function signatures of all supported functions to stdout.
-- by Wolfgang Oertl 2007
--


function main(module_name, ifname)
    local fname
    local ar = {}
    local mod = require(module_name)

    -- get all functions, then sort
    for line in io.lines(ifname) do
	fname = line:match("^([^,]+)")
	ar[#ar + 1] = fname
    end

    table.sort(ar)

    for _, fname in ipairs(ar) do
	local rc, msg = pcall(function()
	    print(gnome.function_sig(mod, fname, 20)
		or "* " .. fname .. ": not found")
	end)
	if not rc then print("* " .. fname .. ": " .. msg) end
    end
end

if not arg[2] then
    print "Arguments: [module name] [functions.txt]"
    print "The functions.txt file may include a path."
    os.exit(1)
end

main(arg[1], arg[2])

