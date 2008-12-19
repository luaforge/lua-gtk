/* vim:sw=4:sts=4
 * Lua Gtk2 binding.
 * Handle channels, which requires a few wrappers for glib functions.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * Exported symbols:
 *   glib_init_channel
 */

/**
 * @class module
 * @name gtk_internal.channel
 */

#include "module.h"
#include "override.h"
#include <glib/giochannel.h>	// GIOChannel structure
#include <string.h>		// strcmp

/*-
 * When g_io_add_watch is called, a Lua stack has to be provided.  This must
 * be the global, or initial, Lua stack and not of some coroutine.  Because
 * new watches may be created from within coroutines, the initial Lua stack
 * has to be stored somewhere...
 */
static lua_State *global_lua_state;


/**
 * Check that the given Lua value is a object for a GIOChannel.
 *
 * @return the object; raises a Lua error otherwise.
 */
static GIOChannel *_get_channel(lua_State *L, int index)
{
    luaL_checktype(L, index, LUA_TUSERDATA);
    struct object *o = (struct object*) lua_touserdata(L, index);
    const char *name = api->get_object_name(o);
    if (strcmp(name, "GIOChannel"))
	luaL_error(L, "Argument %d must be a GIOChannel, not %s\n", index,
	    name);

    return (GIOChannel*) o->p;
}

#if 0
/**
 * A numeric argument might be given as an ENUM.  If this is so,
 * extract the value.
 */
static int _get_int_or_enum(lua_State *L, int index)
{
    int type = lua_type(L, index);

    switch (type) {
	case LUA_TNUMBER:
	return lua_tonumber(L, index);

	case LUA_TUSERDATA:;
	    typespec_t ts = { 0 };
	    struct lg_enum_t *e = api->get_constant(L, index, ts, 1);
	    return e->value;
    }

    luaL_error(L, "Expected integer or enum, got a %s\n",
	lua_typename(L, type));
    return 0;
}

// the user_data for g_io_add_watch_full
struct _watch_info {
    lua_State	*L;
    int		func_ref;
    int		data_ref;
    int		handle;     // for debugging
    GIOChannel	*gio;	    // for debugging in _watch_destroy_notify
};
#endif

#if 0

/**
 * This is the handler for channel related events.  Call the appropriates
 * Lua callback with the prototype of GIOFunc, it is passed the following
 * arguments:
 *
 *  [1]  GIOChannel
 *  [2]  The condition that led to the activation of the callback
 *  [3]  The data that was passed to g_io_add_watch
 *
 * It is expected to return a boolean (true=keep listening for this event)
 *
 * Note: this runs within the initial Lua state.  Maybe a new state would
 * be better, i.e. in l_gtk_init luaL_newstate().  This might lead to other
 * problems, like variables not visible from within the handler.
 *
 * So, all I can do now is take care that the stack of the global Lua state
 * isn't modified - well now this would lead to strange bugs...
 *
 * @param gio  The I/O channel that was signaled
 * @param cond  Condition that caused the callback
 * @param data  a struct _watch_info
 * @return  true if to continue watching for this event, false otherwise.
 */
static gboolean _watch_handler(GIOChannel *gio, GIOCondition cond,
	gpointer data)
{
    struct _watch_info *wi = (struct _watch_info*) data;
    lua_State *L = wi->L;
    int stack_top;
    gboolean again = 0;

    if (gio != wi->gio) {
	printf("%s _watch_handler: GIOChannel mismatch %p != %p\n",
	    api->msgprefix, gio, wi->gio);
	return 0;
    }

    stack_top = lua_gettop(L);

    // [0] the function to call
    lua_rawgeti(L, LUA_REGISTRYINDEX, wi->func_ref);
    if (lua_type(L, -1) != LUA_TFUNCTION) {
	printf("%s _watch_handler: invalid function ref %d\n",
	    api->msgprefix, wi->func_ref);
	goto ex;
    }

    // [1] the GIOChannel; this object should already exist.  Anyway, it's not
    // new.
    typespec_t ts = api->find_struct(L, thismodule, "GIOChannel", 1);
    api->get_object(L, gio, ts, FLAG_NOT_NEW_OBJECT);
    if (lua_isnil(L, -1)) {
	printf("%s watch_handler: invalid GIOChannel (first argument)\n",
	    api->msgprefix);
	goto ex;
    }

    // [2] the condition is FLAGS of type GIOCondition
    ts = api->find_struct(L, thismodule, "GIOCondition", 0);
    if (!ts.value)
	luaL_error(L, "internal error: enum GIOCondition not known.");
    api->push_constant(L, ts, cond);

    // [3] the extra data
    lua_rawgeti(L, LUA_REGISTRYINDEX, wi->data_ref);

    lua_call(L, 3, 1);
    again = lua_toboolean(L, -1);

ex:
    lua_settop(L, stack_top);

    /* The result of the callback is a boolean.  If it is TRUE, continue to
     * watch this event, otherwise stop doing so.
     *
     * NOTE: if you return FALSE, and do not call g_source_remove for this
     * watch, then the gtk main loop goes into 100% busy mode, while the GUI is
     * still being responsive.  Try to avoid this! ;)
     */
    return again;
}

#endif

#if 0
/**
 * Clean up the data of a watch.
 *
 * Some callback information is stored in the registry of the given Lua state;
 * remove it, then free the struct _watch_info.
 *
 * @param data  A struct _watch_info.
 */
static void _watch_destroy_notify(gpointer data)
{
    struct _watch_info *wi = (struct _watch_info*) data;
    lua_State *L = wi->L;
    /*
    printf("_watch_destroy_notify for GIOChannel %p, handle %d\n", wi->gio,
	wi->handle);
    */
    luaL_unref(L, LUA_REGISTRYINDEX, wi->func_ref);
    luaL_unref(L, LUA_REGISTRYINDEX, wi->data_ref);
    g_slice_free(struct _watch_info, wi);
}
#endif


/**
 * Build a response for the Lua caller about the result of a Channel IO
 * operation.  Should the OK response not be a simple boolean, handle this
 * instead of calling this function.
 *
 * @param L  lua_State
 * @param status  I/O status of the operation
 * @param error  Pointer to a GError structure with further information
 * @param bytes_transferred  Bytes transferred (and discarded) so far
 * @return 3 items on the Lua stack.
 */
static int _handle_channel_status(lua_State *L, GIOStatus status, GError *error,
    int bytes_transferred)
{
    switch (status) {
	case G_IO_STATUS_NORMAL:
	    lua_pushboolean(L, 1);
	    lua_pushliteral(L, "ok");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;

	case G_IO_STATUS_AGAIN:
	    lua_pushnil(L);
	    lua_pushliteral(L, "timeout");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
	
	case G_IO_STATUS_ERROR:
	    lua_pushnil(L);
	    lua_pushstring(L, error->message);
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
	
	case G_IO_STATUS_EOF:
	    lua_pushnil(L);
	    lua_pushliteral(L, "connection lost");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
    }

    /* not reached */
    return 0;
}



/**
 * Add a new watch on a GIOChannel to the main loop.  The callback function
 * will be called in the context of the main thread.  Information is stored in
 * the main thread's environment (i.e. the environment of the module gtk).
 *
 * The callback can't be run in the thread context of the caller, because
 * this thread might terminate, leaving L pointing nowhere.  Also, it can't
 * be run in the thread that will handle the callback (a thread can't resume
 * itself).
 * 
 * @name  g_io_add_watch
 * @luaparam    GIOChannel (object)
 * @luaparam    conditions (integer, or ENUM)
 * @luaparam    callback (Lua function)
 * @luaparam    thread the callback runs in
 * @luareturn	ID of the new watch; this can be used to remove it, see
 *		g_source_remove().
 */
#if 0
static int l_g_io_add_watch(lua_State *L)
{
    GIOChannel *channel = _get_channel(L, 1);
    GIOCondition condition = _get_int_or_enum(L, 2);
    luaL_checktype(L, 3, LUA_TFUNCTION);
    luaL_checkany(L, 4);
    lua_settop(L, 4);	    // ignore extra args

    struct _watch_info *wi = g_slice_new(struct _watch_info);

    wi->L = global_lua_state;
    wi->gio = channel;

    // If the data is not in the global thread, move the arguments there.
    if (wi->L != L)
	lua_xmove(L, wi->L, 2);

    wi->data_ref = luaL_ref(wi->L, LUA_REGISTRYINDEX);
    wi->func_ref = luaL_ref(wi->L, LUA_REGISTRYINDEX);

    // use a lower priority, so that the GUI remains fully interactive.
    // Note: the inverse of this is g_source_remove; it has no
    // special wrapper, but can be called directly from Lua.
    int id = g_io_add_watch_full(channel, 3, condition, _watch_handler,
	(gpointer) wi, _watch_destroy_notify);
    wi->handle = id;
    lua_pushinteger(L, id);

    return 1;
}
#endif


/**
 * Read data from the channel up to a given maximum length.
 *
 * @name g_io_channel_read_chars
 * @luaparam channel
 * @luaparam maxbytes
 * @luareturn  The string read, or nil on error
 * @luareturn  on error, a message
 * @luareturn  on error, number of bytes read (and discarded)
 */
static int l_g_io_channel_read_chars(lua_State *L)
{
    GIOStatus status;
    GIOChannel *channel = _get_channel(L, 1);
    gsize buf_size = luaL_checkint(L, 2);
    gchar *buf = alloca(buf_size);
    gsize bytes_read;
    GError *error = NULL;

    status = g_io_channel_read_chars(channel, buf, buf_size, &bytes_read,
	&error);

    if (status == G_IO_STATUS_NORMAL) {
	lua_pushlstring(L, buf, bytes_read);
	return 1;
    }

    return _handle_channel_status(L, status, error, bytes_read);
}


/**
 * Read the next line from the channel.  Newlines at the end are chopped off
 * automatically.
 *
 * The channel has to be buffered in order for this to work.
 *
 * @name g_io_channel_read_line
 * @luaparam channel
 * @luareturn string, or nil, error message, bytes transferred
 */
static int l_g_io_channel_read_line(lua_State *L)
{
    GIOChannel *channel = _get_channel(L, 1);
    gchar *str = NULL;
    gsize length=0, terminator_pos=0;
    GError *error = NULL;

    GIOStatus status = g_io_channel_read_line(channel, &str, &length,
	&terminator_pos, &error);

    if (status == G_IO_STATUS_NORMAL) {
	if (terminator_pos)
	    length = terminator_pos;
	while (length > 0 && str[length-1] < ' ')
	    length --;
	lua_pushlstring(L, str, length);
	g_free(str);
	return 1;
    }

    return _handle_channel_status(L, status, error, 0);
}

/**
 * Write a buffer to the given IO Channel.
 *
 * @name g_io_channel_write_chars
 * @luaparam channel
 * @luaparam buf  The string to write
 * @luareturn  true on success, else nil
 * @luareturn  on error, a message
 */
static int l_g_io_channel_write_chars(lua_State *L)
{
    GError *error = NULL;
    gsize count, bytes_written;
    GIOChannel *channel = _get_channel(L, 1);
    const gchar *buf = lua_tolstring(L, 2, &count);
    GIOStatus status = g_io_channel_write_chars(channel, buf, count,
	&bytes_written, &error);
    /*
    printf("g_io_channel_write_chars: bytes written: %d/%d\n",
	bytes_written, count);
    */

    // if not all bytes were written, treat this as IO timeout.
    if (status == G_IO_STATUS_NORMAL && bytes_written < count)
	status = G_IO_STATUS_AGAIN;
    return _handle_channel_status(L, status, error, bytes_written);
}


/**
 * Flush the IO Channel.
 *
 * @name g_io_channel_flush
 * @luaparam channel
 */
static int l_g_io_channel_flush(lua_State *L)
{
    GError *error = NULL;
    GIOChannel *channel = _get_channel(L, 1);
    GIOStatus status = g_io_channel_flush(channel, &error);
    return _handle_channel_status(L, status, error, 0);
}

static const luaL_reg _channel_reg[] = {
    {"g_io_channel_read_chars", l_g_io_channel_read_chars },
    {"g_io_channel_read_line", l_g_io_channel_read_line },
    {"g_io_channel_write_chars", l_g_io_channel_write_chars },
    {"g_io_channel_flush", l_g_io_channel_flush },
//    {"g_io_add_watch", l_g_io_add_watch },
    { NULL, NULL }
};


static int _channel_handler(struct object *w, object_op op, int data)
{
    switch (op) {
	case WIDGET_SCORE:
	    return strcmp(api->get_object_name(w), "GIOChannel") ? 0 : 100;

	case WIDGET_GET_REFCOUNT:
	    return ((GIOChannel*) w->p)->ref_count;

	case WIDGET_REF:
	    // GIOChannels are created with a refcount of 1.  Only add more
	    // refs if this is not a new object.
	    if (!data /* is_new */)
		g_io_channel_ref((GIOChannel*) w->p);
	    /*
	    fprintf(stderr, "%p %p channel ref - refcnt now %d\n", w, w->p,
		((GIOChannel*)w->p)->ref_count);
	    */
	    break;
	
	case WIDGET_UNREF:;
	    GIOChannel *ioc = (GIOChannel*) w->p;
	    /*
	    fprintf(stderr, "%p %p channel unref - refcnt %d.\n",
		w, w->p, ioc->ref_count);
	    */

	    // The ref count should not be zero, of course, so this is just
	    // a precaution.
	    if (ioc->ref_count > 0)
		g_io_channel_unref(ioc);
	    w->p = NULL;
	    break;
    }

    return 0;
}


void glib_init_channel(lua_State *L)
{
    global_lua_state = L;
    luaL_register(L, NULL, _channel_reg);
    api->register_object_type("channel", _channel_handler);
}


