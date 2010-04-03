#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "gtk"

buf = gtk.text_buffer_new(nil)

-- no problem
m1 = buf:get_insert()
m2 = buf:get_insert()
m3 = buf:get_insert()

-- no problem
iter = gtk.new "TextIter"
buf:get_start_iter(iter)

-- this used to cause a segfault, but is fixed as of 2008-07-16
m4 = gtk.text_mark_new("mark1", true)
buf:add_mark(m4, iter)

m4 = buf:get_mark("mark1")

m5 = buf:create_mark("mark2", iter, true)

-- test text tags
t1 = buf:create_tag('foo', 'foreground', 'blue', nil)
assert(t1)
t2 = buf:create_tag('foo', 'foreground', 'blue', nil)
assert(t2 == nil)


