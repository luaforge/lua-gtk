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

-- _watches = {}		-- key = thread/channel/cond, true

--
-- Callback when a watch fired; it is normally called via _watch_handler
-- in src/channel.c.  Resume the coroutine waiting for this event.  It can also
-- be used to start a thread.
--
-- If this watch should be kept, return true, else false.
--
-- Note: it is called in the global Lua state (thread) for callbacks, or
-- in any thread when called from start_watch().
--
function _watch_func(thread, channel, cond, old_cond)

    -- Run the coroutine (thread) until it has to block; it either calls
    -- yield(), exits normally or calls error().
    local rc, msg, new_channel, new_cond = coroutine.resume(thread, channel,
	cond)

    -- if resume returns false, then an error was raised in the thread.
    if not rc then
	print "WARNING: thread died unexpectedly:"
	print(msg)
	-- this must not happen.  An endless loop could ensue
	if msg == "cannot resume dead coroutine" then
	    gtk.main_quit()
	end
	return false
    end

    -- Blocked on a channel? if the IOWait doesn't exist yet, add it.
    if msg == "iowait" then

	-- must also watch for IO Errors, otherwise endless loops may happen.
	new_cond = new_cond + gtk.G_IO_ERR

	-- keep same watch if waiting for the same thing.
	if channel == new_channel and old_cond == new_cond then
	    return true
	end

	-- add a new watch and discard the previous one
	local id = gtk.g_io_add_watch(new_channel, new_cond, _watch_func_2,
	    { thread, new_cond })
	return false
    end

    -- sleep a certain interval?  new_channel is the interval
    if msg == "sleep" then
	gtk.g_timeout_add(new_channel, _watch_func_1, thread)
	return false
    end

    if (not msg) and new_channel then print(channel) end
    return false
end

-- prototype GSourceFunc(gpointer data)
function _watch_func_1(thread)
    return _watch_func(thread)
end

-- prototype GIOFunc(GIOChannel, GIOCondition, gpointer)
function _watch_func_2(channel, condition, data)
    return _watch_func(data[1], channel, condition, data[2])
end

function start_watch(thread, channel)
    if base.type(thread) ~= "thread" then
	thread = coroutine.create(thread)
    end
    return _watch_func(thread, channel, 0, 0)
end

gtk.strict.lock()

