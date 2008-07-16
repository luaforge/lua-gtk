#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"
gtk.set_debug_flags()

e = gtk.text_buffer_new(nil)

-- no problem
m1 = e:get_insert()
m2 = e:get_insert()
m3 = e:get_insert()

-- no problem
iter = gtk.new "GtkTextIter"
e:get_start_iter(iter)

-- this used to cause a segfault, but is fixed as of 2008-07-16
m4 = gtk.text_mark_new("mark1", true)
e:add_mark(m4, iter)

m4 = e:get_mark("mark1")

m5 = e:create_mark("mark2", iter, true)


