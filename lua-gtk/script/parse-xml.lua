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

funclist = {}	    -- [name] = [rettype, arg1type, arg2type, ...]
unhandled = {}	    -- [name] = true
globals = {}	    -- [name] = {...}
typedefs = {}	    -- [id] = { type=..., name=..., struct=... }
  -- struct = { name, size, align, members, _type, fields } (same for enum)
enum_values = {}    -- [name] = { val, context }
max_bit_offset = 0
max_bit_length = 0
max_struct_id = 0
max_func_args = 0
max_struct_size = 0
fundamental_name2id = {}
prototypes = {}

type_override = {
    ["GtkObject.flags"] = { "GtkWidgetFlags" },
}

-- Some structures would not be included, because they are not used by
-- any existing function.  Include them anyway...
used_override = {
    ["GtkFileChooserWidget"] = true,
    ["GtkFileChooserDialog"] = true,
}

-- List of fundamental types existing.  the fid (fundamental id) is an index
-- into this table.  Append as many "*" to the name as there are indirections.
-- More fundamental types will be created and added as found.  No in_use field
-- exists, as these entries are only created during the mark_as_used phase.
fundamental_ifo = {
    { name="vararg" },
    { name="func" },
    { name="struct" },
    { name="union" },
    { name="enum" },
}

-- init fundamental types
for i, v in ipairs(fundamental_ifo) do
    fundamental_name2id[v.name] = i
    v.pointer = 0	-- number of indirections
end
next_fid = #fundamental_ifo + 1


---
-- For each fundamental type, give the FFI type to use when building
-- the parameter list, and a numerical type for handling the types in
-- a switch statement.
--
-- {ffi_type, flags, lua2ffi, ffi2lua, lua2struct, struct2lua}
--
fundamental_map = {
    -- Note: ffi_type for vararg is "void".  This is not exactly true, as
    -- a vararg will be replaced by zero or more arguments of variable type in
    -- an actual function call.  types.c:lua2ffi_vararg will replace it anyway
    -- so it could be anything, but it can't be nil, because then
    -- call.c:_call_build_parameters would complain about using a type with
    -- undefined ffi_type.
    ["vararg"] = { "void", 0, "vararg", nil, nil, nil },
    ["void"] = { "void", 0, nil, "void", nil, nil },
    ["enum"] = { "uint", 3, "enum", "enum", "enum", "enum" },
    ["struct"] = { "pointer", 0, nil, nil, nil, "struct" },
	    -- for globals XXX may be wrong
    ["union"] = { "pointer", 0, nil, nil, nil, "struct" },
	    -- same as struct, actually

    ["short unsigned int"] = { "ushort", 3, "long", "long", "long", "long" },
    ["short int"] = { "sshort", 3, "long", "long", "long", "long" },
    ["unsigned char"] = { "uchar", 3 },
    ["signed char"] = { "schar", 3 },
    ["char"] = { "schar", 3 },
    ["long long unsigned int"] = { "ulong", 3, "longlong" },
    ["long unsigned int"] = { "ulong", 3, "long", "long", "long" },
    ["long long int"] = { "slong", 3, "longlong" },
    ["long int"] = { "slong", 3, "long", "long", "long", "long" },
    ["int"] = { "sint", 3, "long", "long", "long", "long" },
    ["unsigned int"] = { "uint", 3, "long", "long", "long", "long" },
    ["long double"] = { "double", 1, "double" },
    ["double"] = { "double", 1, "double", "double" },
    ["float"] = { "float", 1, "float" },
    ["boolean"] = { "uint", 3, "bool", "bool" },

    -- pointer types
    ["struct*"] = { "pointer", 0, "struct_ptr", "struct_ptr", nil, "struct_ptr" },
    ["union*"] = { "pointer", 0, "struct_ptr", "struct_ptr", nil, "struct_ptr" },
    ["char*"] = { "pointer", 0, "char_ptr", "char_ptr", nil, "char_ptr" },
    ["char**"] = { "pointer", 0, "char_ptr_ptr", "char_ptr_ptr", nil, nil },
    ["unsigned char*"] = { "pointer", 0, "char_ptr", "char_ptr", nil, "char_ptr" },
    ["void*"] = { "pointer", 0, "void_ptr", "void_ptr", nil, nil },
    ["int*"] = { "pointer", 0, "int_ptr", "int_ptr", nil, nil },
    ["unsigned int*"] = { "pointer", 0, "int_ptr", "int_ptr", nil, nil },
    ["func*"] = { "pointer", 0, "func_ptr", nil, "func_ptr" },
    ["struct**"] = { "pointer", 0, "struct_ptr_ptr", "struct_ptr_ptr" },
}

---
-- Check whether a given fundamental type is already known.  If not,
-- add it.  Anyway, return the fid for this type.
--
function register_fundamental(name, pointer, bit_len)
    name = name .. string.rep("*", pointer)
    id = fundamental_name2id[name]
    if id then return id end
    fundamental_ifo[#fundamental_ifo + 1] = {
	name = name,
	pointer = pointer,
	bit_len = bit_len
    }
    fundamental_name2id[name] = next_fid
    next_fid = next_fid + 1
    return next_fid - 1
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
	curr_func = { el.returns }
	funclist[el.name] = curr_func
    end,

    -- discard the argument names, just keep the type.
    Argument = function(p, el)
	if curr_func then
	    curr_func[#curr_func + 1] = el.type
	end
    end,

    -- translated to vararg argument later
    Ellipsis = function(p, el)
	if curr_func then
	    curr_func[#curr_func + 1] = "vararg"
	end
    end,

    -- declare a type being a function prototype
    FunctionType = function(p, el)
	curr_func = { el.returns }
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
	    bits=el.bits }
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

--	fundamental_name2id[el.name] = next_fid
--	fundamental_ifo[next_fid] = { name=el.name, type_id=el.id, pointer=0,
--	    bit_len=el.size }
--	next_fid = next_fid + 1

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
	    mark_typedef_in_use(tp)
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
-- @param type_id Type identifier, which is a number with leading _
--
-- @return Table with fields name, bit_len, bit_size, detail, pointer, array,
--  fid
--
function resolve_type(type_id)
    if type_id == nil then return {} end
    local res = { bit_len=0, detail=nil, pointer=0, array=0 }

    if type_id == "vararg" then
	res.name = type_id
    end

    while typedefs[type_id] do
	tp = typedefs[type_id]

	-- pointer to something
	if tp.type == "pointer" then
	    res.bit_len = tp.size
	    res.pointer = res.pointer + 1
	    -- tp.align not used
	    type_id = tp.what

	-- a typedef, i.e. an alias
	elseif tp.type == "typedef" or tp.type == "qualifier" then
	    -- qualifier: discarded
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
-- @param s the string to store
-- @return byte offset into the string table
--
function store_string(s, omit_nul)
    local ofs = string_table[s]
    if ofs ~= nil then return ofs end
    ofs = string_offset

    -- escape
    local len = #s
--    local s = string.gsub(s, "%c", function(c)
--	return string.format("\\%03o", string.byte(c)) end)

    if not omit_nul then
	s = s .. string.char(0) -- "\\000"
	len = len + 1
    end

    string_offset = ofs + len

--    string_offset = ofs + string.len(s) + 1	    -- plus NUL byte
    string_table[s] = ofs
    string_buf[#string_buf + 1] = s
    return ofs
end

---
-- Add the information for one structure (with all its fields) to the output.
--
function output_one_struct(ofile, tp)
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

	    tp = resolve_type(member.type)
	    if not tp.fid then
		print("no FID for", tp.name, member.name or member_name)
	    end

	    -- For functions, generate a prototype (or reuse one from the
	    -- list), and output the proto_id below.  Because the IDs of all
	    -- used structures must be known, this can only be called after
	    -- the assignment of struct_ids.
	    if tp.name == "func" then
		register_prototype(tp.detail)
	    end

	    -- name offset, bit offset, bit length (0=see detail),
	    -- fundamental type id, type detail (0=none)
	    ofile:write(string.format(" { %d, %d, %d, %d, %d }, /* %s */\n",
		ofs, member.offset, tp.bit_len, tp.fid,
		tp.detail and (tp.detail.proto_id or tp.detail.struct_id) or 0,
		member.name or member_name))
	    elem_start = elem_start + 1
	end
    end
end

-- 
-- @param proto  Array of type_ids describing the return value and arguments
--   to this function type.
-- @return  Offset in the string table where the prototype is defined.
--   It may be reused for identical signatures of different functions.
--
function register_prototype(typedef)
    if typedef.proto_id then return end
    local sig = table.concat(typedef.prototype, ",")
    local proto_ofs = prototypes[sig]

    if not proto_ofs then
	local sig = _function_arglist(typedef.prototype)

	-- prepend a length byte
	sig = string.char(#sig) .. sig

	proto_ofs = store_string(sig, true)
	prototypes[sig] = proto_ofs
    end

    typedef.proto_id = proto_ofs
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
    for k, v in pairs(typedefs) do
	if v.in_use and types[v.type] then
	    keys[#keys + 1] = v.name
	    name2id[v.name] = k
	end
    end
    table.sort(keys)

    -- assign numbers to the structures; don't use 0.
    local struct_id = 1
    for i, name in ipairs(keys) do
	tp = typedefs[name2id[name]]
	tp.struct_id = struct_id
	struct_id = struct_id + 1
    end
    max_struct_id = struct_id - 1

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
	    output_one_struct(ofile, tp)
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
-- Mark all these data types as used.
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
-- Mark all data types used by the functions (return type, arguments) as used.
--
function _function_analyze(fname)
    for i, type_id in ipairs(funclist[fname]) do
	mark_type_id_in_use(type_id)
    end
end


---
-- Run through all globals and mark the types as used.
--
function analyze_globals()
    for k, var in pairs(globals) do
	mark_type_id_in_use(var.type)
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
	    mark_typedef_in_use(typedef)
	end
    end
end

-- given a type_id, make sure the base type for it is marked used.
function mark_type_id_in_use(type_id)
    local tp = resolve_type(type_id)
    if tp.detail then
	return mark_typedef_in_use(tp.detail)
    end
end

---
-- Recursively mark this typedef and all subtypes as used.
--
function mark_typedef_in_use(typedef)
    local ignore_types = { constructor=true, union=true, struct=true }
    local field, tp2

    -- already marked?
    if typedef.in_use then return end

    typedef.in_use = true

    -- mark elements of a structure
    if typedef.struct then

	for i, name in ipairs(typedef.struct.members) do
	    field = typedef.struct.fields[name]
	    if not ignore_types[field.type] then
		mark_type_id_in_use(field.type)
	    elseif field.type ~= "constructor" then
		print("ignore??", name, field.type)
	    end
	end
    end

    -- mark types of arguments
    if typedef.prototype then
	for i, type_id in ipairs(typedef.prototype) do
	    mark_type_id_in_use(type_id)
	end
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
    -- return fname .. "," .. _function_arglist(funclist[fname])
    return fname .. "," .. string.gsub(_function_arglist(funclist[fname]),
	".", function(c) return string.format("\\%03o", string.byte(c)) end)
end

function _function_arglist(arg_list)
    local tp, val, s

    s = ""
    for i, type_id in ipairs(arg_list) do
	tp = resolve_type(type_id)
	val = tp.fid
	if tp.detail ~= nil then
	    val = bit.bor(val, 0x80)
	end
	s = s .. string.char(val)
	-- s = s .. string.format("\\%03o", val)
	if tp.detail ~= nil then
	    if tp.name == "func" then register_prototype(tp.detail) end
	    local id = tp.detail.struct_id or tp.detail.proto_id
	    assert(id, "arglist type not registered: " .. type_id)
	    s = s .. string.char(bit.band(bit.rshift(id, 8), 255),
		bit.band(id, 255))
	    -- s = s .. format_2bytes(id)
	end
    end

    -- determine maximum number of function arguments (including return value)
    max_func_args = math.max(max_func_args, #arg_list)

    return s
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

	ofs = _type_name_add(v.name)
	ofile:write(string.format("  { %d, %d, %d, %d, %s, %s, %s, %s, %s },\n",
	    ofs,		-- name_ofs
	    v.bit_len or 0,	-- bit_len
	    v.pointer,		-- indirections
	    ffitype[2],		-- flags
	    ffitype[3] and "LUA2FFI_" .. string.upper(ffitype[3]) or 0,
	    ffitype[4] and "FFI2LUA_" .. string.upper(ffitype[4]) or 0,
	    ffitype[5] and "LUA2STRUCT_" .. string.upper(ffitype[5]) or 0,
	    ffitype[6] and "STRUCT2LUA_" .. string.upper(ffitype[6]) or 0,
	    ffitype[1] and "LUAGTK_FFI_TYPE_" .. string.upper(ffitype[1]) or 0
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
    local keys, ofile, gl, tp, ffitype = {}
    local count = 0

    for k, v in pairs(globals) do
	keys[#keys + 1] = v.name
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")
    ofile:write "const struct globals[] = {\n"
    for i, name in pairs(keys) do
	gl = globals[name]
	tp = resolve_type(gl.type)
	if tp.detail and not tp.detail.name then
	    print("warning, no name for", tp.name, tp.fid)
	    tp.detail.name = "?"
	end
	ofile:write(string.format("  { \"%s\", %d, %d }, /* %s */\n", name,
	    tp.fid,
	    tp.detail and (tp.detail.struct_id or tp.detail.proto_id) or 0,
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
    

-- MAIN --
if #arg ~= 2 then
    print "Parameter: Output directory, and XML file to parse"
    return
end

parse_xml(arg[2])
analyze_functions()
analyze_globals()
mark_all_enums_as_used()
mark_ifaces_as_used()
mark_override()

-- detect_widgets()

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
print("max_type_id", next_fid - 1)
print("max_struct_id", max_struct_id)
print("max_func_args", max_func_args)


