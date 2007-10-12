/* vim:sw=4:sts=4
 *
 * Library to use the Gtk2 widget library from Lua 5.1
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 * Use this software under the terms of the GPLv2.
 *
 * Revision history:
 *  2005-07-24	first public release
 *  2005-08-18	update for Lua 5.1-work6
 *  2007-02-02	no global Lua state; use luaL_ref
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

/**
 * A parameter for a callback must be pushed onto the stack.  The type to
 * use depends on the "type" (from the g_signal_query results).  A value
 * is always pushed; in the case of error, NIL.
 *
 * signal_name: to find overrides.
 * arg_nr: the argument number for thet signal.  It is used to find overrides.
 */
void push_a_value(lua_State *L, GType type, union gtk_arg_types *data,
    const char *signal_name, int arg_nr)
{

    if (!data) {
	printf("push_a_value called with NULL data.\n");
	lua_pushnil(L);
	return;
    }

    // see /usr/include/glib-2.0/gobject/gtype.h for type numbers.
    /*
    printf("push a value %s:%d, type is %d, is fundamental: %d\n",
	signal_name, arg_nr,
	(unsigned int) type, G_TYPE_IS_FUNDAMENTAL(type));
    */
	
    if (G_TYPE_IS_FUNDAMENTAL(type)) {
	switch (G_TYPE_FUNDAMENTAL(type)) {
	    case G_TYPE_BOOLEAN:
		lua_pushboolean(L, data->l);
		break;
	    case G_TYPE_INT:
	    case G_TYPE_LONG:
	    case G_TYPE_INT64:
	    case G_TYPE_ENUM:
		lua_pushnumber(L, data->l);
		break;
	    case G_TYPE_UINT:
	    case G_TYPE_ULONG:
	    case G_TYPE_UINT64:
		lua_pushnumber(L, (unsigned long) data->l);
		break;
	    case G_TYPE_FLOAT:
		lua_pushnumber(L, data->f);
		break;
	    case G_TYPE_DOUBLE:
		lua_pushnumber(L, data->d);
		break;
	    case G_TYPE_POINTER:
		// Some opaque structure.  This is very seldom and it is
		// not useful to try to override it.  There's a reason for
		// parameters being opaque...
		lua_pushlightuserdata(L, data->p);

		break;
	    case G_TYPE_STRING:
		lua_pushstring(L, data->p);
		break;
	    // XXX handle more fundamental types
	    case G_TYPE_NONE:
		printf("strange... an argument of type NONE?\n");
		break;
	    default:
		printf("Warning: unhandled fundamental type %ld\n",
		    (long int) type >> 2);
		lua_pushnumber(L, data->l);
	}
	return;
    }


    /* not a fundamental type */
    const char *name = g_type_name(type);
    if (!name) {
	printf("%s callback argument is not a valid type!\n", msgprefix);
	lua_pushnil(L);
	return;
    }

    /* If this type is actually derived from GObject, then let make_widget
     * find out the exact type itself.  Maybe it is a type derived from the
     * one specified, then better use that.
     */
    int type_of_gobject = g_type_from_name("GObject");
    if (g_type_is_a(type, type_of_gobject)) {
	get_widget(L, data->p, 0, 0);	    // pushes nil on error.
	return;
    }
    
    struct struct_info *si = find_struct(name);
    if (!si) {
	printf("%s structure not found for callback arg: %s\n",
	    msgprefix, name);
	lua_pushnil(L);
	return;
    }

    /**
     * Find or create a Lua wrapper for the given object.  If it doesn't
     * already exist, create it.  Be careful not to free the object on
     * garbage collection, because it was allocated by the library
     * itself and will therefore be freed.
     */
    int struct_nr = si - struct_list;
    get_widget(L, data->p, struct_nr, 0);	// pushes nil on error.
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
    return do_call(L, &me->fi, 1);
}

/**
 * Given a pointer to a structure and the description of the desired element,
 * push a value onto the Lua stack with this item.
 *
 * Returns the number of pushed items, i.e. 1 on success, 0 on failure.
 */
static int _push_attribute(lua_State *L, const struct struct_info *si,
    const struct struct_elem *se, unsigned char *ptr)
{
    const struct ffi_type_map_t *arg_type;

    /*
    printf("attribute %s(%d).%s\n", STRUCT_NAME(si), si - struct_list,
	STRUCT_NAME(se));
    */

    arg_type = &ffi_type_map[se->ffi_type_id];
    if (arg_type->struct2lua)
	return arg_type->struct2lua(L, se, ptr);

    luaL_error(L, "%s unhandled attribute type %s (%s.%s)\n",
	msgprefix, arg_type->name, STRUCT_NAME(si), STRUCT_NAME(se));
    return 0;
}

/**
 * A meta entry is on the top of the stack; use it to retrieve the method
 * pointer or attribute value.
 *
 * Stack: 1=widget, 2=key, 3=dest metatable, 4=current metatable,... meta entry
 */
static int handle_meta_entry(lua_State *L)
{
    /* an override -- just return it */
    if (lua_iscfunction(L, -1) || lua_isfunction(L, -1))
	return 1;

    /* For functions, set up a c closure with one upvalue, which is the pointer
     * to the meta entry. */
    const struct meta_entry *me = lua_topointer(L, -1);
    if (me->struct_nr == 0) {
	lua_pushlightuserdata(L, (void*) me);
	lua_pushcclosure(L, l_call_func, 1);
	return 1;
    }

    /* otherwise, handle attribute access */
    struct widget *w = (struct widget*) lua_topointer(L, 1);
    return _push_attribute(L, struct_list + me->struct_nr, me->se, w->p);
}

/**
 * Write an attribute (only numeric so far), i.e. a field of a Gtk structure.
 *
 * index: the Lua stack index where the data is to be found.
 */
static int _write_attribute(lua_State *L, const struct struct_elem *se,
    unsigned char *ptr, int index)
{
    const struct ffi_type_map_t *arg_type;

    arg_type = &ffi_type_map[se->ffi_type_id];
    if (arg_type->lua2struct)
	return arg_type->lua2struct(L, se, ptr, index);

    printf("%s unhandled attribute write of type %s (attribute %s)\n",
	msgprefix, arg_type->name, STRUCT_NAME(se));
    return 0;
}



/**
 * Assignment to an attribute of a structure.  Must not be a built-in
 * method, but basically could be...
 * Stack: 1=widget, ...
 */
static int handle_write_entry(lua_State *L, int index)
{
    const struct meta_entry *me = lua_topointer(L, -1);
    struct widget *w;

    if (me->struct_nr == 0) {
	printf("%s overwriting method %s not supported.\n", msgprefix,
	    "(unknown)");
	return 0;
    }

    /* write to attribute */
    w = (struct widget*) lua_topointer(L, 1);
    _write_attribute(L, me->se, w->p, index);

    return 0;
}


/**
 * __index function for the metatable used for userdata (widgets).  This is
 * to access a method or an attribute of the class, or a value stored by
 * the user with an arbitrary key.
 *
 * Input stack: 1=widget, 2=key
 * Return value: 0=nothing found, 1=found a value
 * Output stack: last element is the value, if found.
 */
int gtk_index(lua_State *L)
{
    int rc;

    rc = find_element(L, 1);

    /* Stack: 1=widget, 2=key, 3=metatable, 4=metatable,
     * 5=func or meta entry (if found) */
    switch (rc) {
	case 0:
	case 1:
	    return rc;
	
	case 2:
	    /* meta entry */
	    return handle_meta_entry(L);
	
	default:
	    printf("%s invalid return code %d from find_element\n", msgprefix,
		rc);
	    return 0;
    }
}


/**
 * Set existing attributes of an object, or arbitrary values.
 * The environment of the userdata will be used to store additional values.
 *
 * Input stack: 1=widget, 2=key, 3=value
 */
int gtk_newindex(lua_State *L)
{
    /* check parameters */
    if (lua_gettop(L) != 3) {
	printf("%s gtk_newindex not called with 3 parameters\n", msgprefix);
	return 0;
    }

    /* Is this an attribute of the underlying object? */
    int rc = find_element(L, 0);

    switch (rc) {
	case -1:
	    return 0;

	case 2:
	    handle_write_entry(L, 3);
	    return 0;
    }

    /* Not found, or existing entry in the object's environment table.  In both
     * cases store the value in the environment table. */

    lua_getfenv(L, 1);			    // w k v env

    /* actually, cannot(TM) happen.  Every Lua widget object gets an env tbl */
    if (lua_isnil(L, -1)) {		    // w k v nil
	printf("%s widget has no environment table!\n", msgprefix);
	lua_pop(L, 1);			    // w k v
	lua_newtable(L);		    // w k v env
	lua_pushvalue(L, -1);		    // w k v env env
	lua_setfenv(L, 1);		    // w k v env
    }

#if 1
    else {

	/* Is this the default empty table?  If so, create a new one private to
	 * this object. */
	lua_getglobal(L, "gtk");	    // w k v env gtk
	lua_getfield(L, -1, "emptyattr");   // w k v env gtk emptyattr
	if (lua_topointer(L, -1) == lua_topointer(L, -3)) {
	    lua_newtable(L);		    // w k v env gtk emptyattr t
	    lua_pushvalue(L, -1);	    // w k v env gtk emptyattr t t
	    lua_setfenv(L, 1);		    // w k v env gtk emptyattr t
	} else {
	    lua_pop(L, 2);		    // w k v env
	}
    }
#endif

    /* the top of the stack now has the table where to put the data */
    lua_replace(L, 1);			    // env k v [...]
    lua_settop(L, 3);			    // env k v
    lua_rawset(L, 1);			    // env 

    return 0;
}

/**
 * Initialize the library, returns a table.  Note that the table is also stored
 * as the global "gtk", because within this library the global table is
 * accessed sometimes.
 */
int luaopen_gtk(lua_State *L)
{
    if (!dl_init())
	return 0;

    /* make the table to return, and make it global as "gtk" */
    lua_newtable(L);

    lua_pushvalue(L, -1);
    lua_setglobal(L, "gtk");

    /* gtk._meta_tables */
    lua_pushstring(L, "_meta_tables");	// gtk "_mt"
    lua_newtable(L);			// gtk "_mt" t
    lua_newtable(L);			// gtk "_mt" t mt
    lua_pushstring(L, "v");		// gtk "_mt" t mt "v"
    lua_setfield(L, -2, "__mode");	// gtk "_mt" t mt
    lua_setmetatable(L, -2);		// gtk "_mt" t
    lua_rawset(L, -3);			// gtk
    
    /* gtk.widgets */
    lua_pushstring(L, "widgets");	// gtk "widgets"
    lua_newtable(L);			// gtk "widgets" t
    lua_newtable(L);			// gtk "widgets" t mt
    lua_pushcfunction(L, l_getwidget);
    lua_setfield(L, -2, "__index");

    /**
     * Automatically remove unused widgets.  Be sure to keep references
     * to those you need, especially those that have additional data,
     * i.e. an environment attached.
     */
    lua_pushstring(L, "v");		// gtk "widgets" t mt "v"
    lua_setfield(L, -2, "__mode");	// gtk "widgets" t mt
    lua_setmetatable(L, -2);		// gtk "widgets" t
    lua_rawset(L, -3);			// gtk

    /* default attribute table of a widget */
#if 1
    lua_pushstring(L, "emptyattr");	// gtk "emptyattr"
    lua_newtable(L);			// gtk "emptyattr" t
    lua_rawset(L, -3);			// gtk
#endif

    /* execute the glue library (compiled in) */
    luaL_loadbuffer(L, override_data, override_size, "override.lua");
    lua_pcall(L, 0, 0, 0);

    /* define meta table (itself) and functions */
    lua_pushvalue(L, -1);
    lua_setmetatable(L, -2);
    luaL_openlib(L, NULL, gtk_methods, 0);

    /* one retval on the stack: gtk.  This is usually not used anywhere,
     * but you have to use the global variable "gtk". */
    return 1;
}

