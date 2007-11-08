/* vim:sw=4:sts=4
 * Lua Gtk2 binding.
 * This file contains most of the user-visible functions in the gtk table.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * Exported functions:
 *   none (only gtk_methods)
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_error
#include <string.h>	    // strcpy


/**
 * Handle accesses of "gtk.xxx", where xxx may be any gtk function, used mainly
 * for gtk.xxx_new(), and ENUMs.
 *
 * input stack: 1=table, 2=value
 * output: either a userdata (for ENUMs) or a closure (for functions).
 */
static int l_gtk_lookup(lua_State *L)
{
    const char *s = luaL_checkstring(L, 2);
    struct func_info fi;
    char func_name[50];

    if (!s) {
	luaL_error(L, "%s attempt to look up a NULL string\n", msgprefix);
	/* not reached */
	return 0;
    }

    /* if it starts with an uppercase letter, it's probably an ENUM. */
    if (s[0] >= 'A' && s[0] <= 'Z') {
	int val, struct_nr;
	if (find_enum(s, -1, &val, &struct_nr))
	    return luagtk_enum_push(L, val, struct_nr);
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
    // NOTE: need to duplicate the name, fi.name points to the local variable
    // fund_name.  So, allocate a new func_info with some space after it large
    // enough to hold the function name.
    int name_len = strlen(fi.name) + 1;
    struct func_info *fi2 = (struct func_info*) lua_newuserdata(L,
	sizeof(*fi2) + name_len);
    memcpy(fi2, &fi, sizeof(*fi2));
    memcpy(fi2+1, fi.name, name_len);
    fi2->name = (char*) (fi2+1);
    lua_pushcclosure(L, luagtk_call_wrapper, 1);
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
	return luagtk_call(L, &fi, 2);
    }

    printf("%s l_call: function %s not found.\n", msgprefix, func_name);
    return 0;
}


/**
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
static int l_new(lua_State *L)
{
    const char *struct_name = luaL_checkstring(L, 1);
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

#if 0

/**
 * Store information about a Gtk widget.
 *
 * The global table gtk.widgets will contain two new entries:
 *   address -> widget
 *   ID -> widget
 */
static int l_register_widget(lua_State *L)
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

#endif

/**
 * g_type_from_name fails unless the type has been initialized before.  Use
 * my wrapper that handles the initialization when required.
 */
static int l_g_type_from_name(lua_State *L)
{
    const char *s = luaL_checkstring(L, 1);
    int type_nr = luagtk_g_type_from_name(s);
    lua_pushnumber(L, type_nr);
    return 1;
}


/**
 * Perform the G_OBJECT_GET_CLASS on an object.
 * Returns a GObjectClass structure, or nil on error.
 */
static int l_g_object_get_class(lua_State *L)
{
    // printf("get class.\n");
    GObject *parent = (GObject*) lua_topointer(L, 1);
    // printf("  parent is %p\n", parent);
    GObjectClass *c = G_OBJECT_GET_CLASS(parent);
    // printf("  class is %p\n", c);
    const struct struct_info *si = find_struct("GObjectClass");
    if (!si)
	luaL_error(L, "%s type GObjectClass unknown.\n", msgprefix);

    // manage_mem is 0, i.e. do not try to g_free(c) later on.
    // XXX or reference c?
    get_widget(L, c, si - struct_list, 0);
    return 1;
}


static int l_dump_stack(lua_State *L)
{
#ifdef DEBUG_DUMP_STACK
    return luagtk_dump_stack(L, 1);
#endif
}


/**
 * Call this function and return the result as a Lua string.
 * 
 * Parameters: pixbuf, type, args...
 * Returns: buffer (or nil)
 */
static int l_gdk_pixbuf_save_to_buffer(lua_State *L)
{
    struct widget *w = (struct widget*) lua_topointer(L, 1);
    GdkPixbuf *pixbuf = (GdkPixbuf*) w->p;
    gchar *buffer = NULL;
    gsize buffer_size = 0;
    const char *type = lua_tostring(L, 2);
    GError *error = NULL;
    gboolean rc;

    rc = gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, type, &error,
	NULL);
    if (buffer) {
	lua_pushlstring(L, buffer, buffer_size);
	g_free(buffer);
	return 1;
    }

    return 0;
}


/**
 * To give the application an idea of the platform.  Could be used to select
 * path separators and more.
 */
static int l_get_osname(lua_State *L)
{
#ifdef WIN32
    lua_pushstring(L, "win32");
#else
    lua_pushstring(L, "linux");
#endif
    return 1;
}


/**
 * This should be called by the application soon after startup.  This override
 * exists for two reasons.
 *  1. to avoid warning messages about unused return values
 *  2. to set the global_lua_state
 */
static int l_gtk_init(lua_State *L)
{
    global_lua_state = L;

    if (lua_gettop(L) > 0)
	runtime_flags = lua_tonumber(L, 1);

    if (runtime_flags & RUNTIME_GMEM_PROFILE)
	g_mem_set_vtable(glib_mem_profiler_table);

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
static int l_g_object_set_property(lua_State *L)
{
    struct widget *w = (struct widget*) lua_topointer(L, 1);
    if (!w /*|| w->refcounting >= WIDGET_RC_LAST */) {
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
	printf("g_object_set_property: no property named %s\n", prop_name);
	return 0;
    }
    GValue gvalue = {0};
    if (luagtk_fill_gvalue(L, &gvalue, pspec->value_type, 3))
	g_object_set_property(object, prop_name, &gvalue);
    g_type_class_unref(oclass);
    return 0;
}

/**
 * Return the reference counter of the object the given variable points to.
 * Returns NIL if the object has no reference counting.
 */
static int l_get_refcount(lua_State *L)
{
    lua_settop(L, 1);
    struct widget *w = (struct widget*) lua_topointer(L, 1);

    lua_getmetatable(L, 1);
    if (lua_isnil(L, 2))
	return 1;

    lua_getfield(L, 2, "_classname");
    if (lua_isnil(L, 3))
	return 1;

    lua_pushinteger(L, luagtk_get_widget_refcount(w));
    return 1;
}

#if 0
/**
 * args: model, iter, column
 * returns: GValue
 */
static int l_gtk_tree_model_get_value(lua_State *L)
{
    struct widget *model = (struct widget*) lua_topointer(L, 1);
    struct widget *iter = (struct widget*) lua_topointer(L, 2);
    int column = lua_tonumber(L, 3);
    GValue gvalue = { 0 };

    gtk_tree_model_get_value(model->p, iter->p, column, &gvalue);
    luagtk_push_value(L, gvalue.g_type, (void*) &gvalue.data);
    return 1;
}
#endif


/**
 * Widgets are kept in the table gtk.widgets, so that the "struct widget"
 * doesn't have to be constructed again and again.  If a widget is really
 * not needed anymore, remove it from there; I currently have no mechanism
 * to do this manually.  It will be garbage collected anyway at some point.
 *
 * XXX not implemented
 */
static int l_forget_widget(lua_State *L)
{
    return 0;
}

/**
 * Get the function signature, similar to a C declaration.
 *
 * @param The function name
 * @return A string on the Lua stack with the function signature.
 */
static int l_function_sig(lua_State *L)
{
    const char *fname = luaL_checkstring(L, 1);
    struct func_info fi;

    if (!find_func(fname, &fi))
	return 0;

    return luagtk_function_signature(L, &fi);
}


/* methods directly callable from Lua; most go through __index */
const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"init",		l_gtk_init },
    {"call",		l_call },
    {"new",		l_new },
    {"get_osname",	l_get_osname },
    {"get_refcount",	l_get_refcount },

    // these function will probably change
    // {"luagtk_register_widget", l_register_widget },
    {"my_g_io_add_watch",	l_g_io_add_watch },
    {"forget_widget",	l_forget_widget },

    // debugging
    {"dump_struct",	luagtk_dump_struct },
    {"dump_stack",	l_dump_stack },
    {"dump_memory",	luagtk_dump_memory },
    {"function_sig",	l_function_sig },
    {"breakfunc",	luagtk_breakfunc },

    /* some overrides */
    {"gtk_object_connect", luagtk_connect },
    {"gtk_object_disconnect",	luagtk_disconnect },
    {"g_type_from_name", l_g_type_from_name },
    {"g_object_get_class", l_g_object_get_class },
    {"g_object_set_property", l_g_object_set_property },
    {"g_io_channel_read_chars", l_g_io_channel_read_chars },
    {"g_io_channel_read_line", l_g_io_channel_read_line },
    {"g_io_channel_write_chars", l_g_io_channel_write_chars },
    {"g_io_channel_flush", l_g_io_channel_flush },
    {"gdk_pixbuf_save_to_buffer", l_gdk_pixbuf_save_to_buffer },
    // {"gtk_tree_model_get_value", l_gtk_tree_model_get_value },

    { NULL, NULL }
};
