-- vim:sw=4:sts=4
--
-- The actual parser for types.xml.
--

-- Lua Expat Binding - expat is an XML parser library
-- It is available in Debian as the package liblua5.1-expat0.  Links:
--  http://www.keplerproject.org/luaexpat/
--  http://www.luaforge.net/projects/luaexpat/

local M = {}
local lxp = require "lxp"
setmetatable(M, {__index=_G})
setfenv(1, M)

local curr_func = nil
local curr_enum = nil
local parser = nil
local xml_curr_line = nil
local input_file_name = nil

funclist = {}	-- [name] = [ [rettype,"retval","fileid"],
		--   [arg1type, arg1name], ...]
typedefs = {
    ["vararg"] = { type="fundamental", name="vararg", fname="vararg", size=0 },
} -- [id] = { type=..., name=..., struct=... }
  -- struct = { name, size, align, members, _type, fields } (same for enum)
enum_values = {}    -- [name] = { val, context }
globals = {}	    -- [name] = {...}
filelist = {}	-- [id] = "full path"

max_bit_offset = 0
max_bit_length = 0

local type_override = {
    ["GtkObject.flags"] = { "GtkWidgetFlags" },
}

---
-- Display an error message with the current XML parsing position.
--
local function parse_error(...)
    local line, col = parser:pos()
    local s = string.format("%s(%d): %s", input_file_name, line,
	string.format(...))
    print(s)
    print(xml_curr_line)
    parse_errors = parse_errors + 1
    if parse_errors > 20 then
	print("Too many errors, exiting.")
	os.exit(1)
    end
end


---
-- Verify that the table "el" has all given fields.
--
-- @return  false on success, true on error
--
local function check_fields(el, ...)
    local err = false
    for i = 1, select('#', ...) do
	local f = select(i, ...)
	if not el[f] then
	    parse_error("missing attribute %s", f)
	    err = true
	end
    end
    return err
end

---
-- An override entry has been found.  It gives the name of the type to use,
-- but we need the type ID, i.e. a "_" followed by a number.  As I don't want
-- to build another index, search the list of types
--
local function do_override(ov)
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


---
-- Handle Struct and Union declarations.
--
-- @param el  Element information
-- @param what  "struct" or "union"
--
local function xml_struct_union(p, el, what)

    local members, my_name, struct

    members = {}
    my_name = el.name or el.demangled
    if not my_name then
	parse_error("%s without name or demangled attribute", what)
	return
    end

    if check_fields(el, "id") then return end

    -- remove leading "_", which all structures and unions seem to have.
    -- my_name = my_name:gsub("^_", "")

    if el.incomplete then
	el.size = 0
    else
	if not el.size then
	    parse_error("%s %s without size", what, my_name)
	    return
	end
	if not el.members then
	    parse_error("%s %s without member list", what, my_name)
	    return
	end
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
    }, file_id=el.file }

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




local xml_tags = {

    -- not interested in namespaces.
    Namespace = function(p, el)
    end,

    -- store functions
    Function = function(p, el)
	if check_fields(el, "name", "returns", "file") then return end
	if el.attributes and string.match(el.attributes, "visibility%(hidden%)") then
	    curr_func = nil
	    return
	end
	if config.lib[el.name] then
	    curr_func = nil
	    return
	end
	curr_func = { { el.returns, "retval", el.file } }
	funclist[el.name] = curr_func
    end,

    -- discard the argument names, just keep the type.
    Argument = function(p, el)
	if not curr_func then return end
	local name = el.name or string.format("arg_%d", #curr_func)
	if check_fields(el, "type") then return end
	curr_func[#curr_func + 1] = { el.type, name }
    end,

    -- translated to vararg argument later
    Ellipsis = function(p, el)
	if curr_func then
	    curr_func[#curr_func + 1] = { "vararg", "vararg" }
	end
    end,

    -- declare a type being a function prototype
    FunctionType = function(p, el)
	if check_fields(el, "id", "returns") then return end
	curr_func = { { el.returns, "retval" } }
	typedefs[el.id] = { type="func", prototype=curr_func,
	    name="func" .. el.id, dummy_name=true }
    end,

    -- Not interested much in constructors.  Store anyway to avoid
    -- dangling references.
    Constructor = function(p, el)
	if check_fields(el, "id", "context") then return end
	local t = typedefs[el.context]
	if not t then
	    parse_error("Constructor for unknown structure %s", el.context)
	    return
	end
	local st = t.struct
	st.fields[el.id] = { type="constructor", name=el.name or el.demangled }
	curr_func = nil
    end,

    -- structures and unions
    Struct = function(p, el)
	if el.name == "_cairo" then el.name = "cairo" end
	return xml_struct_union(p, el, "struct")
    end,

    Union = function(p, el) return xml_struct_union(p, el, "union") end,

    -- member of a structure
    Field = function(p, el) 
	-- el.bits is optional.
	if check_fields(el, "id", "context", "name", "type", "offset")
	    then return end
	local t = typedefs[el.context]
	if not t then
	    parse_error("Field for unknown structure %s", el.context)
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
	if check_fields(el, "name", "file") then return end
	globals[el.name] = el
    end,

    -- declare an alternative name for another type
    Typedef = function(p, el)
	if check_fields(el, "id", "context", "name", "type") then return end
	if el.context ~= "_1" then
	    print("Warning: typedef context is " .. el.context)
	end

	-- cairo uses a _t suffix for all types (except for _cairo); remove
	-- that.  Otherwise, the functions can't be found, e.g.
	-- cairo_surface_t_status() doesn't exist!
	if string.match(el.name, "^cairo.*_t") then
	    el.name = string.sub(el.name, 1, -3)
	    -- print("rename", el.name)
	end
	typedefs[el.id] = { type="typedef", name=el.name, what=el.type,
	    file_id=el.file }
    end,

    EnumValue = function(p, el)
	if check_fields(el, "name", "init") then return end
	enum_values[el.name] = { val=tonumber(el.init), context=curr_enum }
    end,

    -- declare a type being an enum
    Enumeration = function(p, el)
	if check_fields(el, "id", "name", "size", "align") then return end
	typedefs[el.id] = { type="enum", name=el.name, size=el.size,
	    align=el.align, file_id=el.file }
	curr_enum = el.id
    end,

    -- declare a type being a pointer to another type
    PointerType = function(p, el)
	if check_fields(el, "id", "type", "size", "align") then return end
	typedefs[el.id] = { type="pointer", what=el.type, size=el.size,
	    align=el.align }
    end,

    FundamentalType = function(p, el)
	-- size is optional (for void)
	if check_fields(el, "id", "name", "align") then return end
	t = { type="fundamental", fname=el.name, size=el.size, align=el.align,
	    pointer=0 }
	    -- useless element: fid=fid
	types.register_fundamental(t)
	typedefs[el.id] = t
	if not el.size and el.name ~= "void" then
	    parse_error("fundamental type %s without size", el.name)
	end
    end,

    -- wrapper for another type adding qualifiers: const, restrict, volatile
    CvQualifiedType = function(p, el)
	if check_fields(el, "id", "type") then return end
	typedefs[el.id] = { type="qualifier", what=el.type,
	    restrict=el.restrict, const=el.const, volatile=el.volatile }
    end,

    ArrayType = function(p, el)
	if check_fields(el, "id", "min", "max", "align", "type") then return end
	local max = tonumber(string.match(el.max, "^(%d+)")) or 0
	typedefs[el.id] = { type="array", min=el.min, max=max,
	    align=el.align, what=el.type }
    end,

    -- a function parameter that is passed by reference; only used in the
    -- automatically generated and not useful constructors.
    ReferenceType = function(p, el)
    end,

    -- Associate file names (including full path) to the file IDs.  This is
    -- used later to filter out relevant defines, which are identified by
    -- the path of the files.
    File = function(p, el)
	filelist[el.id] = el.name
    end,
}


local unhandled = {}	    -- [name] = true
local function regular_parser(p, name, el)
    local f = xml_tags[name]
    if f then return f(p, el) end

    if not unhandled[name] then
	print("Unhandled XML element " .. name)
	unhandled[name] = true
    end
end


local function look_for_gcc_xml(p, name, el)
    if name == "GCC_XML" then
	callbacks.StartElement = regular_parser
    end
end


---
-- Read the given XML file
--
-- @param xml_file filename (with path) of the input file
--
function parse_xml(xml_file)
    input_file_name = xml_file
    callbacks = { StartElement = look_for_gcc_xml }
    parser = lxp.new(callbacks, "::")
    for l in io.lines(xml_file) do
	xml_curr_line = l
	parser:parse(l)
	parser:parse("\n")
    end
    parser:parse()	    -- close document
    parser:close()	    -- close parser
    parser = nil
    callbacks = nil
end

function show_statistics()
    info_num("Max. bit offset", max_bit_offset)
    info_num("Max. bit length", max_bit_length)
end

return M

