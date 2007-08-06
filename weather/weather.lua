#! /usr/bin/lua
-- vim:sw=4:sts=4
--
-- Demonstration program to download and display weather information from weather.com.
-- by Wolfgang Oertl
--
-- Revisions:
--  2007-08-06	first version: show a few facts about the current weather.
--
-- TODO:
--  - display forecast nicer: as a table
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
    local code = store:get_value(iter, 1)
    get_weather_info(code)
end

function get_weather_info(code)
    gtk.http_co.request_co{
	host = "xoap.weather.com",
	uri = "/weather/local/" .. code .. "?cc=*&unit=m&dayf=" .. forecast_days,
	callback = weather_info_callback,
    }
end

function weather_info_callback(arg, ev, data1, data2, data3)
    -- print("CALLBACK", arg, ev, data1, data2, data3)
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

--
-- The weather response has been parsed into a nice tree.  Extract the interesting
-- fields and fill the GUI.
--
function present_weather(xml)
    local s
    local cw = mainwin.currweather
    local buf = cw:get_buffer()

    s = xml.weather.loc.dnam .. " at " .. xml.weather.cc.lsup .. "\n"
    s = s .. "Temp: " .. xml.weather.cc.tmp .. " " .. xml.weather.head.ut.."\n"
    s = s .. "Description: " .. xml.weather.cc.t .. "\n"
    s = s .. "Humidity: " .. xml.weather.cc.hmid .. "%\n"

    buf:set_text(s, string.len(s))

    if xml.weather.dayf then
	s = ""
	for i, day in ipairs(xml.weather.dayf.day) do
	    s = s .. day.t .. " " .. day.dt .. ": "
		.. day.low .. " to " .. day.hi .. " "
		.. xml.weather.head.ut .. "\n"
	end
	mainwin.forecast:get_buffer():set_text(s, #s)
    end
end

function main()

    gtk.init(nil, nil)
    tree = gtk.glade.read("weather.glade")
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

main()
tree = nil
mainwin = nil
collectgarbage("collect")
print(collectgarbage("count"), "kB")

