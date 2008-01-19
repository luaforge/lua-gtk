#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Download required prebuilt Gtk related libraries from gnome.org  The
-- locations are current as of 2008-01-11.  Tested on Linux and Windows.
-- by Wolfgang Oertl
--
-- Usage: provide a directory where to store the files.  Existing files
-- won't be overwritten.
--

require "curl"
require "lfs"

-- Access via FTP is basically possible, but may use reverse DNS checking and
-- not play nicely with firewalls and NAT, so I use HTTP.
base = "http://ftp.gnome.org/pub/gnome/binaries/win32/"

-- main packages; the -dev libraries are required for building, too.
packages1 = { "atk", "glib", "gtk+", "pango" }

-- packages in dependencies; no -dev libraries needed.
packages2 = { "cairo", "gettext%-runtime", "libiconv", "libjpeg",
    "libpng", "libtiff", "zlib" }

devel = false

---
-- Look for the newest versions of the given packages including the -dev
-- counterparts.  Each package has its own subdirectory with one more
-- subdirectory per version, e.g. ..../atk/1.20/atk-1.20.0.zip
--
function get_main_packages(c, list)

    for _, package in ipairs(list) do
	dir_list = get_directory_listing(c, base .. package .. "/", true)
	dir = dir_list[#dir_list]
	if dir then
	    dir = base .. package .. "/" .. dir 
	    pat = string.gsub(package, "%+", "%%+")
	    dir_list = get_directory_listing(c, dir)
	    get_file(c, dir_list, dir, string.format("^%s%%-%%d.*zip$", pat))
	    if devel then
		get_file(c, dir_list, dir, string.format("^%s%%-dev.*zip$", pat))
	    end
	end
    end

end

-- Return a 
function build_w_cb(t)
    return function(s, len)
	t[#t + 1] = s
	return len, nil
    end
end

function get_dependencies(c, list)
    local dir = base .. "dependencies/"
    local dir_list = get_directory_listing(c, dir)

    -- for each file to download, look for the last matching file
    for _, package in ipairs(list) do
	get_file(c, dir_list, dir, string.format("^%s%%-%%d.*zip$", package))
    end
end

-- @param c  CURL object
-- @param list  A directory listing as returned from get_directory_listing
-- @param url  Location of the directory
-- @param pat  A pattern to look for in list; the last one will be fetched.
function get_file(c, list, url, pat)
    local name
    for i = #list, 1, -1 do
	if string.match(list[i], pat) then
	    name = list[i]
	    break
	end
    end

    if not name then
	print("not found:", pat)
	return
    end

    if lfs.attributes(name, "mode") then
	print("Output file exists: " .. name)
	return
    end

    ofile, msg = io.open(name, "wb")
    if not ofile then
	print(string.format("Can't open output file %s: %s", name, msg))
	return
    end

    c:setopt(curl.OPT_URL, url .. name)
    c:setopt(curl.OPT_WRITEFUNCTION, function(s, len)
	ofile:write(s)
	return len, nil
    end)
    print(url .. name)
    c:perform()
	
    ofile:close()
end

---
-- Get a list of files in the directory at the given URL.
--
-- @param c  a CURL object
-- @param url  The URL to fetch
-- @param dirs  If true, return subdirectories, else files
-- @return  A list of directory entries
--
function get_directory_listing(c, url, dirs)
    local t, s, pat = {}

    -- get list of base/dependencies
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_WRITEFUNCTION, function(s, len)
	t[#t + 1] = s
	return len, nil
    end)
    c:perform()

    -- if looking for subdirectories, require a trailing "/" in the file name.
    pat = dirs and 'href="([^"?:/]*/)"' or 'href="([^"?:/]*)"'

    s = table.concat(t)
    t = {}
    for item in s:gmatch(pat) do
	t[#t + 1] = item
    end
    
    return t
end


-- MAIN --
if arg[1] == "-d" then
    devel = true
    table.remove(arg, 1)
end

if #arg ~= 1 then
    print(string.format("Usage: %s [-d] output_dir", arg[0]))
    return
end

rc, msg = lfs.chdir(arg[1])
if not rc then
    print(string.format("Can't chdir(%s): %s", arg[1], msg))
    return
end

c = curl.easy_init()
get_main_packages(c, packages1)
get_dependencies(c, packages2)

