#! /usr/bin/env lua
-- vim:sw=4:sts=4
--[[

 Generate static HTML pages for simple websites.
 Copyright (C) 2007, 2009 Wolfgang Oertl <wolfgang.oertl@gmail.com>

 Features:

  - recursively reads all files, processes the .html files, copies .css,
    .jpg and .png files.

  - uses a template file with header and document layout.

  - parses the input HTML files and processes following patterns:
    {{item ...}}
    An item can be:
	#label		anchor, can be referenced.  No whitespace in label.
	*		hide this entry (no text output)
	=label		reference to that anchor.  If not text is given,
			use the text of the referenced element.
	noindex		don't add to the index
	Any text	text content of this directive; must be the last
			item.

  - Can generate a sorted index of keywords

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
extensions = { png=true, gif=true, jpg=true, css=true }

-- Handling of {{...}} directives
items = {}		    -- array of items
items_byname = {}	    -- key=anchor name, value=item
files = {}		    -- array of input HTML files
curr_file = nil		    -- file currently being read, see _process_html

-- Handling of the index generation
index_string = nil	    -- computed index, used by generate_index()

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


---
-- The environment available to the functions in the template.  Note that
-- all global variables (including functions) are available too.  This
-- should probably change.
--
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
    local f_from, f_to, buf

    f_from = lfs.attributes(from)
    f_to = lfs.attributes(to)

    -- Skip unchanged files.
    if f_from and f_to and f_from.size == f_to.size and f_from.modification
	<= f_to.modification then
	return
    end

    f_from = io.open(from, "rb")
    assert(f_from)
    _mkdir(to)
    f_to = io.open(to, "wb")
    assert(f_to)

    while true do
	buf = f_from:read("*a", 2048)
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
	    tbl[#tbl + 1] = '<li>'
	    _make_side_menu(tbl, item[3], path)
	    tbl[#tbl + 1] = '</li>'
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
function _process_html(ifname, basename, menu_entry, do_index)
    local ifile, ar, buf

    ifile = assert(io.open(ifname, "rb"))

    ar = ar or {}
    curr_file = {
	variables = ar,
	file_name = ifname,
	basename = basename,
	menu_entry = menu_entry,
	index_count = 0,
    }

    ar.SIDEMENU = make_side_menu(menu_entry)
    ar.TITLE = menu_entry[2]
    ar.MAINMENU = main_menu
    ar.CONTENTCLASS = (ar.SIDEMENU == "") and "center" or "right"

    buf = {}
    for line in ifile:lines() do
	buf[#buf + 1] = string.gsub(line, "{{(.-)}}", _html_pass1)
    end
    ifile:close()
    ar.CONTENT = table.concat(buf, "\n")
    -- ar.CONTENT = string.gsub(ifile:read"*a", "{{(.-)}}", _html_pass1)

    files[#files + 1] = curr_file
    curr_file = nil
end

---
-- Second pass over HTML files and output.
--
function output_html()
    local ifile, page, old_page, ofile, ofname, skip

    if not page_template then
	ifile = assert(io.open(input_dir .. "/template.html", "rb"))
	page_template = ifile:read "*a"
	ifile:close()
    end

    for _, file in ipairs(files) do
	_evaluate_html_pass2(file)
	page = string.gsub(page_template, "#([A-Z]+)#", file.variables)

	ofname = output_dir .. "/" .. file.basename

	-- Check for changes.  This avoids a newer date on unchanged
	-- files.
	skip = false
	if lfs.attributes(ofname, "mode") == "file" then
	    ifile = assert(io.open(ofname, "rb"))
	    old_page = ifile:read"*a"
	    ifile:close()
	    if page == old_page then
		skip = true
	    else
		print("CHANGES IN", ofname)
	    end
	end

	if not skip then
	    ofile = assert(io.open(ofname, "wb"))
	    ofile:write(page)
	    ofile:close()
	end
    end
end

---
-- Split a string using a delimiter, which can be a search pattern.  Make sure
-- that the delimiter doesn't match the empty string.
--  
function split(s, delim, is_plain)
    local ar, pos = {}, 1

    while true do
        local first, last = s:find(delim, pos, is_plain)
        if first then
            table.insert(ar, s:sub(pos, first-1))
            pos = last + 1
        else
            table.insert(ar, s:sub(pos))
            break
        end
    end

    return ar
end

---
-- Handler for {{...}} matches during the first pass over the HTML content.
-- These strings are replaced by {{{%d}}}, the data being stored elsewhere.
--
-- Globals: curr_file is the file being read.
--
function _html_pass1(str)
    local c, item

    -- Split the string into elements and fill "item" with data.
    item = { file=curr_file }
    for _, s in ipairs(split(str, " +")) do
	c = string.sub(s, 1, 1)
	if c == "#" then
	    item.is_anchor = true
	    item.anchor_name = string.sub(s, 2)
	elseif c == "*" then
	    item.is_hidden = true
	elseif c == "=" then
	    item.is_reference = true
	    item.ref_name = string.sub(s, 2)
	elseif s == "noindex" then
	    item.omit_index = true
	elseif item.text then
	    item.text = item.text .. " " .. s
	else
	    item.text = s
	end
    end

    -- if this item has no anchor name, generate the next available
    if not item.is_anchor then
	curr_file.index_count = curr_file.index_count + 1
	item.anchor_name = string.format("idx%d", curr_file.index_count)
    end

    if item.is_hidden then
	item.full_anchor = curr_file.basename
    else
	item.full_anchor = string.format("%s#%s", curr_file.basename,
	    item.anchor_name)
    end

    -- assign the next number and store.  If an anchor is defined, store
    -- that too.
    item.nr = #items + 1
    items[#items + 1] = item
    if item.is_anchor then
	assert(items_byname[item.anchor_name] == nil, "Duplicate anchor")
	items_byname[item.anchor_name] = item
    end

    return string.format("{{{%d}}}", item.nr)
end

---
-- Replace the {{{%d}}} strings with their proper content.
--
function _html_pass2(nr)
    local item, target

    item = assert(items[tonumber(nr)], "Item " .. tostring(nr) .. " not found")

    -- nothing is output for hidden items.
    if item.is_hidden then
	-- assert(not item.is_anchor)
	assert(not item.is_reference)
	return ""
    end

    -- a reference is replaced with a link to the referenced anchor
    if item.is_reference then
	target = items_byname[item.ref_name]
	if not target then
	    error(string.format("%s(%d): Missing target %s",
		item.file.basename,
		item.line_nr or 0,
		item.ref_name))
	end

	assert(target.is_anchor)
	assert(item.text or target.text)
	return string.format('<a href="%s">%s</a>', target.full_anchor,
	    item.text or target.text)
    end

    -- named anchors are set
    if item.is_anchor then
	return string.format('<a name="%s">%s</a>', item.anchor_name,
	    item.text)
    end

    -- unnamed anchor - for the index
    assert(item.text)
    return string.format('<a name="%s">%s</a>', item.anchor_name, item.text)
end


---
-- Perform the second pass over the HTML files.  First, {{{%d}}} items left
-- by the first pass are replaced with their final value, and then inline
-- Lua code is executed.
--
function _evaluate_html_pass2(file)
    local v = file.variables

    v.CONTENT = string.gsub(v.CONTENT, "{{{(%d+)}}}", _html_pass2)

    -- curr_menu = file.menu_entry
    v.CONTENT = string.gsub(v.CONTENT, "<%%=(.-)%%>", function(fn)
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

    local ext = string.match(path, "([^.]+)$")

    if extensions[ext] then
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
-- Create a HTML snippet with the alphabetically sorted index.  All the
-- HTML files have already been read.
--
function generate_index()
    local keys, buf, item

    -- collect all the strings to be placed in the index, sort.
    keys = {}
    for _, item in ipairs(items) do
	if not item.omit_index and item.text then
	    keys[#keys + 1] = { string.upper(item.text), item }
	end
    end
    table.sort(keys, function(a, b) return a[1] < b[1] end)

    -- combine index entries with the same string
    for i, item in ipairs(keys) do
	while keys[i + 1] and keys[i + 1][1] == item[1] do
	    item[#item + 1] = keys[i + 1][2]
	    table.remove(keys, i + 1)
	end
    end

    -- build the index string
    buf = {}
    for i, tmp in ipairs(keys) do
	buf[#buf + 1] = tmp[2].text .. ": "
	for i = 2, #tmp do
	    buf[#buf + 1] = string.format('%s<a href="%s">%d</a>',
		i > 2 and ", " or "",
		tmp[i].full_anchor, i - 1)
	end

	buf[#buf + 1] = "<br/>\n"
    end

    index_string = table.concat(buf)
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
generate_index()
output_html()


