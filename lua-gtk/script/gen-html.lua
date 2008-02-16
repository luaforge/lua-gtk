#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Generate the HTML pages for the website of lua-gtk.
--
-- Invoke this with the current directory set to .../html_in.
-- It recursively reads all files, processes the .html files,
-- copies .css and .png.  Output directory is defined below.
--
-- Copyright (C) 2007 Wolfgang Oertl <wolfgang.oertl@gmail.com>
--
-- TODO
--  - don't hard code the menu
--  - option parsing for output directory, input files etc.
--

require "luadoc.lp"
require "lfs"

html_header = [[
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" 
    "http://www.w3.org/TR/html4/strict.dtd">
<html>

<head>
 <meta name="description" content="The Lua-Gtk Homepage #TITLE#">
 <meta name="keywords" content="Lua, Gtk">
 <title>Lua-Gtk #TITLE#</title>
 <link rel="stylesheet" href="lua-gtk.css" type="text/css">
</head>

<body>

<div id="header">
 <img width=128 height=128 border=0 alt="Lua-Gtk Logo" src="img/lua-gtk-logo.png"/>
 <p>Binding to Gtk 2 for Lua</p>
 <p>
  <a href="index.html">Home</a> &middot;
  <a href="examples1.html">Examples 1</a> &middot;
  <a href="examples2.html">Examples 2</a> &middot;
  <a href="reference.html">Reference</a>
 </p>
</div>

<div id="content">
]]

html_trailer = [[
</div>
</body>
</html>
]]

output_dir = "../build/html/"

-- The environment available to the functions in the template.
env = {

   io = io, 

    -- page header
    html_header = function(title)
	-- avoid the second return value (number of substitutions) to be
	-- returned, too.
	local s = string.gsub(html_header, "#TITLE#", title)
	return s
    end,

    html_trailer = function()
	return html_trailer
    end,

    -- extract a function from a Lua source file
    copy_function = function(file, name)
	local state = 0
	local res = {}

	for line in io.lines("../" .. file) do
	    if state == 0 then
		if string.match(line, "function " .. name) then
		    state = 1
		end
	    end

	    if state == 1 then
		table.insert(res, line)
		if string.match(line, "^end") then
		    break
		end
	    end
	end

	return table.concat(res, "\n")
    end,

}


---
-- Make sure all the directories leading to the given file exist.
-- The file itself might not exist yet.
--
-- @param path  Path and filename.
--
function _mkdir(path)
    local s = ""
    for w in string.gmatch(path, "[^/]+/") do
	s = s .. w
	lfs.mkdir(s)
    end
end

---
-- Copy a file.  All the directories leading to the destination file are
-- automatically created.
--
-- @param from   Source file
-- @param to  Destination
--
function _file_copy(from, to)
    local f_from = io.open(from)
    assert(f_from)
    _mkdir(to)
    local f_to = io.open(to, "w")
    assert(f_to)

    while true do
	local buf = f_from:read("*a", 2048)
	if not buf or #buf == 0 then break end
	f_to:write(buf)
    end

    f_from:close()
    f_to:close()
end

---
-- Process a file.  If it is a HTML file, run the luadoc template routines on
-- it, otherwise (if it has a known extension) copy it to the destination.
--
function _read_file(path)
    if string.match(path, "%.html$") then
	print("Processing " .. path)
	_mkdir(output_dir .. path)
	local f = io.open(output_dir .. path, "w")
	assert(f)
	io.output(f)
	luadoc.lp.include(path, env)
	f:close()
	return
    end

    if string.match(path, "%.png$") or string.match(path, "%.css$") then
	print("Copying " .. path)
	_file_copy(path, output_dir .. path)
	return
    end
end

---
-- Process a file or directory.  Files are handled by _read_file, while
-- directories are recursed into.
--
function _read_file_dir(path)
    local attr = lfs.attributes(path)

    if not attr then
	print(string.format("error stating file %s", path))
    elseif attr.mode == "file" then
	_read_file(path)
    elseif attr.mode == "directory" then
	for f in lfs.dir(path) do
	    if f ~= "." and f ~= ".." and f ~= "CVS" then
		_read_file_dir(path == "." and f or path .. "/" .. f)
	    end
	end
    end
end

_read_file_dir(".")

