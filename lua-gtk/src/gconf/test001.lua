#! /usr/bin/env lua
-- vim:sw=4:sts=4

require 'gconf'
-- gnome.set_debug_flags"memory"

eng = gconf.engine_get_default()


-- test user_data

data = { "a", "b", "c" }
destroyed = false

function engine_destroy(data2)
    assert(data2)
    assert(data2[1] == data[1])
    destroyed = true
end

eng.__dnotify = gnome.closure(engine_destroy)
eng:set_user_data(data, eng.__dnotify)


-- retrieve some values

val, err = eng:get("/system/http_proxy/use_http_proxy", gnome.NIL)
if val then
    print("use_http_proxy", val:get_bool())
    -- get schema information
    val, err = eng:get("/schemas/system/http_proxy/use_http_proxy", gnome.NIL)
    assert(val)
    print"x"
    schema = val:get_schema()
    print"y"
    assert(schema)
    print("short_desc", schema:get_short_desc())
    print("long_desc", schema:get_long_desc())
end

val, err = eng:get("/desktop/gnome/sound/theme_name", gnome.NIL)
if val then
    print("theme_name", val:get_string())
elseif err then
    print(err.message)
end


val, err = eng:get("/nonexistent/path/is_not_an_error", gnome.NIL)
assert(val == nil)
assert(err == nil)

val, err = eng:get("invalid path is an error", gnome.NIL)
assert(val == nil)
assert(err)


-- Free the engine now, which calls the closure.  If Lua's garbage collector
-- frees the closure before the engine, an error would occur.
eng:unref()

-- verify that the handler was called.
assert(destroyed, "the dnotify handler was not called.")

