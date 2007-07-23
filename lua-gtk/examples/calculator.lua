#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Simple calculator demo.  Evaluates input as Lua expression.
-- by Wolfgang Oertl 2007.  The buttons are quite useless as you'd type
-- the numbers anyway, but this should show off some features, so...
--
-- Possible improvements: allow assignments to variables.
--

require "gtk"

local CALC = {}
CALC.__index = CALC

--
-- Calculate the expression by evaluating it as Lua expression.
-- Returns the result (a value as string) or an error message.
--
function calculate(s)
    local chunk, msg = loadstring("return " .. s, s)
    if not chunk then
	return string.match(msg, ":%d: (.*)")
    end

    -- The global environment of the user defined function is set to "math", so
    -- all functions of the math library (e.g. abs, asin, ceil, deg, exp,
    -- floor, log, max, min, pi, pow, random, sin, sqrt) are available, but
    -- nothing else: sandboxing!
    setfenv(chunk, math)
    local rc, result = pcall(chunk)
    if not rc then return result end

    result = tostring(result)
    return string.gsub(result, ",", ".")
end


--
-- A button has been pressed
--
function CALC:btn_click(c, op)
    local s = c.entry:get_text()
    local pos = -100

    if op == '=' then
	if s ~= "" then s = calculate(s) end
	pos = -1
    elseif op == 'AC' then
	s = ""
    elseif op == 'EXP' then
	s = s .. "^"
    elseif op == 'Ans' then
	s = s .. "$ans"		-- not working
    elseif op == 'DEL' then
	s = s:sub(1, s:len() - 1)
    else
	s = s .. op
    end

    c.entry:set_text(s)
    if pos ~= -100 then c.entry:set_position(pos) end
end


function my_insert_text(entry, txt, len, posptr, userdata)
    print("insert text", entry, txt, len, posptr, userdata)
end

--
-- Create a CALC object with a stack and the window.  Add buttons.
--
function CALC.new()

    local tbl
    local vbox, hbox, btn

    local c = { stack={} }
    setmetatable(c, CALC)

    c.win = gtk.window_new(0)
    c.win:connect('destroy', function() gtk.main_quit() end)
    c.win:set_title('Calculator')

    tbl = gtk.table_new(5, 5, true)	-- rows, cols, homogenous
    c.win:add(tbl)

    -- entry field
    c.entry = gtk.entry_new()
    c.entry:set_alignment(0.9)
    c.entry:set_activates_default(true)
    -- c.entry:connect('insert-text', my_insert_text)
    tbl:attach_defaults(c.entry, 0, 5, 0, 1)

    -- buttons
    local buttons = { '7', '8', '9', 'DEL', 'AC',
	'4', '5', '6', '*', '/',
	'1', '2', '3', '+', '-',
	0, '.', 'EXP', 'Ans', '=' }

    local row = 0
    local col = 0
    for nr, lbl in pairs(buttons) do
	if math.mod(nr, 5) == 1 then
	    row = row + 1
	    col = 0
	end

	btn = gtk.button_new_with_label(lbl)
	tbl:attach_defaults(btn, col, col + 1, row, row + 1)
	btn:connect('clicked', CALC.btn_click, c, lbl)
	if lbl == '=' then
	    btn.flags = btn.flags + gtk.GTK_CAN_DEFAULT
	    btn:grab_default()
	end
	col = col + 1
    end


    c.win:show_all()
    return c
end

gtk.init(nil, nil)
local calc = CALC.new()
gtk.main()


