#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Functions used from configure.lua, parse-xml.lua, make-link.lua,
-- make-xml.lua and others.
--
-- Exported symbols:
--  load_spec
--  load_config
--  function_flag_map
--

-- This map must match the defines for FLAG_xxx in include/common.h.  These
-- constants are available to library config files.
function_flag_map = {
    CONST_OBJECT = 1,		-- used
    NOT_NEW_OBJECT = 2,		-- used
    DONT_FREE = 4,		-- used
    CHAR_PTR = 0x1000,		-- used indirectly
    CONST_CHAR_PTR = 0x2000,	-- used indirectly
}

-- Read a Lua file, no frills.
function load_config(fname, tbl)
    local chunk
    chunk = assert(loadfile(fname))
    tbl = tbl or {}
    setfenv(chunk, tbl)
    chunk()
    return tbl
end

-- read another modules's spec file and copy all settings into the current
-- spec.
local function include_spec(modname)
    local fname, spec, target

    fname = string.format("src/%s/spec.lua", modname)
    spec = load_config(fname)
    target = getfenv(2)
    for k, v in pairs(spec) do
	target[k] = v
    end
end

local function ignore_spec(name)
end

---
-- Read a Lua configuration file.  In case of error, aborts the application.
--
-- @param fname  The path and name of the file to load
-- @param is_other  True when loading all other libraries; don't follow
--	include_spec statements.  Only "native" declarations are considered.
-- @return  A table with the variables defined in that file.
--
function load_spec(fname, is_other)
    local tbl = { include_spec=is_other and ignore_spec or include_spec }
    for k, v in pairs(function_flag_map) do
	tbl[k] = v
    end
    return load_config(fname, tbl)
end

