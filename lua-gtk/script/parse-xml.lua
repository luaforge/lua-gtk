#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Script to extract type information for the Gtk+ and supporting libraries,
-- and to write it to various files suitable for compliation or post
-- processing.  This is a rewrite of an earlier, Perl + objdump based solution.
--
-- Copyright (C) 2007 Wolfgang Oertl
--
-- Revisions:
--  2007-09-11	first version, not yet functional
--  2007-10-03	lots of improvements to date: write function information, add
--		ENUMs as types, resolve types to base types.  Mark all ENUMs as
--		used.  Write a list of globals.  Determine ffi_types.
--  2008-01-17	Special char* type that advises to free it when used as return
--              value of a function.
--  2008-02-24	split into multiple files
--

-- Bitlib. See http://luaforge.net/projects/bitlib/
-- Debian: liblua5.1-bit0
require "bit"

-- add the directory where this Lua file is in to the package search path.
package.path = package.path .. ";" .. string.gsub(arg[0], "%/[^/]+$", "/?.lua")
require "common"

char_ptr_second = nil

xml = require "xml-parser"
typedefs = xml.typedefs
types = require "xml-types"
output = require "xml-output"

typedefs_sorted = {}
typedefs_name2id = {}

architecture = nil  -- target architecture
free_methods = {}	-- [name] = 0/1
input_file_name = nil
parse_errors = 0	-- count errors
verbose = 0		-- verbosity level

---
-- Unfortunately, sometimes ENUM fields in structures are not declared as such,
-- but as integer.  Therefore, used ENUMs may appear unused.  Simply mark all
-- ENUMs as used...
--
function mark_all_enums_as_used()
    local fid, tp
    for id, t in pairs(typedefs) do
	if t.type == "enum" and not t.in_use then
	    types.mark_type_id_in_use(id, nil)
	end
    end
end

---
-- Some enumerations have dummy names, like _cairo_line_cap; what is really
-- used is a typedef for this type, like cairo_line_cap_t.  Find such
-- typedefs for enums and use them.
--
function promote_enum_typedefs()

    local enum_list = {}
    local t2

    -- find all enums
    for id, t in pairs(typedefs) do
	if t.type == "enum" then
	    enum_list[id] = true
	end
    end

    -- find typedefs that refer to them
    for id, t in pairs(typedefs) do
	if t.type == "typedef" and enum_list[t.what] then
	    -- print("FOUND typedef for enum:", t.full_name)
	    types.mark_type_id_in_use(id)
	    t2 = typedefs[t.what]
	    t.counter = t.counter + t2.counter - 1
	    t2.in_use = false
	    t2.enum_redirect = id	-- output the ENUM values anyway
	    t2.counter = 0
	end
    end
end

---
-- The structures named *Iface are required to be able to override interface
-- virtual functions.  They are not intended to be used directly by the user.
--
function mark_ifaces_as_used()
    for type_id, t in pairs(typedefs) do
	if t.type == "struct" and string.match(t.name, "Iface$") then
	    types.mark_type_id_in_use(type_id)
	end
    end
end



function_list = {}

---
-- Take a look at all relevant functions and the data types they reference.
-- Mark all these data types as used.  Note that functions that only appear
-- in structures (i.e., function pointers) are not considered here.
--
-- XXX maybe instead of the function prefix, I should look at the include
-- file where it is defined.  not all functions follow the pattern with
-- a common prefix, e.g. getSystemId from libxml2.
--
function analyze_functions()
    local inc_prefixes = {
	g=true, gdk=true,	-- for glib, gdk
	gtk=true,		-- for gtk
	atk=true,		-- for atk
	pango=true,		-- for pango
	cairo=true,		-- for cairo
	html=true, css=true, dom=true,	-- for libgtkhtml-2.0
    }

    -- Make a sorted list of functions to output.  Only use function with
    -- one of the prefixes in the inc_prefixes list.
    for k, v in pairs(xml.funclist) do
	pos = k:find("_")
	if pos ~= nil and inc_prefixes[k:sub(1, pos - 1)] then
	    function_list[#function_list + 1] = k
	    _function_analyze(k)
	end
    end
    table.sort(function_list)
end


---
-- Mark all data types used by the functions (return type, arguments) as used.
--
function _function_analyze(fname)
    -- arg_info: [ arg_type, arg_name ]
    for arg_nr, arg_info in ipairs(xml.funclist[fname]) do
	if not (arg_info[1] and arg_info[2]) then
	    print(string.format("Incomplete argument spec for %s arg %s",
		fname, arg_nr))
	    for k, v in pairs(arg_info) do print(">", k, v) end
	end
	types.mark_type_id_in_use(arg_info[1],
	    string.format("%s.%s", fname, arg_info[2]))
    end
end


---
-- Look at all structures that have been marked in use - either because they
-- are used as a function return type or argument type, for a global variable
-- or because forced.  Make sure that all their elements' types are registered;
-- this includes function pointers.
--
function analyze_structs()
    for id, t in pairs(typedefs) do
	if t.type == 'struct' or t.type == 'union' then
	    -- in_use: directly used; marked: indirectly used
	    if t.in_use or t.marked then
		_analyze_struct(id, t)
--	    else
--		print("SKIP", t.name)
	    end
	end
    end
end

function _analyze_struct(id, t)
    local st = t.struct
    local ignorelist = { constructor=true, union=true, struct=true }
    local name, tp

    for _, member_name in ipairs(st.members) do
	member = st.fields[member_name]
	if member and not ignorelist[member.type] then
	    -- tp = types.resolve_type(member.type, member.size)
	    -- assert(tp.fid)
	    types.mark_type_id_in_use(member.type,
		string.format("%s.%s", t.name, member.name or member_name))
	end
    end
end


---
-- Run through all globals and mark the types as used.
--
function analyze_globals()
    for name, var in pairs(xml.globals) do
	types.mark_type_id_in_use(var.type, name)
    end
end

local next_synth_nr = 1

---
-- Mark some types as used, or create them.  This is for such types that are
-- not used by any function and are not part of a used structure.
--
-- Some required types are not even in the type list, like
-- GtkFileChooserWidget*; only GtkFileChooserWidget is defined, i.e. without
-- the pointer.
--
function mark_override()
    local ar = {}
    local name2id = {}

    -- get the list of types from the file
    for line in io.lines("src/include_types.txt") do
	line = string.gsub(line, "%s*#.*$", "")
	if line ~= "" then
	    ar[line] = true
	end
    end

    -- Scan all typedefs, resolve their names.  Requested types that can be
    -- found are marked in use.
    for id, t in pairs(typedefs) do
	if not t.full_name then
	    types.resolve_type(id, nil, true)
	    if not t.full_name then
		print("COULD NOT RESOLVE TYPE", id, t.name, t.fname)
	    end
	end
	if t.full_name then
	    if ar[t.full_name] then
		if verbose > 1 then
		    print("mark_override", id, t.type, t.full_name)
		end
		types.mark_type_id_in_use(id)
		ar[t.full_name] = nil
	    elseif not name2id[t.full_name] then
		name2id[t.full_name] = id
	    end
	end
    end

    -- Try to synthetize a new pointer type for still undefined types.
    for full_name, v in pairs(ar) do
	if not synthesize_type(full_name, name2id) then
	    print("Can't synthesize type for " .. full_name)
	else
	    ar[full_name] = nil
	end
    end

    -- what's left hasn't been found.
    for full_name, v in pairs(ar) do
	print("OVERRIDE NOT FOUND", full_name)
    end
end



---
-- The given type doesn't exist.  Remove one level of indirection and check;
-- if found, create a pointer type.  If not, recurse.
--
function synthesize_type(full_name, name2id)

    if string.sub(full_name, -1) ~= "*" then
	return false
    end

    local parent_name = string.sub(full_name, 1, -2)
    local parent_id = name2id[parent_name] or synthesize_type(parent_name,
	name2id)
    if not parent_id then return false end

    local new_id = "synth" .. next_synth_nr
    next_synth_nr = next_synth_nr + 1
    local parent = typedefs[parent_id]
    typedefs[new_id] = { type="pointer", what=parent_id, name=parent.name }
    local t = types.mark_type_id_in_use(new_id, nil)
    if verbose > 1 then
	print("mark override new", new_id, t.type, t.full_name)
    end
    return new_id
end


---
-- The function returns char* or const char*.  Determine whether the returned
-- string should be g_free()d, which should coincide with the const attribute:
-- const strings are not freed, while non-const are.
--
-- Returns the FID (fundamental_id) to use.
--
function _handle_char_ptr_returns(arg_list, tp, fname)

    local method

    -- this is what the API says; consts should not be freed.
    local default_method = tp.const and 0 or 1

    -- The free_method may have been defined by reading the
    -- char_ptr_handling.txt file.
    if arg_list.free_method then
	method = arg_list.free_method
    else

	-- This might be a function argument or structure member, and therefore
	-- should have an entry in this table:
	method = free_methods[fname]

	if not method then
	    print(string.format("Warning: free method not defined for %s",
		fname))
	    method = default_method
	end
    end

    -- Warn if API and my list differ.  Sometimes this is intentionally,
    -- but then should be documented in char_ptr_handling.txt.
    if method ~= default_method then
	print("Warning: inconsistency of free method of function " .. fname)
    end

    return tp.fid + method

end


---
-- Read a list of specs how to handle char* return values of functions.
--
function get_extra_data()
    local active = true
    local arch, arch2, func, method, inverse

    for line in io.lines("src/char_ptr_handling.txt") do

	arch = string.match(line, "^arch (.*)$")
	if arch then
	    arch2 = string.match(arch, "^not (.*)$")
	    inverse = false
	    if arch2 then
		inverse = true
		arch = arch2
	    end
	    active = arch == "all" and true or string.match(architecture, arch)
	    if inverse then active = not active end
	end

	if not arch and active then
	    func, method = string.match(line, '^([^#,]*),(%d)$')
	    if func and method then
		_set_char_ptr_handling(func, tonumber(method))
	    end
	end
    end
end

---
-- Set the free_method of a given function
--
function _set_char_ptr_handling(funcname, method)

    -- funcnames that include a dot are not simple functions, but refer to
    -- an argument of a function, or a member of a structure.
    local parent, item = string.match(funcname, "^([^.]+)%.(.*)$")
    if parent and item then
	free_methods[parent == "funcptr" and item or funcname] = method
	return
    end

    local fi = xml.funclist[funcname]
    if not fi then
	print("Warning: undefined function in char_ptr_handling: " .. funcname)
	return
    end

    assert(fi.free_method == nil, "Duplicate in char_ptr_handling.txt: "
	.. funcname)
    tp = types.resolve_type(fi[1][1])

    -- must be a char*, i.e. with one level of indirection
    assert(tp.fname == "char")
    assert(tp.pointer == 1)

    -- If a return type is "const char*", then this usually means "do not
    -- free it".  Alas, this rule of thumb has exceptions.
    if not (method == 0 and tp.const or method == 1 and not tp.const) then
	print("Warning: inconsistency of free method of function " .. funcname)
    end

    fi.free_method = method
end



enums = {}

---
-- Certain #defines from the Gtk/Gdk include files are relevant, but not
-- included in types.xml.  Extract them and add them to the ENUM list.
--
function parse_header_file(fname, nums)
    local line2 = ""
    local name, value
    local enums = xml.enum_values

    -- a typedef.context to use for the defines
    typedefs.__dummy = { in_use=true, count=1 }

    for line in io.lines(fname) do
	-- emulate "continue" command
	while true do
	    -- continuation
	    if string.match(line, "\\$") then
		line2 = line2 .. string.sub(line, 1, -2)
		break
	    end

	    line = line2 .. line
	    line2 = ""

	    -- numeric defines
	    if nums then
		name, value = string.match(line,
		    "^#define ([A-Z][A-Za-z0-9_]+) +([0-9a-fx]+)$")
		if name and value then
		    assert(not enums[name])
		    enums[name] = { val=tonumber(value), context="__dummy" }
		    -- print(encode_enum(name, tonumber(value), 0))
		    break
		end
	    end

	    -- string defines
	    name, value = string.match(line,
		"^#define ([A-Z_]+) +\"([^\"]+)\"")
	    if name and value then
		assert(not enums[name])
		enums[name] = { val=value, context="__dummy" }
		-- print(encode_enum(name, value, 0))
		break
	    end

	    -- G_TYPE defines
	    name, value = string.match(line,
		"^#define ([A-Z0-9_]+)%s+G_TYPE_MAKE_FUNDAMENTAL%s+%((%d+)%)")
	    if name and value then
		-- *4 is what G_TYPE_MAKE_FUNDAMENTAL does.
		assert(not enums[name])
		enums[name] = { val=tonumber(value) * 4, context="__dummy" }
		-- print(encode_enum(name, value * 4, 0))
		break
	    end

	    -- nothing usable in this line, skip.
	    break
	end
    end
end

    

---
-- Show a numeric statistical information
--
function info_num(label, value)
    print(string.format("  %-40s%d", label, value))
end


-- MAIN --

-- parse optional arguments --
while #arg > 0 do
    if arg[1] == '-v' then
	verbose = verbose + 1
	table.remove(arg, 1)
    else
	break
    end
end

-- remaining must be three --
if #arg ~= 3 then
    print(string.format("Usage: %s [options] {outputdir} {xmlfile} {arch}",
	arg[0]))
    return
end

architecture = arg[3]

-- read the XML data
xml.parse_xml(arg[2])

get_extra_data()
mark_ifaces_as_used()
analyze_globals()

analyze_functions()
mark_override()
analyze_structs()
mark_all_enums_as_used()
promote_enum_typedefs()

-- before writing the structures, the functions must be looked at to
-- find prototypes that need registering.

types.assign_type_idx()

-- Now that all used types have their IDs, the function prototypes
-- can be registered.
types.register_function_prototypes()

-- read additional ENUMs from header files.  Do this after assign_type_idx,
-- so that the __dummy entry isn't being output.
path_gtk = "/usr/include/gtk-2.0"
path_glib = "/usr/include/glib-2.0"
parse_header_file(path_gtk .. "/gtk/gtkstock.h", false)
parse_header_file(path_glib .. "/gobject/gtype.h", false)
parse_header_file(path_gtk .. "/gdk/gdkkeysyms.h", true)

output.output_types(arg[1] .. "/gtkdata.structs.c")
output.output_enums(arg[1] .. "/gtkdata.enums.txt")
output.output_functions(arg[1] .. "/gtkdata.funcs.txt")
output.output_fundamental_types(arg[1] .. "/gtkdata.types.c")
output.output_globals(arg[1] .. "/gtkdata.globals.c")

print("\n --- " ..arg[2] .. " Parsing Results ---\n")
xml.show_statistics()
types.show_statistics()
output.show_statistics()
enum_statistics()
print ""

