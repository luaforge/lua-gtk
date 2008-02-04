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
--


-- Lua Expat Binding - expat is an XML parser library
-- It is available in Debian as the package liblua5.1-expat0.  Links:
--  http://www.keplerproject.org/luaexpat/
--  http://www.luaforge.net/projects/luaexpat/
require "lxp"

-- Bitlib. See http://luaforge.net/projects/bitlib/
require "bit"

-- add the directory where this Lua file is in to the package search path.
package.path = package.path .. ";" .. string.gsub(arg[0], "%/[^/]+$", "/?.lua")
require "common"

funclist = {}	    -- [name] = [ [rettype,"retval"], [arg1type, arg1name], ...]
funclist2 = {}
unhandled = {}	    -- [name] = true
globals = {}	    -- [name] = {...}
typedefs = {}	    -- [id] = { type=..., name=..., struct=... }
  -- struct = { name, size, align, members, _type, fields } (same for enum)
enum_values = {}    -- [name] = { val, context }
max_bit_offset = 0
max_bit_length = 0
max_struct_id = 0   -- last struct_id in use
max_func_args = 0
max_struct_size = 0
fundamental_name2id = {}
prototypes = {}
char_ptr_second = 0
free_methods = {}	-- [name] = 0/1

type_override = {
    ["GtkObject.flags"] = { "GtkWidgetFlags" },
}

-- Some structures would not be included, because they are not used by
-- any existing function.  Include them anyway...
used_override = {
    ["GtkFileChooserWidget"] = true,
    ["GtkFileChooserDialog"] = true,
}

-- List of fundamental types existing.  The fid (fundamental id) is an index
-- into this table; the first entry starts at index 1.  Append as many "*" to
-- the name as there are indirections.  The entries are added as found and
-- therefore are all in use.
fundamental_ifo = {}

-- get the list of supported fundamental data types.
require "src/fundamental"

---
-- Check whether a given fundamental type is already known.  If not,
-- add it.  Anyway, return the fid for this type.
--
function register_fundamental(name, pointer, bit_len)
    local fid

    assert(name, "Trying to register fundamental type with null name")

    -- fixup for atk_object_connect_property_change_handler.  The second
    -- argument's type seems to be "func**", but it really is "func*".
    if name == 'func' and pointer > 1 then pointer = 1 end

    name = name .. string.rep("*", pointer)
    fid = fundamental_name2id[name]
    if fid then return fid end

    -- register new fundamental type
    fid = #fundamental_ifo + 1
    assert(fid < 100, "Too many fundamental types!")

    fundamental_ifo[fid] = {
	name = name,
	pointer = pointer,
	bit_len = bit_len
    }
    fundamental_name2id[name] = fid

    -- Special case for char*: add another entry for const char*, which
    -- must directly follow the regular char* entry.
    if name == "char*" then
	fundamental_ifo[fid + 1] = {
	    name = "const char*",
	    pointer = pointer,
	    bit_len = bit_len
	}
	char_ptr_second = fid + 1
    end

    -- print("register fundamental type", fid, name, bit_len)
    return fid
end

---
-- An override entry has been found.  It gives the name of the type to use,
-- but we need the type ID, i.e. a "_" followed by a number.  As I don't want
-- to build another index, search the list of types
--
function do_override(ov)
    if ov[2] then return ov[2] end
    local name = ov[1]
    for k, v in pairs(typedefs) do
	if v.name == name then
	    ov[2] = k
	    return k
	end
    end
    print("Override type not found:", name)
end


curr_func = nil
curr_enum = nil

xml_tags = {

    -- not interested in namespaces.
    Namespace = function(p, el)
    end,

    -- store functions
    Function = function(p, el)
	curr_func = { { el.returns, "retval" } }
	funclist[el.name] = curr_func
    end,

    -- discard the argument names, just keep the type.
    Argument = function(p, el)
	if curr_func then
	    curr_func[#curr_func + 1] = { el.type, el.name or
		string.format("arg_%d", #curr_func) }
	end
    end,

    -- translated to vararg argument later
    Ellipsis = function(p, el)
	if curr_func then
	    curr_func[#curr_func + 1] = { "vararg", "vararg" }
	end
    end,

    -- declare a type being a function prototype
    FunctionType = function(p, el)
	curr_func = { { el.returns, "retval" } }
	typedefs[el.id] = { type="func", prototype=curr_func }
    end,

    -- Not interested much in constructors.  Store anyway to avoid
    -- dangling references.
    Constructor = function(p, el)
	local t = typedefs[el.context]
	if not t then
	    print("Constructor for unknown structure " .. el.context)
	    return
	end
	local st = t.struct
	st.fields[el.id] = { type="constructor", name=el.name }
	curr_func = nil
    end,

    -- structures and unions
    Struct = function(p, el) return xml_struct_union(p, el, "struct") end,
    Union = function(p, el) return xml_struct_union(p, el, "union") end,

    -- member of a structure
    Field = function(p, el) 
	local t = typedefs[el.context]
	if not t then
	    print("Field for unknown structure " .. el.context)
	    return
	end
	local st = t.struct
	local override = type_override[st.name .. "." .. el.name]
	if override then
	    el.type = do_override(override)
	end
	st.fields[el.id] = { name=el.name, type=el.type, offset=el.offset,
	    size=el.bits }
	max_bit_offset = math.max(max_bit_offset, el.offset)
	-- in most cases, no bit length is given; mostly it derives from the
	-- referenced type.
	if el.bits then
	    max_bit_length = math.max(max_bit_length, el.bits)
	end
    end,

    Variable = function(p, el)
	globals[el.name] = el
    end,

    -- declare an alternative name for another type
    Typedef = function(p, el)
	if el.context ~= "_1" then
	    print("Warning: typedef context is " .. el.context)
	end
	typedefs[el.id] = { type="typedef", name=el.name, what=el.type }
    end,

    EnumValue = function(p, el)
	enum_values[el.name] = { val=tonumber(el.init), context=curr_enum }
    end,

    -- declare a type being an enum
    Enumeration = function(p, el)
	-- print("ENUM", el.name)
	typedefs[el.id] = { type="enum", name=el.name, size=el.size,
	    align=el.align }
	curr_enum = el.id
    end,

    -- declare a type being a pointer to another type
    PointerType = function(p, el)
	typedefs[el.id] = { type="pointer", what=el.type, size=el.size,
	    align=el.align }
    end,

    FundamentalType = function(p, el)
	local fid = register_fundamental(el.name, 0, el.size)
	typedefs[el.id] = { type="fundamental", name=el.name, size=el.size,
	    align=el.align, fid=fid }
	if not el.size and el.name ~= "void" then
	    print("Warning: fundamental type without size: " .. el.name)
	end
    end,

    -- wrapper for another type adding qualifiers: const, restrict, volatile
    CvQualifiedType = function(p, el)
	typedefs[el.id] = { type="qualifier", what=el.type,
	    restrict=el.restrict, const=el.const, volatile=el.volatile }
    end,

    ArrayType = function(p, el)
	typedefs[el.id] = { type="array", min=el.min, max=el.max,
	    align=el.align, what=el.type }
    end,

    -- a function parameter that is passed by reference; only used in the
    -- automatically generated and not useful constructors.
    ReferenceType = function(p, el)
    end,

    -- associate names to the file IDs which are not used anyway.
    File = function(p, el)
    end,
}

---
-- Handle Struct and Union declarations.
--
-- @param el Element information
-- @param what "struct" or "union"
--
function xml_struct_union(p, el, what)
    local members, my_name, struct

    members = {}
    my_name = el.name or el.demangled

    -- remove leading "_", which all structures and unions seem to have.
    my_name = my_name:gsub("^_", "")

    if not el.incomplete then
	for w in string.gmatch(el.members, "[_0-9]+") do
	    members[#members + 1] = w
	end
    end

    typedefs[el.id] = { type=what, name=my_name, struct = {
	name=my_name,
	size=el.size,	    -- total size in bits (unset for incomplete structs)
	align=el.align,
	members=members,    -- list (in order) of the IDs in fields
	_type=what,
	fields={}	    -- [ID] = { name, offset, ... }
    } }

    -- substructure of another structure?  If so, hook it in there
    if el.context and el.context ~= "_1" then
	local t = typedefs[el.context]
	if not t then
	    print("Union/Structure for unknown structure " .. el.context)
	    return
	end
	local st = t.struct
	assert(not st.fields[el.id], "repeated ID " .. el.id .. " in "
	    .. my_name)
	st.fields[el.id] = { type=what, id=el.id }
    end
end


function regular_parser(p, name, el)

    local f = xml_tags[name]
    if f then return f(p, el) end

    if not unhandled[name] then
	print("Unhandled XML element " .. name)
	unhandled[name] = true
    end

end

function look_for_gcc_xml(p, name, el)
    if name == "GCC_XML" then
	callbacks.StartElement = regular_parser
    end
end

-- Initial state: just look for the GCCXML signature, then continue with the
-- real callback.
callbacks = {
    StartElement = look_for_gcc_xml
}


---
-- Read the given XML file
--
-- @param xml_file filename (with path) of the input file
--
function parse_xml(xml_file)
    local p = lxp.new(callbacks, "::")
    for l in io.lines(xml_file) do
	p:parse(l)
	p:parse("\n")
    end
    p:parse()	    -- close document
    p:close()	    -- close parser
end

---
-- Unfortunately, sometimes ENUM fields in structures are not declared as such,
-- but as integer.  Therefore, used ENUMs may appear unused.  Simply mark all
-- ENUMs as used...
--
function mark_all_enums_as_used()
    for k, tp in pairs(typedefs) do
	if tp.type == "enum" then tp.in_use = true end
    end
end

---
-- The structures named *Iface are required to be able to override interface
-- virtual functions.  They are not intended to be used directly by the user.
--
function mark_ifaces_as_used()
    for type_id, tp in pairs(typedefs) do
	if tp.type == "struct" and string.match(tp.name, "Iface$") then
	    mark_typedef_in_use(tp, tp.name)
	end
    end
end


---
-- Generate a sorted list of ENUMs suitable for postprocessing with a hashing
-- tool.
--
-- Each entry consist of the name, ",", the 16 bit number of the structure
-- number (describing this ENUM), and the actual value in a low to high byte
-- order.  Only as many bytes are output as are required to represent the given
-- value.  The value zero has no bytes.
--
-- Call this function _after_ output_structs, because there the struct_ids
-- are assigned.
--
-- @param ofname Name of the output file
--
function output_enums(ofname)
    local keys, ofile, s, enum, val, prefix = {}

    for k, enum in pairs(enum_values) do
	tp = typedefs[enum.context]
	if tp.in_use then
	    keys[#keys + 1] = k
	end
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")

    for i, name in pairs(keys) do
	enum = enum_values[name]
	val = tonumber(enum.val)
	s = encode_enum(name, val, typedefs[enum.context].struct_id)
	ofile:write(s .. "\n")
    end
    ofile:close()
end


---
-- Given a Type ID, find the underlying type - which may be a structure,
-- union, fundamental type, function, enum, array, pointer or maybe other
-- things.
--
-- @param type_id  Type identifier, which is a number with leading _
-- @param size  For structure elements, a bitsize is usually given and can
--   override the default size; only useful for integers.
--
-- @return Table with fields name, bit_len, bit_size, detail, pointer, array,
--  fid
--
function resolve_type(type_id, size)
    if type_id == nil then return {} end
    local res = { bit_len=size or 0, detail=nil, pointer=0, array=0,
	name=nil, name2=nil }

    if type_id == "vararg" then
	res.name = type_id
    end

    while typedefs[type_id] do
	tp = typedefs[type_id]

	-- use the most generic name for this type
	res.name2 = tp.name or res.name2

	-- pointer to something
	if tp.type == "pointer" then
	    res.bit_len = tp.size
	    res.pointer = res.pointer + 1
	    -- tp.align not used
	    type_id = tp.what

	-- a typedef, i.e. an alias
	elseif tp.type == "typedef" or tp.type == "qualifier" then
	    -- copy qualifiers; they add up if multiple are used
	    if tp.const then res.const = true end
	    if tp.volatile then res.volatile = true end
	    if tp.restrict then res.restrict = true end
	    type_id = tp.what

	    -- special case gboolean (typedef to some numeric type)
	    if tp.name == "gboolean" then res.alias = "boolean" end

	-- structure or union.
	elseif tp.type == "struct" or tp.type == "union" then
	    if tp.size then res.bit_len = tp.size end
	    res.name = tp.type
	    res.detail = tp
	    break

	-- fundamental type.
	elseif tp.type == "fundamental" then
	    -- tp.type, name, size, align
	    if res.bit_len == 0 and tp.size then res.bit_len = tp.size end
	    res.name = tp.name
	    break

	-- function pointer
	elseif tp.type == "func" then
	    res.name = "func"
	    res.detail = tp
	    -- res.prototype = tp.prototype
	    break

	-- an enum
	elseif tp.type == "enum" then
	    -- information about which enum is lost
	    -- the enum name is tp.name
	    res.bit_len = tp.size
	    res.name = "enum"
	    res.detail = tp
	    break

	-- array of some other type
	elseif tp.type == "array" then
	    if tp.size then res.bit_len = tp.size end
	    res.array = 1
	    type_id = tp.what

	-- unknown type
	else
	    print("? " .. tp.type)
	    break
	end
    end

    if res.alias then
	res.name = res.alias
	res.alias = nil
    end

    -- register this type
    res.fid = register_fundamental(res.name, res.pointer, res.bit_len)

    -- compute a full name
    res.full_name = string.format("%s%s%s",
	res.const and "const " or "",
	res.name,
	string.rep("*", res.pointer))

    return res
end

---
-- Helper function to build a string table; used for the structures
--

local string_table = {}	-- [name] = offset
local string_buf = {}	-- names
local string_offset = 0
local elem_start = 0	-- current position in the element table

---
-- Add another string to the string table and return the offset.  If the string
-- already exists, reuse.
--
-- @param s  the string to store
-- @param omit_nul  If true, don't append a nul byte
-- @return byte offset into the string table
--
function store_string(s, omit_nul)

    if not omit_nul then
	s = s .. string.char(0)
    end
    local len = #s

    -- if already in the string table, reuse.
    local ofs = string_table[s]
    if ofs ~= nil then return ofs end

    -- store a new entry.
    ofs = string_offset
    string_offset = ofs + len
    string_table[s] = ofs
    string_buf[#string_buf + 1] = s
    return ofs
end

---
-- Add the information for one structure (with all its fields) to the output.
--
function output_one_struct(ofile, tp, struct_name)
    local st, member, ofs
    st = tp.struct
    st.elem_start = elem_start

    -- no details required for an enum.
    if st._type == 'enum' then return end

    for j, member_name in pairs(st.members) do
	member = st.fields[member_name]
	if not member then
	    print("? unspecified member >>" .. member_name .. "<<")

	-- ignore these member types.  constructors are irrelevant;
	-- substructures (and sub unions) are listed twice, once as a regular
	-- field and once as the union/struct; ignore this second instance.
	elseif member.type == "constructor" or member.type == "union"
	    or member.type == "struct" then
	    -- nothing
	else
	    ofs = store_string(member.name or member_name)

	    tp = resolve_type(member.type, member.size)
	    if not tp.fid then
		print("no FID for", tp.name, member.name or member_name)
	    end

	    local detail_id = 0

	    -- For functions, generate a prototype (or reuse one from the
	    -- list), and output the proto_id below.  Because the IDs of all
	    -- used structures must be known, this can only be called after
	    -- the assignment of struct_ids.
	    if tp.detail then
		if tp.name == 'func' then
		    register_prototype(tp.detail, string.format("%s.%s",
			struct_name, member.name or member_name))
		    detail_id = tp.detail.proto_id
		else
		    detail_id = tp.detail.struct_id
		end
	    end

	    -- name offset, bit offset, bit length (0=see detail),
	    -- fundamental type id, type detail (0=none)
	    ofile:write(string.format(" { %d, %d, %d, %d, %d }, /* %s */\n",
		ofs, member.offset, tp.bit_len, tp.fid, detail_id,
		member.name or member_name))
	    elem_start = elem_start + 1
	end
    end
end

---
-- A pointer to a function appeared as an argument type to another function,
-- or as the type of a member of a structure.  In both cases, make sure this
-- function's signature is stored as usual.  The "proto_id" of the given
-- typedef will be set.
--
-- @param typedef   An entry of typedefs[] with .prototype set
-- @return  true on success, false on error (some arg type not defined yet)
--
function register_prototype(typedef, name)
    
    local key = {}

    -- Compute a string to identify this prototype.  It contains the types of
    -- return value and all the arguments' types, but without their names.
    for i, arg_info in ipairs(typedef.prototype) do
	-- no bit size given for function parameters.
	local tp = resolve_type(arg_info[1])
	key[#key + 1] = tp.full_name
    end
    key = table.concat(key, ',')

    local proto_ofs = prototypes[key]

    if not proto_ofs then
	local sig = _function_arglist(typedef.prototype, name)
	if not sig then return false end

	-- prepend a length byte
	sig = string.char(#sig) .. sig

	proto_ofs = store_string(sig, true)
	prototypes[sig] = proto_ofs
    end

    -- this can happen when there are inconsistencies of free methods.
    if typedef.proto_id and typedef.proto_id ~= proto_ofs then
	print(string.format("Warning: differing prototypes %d and %d for %s, "
	    .. "key=%s", typedef.proto_id, proto_ofs, name, key))
    end

    typedef.proto_id = proto_ofs
    return true
end

---
-- Write a C file with the structure information, suitable for compilation
-- and linking to the library.
--
-- @param ofname Name of the output file to write to.  If it exists, it will
-- be overwritten.
--
function output_structs(ofname)
    local keys, name2id, ofile, s, val, st, tp =  {}, {}
    local types = {struct=true, union=true, enum=true}

    -- Make a list of used structs/unions/enums to output, sort.
    for k, tp in pairs(typedefs) do
	if tp.in_use and types[tp.type] then
	    keys[#keys + 1] = tp.name
	    name2id[tp.name] = k
	end
    end
    table.sort(keys)

    -- Assign numbers to the structures; don't use 0.  Note that the
    -- structure IDs must start at 1 and not have holes, and be sorted by name
    -- because a bsearch() is done on the structure array.
    for id, name in ipairs(keys) do
	tp = typedefs[name2id[name]]
	tp.struct_id = id
    end
    max_struct_id = #keys

    -- Now that all used structures have their IDs, the function prototypes
    -- can be registered.
    register_function_prototypes()

    ofile = io.open(ofname, "w")
    ofile:write("#include \"luagtk.h\"\n")

    -- generate the list of elements
    -- fields: name_ofs, bit_offset, bit_len, ffi_type_id, type_detail
    elem_start = 0
    ofile:write("const struct struct_elem elem_list[] = {\n")
    for i, name in ipairs(keys) do
	tp = typedefs[name2id[name]]
	tp.name_ofs = store_string(name)
	if tp.struct then
	    output_one_struct(ofile, tp, name)
	else
	    -- If it is not a structure, still memorize the current elem_start.
	    -- It will be output, causing the correct element count for the
	    -- previous structure to be computed.
	    tp.elem_start = elem_start
	end
    end
    ofile:write("};\n\n")

    -- struct_list.  It contains entries for all the ENUMs, which don't have
    -- any elements of course (size=0).
    ofile:write("const struct struct_info struct_list[] = {\n"
	.. " { 0, 0, 0 }, /* placeholder for undefined structures */\n")
    for i, name in ipairs(keys) do
	tp = typedefs[name2id[name]]
	assert(tp.struct_id)
	assert(tp.struct_id == i)
	st = tp.struct or { elem_start=tp.elem_start, size=0 }
	local struct_size = (st.size or 0)/8
	ofile:write(string.format(" { %d, %d, %d }, /* %s */\n",
	    tp.name_ofs, st.elem_start, struct_size, name))
	max_struct_size = math.max(max_struct_size, struct_size)
    end

    -- Last entry to calculate the elem count of the real last entry.  This one
    -- isn't being counted in the struct_count.
    ofile:write(string.format(" { %d, %d, %d }\n};\n",
	0, elem_start, 0))
    ofile:write("const int struct_count = " .. max_struct_id .. ";\n\n")

    -- string table.  The strings that need it already have a trailing NUL
    -- byte.  Note that formatting with %q is NOT enough, C needs to escape
    -- more characters.
    ofile:write("const char struct_strings[] = \n");
    for i, s in pairs(string_buf) do
	ofile:write(string.format(" \"%s\"\n", string.gsub(s, "[^a-zA-Z0-9_.]",
	    function(c) return string.format("\\%03o", string.byte(c)) end)))
    end
    ofile:write(";\n");

    ofile:close()
end

function_list = {}

---
-- Take a look at all relevant functions and the data types they reference.
-- Mark all these data types as used.  Note that functions that only appear
-- in structures (i.e., function pointers) are not considered here.
--
function analyze_functions()
    local inc_prefixes = { pango=true, gtk=true, gdk=true, g=true, atk=true,
	cairo=true }

    -- Make a sorted list of functions to output.  Only use function with
    -- one of the prefixes in the inc_prefixes list.
    for k, v in pairs(funclist) do
	pos = k:find("_")
	if pos ~= nil and inc_prefixes[k:sub(1, pos - 1)] then
	    function_list[#function_list + 1] = k
	    _function_analyze(k)
	end
    end
    table.sort(function_list)
end

---
-- Look at all structures that have been marked in use.  make sure that all
-- their elements' types are registered; this includes function pointers.
--
function analyze_structs()
    for id, tp in pairs(typedefs) do
	if tp.in_use and (tp.type == 'struct' or tp.type == 'union') then
	    analyze_struct(tp)
	end
    end
end

function analyze_struct(tp)

    local st = tp.struct
    local ignorelist = { constructor=true, union=true, struct=true }
    local name, tp2

    --print("analyze_struct", tp.name)

    for _, member_name in pairs(st.members) do
	member = st.fields[member_name]
	if member and not ignorelist[member.type] then
	    tp2 = resolve_type(member.type, member.size)
	    assert(tp2.fid)
	    name = string.format("%s.%s", tp.name, member.name or member_name)
	    mark_typedef_in_use(tp2, name)
	end
    end
end

---
-- Mark all data types used by the functions (return type, arguments) as used.
--
function _function_analyze(fname)
    -- arg_info: [ arg_type, arg_name ]
    for arg_nr, arg_info in ipairs(funclist[fname]) do
	mark_type_id_in_use(arg_info[1],
	    string.format("%s.%s", fname, arg_info[2]))
    end
end


---
-- Run through all globals and mark the types as used.
--
function analyze_globals()
    for k, var in pairs(globals) do
	mark_type_id_in_use(var.type, k)
    end
end


---
-- Mark all types that are forced to be visible.
--
-- Note: because the leading underscore is removed (see xml_struct_union) one
-- entry in used_overide may activate a structure declaration and the
-- corresponding typedef, but that doesn't matter.
--
function mark_override()
    for k, typedef in pairs(typedefs) do
	if used_override[typedef.name] then
	    mark_typedef_in_use(typedef, typedef.name)
	end
    end
end

-- given a type_id, make sure the base type for it is marked used.
function mark_type_id_in_use(type_id, name)

    -- resolve this type ID, resulting in a fundamental type.  These are
    -- all available; but if it is a structure, union, enum, function etc.
    -- that have additional info, this must be marked in use.
    local tp = resolve_type(type_id)
    if tp.detail then
	-- tp.name2 may be set, but not for anonymous prototypes
	name = tp.name2 or name
	return mark_typedef_in_use(tp.detail, name)
    end

end

---
-- Recursively mark this typedef and all subtypes as used.
--
function mark_typedef_in_use(typedef, name)
    local ignore_types = { constructor=true, union=true, struct=true }
    local field, tp2

    -- already marked?
    if typedef.in_use then return end

    typedef.in_use = true

    -- mark elements of a structure
    if typedef.struct then
	local st = typedef.struct
	for i, member_id in ipairs(st.members) do
	    field = st.fields[member_id]
	    if not ignore_types[field.type] then
		mark_type_id_in_use(field.type, string.format("%s.%s",
		    name, field.name or member_id))
	    elseif field.type ~= "constructor" then
		print("ignore??", member_id, field.type)
	    end
	end
    end

    -- mark types of arguments
    if typedef.prototype then
	for i, arg_info in ipairs(typedef.prototype) do
	    local type_id = arg_info[1]
	    mark_type_id_in_use(type_id, nil)
		-- string.format("%s.%s", name, arg_info[2] .. "XX"))
	end
	-- Can't call register_prototype yet, because no struct_ids are
	-- assigned yet.  Instead, add this to a list.
	assert(not funclist2[name], "double funclist2 entry " .. name)
	funclist2[name] = typedef
    end


end

function register_function_prototypes()
    local cnt, funclist3 = 1

    for loops = 1, 3 do
	funclist3 = {}
	for name, tp in pairs(funclist2) do
	    if not register_prototype(tp, name) then
		-- Could not resolve the prototype yet; try again
		funclist3[name] = tp
	    end
	end
	funclist2 = funclist3
    end
end

---
-- Write the function information in a format suitable for input to a hash
-- generator.
--
-- @param ofname Name of the output file to write to.  If it exists, it will
--  be overwritten.
--
function output_functions(ofname)
    local ofile, pos, s

    -- write that list
    ofile = io.open(ofname, "w")
    for i, k in ipairs(function_list) do
	s = _function_signature(k)
	ofile:write(s .. "\n")
    end
    ofile:close()
end

---
-- Generate the signature for the given function.
--
-- The signature consists of the name, a comma, and one byte per argument,
-- considering the return value of the function as the first argument.  Each
-- byte specifies the type, being an index into the ffi_type_map.  If the
-- high order bit is set, then two following bytes are an index into
-- the structure list.
--
-- @param fname Name of the function
-- @return A string with the signature, ready to be written to the function
--  output file.
function _function_signature(fname)
    return fname .. "," .. string.gsub(_function_arglist(funclist[fname],
	fname),
	".", function(c) return string.format("\\%03o", string.byte(c)) end)
end

function _function_arglist(arg_list, fname)
    local tp, val, s, type_id

    s = ""
    for i, arg_info in ipairs(arg_list) do
	type_id = arg_info[1]
	-- no bit size given for function parameters.
	tp = resolve_type(type_id)
	val = tp.fid

	-- char* return values
	if i == 1 and tp.name == "char" and tp.pointer == 1 then
	    val = _handle_char_ptr_returns(arg_list, tp, fname)
	end

	if tp.detail ~= nil then
	    val = bit.bor(val, 0x80)
	end
	-- print("func", fname, "arg", i, "type", tp.name, "val", val)

	s = s .. string.char(val)
	if tp.detail ~= nil then
	    local id
	    if tp.name == "func" then
		-- A function's prototype might not yet be registered.  This
		-- can happen if a function has a function parameter that will
		-- be registered later.  See ... for how this is handled.
		id = tp.detail.proto_id
		if not id then return nil end
	    else
		-- structures must be registered already
		id = tp.detail.struct_id
	    end

	    assert(id, "arglist type not registered: " .. type_id
		.. " in function " .. fname)
	    s = s .. string.char(bit.band(bit.rshift(id, 8), 255),
		bit.band(id, 255))
	end
    end

    -- determine maximum number of function arguments (including return value)
    max_func_args = math.max(max_func_args, #arg_list)

    return s
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
-- Given a fundamental type, return the suggested FFI type.  Also creates
-- an entry in the argument_types ENUM if it doesn't exist yet.
--
-- Available FFI types: see /usr/include/ffi.h
--
-- @param ft A fundamental type (from the table fundamental_ifo)
-- @return An entry from fundamental_map
--
function fundamental_to_ffi(ft)
    local v = fundamental_map[ft.name]

    if v then return v end

    -- pointer types have this default entry
    if ft.pointer > 0 then
	return { "pointer", 0, "ptr", nil, nil, nil }
    end


    print("Unknown type " .. ft.name)
    return nil
end

local _type_names = {}
local _type_name_offset = 0

function _type_name_add(s)
    local ofs = _type_name_offset
    _type_name_offset = ofs + string.len(s) + 1	    -- +1 because of NUL byte
    _type_names[#_type_names + 1] = '"' .. s .. '\\0"'
    return ofs
end

function _type_names_flush(ofile)
    s = "const char ffi_type_names[] = \n"
	.. table.concat(_type_names, "\n")
	.. ";\n\n";
    ofile:write(s)
end

---
-- Write the list of fundamental types to an output file, which can be compiled
-- as C code.
--
-- @param ofname Name of the file to write to, which will be overwritten if
--  it exists.
--
function output_types(ofname)
    local ofile, ffitype, type_code, ofs

    ofile = io.open(ofname, "w")
    ofs = _type_name_add("INVALID")
    ofile:write(string.format("struct ffi_type_map_t ffi_type_map[] = {\n"
	.. "  { %d, },\n", ofs))

    for i, v in ipairs(fundamental_ifo) do
	ffitype = fundamental_to_ffi(v) or { nil, 0, nil, nil, nil, nil }

	-- Here the second char* entry gets the "4" flag to mark it as const.
	-- This is then used in src/types.c:ffi2lua_char_ptr.
	local flags = (i == char_ptr_second) and 4 or 0

	ofs = _type_name_add(v.name)
	ofile:write(string.format("  { %d, %d, %d, %d, %s, %s, %s, %s, %s }, "
	    .. "/* %s */\n",
	    ofs,		-- name_ofs
	    v.bit_len or 0,	-- bit_len
	    v.pointer,		-- indirections
	    ffitype[2] + flags,	-- flags
	    ffitype[3] and "LUA2FFI_" .. string.upper(ffitype[3]) or 0,
	    ffitype[4] and "FFI2LUA_" .. string.upper(ffitype[4]) or 0,
	    ffitype[5] and "LUA2STRUCT_" .. string.upper(ffitype[5]) or 0,
	    ffitype[6] and "STRUCT2LUA_" .. string.upper(ffitype[6]) or 0,
	    ffitype[1] and "LUAGTK_FFI_TYPE_" .. string.upper(ffitype[1]) or 0,
	    v.name
	))
    end

    -- number of entries; +1 because of the first INVALID which is not
    -- in the fundamental_ifo table.
    ofile:write(string.format("};\nconst int ffi_type_count = %d;\n",
	#fundamental_ifo + 1))
    _type_names_flush(ofile)
    ofile:close()
end

---
-- Write a sorted list of globals.  Maybe not required, but anyway, doesn't
-- hurt.  It is not used yet.
--
function output_globals(ofname)
    local keys, ofile, gl, tp, ffitype, detail_id = {}
    local count = 0

    for k, v in pairs(globals) do
	keys[#keys + 1] = v.name
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")
    ofile:write "const struct globals[] = {\n"
    for i, name in pairs(keys) do
	gl = globals[name]
	-- Globals (from "Variable" XML tags) don't have a specific bit size
	-- given.
	tp = resolve_type(gl.type)
	if tp.detail and not tp.detail.name then
	    print("warning, no name for", tp.name, tp.fid)
	    tp.detail.name = "?"
	end

	if tp.name == 'func' then
	    detail_id = tp.detail.proto_id
	    assert(detail_id, "function without proto_id")
	elseif tp.detail then
	    detail_id = tp.detail.struct_id
	    assert(detail_id, "structure without struct_id")
	else
	    detail_id = 0
	end

	ofile:write(string.format("  { \"%s\", %d, %d }, /* %s */\n", name,
	    tp.fid, detail_id,
	    tp.name .. string.rep("*", tp.pointer)
		.. (tp.detail and (" " .. tp.detail.name) or "") ))
	count = count + 1
    end
    ofile:write "  { NULL, 0, 0 }\n};\n"
    ofile:write(string.format("const int globals_count = %d;\n", count))
    ofile:close()
end

---
-- Look at each structure.  If it derives from GObject, mark it as widget.
-- NOT USED.  Runtime detection of widgets.
--
function detect_widgets()
    for id, tp in pairs(typedefs) do
	if tp.in_use and tp.is_widget == nil then
	    look_at(tp)
	end
    end
end

---
-- st is the structure definition.  Detect the element with offset 0, then
-- look at its type.  If it is "GObject", done.  If it is marked as widget,
-- return true.  If it is 
-- struct = { name, size, align, members, _type, fields } (same for enum)
--	fields={}	    -- [ID] = { name, offset, ... }
function look_at(tp)
    local tp2

    -- already set?
    if tp.is_widget ~= nil then return end

    -- follow typdefs
    if tp.type == "typedef" then
	tp2 = typedefs[tp.what]
	look_at(tp2)
	tp.is_widget = tp2.is_widget
	return
    end

    -- This is the base class; anything derived from this can be considered
    -- a widget.
    if tp.name == "GObject" then
	tp.is_widget = true
	return
    end

    -- only structures (and possibly unions) can be widgets.
    if tp.type ~= "struct" and tp.type ~= "union" then
	tp.is_widget = false
	return
    end

    -- determine the element at offset zero, which can be considered the
    -- parent type in the C based object orientation of Gtk.
    for id, el in pairs(tp.struct.fields) do
	if tonumber(el.offset) == 0 then
	    tp2 = typedefs[el.type]
	    if tp2.is_widget == nil then
		look_at(tp2)
	    end

	    tp.is_widget = tp2.is_widget
	    if tp.is_widget then
		print("Widget:", tp.name)
	    end
	    return
	end
    end

    -- no structure element at offset zero??
    if #tp.struct.fields > 0 then
	print("Warning: no structure element at offset zero in structure "
	    .. tp.name)
    end

    tp.is_widget = false
end

-- Read a list of specs how to handle char* return values of functions.
function get_extra_data()
    for line in io.lines("src/char_ptr_handling.txt") do
	local func, method = string.match(line, '^([^#,]*),(%d)$')
	if func and method then
	    _set_char_ptr_handling(func, tonumber(method))
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
	-- print("ignore char handling", parent, item)
	free_methods[funcname] = method
	return
    end

    local fi = funclist[funcname]
    if not fi then
	print("Warning: undefined function in char_ptr_handling: " .. funcname)
	return
    end
--    assert(fi, "Undefined function in char_ptr_handling.txt: " .. funcname)
    assert(fi.free_method == nil, "Duplicate in char_ptr_handling.txt: "
	.. funcname)
    tp = resolve_type(fi[1][1])

    -- must be a char*, i.e. with one level of indirection
    assert(tp.name == "char")
    assert(tp.pointer == 1)

    -- If a return type is "const char*", then this usually means "do not
    -- free it".  Alas, this rule of thumb has exceptions.
    if not (method == 0 and tp.const or method == 1 and not tp.const) then
	print("Warning: inconsistency of free method of function " .. funcname)
    end

    fi.free_method = method
end
    

-- MAIN --
if #arg ~= 2 then
    print "Parameter: Output directory, and XML file to parse"
    return
end

parse_xml(arg[2])
get_extra_data()
mark_ifaces_as_used()
analyze_functions()
analyze_globals()
analyze_structs()
mark_all_enums_as_used()
mark_override()

-- detect_widgets()

-- before writing the structures, the functions must be looked at to
-- find prototypes that need registering.

output_structs(arg[1] .. "/gtkdata.structs.c")
output_enums(arg[1] .. "/gtkdata.enums.txt")
output_functions(arg[1] .. "/gtkdata.funcs.txt")
output_types(arg[1] .. "/gtkdata.types.c")
output_globals(arg[1] .. "/gtkdata.globals.c")
-- output_argument_types(arg[1] .. "/gtkdata.argtypes.h")

-- Output some maximum values.  This is useful to decide how many bits the
-- various fields of the structures must have.
print("max_bit_offset", max_bit_offset)
print("max_bit_length", max_bit_length)
print("max_struct_string_offset", string_offset)
print("max_struct_size", max_struct_size)
print("max_type_id", #fundamental_ifo)
print("max_struct_id", max_struct_id)
print("max_func_args", max_func_args)


