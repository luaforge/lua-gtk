#! /usr/bin/lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- Demonstration program to download and display weather information from
-- weather.com.  Similar to xfce4-weather-plugin.
-- by Wolfgang Oertl
--
-- Revisions:
--  2007-08-06	first version: show a few facts about the current weather.
--  2007-08-10	forecast as table
--
-- TODO:
--  - configure locations
--  - configure metric/imperial units
--  - configure what fields to show/display nicely
--  - use icons; maybe use /usr/share/xfce4/weather/icons/liquid/*.png
--  - debug memory, find leaks (mostly a lua-gtk issue)
--

require "gtk"
require "gtk.glade"
require "gtk.http_co"
require "gtk.strict"

local forecast_days = 5
local gladefile = string.gsub(arg[0], ".lua", ".glade")

-- handler for the mainwin.destroy signal
function on_mainwin_destroy()
    gtk.main_quit()
end

--
-- New entry selected.  Determine the location code, and initiate fetching
-- the weather info.
--
function on_location_changed(box)
    local store = box:get_model()
    local iter = gtk.new "GtkTreeIter"
    box:get_active_iter(iter)
    local code = store:get_value(iter, 1, nil)

    gtk.http_co.request_co{
	host = "xoap.weather.com",
	uri = "/weather/local/" .. tostring(code)
	    .. "?cc=*&unit=m&dayf="..forecast_days,
	callback = weather_info_callback,
    }
end

--
-- Some progress on receiving.  When done, process the data.
--
function weather_info_callback(arg, ev, data1, data2, data3)
    if ev == 'done' then
	parse_weather_info(arg.sink_data)
    end
end

--
-- The data retrieved from weather.com is a XML text.  Parse it using
-- an internal function of gtk.glade -- not really the way to go, but
-- works for now.
--
function parse_weather_info(data)

    -- build a first representation of the XML input.
    local stack, line_nr, ok, msg = {}, 0

    table.insert(stack, {items={}})

    -- split into lines...
    for line in data:gmatch("([^\n]+)") do
	line_nr = line_nr + 1
	-- print("LINE", line_nr, line)
	if line_nr > 2 then
	    ok, msg = pcall(gtk.glade.glade_line, stack, line)
	    if not ok then
		print(string.format("%s(%s): %s", "weather xml", line_nr, msg))
	    end
	end
    end

    -- build a second representation, using the tag names as keys
    xml = transform_xml(stack[1].items)

    if xml.weather.head.ut == "C" then
	xml.weather.head.ut = "°C"
    end

    -- dump_it(xml)

    present_weather(xml)
end

--
-- Convert the preliminary representation of the tree, which is not easy to use,
-- into a nicer representation.  What makes it complicated is the detection of
-- multiple items with the same label - an array is created in this case.
--
function transform_xml(items)
    local tree, el = {}

    for i, item in pairs(items) do

	el = {}
	if tree[item.label] then
	    if not tree[item.label].__ar then
		tree[item.label] = { __ar=true, tree[item.label] }
	    end
	    table.insert(tree[item.label], el)
	else
	    tree[item.label] = el
	end

	for k, v in pairs(item) do
	    if k ~= "items" and k ~= "label" then
		el[k] = v
	    end
	end

	if item.items then
	    local subitems = transform_xml(item.items)
	    for k, v in pairs(subitems) do
		el[k] = v
	    end
	elseif el.text then
	    tree[item.label] = item.text
	end

    end
    return tree
end

function dump_it(stack, prefix)
    prefix = prefix or ""
    for k, v in pairs(stack) do
	print(prefix .. tostring(k) .. ": " .. tostring(v))
	if type(v) == 'table' then
	    dump_it(v, prefix .. "  ")
	end
    end
end

local function _new_lbl(tbl, top, left, right, s)
    local lbl = gtk.label_new(s)
    lbl:set_use_markup(true)
    tbl:attach_defaults(lbl, left, right, top, top + 1)
    return lbl
end


--
-- The weather response has been parsed into a nice tree.  Extract the
-- interesting fields and fill the GUI.
--
function present_weather(xml)
    local s
    local cw = mainwin.currweather
    local buf = cw:get_buffer()
    local dt = parse_date(xml.weather.cc.lsup)
    local mydt = os.date("%Y-%m-%d")

    -- build the current weather information as a string    
    s = xml.weather.loc.dnam .. " at " .. dt.h .. ":" .. dt.mn .. " "
    if dt.dt ~= mydt then s = s .. dt.dt .. " " end
    s = s .. dt.rest .. "\n"
    s = s .. "Temp: " .. xml.weather.cc.tmp .. " " .. xml.weather.head.ut.."\n"
    s = s .. "Description: " .. xml.weather.cc.t .. "\n"
    s = s .. "Humidity: " .. xml.weather.cc.hmid .. "%\n"

    buf:set_text(s, string.len(s))

    -- remove previous forecast table, if it exists.
    local tmp = mainwin.forecast:get_child()
    if tmp then tmp:destroy() end

    -- if a forecast has been retrieved, show it.
    if xml.weather.dayf then
	cnt = #xml.weather.dayf.day
	tbl = gtk.table_new(3, cnt * 3, false)
	for i, day in ipairs(xml.weather.dayf.day) do
	    local col = i * 3

	    -- day label
	    _new_lbl(tbl, 0, col, col + 2, "<span weight=\"bold\">" .. day.t
		.. "</span>")

	    -- precipitation
	    _new_lbl(tbl, 1, col, col + 1, day.part[1].ppcp .. "%")
	    _new_lbl(tbl, 1, col+ 1, col + 2, day.part[2].ppcp .. "%")

	    -- temperature
	    _new_lbl(tbl, 2, col, col + 1, "<span foreground=\"#ff0000\">"
		.. day.hi .. "</span> " .. xml.weather.head.ut)
	    _new_lbl(tbl, 2, col + 1, col + 2, "<span foreground=\"#0000ff\">"
		.. day.low .. "</span> " .. xml.weather.head.ut)

	    -- separator
	    if i < cnt then
		tbl:attach_defaults(gtk.vseparator_new(), col + 2, col + 3,
		    0, 3)
	    end
	end
	mainwin.forecast:add(tbl)
	tbl:show_all()
    end
end

--
-- weather.com returns date/time in this format: mm/dd/yy hh:mm [AM|PM]
-- parse that and return it in a better format.
--
function parse_date(s)
    local m, d, y, h, mn, ampm, rest = s:match(
	"^(%d+)/(%d+)/(%d+) (%d+):(%d+) ([AP]M) (.*)")
    if ampm == "PM" then h = h + 12 end
    if y+0 < 2000 then y = y + 2000 end
    return { dt=string.format("%04d-%02d-%02d", y, m, d), h=h, mn=mn,
	rest=rest }
end

function main()

    gtk.init()
    tree = gtk.glade.read(gladefile)
    mainwin = gtk.glade.create(tree, "mainwin")

    -- setup location selector
    local store = gtk.list_store_new(2, gtk.G_TYPE_STRING, gtk.G_TYPE_STRING)
    mainwin.location:set_model(store)

    local r = gtk.cell_renderer_text_new()
    mainwin.location:pack_start(r, false)
    mainwin.location:set_attributes(r, 'text', 0, nil)

    -- read config file for locations
    local configfunc, msg = loadfile("weather.cfg")
    if not configfunc then
	print("Error loading config file weather.cfg: " .. msg)
	return
    end
    local config = {}
    setfenv(configfunc, config)
    configfunc()

    -- add some locations
    local iter = gtk.new "GtkTreeIter"
    for i, info in pairs(config.locations) do
	store:append(iter)
	store:set(iter, 0, info[1], 1, info[2], -1)
    end

    mainwin.mainwin:show()
    gtk.main()
end

-- MAIN --

main()
tree = nil
mainwin = nil
collectgarbage("collect")
print(collectgarbage("count"), "kB")

