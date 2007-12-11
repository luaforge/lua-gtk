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

    GTK_INITIALIZE();

    /* if it starts with an uppercase letter, it's probably an ENUM. */
    if (s[0] >= 'A' && s[0] <= 'Z') {
	int val, struct_nr;
	switch (find_enum(L, s, -1, &val, &struct_nr)) {
	    case 1:		// ENUM/FLAG found
	    return luagtk_enum_push(L, val, struct_nr);

	    case 2:		// integer found
	    lua_pushinteger(L, val);
	    /* fall through */

	    case 3:		// string found - is on Lua stack
	    return 1;
	}
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

    GTK_INITIALIZE();

    if (!(si=find_struct(struct_name))) {
	printf("%s structure %s not found\n", msgprefix, struct_name);
	return 0;
    }

    /* Allocate and initialize the object.  I used to allocate just one
     * userdata big enough for both the wrapper and the widget, but many
     * free functions exist, like gtk_tree_iter_free, and they expect a memory
     * block allocated by g_slice_alloc0.  Therefore this optimization is not
     * possible. */
    p = g_slice_alloc0(si->struct_size);

    /* Make a Lua wrapper for it, push it on the stack.  FLAG_ALLOCATED causes
     * the _malloc_handler be used, and FLAG_NEW_OBJECT makes it not complain
     * about increasing the (non existant) refcounter. */
    luagtk_get_widget(L, p, si - struct_list, FLAG_ALLOCATED | FLAG_NEW_OBJECT);
    return 1;
}


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
    lua_pushliteral(L, "win32");
#else
    lua_pushliteral(L, "linux");
#endif
    return 1;
}


/**
 * Return the reference counter of the object the given variable points to.
 * Returns NIL if the object has no reference counting.
 *
 * @name get_refcount
 * @luaparam object  The object to query
 * @luareturn The current reference counter
 * @luareturn Widget type name
 */
static int l_get_refcount(lua_State *L)
{
    lua_settop(L, 1);

    struct widget *w = luagtk_check_widget(L, 1);
    if (w) {
	struct widget_type *wt = luagtk_get_widget_type(w);
	lua_pushinteger(L, luagtk_get_refcount(w));
	lua_pushstring(L, wt->name);
	return 2;
    }

    return 0;
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


/* methods directly callable from Lua; most go through __index */
const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"new",		l_new },
    {"get_osname",	l_get_osname },
    {"get_refcount",	l_get_refcount },

    // debugging
    {"dump_struct",	luagtk_dump_struct },
    {"dump_stack",	l_dump_stack },
    {"dump_memory",	luagtk_dump_memory },
    {"function_sig",	l_function_sig },
    {"breakfunc",	luagtk_breakfunc },

    { NULL, NULL }
};

