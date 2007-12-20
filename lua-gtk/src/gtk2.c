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
 *  luagtk_index
 *  luagtk_newindex
 *  luagtk_push_gvalue
 *  luaopen_gtk
 */

#include "luagtk.h"
#include <lauxlib.h>
#include <stdlib.h>		/* bsearch */
#include <string.h>		/* strcmp */
#include <stdio.h>		/* fopen & co */
#include <stdarg.h>
#include <locale.h>


/* in interface.c */
extern const luaL_reg gtk_methods[];

/* in _override.c */
extern char override_data[];
extern int override_size;

int gtk_is_initialized = 0;

void luagtk_init_gtk()
{
    if (gtk_is_initialized)
	return;
    gtk_is_initialized = 1;
    gtk_init(NULL, NULL);
}
    

/*-
 * The GValue at *gv is of a fundamental type.  Push the appropriate value
 * on the Lua stack.  If the type is not handled, a Lua error is raised.
 */
static void _push_gvalue_fundamental(lua_State *L, GValue *gv)
{
    GType type = gv->g_type;
    void *data = (void*) &gv->data;

    // see /usr/include/glib-2.0/gobject/gtype.h for type numbers.
    switch (G_TYPE_FUNDAMENTAL(type)) {
	case G_TYPE_INVALID:
	    lua_pushnil(L);
	    return;

	case G_TYPE_NONE:
	    printf("strange... an argument of type NONE?\n");
	    return;

	// missing: G_TYPE_INTERFACE

	case G_TYPE_CHAR:
	case G_TYPE_UCHAR:
	    lua_pushlstring(L, (char*) data, 1);
	    return;

	case G_TYPE_BOOLEAN:
	    lua_pushboolean(L, * (int*) data);
	    return;

	case G_TYPE_INT:
	    lua_pushnumber(L, * (int*) data);
	    return;

	case G_TYPE_UINT:
	    lua_pushnumber(L, * (unsigned int*) data);
	    return;

	case G_TYPE_LONG:
	    lua_pushnumber(L, * (long int*) data);
	    return;

	case G_TYPE_ULONG:
	    lua_pushnumber(L, * (unsigned long int*) data);
	    return;

	case G_TYPE_INT64:
	    lua_pushnumber(L, * (gint64*) data);
	    return;

	case G_TYPE_UINT64:
	    lua_pushnumber(L, * (guint64*) data);
	    return;

	// XXX might be possible to find out which ENUM it is?
	case G_TYPE_ENUM:
	case G_TYPE_FLAGS:
	    lua_pushnumber(L, * (int*) data);
	    return;

	case G_TYPE_FLOAT:
	    lua_pushnumber(L, * (float*) data);
	    return;

	case G_TYPE_DOUBLE:
	    lua_pushnumber(L, * (double*) data);
	    return;

	case G_TYPE_STRING:
	    lua_pushstring(L, * (char**) data);
	    return;

	case G_TYPE_POINTER:
	    // Some opaque structure.  This is very seldom and it is
	    // not useful to try to override it.  There's a reason for
	    // parameters being opaque...
	    lua_pushlightuserdata(L, * (void**) data);
	    return;

	// missing: G_TYPE_BOXED
	// missing: G_TYPE_PARAM
	// missing: G_TYPE_OBJECT

	default:
	    luaL_error(L, "luagtk_push_value: unhandled fundamental "
		"type %d\n", (int) type >> 2);
    }
}



/**
 * A parameter for a callback must be pushed onto the stack.  The type to
 * use depends on the "type" (from the g_signal_query results).  A value
 * is always pushed; in the case of error, NIL.
 *
 * @param L  Lua State
 * @param type  GType of the parameter to be pushed
 * @param data  pointer to the location of this data
 */
void luagtk_push_gvalue(lua_State *L, GValue *gv)
{
    if (!gv)
	luaL_error(L, "[gtk] luagtk_push_value called with NULL data");

    GType type = gv->g_type;
    void *data = (void*) &gv->data;

    if (G_TYPE_IS_FUNDAMENTAL(type)) {
	_push_gvalue_fundamental(L, gv);
	return;
    }

    /* not a fundamental type */
    const char *name = g_type_name(type);
    if (!name)
	luaL_error(L, "[gtk] callback argument GType %d invalid", type);

    /* If this type is actually derived from GObject, then let make_widget
     * find out the exact type itself.  Maybe it is a type derived from the
     * one specified, then better use that.
     */
    int type_of_gobject = g_type_from_name("GObject");
    if (g_type_is_a(type, type_of_gobject)) {
	// pushes nil on error.
	luagtk_get_widget(L, * (void**) data, 0, FLAG_NOT_NEW_OBJECT);
	return;
    }
    
    struct struct_info *si = find_struct(name);
    if (!si) {
	printf("%s structure not found for callback arg: %s\n",
	    msgprefix, name);
	lua_pushnil(L);
	return;
    }

    /* Find or create a Lua wrapper for the given object. */
    int struct_nr = si - struct_list;
    luagtk_get_widget(L, * (void**) data, struct_nr, FLAG_NOT_NEW_OBJECT);
}


/**
 * After a method has been looked up, this function is called to do the
 * invoction of the corresponding gtk function.
 *
 * Note that this is intended to be used in a closure with the upvalue(1)
 * being a reference to the meta entry for the function call.
 */
static int l_call_func(lua_State *L)
{
    struct meta_entry *me = (struct meta_entry*) lua_topointer(L,
	lua_upvalueindex(1));
    return luagtk_call(L, &me->fi, 1);
}

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
    // of the given type exist anymore, they may be removed (weak values).
    lua_newtable(L);			// gtk mt t
    lua_pushvalue(L, -2);		// gtk mt t mt
    lua_setmetatable(L, -2);		// gtk mt t
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
#if 1
    // lua_pushliteral(L, "emptyattr");	// gtk "emptyattr"
    lua_newtable(L);			// gtk "emptyattr" t
    lua_setfield(L, LUA_ENVIRONINDEX, LUAGTK_EMPTYATTR);
#endif

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

