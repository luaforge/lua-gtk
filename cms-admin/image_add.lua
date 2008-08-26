#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- This is the code needed on the image info input page.
-- Copyright (C) 2007 Wolfgang Oertl
--

--
-- Send the titles and descriptions to the server.  Should the file upload
-- not have been completed yet, wait.  At least one title has to be
-- present.
--
function on_button_save_clicked()
    local langs, req, buf = {}

    if upload_running then
	set_status "Please wait until the file upload has been completed."
	return
    end
    
    if not uploaded_file_tmp then
	set_status "Please upload a file first."
	return
    end

    req = {
	cmd = 'add-image',
	tmpfile = uploaded_file_tmp,
	file = uploaded_file,
	callback = save_done,
    }

    local iter_start = gtk.new "TextIter"
    local iter_end = gtk.new "TextIter"
    local iter = gtk.new "TreeIter"
    local title_s, title, descr_s, descr, album_s, album

    for i, lang in pairs(languages) do
	title_s = "title_" .. lang
	title = mainwin[title_s]:get_text()

	-- get the description
	descr_s = "descr_" .. lang
	buf = mainwin[descr_s]:get_buffer()
	buf:get_start_iter(iter_start)
	buf:get_end_iter(iter_end)
	descr = buf:get_text(iter_start, iter_end, false)

	-- get the album
	album_s = "album_" .. lang
	if mainwin[album_s]:get_active_iter(iter) then
	    album = album_store_lang[lang]:get_value(iter, 0, nil)
	else
	    -- print("* Warning: no album selected for language", lang)
	    album = 0
	end

	-- If title and album are specified, add this language; if the
	-- information is partly entered, show an error and stop.
	if title ~= "" and album ~= 0 then
	    req[title_s] = title
	    req[descr_s] = descr    -- can be empty.
	    req[album_s] = album
	    table.insert(langs, lang)
	elseif title ~= "" or descr ~= "" or album ~= 0 then
	    set_status("Incomplete entry for " .. (language_names[lang]
		or lang))
	    return
	end
    end

    if #langs == 0 then
	set_status "Please enter data in at least one language."
	return
    end

    req.langs = table.concat(langs, ',')

    mainwin.progress:set_fraction(0)
    mainwin.progress:set_text("Publishing image...")

    -- gtk.glade.print_r(req)
    server_request{req}
end

function save_done(resp)
    print("The image has been submitted.", resp)
    mainwin.progress:set_fraction(1)
    mainwin.progress:set_text("Image has been submitted.")
    if resp.ok then
	print "Success.  Informational messages:"
	print(resp.info)
	_image_add_clear(false)

    else
	print("Probably failed:", resp.err)
    end
end

function on_button_clear_clicked()
    _image_add_clear(true)
end

--
-- clear out the fields, except for the albums; I often upload
-- multiple images to the same album.
--
function _image_add_clear(with_album)
    local buf

    for i, lang in pairs(languages) do
	mainwin["title_" .. lang]:set_text ""
	buf = mainwin["descr_" .. lang]:get_buffer()
	buf:set_text("", 0)
	if with_album then
	    mainwin["album_" .. lang]:set_active(-1)
	end
    end
end

--
-- The user selected an album.  Try to find translations using the
-- table album_translations, and then set all of the other, still
-- unset (or set to the previous value of this combo) combos.
--
function on_album_de_changed(combo)
    _album_changed(combo, 'de')
end

function on_album_en_changed(combo)
    _album_changed(combo, 'en')
end

function on_album_es_changed(combo)
    _album_changed(combo, 'es')
end

local _album_changed_block = false

--
-- When the album selection changed, update the others to contain
-- the corresponding, translated albums, BUT ONLY FOR THOSE THAT
-- HAVE A TITLE.
--
function _album_changed(combo, this_lang)
    local iter, trid, store, lang, info, item_nr, s

    print("- album changed", combo, this_lang, _album_changed_block)
    if _album_changed_block then return end

    iter = gtk.new "TreeIter"
    trid = 0

    if combo:get_active_iter(iter) then
	store = combo:get_model()
	trid = store:get_value(iter, 2, nil)
    end

    if trid == 0 then
	print "  currently selected: none"
	return
    end


    info = album_translations[trid]
    if not info then
	print("* No information about trid " .. tostring(trid))
	return
    end

    
    for i, lang in ipairs(languages) do
	if lang ~= this_lang and info[lang] then
	    s = mainwin["title_" .. lang]:get_text()
	    if s ~= "" then
		item_nr = info[lang]
		combo = mainwin["album_" .. lang]
		_album_changed_block = true
		combo:set_active(item_nr)
		_album_changed_block = false
	    end
	end
    end

end

