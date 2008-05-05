-- vim:sw=4:sts=4:encoding=utf8
-- Interface module for Accuweather.com as data source
-- kindly provided free of charge.
--
-- Exported symbols: accuweather with the following methods:
--
--  search_location
--  get_data
--

local M = {}

require "gtk"

local host = "oertl.accu-weather.com"
local url_base = "/widget/oertl/"

local function search_callback(arg, ev, data1, data2, data3)
    if ev == 'done' then
	print "Got complete result for location search:"
	print(arg.sink_data)
    end
end

function M:search_location(s)
    gtk.http_co.request_co{
	host = host,
	uri = url_base .. "city-find.asp?location=" .. s,
	callback = search_callback
    }
end

local function print_r(t, prefix)
    for k, v in pairs(t) do
	if type(v) == 'table' then
	    print(prefix .. k .. ">>")
	    print_r(v, prefix .. '  ')
	else
	    print(prefix .. k .. "=" .. tostring(v))
	end
    end
end

local function _new_lbl(tbl, top, left, right, s)
    local lbl = gtk.label_new(s)
    lbl:set_use_markup(true)
    tbl:attach_defaults(lbl, left, right, top, top + 1)
    return lbl
end

local function present_weather(xml)

    widgets.logo:set_from_file("accuweather.png")

    local cw = widgets.currweather
    local buf = cw:get_buffer()
    local l = xml.adc_database['local']
    local s = string.format("%s, %s at %s\n\n", l.city, l.state, l.time)
    local u = xml.adc_database.units

    l = xml.adc_database.currentconditions
    s = s .. "Temp: " .. l.temperature .. " " .. u.temp .. "\n"
    s = s .. "Description: " .. l.weathertext .. "\n"
    s = s .. "Humidity: " .. l.humidity .. "\n"

    buf:set_text(s, #s)

    -- remove previous forecast table, if it exists.
    local tmp = widgets.forecast:get_child()
    if tmp then tmp:destroy() end

    local f = xml.adc_database.forecast
    if f then
	local cnt = #f.day
	local tbl = gtk.table_new(3, cnt * 3, false)
	for i, day in ipairs(f.day) do
	    local col = i * 3
	    _new_lbl(tbl, 0, col, col+2, "<span weight=\"bold\">"
		.. day.daycode .. "</span>")

	    -- precipitation
	    _new_lbl(tbl, 1, col, col + 1, day.daytime.rainamount)
	    _new_lbl(tbl, 1, col + 1, col + 2, day.nighttime.rainamount)

	    -- temperature
	    _new_lbl(tbl, 2, col, col + 1, "<span foreground=\"#ff0000\">"
		.. day.daytime.hightemperature .. "</span> " .. u.temp)
	    _new_lbl(tbl, 2, col + 1, col + 2, "<span foreground=\"#0000ff\">"
		.. day.nighttime.lowtemperature.. "</span> " .. u.temp)

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

local function fetch_callback(arg, ev, data1, data2, data3)
    if ev == 'done' then
	print "Got the weather data:"
	local data = parse_weather_info(arg.sink_data)
	present_weather(data)
    end
end

function M:get_data(loc)
    gtk.http_co.request_co{
	host = host,
	uri = url_base .. "weather-data.asp?location=" .. loc
	    .. "&metric=1",
	callback = fetch_callback
    }
end

return M

