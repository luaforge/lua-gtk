/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * This code handles callbacks from Gtk to Lua.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * Exported functions:
 *   luagtk_connect
 *   luagtk_disconnect
 *   luagtk_call_wrapper
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_check*, luaL_ref/unref

/**
 * Gtk calls a signal handler; find the proper Lua callback, build the
 * parameters, call, and optionally return something to Gtk.
 *
 * Note: this runs in the lua_State that the init function was called with.
 *
 * Note 2: no assumptions can be made about the contents of the stack, as
 *  this is a callback it may be invoked any time (just my guess to be on the
 *  safe side).
 *
 * Returns: a value to return to Gtk.
 */
static int _callback(void *widget, struct callback_info *cbi, int arg_cnt,
    long int *args)
{
    int i, n, val, return_count, stack_top, extra_args=0;
    lua_State *L = cbi->L;

    stack_top = lua_gettop(L);

    /* get the handler function */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->handler_ref);

    /* get the widget - no type hint given; not a new object. */
    get_widget(L, widget, 0, 0);

    if (lua_isnil(L, -1))
	printf("Warning: _callback couldn't find widget %p\n", widget);

    /* stack: function, widget.  Now add the signal's arguments.  Note that
     * the implicit first parameter always is the widget itself, this is
     * not included in query.n_params.
     */
    n = cbi->query.n_params;
    if (n != arg_cnt) {
	printf("%s callback parameter count doesn't match for %s (%d vs %d).\n",
	    msgprefix, cbi->query.signal_name, arg_cnt, n);
	return 0;
    }

    /* push all the arguments to the Lua stack */
    for (i=0; i<arg_cnt; i++) {
	GType type = cbi->query.param_types[i] & ~G_SIGNAL_TYPE_STATIC_SCOPE;
	luagtk_push_value(L, type, (union gtk_arg_types*) &args[i],
	    cbi->query.signal_name, i);
    }

    /* copy all the extra arguments (user provided) to the stack. */
    if (cbi->args_ref) {
	lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->args_ref);
	lua_pushnil(L);
	// stack: ..., argstable, key
	while (lua_next(L, -2) != 0) {
	    lua_insert(L, -3);
	    extra_args ++;
	}
	lua_pop(L, 1);
    }

    /* determine whether a return value is expected */
    GType return_type = cbi->query.return_type & ~G_SIGNAL_TYPE_STATIC_SCOPE;
    return_count = (return_type == G_TYPE_NONE) ? 0 : 1;

    /* Call the callback! */
    lua_call(L, n+extra_args+1, return_count);

    /* Determine the return value (default is zero) */
    val = 0;

    switch (return_type) {
	case G_TYPE_NONE:
	    break;
	case G_TYPE_BOOLEAN:
	    val = lua_toboolean(L, -1);
	    break;
	// XXX handle more return types!
	default:
	    printf("%s unhandled callback return type %ld of callback %s\n",
		msgprefix, (long int) return_type, cbi->query.signal_name);
    }

    /* make sure the stack is back to the original state */
    lua_settop(L, stack_top);

    return val;
}


/**
 * Callbacks with different number of parameters.  This is called directly
 * by Gtk; the _last_ parameter is the "data" that was passed to
 * g_signal_connect.  Unfortunately, _callback needs this last parameter
 * to know how many parameters there are.
 *
 * NOTE: sometimes a return value is expected!  Look at callback info for
 * more information.
 */
static int _callback_0(void *widget, struct callback_info *cbi)
{
    return _callback(widget, cbi, 0, NULL);
}

static int _callback_1(void *widget, long int data0, struct callback_info *cbi)
{
    return _callback(widget, cbi, 1, &data0);
}

static int _callback_2(void *widget, long int data0, long int data1,
    struct callback_info *cbi)
{
    return _callback(widget, cbi, 2, &data0);
}

static int _callback_3(void *widget, long int data0, long int data1,
    long int data2, struct callback_info *cbi)
{
    return _callback(widget, cbi, 3, &data0);
}

static const void (*g_callbacks[]) = {
    _callback_0,
    _callback_1,
    _callback_2,
    _callback_3
};

static const int max_callback_args = sizeof(g_callbacks)
    / sizeof(g_callbacks[0]);


/**
 * When a signal handler is disconnected, free the struct callback_info.
 */
static void _free_callback_info(gpointer data, GClosure *closure)
{
    // data is a struct callback_info.  It contains references, free them.
    // see interface.c:l_gtk_connect()
    struct callback_info *cb_info = (struct callback_info*) data;

    // remove the reference to the callback function (closure)
    luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->handler_ref);

    // remove the reference to the table with the extra arguments
    if (cb_info->args_ref)
	luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->args_ref);

    g_free(data);
}


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
    return luagtk_call(L, &fi, 1);
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

    handler_id = g_signal_connect_data(widget, signame,
	g_callbacks[n_params], cb_info, _free_callback_info, 0);

    // handler_id = _connect(widget, signame, n_params, cb_info);
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

