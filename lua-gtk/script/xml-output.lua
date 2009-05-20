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
headerstrings = {}	-- to be written into the .h file
mi_strings = {}		-- to build the "struct modinfo"

-- Add another definition to the header
local function header(fmt, ...)
    headerstrings[#headerstrings + 1] = string.format(fmt, ...)
end

local function modinfo(fmt, ...)
    mi_strings[#mi_strings + 1] = string.format(fmt, ...)
end

---
-- Generate a sorted list of constants suitable for postprocessing with a
-- hashing tool.  Note that constants with a type that is not otherwise
-- used is omitted.
--
-- Each entry consist of the name, ",", and the encoded value of the constant,
-- depending on the method selected in xml-const.lua.
--
-- Call this function _after_ output_structs, because there the type_ids
-- are assigned.
--
-- @param ofname Name of the output file
--
function output_constants(ofname)
    local keys, t, ofile, s, enum, val, prefix = {}

    for k, enum in pairs(xml.enum_values) do
	t = typedefs[enum.context]
	assert(t, "Unknown context (structure) " .. tostring(enum.context)
	    .. " for enum " .. k)
	if (t.in_use or t.enum_redirect) and not t.no_good then
	    keys[#keys + 1] = k
	end
    end
    table.sort(keys)

    header("extern const struct hash_info hash_info_constants;")
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
	    next_ofs=1	    -- offset of next string to be added
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
    local maxlen, sig
    for name, buf in pairs(string_buf) do
	maxlen = 0
	sig = string.format("const %schar %sstrings_%s[]",
	    name == "proto" and "unsigned " or "", config.prefix, name)
	header("extern %s;", sig)
	ofile:write(sig .. " = \"\\0\"\n")
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

	    -- The structure element might not have a type idx; this can happen
	    -- for undefined types (?)
	    local type_idx = tp.type_idx
	    if not type_idx then
		print("Warning: No type_idx set for " .. struct_name .. "."
		    .. tostring(tp.name) .. " type_id " .. member.type)
		type_idx = 0
	    else
		assert(type_idx ~= 0, "invalid type_idx zero for "
		    .. struct_name .. "." .. tp.full_name)
	    end
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

file_to_module = {}

---
-- When a type is non-native, look through the aggregated include list of
-- the other modules.  If the path of the file that defines the given type
-- can be found, this is the module that handles the type.
--
-- If no module is responsible, no automatic loading can happen when the type
-- is accessed, and an error will happen, unless the user loads a third-party
-- module that handles it.
--
function _find_non_native_module(t)
    local ofs, fname

    if not t.file_id then return false end
    ofs = file_to_module[t.file_id]
    if ofs then return ofs end

    fname = xml.filelist[t.file_id]
    ofs = false
    for path, modname in pairs(non_native_includes) do
	if string.find(fname, path, 1, true) then
	    ofs = store_string("types", modname)	-- was "modules"
	    break
	end
    end

    if not ofs then
	print("Warning: no module found for type " .. tostring(t.full_name)
	    .. " from " .. fname)
    end

    -- found (or not, ofs == false in this case).
    file_to_module[t.file_id] = ofs
    return ofs
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
    local types_native, types_native_strings, types_foreign = 0, 0, 0
    local array_list = {}

    ofile = io.open(ofname, "w")
    ofile:write("#include \"common.h\"\n")

    -- Generate the list of struct/union elements for types that are
    -- "native" to this module.
    elem_start = 0
    header("extern const struct struct_elem %selem_list[];", config.prefix)
    ofile:write(string.format("const struct struct_elem %selem_list[] = {\n",
	config.prefix))
    for i, full_name in ipairs(keys) do
	t = typedefs[name2id[full_name]]
	assert(t)
	assert(t.extended_name)

	-- do not store anything for non-native types
	if t.is_native then
	    t.name_ofs = store_string("types", t.extended_name)
	    if t.detail and t.detail.struct then
		output_one_struct(ofile, t.detail, full_name)
	    end
	end
    end
    ofile:write("};\n\n")

    -- type_list.
    header("extern const union type_info %stype_list[];", config.prefix)
    ofile:write(string.format("const union type_info %stype_list[] = {\n"
	.. " { nn: { %d, 0, 0, 0 } }, /* placeholder for undefined types */\n",
	config.prefix, 0))

    for i, full_name in ipairs(keys) do
	t = typedefs[name2id[full_name]]
	assert(t.type_idx, "no type_id defined for type " .. full_name)
--	assert(t.type_idx == i, "type ID mismatch: " .. t.type_idx .. " vs "
--	    .. i .. " for type " .. full_name)

	local detail = t.detail

	-- integrity checks
	local fu = types.ffi_type_map[t.fid]
	assert(t.pointer == fu.pointer, "pointer mismatch for " .. t.full_name
	    .. ": " .. t.pointer .. " vs " .. fu.pointer .. ", fu=" .. fu.name)
	if t.is_native then
	    assert(t.name_ofs, "no name_ofs defined for type " .. full_name)
	else
	    assert(not t.name_ofs, "name_ofs defined for non-native type "
		.. full_name)
	end

	-- non-native types are output with the hash value of the type name.
	if not t.is_native then
	    local hash_value = gnomedev.compute_hash(full_name)
	    local name_ofs = _find_non_native_module(t)
	    local name_is_module

	    if name_ofs then
		name_is_module = 1
	    else
		-- no known module; need to store the type's name itself.
		name_ofs = store_string("types", t.extended_name) or 0
		name_is_module = 0
	    end
	    s = string.format(" { nn: { %d, %d, 0, %d, 0x%08x } }",
		0, name_is_module, name_ofs, hash_value)
	elseif t.fname == "func" then
	    assert(detail.proto_ofs, "Prototype not set for function "
		.. full_name)
	    s = string.format(" { fu: { %d, %d, %d, %d, 0, %d } }",
		2, t.fid, t.name_ofs, t.indir, detail.proto_ofs)
	elseif detail and detail.struct then
	    st = detail.struct
	    assert(st)
	    local struct_size = (st.size or 0)/8
	    s = string.format(
		" { st: { %d, %d, %d, %d, 0, %d, %d, %d, %d, %d } }",
		1, t.fid, t.name_ofs, t.indir, t.const and 1 or 0,
		t.array and 1 or 0,
		struct_size, st.elem_start, st.elem_count)
	    max_struct_size = math.max(max_struct_size, struct_size)
	    max_struct_elems = math.max(max_struct_elems, st.elem_count)

	    if t.array then
		_add_array(array_list, t)
	    end
	else
	    -- no structure.... must be a fundamental type.
	    s = string.format(
		" { st: { %d, %d, %d, %d, 0, %d, %d } }",
		3, t.fid, t.name_ofs, t.indir, t.const and 1 or 0,
		t.array and 1 or 0)
	    if t.array then
		_add_array(array_list, t)
	    end
	end

	s = s .. string.format(", /* %d: %s %s */\n",
	    t.type_idx, t.fname or "", full_name)

	if t.is_native then
	    types_native = types_native + 1
	    types_native_strings = types_native_strings + #t.extended_name
	else
	    types_foreign = types_foreign + 1
	end

	ofile:write(s)
    end

    ofile:write(string.format("};\n\n"))

    -- write that later into the .h file
    -- header("#define TYPE_COUNT %d", #keys)
    config.type_count = #keys

    -- List of array types and their dimensions
    array_list[#array_list + 1] = " { 0 }\n";
    header("extern const struct array_info %sarray_list[];", config.prefix)
    ofile:write(string.format(
	"const struct array_info %sarray_list[] = {\n%s};\n\n",
	config.prefix, table.concat(array_list)))

    output_strings(ofile)
--    if not string_buf.modules then
--	header("#define glib_strings_modules NULL")
--    end
    ofile:close()

    print "Type statistics:"
    print(string.format("native types=%d, strlen=%d", types_native,
	types_native_strings))
    print(string.format("foreign types=%d", types_foreign))
end

---
-- The type t is an array.  Append another line to the array_list.
function _add_array(array_list, t)
    -- print("array list", t.type_idx, t.full_name, t.array[1], t.array[2])
    array_list[#array_list + 1] = string.format(
	" { %d, { %d, %d } }, /* %s */\n",
	t.type_idx, t.array[1], t.array[2] or 0, t.full_name)
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
    header("extern const struct hash_info hash_info_functions;")
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
    header("const char %sffi_type_names[];", config.prefix)
    s = string.format("const char %sffi_type_names[] = \n%s;\n\n",
	config.prefix, table.concat(_type_names, "\n"))
    ofile:write(s)
end

---
-- Write the list of fundamental types to an output file, which can be compiled
-- as C code.  This is only required for the core module, which handles
-- all accesses to them.
--
-- @param ofname Name of the file to write to, which will be overwritten if
--  it exists.
--
function output_fundamental_types(ofname)
    local ofile, ffitype, type_code, ofs

    assert(config.is_core)
    ofile = io.open(ofname, "w")
    ofs = _type_name_add("INVALID")

    ofile:write("/* List of fundamental types.  See include/fundamental.lua */\n")
    ofile:write(string.format("struct ffi_type_map_t ffi_type_map[] = {\n"
	.. "  { %d, },\n", ofs))

    for i, v in ipairs(types.ffi_type_map) do
	ffitype = types.fundamental_to_ffi(v) or {}
	ofs = _type_name_add(v.name)
	ofile:write(string.format("  { %d, %d, %d, %s, %s, "
	    .. "%s }, /* %d %s */\n",
	    ofs,		-- name_ofs
	    v.bit_len or 0,	-- bit_len
	    v.pointer,		-- indirections
	    ffitype[2] and "CONV_" .. string.upper(ffitype[2]) or 0,
	    ffitype[3] and "STRUCTCONV_" .. string.upper(ffitype[3]) or 0,


	    ffitype[1] and "LUAGTK_FFI_TYPE_" .. string.upper(ffitype[1])
		or 0,
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

function output_fundamental_hash(ofname)
    local res, ofile = {}

    assert(not config.is_core)

    for i, v in ipairs(types.ffi_type_map) do
	res[#res + 1] = string.format("  0x%08x, /* %s */\n",
	    gnomedev.compute_hash(v.name), v.name)
    end

    ofile = io.open(ofname, "w")
    header("extern const unsigned int %sfundamental_hash[];", config.prefix)
    ofile:write(string.format("const unsigned int %sfundamental_hash[] = {\n",
	config.prefix))
    ofile:write(table.concat(res))
    ofile:write("};\n\n")
    ofile:close()

    -- header("#define FUNDAMENTAL_COUNT %d", #res)
    config.fundamental_count = #res
end

---
-- Write a sorted list of globals, so that they can be accessed.
--
function output_globals(ofname)
    local keys, ofile, gl, tp = {}
    local count = 0

    for k, v in pairs(xml.globals) do
	if v.is_native then
	    keys[#keys + 1] = v.name
	end
    end
    table.sort(keys)

    ofile = io.open(ofname, "w")
    header("extern const char %sglobals[];", config.prefix)
    ofile:write(string.format("const char %sglobals[] =\n", config.prefix))
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

function output_init()
    header('#include "module.h"')
end

---
-- Write a C file with some defines needed to compile
--
function output_code(ofname)
    -- not required for the core module; it has no module info.
    if config.is_core then return end
    local ofile = io.open(ofname, "w")
    -- to save typing in modules/init.c; in the file generated by
    -- make-link.lua, and only if RUNTIME_LINKING is defined.
    if config.runtime_linking then
	header("extern const char %sdynlink_names[];", config.prefix)
    end
    _generate_module_info()
    ofile:write(table.concat(headerstrings, "\n") .. "\n")
    ofile:close()
end

---
-- Build the "module_info" structure
--
function _generate_module_info()
    local modname = config.module

    -- declare hook functions
    for k, v in pairs(config.lib.module_info or {}) do
	if k == 'call_hook' then
	    header('void %s(lua_State *L, struct func_info *fi);', v)
	elseif k == 'allocate_object' then
	    header('void *%s(cmi mi, lua_State *L, typespec_t ts, int count, '
		.. 'int *flags);', v)
	elseif k == 'overrides' then
	    header('extern const luaL_reg %s[];', v)
	elseif k == 'arg_flags_handler' then
	    header('int %s(lua_State *L, typespec_t ts, int arg_flags);', v)
	elseif k == 'prefix_func_remap' then
	    header('extern const char %s[];', v)
	end
    end

    
    header("")
    header("struct module_info modinfo_%s = {", modname)
    header("    major: LUAGNOME_MODULE_MAJOR, minor: LUAGNOME_MODULE_MINOR,")
    header('    name: "%s",', modname)
    header('    type_list: %s_type_list,', modname)
    header('    elem_list: %s_elem_list,', modname)
    header('    type_count: %d,', config.type_count)    -- set in output_types
    header('    fundamental_hash: %s_fundamental_hash,', modname)
    header('    fundamental_count: %d,', config.fundamental_count)
    if string_buf.elem then
	header('    type_strings_elem: %s_strings_elem,', modname)
    end
    if string_buf.proto then
	header('    prototypes: %s_strings_proto,', modname)
    end
    header('    type_names: %s_strings_types,', modname)
    header('    globals: %s_globals,', modname)
    header('    array_list: %s_array_list,', modname)
    header('    hash_functions: &hash_info_functions,')
    header('    hash_constants: &hash_info_constants,')
    header('    methods: module_methods,')
    for k, v in pairs(config.lib.module_info or {}) do
	header('    %s: %s,', k, v)
    end
    header('    dynlink: {')
    if config.libraries then
	header('      dll_list: "%s\\0",',
	    table.concat(config.libraries, "\\0"))
    end
    if config.runtime_linking then
	header('      dynlink_names: %s_dynlink_names,', modname)
	header('      dynlink_table: %s_dynlink_table,', modname)
    end
    header('    },')
    header('};')
    header("struct module_info *thismodule = &modinfo_%s;", modname)
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

