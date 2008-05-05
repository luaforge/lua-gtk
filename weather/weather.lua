#! /usr/bin/env lua
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

providers = {}

gtk.strict.init()

forecast_days = 5
gladefile = string.gsub(arg[0], ".lua", "") .. ".ui"

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
    local prov = store:get_value(iter, 1, nil)
    local location = store:get_value(iter, 2, nil)

    -- load the appropriate provider module on first use
    if not providers[prov] then
	providers[prov] = require(prov)
    end

    providers[prov]:get_data(location)
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
	    print("IGNORE in", key, ":", data)
	end
    end,

}


--
-- The data retrieved from weather.com is a XML text.  Parse it and create
-- a tree like structure representing the data.  This allows direct access
-- to various items.
--
function parse_weather_info(data)
    local tree = {}
    stack = { { tree, "top" } }

    local p = lxp.new(callbacks, nil)
    p:parse(data)
    p:parse()
    p:close()
    p = nil
    stack = nil

    return tree.top
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


function build_gui()
    local b = gtk.builder_new()
    local rc, err = b:add_from_file(gladefile, nil)
    if err then print(err.message); return end
    b:connect_signals_full(_G)

    -- access relevant widgets
    for _, v in ipairs { "currweather", "forecast", "mainwin", "location",  
	"logo" } do
	widgets[v] = b:get_object(v)
    end
    widgets.logo:clear()

    -- setup location selector.  Name, Provider, Location Code
    local location = widgets.location
    local store = gtk.list_store_new(3, gtk.G_TYPE_STRING, gtk.G_TYPE_STRING,
	gtk.G_TYPE_STRING)
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
	store:set(iter, 0, info[1], 1, info[2], 2, info[3], -1)
    end

    widgets.mainwin:show()
    return true
end

-- MAIN --

gtk.strict.lock()
if not build_gui() then os.exit(1) end
gtk.main()
widgets = nil
collectgarbage()
collectgarbage()
collectgarbage()
print(collectgarbage("count"), "kB")

