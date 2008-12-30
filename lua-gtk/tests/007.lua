#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test GError handling
--

require "glib"

s, err = glib.file_read_link("/some/invalid/path", gnome.NIL)

assert(err)
assert(err.domain == glib.file_error_quark())
assert(err.code == glib.FILE_ERROR_NOENT:tonumber())
assert(err.message == "Failed to read the symbolic link '/some/invalid/path': No such file or directory")

