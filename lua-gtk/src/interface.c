/* vim:sw=4:sts=4
 * Lua Gtk2 binding.
 *
 */

#include "luagtk.h"
#include <lauxlib.h>
#include <string.h>	    // strcpy
// #include <malloc.h>
#include <stdlib.h>	    // strtol

int _make_gvalue(lua_State *L, GValue *gv, int type_nr, int index);

/**
 * When g_io_add_watch is called, a Lua stack has to be provided.  This must
 * be the global, or initial, Lua stack and not of some coroutine.  Because
 * new watches may be created from within coroutines, the initial Lua stack
 * has to be stored somewhere...
 */
const lua_State *global_lua_state;


/**
 * A method has been found and should now be called.
 * input stack: parameters to the function
 * upvalues: the name of the function - func - args_info
 */
static int _gtk_call_wrapper(lua_State *L)
{
    struct func_info fi;
    fi.name = (char*) lua_tostring(L, lua_upvalueindex(1));
    fi.func = (void*) lua_topointer(L, lua_upvalueindex(2));
    fi.args_info = lua_topointer(L, lua_upvalueindex(3));
    fi.args_len = lua_tointeger(L, lua_upvalueindex(4));
    return do_call(L, &fi, 1);
}


/**
 * Handle accesses of "gtk.xxx", where xxx may be any gtk function, used mainly
 * for gtk.xxx_new(), and ENUMs.
 *
 * input stack: 1=table, 2=value
 * output: either an integer (for ENUMs) or a closure (for functions).
 */
static int l_gtk_lookup(lua_State *L)
{
    const char *s = luaL_checkstring(L, 2);
    struct func_info fi;
    char func_name[50];

    if (!s) {
	printf("%s attempt to lookup a NULL string\n", msgprefix);
	dump_stack(L, 1);
	return 0;
    }

    /* if it starts with an uppercase letter, it's probably an ENUM. */
    if (s[0] >= 'A' && s[0] <= 'Z') {
	int val;
	if (find_enum(s, &val)) {
	    lua_pushnumber(L, val);
	    return 1;
	}
    }

    strcpy(func_name, s);
    if (!find_func(func_name, &fi)) {
	sprintf(func_name, "gtk_%s", s);
	if (!find_func(func_name, &fi)) {
	    printf("%s attribute or method not found: %s\n", msgprefix, s);
	    return 0;
	}
    }

    /* A function has been found, so return a closure that can call it. */
    lua_pushstring(L, func_name);
    lua_pushlightuserdata(L, fi.func);
    lua_pushlightuserdata(L, (void*) fi.args_info);
    lua_pushinteger(L, fi.args_len);
    lua_pushcclosure(L, _gtk_call_wrapper, 4);
    return 1;
}

/**
 * Call any gtk function through this catch-all API.
 * Stack: 1=name of the function, 2 and up=arguments to the function
 */
static int l_call(lua_State *L)
{
    const char *func_name = luaL_checkstring(L, 1);
    struct func_info fi;

    if (find_func(func_name, &fi)) {
	return do_call(L, &fi, 2);
    }

    printf("%s function %s not found in l_call\n", msgprefix, func_name);
    return 0;
}


/*
 * Allocate a structure, initialize with zero and return.
 * This is NOT intended for widgets or structures that have specialized
 * creator functions, like gtk_window_new and such.  Use it for simple
 * structures like GtkTreeIter.
 *
 * The widget is, as usual, a Lua wrapper in the form of a light user data,
 * containing a pointer to the actual widget.  I used to allocate just one
 * light userdata big enough for both the wrapper and the widget, but
 * sometimes a special free function must be called, like gtk_tree_iter_free.
 * So, this optimization is not possible.
 *
 * TODO
 * - find out whether a specialized free function exists.  If so, allocate
 *   a separate block of memory for the widget (as it is done now).  Otherwise,
 *   allocate a larger userdata with enough space for the widget.  Do not
 *   call g_free() in the GC function.
 */
static int _allocate_structure(lua_State *L, const char *struct_name)
{
    struct struct_info *si;
    void *p;

    if (!(si=find_struct(struct_name))) {
	printf("%s structure %s not found\n", msgprefix, struct_name);
	return 0;
    }

    /* allocate and initialize the object */
    p = g_malloc(si->struct_size);
    memset(p, 0, si->struct_size);

    /* Make a Lua wrapper for it, push it on the stack.  Note that manage_mem
     * is 1, i.e. call g_free later. */
    get_widget(L, p, si - struct_list, 1);
    return 1;
}




/**
 * Wrapper for _allocate_structure, see there.
 */
static int l_new(lua_State *L)
{
    const char *struct_name = luaL_checkstring(L, 1);
    return _allocate_structure(L, struct_name);
}

/**
 * Connect a signal to a Lua function.
 *
 * input: 1=widget, 2=signal name, 3=lua function, 4... extra parameters
 * output: the handler id, which can be used to disconnect the signal.
 */
static int l_gtk_connect(lua_State *L)
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
static int l_gtk_disconnect(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    luaL_checktype(L, 2, LUA_TNUMBER);

    void *widget = * (void**) lua_topointer(L, 1);
    gulong handler_id = lua_tointeger(L, 2);
    g_signal_handler_disconnect(widget, handler_id);

    return 0;
}

/**
 * Store information about a Gtk widget.
 *
 * The global table gtk.widgets will contain two new entries:
 *   address -> widget
 *   ID -> widget
 */
int luagtk_register_widget(lua_State *L)
{
    lua_getfield(L, LUA_GLOBALSINDEX, "gtk");
    lua_getfield(L, -1, "widgets");

    GtkWidget **p = (GtkWidget**) lua_topointer(L, 1);
    GtkWidget *w = *p;
    lua_pushlightuserdata(L, w);
    lua_pushvalue(L, 1);
    lua_rawset(L, -3);

    return 0;
}


static int l_g_type_from_name(lua_State *L)
{
    const char *s = luaL_checkstring(L, 1);
    int type_nr = _g_type_from_name(s);
    lua_pushnumber(L, type_nr);
    return 1;
}


/**
 * Perform the G_OBJECT_GET_CLASS on an object.
 * Returns a GObjectClass structure, or nil on error.
 */
static int l_g_object_get_class(lua_State *L)
{
    printf("get class.\n");
    GObject *parent = (GObject*) lua_topointer(L, 1);
    printf("  parent is %p\n", parent);
    GObjectClass *c = G_OBJECT_GET_CLASS(parent);
    printf("  class is %p\n", c);
    const struct struct_info *si = find_struct("GObjectClass");
    if (!si) {
	printf("%s ERROR - no info about GObjectClass available.\n", msgprefix);
	return 0;
    }

    // manage_mem is 0, i.e. do not try to g_free(c) later on.
    get_widget(L, c, si - struct_list, 0);
    return 1;
}


#ifdef DEBUG_DUMP_STRUCT
/**
 * Display a structure for debugging purposes.
 *
 * Input: a structure
 */
int l_dump_struct(lua_State *L)
{
    if (!lua_type(L, 1) == LUA_TLIGHTUSERDATA) {
	printf("Object is not light user data\n");
	return 0;
    }

    void **p = (void**) lua_topointer(L, 1);
    unsigned char *obj;

    if (!p) {
	printf("NIL\n");
	return 0;
    }

    obj = *p;
    if (!obj) {
	printf("Object pointing to NULL\n");
	return 0;
    }

    if (!lua_getmetatable(L, 1)) {
	printf("Object doesn't have a metatable.\n");
	return 0;
    }

    lua_pushstring(L, "_struct");
    lua_rawget(L, -2);
    const struct struct_info *si = lua_topointer(L, -1);
    lua_pop(L, 1);
    if (!si) {
	printf("Object has no _struct information!\n");
	return 0;
    }

    /* the structure is OK, dump it */
    const char *name = NAME(si->name_ofs);
    const struct ffi_type_map_t *arg_type;
    const struct struct_elem *se;
    const struct struct_info *si2;
    int i, elem_count;
    elem_count = si[1].elem_start - si[0].elem_start;
    printf("Object at %p, type %s, size %d, elements %d\n", obj, name,
	si->struct_size, elem_count);

    for (i=0; i<elem_count; i++) {
	se = elem_list + si->elem_start + i;
	name = NAME(se->name_ofs);
	printf("  %d %s, size=%d bit", i, name, se->bit_length);
	arg_type = &ffi_type_map[se->type - '0'];
	switch (arg_type->at) {
	    case AT_STRUCT:
		si2 = struct_list + se->type_detail;
		printf(", structure type %s\n",
		    NAME(si2->name_ofs));
		break;

	    case AT_WIDGET:
		printf(", widget\n");
		break;

	    case AT_POINTER:
		printf(", pointer\n");
		break;

	    case AT_STRUCTPTR:;
		const struct struct_info * sub_si = struct_list
		    + se->type_detail;
		const char *sub_name = NAME(sub_si->name_ofs);
		printf(", structpointer to a %s\n", sub_name);
		break;

	    case AT_STRING:;
		gchar **addr = (gchar**) (obj + se->bit_offset/8);
		printf(", value=%s\n", addr ? *addr : "nil");
		break;

	    case AT_LONG:;
		long int v = get_bits(obj, se->bit_offset, se->bit_length);
		printf(", value=%ld\n", v);
		break;

	    default:
		printf(", some value of type %s\n", arg_type->name);
		break;
	}
    }

    return 0;
}
#else
int l_dump_struct(lua_State *L)
{
    return 0;
}
#endif


static int l_dump_stack(lua_State *L)
{
#ifdef DEBUG_DUMP_STACK
    return dump_stack(L, 1);
#endif
}

/**
 * Try to convert the string to a boolean value.
 */
static int _parse_boolean(const char *s)
{
    if (!strcasecmp(s, "true"))
	return 1;
    if (!strcasecmp(s, "false"))
	return 0;
    if (s[1] == 0 && (s[0] == '0' || s[0] == '1'))
	return s[0] - '0';
    printf("%s Can't convert %s to boolean.\n", msgprefix, s);
    return -1;
}

/**
 * Conversion of a string to float.
 *
 * This function doesn't depend on a library function and therefore is
 * immune to locale settings.  I found it unreliable to set/reset the
 * locale for every conversion.
 *
 * It sets *ok to 0 on error, or 1 on success.
 */
static double my_convert_to_double(const char *s, int *ok)
{
    const char *pos = s;
    char c;
    double v = 0;

    /* digits before the decimal point */
    for (;;) {
	c = *pos++;
	if (c == '.' || c == 0)
	    break;
	if (c >= '0' && c <= '9')
	    v = v * 10 + (c - '0');
	else
	    goto conv_error;
    }

    /* more digits after the decimal point? */
    if (c == '.') {
	double div = 10;
	for (;;) {
	    c = *pos++;
	    if (c == 0)
		break;
	    if (c >= '0' && c <= '9') {
		v = v + (c - '0') / div;
		div = div * 10;
	    } else
		goto conv_error;
	}
    }

    *ok = 1;
    return v;

conv_error:
    *ok = 0;
    printf("%s Conversion error to float: %s\n", msgprefix, s);
    return 0;
}


/**
 * Get the floating point number from the given Lua value.  If it is a string,
 * a conversion has to be done.  The decimal point is always ".", disregarding
 * the current locale setting.
 */
static double my_tonumber(lua_State *L, int index, int *ok)
{
    int type = lua_type(L, index);
    *ok = 1;

    if (type == LUA_TNUMBER) {
	return lua_tonumber(L, index);
    }

    if (type == LUA_TSTRING) {
	const char *s = lua_tostring(L, index);
	double dbl = my_convert_to_double(s, ok);
	if (*ok)
	    return dbl;

	printf("%s Can't convert the string %s to double\n", msgprefix, s);
	return 0;
    }

    *ok = 0;
    printf("%s Can't convert Lua type %d to double\n", msgprefix, type);
    return 0;
}
	


int _make_gvalue(lua_State *L, GValue *gv, int type_nr, int index)
{
    int type = lua_type(L, index);
    int ok = 1;
    const char *s;

    // printf("  Making a gvalue for type %d\n", type_nr);

    /* be optimistic that this type can actually be produced. */
    gv->g_type = type_nr;

    /* This is not a fundamental type.  Try to find a base type that can
     * be set.
     */
    if (!G_TYPE_IS_FUNDAMENTAL(type_nr)) {
	while (type_nr) {
	    type_nr = g_type_parent(type_nr);
	    if (!type_nr || type_nr == G_TYPE_ENUM)
		break;
	}
    }

    /* If the type (or a base type) is fundamental, set it now. */
    switch (G_TYPE_FUNDAMENTAL(type_nr)) {

	case G_TYPE_BOOLEAN:
	    if (type == LUA_TBOOLEAN)
		gv->data[0].v_uint = lua_toboolean(L, index) ? 1: 0;
	    else if (type == LUA_TSTRING) {
		gv->data[0].v_int = _parse_boolean(lua_tostring(L, index));
		if (gv->data[0].v_int < 0)
		    return 0;
	    } else {
		printf("%s can't coerce Lua type %d to boolean.\n",
		    msgprefix, type);
		return 0;
	    }
		
	    break;

	case G_TYPE_INT:
	case G_TYPE_UINT:
	case G_TYPE_LONG:
	case G_TYPE_INT64:
	case G_TYPE_UINT64:
	    if (type == LUA_TNUMBER)
		gv->data[0].v_uint = lua_tointeger(L, index);
	    else if (type == LUA_TSTRING) {
		char *endptr;
		s = lua_tostring(L, index);
		gv->data[0].v_uint = strtol(s, &endptr, 0);
		if (*endptr) {
		    /* special case: a single character can be converted
		     * to integer; it is the ASCII code. */
		    if (s[1] == 0)
			gv->data[0].v_uint = s[0];
		    else {
			printf("%s can't convert %s to integer\n", msgprefix,
			    s);
			return 0;
		    }
		}
	    }
	    break;

	/* if it is an ENUM, use numbers directly, and convert strings */
	case G_TYPE_ENUM:
	    switch (type) {
		case LUA_TSTRING:;
		    const char *s = lua_tostring(L, index);
		    gv->data[0].v_int = 0;
		    if (!find_enum(s, &gv->data[0].v_int))
			printf("%s ENUM %s not found, using zero.\n",
			    msgprefix, s);
		    break;

		case LUA_TNUMBER:
		    gv->data[0].v_int = lua_tointeger(L, index);
		    break;

		default:
		    printf("%s Can't convert Lua type %d to enum.\n",
			msgprefix, type);
		    return 0;
	    }
		    
	    break;
	
	case G_TYPE_STRING:
	    // XXX this is problematic.  The string this points to may
	    // be freed!
	    // printf("making a GValue string\n");
	    // gv->data[0].v_pointer = strdup( (char*) lua_tostring(L, index) );
	    gv->data[0].v_pointer = (char*) lua_tostring(L, index);
	    break;
	
	case G_TYPE_FLOAT:
	    gv->data[0].v_float = my_tonumber(L, index, &ok);
	    break;
	
	case G_TYPE_DOUBLE:
	    gv->data[0].v_double = my_tonumber(L, index, &ok);
	    break;

	default:
	    printf("%s make_gvalue type %d not supported\n",
		msgprefix, (int) G_TYPE_FUNDAMENTAL(type_nr));
	    ok = 0;
    }

    return ok;
}


/**
 * This is the handler for channel related events.  Call the appropriates
 * Lua callback.
 */
static gboolean watch_handler(GIOChannel *gio, GIOCondition cond, gpointer data)
{
    lua_State *L = data;
    int stack_top;
    gboolean again;

    stack_top = lua_gettop(L);

    /* use the address of the GIOChannel as key to find the info table. */
    lua_rawgeti(L, LUA_ENVIRONINDEX, (int) gio);
    if (!lua_istable(L, -1)) {
	printf("watch_handler with unknown GIOChannel.\n");
	return 0;
    }

    /* call the function(condition, userdata) */
    lua_getfield(L, -1, "func");
    lua_getfield(L, -2, "data");
    const struct struct_info *si = find_struct("GIOChannel");

    // this object should already exist; anyway, it's not new.
    get_widget(L, gio, si - struct_list, 0);
    if (lua_isnil(L, -1)) {
	printf("%s watch_handler: invalid GIOChannel (first argument)\n",
	    msgprefix);
	return 0;
    }

    lua_pushinteger(L, cond);
    lua_call(L, 3, 1);
    again = lua_toboolean(L, -1);
    lua_settop(L, stack_top);

    /* The result of the callback is a boolean.  If it is TRUE, continue to
     * watch this event, otherwise stop doing so.
     *
     * NOTE: if you return FALSE, and do not call g_source_remove for this
     * watch, then the gtk main loop goes into 100% busy mode, while the GUI is
     * still being responsive.  Try to avoid this!
     * */
    return again;
}

static void watch_destroy_notify(gpointer data)
{
    // printf("A watcher was destroyed!  data=%p\n", data);
}

/**
 * Add a new watch to the main loop.
 * 
 * Parameters: GIOChannel (as lightuserdata), conditions (integer),
 *  callback (Lua function), user_data (whatever)
 *
 * Returns the ID of the new watch; this can be used to remove it, see
 * g_source_remove().
 */
int l_g_io_add_watch(lua_State *L)
{
    GIOChannel *channel = * (GIOChannel**) lua_topointer(L, 1);
    GIOCondition condition = lua_tointeger(L, 2);

    /* construct a table with info for the callback */
    lua_pushinteger(L, (int) channel);	// key for ENVIRONINDEX
    lua_createtable(L, 2, 0);
    lua_pushvalue(L, 3);
    lua_setfield(L, -2, "func");

    lua_pushvalue(L, 4);
    lua_setfield(L, -2, "data");
    lua_settable(L, LUA_ENVIRONINDEX);	// expects k, v at top of stack

    // use a lower priority, so that the GUI remains fully interactive.
    int id = g_io_add_watch_full(channel, 3, condition, watch_handler,
	(gpointer) global_lua_state, watch_destroy_notify);
    lua_pushinteger(L, id);

    return 1;
}


/**
 * Call this function and return the result as a Lua string.
 * 
 * Parameters: pixbuf, type, args...
 * Returns: buffer (or nil)
 *
 * XXX leaky, leaky...
 */
int l_gdk_pixbuf_save_to_buffer(lua_State *L)
{
    GdkPixbuf *pixbuf = * (GdkPixbuf**) lua_topointer(L, 1);
    gchar *buffer = NULL;
    gsize buffer_size = 0;
    const char *type = lua_tostring(L, 2);
    GError *error = NULL;
    gboolean rc;

    rc = gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, type, &error,
	NULL);
    if (buffer) {
	lua_pushlstring(L, buffer, buffer_size);
	return 1;
    }

    return 0;
}

int l_get_osname(lua_State *L)
{
#ifdef WIN32
    lua_pushstring(L, "win32");
#else
    lua_pushstring(L, "linux");
#endif
    return 1;
}


/**
 * Build a response for the Lua caller about the result of a Channel IO
 * operation.  Should the OK response not be a simple boolean, handle this
 * instead of calling this function.
 */
int _handle_channel_status(lua_State *L, GIOStatus status, GError *error,
    int bytes_transferred)
{
    switch (status) {
	case G_IO_STATUS_NORMAL:
	    lua_pushboolean(L, 1);
	    lua_pushstring(L, "ok");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;

	case G_IO_STATUS_AGAIN:
	    lua_pushnil(L);
	    lua_pushstring(L, "timeout");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
	
	case G_IO_STATUS_ERROR:
	    lua_pushnil(L);
	    lua_pushstring(L, error->message);
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
	
	case G_IO_STATUS_EOF:
	    lua_pushnil(L);
	    lua_pushstring(L, "connection lost");
	    lua_pushinteger(L, bytes_transferred);
	    return 3;
    }

    /* not reached */
    return 0;
}


/**
 * Read some bytes from the channel.
 *
 * Args: channel, maxbytes
 * Returns: a string, or NIL and an error message.
 */
int l_g_io_channel_read_chars(lua_State *L)
{
    GIOStatus status;
    GIOChannel *channel = * (GIOChannel**) lua_topointer(L, 1);
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
 * Read the next line from the channel.
 *
 * The channel has to be buffered in order for this to work.
 *
 * Args: channel
 * Returns: string, or NIL and an error message.
 */
int l_g_io_channel_read_line(lua_State *L)
{
    GIOChannel *channel = * (GIOChannel**) lua_topointer(L, 1);
    gchar *str;
    gsize length, terminator_pos;
    GError *error = NULL;

    GIOStatus status = g_io_channel_read_line(channel, &str, &length,
	&terminator_pos, &error);
    
    // printf("read line got %d bytes, status=%d\n", length, status);

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
 * Args: channel, string
 * Returns: true on success, otherwise nil and an error message.
 */
int l_g_io_channel_write_chars(lua_State *L)
{
    GError *error = NULL;
    gsize count, bytes_written;
    GIOChannel *channel = * (GIOChannel**) lua_topointer(L, 1);
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
 */
int l_g_io_channel_flush(lua_State *L)
{
    GError *error = NULL;
    GIOChannel *channel = * (GIOChannel**) lua_topointer(L, 1);
    GIOStatus status = g_io_channel_flush(channel, &error);
    return _handle_channel_status(L, status, error, 0);
}


/**
 * This should be called by the application soon after startup.  This override
 * exists for two reasons.
 *  1. to avoid warning messages about unused return values
 *  2. to set the global_lua_state
 */
int l_gtk_init(lua_State *L)
{
    global_lua_state = L;
    gtk_init(NULL, NULL);
    return 0;
}


/**
 * Set the given property; the difficulty is to first convert the value to
 * a GValue of the correct type.
 *
 *  Parameters: GObject, property_name, value
 *  Returns: nothing
 */
int l_g_object_set_property(lua_State *L)
{
    struct widget *w = (struct widget*) lua_topointer(L, 1);
    if (!w || w->refcounting > WIDGET_RC_MAX) {
	printf("%s invalid object in l_g_object_set_property.\n", msgprefix);
	return 0;
    }

    GObject *object = * (GObject**) lua_topointer(L, 1);
    lua_getmetatable(L, 1);
    lua_getfield(L, -1, "_gtktype");
    GType type = lua_tointeger(L, -1);
    GObjectClass *oclass = (GObjectClass*) g_type_class_ref(type);
    const gchar *prop_name = lua_tostring(L, 2);
    GParamSpec *pspec = g_object_class_find_property(oclass, prop_name);
    if (!pspec) {
	printf("no property named %s\n", prop_name);
	return 0;
    }
    GValue gvalue;
    if (_make_gvalue(L, &gvalue, pspec->value_type, 3)) {
	g_object_set_property(object, prop_name, &gvalue);
    }
    g_type_class_unref(oclass);
    return 0;
}

/**
 * Return the reference counter of the object the given variable points to.
 * Returns NIL if the object has no reference counting.
 */
int l_get_refcount(lua_State *L)
{
    lua_settop(L, 1);
    struct widget *w = (struct widget*) lua_topointer(L, 1);

    lua_getmetatable(L, 1);
    if (lua_isnil(L, 2))
	return 1;

    lua_getfield(L, 2, "_classname");
    if (lua_isnil(L, 3))
	return 1;

    lua_pushinteger(L, get_widget_refcount(w));
    return 1;
}

/**
 * Dump a table, possibly recurse.
 * Input: a table.
 *  At stack[1] there's the function tostring, and at [2] a table with
 *  key=object, value=true (all objects seen so far)
 * Output: none
 */
int _dump_memory(lua_State *L, int level, const char *name)
{
    static const char prefix[] = "               ";
    if (!lua_type(L, -1) == LUA_TTABLE) {
	printf("memory dump error: parameter is not a table.\n");
	return 0;
    }

    // if already seen, skip.
    lua_pushvalue(L, -1);
    lua_rawget(L, 2);
    int seen = !lua_isnil(L, -1);
    lua_pop(L, 1);
    if (seen)
	return 0;

    // mark it as seen.
    lua_pushvalue(L, -1);
    lua_pushboolean(L, 1);
    lua_rawset(L, 2);

    if (name) {
	printf("%*.*s%s\n", level, level, prefix, name);
    }

    int t = lua_gettop(L) - 1, type;
    
    lua_pushnil(L);			// t k
    while (lua_next(L, t+1)) {		// t k v

	lua_pushvalue(L, 1);		// t k v tostring
	lua_pushvalue(L, t+2);		// t k v tostring k
	lua_call(L, 1, 1);		// t k v string(k)

	lua_pushvalue(L, 1);		// t k v string(k) tostring
	lua_pushvalue(L, t+3);		// t k v string(k) tostring v
	lua_call(L, 1, 1);		// t k v string(k) string(v)

	printf("%*.*s%s = %s\n", level, level, prefix,
	    lua_tostring(L, -2), lua_tostring(L, -1));
	lua_pop(L, 2);			// t k v

	// is there a metatable?
	if (lua_getmetatable(L, -1)) {	// t k v meta(v)
	    lua_pushvalue(L, 1);
	    lua_pushvalue(L, -2);
	    lua_call(L, 1, 1);
	    printf("%*.*sMETATABLE %s\n", level, level, prefix,
		lua_tostring(L, -1));
	    lua_pop(L, 1);
	    _dump_memory(L, level + 1, "Metatable");
	    lua_pop(L, 1);
	}

	// recurse for tables
	type = lua_type(L, -1);

	switch (type) {
	    case LUA_TTABLE:
		_dump_memory(L, level + 1, "Table");
		break;

	    case LUA_TFUNCTION:
	    case LUA_TTHREAD:
	    case LUA_TUSERDATA:
		lua_getfenv(L, -1);
		if (!lua_isnil(L, -1)) {
		    _dump_memory(L, level + 1, "Environment");
		}
		lua_pop(L, 1);
		break;
	}

	lua_pop(L, 1);			// t k
    }
    
    return 0;
}

/**
 * walk through all reachable memory objects.  Starting points:
 * - the global table
 * - the registry
 */
int l_dump_memory(lua_State *L)
{
    printf("\n** MEMORY DUMP **\n");
    lua_settop(L, 0);

    lua_getglobal(L, "tostring");	// tostring
    lua_newtable(L);			// tostring list

    lua_pushvalue(L, LUA_GLOBALSINDEX);	// tostring t
    _dump_memory(L, 0, "Global");
    lua_pop(L, 1);

    printf("\n\n** REGISTRY ** %d\n", lua_gettop(L));

    lua_pushvalue(L, LUA_REGISTRYINDEX);
    _dump_memory(L, 0, "Registry");
    lua_pop(L, 1);

    lua_pop(L, 2);
    printf("** MEMORY DUMP ENDS **\n");
    return 0;
}

/**
 * args: model, iter, column
 * returns: GValue
 */
int l_gtk_tree_model_get_value(lua_State *L)
{
    struct widget *model = (struct widget*) lua_topointer(L, 1);
    struct widget *iter = (struct widget*) lua_topointer(L, 2);
    int column = lua_tonumber(L, 3);
    GValue gvalue = { 0 };

    gtk_tree_model_get_value(model->p, iter->p, column, &gvalue);
    push_a_value(L, gvalue.g_type,
	(union gtk_arg_types*) &gvalue.data, NULL, 0);
    return 1;
}


/**
 * Widgets are kept in the table gtk.widgets, so that the "struct widget"
 * doesn't have to be constructed again and again.  If a widget is really
 * not needed anymore, remove it from there; I currently have no mechanism
 * to do this automatically.
 *
 */
int l_forget_widget(lua_State *L)
{
    return 0;
}

/* methods directly callable from Lua; most go through __index */
const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"init",		l_gtk_init },
    {"call",		l_call },
    {"new",		l_new },
    {"dump_struct",	l_dump_struct },
    {"dump_stack",	l_dump_stack },
    {"luagtk_register_widget", luagtk_register_widget },
    {"my_g_io_add_watch",	l_g_io_add_watch },
    {"get_osname",	l_get_osname },
    {"get_refcount",	l_get_refcount },
    {"widget_gc",	l_widget_gc },
    {"breakfunc",	breakfunc },
    {"dump_memory",	l_dump_memory },
    {"forget_widget",	l_forget_widget },

    /* some overrides */
    {"gtk_object_connect", l_gtk_connect },
    {"gtk_object_disconnect",	l_gtk_disconnect },
    {"g_type_from_name", l_g_type_from_name },
    {"g_object_get_class", l_g_object_get_class },
    {"g_object_set_property", l_g_object_set_property },
    {"g_io_channel_read_chars", l_g_io_channel_read_chars },
    {"g_io_channel_read_line", l_g_io_channel_read_line },
    {"g_io_channel_write_chars", l_g_io_channel_write_chars },
    {"g_io_channel_flush", l_g_io_channel_flush },
    {"gdk_pixbuf_save_to_buffer", l_gdk_pixbuf_save_to_buffer },
    {"gtk_tree_model_get_value", l_gtk_tree_model_get_value },

    { NULL, NULL }
};
