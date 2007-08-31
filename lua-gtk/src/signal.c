/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * Handle signals, i.e. callbacks from Gtk to Lua.
 */

#include "luagtk.h"
#include <malloc.h>	    // free
#include <lauxlib.h>	    // luaL_unref


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
int do_callback(void *widget, struct callback_info *cbi, int arg_cnt, int *args)
{
    int i, n, val, return_count, stack_top, extra_args=0;
    lua_State *L = cbi->L;

    stack_top = lua_gettop(L);

    /* get the handler function */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->handler_ref);

    /* get the widget - no type hint given; not a new object. */
    get_widget(L, widget, 0, 0);

    if (lua_isnil(L, -1))
	printf("Warning: do_callback couldn't find widget %p\n", widget);

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
	push_a_value(L, type, (union gtk_arg_types*) &args[i],
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
 * g_signal_connect.  Unfortunately, do_callback needs this last parameter
 * to know how many parameters there are.
 *
 * NOTE: sometimes a return value is expected!  Look at callback info for
 * more information.
 */
static int g_callback_0(void *widget, struct callback_info *cbi)
{
    return do_callback(widget, cbi, 0, NULL);
}

static int g_callback_1(void *widget, int data0, struct callback_info *cbi)
{
    return do_callback(widget, cbi, 1, &data0);
}

static int g_callback_2(void *widget, int data0, int data1, struct callback_info *cbi)
{
    return do_callback(widget, cbi, 2, &data0);
}

static int g_callback_3(void *widget, int data0, int data1, int data2, struct callback_info *cbi)
{
    return do_callback(widget, cbi, 3, &data0);
}

static void (*g_callbacks[]) = {
    g_callback_0,
    g_callback_1,
    g_callback_2,
    g_callback_3
};

int max_callback_args = sizeof(g_callbacks) / sizeof(g_callbacks[0]);


/**
 * When a signal handler is disconnected, free the struct callback_info.
 */
static void free_callback_info(gpointer data, GClosure *closure)
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
 * This is here so that g_callbacks doesn't need to be exported from this
 * module.
 */
int do_connect(void *widget, const char *signame, int n_params,
    struct callback_info *cb_info) {

    return g_signal_connect_data(widget, signame,
	g_callbacks[n_params], cb_info, free_callback_info, 0);
}

