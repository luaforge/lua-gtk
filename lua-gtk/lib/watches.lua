#! /usr/bin/env lua
-- vim:sw=4:sts=4

local base = _G
local coroutine = coroutine
local print = print
local gtk = require "gtk"
local os = gtk.get_osname()
module "gtk.watches"

-- Watches

local _watches = {}		-- key = thread/channel/flags, true

--
-- Callback when a watch fired.  Resume the coroutine waiting for this event.
--
local function my_watch_func(thread, channel, condition)
    -- print("resume", thread)
    local rc, msg, channel, flags = coroutine.resume(thread, channel, condition)

    -- print("yield", thread, rc, msg, channel, flags)

    -- blocked on a channel? if the IOWait doesn't exist yet, add it.
    if rc and msg == "iowait" then
	add_watch(thread, channel, flags)
    end
    --
    -- exit gracefully; should not be required.
    if not rc then
	print "WARNING: thread died unexpectedly:"
	print(msg)
	-- this must not happen.  An endless loop could ensue
	if msg == "cannot resume dead coroutine" then
	    gtk.main_quit()
	end
	remove_watch(thread, nil, nil)
    end

    return rc
end


--
-- Return a key for the _watches table
--
local function _watch_key(thread, channel, flags)
    local s = (thread and base.tostring(thread) or ".-") .. ","
    s = s .. (channel and base.tostring(channel) or ".-") .. ","
    s = s .. (flags and base.tostring(flags) or ".-")
    return s
end

--
-- Watch a channel
--
function add_watch(thread, channel, flags)
    local key = _watch_key(thread, channel, flags)
    if _watches[key] then return end
    -- print("ADD WATCH", key)

    -- first, remove other watches on this channel.  For example, if there's
    -- a write watch, but now the user wants to read something, then the write
    -- watch would always fire even though there's nothing to read.
    remove_watch(thread, channel, nil)

    local id = gtk.my_g_io_add_watch(channel, flags, my_watch_func, thread)
    -- print("ID is", id)
    _watches[key] = id or true
end


--
-- Remove unused watches.
--
-- thread, channel and/or flags can be nil; in this case, they act as wildcard.
--
function remove_watch(thread, channel, flags)
    local key = _watch_key(thread, channel, flags)

    -- print("Removing watches for", key)
    for k, v in base.pairs(_watches) do
	if base.string.match(k, key) then
	    -- print("REMOVE WATCH", k)
	    gtk.g_source_remove(_watches[k])
	    _watches[k] = nil
	end
    end
end

function start_watch(thread)
    return my_watch_func(thread, nil, 0)
end

