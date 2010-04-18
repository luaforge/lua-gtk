#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Extract all messages from the specified module's source files, and upload
-- new and changed messages to the server.
--
-- Arguments: name of the module to process
--
-- This is work in progress.  The "server" is a local installation of a
-- Lua based CMS that I haven't published anywere yet.  It has a module
-- that is a rough but working tool to translate messages via the web.
--

require "lfs"
require "socket.http"

-- configuration
server_url = "http://localhost/nab2/index.lua?q="
cookie = nil
-- end configuration


---
-- Parse a Lua data structure given as string.
-- from nab2/lib/util.lua
--
function deserialize(s)
    assert(type(s) == "string")
    if s == "" then return nil end
    local chunk = assert(loadstring("return " .. s))
    setfenv(chunk, {})
    return assert(chunk())
end




-- metatable for module
MOD = {}
MOD.__index = MOD

function new_module(modname)
    -- messages: key=ID, value={ msg, {loc, ...}}
    -- loc: { filename, linenumber, function }
    local o = { modname=modname, err_cnt=0, messages={}, languages={} }
    setmetatable(o, MOD)
    return o
end

function MOD:err(msg, ...)
    if select('#', ...) > 0 then
	msg = string.format(msg, ...)
    end
    print(string.format("%s(%d): %s", self.curr_fname, self.curr_line_nr, msg))
    self.err_cnt = self.err_cnt + 1
end



---
-- Read one C source file to extract all messages.
--
function MOD:process_source()
    self.curr_id = nil
    self.curr_fnname = nil
    for line in io.lines(self.curr_fname) do
	self.curr_line_nr = self.curr_line_nr + 1
	self:process_source_line(line)
    end
end

local macros = {
    "(LG_ERROR)%((.*)",		-- args: id, fmt, ...
    "(LG_ARGERROR)%((.*)",	-- args: nr, id, fmt, ...
    "(LG_MESSAGE)%((.*)",	-- args: id, msg
}


---
-- Read one line of a C source file to find usages of messages.
--
function MOD:process_source_line(line)
    local s, macro, args

    if line == "" then return end

    -- looking for more continuation lines
    if self.curr_line then
	-- remove trailing " (if possible)
	s = string.gsub(self.curr_line, '"%s*$', '')
	if s ~= self.curr_line then
	    line = string.gsub(line, '^%s*"', '')    -- remove leading "
	end
	self.curr_line = s .. line
	self:try_commit_message()
	return
    end

    -- look for new functions
    s = string.match(line, '^%w[%w ]-([%w_]+)%(')
    if s then
	self.curr_fnname = s
	return
    end

    -- look for new messages.
    for _, macroname in ipairs(macros) do
	macro, args = string.match(line, macroname)
	if macro then
	    self.curr_macro = macro
	    self.curr_line = args
	    self.curr_macro_line = self.curr_line_nr
	    self:try_commit_message()
	    break
	end
    end
end


---
-- The line buffer self.curr_line might be a complete statement, i.e. end
-- with a semicolon.  In this case, analyze it.
--
function MOD:try_commit_message()
    if string.sub(self.curr_line, -1) ~= ";" then return end

    -- for this macro, discard the leading argument number
    if self.curr_macro == "LG_ARGERROR" then
	self.curr_line = string.match(self.curr_line, '^[^,]+, *(.*)')
    end

    -- the rest is id, "message"
    id, msg = string.match(self.curr_line, '^(%d+),%s*"([^"]+)"')
    if id then
	self:commit_message(id, msg, self.curr_macro_line)
    end

    self.curr_macro = nil
    self.curr_line = nil
    self.curr_macro_line = nil
end


---
-- The current message should be stored.
--
function MOD:commit_message(id, msg, line_nr)

    ar = self.messages[id]
    if ar then
	if ar[1] ~= msg then
	    self:err("Redefinition of message %s %s", self.modname, id)
	    return
	end
    else
	-- new message
	ar = { msg, {} }
	self.messages[id] = ar
    end

    -- add the current location: filename, line, function
    table.insert(ar[2], { self.curr_fname, line_nr, self.curr_fnname })
end


-- fetch a list of existing messages with a hash value of name/
function MOD:get_existing_messages()
    local res = {}
    local body = "op=fetch&module=" .. self.modname
    socket.http.request {
	url = server_url .. "luagnome/upload",
	method = "POST",
	headers = { Cookie=cookie, ["Content-Length"] = #body },
	source = ltn12.source.string(body),
	sink = ltn12.sink.table(res),
    }

    res = table.concat(res)

    print("existing messages", res)

    res = deserialize(res)

    -- XXX evaluate the result
    -- res: array of entries with { msg_id, msg_nr, hashvalue }
    -- hashvalue is supposed to be a md5(message text .. locations)
end

-- Check for new/changed messages and upload them.
function MOD:upload_changes()

    -- XXX for each message, compute the hashvalue.  if it differs or no
    -- old message exists, append to an array to upload.  then serialize
    -- it and upload unless empty.

end


---
-- Make a string with the locations where a message is used.
-- @param msg  An entry from the "messages" array.
-- @return  A string with the locations.
--
function locations(msg)
    local buf = {}
    for _, loc in ipairs(msg[2]) do
	if loc[3] then
	    buf[#buf + 1] = string.format("%s(%s):%s()", loc[1], loc[2], loc[3])
	else
	    buf[#buf + 1] = string.format("%s(%s)", loc[1], loc[2])
	end
    end
    return table.concat(buf, ", ")
end

function MOD:process()
    local path, lang
    
    path = "src/" .. self.modname

    if lfs.attributes(path, "mode") ~= "directory" then
	print("Invalid module " .. self.modname)
	return 2
    end

    for fname in lfs.dir(path) do
	self.curr_fname = path .. "/" .. fname
	self.curr_line_nr = 0

	if string.match(fname, "%.c$") then
	    self:process_source()
	end
    end

    self:get_existing_messages()
    self:upload_changes()

end

-- Connect to the server, i.e. login
function server_login()
    local body, status, header, status2 = socket.http.request(
	server_url .. "login",
	"user=admin&pass=passme\n")
    if tostring(status) == "200" then
	for k,v in pairs(header) do
	    if k == "set-cookie" then
		cookie = string.match(v, "^[^;]+")
		print("COOKIE", cookie)
	    end
	end
    end

    if not cookie then
	print("Failed to login to server.")
	os.exit(1)
    end
end

-- Disconnect, i.e. logout
function server_logout()
    local t = {}
    local body, status, header, status2 = socket.http.request {
	url = server_url .. "logout",
	headers = { Cookie=cookie },
	sink = ltn12.sink.table(t)
    }
    print("LOGOUT", body, status, header, status2, table.concat(t))
end

function main()
    local modname, mod, rc

    modname = arg[1]
    if not modname then
	print "Required argument: a module's name"
	return 1
    end

    server_login()
    if true then
	mod = new_module(modname)
	rc = mod:process()
    end
    server_logout()
end

os.exit(main())

