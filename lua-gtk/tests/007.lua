#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test GError handling
--

require "gtk"

s, err = gtk.g_file_read_link("/some/invalid/path", nil)

assert(err)
assert(err.domain == gtk.g_file_error_quark())
assert(err.code == gtk.G_FILE_ERROR_NOENT:tonumber())
assert(err.message == "Failed to read the symbolic link '/some/invalid/path': No such file or directory")

