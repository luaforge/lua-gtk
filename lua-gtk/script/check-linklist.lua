#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Read a spec.lua file, extract the linklist, and search through the
-- .c source files of the module to verify that all these functions
-- are actually used.
--
-- Note that functions not directly being called from the source files may
-- still be used through macros.
--

require "script.util"
require "lfs"

function read_source(modname)
    local dir, ar, s, f

    dir = "src/" .. modname
    ar = {}

    for name in lfs.dir(dir) do
	if string.sub(name, -2) == ".c" then
	    f = io.open(dir .. "/" .. name)
	    s = f:read"*a"
	    f:close()
	    ar[#ar + 1] = s
	end
    end

    return table.concat(ar)
end

function main()
    if #arg ~= 1 then
	print("Usage: module name")
	os.exit(1)
    end

    fname = string.format("src/%s/spec.lua", arg[1])
    spec = load_spec(fname)
    if not spec.linklist then
	print("This module doesn't define a linklist.")
	os.exit(0)
    end

    code = read_source(arg[1])

    for _, func in ipairs(spec.linklist) do
	if type(func) == "table" then
	    func = func[1]
	end
	if not string.find(code, func) then
	    print("Unused function:", func)
	end
    end
end

main()

