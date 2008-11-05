-- vim:sw=4:sts=4
-- Functions to output the .c and .txt files
--

local M = {}
setmetatable(M, {__index=_G})
setfenv(1, M)

max_type_id = 0   -- last type_id in use
struct_count = 0    -- structs or unions
max_struct_size = 0
max_struct_elems = 0

---
-- Generate a sorted list of ENUMs suitable for postprocessing with a hashing
-- tool.
--
-- Each entry consist of the name, ",", the 16 bit number of the structure
-- number (describing this ENUM), and the actual value in a low to high byte
-- order.  Only as many bytes are output as are required to represent the given
-- value.  The value zero has no bytes.
--
-- Call this function _after_ output_structs, because there the type_ids
-- are assigned.
--
-- @param ofname Name of the output file
--
function output_enums(ofname)
    local keys, t, ofile, s, enum, val, prefix = {}

    for k, enum in pairs(xml.enum_values) do
	t = typedefs[enum.context]
	assert(t, "Unknown context (structure) " .. tostring(enum.context)
	    .. " for enum " .. k)
	if t.in_use or t.enum_redirect then
	    keys[#keys + 1] = k
	end
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")

    for i, name in pairs(keys) do
	enum = xml.enum_values[name]
	val = enum.val
	-- val = tonumber(enum.val)
	t = typedefs[enum.context]
	if t.enum_redirect then
	    t = typedefs[t.enum_redirect]
	end
	s = encode_enum(name, val, t.type_idx)
	ofile:write(s .. "\n")
    end
    ofile:close()
end


---
-- Helper function to build a string table; used for the structures
--

local string_buf = {}	-- name => { tbl, buf, offsets, offset }

local elem_start = 0	-- current position in the element table

---
-- Add another string to the string table and return the offset.  If the string
-- already exists, reuse.
--
-- @param s  the string to store
-- @param omit_nul  If true, don't append a nul byte
-- @return byte offset into the string table
--
function store_string(bufname, s, omit_nul)

    local buf = string_buf[bufname]
    if not buf then
	buf = {
	    tbl={},		    -- [string] => offset
	    buf={},		    -- [i] = string #i
	    offsets={},	    -- [i] => offset of this entry (for debugging)
	    next_ofs=0	    -- offset of next string to be added
	}
	string_buf[bufname] = buf
    end

    if not omit_nul then
	s = s .. string.char(0)
    end
    local len = #s

    -- store a new entry if it doesn't exist yet.
    local ofs = buf.tbl[s]
    if not ofs then
	ofs = buf.next_ofs
	buf.next_ofs = ofs + len
	buf.tbl[s] = ofs
	buf.buf[#buf.buf + 1] = s
	buf.offsets[#buf.offsets + 1] = ofs
    end

    return ofs
end

---
-- Write the string tables.  The strings that need it already have a trailing
-- NUL byte.  Note that formatting with %q is NOT enough, C needs to escape
-- more characters.
--
function output_strings(ofile)
    local maxlen
    for name, buf in pairs(string_buf) do
	maxlen = 0
	ofile:write(string.format("const %schar type_strings_%s[] = \n",
	    name == "proto" and "unsigned " or "", name));
	for i, s in ipairs(buf.buf) do
	    ofile:write(string.format(" \"%s\" /* %d */\n",
		string.gsub(s, "[^a-zA-Z0-9_. *]",
		function(c) return string.format("\\%03o", string.byte(c)) end),
		buf.offsets[i]))
	    maxlen = math.max(maxlen, #s)
	end
	buf.maxlen = maxlen
	ofile:write(";\n\n");
    end
end

---
-- Add the information for one structure (with all its fields) to the output.
--
-- @param ofile  Output file handle
-- @param tp  typedef of the structure
-- @param struct_name  Name of the structure
--
function output_one_struct(ofile, tp, struct_name)
    local st, member, ofs
    st = tp.struct

    -- already stored?
    if st.elem_start then return end

    st.elem_start = elem_start
    struct_count = struct_count + 1

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
	    ofs = store_string("elem", member.name or member_name)

	    tp = types.resolve_type(member.type)
	    if not tp.fid then
		print("no FID for", tp.full_name, member.name or member_name)
	    end

	    -- For functions, generate a prototype (or reuse one from the
	    -- list), and output the proto_ofs below.  Because the IDs of all
	    -- used structures must be known, this can only be called after
	    -- the assignment of type_ids.
	    if tp.detail then
		if tp.name == 'func' then
		    types.register_prototype(tp.detail, string.format("%s.%s",
			struct_name, member.name or member_name))
		end
	    end

	    local type_idx = tp.type_idx
	    assert(type_idx, "no type_idx set for " .. tp.full_name)
	    assert(type_idx ~= 0)
	    max_type_id = math.max(max_type_id, type_idx)

	    -- name offset, bit offset, bit length (0=see detail),
	    -- fundamental type id, type detail (0=none)
	    local s = string.format(" { %d, %d, %d, %d }, ",
		ofs, member.offset, member.size or tp.size or 0, type_idx)
	    s = s .. string.rep(" ", #s < 32 and (32 - #s) or 0)
	    s = s .. string.format("/* %s %s.%s */\n", tp.full_name,
		struct_name, member.name or member_name)
	    ofile:write(s)

	    elem_start = elem_start + 1
	end
    end

    st.elem_count = elem_start - st.elem_start
end

---
-- Write a C file with the structure information, suitable for compilation
-- and linking to the library.
--
-- @param ofname Name of the output file to write to.  If it exists, it will
-- be overwritten.
--
function output_types(ofname)

    local keys = typedefs_sorted
    local name2id = typedefs_name2id

    ofile = io.open(ofname, "w")
    ofile:write("#include \"luagtk.h\"\n")

    -- generate the list of struct/union elements
    -- fields: name_ofs, bit_offset, bit_len, ffi_type_id, type_detail
    elem_start = 0
    ofile:write("const struct struct_elem elem_list[] = {\n")
    for i, full_name in ipairs(keys) do
	t = typedefs[name2id[full_name]]
	assert(t)
	assert(t.extended_name)
	t.name_ofs = store_string("types", t.extended_name)

	if t.detail and t.detail.struct then
	    output_one_struct(ofile, t.detail, full_name)
	end
    end
    ofile:write("};\n\n")

    -- type_list.
    ofile:write("const struct type_info type_list[] = {\n"
	.. " { 0, 0 }, /* placeholder for undefined structures */\n")
    for i, full_name in ipairs(keys) do
	t = typedefs[name2id[full_name]]
	assert(t.name_ofs, "no name_ofs defined for type " .. full_name)
	assert(t.type_idx, "no type_id defined for type " .. full_name)
--	assert(t.type_idx == i, "type ID mismatch: " .. t.type_idx .. " vs "
--	    .. i .. " for type " .. full_name)

	local detail = t.detail

	-- common elements
	local fu = types.ffi_type_map[t.fid]
	assert(t.pointer == fu.pointer, "pointer mismatch for " .. t.full_name
	    .. ": " .. t.pointer .. " vs " .. fu.pointer .. ", fu=" .. fu.name)
	s = string.format(" { %d, %d, %d", t.fid, t.const and 1 or 0,
	    t.name_ofs)

	if detail and detail.struct then
	    st = detail.struct
	    assert(st)
	    local struct_size = (st.size or 0)/8
	    s = s .. string.format(", { st: { %d, %d, %d } } }, /* %d: %s %s */\n",
		struct_size, st.elem_start, st.elem_count,
		t.type_idx, t.fname or "", full_name)
	    max_struct_size = math.max(max_struct_size, struct_size)
	    max_struct_elems = math.max(max_struct_elems, st.elem_count)
	elseif t.fname == "func" then
	    s = s .. string.format(", { fu: { %d } } }, /* %d: func %s */\n",
		detail.proto_ofs, t.type_idx, full_name)
	else
	    s = s .. string.format(" }, /* %d: %s */\n", t.type_idx, full_name)
	end

	ofile:write(s)
    end

    ofile:write("};\nconst int type_count = " .. #keys .. ";\n\n")


    output_strings(ofile)
    ofile:close()
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
    return fname .. "," .. string.gsub(types.function_arglist(
	xml.funclist[fname], fname),
	".", function(c) return string.format("\\%03o", string.byte(c)) end)
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
function output_fundamental_types(ofname)
    local ofile, ffitype, type_code, ofs

    ofile = io.open(ofname, "w")
    ofs = _type_name_add("INVALID")
    ofile:write(string.format("struct ffi_type_map_t ffi_type_map[] = {\n"
	.. "  { %d, },\n", ofs))

    for i, v in ipairs(types.ffi_type_map) do
	ffitype = types.fundamental_to_ffi(v) or { nil, 0, nil, nil, nil, nil }
	ofs = _type_name_add(v.name)
	ofile:write(string.format("  { %d, %d, %d, %d, %s, %s, %s, %s, %s }, "
	    .. "/* %d %s */\n",
	    ofs,		-- name_ofs
	    v.bit_len or 0,	-- bit_len
	    v.pointer,		-- indirections
	    ffitype[2],		-- flags
	    ffitype[3] and "LUA2FFI_" .. string.upper(ffitype[3]) or 0,
	    ffitype[4] and "FFI2LUA_" .. string.upper(ffitype[4]) or 0,
	    ffitype[5] and "LUA2STRUCT_" .. string.upper(ffitype[5]) or 0,
	    ffitype[6] and "STRUCT2LUA_" .. string.upper(ffitype[6]) or 0,
	    ffitype[1] and "LUAGTK_FFI_TYPE_" .. string.upper(ffitype[1]) or 0,
	    i, v.name
	))
    end

    -- number of entries; +1 because of the first INVALID which is not
    -- in the ffi_type_map table.
    ofile:write(string.format("};\nconst int ffi_type_count = %d;\n\n",
	#types.ffi_type_map + 1))
    _type_names_flush(ofile)
    ofile:close()
end


---
-- Write a sorted list of globals.  Maybe not required, but anyway, doesn't
-- hurt.  It is not used yet.
--
function output_globals(ofname)
    local keys, ofile, gl, tp = {}
    local count = 0

    for k, v in pairs(xml.globals) do
	keys[#keys + 1] = v.name
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")
    ofile:write "const char luagtk_globals[] =\n"
    for i, name in pairs(keys) do
	gl = xml.globals[name]
	tp = types.resolve_type(gl.type)
	assert(tp.full_name)
	assert(tp.type_idx)

	ofile:write(string.format("  \"%s\\000%s\" /* %d: %d=%s */\n",
	    name, format_2bytes(tp.type_idx), i, tp.type_idx, tp.full_name))
	count = count + 1
    end
    ofile:write "  \"\\000\";\n"
    ofile:close()
end


-- Output some maximum values.  This is useful to decide how many bits the
-- various fields of the structures must have.
function show_statistics()
    info_num("Max. structure size (bytes)", max_struct_size)
    info_num("Number of types", max_type_id)
    info_num("Number of structures", struct_count)
    info_num("Number of functions", #function_list)
    info_num("Max. number of struct elements", max_struct_elems)
    for name, buf in pairs(string_buf) do
	info_num("Strings " .. name .. " count", #buf.buf)
	info_num("Strings " .. name .. " maxlen", buf.maxlen)
	info_num("Strings " .. name .. " bytes", buf.next_ofs)
    end
end

return M

