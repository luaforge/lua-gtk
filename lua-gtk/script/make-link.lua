#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Read linklist.txt and the type XML file to generate the C and header files.
-- Copyright (C) 2007 Wolfgang Oertl
--
-- It is possible to avoid linking the resulting shared object file with the
-- Gtk libraries.  In this case, they are opened using dlopen() or similar at
-- startup, and all functions used from within the lua-gtk library itself are
-- looked up, and the pointers are stored in the dl_link array.  The function
-- name list is stored at a different memory location, thereby making the
-- lookup table smaller (better for CPU cache usage).
--
-- All the functions called by a Lua script using the lua-gtk binding are
-- looked up in the same fashion anyway, so the additional code is little.
--
-- The advantage of this method over letting the dynamic loaded do this is
-- that when symbols are missing, the library is loaded anyway and works
-- until the missing symbol is accessed.
--
-- In order to guarantee full type checking (return values, parameters), the
-- function signatures are extracted from types.xml just like parse-xml.lua
-- does.  With this information, #defines are output to redirect function
-- calls from C to the Gtk libraries to a function pointer.
--

require "lxp"
require "script.util"

funclist_ordered = {}	    -- [idx] = "name"
funclist = {}		    -- [name] = { type, { rettype, arg1, arg, ... } }
typedefs = {}		    -- [id] = { type, name/id }
globals = {}		    -- [name] = { type }
curr_func = nil

---
-- List of "interesting" tags in the input XML file: those related to function
-- declaration and all the typedefs.
--
xml_tags = {
    Function = function(p, el)
	if funclist[el.name] then
	    curr_func = { "func", { el.returns } }
	    funclist[el.name] = curr_func
	else
	    curr_func = nil
	end
    end,

    Argument = function(p, el)
	if curr_func then
	    table.insert(curr_func[2], el.type)
	end
    end,

    Ellipsis = function(p, el)
	if curr_func then
	    table.insert(curr_func[2], "...")
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

    Variable = function(p, el)
	if funclist[el.name] then
	    funclist[el.name] = { "var", { el.type } }
	end
    end,
}

-- callback to parse the body of the XML file
function regular_start(p, name, el)
    local f = xml_tags[name]
    if f then return f(p, el) end
end

function regular_end(p, name)
    if name == 'Function' then curr_func = nil end
end

-- callback looking for the opening XML tag.
function look_for_gcc_xml(p, name, el)
    if name == "GCC_XML" then
	callbacks.StartElement = regular_start
	callbacks.EndElement = regular_end
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

-- Environment to evaluate conditions in
cond_env = {}
cond_env.__index = cond_env

-- List of libraries to query the version for.  The first column is the
-- lib name, and the second the lib name for pkg-config.
libs = {
    { 'glib', 'glib-2.0' },
    { 'gtk', 'gtk+-2.0' },
    { 'pango', 'pango' },
}

---
-- Use pkg-config to get the versions of the used libraries.
--
function get_lib_versions()
    local fh, s
    for _, item in ipairs(libs) do
	fh = io.popen("pkg-config --modversion " .. item[2] .. " 2> /dev/null")
	if fh then
	    s = fh:read("*l")
	    cond_env[item[1]] = s
	    fh:close()
	end
    end
end


---
-- Load the spec file and extract the "linklist" section, which may be missing.
-- Each entry in that list may be in one of two formats:
--
--  "name",		unconditionally include that function
--  { "name", "cond" }	include only if cond evaluates to true.
--
function read_list(fname)
    local cfg, list, cond, chunk

    cfg = load_spec(fname, true)
    list = cfg.linklist
    if not list then return end

    for i, item in ipairs(list) do
	if type(item) == "string" then
	    _add_function(item)
	else
	    assert(type(item) == "table")
	    assert(type(item[1]) == "string")
	    assert(type(item[2]) == "string")
	    cond = "return " .. item[2]
	    chunk = assert(loadstring(cond))
	    setfenv(chunk, cond_env)
	    if chunk() then
		_add_function(item[1])
	    end
	end
    end

end

function _add_function(name)
    funclist[name] = true
    funclist_ordered[#funclist_ordered + 1] = name
end

--[[
-- from script/parse-xml.lua
function load_config(fname)
    local chunk, msg = loadfile(fname)
    if not chunk then print(msg); os.exit(1) end
    local tbl = { include_spec=include_spec }
    setfenv(chunk, tbl)
    chunk()
    return tbl
end

function include_spec(name)
end
--]]


---
-- Complain about functions that haven't been found in the XML input file.
-- @return  Number of errors found, 0 in case of success.
--
function check_completeness()
    local err = 0

    for k, v in pairs(funclist) do
	if type(v) ~= 'table' then
	    print("Function not defined: " .. k)
	    err = err + 1
	end
    end

    return err
end

---
-- Write the #defines that redirect function calls to the indirect pointers
-- stored in the array dl_link
--
-- @param ofname    Name of the output file to write to
--
function output_header(ofname, ifname)
    local ofile = io.open(ofname, "w")
    local ar, ar1, sig, def

    ofile:write(string.format("/* Automatically generated from %s */\n\n",
	ifname))

    ofile:write(string.format("extern linkfuncptr %s_table[];\n", prefix))

    for nr, name in ipairs(funclist_ordered) do
	def = funclist[name]

	ar = {}
	for k, v in pairs(def[2]) do
	    table.insert(ar, resolve_type(v))
	end

	if def[1] == "func" then

	    -- definition to redirect uses of the function to the pointer
	    ar1 = table.remove(ar, 1)
	    sig = string.format("#define %s ((%s(*)(%s)) %s_table[%d])\n",
		name, ar1, table.concat(ar, ","), prefix, nr-1)
	
	else	    -- "var"
	    sig = string.format("#define %s (*(%s*) %s_table[%d])\n",
		name, ar[1], prefix, nr-1)
	end
	ofile:write(sig)
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
	.. "#include \"common.h\"\n"
	.. "linkfuncptr %s_table[%d];\nconst char %s_names[] = \"\"\n",
	ifname, prefix, #funclist_ordered, prefix))
    for nr, name in ipairs(funclist_ordered) do
	-- pointer and a means to set it to the real function
	ofile:write(string.format("  \"%s\\000\"\n", name, name))
    end
    ofile:write(";\n")
    ofile:close()
end

-- MAIN --

if (#arg ~= 5) then
    print("Arguments: XML file, spec file, output header file, "
	.. "output C file, prefix")
    os.exit(1)
end

get_lib_versions()
prefix = arg[5]
read_list(arg[2])
parse_xml(arg[1])
if check_completeness() ~= 0 then
    os.exit(2)
end

output_header(arg[3], arg[2])
output_c(arg[4], arg[2])

