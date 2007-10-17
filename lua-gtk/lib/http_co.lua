#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
---
-- HTTP requests using the socket_co library.
-- Copyright (C) 2007 Wolfgang Oertl
--

local base = _G
local string = string
local print = print
local gtk = require "gtk"
local watches = require "gtk.watches"
local socket_co = require "gtk.socket_co"

module "gtk.http_co"

base.strict()

PORT = 80

---
-- Given a list of POST variables, produce a string suitable as body for
-- a POST request.
--
-- XXX urlencoding not yet done
--
function build_post_request(arg)
    local s

    for k, v in base.pairs(arg) do
	v = string.gsub(v, " ", "%%20")
	if s then
	    s = s .. "&" .. k .. "=" .. v
	else
	    s = k .. "=" .. v
	end
    end

    return s
end

---
-- This sink collects the body in a variable.  It is the default, unless
-- you specify another function like this: request{sink=...}.
--
function sink_memory(arg, chunk)
    if not arg.sink_data then
	arg.sink_data = chunk
    elseif chunk then
	arg.sink_data = arg.sink_data .. chunk
    end
end

---
-- Write the body to a file.  Each call provides some more data; when
-- called with NIL, this means the end of input -> close the file.
--
function sink_file(arg, chunk)
    if not chunk then
	if arg.ofile then
	    arg.ofile:close()
	    arg.ofile = nil
	end
	return
    end

    if not arg.ofile then
	arg.ofile = base.io.open(arg.body_file, "w")
    end
    arg.ofile:write(chunk)
end

---
-- Start a request as new coroutine.  No return value is given; instead, set
-- the callback function in arg and/or a sink function.  See request() for
-- an explanation.
--
function request_co(arg)
    local thread = base.coroutine.create(function()
	local rc, msg = request(arg)
	if rc ~= "http ok" then
	    if arg.callback then
		arg:callback("error", rc, msg)
	    end
	    print("request_co exiting", rc, msg)
	end
	return rc, msg
    end)
    watches.start_watch(thread)
end


---
-- Prepare parameters for a request
--
local function _prepare_request_args(arg)
    local rc, msg

    arg.headers = arg.headers or {}
    arg.headers.host = arg.headers.host or arg.host
    arg.method = arg.method or "GET"
    arg.sink = arg.sink or sink_memory

    -- build a post request
    if arg.post then
	arg.method = "POST"
	arg.body = build_post_request(arg.post)
	arg.post = nil
	arg.headers.accept = 'text/plain,text/html,text/xml'
	arg.headers['content-type'] = 'application/x-www-form-urlencoded'
    end

    -- build a get request
    if arg.get then
	arg.method = "GET"
	arg.uri = arg.uri .. "?" .. build_post_request(arg.get)
	arg.get = nil
    end

    -- if a body is provided, send it using the buffer source.
    if arg.body then
	arg.source = socket_co.source_buffer
	arg.source_data = arg.body
	-- Without content-length, a request would fail.  How would the server
	-- know when the request body ends?
	-- arg.headers['content-Length'] = string.len(arg.body)
	arg.body = nil
    end

    -- open the source, if available
    if arg.source then
	rc, msg = arg:source("open")
	if not rc then return rc, msg end

	if not arg.headers['content-length'] then
	    arg.headers['content-length'] = arg:source("get-length")
	end
    end

    -- add all known cookies
    if arg.cookies then
	for k, v in base.pairs(arg.cookies) do
	    if arg.headers.cookie then
		arg.headers.cookie = arg.headers.cookie .. "; " .. k .. "=" .. v
	    else
		arg.headers.cookie = k .. "=" .. v
	    end
	end
    end

    -- Try to keep the connection alive.  HTTP/1.1 doesn't need this, but it
    -- doesn't hurt either.
    arg.headers.connection = 'Keep-Alive'

    if arg.keep_alive then
	arg.channel = arg.keep_alive.channel
	arg.channel_socket = arg.keep_alive.channel_socket
	arg.keep_alive.do_not_shutdown = true
    end

    -- add the progress function
    arg._progress = _progress_function

    return "ok"

end

function _progress_function(arg, what, count, total_size)
    if arg.callback then arg:callback("progress", what, count, total_size) end
end

---
-- Perform a complete HTTP request.  arg specifies all the parameters.
--
-- @param arg   A table with all the named parameters as given below.
--
-- @usage
--  host	the host to contact
--  uri		the URI to use in the GET/... request
--
--  headers	(optional) a table with key, value pairs for extra headers
--  method	(optional) the method
--  source	(optional) a source for the body of the request
--  sink	(optional) a sink to store the body of the result
--
function request(arg)
    local rc, msg, ioc, ioc_sock

    rc, msg = _prepare_request_args(arg)
    if not rc then return rc, msg end

    arg:_progress("send", 0, -1)

    -- connect to the server
    if not arg.channel then
	rc, msg = socket_co.connect(arg.host, arg.port or PORT, false)
	if not rc then return rc, msg end
	arg.channel = rc
	arg.channel_socket = msg
    end

    rc, msg = request_2(arg)

    -- clean up
    watches.remove_watch(nil, arg.channel, nil)

    if not arg.response_headers
	or arg.response_headers['connection'] == 'close' then
	_shutdown_channel(arg)
    else
	print "KEEP ALIVE Channel #1"
    end

    if arg.callback then arg:callback('done') end

    if not arg.do_not_shutdown and arg.channel then
	_shutdown_channel(arg)
    end

    return rc, msg
end


---
-- The channel is no longer needed, close it.
--
function _shutdown_channel(arg)
    arg.channel:shutdown(false, nil)
    -- print("- remove widget from gtk.widgets:", arg.channel)
    -- gtk.widgets[arg.channel] = nil
    arg.channel = nil
    arg.channel_socket:close()
    arg.channel_socket = nil
end

---
-- The connection has been established, now send the request and read the
-- response.
--
function request_2(arg)
    local rc, msg, buf, headers, body

    -- send request
    buf = string.format("%s %s HTTP/1.1\r\n", arg.method, arg.uri)
    rc, msg = socket_co.write_chars(arg.channel, buf, false)
    if not rc then return rc, msg end

    -- send headers
    rc, msg = send_headers(arg.channel, arg.headers)
    if not rc then return rc, msg end

    -- send body
    if arg.source then
	rc, msg = send_body(arg.channel, arg)
	if not rc then return rc, msg end
    end

    -- flush not required because the socket is unbuffered anyway.

    -- retrieve response headers
    local code = 100
    while code == 100 do
	rc, msg = receive_status_line(arg.channel)
	if not rc then return rc, msg end
	code = rc

	rc, msg = receive_headers(arg.channel, headers)
	if not rc then return rc, msg end
	headers = rc
    end

    arg.response_headers = headers

    if arg.callback then arg:callback("headers") end

    -- retrieve body
    if expect_body(arg, code) then
	rc, msg = receive_body(arg)
	if not rc then return rc, msg end
	arg:sink(nil)
    end

    -- input buffer should now be empty.

    return "http ok"
end

---
-- Send all the headers for this request in an unspecified order.
--
-- The first letter of the header names is converted to uppercase, this is
-- more beautiful.
--
function send_headers(ioc, ar)
    local hdr = ""

    if ar then
	for k, v in base.pairs(ar) do
	    k = string.gsub(k, "^(%w)", function(c) return string.upper(c) end)
	    hdr = hdr .. k .. ": " .. v .. "\r\n"
	end
    end

    hdr = hdr .. "\r\n"
    return socket_co.write_chars(ioc, hdr, false)
end

---
-- Send the request body.
--
function send_body(ioc, arg)
    local rc, msg, buf, count, total_size

    count = 0
    total_size = arg:source("get-length")
    while true do
	buf = arg:source("read", 2048)
	if not buf then break end
	rc, msg = socket_co.write_chars(ioc, buf, false)
	if not rc then return rc, msg end
	count = count + string.len(buf)
	arg:_progress("send", count, total_size)
    end

    return "ok"
end

---
-- Read and parse an HTTP response
--
function receive_status_line(ioc)
    local rc, msg, _, code

    rc, msg = socket_co.receive_line(ioc)
    if not rc then return rc, msg end

    _, _, code = string.find(rc, "HTTP/%d*%.%d* (%d%d%d)")
    code = base.tonumber(code)
    if code then return code end
    return nil, "invalid response"
end

---
-- Read the response headers.
--
function receive_headers(ioc, headers)
    local rc, msg, name, value, _
    headers = headers or {}

    while true do
	rc, msg = socket_co.receive_line(ioc)
	if not rc then return rc, msg end

	-- detect end of headers: an empty line.
	if rc == "" then break end

	-- continuation?
	if name and string.find(rc, "^%s") then
	    headers[name] = headers[name] .. rc
	else
	    _, _, name, value = string.find(rc, "^(.-):%s*(.*)")
	    if not (name and value) then
		return nil, "malformed response headers"
	    end
	    name = string.lower(name)
	    if headers[name] then
		headers[name] = headers[name] .. ", " .. value
	    else
		headers[name] = value
	    end
	end
    end

    return headers
end

---
-- Determine whether we should expect a body
--
function expect_body(arg, code)
    return not (arg.method == "HEAD"
	or code == 204 or code == 304 or (code >= 100 and code < 200))
end


--
-- Read data until the server closes the connection.
--
local function decode_identity(arg)
    local length = 0

    while true do
	local rc, msg = socket_co.read_chars(arg.channel, 2048)
	if not rc and msg == "connection lost" then break; end
	if not rc then return rc, msg end
	arg:sink(rc)
	length = length + #rc
	arg:_progress("receive", length, -1)
    end

    return 1
end

--
-- A length for the response is given; read up to this number of bytes.
--
-- @param arg     Request structure
-- @param length  bytes to read
--
local function decode_length(arg, length)
    local count, rc, msg = 0

    while count < length do
	rc, msg = socket_co.read_chars(arg.channel, length - count)
	if not rc then return rc, msg end
	arg:sink(rc)
	count = count + #rc
	arg:_progress("receive", count, length)
    end

    return 1
end

--
-- Read one chunk at a time.
--
-- @param arg	   The request arg structure
-- @param param    { length, count }
-- @return         1 on OK, (nil, msg) on error, (nil, nil) on end of input
--
local function decode_chunked(arg, param)
    local rc, msg, size, chunk
    local ioc = arg.channel

    -- get chunk size
    rc, msg = socket_co.receive_line(ioc)
    if not rc then return rc, msg end

    size = base.tonumber(string.gsub(rc, ";.*", ""), 16)
    if not size then return nil, "invalid chunk size: " .. tostring(rc) end

    chunk = ""

    -- end of chunks.
    if size <= 0 then
	-- "trailing headers"
	rc, msg = receive_headers(ioc, arg.response_headers)
	if not rc then return rc, msg end

	-- end of input.
	arg:_progress("receive", param.count, param.count)
	return nil, nil
    end

    -- Read a complete chunk.  The read function returns up to the given size,
    -- so repeated calls may be required.
    while string.len(chunk) < size do
	rc, msg = socket_co.read_chars(ioc, size - string.len(chunk))
	if not rc then return rc, msg end
	chunk = chunk .. rc
	param.count = param.count + #rc
	arg:_progress("receive", param.count, param.total_size)
    end
    
    -- skip trailing CR/LF
    rc, msg = socket_co.receive_line(ioc)
    if not rc then return rc, msg end

    arg:sink(chunk)
    return 1
end

---
-- Read the whole body, using the appropriate decode function.
--
-- @param arg     Request structure
-- @return        1 or (nil, msg)
--
function receive_body(arg)
    local rc, msg, t, length

    -- determine the encoding.
    t = arg.response_headers['transfer-encoding']
    length = base.tonumber(arg.response_headers['content-length'])
    
    if (t and t ~= 'identity') then
	local param = { total_size=length, count=0 }
	while true do
	    rc, msg = decode_chunked(arg, param)
	    if not rc then break end
	end
	-- nil, nil is a normal end; nil, "message" is an error.
	if msg then return rc, msg end
	return 1
    elseif length then
	return decode_length(arg, length)
    end

    -- default
    return decode_identity(arg)
end

---
-- Given the response of a request, try to identify cookies. 
--
-- @param arg    Request arguments
-- @param jar    A table what will be filled with cookies from the response
--               headers in arg. key=name, value=value of cookie.
-- @return       nil
--
function get_cookies(arg, jar)
    if not arg.response_headers then return end
    local cookie, _, name, value = arg.response_headers['set-cookie']
    if not cookie then return end
    _, _, name, value = string.find(cookie, "([^=]+)=([^;]+)")
    if name and value then
	-- print("got a cookie", name)
	jar[name] = value
    end
end

base.strict_lock()

