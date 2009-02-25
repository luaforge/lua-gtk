#! /usr/bin/env lua
-- vim=sw:4:sts=4

require "gtk"

targets = gtk.new_array("TargetEntry", 2)

-- set a string and verify
targets[1].target = "demo"
assert(targets[1].target == "demo")


