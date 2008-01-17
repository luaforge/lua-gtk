#! /usr/bin/lua

-- call g_convert functions; this also tests how char** arguments
-- are handled; right now not very well.

require "gtk"

latin1_string = "Teststring - öäü ÖÄÜ ß ENDE AAAAAAAAAAAAAAA ENDE2"

-- g_convert
s, read, written, err = gtk.g_convert(latin1_string, -1, "UTF8", "ISO-8859-1",
	0, 0, nil)

print("Ergebnis von g_convert", s, read, written, err)


-- set up conversion to utf8
conv = gtk.g_iconv_open("UTF8", "ISO-8859-1")

val = latin1_string
obuf = string.rep(' ', #val)

-- This call will modify obuf - which is usually not OK, because in Lua
-- strings are immutable - but anyway works somewhat.
a, b, c, d, e = gtk.g_iconv(conv, val, #val, obuf, #obuf)
print(a, b, c, d, e)
print("eingabestring - sollte nicht gut lesbar sein, weil nicht utf8:\n", val)
print("obuf", obuf)

