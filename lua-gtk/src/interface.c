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
 * Main module for the Lua-Gtk binding.
 * @class module
 * @name gtk
 */

/*-
 * A method has been found and should now be called.
 * input stack: parameters to the function
 * upvalues: the func_info structure
 */
static int _call_wrapper(lua_State *L)
{
    struct func_info *fi = (struct func_info*) lua_topointer(L,
	lua_upvalueindex(1));
    return luagtk_call(L, fi, 1);
}


/**
 * Look up a name in gtk.  This works for any Gtk function, like
 * gtk.window_new(), and ENUMs, like gtk.GTK_WINDOW_TOPLEVEL.
 *
 * @name __index
 * @luaparam table     The table to look in; is automatically set to gtk
 * @luaparam key       The name of the item to look up
 * @luareturn          Either a userdata (for ENUMs) or a closure (for
 *			functions)
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
	    return luaL_error(L, "[gtk] not found: gtk.%s", s);
	    // printf("%s attribute or method not found: %s\n", msgprefix, s);
	    // return 0;
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
    lua_pushcclosure(L, _call_wrapper, 1);
    return 1;
}


/**
 * Allocate a structure, initialize with zero and return it.
 *
 * This is NOT intended for widgets or structures that have specialized
 * creator functions, like gtk_window_new and such.  Use it for simple
 * structures like GtkTreeIter.
 *
 * The widget is, as usual, a Lua wrapper in the form of a userdata,
 * containing a pointer to the actual widget.
 *
 * @name new
 * @luaparam name Name of the structure to allocate
 * @luareturn The new structure
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

    /* Allocate and initialize the object.  I used to allocate just one
     * userdata big enough for both the wrapper and the widget, but sometimes a
     * special free function must be called, like gtk_tree_iter_free.  So, this
     * optimization is not possible. */
    p = g_malloc(si->struct_size);
    memset(p, 0, si->struct_size);

    /* Make a Lua wrapper for it, push it on the stack.  Note that manage_mem
     * is 1, i.e. call g_free later. */
    get_widget(L, p, si - struct_list, 1);
    return 1;
}

#if 0

/*-
 * Store information about a Gtk widget.
 *
 * This is probably not required.  This only makes sense for widgets created
 * outside of Lua, i.e. from C code.  Thus, a function callable from C
 * would make more sense, wouldn't it?
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

static int l_dump_stack(lua_State *L)
{
#ifdef DEBUG_DUMP_STACK
    return luagtk_dump_stack(L, 1);
#endif
}


/**
 * To give the application an idea of the platform.  Could be used to select
 * path separators and more.
 *
 * @name get_osname
 * @luareturn The ID of the operating system: "win32" or "linux".
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

#if 0

#include <malloc.h>
static gpointer my_realloc(gpointer mem, gsize n_bytes)
{
    if (n_bytes == 640) {
	printf("640 bytes allocated\n");
    }
    return realloc(mem, n_bytes);
}

static GMemVTable my_vtable = {
    malloc: malloc,
    realloc: my_realloc,
    free: free
};
#endif

/**
 * Return the reference counter of the object the given variable points to.
 * Returns NIL if the object has no reference counting.
 *
 * @name get_refcount
 * @luaparam object  The object to query
 * @luareturn The current reference counter
 * @luareturn Widget type number (internal)
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
    lua_pushinteger(L, w->widget_type);
    return 2;
}

/**
 * Get the function signature, similar to a C declaration.
 *
 * @name function_sig
 * @luaparam name The function name
 * @luareturn A string with the function signature.
 */
static int l_function_sig(lua_State *L)
{
    const char *fname = luaL_checkstring(L, 1);
    struct func_info fi;

    if (!find_func(fname, &fi))
	return 0;

    return luagtk_function_signature(L, &fi);
}


/**
 * Free memory.  This is optional, but aids finding memory leaks.
 * I have not found a way to make Lua call an exit function automatically.
 */
static int l_done(lua_State *L)
{
    call_info_free_pool();
    return 0;
}


/* methods directly callable from Lua; most go through __index */
const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"new",		l_new },
    {"get_osname",	l_get_osname },
    {"get_refcount",	l_get_refcount },

    // these function will probably change
    // {"luagtk_register_widget", l_register_widget },

    // debugging
    {"dump_struct",	luagtk_dump_struct },
    {"dump_stack",	l_dump_stack },
    {"dump_memory",	luagtk_dump_memory },
    {"function_sig",	l_function_sig },
    {"breakfunc",	luagtk_breakfunc },
    {"done",		l_done },

    { NULL, NULL }
};
