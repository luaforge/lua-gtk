#! /usr/bin/env lua

-- test whether the library is loadable

-- print(package)
-- table.foreach(package, function(k,v) print(k,v) end)
-- require "gt2"
require "gtk"

-- print("gtk is", gtk)
-- table.foreach(gtk, function(k,v) print(k,v) end)
gtk.init()

