#! /usr/bin/env lua
-- vim:sw=4:sts=4

local base = _G
local coroutine = coroutine
local print = print
local gtk = require "gtk"
local os = gtk.get_osname()
module "gtk.watches"

---
-- Watches.  These are used to run network communication in the background.
-- A coroutine that needs to wait on input or output, calls coroutine.yield
-- with appropriate parameters.
--

_watches = {}		-- key = thread/channel/cond, true

--
-- Callback when a watch fired; it is normally called via _watch_handler
-- in src/channel.c.  Resume the coroutine waiting for this event.  It can also
-- be used to start a thread.
--
-- Note: it is called in the global Lua state (thread) for callbacks, or
-- in any thread when called from start_watch().
--
function _watch_func(thread, channel, cond)
    local rc, msg

    -- Run the coroutine (thread) until it has to block; it either calls
    -- yield(), exits normally or calls error().
    -- print("run", thread)
    rc, msg, channel, cond = coroutine.resume(thread, channel, condition)
    -- print("done", thread, rc, msg, channel, cond)

    -- if resume returns false, then an error was raised in the thread.
    if not rc then
	print "WARNING: thread died unexpectedly:"
	print(msg)
	-- this must not happen.  An endless loop could ensue
	if msg == "cannot resume dead coroutine" then
	    gtk.main_quit()
	end
	remove_watch(thread, nil, nil)
	return rc
    end

    -- Blocked on a channel? if the IOWait doesn't exist yet, add it.
    if msg == "iowait" then
	add_watch(thread, channel, cond)
	return rc
    end

    -- XXX some other reasons to block (besides iowait) might be added later.

    print "Thread exited."
    remove_watch(thread, nil, nil)
    if not msg then print(channel) end
    return false
end


--
-- Return a key for the _watches table
--
function _watch_key(thread, channel, cond)
    local s = (thread and base.tostring(thread) or ".-") .. ","
    s = s .. (channel and base.tostring(channel) or ".-") .. ","
    s = s .. (cond and base.tostring(cond) or ".-")
    return s
end

---
-- Watch a channel.
--
-- When an appropriate event (specified by cond) happens, The function
-- _watch_func will be invoked, which then resumes the given thread.
--
-- @param thread       The thread to resume when the event happens
-- @param channel      The channel to wait on
-- @param cond         The condition to wait for
--
function add_watch(thread, channel, cond)
    local key = _watch_key(thread, channel, cond)
    if _watches[key] then return end
    -- print("ADD WATCH", key)

    -- First, remove other watches on this channel.  For example, if there's
    -- a write watch, but now the user wants to read something, then the write
    -- watch would always fire even though there's nothing to read.
    remove_watch(thread, channel, nil)

    local id = gtk.my_g_io_add_watch(channel, cond, _watch_func, thread)
    -- print("ID is", id)
    _watches[key] = id or true
end


--
-- Remove unused watches.
--
-- thread, channel and/or cond can be nil; in this case, they act as wildcard.
--
function remove_watch(thread, channel, cond)
    local key = _watch_key(thread, channel, cond)

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
    return _watch_func(thread, nil, 0)
end

