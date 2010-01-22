#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf8
--
-- This program should, one day, allow to upload one image at a time to
-- my CMS (Drupal), using a custom yet-to-be-written module on the server,
-- to publish it in three languages; the file will be scaled down before
-- uploading.
--
-- The GUI toolkit used is Gtk2.  For added difficulty I use my own Lua-Gtk
-- binding, which is severely underpowered at the moment, and requires
-- constant refinement.
--
-- Copyright (C) 2007 Wolfgang Oertl
--
-- Revisions:
--  2007-02-02	first version.
--  2007-02-04	Lua-Gtk2 updated so the GUI is created correctly.
--  2007-02-06	Rewrote socket.ftp to use coroutines; upload in the background.
--		scale the image to 1024x768 before uploading.
--  2007-07-08	More testing
--

require "strict"
strict()

require "gtk"
require "gtk.glade"
require "gtk.ftp_co"
require "gtk.http_co"
require "transport"
require "view"
require "image_add"
require "settings"

config_file = "cms-admin.conf"
languages = {}		-- list of languages; retrieved from server.
os = gtk.get_osname()
mainwin = nil		-- list of widgets in the main window
selected_file = nil	-- currently selected filename (only valid images)
upload_running = false	-- true while the image upload is active
cookie_jar = {}		-- a successful login on the server yields a cookie.
uploaded_file_tmp = nil	-- after img upload, this is the name on the server
uploaded_file = nil	-- after img upload, original file name
tree = nil		-- XML parse tree
cfg = {}
language_names = { de='Deutsch', en='English', es='Spanisch', pt='Portugese',
    ru='Russian', fr='French' }


---
-- Try to load the config file
--
function load_config()
    local chunk, env
    chunk = loadfile(config_file)
    if not chunk then return end

    env = {}
    setfenv(chunk, env)
    local rc = pcall(chunk)

    -- on success, the environment should now have the cfg variable.
    if rc and env.cfg then
	cfg = env.cfg
    end
end

load_config()


--
-- When choosing a new file, a preview should be displayed.
--
-- If the file is not a valid image, clear the preview area instead of
-- disabling the preview, which would cause resizing of the widget, which
-- doesn't look so nice.
--
function on_filechooser_update_preview()
    local fc = mainwin.filechooser
    local img = fc:get_preview_widget()
    local fname

    if os == "win32" then
	fname = fc:get_preview_filename_utf8()
    else
	fname = fc:get_preview_filename()
    end

    if not fname or fname == "" then
	return
    end

    selected_file = nil

    local info, width, height = gtk.gdk_pixbuf_get_file_info(fname, 0, 0)

    if not info then
	img:clear()
	return
    end
    
    width = math.min(width, cfg.filechooser_preview_width)

    local pixbuf
    if os == "win32" then
	pixbuf = gtk.gdk_pixbuf_new_from_file_at_size_utf8(fname,
	    width, height, nil)
    else
	pixbuf = gtk.gdk_pixbuf_new_from_file_at_size(fname, width, height, nil)
    end

    if pixbuf then
	img:set_from_pixbuf(pixbuf)
	selected_file = fname
	fc:set_preview_widget_active(true)
    else
	img:clear()
    end

    pixbuf = nil
    collectgarbage("collect")
end


--
-- Double click on a filename.  If the file is a valid image, start uploading
-- it and show the description page.
--
-- scale the image to 1024x768, save in a temporary file, upload via FTP
-- or HTTP in the background, then delete the temporary file.  Update the
-- progress bar.
--
-- This may require http://luajit.luaforge.net/coco.html, and/or a custom
-- main loop with built-in socket operations.
--
-- Note.  This currently works by running some Gtk main loop steps in the
-- pump function.  The GUI is very unresponsive, but it works.
--
function on_filechooser_file_activated(filechooser)
    local utf8_fname, pixbuf

    if not selected_file then return end

    if os == "win32" then
	utf8_fname = selected_file
    else
	utf8_fname = gtk.g_filename_to_utf8(selected_file, -1, 0, 0, nil)
	    or selected_file
    end

    mainwin.lbl_info:set_text(utf8_fname)
    mainwin.notebook1:set_current_page(1)

    -- scale the image, compress to jpeg
    if os == "win32" then
	pixbuf = gtk.gdk_pixbuf_new_from_file_at_size_utf8(selected_file,
	    cfg.upload_resize_x, cfg.upload_resize_y, nil)
    else
	pixbuf = gtk.gdk_pixbuf_new_from_file_at_size(selected_file,
	    cfg.upload_resize_x, cfg.upload_resize_y, nil)
    end
    local buf = pixbuf:save_to_buffer("jpeg")
    pixbuf = nil

    -- upload the buffer
    http_upload(selected_file, utf8_fname, "buffer", buf, file_uploaded)
end

--
-- A file has been successfully uploaded.  Note its temporary file name.
--
function file_uploaded(resp)
    print "* file upload done"
    upload_running = false
    if resp.err then
	set_status(tostring(resp.err))
    else
	uploaded_file = resp._uploaded_file
	uploaded_file_tmp = resp.fileinfo.tmpfile
    end
end


function on_button_quit_clicked()
    gtk.main_quit()
end

function on_button_abort_clicked()
    upload_running = false
end

function on_button_upload_module_clicked()
    ftp_upload("Server Module", "file", server_module,
	server_module_path .. '/' .. server_module)
end

function on_button_settings_clicked()
    settings_edit(tree)
end

--
-- Try to login, i.e. get a valid session cookie.
-- At the same time, get the language list and the album list, this
-- saves time.  Note that the subrequests are executed in order.  Should
-- the login fail, then the other subrequests won't be answered.
--
function server_login()
    if not (cfg.server_http_host and cfg.server_http_uri
	and cfg.server_user and cfg.server_password) then
	set_status "Please configure server and login information."
	return
    end

    set_status "Login..."
    server_request{ {
	    cmd = 'login',
	    user = cfg.server_user,
	    password = cfg.server_password,
	    callback = login_callback,
	}, {
	    cmd = 'get-language-list',
	    callback = language_list_callback,
	}, {
	    cmd = 'get-album-list',
	    callback = album_list_callback,	-- in view.lua
	}
    }
end

function login_callback(resp)
    if resp.info then
	print "- login callback with info"
	print(resp.info)
    end
    if resp.err then
	fatal_error("Login failed: " .. tostring(resp.err))
    end
end

function language_list_callback(resp)
    if resp.ok and resp.langinfo and resp.langinfo.languages then
	languages = resp.langinfo.languages
	for k, v in pairs(languages) do print("lang", k, v) end
    else
	fatal_error("Failed to retrieve the language list.")
    end
end

--
-- Display an error message in a popup, then exit the application.
--
function fatal_error(msg, ...)
    set_status "Fatal error."
    local dlg = gtk.message_dialog_new(mainwin.mainwin,
	gtk.GTK_DIALOG_MODAL + gtk.GTK_DIALOG_DESTROY_WITH_PARENT,
	gtk.GTK_MESSAGE_ERROR,
	gtk.GTK_BUTTONS_OK, msg, ...)
    dlg:run()
    gtk.main_quit()
end

--
-- Set the status message to msg, which is passed to string.format along with
-- the optional, additional parameters.
--
function set_status(msg, ...)
    local sb, s = mainwin.statusbar

    if not sb._context_id then
	sb._context_id = sb:get_context_id("general messages")
    else
	sb:pop(sb._context_id)
    end

    -- format the message, and strip trailing newline if present.
    s = string.format(tostring(msg), ...)
    if string.sub(s, #s, #s) == "\n" then
	s = string.sub(s, 1, #s-1)
    end
    sb:push(sb._context_id, s)

    -- XXX maybe add to a logfile, or rather a log textfield on another page.
end

--
-- Main: build the main window using the glade library.
--
function main()
    gtk.init(0)
    tree = gtk.glade.read("cms-admin.glade")
    mainwin = gtk.glade.create(tree, "mainwin")
    mainwin.mainwin:connect('destroy', on_button_quit_clicked)

    -- setup preview for file chooser
    local filechooser = mainwin.filechooser
    local preview = gtk.image_new()
    filechooser:set_preview_widget(preview)

    -- setup the statusbar
    mainwin.statusbar._context_id = false

    setup_image_view()

    -- start the login procedure right away.
    server_login()

    -- remove all unused widgets from gtk.widgets (lots!).
    collectgarbage("collect")

    gtk.main()
end

-- collectgarbage("stop")
-- collectgarbage("setpause", 0)
-- collectgarbage("setstepmul", 800)
main()
mainwin = nil
shutdown_image_view()
-- print "- collect garbage."

-- free all unreferenced memory, then show what's left - should be
-- around 200 kB.
print(collectgarbage("count"), "kB")
collectgarbage("collect")
print(collectgarbage("count"), "kB")

-- print "** WIDGETS **"
-- for k, v in pairs(gtk.widgets) do print(k, v) end
-- gtk.dump_memory()
-- print "** END OF WIDGETS **"

