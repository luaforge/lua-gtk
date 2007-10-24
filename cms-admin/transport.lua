#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Handle the communication with the server module.
-- Copyright (C) 2007 Wolfgang Oertl
--


--
-- Start a transfer in a new coroutine.
--
-- label = what to display; must be valid utf8, whereas the filename may not be
-- t = type - can be "buffer" or "file"
-- data = buffer contents as string, or a filename
--
function ftp_upload(label, t, data, dest)
    -- initialize the progress meter
    local progress = mainwin.progress
    progress:set_text("FTP Upload of " .. label)
    progress:set_fraction(0)
    upload_running = true
    gtk.ftp_co.put_co{
	source = t,
	source_data = data,
	host = server_ftp_host,
	user = server_ftp_user,
	password = server_ftp_password,
	path = dest,
	callback = ftp_upload_callback}
end

--
-- The FTP routine calls this function when the transfer advances, or when
-- it completes.  It can return FALSE to abort the transfer.
--
function ftp_upload_callback(arg, ev, data)
    local progress = mainwin.progress

    if not upload_running then
	progress:set_text("Upload aborted.")
	return false
    end

    if ev == 'progress' then
	print("* set fraction", data)
	progress:set_fraction(data)
    elseif ev == 'done' then
	progress:set_text("Upload completed.")
	progress:set_fraction(1)
	upload_running = false
    elseif ev == 'failure' then
	progress:set_text(data)
	upload_running = false
    end
end


--
-- Upload a file to the server.
--
-- fname	file name
-- label	what to display; the UTF8 version of fname, maybe just basename
-- method	"buffer" or "file"
-- data		for the buffer method, the file contents.  for file, unused
-- callback	function to call upon completion.
--
-- NOTE: basically, this would support uploading multiple files at once,
-- but isn't fully implemented.  The uploaded files have to be named
-- "file" + the request number.
--
function http_upload(fname, label, method, data, callback)
    local progress = mainwin.progress
    progress:set_text("HTTP Upload of " .. label)
    progress:set_fraction(0)
    upload_running = true

    local basename = string.match(fname, "[^/]*$")
    if not basename then
	print("* Can't get basename of " .. tostring(fname))
	return
    end

    -- build the data required for wrapping the file data
    -- XXX only image/jpeg is supported as MIME type.
    local boundary = "boundary8059485039485"
    local part1 = "--" .. boundary .. "\r\n"
	.. "Content-Disposition: form-data; "
	.. "name=\"" .. "edit[file1]"  .. "\"; "
	.. "filename=\"" .. basename .. "\"\r\n"
	.. "Content-type: image/jpeg\r\n"
	.. "Content-length: " .. string.len(data) .. "\r\n"
	.. "\r\n"
    local part2 = "\r\n--" .. boundary .. "--\r\n"

    print "Starting upload as a coroutine."
    gtk.http_co.request_co{
	source = gtk.socket_co.source_chain,
	source_parts = {
	    { source = gtk.socket_co.source_buffer, source_data = part1 },
	    { source = gtk.socket_co.source_buffer, source_data = data },
	    { source = gtk.socket_co.source_buffer, source_data = part2 },
	},
	host = cfg.server_http_host,
	uri = cfg.server_http_uri .."?r[1][cmd]=upload",
	method = "POST",
	cookies = cookie_jar,
	callback = http_upload_callback,
	sink = server_request_sink,
	_response_state = { status = "", buf = "", bufpos=1 },
	headers = {
	    ["Content-type"] = "multipart/form-data; boundary=" .. boundary,
	},
	response = {
	    { callback = callback, _uploaded_file = label },
	},
    }
    print "Upload is running."
end

--
-- Callback used for HTTP upload.
--
function http_upload_callback(req, ev, data1, data2, data3)
    local progress = mainwin.progress
    local rc, msg

    if ev == 'done' then
	print "HTTP Upload is done."
	progress:set_text("Done.")
	progress:set_fraction(1)
    end

    -- only interested in sending; retrieving the result should be
    -- minimal.
    if ev == 'progress' and data1 == 'send' then
	-- data1="send" or "retrieve", data2=count, data3=total
	print("fraction is", data2/data3)
	progress:set_fraction(data2/data3)
    end
end


--
-- Send a standard server request, which will also be handled in a
-- standard way.
--
-- get_arg must be an array of individual requests, see below.  additional
-- fields:
--	progress	a function to be called on each received packet
--
function server_request(get_arg)
    local arg = {
	host = cfg.server_http_host,
	uri = cfg.server_http_uri,
	cookies = cookie_jar,
	callback = server_request_callback,
	sink = server_request_sink,
	_response_state = { status = "", buf = "", bufpos=1 },
    }
    arg.get = server_request_parse_args(arg, get_arg)
    gtk.http_co.request_co(arg)
end

--
-- Convert the request to PHP variables
--
-- get_arg must be an array of individual requests, each being an array
-- with these fields:
--
--  callback	response handler
--  response	array with values to be sent to the response handler, too
--  any other	will be sent to the server
--
function server_request_parse_args(arg, get_arg)
    local get = {}

    arg.response = arg.response or {}
    arg.progress = get_arg.progress

    for i, rq in ipairs(get_arg) do
	arg.response[i] = arg.response[i] or {}
	arg.response[i].vars = {}
	for name, val in pairs(rq) do
	    if name == 'callback' then
		arg.response[i].callback = val
	    elseif name == 'response' then
		for k, v in pairs(val) do
		    arg.response[i][k] = v
		end
	    else
		get[string.format("r[%d][%s]", i, name)] = val
	    end
	end
    end

    -- gtk.glade.print_r(get)
    return get
end

--
-- arg:
--   response[i]
--	data
--	arbitrary variables sent by server
--	info
--	err
--
--   _response_state
--      status	    current status - may be nothing, LUA or DATA
--      req_nr	    current request nr
--      remaining   how many more bytes are wanted for data
--      data_name   name parameter of LUA/DATA cmd
--      data	    output buffer
--	buf	    input buffer
--	bufpos	    input position
--

--
-- Some more response data is available from the server.  Parse and act
-- upon it immediately.
--
function server_request_sink(arg, chunk)
    local st = arg._response_state
    local buf, line

    -- after the end of input, this function is called once with a nil chunk.
    if not chunk then
	local st = #st.buf - st.bufpos + 1
    	if st ~= 0 then
	    print("* WARNING: server_request_sink: remaining data", st)
	end

	-- check that all requests have their complete response.
	for i, resp in ipairs(arg.response) do
	    if not (resp.ok or resp.err) then
		resp.err = 'Unfinished response.\n'
		server_request_call_callback(resp)
	    end
	end

	return
    end

    -- Append the new data, throwing out the already read part of the input
    -- buffer.
    st.buf = string.sub(st.buf, st.bufpos) .. chunk
    st.bufpos = 1

    -- Parse the buffer as far as possible.
    while true do

	-- If currently receiving binary or Lua data, copy it to the
	-- destination
	if st.status == 'DATA' or st.status == 'LUA' then
	    -- print("* data/lua", st.bufpos, st.remaining)
	    buf = string.sub(st.buf, st.bufpos, st.bufpos+st.remaining-1)
	    st.data = st.data .. buf
	    st.bufpos = st.bufpos + #buf

	    st.remaining = st.remaining - #buf
	    if st.remaining ~= 0 then
		-- print("* need more data", st.bufpos, #st.buf)
		assert(st.bufpos == #st.buf+1)
		return 
	    end

	    -- print("* end of data. remaining input", #st.buf - st.bufpos + 1)

	    if st.status == 'LUA' then
		server_request_evaluate(arg, st.req_nr)
	    else
		arg.response[st.req_nr].data = st.data
		arg.response[st.req_nr].data_name = st.data_name
	    end

	    -- clear the fields used during block reading.
	    st.status = ''
	    st.req_nr = 0
	    st.data = ""
	end

	line = server_request_line(arg)
	if not line then break end
	-- print("* response line >>" .. line .. "<<")
	server_request_handle_line(arg, line)
    end

end

--
-- Return the next available line
--
function server_request_line(arg)
    local st, start, pos, line = arg._response_state
    start = st.bufpos
    pos = string.find(st.buf, "\n", start, true)
    if not pos then return nil end
    st.bufpos = pos + 1
    if string.sub(st.buf, pos-1, pos-1) == "\r" then pos=pos-1 end
    return string.sub(st.buf, start, pos-1)
end

--
-- Evaluate the data returned by the server.  It must have one or more header
-- lines, each starting with OK, ERR or INFO.  After an empty line follows,
-- if applicable, the data.  This data must be a valid Lua expression, most
-- likely a table definition.
--
-- On success, the evaluated expression is returned, else NIL plus an error
-- message.
--
function server_request_handle_line(arg, line)
    local req_nr, cmd, data = string.match(line, "^(%d+) (%u+) ?(.*)$")

    if not req_nr then
	print("* invalid response line >>" .. line .. "<<")
	return
    end
    req_nr = tonumber(req_nr)

    -- print("* found a response", req_nr, cmd)

    local resp = arg.response[req_nr]
    if not resp then
	-- The request nr. 0 is used by the backend to transport messages
	-- from the CMS.
	if req_nr == 0 then
	    print("INFO", data)
	else
	    print("* response for invalid request nr. " .. tostring(req_nr)
		.. ": >>" .. line .. "<<")
	end
	return
    end

    -- these two commands can end a response
    if cmd == 'OK' then
	resp.ok = data or true
	server_request_call_callback(resp)
	return
    end

    if cmd == 'ERR' then
	resp.err = data or true
	server_request_call_callback(resp)
	return
    end

    -- No more data is accepted for responses that have already been
    -- completed.  The callback has already been run, so the data would
    -- go nowhere.
    if resp.ok or resp.err then
	print("* invalid data for request after OK or ERR response:", req_nr)
	print("  line: >>" .. line .. "<<")
	return
    end

    if cmd == 'INFO' then
	resp.info = (resp.info or "") .. data .. "\n"
	return
    end

    if cmd == 'VAR' then
	local name, val = string.match(data, " *(%w+) (.*)")
	if name and val then
	    if string.match(val, "^%d+$") then val = tonumber(val) end
	    resp.vars[name] = val
	end
	return
    end

    if cmd == 'LUA' or cmd == 'DATA' then
	local len, name = string.match(data, "^(%d+) (.*)$")
	if not (len and name) then
	    print("* invalid lua/data command parameters >>" .. data .. "<<")
	    return
	end
	local st = arg._response_state
	st.status = cmd
	st.req_nr = req_nr
	st.remaining = len
	st.data_name = name
	st.data = ""
	return
    end

    print("* unparseable response line", line)
end

function server_request_call_callback(resp)
    if resp.callback then resp:callback() end
end

--
-- The Lua data for the given request has been completely read.  Now
-- evaluate it.
--
function server_request_evaluate(arg, req_nr)
    local rc, msg
    local st = arg._response_state
    -- print("* evaluate lua into", st.data_name)

    rc, msg = loadstring("return " .. st.data)
    if not rc then return rc, "Syntax error in data: " .. tostring(msg) end

    -- sandbox, then execute
    setfenv(rc, {})
    rc, msg = pcall(rc)
    if not rc then return rc, "Failed to evaluate data: " .. tostring(msg) end

    arg.response[req_nr][st.data_name] = msg
end

-- evaluate the response headers early on.
function server_request_callback(arg, ev, data1, data2, data3)
    if ev == 'headers' then
	gtk.http_co.get_cookies(arg, cookie_jar)
    elseif ev == 'progress' and arg.progress then
	-- data1="send" or "receive", data1=bytes transferred so far,
	-- data2=total length or -1 if unknown
	arg:progress(data1, data2, data3)
    end
end

