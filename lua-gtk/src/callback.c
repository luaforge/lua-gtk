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
#include <stdarg.h>

/**
 * Handle return values from the Lua handler to pass back to Gtk.
 *
 * @param return_type     The GType of the expected return value
 * @param cbi             callback_info of this signal
 * @return                An integer to return to Gtk.
 */
static int _callback_return_value(lua_State *L, int return_type,
    struct callback_info *cbi)
{
    int val = 0;

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

    return val;
}


/**
 * Gtk calls a signal handler; find the proper Lua callback, build the
 * parameters, call, and optionally return something to Gtk.
 *
 * This runs in the lua_State that was used to call luagtk_connect with.  No
 * assumptions can be made about how the parameters for the callback arrive,
 * i.e. on the stack, or in registers, or some mixture.
 *
 * Note 2: no assumptions can be made about the contents of the Lua stack, as
 * this is a callback it may be invoked any time (just my guess to be on the
 * safe side).  Care is taken not to modify the Lua stack.
 *
 * @param data   a pointer to a struct callback_info
 * @param ...    Variable arguments, and finally the widget pointer.
 * @return       A value to return to Gtk.
 */
static int _callback(void *data, ...)
{
    va_list ap;
    int i, arg_cnt, return_count, stack_top, extra_args=0;
    lua_State *L;

    struct callback_info *cbi = (struct callback_info*) data;
    L = cbi->L;
    stack_top = lua_gettop(L);

    /* get the handler function */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->handler_ref);

    /* push all the signal arguments to the Lua stack */
    arg_cnt = cbi->query.n_params;

    va_start(ap, data);
    for (i=0; i<arg_cnt; i++) {
	GType type = cbi->query.param_types[i] & ~G_SIGNAL_TYPE_STATIC_SCOPE;
	// XXX might need to differentiate between 4 and 8 byte arguments,
	// which can be derived from the type.
	long int val = va_arg(ap, long int);
	(void) luagtk_push_value(L, type, (char*) &val);
    }

    /* the widget is the last parameter to this function.  The Lua callback
     * gets it as the first parameter, though. */
    void *widget = va_arg(ap, void*);
    get_widget(L, widget, 0, 0);
    va_end(ap);

    if (lua_isnil(L, -1))
	printf("Warning: _callback couldn't find widget %p\n", widget);
    lua_insert(L, stack_top + 2);

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
    lua_call(L, arg_cnt+extra_args+1, return_count);

    /* Determine the return value (default is zero) */
    int val = _callback_return_value(L, return_type, cbi);

    /* make sure the stack is back to the original state */
    lua_settop(L, stack_top);

    return val;
}


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


    // Find out how many bytes of arguments there are, and how much
    // space they occupy.
    /*
    int n_bytes = 0;
    int n_params = cb_info->query.n_params;

    for (i=0; i<n_params; i++) {
	GType t = cb_info->query.param_types[i];
	int sz;

	t = G_TYPE_FUNDAMENTAL(t);
	printf("fundamental is %d\n", t);

	switch (t) {
	    case G_TYPE_LONG:
	    case G_TYPE_ULONG:
		sz = sizeof(long int);
		break;

	    case G_TYPE_POINTER:
	    case G_TYPE_BOXED:
	    case G_TYPE_OBJECT:
		sz = sizeof(void*);
		break;

	    default:
		sz = sizeof(int);
	}

	n_bytes += sz;
    }

    printf("signal %s receives %d parameters = %d bytes\n",
	signame, n_params, n_bytes);
    cb_info->args_bytes = n_bytes;
    */

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

    /*
    printf("connect for widget %p, signal %s to %p with info %p\n",
	widget, signame, _callback, cb_info);
    */

    // verify the readability of this address
    // int foo = * (int*) widget;
    // foo = foo + 1;

    handler_id = g_signal_connect_data(widget, signame,
	(GCallback) _callback, cb_info, _free_callback_info,
	G_CONNECT_SWAPPED);

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

