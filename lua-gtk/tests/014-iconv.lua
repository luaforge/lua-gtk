#! /usr/bin/env lua
-- vim:sw=4:sts=4

require "glib"

-- test g_convert and g_iconv; the latter has an override.

latin1_string = "Teststring - öäü ÖÄÜ ß ENDE AAAAAAAAAAAAAAA ENDE2"
assert(#latin1_string == 49)

-- g_convert
result1, read, written, err = glib.convert(latin1_string, -1, "UTF8",
    "ISO-8859-1", 0, 0, nil)
assert(#result1 == 56)
assert(read == 49)
assert(written == #result1)
assert(err == nil)

-- set up conversion to utf8
conv = glib.iconv_open("UTF8", "ISO-8859-1")
assert(conv)

-- This call will modify obuf - which is usually not OK, because in Lua
-- strings are immutable - but anyway works somewhat.
rc, result2, rest = glib.iconv(conv, latin1_string)
assert(rc == 0)
assert(result2 == result1)
assert(#rest == 0)

