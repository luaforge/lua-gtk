require "glib"

rex = glib.regex_new("^foo[bar]+", 0, 0, nil)

-- object-oriented version
ok, match = rex:match("fooabx", 0, true)
print(match:get_string())

-- function call version
ok, match = glib.regex_match(rex, "fooabx", 0, true)
print(glib.match_info_get_string(match))

