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
 * Exported symbols:
 *  luagtk_init_gtk
 *  luaopen_gtk
 *  msgprefix
 *  is_initialized
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_error
#include <string.h>	    // strcpy


/* in _override.c */
extern char override_data[];
extern int override_size;

int gtk_is_initialized = 0;
const char msgprefix[] = "[gtk]";

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
 * Lua Stack: [1]=gtk [2]=name
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

    if (!s)
	return luaL_error(L, "%s attempt to look up a NULL string", msgprefix);

    GTK_INITIALIZE();

    /* if it starts with an uppercase letter, it's probably an ENUM. */
    if (s[0] >= 'A' && s[0] <= 'Z') {
	int val, type_idx;
	switch (find_enum(L, s, -1, &val, &type_idx)) {
	    case 1:		// ENUM/FLAG found
	    return luagtk_enum_push(L, val, type_idx);

	    case 2:		// integer found
	    lua_pushinteger(L, val);
	    /* fall through */

	    case 3:		// string found - is on Lua stack
	    return 1;
	}
    }

    // If it starts with "__", then remove that and don't look for overrides.
    // this is something that overrides written in Lua can use.
    if (s[0] != '_' || s[1] != '_') {
	strcpy(func_name, s);
	if (!find_func(func_name, &fi)) {
	    sprintf(func_name, "gtk_%s", s);

	    // check for overrides
	    lua_pushstring(L, func_name);
	    lua_rawget(L, 1);
	    if (!lua_isnil(L, -1))
		return 1;
	    lua_pop(L, 1);

	    // If not found, throw an error.  Alternatively 0 could be returned,
	    // but mistyped gtk.something lookups would silently return nil,
	    // possibly leading to hard-to-find bugs.
	    if (!find_func(func_name, &fi))
		return luaL_error(L, "%s not found: gtk.%s", msgprefix, s);
	}
    } else {
	// prefixed by "__" - look it up directly.
	strcpy(func_name, s + 2);
	if (!find_func(func_name, &fi))
	    return luaL_error(L, "%s not found: gtk.%s", msgprefix, s);
    }


    /* A function has been found, so return a closure that can call it. */
    // NOTE: need to duplicate the name, fi.name points to the local variable
    // func_name.  So, allocate a new func_info with some space after it large
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


/*-
 * For some classes, no _new function exists, but a _free function does.
 * Newer Gtk versions tend to use GSlice, but this hasn't always been so.
 * In order to make lua-gtk compatible with older versions, in certain
 * cases g_malloc has to be used to allocate certain classes.
 *
 * Note that the _runtime_ Gtk version is compared and not the compile time;
 * this ensures that even when compiled with a new Gtk library, it will work
 * with older versions.
 *
 * See http://svn.gnome.org/viewvc/gtk%2B/
 */
#define _VERSION(x,y,z) ((x)*10000 + (y)*100 + (z))
static const struct special_alloc {
    const char *struct_name;
    int version_from, version_to;	// range of Gtk versions using g_malloc
    int what;				// 1=g_malloc, 2=GdkColor
} special_alloc[] = {
    { "GtkTreeIter", 0, _VERSION(2,10,11), 1 },	// SVN version 17761
    { "GdkColor", 0, _VERSION(2,8,8), 2 },	// SVN version 14359
    { NULL, 0, 0, 0 }
};


/**
 * Determine how to allocate a given structure.
 *
 * @param  struct_name  Name of the structure to allocate
 * @return 0=use g_slice_alloc, 1=use g_malloc, 2=special case for GdkColor
 */
static int _special_alloc(const char *struct_name)
{
    const struct special_alloc *p;
    int version = _VERSION(gtk_major_version, gtk_minor_version,
	gtk_micro_version);

    for (p=special_alloc; p->struct_name; p++)
	if (!strcmp(struct_name, p->struct_name)
	    && p->version_from <= version && version <= p->version_to)
	    return p->what;

    return 0;
}
#undef _VERSION


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
    const struct type_info *ti;
    void *p;
    struct func_info fi;
    char tmp_name[80];
    int rc;

    GTK_INITIALIZE();

    if (!(ti=find_struct(struct_name, 1))) {
	printf("%s structure %s not found\n", msgprefix, struct_name);
	return 0;
    }

    /* There may be an allocator function; if so, use it; any additional
     * parameters to this function start at Lua stack position 2, use them. */
    luagtk_make_func_name(tmp_name, sizeof(tmp_name), struct_name, "new");
    if (find_func(tmp_name, &fi))
	return luagtk_call(L, &fi, 2);

    /* Some objects don't use the GSlice mechanism, depending on the Gtk
     * version.  Allocation would be fine, but calling the free or copy
     * function would mess things up. */
    rc = _special_alloc(struct_name);
    switch (rc) {
	case 0:
	    p = g_slice_alloc0(ti->st.struct_size);
	    break;
	
	case 1:
	    p = g_malloc(ti->st.struct_size);
	    break;
	
	case 2:;
	    // No gdk_color_new function exists.  Instead, call the copy
	    // function with allocates it.  This works for any Gtk version, but
	    // is required before 2.8.8.
	    GdkColor c = { 0, 0, 0, 0 };
	    p = (void*) gdk_color_copy(&c);
	    break;
	
	default:
	    return luaL_error(L, "%s _special_alloc returned invalid value %d",
		msgprefix, rc);
    }

    /* Allocate and initialize the object.  I used to allocate just one
     * userdata big enough for both the wrapper and the widget, but many free
     * functions exist, like gtk_tree_iter_free, and they expect a memory block
     * allocated by g_slice_alloc0.  Therefore this optimization is not
     * possible. */

    /* Make a Lua wrapper for it, push it on the stack.  FLAG_ALLOCATED causes
     * the _malloc_handler be used, and FLAG_NEW_OBJECT makes it not complain
     * about increasing the (non existant) refcounter. */
    luagtk_get_widget(L, p, ti - type_list, FLAG_ALLOCATED | FLAG_NEW_OBJECT);
    return 1;
}


/**
 * Give the application an idea of the platform.  Could be used to select
 * path separators and more.  I have not found a way to determine this
 * in any other way, so far.
 *
 * @name get_osname
 * @luareturn  The the operating system, e.g. "win32" or "linux".
 * @luareturn  The CPU, e.g. "i386", "amd64"
 */
static int l_get_osname(lua_State *L)
{
    lua_pushliteral(L, LUAGTK_ARCH_OS);
    lua_pushliteral(L, LUAGTK_ARCH_CPU);
    return 2;
}

static const char _module_info[] =
    "_VERSION\0"
    LUAGTK_VERSION "\0"
    "_DESCRIPTION\0"
    "LuaGtk is a binding to Gtk 2.x for easy development of GUI applications.\0"
    "_COPYRIGHT\0"
    "Copyright (C) 2006, 2008 Wolfgang Oertl\0"
    "\0";

/**
 * Add some meta information to the new module.
 */
static void _init_module_info(lua_State *L)
{
    const char *s = _module_info;

    while (*s) {
	lua_pushstring(L, s);	    /* name */
	s += strlen(s) + 1;
	lua_pushstring(L, s);	    /* value */
	lua_rawset(L, -3);
	s += strlen(s) + 1;
    }
}

/* methods directly callable from Lua; most go through __index */
static const luaL_reg gtk_methods[] = {
    {"__index",		l_gtk_lookup },
    {"new",		l_new },
    {"get_osname",	l_get_osname },
    { NULL, NULL }
};


/**
 * Initialize the library, returns a table.  This function is called by Lua
 * when this library is dynamically loaded.  Note that the table is also stored
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
    _init_module_info(L);
    luagtk_init_widget(L);
    luagtk_init_overrides(L);
    luagtk_init_channel(L);
    luagtk_init_debug(L);

    // an object that can be used as NIL
    lua_pushliteral(L, "NIL");
    lua_pushlightuserdata(L, NULL);
    lua_rawset(L, -3);

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

