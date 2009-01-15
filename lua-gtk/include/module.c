/* vim:sw=4:sts=4
 * Common initialization code for modules.  This is part of LuaGnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */

#include "module.h"
#include <string.h>

struct lg_module_api *api;

/**
 * Load the core module and check for compatible versions; then jump to
 * the register_module API function.
 *
 * @param L  Lua State
 * @param module_name  Name of this module
 */
int load_gnome(lua_State *L)
{
    // first make sure that the core module is loaded.
    lua_getglobal(L, "require");
    lua_pushliteral(L, "gnome");
    lua_call(L, 1, 1);

    // get the API
    lua_getfield(L, -1, "api");
    if (lua_isnil(L, -1))
	return luaL_error(L, "gnome.api not found");

    api = (struct lg_module_api*) lua_topointer(L, -1);
    if (!api)
	return luaL_error(L, "gnome.api is NULL");

    return api->register_module(L, thismodule);
}

/**
 * Call a function, and set the flags on the returned object.
 * XXX this should eventually go away.
 */
int lg_set_flags(lua_State *L, const char *funcname, int flags)
{
    int n_results = api->call_byname(L, thismodule, funcname);
    if (n_results == 0)
	return n_results;
    struct object *o = (struct object*) lua_topointer(L, -1);
    if (o)
	o->flags |= flags;
    return n_results;
}


/*
 * Default methods in a module: __index, new and new_array.
 */

static int lg_index(lua_State *L)
{
    return api->generic_index(L);
}

static int lg_new(lua_State *L)
{
    return api->generic_new_array(L, thismodule, 0);
}

static int lg_new_array(lua_State *L)
{
    return api->generic_new_array(L, thismodule, 1);
}

const luaL_reg module_methods[] = {
    {"__index",		lg_index },
    {"new",		lg_new },
    {"new_array",	lg_new_array },
    { NULL, NULL }
};


