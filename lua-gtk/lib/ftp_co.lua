#! /usr/bin/env lua
-- vim:sw=4:sts=4
--

local base, string, print = _G, string, print

require "gtk"
require "gtk.watches"
require "gtk.socket_co"
require "gtk.strict"

---
-- This is an FTP client that currently only supports file uploads.  It uses
-- coroutines so that it never blocks, and it can run in the background, while
-- the Gtk2 GUI is fully responsive.
--
-- It is based, of course, on luasocket and its FTP module.
--
-- Copyright (C) 2007 Wolfgang Oertl
--

module "gtk.ftp_co"
base.gtk.strict.init()

gtk = base.gtk
socket_co = gtk.socket_co

PORT = 21
TIMEOUT = 60

--
-- Wait for greeting
-- returns nil, errormessage on error
--
function greet(arg)
    local rc, msg = socket_co.check(arg.channel, "1..", "2..")
    if not rc then return rc, msg end
    if string.find(rc, "1..") then
	return socket_co.check(arg.channel, "2..")
    end
    return rc, msg
end

--
-- Send an FTP command to the server.
--
function command(ioc, cmd, arg)
    if arg then
	return socket_co.write_chars(ioc, cmd .. " " .. arg .. "\r\n", false)
    else
	return socket_co.write_chars(ioc, cmd .. "\r\n", false)
    end
end


--
-- Perform the login procedure with user and password.
--
function login(arg)
    command(arg.channel, "user", arg.user or USER)
    local rc, msg = socket_co.check(arg.channel, "2..", "331")
    if rc == 331 then
	command(arg.channel, "pass", arg.password or PASSWORD)
	rc, msg = socket_co.check(arg.channel, "2..")
    end
    return rc, msg
end

function quit(ioc)
    local rc, msg = command(ioc, "quit")
    if not rc then return rc, msg end

    return socket_co.check(ioc, "2..")
end

--
-- Request a second connection (the data channel) to the FTP server.
-- Returns the IP address and the port to connect to.
--
function pasv(ioc)
    local rc, msg = command(ioc, "pasv")
    if not rc then return rc, msg end

    rc, msg = socket_co.check(ioc, "2..")
    if not rc then return rc, msg end

    local pattern = "(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)"
    local _a, _b, a, b, c, d, p1, p2 = string.find(msg, pattern)
    if not (a and b and c and d and p1 and p2) then return nil, "leider nein" end

    return { string.format("%d.%d.%d.%d", a, b, c, d), p1 * 256+ p2 }
end

---
-- Use a table with this structure to pass the request to either put or put_co.
-- @class table
-- @name request_spec
-- @field source Type of the upload; can be "file", "buffer" or a valid
--   source object (see socket_co).
-- @field host   Hostname or IP address of the server
-- @field port   (optional) The port to connect to, default is 21.
-- @field callback (optional) A function to call during the upload with
--   status updates.
--

---
-- Upload a file using FTP.  You proably want to use the ftp_co function
-- instead, which starts a new coroutine to asynchronously do the FTP
-- transfer.
--
-- Note: this performs login, upload and logout.  Multiple commands in one
-- session are currently not supported.
--
-- @param arg   A table with the request specification.
-- @return rc:  nil on error
-- @return msg: on error, a description of the error.
-- @see request_spec
--
function put(arg)
    local rc, msg

    if base.type(arg.source) == "string" then
	arg.source = socket_co.source[arg.source]
    end

    -- Check the source, e.g. for a file, whether it is readable.
    rc, msg = arg:source("open")
    if not rc then return rc, msg end

    -- we usually wait on input on this socket, i.e. a response of the server.
    rc, msg = socket_co.connect(arg.host, arg.port or PORT, false)
    if not rc then return rc, msg end
    arg.channel = rc
    arg.channel_socket = msg

    rc, msg = put_2(arg)

    gtk.watches.remove_watch(nil, arg.channel, nil)
    arg.channel:shutdown(false, nil)
    gtk.widgets[arg.channel] = nil
    arg.channel = nil

    -- #sc The actual file close happened by the shutdown, but this is required
    -- to let the socket know it has been closed.  Otherwise, at a random point
    -- in time, garbage collection collects this socket, closing the file
    -- descriptor it had - which probably is in use again!!
    arg.channel_socket:close()
    arg.channel_socket = nil

    if not rc then
	print("TRANFER FAILED", msg)
    end

  
    if arg.callback then arg:callback('done') end

    return rc, msg
end

-- The command channel is open; negotiate with the FTP server, open a data
-- connection, then call put_3.
function put_2(arg)
    local rc, msg, data_ioc, data_ioc_sock, pasv_data

    rc, msg = greet(arg)
    if not rc then return rc, msg end

    rc, msg = login(arg)
    if not rc then return rc, msg end

    rc, msg = command(arg.channel, "type", "i")
    if not rc then return rc, msg end

    rc, msg = socket_co.check(arg.channel, "200")
    if not rc then return rc, msg end

    rc, msg = pasv(arg.channel)
    if not rc then return rc, msg end
    pasv_data = rc

    rc, msg = socket_co.connect(pasv_data[1], pasv_data[2], false)
    if not rc then return rc, msg end
    data_ioc = rc
    data_ioc_sock = msg

    rc, msg = put_3(arg, data_ioc)

    -- closing the data channel tell the FTP server that the transfer is over
    gtk.watches.remove_watch(nil, data_ioc, nil)
    data_ioc:shutdown(false, nil)
    gtk.widgets[data_ioc] = nil
    -- MUST do this, otherwise... se note #sc above
    data_ioc_sock:close()

    if not rc then return rc, msg end

    -- expect 226 Transfer complete.
    rc, msg = socket_co.check(arg.channel, "2..")
    if not rc then return rc, msg end

    -- properly log out; not really required.
    rc, msg = quit(arg.channel)
    if not rc then return rc, msg end

    return "Transfer completed"
end

--
-- The data channel has been opened, so now perform the transfer.
--
-- This is in a separate function so that cleanup is performed in all cases.
--
function put_3(arg, data_ioc)
    local rc, msg, buf, count, last_byte, total_size

    rc, msg = command(arg.channel, "stor", arg.path)
    if not rc then return rc, msg end

    rc, msg = socket_co.check(arg.channel, "1..", "2..")
    if not rc then return rc, msg end

    count = 0
    total_size = arg:source("get-length")
    while true do
	-- Lua bufsize seems to be 4096 (looking at strace output on Linux)
	buf = arg:source("read", 4096)
	if not buf then break end
	-- flushing makes the progress display more accurate.
	-- print("sending", string.len(buf), "bytes to", data_ioc,
	--    arg.channel_socket)
	rc, msg, last_byte = socket_co.write_chars(data_ioc, buf, false)
	-- XXX detect non-permanent failure, and send again starting at
	-- last_byte.
	if not rc then print("some failure", msg); return rc, msg end
	count = count + string.len(buf)
	if arg.callback then
	    rc = arg:callback('progress', count / total_size)
	    if rc ~= nil and rc == false then return nil, "User abort" end
	end
	-- test refcounting...
	base.collectgarbage("collect")
    end

    return true, "put_3 exited normally"
end

---
-- Start a PUT request as a new thread.  This is what you should use.
--
-- @param arg   A table with the request specification.
-- @see put
--
function put_co(arg)
    local thread = base.coroutine.create(function()
	local rc, msg = put(arg)
	if not rc and arg.callback then arg:callback('failure', msg) end
	return rc, msg
    end)

    gtk.watches.start_watch(thread)
end

gtk.strict.lock()

