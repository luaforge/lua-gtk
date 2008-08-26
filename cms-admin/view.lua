#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- Routines to display an album list, thumbnails and previews in a gallery
-- like fashion.
-- Copyright (C) 2007 Wolfgang Oertl
--

album_store = nil	-- the backing store for the album tree view
album_store_iter = {}	-- key=language code, data=iter for album_store
album_store_lang = {}	-- key=language code, data=store for only this lang
album_translations = {}	-- key=trid, data={ lang=album_id, ... }
image_store = nil	-- backing store for the image view
thumbs_list = {}	-- IDs of images whose thumbs still have to be loaded
thumbs_received = 0	-- thumbnails already downloaded
thumbs_total = 0	-- thumbnails to download in total
images = {}		-- images in image_list. key=image_id, val=tbl w/data 
image_count = 0		-- number of images in table images
image_cache = {}	-- already loaded images (preload), or in progress
curr_image_nr = -1	-- number of the currently displayed image
next_image_id = -1	-- ID of the image that should be displayed next
next_preload = nil	-- image_nr of the image that should be preloaded next


function setup_image_view()

    -- setup album tree. album.id, album.name, album.lang, album.trid
    album_store = gtk.tree_store_new(4, glib.TYPE_INT, glib.TYPE_STRING,
	glib.TYPE_STRING, glib.TYPE_INT)
    mainwin.album_list:set_model(album_store)
    local r = gtk.cell_renderer_text_new()
    local c = gtk.tree_view_column_new_with_attributes("Name", r, "text",
	2, nil)
    mainwin.album_list:append_column(c)

    for lang, name in pairs{ de='Deutsch', en='Englisch', es='Spanisch'} do
	local iter = gtk.new "TreeIter"
	album_store:append(iter, nil)
	album_store:set(iter, 0, 0, 1, lang, 2, name, -1)
	album_store_iter[lang] = iter
--	album_store_iter[lang] = album_store:append1(nil, nil, 0, lang, name)

	-- album.id, album.name, album.trid
	local store = gtk.list_store_new(3, glib.TYPE_INT, glib.TYPE_STRING,
	    glib.TYPE_INT)
	local s = "album_" .. lang
	mainwin[s]:set_model(store)
	album_store_lang[lang] = store

	-- setup album combo - use separate store, just the albums of that
	-- language.
	r = gtk.cell_renderer_text_new()
	mainwin[s]:pack_start(r, false)
	mainwin[s]:set_attributes(r, 'text', 1, nil)
    end

    -- setup icon view
    local image_list = mainwin.image_list
    image_store = gtk.list_store_new(3, glib.TYPE_INT, glib.TYPE_STRING,
	gdk.pixbuf_get_type())
    image_list:set_model(image_store)
    image_list:set_text_column(1)
    image_list:set_pixbuf_column(2)
end

-- free all memory
function shutdown_image_view()
    images = {}
    album_store:clear()
    album_store = nil
    album_store_iter = nil
    album_store_lang = nil
    image_store:clear()
    image_store = nil
    thumbs_list = nil
    image_cache = nil
end

-- usually not called, as this request is included in the login request.
function server_get_album_list()
    server_request{{
	cmd = 'get-album-list',
	callback = album_list_callback,
    }}
end

function album_list_callback(resp)
    if resp.ok then
	set_status "Ready."
	set_album_list(resp.album_list)
    else
	set_status(resp.ok or "Failed to get the album list.")
    end
end

--
-- Got the list of albums.  Fill the list on the album page, and
-- also the dropdown on the create image tab.
--
-- This is an array of { id, name, lang, trid }.  The "trid" is the
-- translation id; all albums that are translations of each other, i.e. that
-- belong together, have the same trid.
--
-- Albums with the same trid should contain the same images in various
-- translations, but this doesn't have to be so.
--
function set_album_list(list)
    local combo = mainwin.album_de
    local iter, album_iter, album_nrs = gtk.new "TreeIter"

    album_translations = {}
    album_nrs = { en=0, de=0, es=0 }
    local at = album_translations

    for i, album in pairs(list) do
	-- depending on album.lang, get the lang iter, i.e. the correct top
	-- level entry
	album_iter = album_store_iter[album.lang]
	if not album_iter then
	    print("* Album with unknown language", album.lang)
	else
	    album_store:append(iter, album_iter)
	    album_store:set(iter, 0, album.id, 1, album.lang, 2, album.name,
		3, album.trid or 0, -1)
--	    album_store:append1(iter, album_iter, album.id, album.lang,
--		album.name, album.trid or 0)

	    -- also fill the combo boxes on the new image page
	    local store = album_store_lang[album.lang]
	    store:append(iter)
	    store:set(iter, 0, album.id, 1, album.name, 2, album.trid or 0, -1)
--	    album_store_lang[album.lang]:append1(iter, album.id,
--		album.name, album.trid or 0)

	    -- link translations together
	    if album.trid and album.trid ~= 0 then
		at[album.trid] = at[album.trid] or {}
		at[album.trid][album.lang] = album_nrs[album.lang]
	    end

	    album_nrs[album.lang] = album_nrs[album.lang] + 1
	end
    end

end


--
-- Double click on an album.  Retrieve the image list, and
-- add them to the image view (in the callback).
--
function on_album_list_row_activated(tree, path, column)
    local iter = gtk.new "TreeIter"
    local model = tree:get_model()
    model:get_iter(iter, path)
    local album_id = model:get_value(iter, 0, nil);
    local album_name = model:get_value(iter, 2, nil);
    image_store:clear()
    thumbs_list = {}
    set_status("Retrieving images in album " .. album_name .. "...")

    server_request{{
	cmd = 'get-album-images',
	album_nr = album_id,
	callback = image_list_response,
    }}
end

--
-- The complete image list has been retrieved.
-- Each image has the following data: { title, id }
--
function image_list_response(resp)
    local list = resp.image_list
    if not list then
	print "* image_list_respone: no image_list found."
	return
    end

    image_store:clear()
    images = {}
    image_count = 0
    set_status "Done."

    local iter = gtk.new "TreeIter"
    for i, image in ipairs(list) do
	image_store:append(iter)
	image_store:set(iter, 0, image.id, 1, image.title, 2, nil, -1)
--	image_store:append1(iter, image.id, image.title, nil)
	table.insert(thumbs_list, image.id)
	image.image_nr = image_count
	images[image.id] = image
	image_count = image_count + 1
    end

    thumbs_received = 0
    thumbs_total = #thumbs_list

    if thumbs_total == 0 then return end

    mainwin.progress:set_text("Fetching " .. thumbs_total .. " thumbnails")
    mainwin.progress:set_fraction(0)

    -- load three in parallel, each of them 5 at a time.  that's quick!
    load_thumbs()
    load_thumbs()
    load_thumbs()
end

--
-- Load thumbnails, up to 5 per request.
--
function load_thumbs()
    local resp = {}

    for i = 1, 15 do
	if #thumbs_list == 0 then break end
	local image_id = table.remove(thumbs_list, 1)

	table.insert(resp, {
	    cmd = 'get-image',
	    id = image_id,
	    size = 't',			-- t means thumbnail
	    callback = thumbnail_received,
	})
    end

    if #resp > 0 then
	server_request(resp)
    end

end

--
-- Received a thumbnail from the server.  Find the icon this is for and
-- add the image.
--
function thumbnail_received(resp)

    thumbs_received = thumbs_received + 1
    if thumbs_received >= thumbs_total then
	mainwin.progress:set_fraction(1)
	mainwin.progress:set_text("Done.")
    else
	mainwin.progress:set_fraction(thumbs_received / thumbs_total)
    end

    if resp.err or not resp.data then
	set_status "ERROR: Thumbnail for image not successfully retrieved."
	print(resp.err)
	return
    end

    if resp.vars.size ~= #resp.data then
	set_status("ERROR: Thumbnail filesize doesn't match: %d - %d",
	    resp.vars.size, #resp.data)
	return
    end

    local image_info = images[resp.vars.id]
    if not image_info then
	print("* Error: thumbnail with ID " .. tostring(resp.vars.id)
	    .. " not known.")
	return
    end

    local _, model, iter = _image_nr_to_id(image_info.image_nr)

    if iter then
	local loader, pix, rc
	loader = gdk.pixbuf_loader_new()
	rc = loader:write(resp.data, #resp.data, nil)
	loader:close(nil)

	if not rc then
	    set_status "ERROR when trying to load image into pixbuf_loader."
	else
	    pix = loader:get_pixbuf()
	    if not pix then
		set_status "ERROR pixbuf loader returned no image."
	    else
		pix:ref()
		-- XXX set_value could be used, but the lua-gtk2 libraray
		-- doesn't handle this properly.
		image_store:set(iter, 2, pix, -1)
		-- store it as the GtkIconView doesn't seem to keep a reference
		-- to the pixbuf.
		images[resp.vars.id].pixbuf = pix
	    end
	end
	loader = nil
    else
	set_status "WARNING received a thumbnail which isn't needed."
    end

    -- for debugging purposes.
    collectgarbage("collect")

    -- continue loading more thumbnails
    load_thumbs()
end


--
-- Click on an icon - load the preview image and display it.
--
function on_image_list_item_activated(iconview, path, column)
    local s = gtk.tree_path_to_string(path)
    _image_goto(true, s)
end

--
-- Jump to the first/prev/next/last image in this album
--
function on_button_image_first_clicked()
    _image_goto(true, 0)
end

function on_button_image_back_clicked()
    _image_goto(false, -1)
end

function on_button_image_forward_clicked()
    _image_goto(false, 1)
end

function on_button_image_last_clicked()
    _image_goto(true, image_count - 1)
end


--
-- Display a given image from the active album.
--
function _image_goto(absolute, where)
    local direction

    where = tonumber(where)
    if not absolute then
	if curr_image_nr < 0 then
	    print "* _image_goto called with relative position, pos unset"
	    return
	end
	direction = where
	where = curr_image_nr + where
    else
	-- if getting the first image, preload the second.
	if where == 0 then direction = 1
	elseif where == image_count-1 then direction = -1 end
    end

    if where ~= curr_image_nr then
	return _image_load(where, direction, false)
    end
end

--
-- Load one image of the current album.
-- image_nr: 0 .. image_count-1
--
function _image_load(image_nr, direction, preloading)
    local image_id, model, iter = _image_nr_to_id(image_nr)
    if not image_id then return end
    local sz, pixbuf = images[image_id].preview.size

    -- if the image cache has it, show immediately.
    pixbuf = image_cache_get(image_id)
    if pixbuf ~= nil then
	if not preloading then
	    -- preload in progress?
	    if pixbuf == true then
		print("- download already in progress for", image_id)
		mainwin.progress:set_text(string.format(
		    "Retrieving preview (%.0f kB)", sz/1024))
		next_image_id = image_id
		if direction then next_preload = image_nr + direction end
		return
	    end
	    -- got it (or false, for failure)
	    _preview_display(image_nr, image_id, pixbuf)
	    -- preload the next image in the current direction.
	    if direction then _image_do_preload(image_nr + direction) end
	end
	return
    end
    
    if not preloading then 
	mainwin.progress:set_text(string.format("Retrieving preview (%.0f kB)",
	    sz/1024))
	mainwin.progress:set_fraction(0)
    end

    server_request{ progress = _preview_progress, {
	cmd = 'get-image',
	id = image_id,
	size = 'p',
	callback = _preview_received,
	response = {
	    image_name = model:get_value(iter, 1, nil),
	    image_nr = image_nr,
	    image_id = image_id,
	    image_size = images[image_id].preview.size,
	    direction = direction,
	},
    }}

    -- add a dummy entry that informs about the in-progress download.
    -- print("- starting download for", image_id)
    image_cache_add(image_id, true)

    if not preloading then
	next_image_id = image_id
    end
end

-- only update progress if this is the image to be displayed?
function _preview_progress(arg, what, length, total_length)
    local resp = arg.response[1]
    if resp.image_id == next_image_id then
	length = math.min(length, resp.image_size)
	mainwin.progress:set_fraction(length / resp.image_size)
    end
end

--
-- The server sends the preview image.  Display it in the image tab
-- and switch to it, unless it was a preload.  In this case, just put
-- the preloaded image into a global variable, where it may, or may not,
-- be used later.
--
function _preview_received(resp)
    local loader, pixbuf, rc
    local show = resp.vars.id == next_image_id

    if show then
	mainwin.progress:set_text "Done."
    end

    if resp.err or not resp.data then
	if show then
	    mainwin.progress:set_text "The image could not be retrieved."
	    mainwin.progress:set_fraction(0)
	end
    else
	loader = gdk.pixbuf_loader_new()
	rc = loader:write(resp.data, #resp.data, nil)
	loader:close(nil)

	if not rc then
	    set_status("ERROR when trying to load preview image into "
		.. "pixbuf_loader.")
	else
	    pixbuf = loader:get_pixbuf()
	    if not pixbuf then
		set_status "ERROR pixbuf loader returned no image."
	    else
		-- need to reference it!  See GdkPixbufLoader documentation.
		pixbuf:ref()
	    end
	end
	loader = nil
    end

    -- add the image to the cache, or false if it couldn't be loaded.
    -- print "- collect garbage"
    -- collectgarbage("collect")
    image_cache_add(resp.image_id, pixbuf or false)

    if show then
	_preview_display(resp.image_nr, resp.vars.id, pixbuf)
	if resp.direction then
	    _image_do_preload(resp.image_nr + resp.direction)
	end
    end

    -- If the user wanted to see this image while it was being downloaded
    -- as preview, immediately download the next one.
    if next_preload then
	-- print("- next_preload is", next_preload)
	local nr = next_preload
	next_preload = nil
	_image_do_preload(nr)
    end
end


--
-- Display the new current image.  pixbuf may be nil, indicating failure
-- to load it.
--
function _preview_display(image_nr, image_id, pixbuf)

    -- set label and button states
    mainwin.image_label:set_text(tostring(image_nr+1)
	.. "/" .. tostring(image_count) .. ": "
	.. tostring(images[image_id].title))
    mainwin.button_image_first:set_sensitive(image_nr > 0)
    mainwin.button_image_back:set_sensitive(image_nr > 0)
    mainwin.button_image_forward:set_sensitive(image_nr+1 < image_count)
    mainwin.button_image_last:set_sensitive(image_nr+1 < image_count)

    curr_image_nr = image_nr

    -- Display the picture, if available.  Can be nil or false, if no
    -- picture is available.
    if pixbuf then
	mainwin.full_image:set_from_pixbuf(pixbuf)
	set_status "Success."
    else
	-- an error message already has been set by the caller.
	-- XXX display a "broken image" instead of an empty space.
	mainwin.full_image:clear()
    end

    mainwin.notebook1:set_current_page(3)
    collectgarbage("collect")
end

--
-- Try to preload the given image, unless it already is in the image cache.
-- If the given number is invalid, ignore the call.
--
function _image_do_preload(image_nr)
    -- print "- preloading next image."
    local image_id = _image_nr_to_id(image_nr)
    if image_id and not image_cache_get(image_id) then
	_image_load(image_nr, nil, true)
    end
end

--
-- Try to find the image_id of the image at position image_nr in the current
-- album.  Also returns the model and iterator for this entry in the icon view.
--
function _image_nr_to_id(image_nr)
    local path, iter, model

    if image_nr < 0 or image_nr >= image_count then return end

    path = gtk.tree_path_new_from_string(tostring(image_nr))
    iter = gtk.new "TreeIter"
    model = mainwin.image_list:get_model()
    if model:get_iter(iter, path) then
	return model:get_value(iter, 0, nil), model, iter
    end
end

--
-- Add an entry for the given image_id.  The cache size is limited, so this
-- may discard the oldest entry.
--
-- pixbuf:
--	GtkPixbuf	the image
--	false		failure to load the image
--	true		download in progress
--
function image_cache_add(image_id, pixbuf)

    -- Possibly replace an existing entry for this image.
    local foo, item = image_cache_get(image_id)
    if item then
	item.pixbuf = pixbuf
	return
    end

    -- add a new entry - first delete if cache full
    while #image_cache > 5 do
	table.remove(image_cache, 1)
    end

    table.insert(image_cache, { id=image_id, pixbuf=pixbuf })
end


--
-- Look for the given image_id in the cache.  If found, returns the
-- associated pixbuf, otherwise nil.  It can also return false if this
-- image can't be loaded.
--
function image_cache_get(image_id)
    local i, item

    for i = 1, #image_cache do
	if image_cache[i].id == image_id then
	    item = table.remove(image_cache, i)
	    table.insert(image_cache, item)
	    return item.pixbuf, item
	end
    end
end

function image_cache_clear()
    image_cache = {}
end

local _del_image_id = nil

function on_button_image_delete_clicked()
    local image_nr = curr_image_nr
    if image_nr == -1 then return end
    local image_id = _image_nr_to_id(image_nr)
    local title = images[image_id].title
    local dlg = gtk.message_dialog_new(mainwin.mainwin,
	gtk.DIALOG_MODAL + gtk.DIALOG_DESTROY_WITH_PARENT,
	gtk.MESSAGE_QUESTION,
	gtk.BUTTONS_OK_CANCEL, "Delete the image %s with all translations?",
	    title)
    dlg:connect('response', _delete_response)
    -- dlg._image_id = image_id
    _del_image_id = image_id
    -- XXX store the ID in the dialog somehow.  dlg.foo won't work properly
    -- because there's no ref on it and it can be garbage collected.
    dlg:show()
end

--
-- If the user clicked on "OK", then delete the image.
--
function _delete_response(dlg, rc)
    local id = _del_image_id
    _del_image_id = nil
    dlg:destroy()
    if not id or rc == gtk.RESPONSE_CANCEL then return end

    server_request{{
	cmd = 'delete-image',
	id = id,
	callback = _delete_callback}}
end

function _delete_callback(resp)
    if not resp.ok then
	set_status("Failed to delete the image.")
	return
    end

    print("- deleted the image", resp.vars.id)

    -- update the GUI
    -- 1. the icon view
    -- 2. if this is the current image, blank the pixbuf

    local info = images[resp.vars.id]
    if not info then
	print "- deleted image not in current album."
	return
    end

    local image_id, model, iter = _image_nr_to_id(info.image_nr)
    if not image_id then
	print "- strange error"
	return
    end

    -- remove image from icon list
    model:set(iter, 2, nil, 1, "(deleted)", 0, 0, -1)

    if curr_image_nr == info.image_nr then
	mainwin.full_image:clear()
    end
end

