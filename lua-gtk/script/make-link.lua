#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
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
-- This helps when some libraries are optional, currently gtkhtml.  If it
-- isn't available at runtime, this doesn't matter until a function is
-- called.
--
-- In order to guarantee full type checking (return values, parameters), the
-- function signatures are extracted from types.xml just like parse-xml.lua
-- does.  With this information, #defines are output to redirect function
-- calls from C to the Gtk libraries to a function pointer.
--

require "lxp"

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
-- Read the list of functions to link to.  Comment lines are ignored.
--
function read_list(fname)
    local name, cond, chunk, msg, rc

    for line in io.lines(fname) do
	if #line > 0 and string.sub(line, 1, 1) ~= "#" then
	    name, cond = string.match(line, "^(%S+)(.*)$")
	    rc = true
	    if cond ~= '' then
		chunk, msg = loadstring("return " .. cond)
		if not chunk then
		    print("Faulty condition", cond)
		    rc = false
		else
		    setfenv(chunk, cond_env)
		    rc = chunk()
		end
	    end
	    
	    -- add to list if no condition was given or the cond was met.
	    if rc then
		funclist[name] = cond
	    end
	end
    end
end


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
	for k, v in pairs(def[2]) do
	    table.insert(ar, resolve_type(v))
	end

	if def[1] == "func" then

	    -- definition to redirect uses of the function to the pointer
	    ar1 = table.remove(ar, 1)
	    sig = string.format("#define %s ((%s(*)(%s)) dl_link[%d])\n",
		name, ar1, table.concat(ar, ","), func_nr)
	
	else	    -- "var"
	    sig = string.format("#define %s (*(%s*) dl_link[%d])\n",
		name, ar[1], func_nr)
	end
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

get_lib_versions()
read_list(arg[2])
parse_xml(arg[1])
if check_completeness() ~= 0 then
    os.exit(2)
end

output_header(arg[3], arg[2])
output_c(arg[4], arg[2])

