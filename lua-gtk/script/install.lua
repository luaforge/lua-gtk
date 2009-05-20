#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Simple installation script for LuaGnome.  Run as root.
-- by Wolfgang Oertl
--
-- Argument: build directory

require "lfs"

---
-- Install a file or directory into the first applicable target directory from
-- the Lua search path.
--
-- @param ar  String with ";" delimited search paths
-- @param pattern  What to replace in the search path
-- @param source  File or directory in the current directory to install
--
function do_install(ar, pattern, source, basename)
    local dest, cmd

    for path in string.gmatch(ar, "[^;]+") do
	-- if too short, then it's ./?.so or something.
	if path:len() > 10 then
	    dest = path:gsub(pattern, basename)
	    if dest ~= path then
		cmd = string.format("cp -a %s %s", source, dest)
--[[		if lfs.attributes(dest2, "mode") then
		    print("Destination exists:", dest2)
		    break
		end
--]]
		print(cmd)
		os.execute(cmd)
		break
	    end
	end
    end
end

build_dir = arg[1]
assert(build_dir, "Please provide the build directory, or run 'make install'.")
for dir in lfs.dir(build_dir) do
    basename = dir .. ".so"
    file = string.format("%s/%s/%s", build_dir, dir, basename)
    if lfs.attributes(file, "mode") then
	do_install(package.cpath, "%?.so", file, basename)
    end
end

do_install(package.path, "%?.lua", "lib", "gtk")

