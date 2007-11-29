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
require "gtk.http_co"
require "lxp"
require "gtk.strict"

gtk.strict.init()

forecast_days = 5
gladefile = string.gsub(arg[0], ".lua", ".ui")

widgets = {}

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

-- global used while parsing the XML data
stack = nil

callbacks = {
    StartElement = function(parser, name, el)
	local top, key = unpack(stack[#stack])
	top[key] = top[key] or {}
	local ar = top[key]

	-- item already exists.  convert into an array if not already so,
	-- then write into it.
	if ar[name] then
	    if type(ar[name]) ~= 'table' or not ar[name].__ar then
		ar[name] = { __ar=true, ar[name] }
	    end
	    ar = ar[name]
	    name = #ar + 1
	end

	table.insert(stack, { ar, name })

	-- treat items in EL as subelements
	for i, key in ipairs(el) do
	    callbacks.StartElement(parser, key, {})
	    callbacks.CharacterData(parser, el[key])
	    callbacks.EndElement(parser, key)
	end
    end,

    EndElement = function(parser, name)
	table.remove(stack)
    end,

    CharacterData = function(parser, data)
	if string.match(data, "^%s*$") then return end
	local ar, key = unpack(stack[#stack])

	if not ar[key] then
	    ar[key] = data
	    return
	else
	    print("IGNORE", key)
	end
    end,

}


--
-- The data retrieved from weather.com is a XML text.  Parse it using
-- an internal function of gtk.glade -- not really the way to go, but
-- works for now.
--
function parse_weather_info(data)
    local tree = {}
    stack = { { tree, "top" } }

    local p = lxp.new(callbacks, "::")
    p:parse(data)
    p:parse()
    p:close()
    p = nil
    stack = nil

    present_weather(tree.top)
end

function dump_it(stack, prefix)
    prefix = prefix or ""
    for k, v in pairs(stack) do
	print(prefix .. tostring(k) .. ": " .. tostring(v)
	    .. ((type(v) == 'table' and v.__ar and " (multivalue array)") or ""))
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
    local s, cnt, tbl
    local cw = widgets.currweather
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
    local tmp = widgets.forecast:get_child()
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
	widgets.forecast:add(tbl)
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

function build_gui()
    local b = gtk.builder_new()
    local rc, err = b:add_from_file(gladefile, nil)
    if err then print(err.message); return end
    b:connect_signals_full(_G)

    -- access relevant widgets
    for _, v in ipairs { "currweather", "forecast", "mainwin", "location" } do
	widgets[v] = b:get_object(v)
    end

    -- setup location selector
    local location = widgets.location
    local store = gtk.list_store_new(2, gtk.G_TYPE_STRING, gtk.G_TYPE_STRING)
    location:set_model(store)

    local r = gtk.cell_renderer_text_new()
    location:pack_start(r, false)
    location:set_attributes(r, 'text', 0, nil)

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

    widgets.mainwin:show()
end

-- MAIN --

gtk.strict.lock()
build_gui()
gtk.main()
widgets = nil
collectgarbage()
collectgarbage()
collectgarbage()
print(collectgarbage("count"), "kB")

