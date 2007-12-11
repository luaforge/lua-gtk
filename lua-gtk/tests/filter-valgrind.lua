#! /usr/bin/env lua
-- vim:sw=4:sts=4

-- The Valgrind leak listing contains lots of blocks that are allocated during
-- library initialization, no way to free them.  In order to be able to see
-- relevant leaks, these blocks must be filtered out.


-- Output the leak info block unless it should be suppressed.
function process_block(block)

    for n, line in pairs(block) do
	if string.find(line, "gdk_display_open") then return end
	if string.find(line, "gtk_parse_args") then return end
	if string.find(line, "gtk_style_init") then return end
	if string.find(line, "dlopen@@GLIBC") then return end
    end

    -- this block contains a relevant memory leak.
    for n, line in pairs(block) do
	print(line)
    end
    print ""
    print ""
end

-- read a valgrind memory log and extract the leak blocks
function process_file(file)

    local block

    for line in file:lines() do

	-- strip PID
	line = string.gsub(line, "^==%d+== *", "")

	if string.match(line, "^[0-9,]+ bytes in %d+ blocks") then
	    block = { line }
	elseif line == "" and block then
	    process_block(block)
	    block = nil
	elseif block then
	    block[#block + 1] = line
	end
    end
end

-- read the given file, else stdin
if #arg >= 1 then
    file = io.open(arg[1])
    if not file then
	print(string.format("Can't open file %s, aborting.", arg[1]))
	os.exit(1)
    end
    process_file(file)
else
    process_file(io.stdin)
end

