-- vim:sw=4:sts=4
--
-- Type handling for parse-xml.lua.
--
-- Exported symbols:
--
--  ffi_type_map
--
--  statistics
--  register_fundamental
--  resolve_type
--  fundamental_to_ffi
--  mark_type_id_in_use
--  function_arglist
--  register_prototype
--  register_function_prototypes
--  assign_type_idx
--



local M = {}
local main = _G
setmetatable(M, {__index=_G})
setfenv(1, M)

max_func_args = 0

-- get the list of supported fundamental data types (fundamental_map).
require "include/fundamental"

-- List of fundamental types existing.  The fid (fundamental id) is an index
-- into this table; the first entry starts at index 1.  Append as many "*" to
-- the name as there are indirections.  The entries are added as found and
-- therefore are all in use.
ffi_type_map = {}


-- Bytes required for extra type bytes.  This is for statistics to be shown
-- before the script exits.
local extension_bytes = 0

-- Mapping to quickly find already known fundamental types
local ffi_type_name2id = {}

-- Already known prototypes; key is a textual signature of return value and
-- all parameters, value is the offset in the string table.
local prototypes = {}

-- Mapping typename to typedefs of type "func" that haven't been registered via
-- register_prototype yet.  The reason is that for register_prototype, all
-- referenced types must alreay be known.  Therefore keep a list and register
-- them at the end (using register_function_prototypes).
local funclist2 = {}

---
-- Check whether a given fundamental type is already known.  If not,
-- add it.  Make sure that t.fid is set.
--
function register_fundamental(t)
    local fid, name, size

    if t.fid then return end

    assert(t.fname, "Trying to register fundamental type with null name")
    assert(t.pointer)
    if t.fname ~= "void" and not t.size then
	error("Trying to register fundamental type " .. t.fname
	    .. " without size: " .. tostring(t.size) )
    end

    -- fixup for atk_object_connect_property_change_handler.  The second
    -- argument's type seems to be "func**", but it really is "func*".
--
-- not so sure.  from /usr/include/atk-1.0/atk/atkobject.h:
--
-- typedef void (*AtkPropertyChangeHandler) (AtkObject*, AtkPropertyValues*);
--
-- guint atk_object_connect_property_change_handler  (AtkObject *accessible,
--     AtkPropertyChangeHandler *handler);
--

--    if t.fname == 'func' and t.pointer > 1 then
--	print("Warning: func" .. string.rep("*", t.pointer) .. " "
--	    .. t.full_name)
--    end

    name = t.fname .. string.rep("*", t.pointer)
    fid = ffi_type_name2id[name]
    if fid then t.fid = fid; return end

    -- size is meaningless for "struct"
    size = t.size or 0
    if name == "struct" then size = 0 end

    -- register new fundamental type.  struct type_info currently has 6
    -- bits for the fundamental ID.
    fid = #ffi_type_map + 1
    assert(fid < 64, "Too many fundamental types!")

    ffi_type_map[fid] = {
	name = name,
	pointer = t.pointer,
	bit_len = size,
	basename = t.fname,
    }
    ffi_type_name2id[name] = fid
    t.fid = fid
end


-- compute a full name for the type including qualifiers and pointers
function make_full_name(t, name)
    local ar_string = ""
    if t.array then
	for _, dim in ipairs(t.array) do
	    ar_string = ar_string .. "[" .. tostring(dim) .. "]"
	end
    end

    -- this is the name stored in the data file; it doesn't include
    -- const, array or pointers, as this information is stored separately.
    t.extended_name = name or t.fname

    t.full_name = string.format("%s%s%s%s",
	t.const and "const " or "",
	name or t.fname,
	string.rep("*", t.indir),
	ar_string)
end

---
-- Given a Type ID, find the underlying type - which may be a structure,
-- union, fundamental type, function, enum, array, pointer or maybe other
-- things.  Sets full_name, pointer, and other attributes of the type.
--
-- The type_ids are chained and may include qualifiers like const, or
-- pointers, arrays, typedefs etc.
--
-- This function is called multiple times per usage of a given type.  No
-- counting of type usage can be done here; the types are not marked as used.
--
-- @param type_id  Type identifier, which is a number with leading _
-- @param path  If given as an empty table, add all IDs seen while resolving,
--   the given type_id first, fundamental type last.  Each indirection adds
--   another entry.
-- @param may_be_incomplete  True to avoid errors/warnings
-- @return  An entry from typedefs, but with additional fields.
--
function resolve_type(type_id, path, may_be_incomplete)
    if type_id == nil then return {} end

    local t, t_top, top_type_id, name

    -- first typedef
    top_type_id = type_id
    t = typedefs[type_id]
    assert(t)

    -- already seen?
    if t.full_name and not path then return t end

    -- the typedef to return eventually.
    t_top = t
    t_top.pointer = 0 -- t_top.pointer or 0
    t_top.indir = 0

    while t do
	-- retain the most specific name and file_id (the first one encountered)
	t_top.fname = t_top.fname or t.fname
	t_top.file_id = t_top.file_id or t.file_id
	name = name or t.name

	-- pointer to something
	if t.type == "pointer" then
	    if t.size and t.size ~= 0 then
		t_top.size = t.size
	    end
	    -- count indirections only until the name is found.  A "gpointer"
	    -- has a pointer count of 1, but indir count of zero, and
	    -- is therefore shown as "gpointer" and not "gpointer*".
	    if not name then
		t_top.indir = t_top.indir + 1
	    end
	    if path then path[#path + 1] = type_id end
	    t_top.pointer = t_top.pointer + 1
	    -- t.align not used

	-- a typedef is just an alias, no further action required
	elseif t.type == "typedef" then

	-- copy qualifiers; they add up if multiple are used
	elseif t.type == "qualifier" then
	    if t.const then t_top.const = true end
	    if t.volatile then t_top.volatile = true end
	    if t.restrict then t_top.restrict = true end

	-- structure or union.
	elseif t.type == "struct" or t.type == "union" then
	    t_top.size = t_top.size or t.struct.size
	    -- if t.size then t_top.bit_len = t.size end
	    t_top.fname = t.type
	    t_top.detail = t
	    break

	-- fundamental type.
	elseif t.type == "fundamental" then
	    -- t.type, name, size, align
	    if not t_top.size or t_top.size == 0 then t_top.size = t.size end
	    break

	-- function pointer
	elseif t.type == "func" then
	    t_top.fname = "func"
	    t_top.detail = t
	    t_top.is_function = true
	    break

	-- an enum
	elseif t.type == "enum" then
	    -- the enum name is t.name
	    if t.size and t.size ~= 0 then
		t_top.size = t.size
	    end
	    t_top.fname = "enum"
	    t_top.detail = t
	    break

	-- array of some other type
	elseif t.type == "array" then
	    if t.size and t.size ~= 0 then t_top.size = t.size end
	    t_top.array = t_top.array or {}
	    assert(t.min == "0")
	    t_top.array[#t_top.array + 1] = t.max or ""
	    -- "[" .. (t.max or "") .. "]"

	-- unknown type
	else
	    print("unknown type in resolve_type", t.type)
	    for k, v in pairs(t) do print(k, v) end
	    print ""
	    break
	end

	-- follow the pointer (Typedef, PointerType etc.)
	type_id = t.what
	t = typedefs[type_id]
    end

    -- special case gboolean: is mapped to integer, but as Lua has a special
    -- boolean type, this must be handled differently.
    if t_top.name == "gboolean" or t_top.name == "cairo_bool" then 
	t_top.fname = "boolean"
    end


    -- don_t set t_top.name - this is only set for types that have an
    -- explicit name in the XML file.

--[[
    if t_top.name then
	assert(t_top.name == name)
    else
	t_top.name = name
    end
--]]

    make_full_name(t_top, name)

    if not t_top.size or t_top.size == 0 then
	if may_be_incomplete then return end
	-- these two types have a zero size.
	if t_top.fname ~= "void" and t_top.fname ~= "vararg" then
	    print("ZERO SIZE", t_top.name, name, t_top.fname)
	end
    end

    -- all types must eventually have a file_id except fundamental types
    -- and function types (which are often declared in a structure and have
    -- no file info)
    if not t_top.file_id and t.type ~= "fundamental" and
	t.type ~= "func" then
	print("NO FILE_ID FOR TYPE", top_type_id, t_top.type, t.type)
    end

    -- make sure the fundamental type is registered.
    register_fundamental(t_top)
    assert(t_top.fid)

    return t_top
end

-- don't show warnings about these types; they are not used by any interesting
-- functions, just some builtin math functions.
local ignore_types = { ["complex float"]=true, ["complex double"]=true,
    ["complex long double"]=true }

---
-- Given a fundamental type, return the suggested FFI type.  Also creates
-- an entry in the argument_types ENUM if it doesn't exist yet.
--
-- Available FFI types: see /usr/include/ffi.h
--
-- @param ft A fundamental type (from the table ffi_type_map)
-- @return An entry from fundamental_map
--
function fundamental_to_ffi(ft)
    local v = fundamental_map[ft.basename]

    if v and v[2 + ft.pointer] then
	return { ft.pointer == 0 and v[1] or "pointer",	-- ffi type
	    unpack(v[2 + ft.pointer]) }
    end

    -- pointer types have this default entry
    if ft.pointer > 0 then
	return { "pointer", "ptr", "ptr", nil, nil }
    end

    if not ignore_types[ft.name] then
	print("Unknown type " .. ft.name)
    end

    return nil
end

---
-- Recursively mark this typedef and all subtypes as used.
--
-- @param t  An entry of the typedefs array.  t.type is struct, union,
--   func or enum.
-- @param typename  While descending the type chain, the "lower" types may not
--   have a type name, esp. functions.  Carry the higher level name.
--
local function _mark_typedef_in_use(t, typename)
    local ignore_types = { constructor=true, union=true, struct=true }
    local field

    typename = typename or t.name
    assert(typename)

    -- already marked?
    if t.in_use or t.marked then
	return
    end

    t.marked = true
    -- mark elements of a structure
    if t.struct then
	local st = t.struct
	for i, member_id in ipairs(st.members) do
	    field = st.fields[member_id]
	    if not field then
		print(string.format("ERROR: structure %s doesn't have the "
		    .. "field %s", st.name, member_id))
	    elseif not ignore_types[field.type] then
		mark_type_id_in_use(field.type, string.format("%s.%s",
		    typename, field.name or member_id))
	    elseif field.type ~= "constructor" then
		-- substructure, subunion - not supported.
		if verbose > 0 then
		    print(string.format("ignore sub%s %d in %s - id=%s",
			field.type, i, st.name, member_id))
		end
	    end
	end
    end

    -- mark types of return type and all arguments
    if t.prototype then
	for i, arg_info in ipairs(t.prototype) do
	    local type_id = arg_info[1]
	    local arg_name = assert(arg_info[2])
	    local t2 = mark_type_id_in_use(type_id, arg_name)
	    assert(t2.in_use)
	    assert(t2.counter > 0)
	end

	-- Can't call register_prototype yet, because no type_ids are
	-- assigned yet.  Instead, add this to a list.
	assert(not funclist2[typename], "double funclist2 entry " .. typename)
	funclist2[typename] = t
    end
end


---
-- Given a type_id, make sure the top level type for it is marked used.
-- This is called once per usage of the given type_id.  Count frequency here.
-- Note: If a type has a smaller bit size, this isn't relevant here.  This
-- only applies to structure elements and is specified there.
--
-- @param type_id  ID of the type, i.e. index into typedefs
-- @param name  Variable or argument name.  Might be required for something?
-- @return  The type entry
--
function mark_type_id_in_use(type_id, varname)

    -- resolve this type ID, resulting in a fundamental type.  These are
    -- all available; but if it is a structure, union, enum, function etc.
    -- that have additional info, this must be marked in use.
    -- print("mark_type_id_in_use", type_id, varname)
    local t = resolve_type(type_id)

    -- for native types, go into the detail, i.e. make sure the types of the
    -- elements of the struct, union, enum or function are available, too.
    -- if no file information is present, follow.
    if t.detail and (not t.file_id or good_files[t.file_id]) then

	-- unnamed function types are quite common.  During type_idx assignment
	-- in assign_type_idx each type must have a unique name, therefore
	-- generate them here from the varname in the form "Struct.elem_name".
	if not t.name and t.fname == "func" then
	    t.name = string.format("%s_func", string.gsub(varname, "%.", "_"))
	    t.name = string.gsub(t.name, "^_", "")
	    -- update the full name, which has const, * and others.
	    make_full_name(t, t.name)
	    -- print("synthetic function name", type_id, t.full_name)
	    assert(t.detail.prototype)
	end
	-- print("mark_typedef_in_use detail", t.name)
	_mark_typedef_in_use(t.detail, t.name)
    end
    

    -- increase the usage counter
    t.counter = (t.counter or 0) + 1
    t.in_use = true
    return t
end


--
-- Encode the argument list of a function (including the return type) into a
-- binary string.  Format of each argument:
--
--   0ttt tttt
--	for type numbers up to 0x007f
--
--   1ttt tttt  tttt tttt
--	for type numbers up to 0x8ffe (high bits first)
--
--   If a type number is 0 (which is unused), then a flags byte follows that
--   applies to the following argument.
--
--   The reserved type number 0x8fff means that this is not a real function,
--   but an alias.  The name of the real function follows.
--
function function_arglist(arg_list, fname)
    local t, val, s, type_id, extra, id, flags

    s = ""
    t = config.lib.function_flags or {}
    flags = t[fname] or {}
    if type(flags) ~= "table" then
	flags = { flags }
    end

    if type(arg_list) == "string" then
	s = string.char(0xff) .. string.char(0xff) .. arg_list .. string.char(0)
	return s
    end

    for i, arg_info in ipairs(arg_list) do
	type_id = arg_info[1]
	t = resolve_type(type_id)
	extra = ""

	-- If flags are set on the argument, encode that first.  The char*
	-- return specification is used otherwise (to enforce const/non-const)
	-- and is not encoded as an argument flag.
	if flags[i] then
	    local v = flags[i]
	    if type(v) == "string" then
		v = assert(config.lib.flag_table[v])
		v = bit.bor(v, 0x80)
		s = s .. string.char(0) .. string.char(v)
		extension_bytes = extension_bytes + 2
	    else
		-- Only flags in the first 8 bits can be stored.  This
		-- skips 
		v = bit.band(v, 0xff)
		if v ~= 0 then
		    s = s .. string.char(0) .. string.char(v)
		    extension_bytes = extension_bytes + 2
		end
	    end
	end

	-- When a function returns a string, the caller must free it, unless
	-- it is a const string.  This policy is followed quite consequently
	-- with few exceptions.
	if i == 1 and t.fname == "char" and t.pointer == 1 then
	    t = _handle_char_ptr_returns(arg_info, t, fname)
	end

	-- if val is 128 or more, a second type byte is required.
	-- the algorithm could be extended to cover even more bits
	val = t.type_idx
	if not val then
	    error(string.format("Function arglist for %s: no type_idx for "
		.. "arg #%d - type %s = %s", fname, i-1, type_id, t.full_name))
	end
	if bit.band(val, 0xffff8000) ~= 0 then
	    error("Type index too high: " .. tostring(val))
	end

	if val >= 128 then
	    -- low byte second
	    extra = string.char(bit.band(val, 0xff))
	    -- high byte with high bit set
	    val = bit.bor(bit.rshift(val, 8), 0x80)
	    extension_bytes = extension_bytes + 1
	end

	-- first byte plus the optional extra data
	s = s .. string.char(val) .. extra
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
-- @param arg_info  An array { return type }
-- @param t  The typedef of the return value, corresponds to arg_info[1]
-- @param fname  Name of the function
-- @return  The typedef of the return value (equal to "t" or modified)
--
function _handle_char_ptr_returns(arg_info, t, fname)
    local ff, flags, name

    -- is there an entry in function flags for this?
    flags = config.lib.function_flags or {}
    ff = flags[fname]
    if not ff then return t end

    -- flags for the return value
    flags = type(ff) == 'table' and ff[1] or ff

    if bit.band(flags, function_flag_map.CHAR_PTR) > 0 then
	-- should be non-const
	if not t.const then return t end
	name = string.gsub(t.full_name, "^const ", "")
    elseif bit.band(flags, function_flag_map.CONST_CHAR_PTR) > 0 then
	if t.const then return t end
	name = "const " .. t.full_name
    end

    print("char/const char* return value MISMATCH for", fname, name)
    return assert(resolve_type(typedefs_name2id[name]))
end



---
-- A pointer to a function appeared as an argument type to another function,
-- or as the type of a member of a structure.  In both cases, make sure this
-- function's signature is stored as usual.  The "proto_ofs" of the given
-- typedef will be set.
--
-- @param typedef   An entry of typedefs[] with .prototype set
-- @return  true on success, false on error (some arg type not defined yet)
--
function register_prototype(t, name)
    
    local key = {}

    assert(t.type == "func")
    assert(t.prototype)
    assert(not t.proto_ofs)

    -- Compute a string to identify this prototype.  It contains the types of
    -- return value and all the arguments' types, but without their names.
    for i, arg_info in ipairs(t.prototype) do
	-- no bit size given for function parameters.
	local tp = resolve_type(arg_info[1])
	key[#key + 1] = tp.full_name
    end
    key = table.concat(key, ',')

    local proto_ofs = prototypes[key]

    if not proto_ofs then
	local sig = function_arglist(t.prototype, name)
	if not sig then return false end

	-- prepend a length byte
	sig = string.char(#sig) .. sig

	proto_ofs = output.store_string("proto", sig, true)
	prototypes[sig] = proto_ofs
    end

    -- this can happen when there are inconsistencies of free methods.
    if t.proto_ofs and t.proto_ofs ~= proto_ofs then
	print(string.format("Warning: differing prototypes %d and %d for %s, "
	    .. "key=%s", t.proto_ofs, proto_ofs, name, key))
    end

    t.proto_ofs = proto_ofs
    return true
end


---
-- Now that the type_idx are assigned, register the prototypes of
-- functions found in structures.
--
function register_function_prototypes()
    local cnt, funclist3 = 1

    for loops = 1, 3 do
	funclist3 = {}
	cnt = 0
	for name, t in pairs(funclist2) do
	    if not register_prototype(t, name) then
		-- Could not resolve the prototype yet; try again
		funclist3[name] = t
		cnt = cnt + 1
	    end
	end
	funclist2 = funclist3
	if cnt == 0 then break end
    end

    -- no unresolved functions must remain.
    assert(cnt == 0)
end


---
-- If foo** exists, make sure that foo* also exists.  This is required because
-- when resolving output arguments in src/types.c, one indirection is removed
-- and the resulting type is searched for.  This type might not be in use
-- otherwise.
local function fixup_types()
    local id, t, t_parent, name2, path
    local keys, name2id = typedefs_sorted, typedefs_name2id

    for i, name in ipairs(keys) do
	while string.sub(name, -2) == '**' do
	    name2 = string.sub(name, 1, -2) 
	    if not name2id[name2] then
		id = name2id[name]
		path = {}
		resolve_type(id, path)
		assert(path[1] == id)
		assert(path[2])
		t = resolve_type(path[2])
		t_parent = typedefs[id]
		t.is_native = t_parent.is_native
		if verbose > 1 then
		    print("fixup_types: adding type", t.full_name)
		end
		name2id[t.full_name] = path[2]
		keys[#keys + 1] = t.full_name
		t.counter = t.counter or 0
	    end
	    name = name2
	end
    end
end


---
-- Look at all used types, and assign them a type_idx.
--
function assign_type_idx()

    -- make a list of used types.  Names may be duplicate, e.g.
    -- const char const is mapped to const char, which might exist, too.
    local t
    local keys, name2id = typedefs_sorted, typedefs_name2id
    for id, t in pairs(typedefs) do
	if t.counter then
	    assert(t.in_use or t.counter == 0)
	    assert(t.full_name, "no full_name of used type " .. id)
	    assert(t.fid, "no fundamental_id defined for type " .. t.full_name)

	    local id2 = name2id[t.full_name]
	    if id2 and id2 ~= id then
		-- already mapped to a different ID
		if verbose > 0 then
		    print(string.format("Duplicate type %s: redirect %s to %s",
			t.full_name, id, id2))
		end

		-- t2 will be eliminated; add its counter (if any) to t
		local t2 = typedefs[id2]
		if t2.counter then
		    t.counter = t.counter + t2.counter
		end

		-- if t2 is native, then t should be, too!
		t.is_native = t.is_native or t2.is_native

		typedefs[id2] = t
	    else
		keys[#keys + 1] = t.full_name
	    end

	    name2id[t.full_name] = id
	end
    end

    fixup_types()

    -- sort the types by their frequency.  The types used more often get
    -- smaller IDs, thereby reducing output data size (number >= 64 need
    -- an additional byte)
    table.sort(keys, function(a, b)
	a = typedefs[name2id[a]]
	b = typedefs[name2id[b]]

	local c = a.counter - b.counter
	if c ~= 0 then return c > 0 end

	-- doesn't have any useful effect, just for beauty
	return a.full_name < b.full_name
    end)

    -- assign IDs in order, and rebuild the typemap index; no duplicates!
    local sum, nr = 0, 1
    local keys_nodup = {}
    for idx, full_name in ipairs(keys) do
	t = typedefs[name2id[full_name]]
	assert(t, "typedef not known: " .. full_name, name2id[full_name])
	-- There may be duplicates: assign just the first one.
	if not t.type_idx then
	    t.type_idx = nr
	    nr = nr + 1
	    keys_nodup[#keys_nodup + 1] = full_name
	    sum = sum + t.counter
--	else
--	    print("Duplicate, skipping: " .. full_name .. ", " .. t.type_idx)
	end
--	print(idx, t.counter, sum, name2id[full_name], full_name)
    end
    return keys_nodup
end

function show_statistics()
    info_num("Type extension bytes in prototypes", extension_bytes)
    info_num("Max. number of function args", max_func_args)
    info_num("Number of fundamental types", #ffi_type_map)
end

---
-- The main module (gnome) must provide handlers for all known types.  This
-- module itself doesn't need all of them, but others do.
--
function register_all_fundamental_types()

    for basename, ar in pairs(fundamental_map) do
	for i = 2, #ar do
	    t = { type="fundamental", fname=basename, size=0, align=0,
		pointer=i - 2 }
	    register_fundamental(t)
	end
    end
end

return M

