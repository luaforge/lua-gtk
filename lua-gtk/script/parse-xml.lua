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

funclist = {}	    -- [name] = [rettype, arg1type, arg2type, ...]
unhandled = {}	    -- [name] = true
globals = {}	    -- [name] = {...}
typedefs = {}	    -- [id] = { type=..., name=..., struct=... }
  -- struct = { name, size, align, members, _type, fields } (same for enum)
enum_values = {}    -- [name] = { val, context }
max_bit_offset = 0
max_bit_length = 0
max_struct_id = 0
fundamental_name2id = {}

type_override = {
    ["GtkObject.flags"] = { "GtkWidgetFlags" },
}

-- Some structures would not be included, because they are not used by
-- any existing function.  Include them anyway...
used_override = {
    ["GtkFileChooserWidget"] = true,
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
    ["vararg"] = { "void", 0, "vararg", nil, nil, nil },
    ["void"] = { "void", 0, nil, "void", nil, nil },
    ["enum"] = { "uint", 3, "enum", "enum", "enum", "enum" },
    ["struct"] = { "pointer", 0, nil, nil, nil, "struct" },
	    -- for globals XXX may be wrong

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
    ["char*"] = { "pointer", 0, "char_ptr", "char_ptr", nil, "char_ptr" },
    ["unsigned char*"] = { "pointer", 0, "char_ptr", "char_ptr", nil, "char_ptr" },
    ["void*"] = { "pointer", 0, nil, "void_ptr", nil, nil },
    ["int*"] = { "pointer", 0, "int_ptr", "int_ptr", nil, nil },
}

---
-- Check whether a given fundamental type is already known.  If not,
-- add it.  Anyway, return the fid for this type.
--
function register_fundamental(name, pointer, bit_len)
    name = name .. string.rep("*", pointer)
    id = fundamental_name2id[name]
    if id then return id end
    table.insert(fundamental_ifo, {
	name = name,
	pointer = pointer,
	bit_len = bit_len
    })
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
	    table.insert(curr_func, el.type)
	end
    end,

    -- translated to vararg argument later
    Ellipsis = function(p, el)
	if curr_func then
	    table.insert(curr_func, "vararg")
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
	    table.insert(members, w)
	end
    end

    typedefs[el.id] = { type=what, name=my_name, struct =  {
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
-- Format a 16 bit value into two octal bytes in low/high order.
--
function format_2bytes(val)
    return string.format("\\%03o\\%03o", bit.band(val, 255),
	bit.band(bit.rshift(val, 8), 255))
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
    local keys, ofile, s, enum, val = {}

    for k, enum in pairs(enum_values) do
	tp = typedefs[enum.context]
	if tp.in_use then
	    table.insert(keys, k)
	end
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")

    for i, name in pairs(keys) do
	enum = enum_values[name]
	val = enum.val
	s = ""
	while val > 0 do
	    s = string.format("\\%03o", bit.band(val, 255)) .. s
	    val = bit.rshift(val, 8)
	end
	s = format_2bytes(typedefs[enum.context].struct_id) .. s
	ofile:write(name .. "," .. s .. "\n")
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
	    res.detail = tp
	    res.name = tp.type
	    break

	-- fundamental type.
	elseif tp.type == "fundamental" then
	    -- tp.type, name, size, align
	    if res.bit_len == 0 and tp.size then res.bit_len = tp.size end
	    res.name = tp.name
	    break

	-- function pointer
	elseif tp.type == "func" then
	    -- print("Function returning " .. tp.prototype[1])
	    res.name = "func"
	    -- XXX return type of function tp.prototype[1] is lost.
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
function store_string(s)
    local ofs = string_table[s]
    if ofs ~= nil then return ofs end
    ofs = string_offset
    string_offset = ofs + string.len(s) + 1	    -- plus NUL byte
    string_table[s] = ofs
    table.insert(string_buf, s)
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

	    -- name offset, bit offset, bit length (0=see detail),
	    -- fundamental type id, type detail (-1=none)
	    ofile:write(string.format(" { %d, %d, %d, %d, %d }, /* %s */\n",
		ofs, member.offset, tp.bit_len, tp.fid,
		tp.detail and tp.detail.struct_id or -1,
		member.name or member_name))
	    elem_start = elem_start + 1
	end
    end
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

    -- Make a list of used structs/unions/enums to output, sort.
    for k, v in pairs(typedefs) do
	if v.in_use then
	    table.insert(keys, v.name)
	    name2id[v.name] = k
	end
    end
    print("In use:", #keys)
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

    -- struct_list

    -- 0 is the undefined structure; therefore start with 1.
--    local struct_count = 1

    ofile:write("const struct struct_info struct_list[] = {\n"
	.. " { 0, 0, 0 }, /* placeholder for undefined structures */\n")
    for i, name in ipairs(keys) do
	tp = typedefs[name2id[name]]
	st = tp.struct or { elem_start=tp.elem_start, size=0 }
	ofile:write(string.format(" { %d, %d, %d }, /* %s */\n",
	    tp.name_ofs, st.elem_start, (st.size or 0)/8, name))
--	struct_count = struct_count + 1
    end

    -- Last entry to calculate the elem count of the real last entry.  This one
    -- isn't being counted in the struct_count.
    ofile:write(string.format(" { %d, %d, %d }\n};\n",
	0, elem_start, 0))
    ofile:write("const int struct_count = " .. max_struct_id .. ";\n\n")

    -- string table
    ofile:write("const char struct_strings[] = \n");
    for i, s in pairs(string_buf) do
	ofile:write(string.format(" \"%s\\000\"\n", s))
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
	    table.insert(function_list, k)
	    _function_analyze(k)
	end
    end
    table.sort(function_list)
end

---
-- Mark all data types used by the functions (return type, arguments) as used.
--
function _function_analyze(fname)
    local tp

    for i, arg_i in ipairs(funclist[fname]) do
	tp = resolve_type(arg_i)

	-- if a structure/union/enum is referenced, mark that as used, too.
	if tp.detail then
	    _mark_in_use(tp.detail)
	end
    end
end


---
-- Run through all globals and mark the types as used.
--
function analyze_globals()
    local tp

    for k, var in pairs(globals) do
	tp = resolve_type(var.type)
	if tp.detail then
	    _mark_in_use(tp.detail)
	end
    end
end


---
-- Mark all types that are forced to be visible.
--
function mark_override()

    for k, v in pairs(typedefs) do
	if used_override[v.name] then
	    print("Override in use", k, v.name)
	    _mark_in_use(v)
	end
    end
end

---
-- Recursively mark this structure and all items in it as used.
--
function _mark_in_use(tp)
    local ignore_types = { constructor=true, union=true, struct=true }
    local field, tp2

    -- already marked?
    if tp.in_use then return end

    tp.in_use = true
    if not tp.struct then return end
    for i, name in ipairs(tp.struct.members) do
	field = tp.struct.fields[name]
	if not ignore_types[field.type] then
	    tp2 = resolve_type(field.type)
	    if not tp2.in_use then
		tp2.in_use = true
		if tp2.detail then _mark_in_use(tp2.detail) end
	    end
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
    local s, args, tp, val

    s = fname .. ","

    for i, arg_i in ipairs(funclist[fname]) do
	tp = resolve_type(arg_i)
	val = tp.fid
	if tp.detail ~= nil then
	    val = bit.bor(val, 0x80)
	end
	s = s .. string.format("\\%03o", val)
	if tp.detail ~= nil then
	    s = s .. format_2bytes(tp.detail.struct_id)
	end
    end

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
    table.insert(_type_names, '"' .. s .. '\\0"')
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
	.. "  { %d, 0, 0, 0, NULL},\n", ofs))

    for i, v in ipairs(fundamental_ifo) do
	ffitype = fundamental_to_ffi(v) or { nil, 0, nil, nil, nil, nil }

	ofs = _type_name_add(v.name)
	ofile:write(string.format("  { %d, %d, %d, %d, %s, %s, %s, %s, %s },\n",
	    ofs,		-- name_ofs
	    v.bit_len or 0,	-- bit_len
	    v.pointer,		-- indirections
	    ffitype[2],		-- flags
	    ffitype[1] and "&ffi_type_" .. ffitype[1] or "NULL",
	    ffitype[3] and "lua2ffi_" .. ffitype[3] or "NULL",
	    ffitype[4] and "ffi2lua_" .. ffitype[4] or "NULL",
	    ffitype[5] and "lua2struct_" .. ffitype[5] or "NULL",
	    ffitype[6] and "struct2lua_" .. ffitype[6] or "NULL"
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
	table.insert(keys, v.name)
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")
    ofile:write "const struct globals[] = {\n"
    for i, name in pairs(keys) do
	gl = globals[name]
	tp = resolve_type(gl.type)
	ofile:write(string.format("  { \"%s\", %d, %d }, /* %s */\n", name,
	    tp.fid,
	    tp.detail and tp.detail.struct_id or -1,
	    tp.name .. string.rep("*", tp.pointer)
		.. (tp.detail and (" " .. tp.detail.name) or "") ))
	count = count + 1
    end
    ofile:write "  { NULL, 0, -1 }\n};\n"
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
mark_override()

-- detect_widgets()

output_structs(arg[1] .. "/gtkdata.structs.c")
output_enums(arg[1] .. "/gtkdata.enums.txt")
output_functions(arg[1] .. "/gtkdata.funcs.txt")
output_types(arg[1] .. "/gtkdata.types.c")
output_globals(arg[1] .. "/gtkdata.globals.c")
-- output_argument_types(arg[1] .. "/gtkdata.argtypes.h")

print("max_bit_offset", max_bit_offset)
print("max_bit_length", max_bit_length)
print("max string offset in structure strings", string_offset)
print("max type_id", next_fid - 1)
print("max struct id", max_struct_id)


