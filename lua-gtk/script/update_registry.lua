#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "lfs"

path = 'hklm\\system\\CurrentControlSet\\Control\\Session Manager\\Environment'
key = 'Path'


-- Retrieve the current setting of a given registry entry
function reg_query(path, name)
    local f, s

    s = string.format('reg query "%s" /v %s', path, name)
    f = io.popen(s, "r")
    for line in f:lines() do
        -- print(">>", line)
        val = string.match(line, "^%s*Path%s+%S+%s+(.*)$")
        if val then return val end
    end
end

-- Set a registry entry, possibly overwriting the existing entry.
function reg_set(path, name, value)
    s = string.format('reg add "%s" /v "%s" /t REG_EXPAND_SZ /d "%s" /f',
        path, name, value)
    print(s)
    os.execute(s)
end

s = reg_query(path, key)

if not s then
    print("Error - can't query current PATH")
    os.exit(1)
end

here = lfs.currentdir() .. "\\bin"
pat = string.lower(string.gsub(here, "[%$%^%(%)%%%.%[%]%+%-%?]", "%%%1"))

if string.match(string.lower(s), pat) then
    print("Already set.")
    os.exit(0)
end

s = s .. ";" .. here
reg_set(path, key, s)


