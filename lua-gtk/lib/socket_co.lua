#! /usr/bin/env lua
-- vim:sw=4:sts=4

local base, string, coroutine, print = _G, string, coroutine, print

require "gtk"
require "gtk.strict"
require "socket.core"

---
-- Socket communication using coroutines, integrated with the Gtk message loop
-- to allow background transfers.
-- Copyright (C) 2007 Wolfgang Oertl
--

module "gtk.socket_co"
base.gtk.strict.init()

gtk = base.gtk
os = gtk.get_osname()

---
-- A data source for upload which reads from a buffer in memory.
--
-- @param arg	The usual arg
-- @param op    The operation, may be open, get-length, or read
-- @param len	For read, how many bytes to return at most.
-- @return      For read, the next <code>len</code> bytes; nil at EOF
--
function source_buffer(arg, op, len)
    local slice

    if op == 'open' then
	if not arg.source_pos then
	    arg.source_pos = 1
	    arg.source_size = string.len(arg.source_data)
	end
	return true
    end

    if op == 'get-length' then
	return arg.source_size
    end
    
    if op == 'read' then
	if arg.source_pos >= arg.source_size then return nil end
	slice = string.sub(arg.source_data, arg.source_pos,
	    arg.source_pos + len-1)
	arg.source_pos = arg.source_pos + string.len(slice)
	return slice
    end
end

---
-- A data source that reads from a file.
--
-- XXX The file is read synchronously; it could be otherwise, yielding as
-- required.
--
function source_file(arg, op, len)
    if arg.closed then return nil end

    if op == 'open' then
	if not arg.file then
	    arg.file = base.io.open(arg.source_data, "r")
	    if not arg.file then return nil, "can't open input file "
		.. arg.source_data end
	    arg.size = arg.file:seek("end")
	    arg.file:seek("set")
	    -- print("opened input file", arg.source_data, arg.size)
	end
	return true
    end

    if op == 'get-length' then
	return arg.size
    end

    if op == 'read' then
	local buf = arg.file:read(len)
	if not buf then
	    arg.file:close()
	    arg.closed = true
	end
	return buf
    end
end

---
-- Implements a source that is a chain of multiple subsources.
--
-- set arg.source_parts as an array of { source=..., source_data=... }
--
function source_chain(arg, op, len)
    local rc, msg

    if op == 'open' then
	-- print("source_chain: open.  subpart count:", #arg.source_parts)
	for i, v in base.pairs(arg.source_parts) do
	    rc, msg = v:source("open")
	    if not rc then return rc, msg end
	end
	arg.source_data = {}
	arg.source_data.curr_part = 1
	return true
    end

    if op == 'get-length' then
	local size = 0
	for i, v in base.pairs(arg.source_parts) do
	    local subsize = v:source(op)
	    -- print("source_chain: length of subpart", i, "is", subsize)
	    size = size + subsize
	end
	-- print("source_chain: total length is", size)
	return size
    end

    if op == 'read' then
	local d = arg.source_data
	if d.curr_part >  #arg.source_parts then
	    -- print("source_chain: no more subparts.")
	    return nil, "no more subparts to read in source_chain."
	end
	-- print("source_chain: reading from subpart", d.curr_part, len)
	rc, msg = arg.source_parts[d.curr_part]:source("read", len)
	if rc then
	    -- print("source_chain: got " .. string.len(rc) .. " bytes")
	    return rc, msg
	end
	-- print("no more data in subpart", d.curr_part)
	d.curr_part = d.curr_part + 1
	-- try again for next part
	return arg:source("read", len)
    end

    print("source_chain: invalid command", op)
end


source = { file = source_file, buffer = source_buffer }

---
-- Connect to the server.
--
-- Returns the new GIOChannel and the socket.  Be sure to keep a reference
-- to the socket, otherwise it will be destroyed!
--
-- @param host        Host to connect to; IP address or DNS name.
-- @param port        The port to connect to; must be numeric.
-- @param buffered    true to use buffered sockets; don't do this.
-- @return GIOChannel, or nil + error message.
--
function connect(host, port, buffered)
    local sock, rc, msg, gio

    sock, msg = base.socket.tcp()
    if not sock then return sock, msg end

    sock:settimeout(0)
    gio = create_io_channel(sock, buffered)

    -- DNS resolution may block, unfortunately it is not asynchronous.
    rc, msg = sock:connect(host, port)
    if rc then return gio, sock end

    -- failed to connect; if timeout, then wait, otherwise return error
    if msg ~= "timeout" then return rc, msg end
    coroutine.yield("iowait", gio, gtk.G_IO_OUT)
    return gio, sock
end

---
-- Given a socket, construct a GIOChannel around it.
--
-- @param sock       A socket
-- @param buffered   Should be false
-- @return a GIOChannel for the socket, and the socket itself
--
function create_io_channel(sock, buffered)
    local fd, gioc = sock:getfd()

    -- print("creating a GIOChannel for fd", fd)

    if os == "win32" then
	gioc = gtk.g_io_channel_win32_new_socket(fd)
    else
	gioc = gtk.g_io_channel_unix_new(fd)
    end

    -- created with ref=1, and the assignment sets it to two.
    -- gioc:unref();
    gioc:set_encoding(nil, nil)
    gioc:set_buffered(buffered)

    gioc._buffer = ""
    gioc._bufpos = 1

    if buffered then
	print "WARNING buffered IOChannels are deprecated."
    end

    -- may lead to problems...
    gioc:set_close_on_unref(false)

    --[[
    local meta = base.getmetatable(sock)
    if not meta.__old_gc then
	meta.__old_gc = meta.__gc
	meta.__gc = socket_gc
    end
    --]]

    return gioc, sock
end

--[[
function socket_gc(sock)
    local meta = base.getmetatable(sock)
    print("SOCKET GC of", sock, meta)
    if meta.__old_gc then meta.__old_gc(sock) else print "no __old_gc" end
end
--]]


---
-- Read a line from the server; if no input is available, yield.
-- Buffering is done internally.
--
function receive_line(ioc)
    local rc, msg, buf, pos, start

    while true do

	buf, start = ioc._buffer, ioc._bufpos

	pos = string.find(buf, "\n", start, true)
	if pos then
	    ioc._bufpos = pos + 1
	    -- strip optional \r at end of line
	    if string.sub(buf, pos-1, pos-1) == "\r" then
		pos = pos - 1
	    end
	    buf = string.sub(buf, start, pos - 1)
	    -- print("* returning: >>" .. buf .. "<<")
	    return buf
	end

	-- need to read more.
	while true do
	    rc, msg = ioc:read_chars(1024)
	    if rc or msg ~= 'timeout' then break end
	    rc, msg = coroutine.yield("iowait", ioc, gtk.G_IO_IN)
	end

	if not rc then break end

	-- keep unread part of the input buffer, append new data, try again.
	ioc._buffer = string.sub(ioc._buffer, start) .. rc
	ioc._bufpos = 1
    end

    -- on error, msg contains some info
    return rc, msg
end

---
-- Read some data from the server.  This has to take our own buffering
-- into account.
--
-- It can return UP TO length bytes but may return less.  Calling it again
-- will then return more, unless the server stops sending data.
--
-- @param ioc     GIOChannel
-- @param length  Max. bytes to read
-- @return        Buffer, or nil and message
--
function read_chars(ioc, length)
    local rc, msg, buf

    -- do we have data in the input buffer left over?
    if #ioc._buffer >= ioc._bufpos then
	buf = string.sub(ioc._buffer, ioc._bufpos, ioc._bufpos + length - 1)
	ioc._bufpos = ioc._bufpos + #buf
	-- print("* read chars from buffer", #buf)
	return buf
    end

    -- print("* need to read something")
    while true do
	rc, msg = ioc:read_chars(length)
	if rc or msg ~= 'timeout' then break end
	-- print "read_chars: need to wait"
	coroutine.yield("iowait", ioc, gtk.G_IO_IN)
    end

    return rc, msg
end

---
-- Read a reply from the server
-- This is somewhat protocol specific, but works for FTP and HTTP.
--
function get_reply(ioc)
    local code, current, sep, line, err, reply, _

    line, err = receive_line(ioc)
    if not line then return nil, err end

    reply = line

    _, _, code, sep = string.find(line, "^(%d%d%d)(.?)")
    if not code then return nil, "invalid server reply" end

    -- multiline response?
    if sep == '-' then
	repeat
	    line, err = receive_line(ioc)
	    if not line then return nil, err end

	    _, _, current, sep = string.find(line, "^(%d%d%d)(.?)")
	    reply = reply .. "\n" .. line
	until code == current and sep == " "
    end

    return code, reply
end


---
-- Read a response from the server, and compare with allowed status codes.
-- returns the response if OK, else NIL and an error message
--
function check(ioc, ...)
    local code, reply = get_reply(ioc)
    if not code then return nil, reply end
    for i = 1, base.select('#', ...) do
	local pattern = base.select(i, ...)
	if string.find(code, pattern) then
	    return base.tonumber(code), reply
	end
    end

    return nil, reply
end

---
-- Send a block of data over the given socket.
--
function write_chars(ioc, data, do_flush)
    local rc, msg, bytes_written

    while true do
	rc, msg, bytes_written = ioc:write_chars(data)
	if rc or msg ~= "timeout" then break end
	data = string.sub(data, bytes_written+1)
	coroutine.yield("iowait", ioc, gtk.G_IO_OUT)
    end

    -- on successful write, maybe force a flush.
    -- XXX This doesn't work as intended.  It does advise the glib routine to
    -- actually write the data to the socket from its internal buffers, but
    -- this may fail with EAGAIN.
    if rc and do_flush then
	rc, msg = flush(ioc)
    end

    return rc, msg
end


---
-- Make sure all the data is actually written to the socket.
--
-- NOTE:
-- There is a problem with Glib.  The watch G_IO_OUT that is placed on the
-- channel only checks that the channel's output buffers are not full.  I
-- don't see a way to wait on the channel such that the socket is ready
-- to take more data.  Therefore, this goes into a 100% CPU busy loop.
--
-- NOTE 2:
-- in this form, probably does nothing.  A flush would have to be performed
-- on the socket, not on the channel.
--
function flush(ioc)
    local rc, msg

    print "* flush"

    if ioc:get_buffered() then	
	print("ERROR: trying to flush a buffered output channel! "
	    .. "This won't work properly.")
    end

    while true do
	rc, msg = ioc:flush()
	if rc or msg ~= "timeout" then break end
	print("YIELD in flush", ioc, gtk.G_IO_OUT)
	local rc, msg = coroutine.yield("iowait", ioc, gtk.G_IO_OUT)
    end

    return rc, msg
end

gtk.strict.lock()

