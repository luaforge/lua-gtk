#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Extract the (error) messages from each module's messages_LANG.html file, and
-- find all locations of their usage in the source files to produce
-- documentation HTML files.
--
-- Arguments: name of the module to process
--

require "lfs"

-- metatable for module
MOD = {}
MOD.__index = MOD

function new_module(modname)
    -- messages: key=ID, value={ msg, {loc, ...}}
    -- loc: { filename, linenumber, function }
    -- descriptions: key=ID, value=text
    local o = { modname=modname, err_cnt=0, descriptions={}, messages={},
	languages={} }
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


---
-- Read an HTML file and extract the error descriptions
-- @param lang  Language code of the file to be processed
--
function MOD:process_messages(lang)
    local id, ar, buf, curr_id

    curr_id = nil

    for line in io.lines(self.curr_fname) do
	id = string.match(line, "^MSG (%w+)$")

	-- start of next message block
	if id then
	    if buf then
		ar[lang] = table.concat(buf, "\n")
	    end
	    ar = self.descriptions[id] or {}
	    self.descriptions[id] = ar
	    if ar[lang] then
		self:err("Redefinition of message %s %s", self.modname, id)
	    end
	    curr_id = id
	    buf = {}

	-- another line when a message block is active
	elseif buf then
	    buf[#buf + 1] = line
	end

    end

    -- save the last block, too
    if buf then
	ar[lang] = table.concat(buf, "\n")
    end
end

---
-- Verify that all descriptions are used, and that all required descriptions
-- are present.
--
function MOD:check_descriptions()

    -- are all descriptions used somewhere?
    for id, ar in pairs(self.descriptions) do
	if not self.messages[id] then
	    print(string.format("Description %s.%s is not used",
		self.modname, id))
	end
    end

    -- are all usages provided with descriptions?
    for id, ar in pairs(self.messages) do
	if not self.descriptions[id] then
	    print(string.format("Missing description for %s.%s used at %s",
		self.modname, id, locations(ar)))
	end
    end
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

---
-- Write an HTML file for one language.
--
function MOD:output_html(lang)
    local f, fname, ids, msg

    fname = string.format("build/doc/%s/messages-%s.html.in",
	lang, self.modname)
    print("Writing " .. fname)
    f = io.open(fname, "w")

    -- sort all the descriptions
    ids = {}
    for id, ar in pairs(self.descriptions) do
	if ar[lang] and self.messages[id] then
	    ids[#ids + 1] = id
	end
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)

    -- write all descriptions in order
    for _, id in ipairs(ids) do
	-- print("Writing message", id)
	msg = self.messages[id]

	f:write(string.format('<h3><a name="msg%s">[LG %s.%s] %s</a></h3>\n',
	    id, self.modname, id, msg[1]))
	f:write(self.descriptions[id][lang])

	f:write(string.format("<p><i>%s</i></p>\n\n", locations(msg)))

    end

    f:close()
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
	    -- print("Reading " .. self.curr_fname)
	    self:process_source()
	else
	    lang = string.match(fname, "^messages%-(.*)%.html")
	    if lang then
		-- print("Reading " .. self.curr_fname)
		self.languages[#self.languages + 1] = lang
		self:process_messages(lang)
	    end
	end
    end

    self:check_descriptions()

    for _, lang in pairs(self.languages) do
	self:output_html(lang)
    end
end

function main()
    local modname, mod

    modname = arg[1]
    if not modname then
	print "Required argument: a module's name"
	return 1
    end

    mod = new_module(modname)
    return mod:process()
end

os.exit(main())

