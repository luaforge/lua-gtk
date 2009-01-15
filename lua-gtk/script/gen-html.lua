#! /usr/bin/env lua
-- vim:sw=4:sts=4
--[[

 Generate static HTML pages for simple websites.
 Copyright (C) 2007, 2009 Wolfgang Oertl <wolfgang.oertl@gmail.com>

 Features:

  - recursively reads all files, processes the .html files, copies .css,
    .jpg and .png files.

  - uses a template file with header and document layout.

  - Can generate a sorted index of keywords which -- are marked with {{...}}
    in the HTML files.

  - Generates a short horizontal and detailed vertical menu linking to all
    the pages using the menu definition in the file "menu.lua" in the
    input directory.

  - detects .html files which are not mentioned in the menu, and complains
    about them.

  - can use .html.in files in the _output_ directory instead of the
    equivalent .html file in the input directory.  This enables another
    program to generate input files which will then get the document
    structure and appear in the menu.

 menu_entry structure: [1]=basename, [2]=title, [3]=submenu, [seen]=true

--]]

require "lfs"

page_template = nil
input_dir = nil
output_dir = nil
config = nil
main_menu = nil

-- Handling of the index generation
index = {}		    -- key=word, data={ href, ... }
index_nr = 0		    -- next index number in current file
index_file = nil	    -- menu entry of the index file
index_string = nil	    -- computed index, used by generate_index()
curr_menu = nil		    -- required by generate_index()

-- expand tabs; taken from "Programming in Lua" by Roberto Ierusalimschy
function expand_tabs(s, tab)
    local corr = 0
    tab = tab or 8
    s = string.gsub(s, "()\t", function(p)
	local sp = tab - (p - 1 + corr) % tab
	corr = corr - 1 + sp
	return string.rep(" ", sp)
    end)
    return s
end

-- colorize keywords
lua_keywords = { 
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while",
}

--[[
lua_library = { 
    "assert", "collectgarbage", "dofile", "error", "getfenv",
    "getmetatable", "ipairs", "load", "loadfile", "loadstring", "module",
    "next", "pairs", "pcall", "print" "rawequal", "rawget", "rawset",
    "require", "select", "setfenv", "setmetatable", "tonumber", "tostring",
    "type", "unpack", "xpcall",
}
--]]

lua_gnome = { "gnome", "gtk", "glib", "gdk", "pango", "cairo", "gtkhtml",
    "gtksourceview" }

-- globals
lua_keyindex = nil
col_res = nil
function put(s)
    col_res[#col_res + 1] = s
end
word = ""
delim = nil

states = {

    -- looking for start of word
    [1] = function(c)
	if c == " " or c == "\n" then
	    put(c)
	    return 1
	end

	word = c

	-- start of string
	if c == '"' or c == "'" then
	    delim = c
	    return 4
	end

	if c >= '0' and c <= '9' then
	    return 5
	end

	return 2
    end,

    -- collecting a word
    [2] = function(c)
	if string.match(c, "^[a-zA-Z_-]$") then
	    word = word .. c
	    -- comment
	    if word == "--" then
		return 3
	    end
	    return 2
	end

	-- number after "-": a negative constant.
	if c >= "0" and c <= "9" and word == "-" then
	    return states[5](c)
	end

	local cl = lua_keyindex[word]
	if cl then
	    put(string.format("<b class=\"%s\">%s</b>", cl, word))
	elseif c == '.' then
	    word = word .. c
	    return 2
	else
	    put(word)
	end
	word = ""
	put(c)
	return 1
    end,

    -- comment
    [3] = function(c)
	if c == "\n" then
	    put("<b class=\"co\">" .. word .. "</b>\n")
	    word = ""
	    return 1
	end
	word = word .. c
	return 3
    end,

    -- in a string
    [4] = function(c)
	word = word .. c
	if c == delim then
	    put("<b class=\"st\">" .. word .. "</b>")
	    return 1
	end
	return 4
    end,

    -- in a number
    [5] = function(c)
	if c >= '0' and c <= '9' then
	    word = word .. c
	    return 5
	end
	put("<b class=\"st\">" .. word .. "</b>")
	return states[1](c)
    end,

}


---
-- Given some Lua code in "s" (may be one line or multiple lines), return
-- HTML code for a colorized (syntax highlighted) representation.
--
function colorize(s)
    if not lua_keyindex then
	lua_keyindex = {}
	for _, k in ipairs(lua_keywords) do lua_keyindex[k] = "kw" end
	for _, k in ipairs(lua_gnome) do lua_keyindex[k] = "gn" end
	for prefix, ar in pairs { [""]=_G, ["string."]=string,
	    ["math."]=math, ["io."]=io, ["package."]=package,
	    ["os."]=os, ["debug."]=debug, ["table."]=table,
	    ["coroutine."]=coroutine } do
	    for k, v in pairs(ar) do
		if type(v) == "function" then
		    lua_keyindex[prefix .. k] = "lb"
		end
	    end
	end
    end

    local state = 1
    word = ""
    col_res = {}
    for c in string.gmatch(s, ".") do
	state = states[state](c)
    end
    states[state] "\n"
    while col_res[#col_res] == "\n" do
	table.remove(col_res)
    end
    return table.concat(col_res, "")
end

-- The environment available to the functions in the template.
env = {

    -- extract a function from a Lua source file
    copy_function = function(file, name)
	local state = 0
	local res = {}

	local exists, _ = lfs.attributes(file)
	if not exists then return "not found: " .. file end

	for line in io.lines(file) do
	    if state == 0 then
		if string.match(line, "function " .. name) then
		    state = 1
		end
	    end

	    if state == 1 then
		res[#res + 1] = colorize(expand_tabs(line))
		if string.match(line, "^end") then
		    break
		end
	    end
	end

	return table.concat(res, "\n")
    end,

    copy_file = function(file)
	local f = io.open(file, "rb")
	if not f then return "not found: " .. file end
	local s = f:read "*a"
	f:close()
	return "<div class=\"code\"><code>\n" .. colorize(s)
	    .. "</code></div>\n"
    end,

    inline_code = function(s, ...)
	local sep = select('#', ...) > 0 and "\n" or ""
	return "<div class=\"code\"><code>\n" .. colorize(s)
	    .. sep .. table.concat({...}, "\n")
	    .. "</code></div>\n"
    end,

    generate_index = function()
	index_file = index_file or curr_menu
	return index_string or ""
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
    local f_from = io.open(from, "rb")
    assert(f_from)
    _mkdir(to)
    local f_to = io.open(to, "wb")
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
-- Add some entries to the menu: _parent in each item, further a basename
-- index in config.menu_index.
--
function _prepare_menu(top, parent, ar)
    ar = ar or top
    for i, item in ipairs(ar) do
	config.menu_index[item[1]] = item
	item._parent = parent
	if item[3] then
	    _prepare_menu(top, item, item[3])	-- recurse
	end
    end
end

-- recursively look for the given basename.
-- ar_in: the part of the menu to look in
-- ar_out: path to the item if found; [1]=most specific, [2]=parent etc.
function _find_in_menu(basename, ar_in, ar_out)

    for i, item in ipairs(ar_in) do
	if item[1] == basename then
	    ar_out[#ar_out+1] = item
	    return true
	end

	if item[3] and _find_in_menu(basename, item[3], ar_out) then
	    ar_out[#ar_out+1] = item
	    return true
	end
    end

end


---
-- Build the side menu for the given menu_entry.  It consists of all siblings
-- and all childs.
-- @param menu  A menu structure
-- @param current  The current menu; in order to descend there and display it
--   differently.
--
function make_side_menu(current)
    local path, m, tbl

    -- determine the path to the current menu entry
    path = {}
    m = current
    while m do
	path[m] = 1
	m = m._parent
    end
    path[current] = 2

    tbl = {}
    _make_side_menu(tbl, config.menu, path)

    if #tbl == 0 then return "" end
    return table.concat(tbl, "\n")
end

function _make_side_menu(tbl, menu, path)
    if #menu == 0 then return end

    tbl[#tbl + 1] = "<ul>"

    for i, item in ipairs(menu) do
	if path[item] == 2 then
	    tbl[#tbl + 1] = string.format("<li><b>%s</b></li>", item[2])
	else
	    tbl[#tbl + 1] = string.format("<li><a href=\"%s.html\">%s</a></li>",
		item[1], item[2])
	end
	if path[item] and item[3] then
	    _make_side_menu(tbl, item[3], path)
	end
    end

    tbl[#tbl + 1] = "</ul>"
end

-- Helper function for _make_side_menu.
function _add_menu_items(tbl, ar)
    for i, item in ipairs(ar) do
	tbl[#tbl + 1] = string.format("<li><a href=\"%s.html\">%s</a></li>",
	    item[1], item[2])
    end
end


---
-- Fill the template using the current menu entry and the given input file,
-- and write the resulting HTML file to ofile.
--
-- @param basename  Name of the output file without the output base path.
-- @param ar  Array with variables available to the page for substitution
--
function _process_html(ifname, basename, menu_entry, ar)
    local ofname, ifile, ofile, ar, page

    ofname = output_dir .. "/" .. basename

    if not page_template then
	ifile = assert(io.open(input_dir .. "/template.html", "rb"))
	page_template = ifile:read "*a"
	ifile:close()
    end

    ifile = assert(io.open(ifname, "rb"))
    index_nr = 0

    ar = ar or {}
    ar.SIDEMENU = make_side_menu(menu_entry)
    ar.TITLE = menu_entry[2]
    ar.CONTENT = _evaluate_html(menu_entry, basename, ifile:read "*a")
    ar.MAINMENU = main_menu
    ar.CONTENTCLASS = (ar.SIDEMENU == "") and "center" or "right"
    ifile:close()

    page = string.gsub(page_template, "#([A-Z]+)#", ar)

    ofile = assert(io.open(ofname, "wb"))
    ofile:write(page)
    ofile:close()
end


---
-- HTML from the input file can contain macros in the form %<= ... %>, which
-- is exactly what luadoc supports.  The ... is evaluated as Lua expression,
-- and its result replaces the whole macro.
--
-- Additionally, extract index words and replace them with an anchor.
--
function _evaluate_html(menu_entry, basename, s)
    s = string.gsub(s, "{{(.-)}}", function(word)
	local hide = false
	if string.sub(word, 1, 1) == "-" then
	    -- hidden ref.
	    word = string.sub(word, 2)
	    hide = true
	end
	local t = index[word] or {}
	index[word] = t
	print("index word", word)
	if hide then
	    t[#t + 1] = basename
	    return ""
	end

	-- regular index entry pointing to a specific location in the text
	index_nr = index_nr + 1
	t[#t + 1] = string.format('%s#idx%d', basename, index_nr)
	return string.format('<a name="idx%d">%s</a>', index_nr, word)
    end)

    curr_menu = menu_entry

    return string.gsub(s, "<%%=(.-)%%>", function(fn)
	local chunk = assert(loadstring("return " .. fn))
	setfenv(chunk, env)
	return chunk()
    end)
end

---
-- Process a file.  If it is a HTML file, run the luadoc template routines on
-- it, otherwise (if it has a known extension) copy it to the destination.
--
function _read_file(path)
    local path1, path_in, basename, menu_entry

    -- basename of the file to process
    path1 = string.sub(path, #input_dir + 2)
    _mkdir(output_dir .. "/" .. path1)

    basename = string.match(path, "([a-z0-9_]+)%.html$")
    if basename then
	if basename == "template" then return end
	menu_entry = assert(config.menu_index[basename],
	    "Missing menu entry for input file " .. basename)
	-- if a .in file exists in the output directory, process that instead.
	-- it might exist if the doc file has been preprocessed.
	path_in = output_dir .. "/" .. path1 .. ".in"
	if lfs.attributes(path_in, "mode") ~= "file" then
	    path_in = path
	end
	print("Processing " .. path1)
	menu_entry.seen = true
	_process_html(path_in, path1, menu_entry)
	return
    end

    if string.match(path, "%.png$")
	or string.match(path, "%.jpg$")
	or string.match(path, "%.css$") then
	print("Copying " .. path)
	_file_copy(path, output_dir .. "/" .. path1)
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


---
-- Read the configuration file for the documentation, which currently only
-- defines the menu structure, including the title for each entry.
--
function _read_config(ifname)
    local ifile = assert(io.open(ifname))
    local s = ifile:read "*a"
    ifile:close()
    local closure = assert(loadstring(s))
    config = {}
    setfenv(closure, config)
    closure()

    -- build the main menu
    local tbl = {}
    for _, entry in ipairs(config.menu) do
	tbl[#tbl + 1] = string.format("<a href=\"%s.html\">%s</a>",
	    entry[1], entry[2])
    end
    main_menu = table.concat(tbl, " &middot;\n")

    config.menu_index = {}
    _prepare_menu(config.menu)

end


---
-- Walk the menu tree and find entries that no file was generated for.
-- Either find a ".in" file in the build directory, or complain.
--
function _check_menu()
    local ifname, ofbase

    for basename, item in pairs(config.menu_index) do
	if not item.seen then
	    ifname = string.format("%s/%s.html.in", output_dir, basename)
	    ofbase = string.format("%s.html", basename)

	    if lfs.attributes(ifname, "mode") == "file" then
		print("Processing " .. ifname)
		item.seen = true
		_process_html(ifname, ofbase, item)
	    else
		print("Missing input file for", basename)
	    end
	end
    end
end

---
-- Create a HTML snippet with the alphabetically sorted index.
--
function _generate_index()
    local keys, buf

    -- which is the file with the index?
    if not index_file then return end

    keys =  {}
    for k, v in pairs(index) do
	keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
	    return string.upper(a) < string.upper(b)
	end)

    buf = {}
    for i, k in ipairs(keys) do
	buf[#buf + 1] = k .. ": "
	for i, v in ipairs(index[k]) do
	    buf[#buf + 1] = string.format('<a href="%s">%d</a>', v, i)
	end
	buf[#buf + 1] = "<br/>\n"
    end

    index_string = table.concat(buf)
    _process_html("html/idx.html", "idx.html", index_file)
end

-- MAIN --
if not arg[2] then
    print(string.format("Usage: %s [input directory] [output directory]",
	arg[0]))
    os.exit(1)
end

input_dir = arg[1]
output_dir = arg[2]
_read_config(arg[1] .. "/menu.lua")
_read_file_dir(arg[1])
_check_menu()
_generate_index()


