/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * This code handles callbacks from Gtk to Lua.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * Exported functions:
 *   luagtk_connect
 *   luagtk_disconnect
 *   luagtk_make_closure
 */

/**
 * @class module
 * @name gtk_internal.callback
 * @description Handle callbacks from Gtk to Lua.
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_check*, luaL_ref/unref
#include <stdarg.h>
#include <gobject/gvaluecollector.h>
#include <string.h>	    // memset (in G_VALUE_COLLECT)
#include "luagtk_ffi.h"

// use this for older FFI versions doesn't detect existing functions!
// #define ffi_closure_alloc(x,y) g_malloc(x)

/* one such structure per connected callback */
struct callback_info {
    int handler_ref;		/* reference to the function to call */
    int args_ref;		/* reference to a table with additional args */
    int widget_ref;		/* reference to the widget: avoids GC */
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
	"of %s%s", msgprefix, lua_typename(L, is_type),
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
		msgprefix, return_type, cbi->query.signal_name);
    }

    return val;
}


#ifdef LUAGTK_linux_amd64

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
 * lua_State that was used to call luagtk_connect with, and therefore probably
 * uses the stack of the main function, which mustn't be modified.
 *
 * @param data   a pointer to a struct callback_info
 * @param ...    Variable arguments, and finally the widget pointer.
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

    /* first parameter: the widget */
    lua_rawgeti(L, LUA_REGISTRYINDEX, cbi->widget_ref);
    struct widget *w = (struct widget*) lua_topointer(L, -1);

    /* push all the signal arguments to the Lua stack */
    arg_cnt = cbi->query.n_params;

    // retrieve the additional parameters using the stdarg mechanism.
    va_start(ap, data);
    for (i=0; i<arg_cnt; i++) {
	GType type = cbi->query.param_types[i] & ~G_SIGNAL_TYPE_STATIC_SCOPE;
	gchar *err_msg = NULL;
	GValue gv;
	memset(&gv, 0, sizeof(gv));

	g_value_init(&gv, type);
	G_VALUE_COLLECT(&gv, ap, G_VALUE_NOCOPY_CONTENTS, &err_msg);
	if (err_msg)
	    return luaL_error(L, "[gtk] vararg %d failed: %s", i+1, err_msg);
	luagtk_push_gvalue(L, &gv);
    }

    /* The widget is the last parameter to this function.  The Lua callback
     * gets it as the first parameter, though, so it isn't really used. */
    void *widget = va_arg(ap, void*);
    if (widget != w->p) {
	fprintf(stderr, "Warning: _callback on different widget: %p %p\n",
	    w->p, widget);
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

    /* Call the callback! */
    lua_call(L, arg_cnt+extra_args+1, return_count);

    /* Determine the return value (default is zero) */
    int val = _callback_return_value(L, return_type, cbi);

    /* make sure the stack is back to the original state */
    lua_settop(L, stack_top);

    return val;
}

#ifdef LUAGTK_linux_amd64

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
    // see luagtk_connect().
    struct callback_info *cb_info = (struct callback_info*) data;

    // remove the reference to the callback function (closure) & the widget
    luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->handler_ref);
    luaL_unref(cb_info->L, LUA_REGISTRYINDEX, cb_info->widget_ref);

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
 * @luaparam widget
 * @luaparam signal_name  Name of the signal, like "clicked"
 * @luaparam handler  A Lua function (the callback)
 * @luaparam ...  (optional) extra parameters to the callback
 *
 * @return  The handler id, which can be used to disconnect the signal.
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
    struct widget *w = (struct widget*) lua_topointer(L, 1);
    if (!w || !w->p)
	luaL_error(L, "trying to connect to a NULL widget\n");

    // determine the signal
    const char *signame = lua_tostring(L, 2);
    signal_id = g_signal_lookup(signame, G_OBJECT_TYPE(w->p));
    if (!signal_id)
	luaL_error(L, "Can't find signal %s::%s\n", WIDGET_NAME(w), signame);

    cb_info = g_slice_new(struct callback_info);
    cb_info->L = L;
    g_signal_query(signal_id, &cb_info->query);

    if (cb_info->query.signal_id != signal_id) {
	g_slice_free(struct callback_info, cb_info);
	luaL_error(L, "invalid signal ID %d for signal %s::%s\n",
	    signal_id, WIDGET_NAME(w), signame);
    }

    /* stack: widget - signame - func - .... */

    /* The callback is either a function, or a table with the function and
     * additional paramters.
     */

    // make a reference to the function, and store it.
    stack_top = lua_gettop(L);
    lua_pushvalue(L, 3);
    cb_info->handler_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    // make a reference to the widget - to avoid it being garbage collected.
    lua_pushvalue(L, 1);
    cb_info->widget_ref = luaL_ref(L, LUA_REGISTRYINDEX);

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
	G_CONNECT_SWAPPED);

    lua_pushnumber(L, handler_id);

    return 1;
}


/**
 * Disconnect a signal handler from a given widget.
 *
 * @name disconnect
 * @luaparam widget  The widget to disconnect a handler for
 * @luaparam handler_id  The handler ID of the connection, as returned from
 *   the connect function.
 */
int luagtk_disconnect(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TNUMBER);

    struct widget *w = (struct widget*) lua_topointer(L, 1);
    gulong handler_id = lua_tointeger(L, 2);
    g_signal_handler_disconnect(w->p, handler_id);

    return 0;
}


struct callback {
    lua_State *L;
    int func_ref;
    unsigned const char *sig;
};


/**
 * Call the appropriate function to convert the return value of the Lua
 * function to a FFI value.
 *
 * @param value  A Lua value of arbitrary type.
 * @param ar  A struct argconv_t
 */
static int _convert_retval(lua_State *L)
{
    struct argconv_t *ar = (struct argconv_t*) lua_topointer(L, 2);
    int idx = ar->arg_type->lua2ffi_idx;
    ffi_type_lua2ffi[idx](ar);
    return 0;
}


/**
 * Call the Lua function from C, passing the required parameters.
 */
static void closure_handler(ffi_cif *cif, void *retval, void **args,
    void *userdata)
{
    struct callback *cb = (struct callback*) userdata;
    lua_State *L = cb->L;
    int top = lua_gettop(L);

    // get the callback
    lua_rawgeti(L, LUA_REGISTRYINDEX, cb->func_ref);

    struct argconv_t ar;
    ar.L = L;
    ar.ci = NULL;
    ar.func_arg_nr = 0;	    // make ffi2lua_xxx() think it's always a retval

    const unsigned char *sig = cb->sig;
    const unsigned char *sig_end = sig + 1 + *sig;
    int arg_nr;
    sig++;

    // push the arguments to the Lua stack
    for (arg_nr=0; sig < sig_end; arg_nr ++) {
	ar.type_idx = get_next_argument(&sig);
	if (arg_nr == 0)    // skip retval
	    continue;
	ar.type = type_list + ar.type_idx;
	ar.ffi_type_nr = ar.type->fundamental_id;
	ar.arg_type = &ffi_type_map[ar.ffi_type_nr];
	int idx = ar.arg_type->ffi2lua_idx;
	if (idx) {
	    ar.index = arg_nr;
	    ar.arg = (union gtk_arg_types*) args[arg_nr - 1];
	    ar.lua_type = lua_type(L, ar.index);
	    ffi_type_ffi2lua[idx](&ar);
	} else
	    luaL_error(L, "%s unhandled argument type %s in closure",
		msgprefix, FTYPE_NAME(ar.arg_type));
    }

    int arg_cnt = lua_gettop(L) - top - 1;

    // call the lua function, expect one return value
    lua_call(L, arg_cnt, 1);

    // stack: [top+1]=return value
    // Convert the result to ffi, set *retval
    {
	struct argconv_t ar;
	int idx;

	sig = cb->sig + 1;
	ar.type_idx = get_next_argument(&sig);
	ar.type = type_list + ar.type_idx;
	ar.arg_type = ffi_type_map + ar.type->fundamental_id;

	// if index is 0, no lua2ffi function is defined for this type.
	idx = ar.arg_type->lua2ffi_idx;
	if (idx) {
	    ar.ci = NULL;
	    ar.L = L;
	    ar.arg = (union gtk_arg_types*) retval;
	    ar.lua_type = lua_type(L, top + 1);
	    ar.index = 1;
	    lua_pushcfunction(L, _convert_retval);
	    lua_pushvalue(L, top + 1);
	    lua_pushlightuserdata(L, &ar);
	    int rc = lua_pcall(L, 2, 0, 0);
	    if (rc) {
		luaL_error(L, "failed to convert the callback's return value: "
		    "%s", lua_tostring(L, -1));
	    }
	}
    }

    // clean the stack
    lua_settop(L, top);
}


/**
 * Initialize the arg_types array with the types taken from the function's
 * signature.  If called with arg_types == NULL, just count the number of args.
 *
 * The first byte is the length of the following data.
 */
static int set_ffi_types(const unsigned char *sig, ffi_type **arg_types)
{
    int type_idx, arg_nr=0;
    const unsigned char *sig_end = sig + 1 + *sig;
    sig ++;

    while (sig < sig_end) {
	type_idx = get_next_argument(&sig);
	if (arg_types) {
	    const struct type_info *ti = type_list + type_idx;
	    int idx = ffi_type_map[ti->fundamental_id].ffi_type_idx;
	    arg_types[arg_nr] = LUAGTK_FFI_TYPE(idx);
	}
	arg_nr ++;
    }

    return arg_nr;
}


/**
 * Create a C closure for a Lua function.
 *
 * @param L  Lua state
 * @param index  Stack position of a Lua function
 * @param signature  Pointer to a binary spec of the function parameters
 * @return  Pointer to a new closure
 */
void *luagtk_make_closure(lua_State *L, int index,
    const unsigned char *signature)
{
    ffi_closure *closure;
    ffi_cif *cif;
    void *code;
    int arg_count;
    ffi_type **arg_types;
    struct callback *cb;

    closure = (ffi_closure*) ffi_closure_alloc(sizeof(*closure), &code);

    // The count includes the return value, and therefore must be at least 1.
    arg_count = set_ffi_types(signature, NULL);
    if (arg_count <= 0)
	luaL_error(L, "luagtk_make_closure: invalid signature");

    // allocate and fill ffi_cif
    int bytes = sizeof(*cif) + sizeof(*cb) + sizeof(ffi_type*) * arg_count;
    cif = (ffi_cif*) g_malloc(bytes);
    cb = (struct callback*) (cif + 1);
    arg_types = (ffi_type**) (cb + 1);

    cb->L = L;
    lua_pushvalue(L, index);
    cb->func_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    cb->sig = signature;

    // fill arg_types (including the return value)0
    set_ffi_types(signature, arg_types);

    ffi_prep_cif(cif, FFI_DEFAULT_ABI, arg_count-1, arg_types[0], arg_types+1);

    ffi_prep_closure_loc(closure, cif, closure_handler, (void*) cb, code);

    // It would be logical to always call "code", but sometimes "closure" must
    // be called instead.  The configure script determines which one works.
#ifdef LUAGTK_FFI_CODE
    return (void*) code;
#else
 #ifdef LUAGTK_FFI_CLOSURE
    return (void*) closure;
 #else
    #error Please define one of LUAGTK_FFI_{CODE,CLOSURE}.
 #endif
#endif
}

