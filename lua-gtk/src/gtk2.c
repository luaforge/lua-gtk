/* vim:sw=4:sts=4
 *
 * Library to use the Gtk2 widget library from Lua 5.1
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 * Use this software under the terms of the GPLv2.
 *
 * Library initialization, and a few basic routines which could as well
 * be in widget.c.
 *
 * Revision history:
 *  2005-07-24	first public release
 *  2005-08-18	update for Lua 5.1-work6
 *  2007-02-02	(almost) no global Lua state; use luaL_ref
 *  2007-10-12	improved modularization of the code; ENUM typechecking
 *
 * Exported functions:
 *  luagtk_init_gtk
 *  luaopen_gtk
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_error
#include <string.h>	    // strcpy


/* in _override.c */
extern char override_data[];
extern int override_size;

int gtk_is_initialized = 0;

/**
 * Initialize Gtk if it hasn't happened yet.  This is mostly called through
 * the macro GTK_INITIALIZE, which calls this function only if
 * gtk_is_initialized isn't set.
 */
void luagtk_init_gtk()
{
    if (gtk_is_initialized)
	return;
    gtk_is_initialized = 1;
    gtk_init(NULL, NULL);
}
    

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

    // cache the result of this lookup
    lua_pushvalue(L, 2);	// key
    lua_pushvalue(L, -2);	// the new closure
    lua_rawset(L, 1);		// [1]=table

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


/**
 * Give the application an idea of the platform.  Could be used to select
 * path separators and more.  I have not found a way to determine this
 * in any other way, so far.
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


/* methods directly callable from Lua; most go through __index */
static const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"new",		l_new },
    {"get_osname",	l_get_osname },
    { NULL, NULL }
};


/**
 * Initialize the library, returns a table.  Note that the table is also stored
 * as the global "gtk", because within this library the global table is
 * accessed sometimes.
 */
int luaopen_gtk(lua_State *L)
{
    if (!luagtk_dl_init())
	return 0;

    // new, empty environment
    lua_newtable(L);
    lua_replace(L, LUA_ENVIRONINDEX);

    /* make the table to return, and make it global as "gtk" */
    luaL_register(L, "gtk", gtk_methods);
    luagtk_init_widget(L);
    luagtk_init_overrides(L);
    luagtk_init_channel(L);
    luagtk_init_debug(L);

    // a metatable to make another table have weak values
    lua_newtable(L);			// gtk mt
    lua_pushliteral(L, "v");		// gtk mt "v"
    lua_setfield(L, -2, "__mode");	// gtk mt

    // Table with all widget metatables; [name] = table.  When no widgets
    // of the given type exist anymore, they may be removed if weak values
    // are used; this doesn't make much sense, as a program will most likely
    // use a certain widget type again if it is used once.
    lua_newtable(L);			// gtk mt t
    /* make it have weak values
    lua_pushvalue(L, -2);		// gtk mt t mt
    lua_setmetatable(L, -2);		// gtk mt t
    */
    lua_setfield(L, LUA_ENVIRONINDEX, LUAGTK_METATABLES);   // gtk mt
    
    // widgets: not a weak table.  It only contains references to entries
    // in the aliases table; they are removed manually when the last alias
    // is garbage collected.
    lua_newtable(L);			// gtk mt t
    lua_setfield(L, LUA_ENVIRONINDEX, LUAGTK_WIDGETS);	    // gtk mt

    // gtk.widgets_aliases.  It has automatic garbage collection (weak values)
    lua_newtable(L);
    lua_pushvalue(L, -2);
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_ENVIRONINDEX, LUAGTK_ALIASES);

    lua_pop(L, 1);			// gtk


    /* default attribute table of a widget */
    lua_newtable(L);			// gtk "emptyattr" t
    lua_setfield(L, LUA_ENVIRONINDEX, LUAGTK_EMPTYATTR);

    /* execute the glue library (compiled in) */
    luaL_loadbuffer(L, override_data, override_size, "override.lua");
    lua_pcall(L, 0, 0, 0);

    // make gtk its own metatable - it contains __index and maybe other
    // special methods.
    lua_pushvalue(L, -1);
    lua_setmetatable(L, -2);

    // Can't initialize Gtk right away: if memory tracing is used, it must
    // be activated first; otherwise, initial allocations are not noted and
    // lead to errors later on, e.g. when a block is reallocated.
    // gtk_init(NULL, NULL);

    /* one retval on the stack: gtk.  This is usually not used anywhere,
     * but you have to use the global variable "gtk". */
    return 1;
}

