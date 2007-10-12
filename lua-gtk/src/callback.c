/* vim:sw=4:sts=4
 * Lua Gtk2 binding.
 * This code handles callbacks from Gtk to Lua.
 * Copyright (C) 2007 Wolfgang Oertl
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_check*, luaL_ref

/**
 * A method has been found and should now be called.
 * input stack: parameters to the function
 * upvalues: the name of the function - func - args_info
 */
int luagtk_call_wrapper(lua_State *L)
{
    struct func_info fi;
    fi.name = (char*) lua_tostring(L, lua_upvalueindex(1));
    fi.func = (void*) lua_topointer(L, lua_upvalueindex(2));
    fi.args_info = lua_topointer(L, lua_upvalueindex(3));
    fi.args_len = lua_tointeger(L, lua_upvalueindex(4));
    return do_call(L, &fi, 1);
}

/**
 * Connect a signal to a Lua function.
 *
 * input: 1=widget, 2=signal name, 3=lua function, 4... extra parameters
 * output: the handler id, which can be used to disconnect the signal.
 */
int luagtk_connect(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TSTRING);
    luaL_checktype(L, 3, LUA_TFUNCTION);

    int stack_top, i;
    gulong handler_id;
    struct callback_info *cb_info;
    guint signal_id;

    // get the widget
    void *widget = * (void**) lua_topointer(L, 1);
    if (!widget) {
	printf("%s trying to connect a NULL widget\n", msgprefix);
	return 0;
    }

    // determine the signal
    const char *signame = luaL_checkstring(L, 2);
    signal_id = g_signal_lookup(signame, G_OBJECT_TYPE(widget));
    if (!signal_id) {
	printf("%s cannot find signal %s\n", msgprefix, signame);
	return 0;
    }

    cb_info = (struct callback_info*) g_malloc(sizeof *cb_info);
    cb_info->L = L;
    g_signal_query(signal_id, &cb_info->query);

    if (cb_info->query.signal_id != signal_id) {
	printf("%s invalid signal ID %d for signal %s\n", msgprefix,
	    signal_id, signame);
	g_free(cb_info);
	return 0;
    }

    int n_params = cb_info->query.n_params;
    if (n_params >= max_callback_args) {
	printf("%s can't handle callback with %d parameters.\n", msgprefix,
	    n_params);
	g_free(cb_info);
	return 0;
    }


    /* stack: widget - signame - func - .... */

    /* The callback is either a function, or a table with the function and
     * additional paramters.
     */

    // make a reference to the function, and store it.
    stack_top = lua_gettop(L);
    lua_pushvalue(L, 3);
    cb_info->handler_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    // if there are more arguments, put them into a table, and store a
    // reference to it.
    if (stack_top > 3) {
	lua_newtable(L);
	for (i=4; i<=stack_top; i++) {
	    lua_pushvalue(L, i);
	    lua_rawseti(L, -2, i - 3);	// [1] etc. are the parameters
	}
	cb_info->args_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    } else
	cb_info->args_ref = 0;

    /* stack: widget - signame - func - cbinfo */
    lua_settop(L, 2);

    handler_id = do_connect(widget, signame, n_params, cb_info);
    lua_pushnumber(L, handler_id);

    return 1;
}


/**
 * Disconnect a signal handler from a given widget.  You need to know the
 * handler_id, which was returned by the connect function.
 */
int luagtk_disconnect(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TNUMBER);

    void *widget = * (void**) lua_topointer(L, 1);
    gulong handler_id = lua_tointeger(L, 2);
    g_signal_handler_disconnect(widget, handler_id);

    return 0;
}


