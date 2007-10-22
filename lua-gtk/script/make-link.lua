#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Read linklist.txt and the type XML file to generate the C and header files.
-- Copyright (C) 2007 Wolfgang Oertl
--
-- It is possible, although probably not useful, to avoid linking the resulting
-- shared object file with the Gtk libraries.  In this case, they are opened
-- using dlopen() or similar at startup, and all functions used from within
-- the lua-gtk library itself are looked up, and the pointers are stored in
-- the dl_link array.  The names are stored separately, because they are
-- only used once, which makes dl_link smaller (better for cache usage).
--
-- All the functions called by a Lua script using the lua-gtk binding are
-- looked up in the same fashion anyway, so the additional code is little.
-- Consider it an extra exercise which might be useful in some situations.
--
-- In order to guarantee full type checking (return values, parameters), the
-- function signatures are extracted from types.xml just like parse-xml.lua
-- does.  With this information, #defines are output to redirect function
-- calls from C to the Gtk libraries to a function pointer.
--

require "lxp"

funclist = {}		    -- [name] = { rettype, arg1, arg, ... }
typedefs = {}		    -- [id] = { type, name/id }
curr_func = nil

---
-- List of "interesting" tags in the input XML file: those related to function
-- declaration and all the typedefs.
--
xml_tags = {
    Function = function(p, el)
	if funclist[el.name] then
	    curr_func = { el.returns }
	    funclist[el.name] = curr_func
	else
	    curr_func = nil
	end
    end,

    Argument = function(p, el)
	if curr_func then
	    table.insert(curr_func, el.type)
	end
    end,

    Ellipsis = function(p, el)
	if curr_func then
	    table.insert(curr_func, "...")
	end
    end,

    Typedef = function(p, el)
	typedefs[el.id] = { "type", el.name }
    end,

    -- adds one level of indirection, i.e. a "*" to the type.
    PointerType = function(p, el)
	typedefs[el.id] = { "pointer", el.type }
    end,

    -- const, static, volatile - only const is considered
    CvQualifiedType = function(p, el)
	typedefs[el.id] = { "qualifier", el.type, el.const and "const" or "" }
    end,

    FundamentalType = function(p, el)
	typedefs[el.id] = { "type", el.name }
    end,

    Enumeration = function(p, el)
	typedefs[el.id] = { "type", el.name }
    end,
}

-- callback to parse the body of the XML file
function regular_parser(p, name, el)
    local f = xml_tags[name]
    if f then return f(p, el) end
end

-- callback looking for the opening XML tag.
function look_for_gcc_xml(p, name, el)
    if name == "GCC_XML" then
	callbacks.StartElement = regular_parser
    end
end

-- function table used by the XML parsing library.
callbacks = {
    StartElement = look_for_gcc_xml
}

---
-- Open, parse, and close the XML file.
--
-- @param xml_file     Name of the file to read
--
function parse_xml(xml_file)
    local p = lxp.new(callbacks, "::")
    for l in io.lines(xml_file) do
	p:parse(l)
	p:parse("\n")
    end
    p:parse()
    p:close()
end

---
-- Resolve a type string to its C declaration.
--
-- @param s     type string ("_" followed by an integer)
-- @return      resolved type; raises an error if it can't be resolved.
--
function resolve_type(s)
    local qualifier = ""
    local ptr = ""

    -- ellipsis for variable arguments
    if s == "..." then
	return s
    end

    -- multiple typedefs may have to be traversed, accumulating their
    -- information, until a real type is found.
    while true do
	tp = typedefs[s]

	if not tp then
	    break
	end

	if tp[1] == "type" then
	    return qualifier .. tp[2] .. ptr
	end

	if tp[1] == "qualifier" then
	    s = tp[2]
	    qualifier = qualifier .. tp[3] .. " "
	end

	if tp[1] == "pointer" then
	    s = tp[2]
	    ptr = ptr .. "*"
	end
    end

    -- failed
    error("Failed to resolve type " .. s)
end

function read_list(fname)
    for line in io.lines(fname) do
	if #line > 0 and string.sub(line, 1, 1) ~= "#" then
	    funclist[line] = true
	end
    end
end

function check_completeness()
    local err = 0

    for k, v in pairs(funclist) do
	if v == true then
	    print("Function not defined: " .. k)
	    err = err + 1
	end
    end

    return err
end

-- number of functions
local func_nr = 0

---
-- Write the #defines that redirect function calls to the indirect pointers
-- stored in the array dl_link
--
-- @param ofname    Name of the output file to write to
--
function output_header(ofname, ifname)
    local ofile = io.open(ofname, "w")
    local ar, ar1, sig

    ofile:write(string.format("/* Automatically generated from %s */\n\n",
	ifname))

    for name, def in pairs(funclist) do

	ar = {}
	for k, v in pairs(def) do
	    table.insert(ar, resolve_type(v))
	end

	-- definition to redirect uses of the function to the pointer
	ar1 = table.remove(ar, 1)
	sig = string.format("#define %s ((%s(*)(%s)) dl_link[%d])\n",
	    name, ar1, table.concat(ar, ","), func_nr)
	ofile:write(sig)

	func_nr = func_nr + 1
    end

    ofile:close()
end

---
-- Write the C file, which contains the array with the uninitialized
-- function pointers, and another array with the function names.
--
function output_c(ofname, ifname)
    local ofile = io.open(ofname, "w")

    ofile:write(string.format("/* Automatically generated from %s */\n\n"
	.. "#include \"luagtk.h\"\n"
	.. "linkfuncptr dl_link[%d];\nconst char dl_names[] = \n", ifname,
	func_nr))
    for name, def in pairs(funclist) do
	-- pointer and a means to set it to the real function
	ofile:write(string.format("  \"%s\\000\"\n",
	    name, name))
    end
    ofile:write(";\n")
    ofile:close()
end

-- MAIN --

if (#arg ~= 4) then
    print("Arguments: XML file, function list, output header file, "
	.. "output C file")
    os.exit(1)
end

read_list(arg[2])
parse_xml(arg[1])
if check_completeness() ~= 0 then
    os.exit(2)
end

output_header(arg[3], arg[2])
output_c(arg[4], arg[2])

