#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- Handle the settings, i.e. load them from a file, store them, and let the
-- user change them using the GUI.
-- Copyright (C) 2007 Wolfgang Oertl
--

-- variable name, title, default
local settings_list = {
  { "server_module", "Server module", "cms_admin.module" },
  { "server_module_path", "Upload path for server module", "www/drupal/modules" },
  { "server_http_host", "host name of your server", "foo.com" },
  { "server_http_uri", "path on the server to access the uploaded Drupal module", "/cms_admin" },
  { "server_user", "Username for Drupal login", "nobody" },
  { "server_password", "Drupal password", "passme" },
  { "server_ftp_host", "host name for FTP access", "foo.com" },
  { "server_ftp_user", "Username for FTP access", "nobody" },
  { "server_ftp_password", "Password for FTP access", "passme" },
  { "filechooser_preview_width", "Width of the preview right of the file seleciton", 200 },
  { "upload_resize_x", "Scale input files to max. this x before uploading", 1024 },
  { "upload_resize_y", "Scale input files to max. this a before uploading", 768 },


}

local settingswin
local cfg_entries = {}

function settings_edit(tree)
    local sw = gtk.glade.create(tree, 'settingswin')
    settingswin = sw.settingswin
    local tbl = sw.settings_table

    -- build settings
    for i, v in pairs(settings_list) do
	local varname, descr, default = v[1], v[2], v[3]
	local lbl = gtk.label_new(varname)
	tbl:attach_defaults(lbl, 1, 2, i, i+1)
	lbl:set_property("xalign", 0)
	local entry = gtk.entry_new()
	tbl:attach_defaults(entry, 2, 3, i, i+1)
	entry:set_text(cfg[varname] or default)
	cfg_entries[varname] = entry
    end

    settingswin:show_all()

end

--
-- Recursively serialize an item; returns a string.
--
function serialize(item, level)
    local t = type(item)

    if t == 'table' then
	local tbl = {}
	for k, v in pairs(item) do
	    table.insert(tbl, string.format("%s = %s", k,
		serialize(v, level+2)))
	end
	local s = string.rep(" ", level)
	return "{\n" .. s .. table.concat(tbl, ",\n" .. s) .. "\n"
	    .. string.rep(" ", level - 2) .. "}"
    end

    if t == 'number' or (t == 'string' and string.match(item, "^%d+$"))  then
	return tostring(item)
    end

    -- escape " within the item
    return '"' .. string.gsub(tostring(item), '"', '\\"') .. '"'
end


--
-- Write the new config file
--
function settings_save(ofname)
    local s, ofile

    -- serialize the global variable cfg, write to config file
    s = "-- configuration, be careful when editing manually --\ncfg = "
    s = s .. serialize(cfg, 2) .. "\n"

    ofile = io.open(ofname, "w")
    ofile:write(s)
    ofile:close()
end

--
-- Forget changes.
--
function on_btn_settings_cancel_clicked()
    settingswin:hide()
    cfg_entries = {}
    settingswin = nil
end

function on_btn_settings_ok_clicked()

    for i, v in pairs(settings_list) do
	local varname, descr, default = v[1], v[2], v[3]
	local val = cfg_entries[varname]:get_text()
	if val == "" then val = nil end
	cfg[varname] = val
    end

    -- get all the answers, write to config file
    settings_save("cms-config.lua")

    -- close the window
    on_btn_settings_cancel_clicked()

    -- read and try to login
    load_config()
    server_login()

end

