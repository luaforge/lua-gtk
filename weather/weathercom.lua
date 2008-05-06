-- vim:sw=4:sts=4:encoding=utf8
--
-- Interface module for weather.com data.  This was the first data source
-- but since May 2008 their terms are quite strict so this probably doesn't
-- work anymore.  It is deprecated and should not be used anymore.
--

local M = {}

--
-- weather.com returns date/time in this format: mm/dd/yy hh:mm [AM|PM]
-- parse that and return it in a better format.
--
local function parse_date(s)
    local m, d, y, h, mn, ampm, rest = s:match(
	"^(%d+)/(%d+)/(%d+) (%d+):(%d+) ([AP]M) (.*)")
    if ampm == "PM" then h = h + 12 end
    if y+0 < 2000 then y = y + 2000 end
    return { dt=string.format("%04d-%02d-%02d", y, m, d), h=h, mn=mn,
	rest=rest }
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
local function present_weather(xml)
    local s, cnt, tbl
    local cw = widgets.currweather
    local buf = cw:get_buffer()
    local dt = parse_date(xml.weather.cc.lsup)
    local mydt = os.date("%Y-%m-%d")

    widgets.logo:clear()

    -- build the current weather information as a string    
    s = xml.weather.loc.dnam .. " at " .. dt.h .. ":" .. dt.mn .. " "
    if dt.dt ~= mydt then s = s .. dt.dt .. " " end
    s = s .. dt.rest .. "\n"
    s = s .. "Temp: " .. xml.weather.cc.tmp .. " " .. xml.weather.head.ut.."\n"
    s = s .. "Description: " .. xml.weather.cc.t .. "\n"
    s = s .. "Humidity: " .. xml.weather.cc.hmid .. "%\n"

    buf:set_text(s, #s)

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
-- Some progress on receiving.  When done, process the data.
--
local function weather_info_callback(arg, ev, data1, data2, data3)
    if ev == 'done' then
	local data = parse_weather_info(arg.sink_data)
    	present_weather(data)
    end
end

function M:get_data(loc)
    gtk.http_co.request_co{
	host = "xoap.weather.com",
	uri = "/weather/local/" .. tostring(loc)
	    .. "?cc=*&unit=m&dayf="..forecast_days,
	callback = weather_info_callback,
    }
end

return M

