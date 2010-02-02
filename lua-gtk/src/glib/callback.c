/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * This code handles callbacks from Gtk to Lua.
 * Copyright (C) 2005, 2008 Wolfgang Oertl
 *
 * Exported functions:
 *   glib_connect
 *   glib_connect_after
 *   glib_disconnect
 */

/**
 * @class module
 * @name gtk_internal.callback
 * @description Handle callbacks from Gtk to Lua.
 */

#include "module.h"
#include <stdarg.h>
#include <gobject/gvaluecollector.h>
#include <string.h>	    // memset (in G_VALUE_COLLECT)

// use this for older FFI versions doesn't detect existing functions!
// #define ffi_closure_alloc(x,y) g_malloc(x)

/* one such structure per connected callback */
struct callback_info {
    int handler_ref;		/* reference to the function to call */
    int args_ref;		/* reference to a table with additional args */
    int object_ref;		/* reference to the object: avoids GC */
    lua_State *L;		/* the Lua state this belongs to */
    GSignalQuery query;		/* information about the signal, see below */
};
/* query: signal_id, signal_name, itype, signal_flags, return_type, n_params,
 * param_types */


static void _callback_type_error(lua_State *L, struct callback_info *cbi,
    int is_type, int expected_type)
{
    lua_Debug ar;
    char funcinfo[80];

    // this is the handler
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->handler_ref);
    if (lua_getinfo(L, ">Sn", &ar))
	snprintf(funcinfo, sizeof(funcinfo), " at %s %s(%d): %s",
	    ar.namewhat, ar.short_src, ar.linedefined, ar.name);
    else
	funcinfo[0] = 0;

    luaL_error(L, "%s can't convert return type %s to %s for signal handler "
	"of %s%s", api->msgprefix, lua_typename(L, is_type),
	lua_typename(L, expected_type), cbi->query.signal_name, funcinfo);
}

/**
 * Handle return values from the Lua handler to pass back to Gtk.  Not many
 * different types are supported - but I think no others are actually used.
 *
 * @param L  lua_State
 * @param return_type  The GType of the expected return value
 * @param cbi  callback_info of this signal
 * @return  An integer to return to Gtk.
 */
static int _callback_return_value(lua_State *L, int return_type,
    struct callback_info *cbi)
{
    int val = 0, type = lua_type(L, -1);

    // NIL is always OK and is zero.
    if (type == LUA_TNIL)
	return 0;

    switch (return_type) {
	case G_TYPE_NONE:
	    break;

	case G_TYPE_BOOLEAN:
	    if (type != LUA_TBOOLEAN)
		_callback_type_error(L, cbi, type, LUA_TBOOLEAN);
	    val = lua_toboolean(L, -1);
	    break;
	
	case G_TYPE_INT:
	    if (type != LUA_TNUMBER)
		_callback_type_error(L, cbi, type, LUA_TNUMBER);
	    val = lua_tointeger(L, -1);
	    break;
	
	default:
	    luaL_error(L, "%s unhandled callback return type %d of callback %s",
		api->msgprefix, return_type, cbi->query.signal_name);
    }

    return val;
}


#ifdef LUAGNOME_amd64

// must be static so the position independent code logic doesn't mess it up.
static int _callback_amd64(void *data, ...);

/*-
 * Workaround for AMD64.  _callback is not called as variadic function, which
 * would imply setting %rax to the number of floating point arguments, but
 * instead through a marshaller, which leaves %rax undefined.  This leads to
 * segfault in the boilerplate code of _callback.
 *
 * To fix this, set %rax to a valid value (between 0 and 8), and jump to
 * _callback.
 *
 * AMD64 calling convention for variadic functions:
 * http://www.technovelty.org/code/linux/abi.html
 * http://www.x86-64.org/documentation/
 */
asm(
".text\n"
"	.type _callback_amd64, @function\n"
"_callback_amd64:\n"
"	movq	$1, %rax\n"
"	jmp	_callback\n"
"	.size	_callback_amd64, . - _callback_amd64\n"
);

#endif

/**
 * Handler for Gtk signal callbacks.  Find the proper Lua callback, build the
 * parameters, call, and optionally return something to Gtk.  This runs in the
 * lua_State that was used to call glib_connect with, and therefore probably
 * uses the stack of the main function, which mustn't be modified.
 *
 * @param data   a pointer to a struct callback_info
 * @param ...    Variable arguments, and finally the object pointer.
 * @return       A value to return to Gtk.
 */
static int _callback(void *data, ...)
{
    va_list ap;
    int i, arg_cnt, return_count, extra_args=0;
    struct callback_info *cbi = (struct callback_info*) data;
    lua_State *L = cbi->L;
    int stack_top = lua_gettop(L);

    /* get the handler function */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->handler_ref);
    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return luaL_error(L, "%s callback handler not found.", api->msgprefix);
    }

    /* first parameter: the object */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->object_ref);
    if (lua_isnil(L, -1)) {
	lua_pop(L, 2);
	return luaL_error(L, "%s callback object not found.", api->msgprefix);
    }
    struct object *w = (struct object*) lua_touserdata(L, -1);

    /* push all the signal arguments to the Lua stack */
    arg_cnt = cbi->query.n_params;

    // retrieve the additional parameters using the stdarg mechanism.
    va_start(ap, data);
    GValue gv = { 0 };
    for (i=0; i<arg_cnt; i++) {
	GType type = cbi->query.param_types[i] & ~G_SIGNAL_TYPE_STATIC_SCOPE;
	gchar *err_msg = NULL;

	g_value_init(&gv, type);
	G_VALUE_COLLECT(&gv, ap, G_VALUE_NOCOPY_CONTENTS, &err_msg);
	if (err_msg)
	    return luaL_error(L, "%s vararg %d failed: %s", api->msgprefix, i+1,
		err_msg);
	api->push_gvalue(L, &gv);
	g_value_unset(&gv);
    }

    /* The object is the last parameter to this function.  The Lua callback
     * gets it as the first parameter, though, so it isn't really used. */
    void *object = va_arg(ap, void*);
    if (object != w->p) {
	fprintf(stderr, "Warning: _callback on different object: %p %p\n",
	    w->p, object);
    }
    va_end(ap);


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

    struct object *delete_o = NULL;

    /* extra hack */
    if (!strcmp(cbi->query.signal_name, "query-tooltip"))
	// argument #5 is the GtkTooltip, which must be released NOW.
	delete_o = (struct object*) lua_touserdata(L, stack_top + 6);

    /* Call the callback! */
    lua_call(L, arg_cnt+extra_args+1, return_count);

    /* Determine the return value (default is zero) */
    int val = _callback_return_value(L, return_type, cbi);

    if (delete_o && !delete_o->is_deleted) {
	// XXX this is lg_dec_refcount
	struct object_type *ot = api->get_object_type(L, delete_o);
	if (ot)
	    ot->handler(delete_o, WIDGET_UNREF, 0);
	api->invalidate_object(L, delete_o);
    }

    /* make sure the stack is back to the original state */
    lua_settop(L, stack_top);

    return val;
}

#ifdef LUAGNOME_amd64

// Avoid a warning about _callback being defined, but not used.  When
// optimizing, avoids the function being omitted altogether.
void dummy() {
    _callback(NULL);
}
 #warning Please ignore the message about _callback_amd64.
 #define _callback _callback_amd64
#endif

/**
 * Free memory on signal handler disconnection.
 *
 * The struct callback_info contains references to entries in the registry
 * of the Lua state.  They must be unreferenced, then the structure itself
 * is freed.
 *
 * XXX the Lua state might not exist anymore?
 */
static void _free_callback_info(gpointer data, GClosure *closure)
{
    // data is a struct callback_info.  It contains references, free them.
    // see glib_connect().
    struct callback_info *cb_info = (struct callback_info*) data;

    // remove the reference to the callback function (closure) & the object
    luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->handler_ref);
    luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->object_ref);

    // remove the reference to the table with the extra arguments
    if (cb_info->args_ref)
	luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->args_ref);

    // Is this required? I guess so.  See
    // glib/gobject/gclosure.c:g_closure_unref() - closure->data is not
    // freed there.
    g_slice_free(struct callback_info, cb_info);
}


/**
 * @class module
 * @name gtk
 */

/**
 * Connect a signal to a Lua function.
 *
 * @name connect
 * @luaparam object
 * @luaparam signal_name  Name of the signal, like "clicked"
 * @luaparam handler  A Lua function (the callback)
 * @luaparam ...  (optional) extra parameters to the callback
 *
 * @return  The handler id, which can be used to disconnect the signal.
 */
static int _connect(lua_State *L, GConnectFlags connect_flags)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TSTRING);
    luaL_checktype(L, 3, LUA_TFUNCTION);

    int stack_top, i;
    gulong handler_id;
    struct callback_info *cb_info;
    guint signal_id;

    // get the object
    struct object *w = (struct object*) lua_touserdata(L, 1);
    if (!w || !w->p)
	luaL_error(L, "trying to connect to a NULL object\n");

    // determine the signal
    const char *signame = lua_tostring(L, 2);
    signal_id = g_signal_lookup(signame, G_OBJECT_TYPE(w->p));
    if (!signal_id)
	luaL_error(L, "Can't find signal %s::%s\n", api->get_object_name(w),
	    signame);

    cb_info = g_slice_new(struct callback_info);
    cb_info->L = L;
    g_signal_query(signal_id, &cb_info->query);

    if (cb_info->query.signal_id != signal_id) {
	g_slice_free(struct callback_info, cb_info);
	luaL_error(L, "invalid signal ID %d for signal %s::%s\n",
	    signal_id, api->get_object_name(w), signame);
    }

    /* stack: object - signame - func - .... */

    /* The callback is either a function, or a table with the function and
     * additional paramters.
     */

    // make a reference to the function, and store it.
    stack_top = lua_gettop(L);
    lua_pushvalue(L, 3);
    cb_info->handler_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    // make a reference to the object - to avoid it being garbage collected.
    lua_pushvalue(L, 1);
    cb_info->object_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    // if there are more arguments, put them into a table, and store a
    // reference to it.  When called just with NIL as "more arguments", ignore
    // that.
    if (stack_top > 3 && (stack_top != 4 || lua_type(L, 4) != LUA_TNIL)) {
	lua_newtable(L);
	for (i=4; i<=stack_top; i++) {
	    lua_pushvalue(L, i);
	    lua_rawseti(L, -2, i - 3);	// [1] etc. are the parameters
	}
	cb_info->args_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    } else
	cb_info->args_ref = 0;

    handler_id = g_signal_connect_data(w->p, signame,
	(GCallback) _callback, cb_info, _free_callback_info,
	G_CONNECT_SWAPPED | connect_flags);

    lua_pushnumber(L, handler_id);

    return 1;
}

int glib_connect(lua_State *L)
{
    return _connect(L, 0);
}

int glib_connect_after(lua_State *L)
{
    return _connect(L, G_CONNECT_AFTER);

}


/**
 * Disconnect a signal handler from a given object.
 *
 * @name disconnect
 * @luaparam object  The object to disconnect a handler for
 * @luaparam handler_id  The handler ID of the connection, as returned from
 *   the connect function.
 */
int glib_disconnect(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TNUMBER);

    struct object *w = (struct object*) lua_touserdata(L, 1);
    gulong handler_id = lua_tointeger(L, 2);
    g_signal_handler_disconnect(w->p, handler_id);

    return 0;
}


