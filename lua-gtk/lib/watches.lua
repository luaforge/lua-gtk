-- vim:sw=4:sts=4

local base, coroutine, print = _G, coroutine, print
require "gtk"
require "gtk.strict"

---
-- Manage asynchronous requests for the Gtk main loop.
--

module "gtk.watches"
base.gtk.strict.init()

gtk = base.gtk

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
    rc, msg, channel, cond = coroutine.resume(thread, channel, cond)
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
	return false
    end

    -- Blocked on a channel? if the IOWait doesn't exist yet, add it.
    if msg == "iowait" then
	add_watch(thread, channel, cond)
	return false
    end

    -- not blocked on this channel; either sleep, or exit.
    remove_watch(thread, nil, nil)

    -- sleep a certain interval?  channel is the interval
    if msg == "sleep" then
	gtk.g_timeout_add(channel, _watch_func, thread)
	return false
    end

    if (not msg) and channel then print(channel) end
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

    -- always include G_IO_ERR, otherwise on error a 100% busy loop ensues.
    local id = gtk.my_g_io_add_watch(channel, cond + gtk.G_IO_ERR,
	_watch_func, thread)
    -- print("ADD WATCH", id, key)
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
	    -- print("REMOVE WATCH", k, _watches[k])
	    gtk.g_source_remove(_watches[k])
	    _watches[k] = nil
	end
    end
end

function start_watch(thread, arg1)
    if base.type(thread) == "function" then
	thread = coroutine.create(thread)
    end
    return _watch_func(thread, arg1, 0)
end

gtk.strict.lock()

