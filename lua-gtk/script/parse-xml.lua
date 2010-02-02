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

-- BitOp, see http://bitop.luajit.org/
require "bit"

-- The binding to the hash functions used in this package.  Compiled during
-- building.
require "gnomedev"

require "lfs"

-- locally defined
require "script.util"

-- add the directory where this Lua file is in to the package search path.
package.path = package.path .. ";" .. string.gsub(arg[0], "%/[^/]+$", "/?.lua")

xml = require "xml-parser"
typedefs = xml.typedefs
types = require "xml-types"
output = require "xml-output"
require "xml-const"

typedefs_sorted = {}
typedefs_name2id = {}
config = {}		-- configuration of architecture, module etc.
parse_errors = 0	-- count errors (used in xml-parser.lua)
verbose = 0		-- verbosity level
good_files = {}		-- [file_id] = true for "interesting" include files
logfile = nil
non_native_includes = {}    -- [path] = libname
function_list = {}
build_errors = 0


-- Print an error message and increase the error counter.
function err(fmt, ...)
    if select('#', ...) > 0 then
	fmt = string.format(fmt, ...)
    end
    print(fmt)
    build_errors = build_errors + 1
end

---
-- Unfortunately, sometimes ENUM fields in structures are not declared as such,
-- but as integer.  Therefore, used ENUMs may appear unused.  Simply mark all
-- ENUMs as used...
--
function mark_all_enums_as_used()
    local fid, tp
    for id, t in pairs(typedefs) do
	if t.type == "enum" then
	    if not t.in_use then
		if good_files[t.file_id] then
		    types.mark_type_id_in_use(id, nil)
		end
	    else
		if not good_files[t.file_id] then
		    t.no_good = true
		end
	    end
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
	if t.type == "enum" and t.in_use then
	    enum_list[id] = true
	end
    end

    -- find typedefs that refer to them
    for id, t in pairs(typedefs) do
	if t.type == "typedef" and enum_list[t.what] then
	    -- print("FOUND typedef for enum:", t.full_name)
	    types.mark_type_id_in_use(id, nil)
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
-- virtual functions.  They are not intended to be used directly by the user,
-- and therefore don't show up as function arguments.
-- All of these structures are named _*Iface, and have a typedef with
-- *Iface for them.  Actually, we need a pointer to that, which isn't defined.
--
function mark_ifaces_as_used()
    local name2id = {}
    for type_id, t in pairs(typedefs) do
	if t.type == "typedef" and string.match(t.name, "Iface$")
	    and good_files[t.file_id] then
	    -- types.mark_type_id_in_use(type_id)
	    name2id[t.name] = type_id
	    synthesize_type(t.name .. "*", name2id)
	end
    end
end


---
-- Read all config files for the libraries in the current setup.  Note
-- that this usually is just one, and probably never is more than one.
--
function load_lib_config()
    local cfg_file, cfg

    -- config_libs = {}
    cfg_file = string.format("%s/spec.lua", config.srcdir)
    config.lib = load_spec(cfg_file)

    if config.lib.native_types then
	for k, v in pairs(config.lib.native_types) do
	    config.native_types[k] = v
	end
    end
end

---
-- Read all spec files of other modules and extract the include_dirs.  This
-- is used to store for non-native types which module should handle it.
--
function load_other_lib_config()
    local ifile

    for libname in lfs.dir("src") do
	ifile = "src/" .. libname .. "/spec.lua"
	if string.sub(libname, 1, 1) ~= "."
	    and lfs.attributes(ifile, "mode") == "file" then
	    cfg = load_spec(ifile, true)
	    for _, path in ipairs(cfg.include_dirs or {}) do
		non_native_includes[path] = libname
	    end
	end
    end
	
end

-- Make a table listing all include paths of the current module.
function _get_include_paths()
    local tbl = {}
    for _, path in ipairs(config.lib.include_dirs or {}) do
	tbl[#tbl + 1] = "/" .. path .. "/"
    end
    return tbl
end


---
-- Look at all the file IDs and mark those files that are relevant for the
-- current module.
--
function make_file_list()
    local paths = _get_include_paths()
    good_files = {}	    -- [id] = true

    for id, name in pairs(xml.filelist) do
	for i, path in ipairs(paths) do
	    if string.find(name, path, 1, true) then
		good_files[id] = true
		break
	    end
	end
    end
end
	

---
-- Take a look at all relevant functions and the data types they reference.
-- Mark all these data types as used.  Note that functions prototypes that only
-- appear in structures (i.e., function pointers) are not considered here.
--
-- Note that this does not consider function types, which are only to be
-- found in the typedefs list.
--
function analyze_functions()

    -- Make a sorted list of functions to output.  Only use functions declared
    -- in one of the "good" files, and ignore those starting with "_", which
    -- are most likely private.  v[1][3] contains the file's ID.
    for k, v in pairs(xml.funclist) do
	local found = false
	assert(v[1][3])
	if good_files[v[1][3]] and string.sub(k, 1, 1) ~= "_" then
	    function_list[#function_list + 1] = k
	    _function_analyze(k)
	end
    end

    -- If aliases are defined, add them too.  The "from" function must
    -- exist, while the "to" function must not exist.  Note that the "from"
    -- function remains available, and must remain, because the argument
    -- list is defined there and not in the alias function entry.
    if config.lib.aliases then
	for to, from in pairs(config.lib.aliases) do
	    assert(xml.funclist[from])
	    assert(not xml.funclist[to])
	    function_list[#function_list + 1] = to
	    xml.funclist[to] = from
	    _function_analyze(from)
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
	    end
	end
    end
end

---
-- After finding all "native" types, those that refer to them are also
-- marked as native.
--
function analyze_structs_native()
    for id, t in pairs(typedefs) do
	if t.in_use then
	    _is_native(t)
	end
    end
end

---
-- Given a type ID, check whether that type is native, or a fundamental type.
--
-- @param t  Typespec
-- @return  false=not native, 1=native, 2=fundamental
--
function _is_native(t)
    if t.is_native ~= nil then return t.is_native end
    local is_native, t2

    if t.type == 'fundamental' then
	is_native = 2
    elseif good_files[t.file_id] then
	is_native = 1
    elseif config.native_types[t.full_name] then
	is_native = 1
    else
	-- follow pointers and qualifiers, then check that type.
	t2 = t
	while t2.type == 'pointer' or t2.type == 'qualifier' do
	    t2 = typedefs[t2.what]
	end
	if t2.type == 'fundamental' then
	    is_native = 2
	elseif t2.type == 'func' then
	    is_native = 1
	else
	    is_native = false
	end
    end

    t.is_native = is_native
    return is_native
end


-- For each member of the structure, mark their type in use.
function _analyze_struct(id, t)
    local st = t.struct
    local ignore_xml_tags = types.ignore_xml_tags

    for _, member_name in ipairs(st.members) do
	member = st.fields[member_name]
	if member and not ignore_xml_tags[member.type] then
	    types.mark_type_id_in_use(member.type,
		string.format("%s.%s", t.name, member.name or member_name))
	end
    end
end


---
-- Run through all useful globals and mark their types as used.
--
function analyze_globals()
    for name, var in pairs(xml.globals) do
	var.is_native = good_files[var.file]
	if var.is_native then
	    types.mark_type_id_in_use(var.type, name)
	end
    end
end


---
-- Mark some types as used, or create them.  This is for such types that are
-- not used by any function and are not part of a used structure.
--
-- Some required types are not even in the type list, like
-- GtkFileChooserWidget*; only GtkFileChooserWidget is defined, i.e. without
-- the pointer.  For these types, new ones are "synthetized", or derived, with
-- additional pointers.
--
function mark_override()
    local it, ar, name2id

    it = config.lib.include_types or {}
    ar = {}
    name2id = {}

    -- collect type names that should be available to LuaGnome.
    for _, name in ipairs(it) do
	ar[name] = true
    end

    -- collect OS specific types (if any)
    it = it[config.arch_os] or {}
    for _, name in ipairs(it) do
	ar[name] = true
    end

    -- skip this if no include_types are set.
    if not next(ar) then
	return
    end

    -- Scan all typedefs, resolve their names.  Requested types that can be
    -- found are marked in use.
    for id, t in pairs(typedefs) do
	if not t.full_name then
	    types.resolve_type(id, nil, true)
	    if not t.full_name then
		err("Could not resolve type %s %s %s", id, t.name, t.fname)
	    end
	end
	if t.full_name then
	    if ar[t.full_name] then
		if verbose > 1 then
		    print("mark_override", id, t.type, t.full_name)
		end
		types.mark_type_id_in_use(id, nil, true)
		t.is_native = true  -- all types in include_types are native.
		ar[t.full_name] = nil
	    elseif not name2id[t.full_name] then
		name2id[t.full_name] = id
	    end
	end
    end

    -- Try to synthetize a new pointer type for still undefined types.
    for full_name, v in pairs(ar) do
	if not synthesize_type(full_name, name2id) then
	    err("Type in include_types can't be synthesized: %s", full_name)
	else
	    ar[full_name] = nil
	end
    end
end


local next_synth_nr = 1

---
-- The requested type doesn't exist, so try to create it by deriving a new
-- type from an existing type.  This includes removing "const" and
-- indirections.
--
function synthesize_type(full_name, name2id)
    local parent_name, parent_id, new_id, parent, t, new_item

    if string.sub(full_name, 1, 6) == "const " then
	parent_name = string.sub(full_name, 7)
	new_item = { type="qualifier", const=true }
    elseif string.sub(full_name, -1) == "*" then
	parent_name = string.sub(full_name, 1, -2)
	new_item = { type="pointer" }
    else
	return false
    end

    parent_id = name2id[parent_name] or synthesize_type(parent_name, name2id)
    if not parent_id then return false end

    new_id = "synth" .. next_synth_nr
    next_synth_nr = next_synth_nr + 1
    parent = typedefs[parent_id]

    new_item.what = parent_id
    new_item.is_native = parent.is_native
    typedefs[new_id] = new_item

    t = types.mark_type_id_in_use(new_id, nil)
    if verbose > 1 then
	print("mark override new", new_id, t.type, t.full_name, full_name)
    end

    return new_id
end


---
-- Certain #defines from the Gtk/Gdk include files are relevant, but not
-- included in types.xml.  Extract them and add them to the ENUM list.
--
-- @param fname  Full pathname of the file to read
-- @param nums  boolean - whether to extract numerical #defines
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
		    "^#define ([A-Z][A-Za-z0-9_]+)%s+([0-9a-fx]+)$")
		if name and value then
		    assert(not enums[name])
		    enums[name] = { val=tonumber(value), context="__dummy" }
		    break
		end
	    end

	    -- string defines
	    name, value = string.match(line,
		"^#define ([A-Z_]+) +\"([^\"]+)\"")
	    if name and value then
		assert(not enums[name])
		enums[name] = { val=value, context="__dummy" }
		break
	    end

	    -- G_TYPE defines
	    name, value = string.match(line,
		"^#define ([A-Z0-9_]+)%s+G_TYPE_MAKE_FUNDAMENTAL%s+%((%d+)%)")
	    if name and value then
		-- *4 is what G_TYPE_MAKE_FUNDAMENTAL does.
		assert(not enums[name])
		enums[name] = { val=tonumber(value) * 4, context="__dummy" }
		break
	    end

	    -- Atoms
	    name, value = string.match(line,
		"^#define ([A-Z0-9_]+)%s+_GDK_MAKE_ATOM%s*%((%d+)%)")
	    if name and value then
		assert(not enums[name])
		local ctx = typedefs_name2id["GdkAtom"]
		assert(ctx, "Unknown type GdkAtom in #define")
		enums[name] = { val=tonumber(value), context=ctx }
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
    logfile:write(string.format("  %-40s%d\n", label, value))
end

-- read additional ENUMs from header files.  Do this after assign_type_idx,
-- so that the __dummy entry isn't being output.
function read_extra_headers()
    for _, row in ipairs(config.lib.headers or {}) do
	parse_header_file(row[1], row[2])
    end
end


function write_summary()
    logfile:write("Parsing Results for " .. arg[2] .. "\n\n")
    xml.show_statistics()
    types.show_statistics()
    output.show_statistics()
    enum_statistics()
    logfile:close()
    logfile = nil
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
    print(string.format("Usage: %s [options] {outputdir} {xmlfile} {cfgfile}",
	arg[0]))
    return
end

-- read config file for this build
config = load_config(arg[3])
assert(config.arch, "No architecture defined in config file")
config.arch = string.lower(config.arch)
config.arch_os = string.match(config.arch, "^[^-]+")
config.native_types = {}

logfile = assert(io.open(arg[1] .. "/parse-xml.log", "w"))

-- read config file for the library in this module
load_lib_config()
load_other_lib_config()

-- read the XML data
xml.parse_xml(arg[2])

make_file_list()
mark_ifaces_as_used()
analyze_globals()
analyze_functions()
mark_override()
analyze_structs()
mark_all_enums_as_used()
analyze_structs_native()
promote_enum_typedefs()

if true then
    count_const_usage()
end

-- before writing the structures, the functions must be looked at to
-- find prototypes that need registering.

typedefs_sorted = types.assign_type_idx()

-- Now that all used types have their IDs, the function prototypes
-- can be registered.
types.register_function_prototypes()

read_extra_headers()

-- The core library must provide support for all fundamental types, even though
-- it doesn't use all of them.  The modules don't have type handling, just
-- have a list of names of fundamental types they use.
if config.is_core then
    types.register_all_fundamental_types()
end

if build_errors > 0 then
    os.exit(1)
end

output.output_init()
output.output_types(arg[1] .. "/types.c")
output.output_constants(arg[1] .. "/constants.txt")
output.output_functions(arg[1] .. "/functions.txt")
if config.is_core then
    output.output_fundamental_types(arg[1] .. "/fundamentals.c")
else
    output.output_fundamental_hash(arg[1] .. "/fundamentals.c")
end
output.output_globals(arg[1] .. "/globals.c")
output.output_code(arg[1] .. "/generated.c")
write_summary(arg[1] .. "/parse.log")

if false then
    for k, t in pairs(typedefs) do
	if not t.in_use and not t.marked and good_files[t.file_id] then
	    print("unused", k, t.type, t.name)
	end
    end
end


