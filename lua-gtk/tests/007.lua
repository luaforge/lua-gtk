#! /usr/bin/env lua
-- vim:sw=4:sts=4
-- Test GError handling
--

require "gtk"

s, err = gtk.g_file_read_link("/some/invalid/path", nil)

assert(err)
assert(err.domain == 78)
assert(err.code == 4)
assert(err.message == "Failed to read the symbolic link '/some/invalid/path': No such file or directory")

