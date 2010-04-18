#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Scan all the .so files and show a table with the sizes of the
-- parts of the module, like type, function and constants data.
--
-- TODO:
--   - if possible, differentiate "other", which is mostly dynamic linking
--     information
--
--   - using extra information from somewhere, split type information into
--     that for "native" types and "glue" types.
--

require "lfs"

build_path = "build/linux-i386"

-- Array of patterns (where MOD is replaced with the current module's
-- name) and names of column names:
--
--  acode	Automatically generated code
--  array	Information about array types
--  bss		The BSS section (uninitialized read/write data)
--  code	Well, code.
--  const	All data sections describing constants (names, values)
--  func	Data about functions (names, argument types)
--  globals	Global variables: names and types
--  link	Dynamic linking table
--  other	All other code or data not assigned to another column
--  type	Information about data types
--
patterns = {
    { "MOD_array_list",	    "array" },

    -- code or code-like symbols
    { "module_methods",	    "code" },
    { "modinfo_MOD",	    "code" },
    { "luaopen_MOD",	    "code" },
    { "MOD_overrides",	    "code" },

    -- automatic code
    { "__do_global_ctors_aux", "acode" },
    { "_fini",		    "acode" },
    { "__CTOR_LIST__",	    "acode" },
    { "__DTOR_LIST__",	    "acode" },


    -- information about global symbols
    { "MOD_globals",	    "globals" },

    -- symbols needed to glue different modules together.
    { "MOD_dynlink_names",  "link" },
    { "MOD_dynlink_table",  "link" },
    { "MOD_fundamental_hash", "link" },
    { "MOD_strings_modules", "link" },
    { "api",		    "link" },
    { "thismodule",	    "link" },
    { "_DYNAMIC",	    "link" },
    { "_GLOBAL_OFFSET_TABLE_", "link" },


    -- data about types
    { "MOD_strings_proto",  "types" },
    { "MOD_strings_types",  "types" },
    { "MOD_type_list",	    "types" },
    { "MOD_strings_elem",   "types" },
    { "MOD_elem_list",	    "types" },

    -- data about constants
    { "hash_info_constants", "const" },
    { "_constants_data",    "const" },
    { "_constants_fch",	    "const" },
    { "_constants_bdz",	    "const" },
    { "_constants_buckets", "const" },
    { "_constants_index",   "const" },

    -- data about functions
    { "hash_info_functions", "func" },
    { "_functions_data",    "func" },
    { "_functions_fch",	    "func" },
    { "_functions_bdz",	    "func" },
    { "_functions_buckets", "func" },
    { "_functions_index",   "func" },

    { "_edata",		    "other" },

}

totals = {}
totalsize = {}		    -- key=modulename, value=size as output by the "size" command


function detect_arch()
    for line in io.lines "build/make.state" do
	s = string.match(line, "^ARCH.*=(.*)$")
	if s then
	    build_path = "build/" .. s
	    break
	end
    end
end

---
-- Determine to which column to add the symbol's size.
--
function store_symbol(fname, size, name, type_)
    local pattern, column

    assert(fname)
    totals[fname] = totals[fname] or {}

    for _, ar in ipairs(patterns) do
	pattern, column = unpack(ar)
	pattern = pattern:gsub("MOD", fname)
	if name == pattern then
	    totals[fname][column] = (totals[fname][column] or 0) + size
	    return
	end
    end

    -- text or initialized data belongs to the code, as well as read-only data
    type_ = string.lower(type_)
    if type_ == "t" or type_ == "d" or type_ == "r" then
	totals[fname].code = (totals[fname].code or 0) + size
	return
    end

    if type_ == "b" then
	totals[fname].bss = (totals[fname].bss or 0) + size
	return
    end

    -- not found; should not happen.
    print("?", fname, name, size)
end


---
-- Run the "nm" command on each shared object.  When used with --print-size,
-- it still omits quite a few symbols; therefore, run with --numeric-sort and
-- compute the size as the difference to the next offset.  --print-size
-- sometimes gives a slightly lower size, as it doesn't include padding.
--
function gather_nm()
    local fname, s, prev_ofs, prev

    local f = io.popen("nm --numeric-sort " .. build_path .. "/*/*.so")
    for l in f:lines() do
	local ofs, type_, name = l:match("^(%x+) (%a) (.*)$")

	if ofs then
	    ofs = tonumber("0x" .. ofs)
	    if prev and prev[3] ~= "__FRAME_END__" then
		prev[2] = ofs - prev[2]
		if prev[2] > 0 then
		    store_symbol(unpack(prev))
		end
	    end
	    prev = { fname, ofs, name, type_ }
	end

	s = l:match("([^/]+)%.so:$")
	if s then
	    fname = s
	    prev_ofs = nil
	end
    end

    f:close()

    -- note: the last symbol isn't included!
end

---
-- Run the "size" command on each shared object; I assume that this is the "true" size,
-- disregarding debugging info.  This is therefore better than the file size.
--
function gather_size()
    local f = io.popen("size " .. build_path .. "/*/*.so")
    for l in f:lines() do
	if not l:match(" *text") then
	    -- text data bss dec hex filename
	    size, name = string.match(l,
		"^%s*%d+%s*%d+%s*%d+%s*(%d+).-(%w+)%.so")
	    totalsize[name] = size
	end
    end
end


    


function show_result()
    local s, size, sum, sumsum
    local mods = {}
    local cols = {}
    local cols2 = { "other" }
    local mod_maxlen = 0

    -- sorted table of modules
    for k, v in pairs(totals) do
	mods[#mods + 1] = k
	mod_maxlen = math.max(mod_maxlen, #k)
	for k, v in pairs(v) do
	    cols[k] = true
	end
    end
    table.sort(mods)

    -- sorted table of columns
    for k, _ in pairs(cols) do
	cols2[#cols2 + 1] = k
    end
    table.sort(cols2)
    cols = cols2

    -- column headers
    s = string.rep(" ", mod_maxlen + 2)
    for _, v in ipairs(cols) do
	s = s .. string.format(" %8s", v)
    end
    s = s ..string.format(" %8s", "TOTAL")
    print(s)

    for _, modname in ipairs(mods) do
	s = string.format("%-" .. mod_maxlen .. "s  ", modname)

	-- calculate size of known columns, the rest is attributed to "other"
	sum = 0
	for _, colname in ipairs(cols) do
	    size = totals[modname][colname] or 0
	    sum = sum + size
	end

	-- output the sizes in each column
	for _, colname in ipairs(cols) do
	    if colname == "other" then
		size = totalsize[modname] - sum
		totals[modname][colname] = size
	    else
		size = totals[modname][colname] or 0
	    end
	    s = s .. string.format(" %8d", size)
	end

	-- output the row's total
	s = s .. string.format(" %8d", totalsize[modname])

	print(s)
    end

    -- separator line
    s = string.rep("-", mod_maxlen + 2 + (#cols + 1) * 9)
    print(s)

    -- show the column totals
    s = string.rep(" ", mod_maxlen + 2)
    sumsum = 0
    for _, colname in ipairs(cols) do
	sum = 0
	for _, modname in ipairs(mods) do
	    size = totals[modname][colname] or 0
	    sum = sum + size
	end
	s = s .. string.format(" %8d", sum)
	sumsum = sumsum + sum
    end
    s = s .. string.format(" %8d", sumsum)
    print(s)

end

detect_arch()
gather_nm()
gather_size()
show_result()

