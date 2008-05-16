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
require "src/fundamental"

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
    local fid, name

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

    -- register new fundamental type
    fid = #ffi_type_map + 1
    assert(fid < 100, "Too many fundamental types!")

    ffi_type_map[fid] = {
	name = name,
	pointer = t.pointer,
	bit_len = t.size or 0,
	basename = t.fname,
    }
    ffi_type_name2id[name] = fid

    -- Special case for char*: add another entry for const char*, which
    -- must directly follow the regular char* entry.
    if name == "char*" then
	ffi_type_map[fid + 1] = {
	    name = "const char*",
	    pointer = t.pointer,
	    bit_len = t.size or 0,
	    basename = t.fname,
	}
	main.char_ptr_second = fid + 1
    end

    t.fid = fid
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
-- @return  An entry from typedefs, but with additional fields.
--
function resolve_type(type_id, path, may_be_incomplete)
    if type_id == nil then return {} end

    local t, t_top

    -- first typedef
    t = typedefs[type_id]
    assert(t)

    -- already seen?
    if t.full_name and not path then return t end

    -- the typedef to return eventually.
    t_top = t
    t_top.pointer = 0 -- t_top.pointer or 0

    if size then
	print("SIZE OVERRIDE", size)
	t_top.size = size
    end

    local name = nil

    while t do

	-- retain the most specific name (the first one encountered)
	t_top.fname = t_top.fname or t.fname
	name = name or t.name

	-- pointer to something
	if t.type == "pointer" then
	    if t.size and t.size ~= 0 then
		t_top.size = t.size
	    end
	    if path then path[#path + 1] = type_id end
	    t_top.pointer = t_top.pointer + 1
	    -- t.align not used

	-- a typedef, i.e. an alias
	elseif t.type == "typedef" or t.type == "qualifier" then
	    -- copy qualifiers; they add up if multiple are used
	    if t.const then t_top.const = true end
	    if t.volatile then t_top.volatile = true end
	    if t.restrict then t_top.restrict = true end

	-- structure or union.
	elseif t.type == "struct" or t.type == "union" then
	    t_top.size = t_top.size or t.struct.size
	    -- if t.size then t_top.bit_len = t.size end
	    t_top.fname = t.type
	    t_top.detail = t
--	    if t.name == "_cairo" then
--		name = "cairo"
--	    end
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
	    t_top.array[#t_top.array + 1] = "[" .. t.max .. "]"

	-- unknown type
	else
	    print("unknown type in resolve_type", t.type)
	    for k, v in pairs(t) do print(k, v) end
	    print ""
	    break
	end

	if track_size then
	    print("track: going to", t.what)
	end

	type_id = t.what
	t = typedefs[type_id]
    end

    -- special case gboolean: is mapped to integer, but as Lua has a special
    -- boolean type, this must be handled differently.
    if t_top.name == "gboolean" or t_top.name == "cairo_bool" then 
	t_top.fname = "boolean"
    end

    -- this is the name stored in the list.  no pointers or arrays; these
    -- are stored as flags.
    t_top.extended_name = name or t_top.fname

    -- compute a full name for the type including qualifiers and pointers
    t_top.full_name = string.format("%s%s%s%s",
	t_top.const and "const " or "",
	name or t_top.fname,
	string.rep("*", t_top.pointer),
	t_top.array and table.concat(t_top.array, "") or "")

    if not t_top.size or t_top.size == 0 then
	if may_be_incomplete then return end
	print("ZERO SIZE", t_top.name, name, t_top.fname)
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

    if v and v[3 + ft.pointer] then
	return { ft.pointer == 0 and v[1] or "pointer", v[2],
	    unpack(v[3 + ft.pointer]) }
    end

    -- pointer types have this default entry
    if ft.pointer > 0 then
	return { "pointer", 0, "ptr", nil, nil, nil }
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
-- @param name  ?
--
local function _mark_typedef_in_use(t, name)
    local ignore_types = { constructor=true, union=true, struct=true }
    local field

    name = name or t.name
    assert(name)

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
		    name, field.name or member_id))
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
	    mark_type_id_in_use(type_id, nil)
		-- string.format("%s.%s", name, arg_info[2] .. "XX"))
	end
	-- Can't call register_prototype yet, because no type_ids are
	-- assigned yet.  Instead, add this to a list.
	assert(not funclist2[name], "double funclist2 entry " .. t.name)
	funclist2[name] = t
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
function mark_type_id_in_use(type_id, name)

    -- resolve this type ID, resulting in a fundamental type.  These are
    -- all available; but if it is a structure, union, enum, function etc.
    -- that have additional info, this must be marked in use.
    local t = resolve_type(type_id)

    -- detail may be set for struct, union, enum, functions.
    if t.detail then
	_mark_typedef_in_use(t.detail, name or t.full_name)
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
--	for type numbers up to 2^7-1
--
--   1ttt tttt  tttt tttt
--	for type numbers up to 2^15-1 (high bits first)
--
function function_arglist(arg_list, fname)
    local t, val, s, type_id, extra, id

    s = ""
    for i, arg_info in ipairs(arg_list) do
	type_id = arg_info[1]
	t = resolve_type(type_id)
	val = t.type_idx
	assert(val, "No type_idx for " .. type_id .. " = " .. t.full_name)
	extra = ""

	-- gchar* and const gchar* return values
-- XXX temporarily out of order
--	if i == 1 and tp.fname == "char" and tp.pointer == 1 then
--	    print("arglist", tp.full_name)
--	    val = _handle_char_ptr_returns(arg_list, tp, fname)
--	end

	-- if val is 128 or more, a second type byte is required.
	-- the algorithm could be extended to cover even more bits
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
    end

    -- no unresolved functions must remain.
    assert(cnt == 0)
end

---
-- Given a type name (like GdkWindow*), find the appropriate ID and retrieve
-- the entry in typedefs.
--
local function find_type_by_name(name)
end

---
-- If foo** exists, make sure that foo* also exists.  This is required because
-- when resolving output arguments in src/types.c, one indirection is removed
-- and the resulting type is searched for.  This type might not be in use
-- otherwise.
local function fixup_types()
    local id, t, name2, path
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
		if verbose > 1 then
		    print("adding", t.full_name)
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
	-- print(idx, t.counter, sum, full_name)
    end
    return keys_nodup
end

function show_statistics()
    info_num("Type extension bytes in prototypes", extension_bytes)
    info_num("Max. number of function args", max_func_args)
    info_num("Number of fundamental types", #ffi_type_map)
end

return M

