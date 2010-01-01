/* vim:sw=4:sts=4
 *
 * Library to use the Gnome family of libraries from Lua 5.1
 * Copyright (C) 2005, 2008 Wolfgang Oertl
 * Use this software under the terms of the GPLv2 (the license of Gnome).
 *
 * Library initialization, and a few basic routines which could as well
 * be in object.c.
 *
 * Revision history:
 *  2005-07-24	first public release
 *  2005-08-18	update for Lua 5.1-work6
 *  2007-02-02	(almost) no global Lua state; use luaL_ref
 *  2007-10-12	improved modularization of the code; ENUM typechecking
 *
 * Exported symbols:
 *  luaopen_gnome
 *  msgprefix
 *  lib_name
 */

#include "luagnome.h"
#include "module.h"
#include <string.h>	    // strcpy
#include <glib.h>
#include <stdlib.h>	    // abort

const char msgprefix[] = "[LuaGnome]";
const char *thismodulename = "gnome";
char *lib_name;

/**
 * Main module for the Lua-Gnome binding.
 * @class module
 * @name gnome
 */

/*-
 * A method has been found and should now be called.
 * input stack: parameters to the function
 * upvalues: the func_info structure
 */
static int lg_call_wrapper(lua_State *L)
{
    struct func_info *fi = (struct func_info*) lua_touserdata(L,
	lua_upvalueindex(1));
    return lg_call(L, fi, 1);
}


/**
 * Create a closure for a C (library) function.  The function info may be
 * static, which is for elements of structures, or dynamically created, as
 * is the case for regular library functions.
 *
 * XXX when alloc_fi is not 0, when will this memory be freed again?
 *
 * @param L  Lua State
 * @param fi  Function Info with name, address and signature
 * @param alloc_fi  0=use fi as-is; 1=duplicate the structure; 2=also duplicate
 *  the name.
 */
int lg_push_closure(lua_State *L, const struct func_info *fi, int alloc_fi)
{
    int name_len;
    struct func_info *fi2;
    
    switch (alloc_fi) {
	case 0:
	lua_pushlightuserdata(L, (void*) fi);
	break;

	case 1:
	fi2 = (struct func_info*) lua_newuserdata(L, sizeof(*fi2));
	memcpy(fi2, fi, sizeof(*fi2));
	break;

	case 2:
	name_len = strlen(fi->name) + 1;
	fi2 = (struct func_info*) lua_newuserdata(L, sizeof(*fi2) + name_len);
	memcpy(fi2, fi, sizeof(*fi2));
	memcpy(fi2+1, fi->name, name_len);
	fi2->name = (char*) (fi2+1);
	break;

	default:
	return luaL_error(L, "%s invalid call to lg_push_closure", msgprefix);
    }

    lua_pushcclosure(L, lg_call_wrapper, 1);
    return 1;
}


/**
 * A function should be used as a function pointer.  If this is a C closure
 * to a library function, we can use that library function's address directly.
 * This avoids a C closure for a Lua closure, the invocation of which would
 * look like this: FFI closure -> closure_handler -> lg_call_wrapper -> library
 * function.
 *
 * @return  1 on success, i.e. ar->arg->p has been set to the C function, or 0
 *  otherwise.
 */
int lg_use_c_closure(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    lua_CFunction func = lua_tocfunction(L, ar->index);
    if (!func || func != &lg_call_wrapper)
	return 0;

    // the first upvalue of this closure is a struct fi
    if (lua_getupvalue(L, ar->index, 1)) {
	struct func_info *fi = (struct func_info*) lua_touserdata(L, -1);
	ar->arg->p = fi->func;
	lua_pop(L, 1);
	return 1;
    }

    return 0;
}




/**
 * The specified Lua value might contain a closure created with the function
 * above, or contain a .  If so, return the func_info embedded in it, otherwise raise an
 * error.
 */
struct func_info *lg_get_closure(lua_State *L, int index)
{
    lua_CFunction f;
    struct func_info *fi;

    // verify that this is actually a closure with the correct C function.
    f = lua_tocfunction(L, index);
    if (!f)
	LG_ERROR(2, "Not a C function, but a %s.",
	    lua_typename(L, lua_type(L, index)));
    if (f != &lg_call_wrapper)
	LG_ERROR(3, "Invalid closure.");

    // the first upvalue is the func_info structure.
    lua_getupvalue(L, index, 1);
    fi = (struct func_info*) lua_touserdata(L, -1);
    if (!fi)
	LG_ERROR(4, "Invalid closure (upvalue 1 not a userdata)");

    return fi;
}


/**
 * Look up a name in the given module.  This works for functions, like
 * gtk.window_new(), and constants, like gtk.WINDOW_TOPLEVEL.
 * Lua Stack: [1]=gnome [2]=name
 *
 * @name __index
 * @luaparam table     The table to look in
 * @luaparam key       The name of the item to look up
 * @luareturn          Either a userdata (for ENUMs) or a closure (for
 *			functions)
 */
static int lg_generic_index(lua_State *L)
{
    size_t name_len, prefix_len = 0;
    const char *name = luaL_checklstring(L, 2, &name_len);
    struct func_info fi = { 0 };
    char symname[70];
    cmi mi;

    // Get the module.  No checks here because this function is called
    // by Lua and should always have the correct arguments.
    lua_getfield(L, 1, "_modinfo");
    mi = lua_touserdata(L, -1);
    lua_pop(L, 1);

    // check arguments
    if (!name || !*name)
	return luaL_error(L, "%s attempt to look up a NULL or empty string",
	    msgprefix);
    prefix_len = strlen(mi->prefix_func);
    prefix_len = MAX(prefix_len, strlen(mi->prefix_constant));
    if (name_len + prefix_len > sizeof(symname) - 10)
	return luaL_error(L, "%s key is too long, max is %d", msgprefix,
	    sizeof(symname) - 10);

    /* if it starts with an uppercase letter, it's probably an ENUM. */
    if (name[0] >= 'A' && name[0] <= 'Z') {
	int val;
	const char *prefix = mi->prefix_constant;

	typespec_t ts = { 0 };
	ts.module_idx = mi->module_idx;
	for (;;) {
	    sprintf(symname, "%s%s", prefix ? prefix : "", name);
	    // strcpy(symname, prefix);
	    // strcat(symname, name);
	    switch (lg_find_constant(L, &ts, symname, -1, &val)) {
		case 1:		// ENUM/FLAG found
		return lg_push_constant(L, ts, val);

		case 2:		// integer found
		lua_pushinteger(L, val);
		/* fall through */

		case 3:		// string found - is on Lua stack
		return 1;
	    }
	    if (!prefix)
		break;
	    prefix = NULL;
	}
    }

    // If it starts with "__", then remove that and don't look for
    // overrides.  This is something that overrides written in Lua can use,
    // to avoid recursively calling itself instead of the Gtk function.
    if (name[0] == '_' && name[1] == '_') {
	strcpy(symname, name + 2);
	if (!lg_find_func(L, mi, symname, &fi))
	    return luaL_error(L, "%s not found: %s.%s", msgprefix, mi->name,
		name);
	goto found_func;
    }

    // Check for an override (with the function prefix).
    strcpy(symname, mi->prefix_func);
    strcat(symname, name);
    lua_pushstring(L, symname);
    lua_rawget(L, 1);
    if (!lua_isnil(L, -1)) {
	lua_pushstring(L, name);
	lua_pushvalue(L, -2);
	lua_rawset(L, 1);
	return 1;
    }
    lua_pop(L, 1);

    // Otherwise, simply look it up
    if (lg_find_func(L, mi, symname, &fi))
	goto found_func;

    // maybe it's a function but with the prefix already added.
    if (*mi->prefix_func && lg_find_func(L, mi, name, &fi))
	goto found_func;
    
    // Might be a global variable.  This is not so common, therefore
    // it is not checked for earlier.
    if (lg_find_global(L, mi, symname))
	return 1;

    // "name" might not need the prefix.
    if (lg_find_global(L, mi, name))
	return 1;
    
    // Maybe it's Windows and a function with _utf8 suffix?  While there
    // are a few with the gtk_ prefix and _utf8 suffix, most have the
    // g_ or gdk_ prefix, so don't automatically add this prefix.
#ifdef LUAGTK_win32
    strcat(symname, "_utf8");
    // sprintf(symname, "%s%s_utf8", prefix_func, name);
    if (lg_find_func(L, mi, symname, &fi))
	goto found_func;
#endif

    // Not found.
    return luaL_error(L, "%s not found: %s.%s", msgprefix, mi->name, name);

found_func:;
    lg_push_closure(L, &fi, 2);

    // cache the result of this lookup, using the key given by the user,
    // and not necessarily the name of the function that was found.
    lua_pushvalue(L, 2);	// key
    lua_pushvalue(L, -2);	// the new closure
    lua_rawset(L, 1);		// [1]=table

    return 1;
}


/**
 * If a module doesn't provide a handler to allocate objects, use this
 * default handler.
 */
static void *default_allocate_object(cmi mi, lua_State *L, typespec_t ts,
    int count, int *flags)
{
    type_info_t ti = mi->type_list + ts.type_idx;
    void *p;

    if (count) {
	*flags = FLAG_ARRAY | FLAG_NEW_OBJECT;
	p = g_malloc(ti->st.struct_size * count);
    } else {
	*flags = FLAG_ALLOCATED | FLAG_NEW_OBJECT;
	p = g_slice_alloc0(ti->st.struct_size);
    }

    return p;
}


/**
 * Allocate a structure, initialize with zero and return it.
 *
 * This is NOT intended for objects or structures that have specialized
 * creator functions, like gtk_window_new and such.  Use it for simple
 * structures like GtkTreeIter.
 *
 * The object is, as usual, a Lua wrapper in the form of a userdata,
 * containing a pointer to the actual object.
 *
 * @param L  Lua State
 * @param mi  Module that handles the type
 * @param is_array  If true, Stack[2] is the count, else allocate a single
 *  object.
 *
 * @luaparam typename  Type of the structure to allocate
 * @luaparam ...  array size, or optional additional arguments to the allocator
 *	function.
 * @luareturn The new structure
 */
static int lg_generic_new_array(lua_State *L, cmi mi, int is_array)
{
    typespec_t ts;
    void *p;
    char tmp_name[80];
    const char *type_name;
    int flags;
    const char *name_in = luaL_checkstring(L, 1);
    int count = 0;

    if (is_array) {
	count = luaL_checknumber(L, 2);
	if (count <= 0)
	    return luaL_error(L, "%s Invalid array size %d", msgprefix, count);
    }

    // add the prefix if available.
    if (mi->prefix_type) {
	strcpy(tmp_name, mi->prefix_type);
	strcat(tmp_name, name_in);
	type_name = tmp_name;
    } else
	type_name = name_in;

    // look for the type; if not found, try again without the prefix.
    for (;;) {
	ts = lg_find_struct(L, type_name, 1);
	if (ts.value)
	    break;
	ts = lg_find_struct(L, type_name, 0);
	if (ts.value)
	    break;
	if (type_name == name_in)
	    return luaL_error(L, "%s type %s* not found\n", msgprefix,
		type_name);
	type_name = name_in;
    }

    /* There may be an allocator function; if so, use it (but only for single
     * objects, not for arrays); use the optional additional arguments */
    if (count == 0) {
	char func_name[80];
	struct func_info fi;

	lg_make_func_name(mi, func_name, sizeof(func_name), type_name, "new");
	if (lg_find_func(L, mi, func_name, &fi))
	    return lg_call(L, &fi, 2);
    }

    /* no additional arguments must be given - they won't be used. */
    luaL_checktype(L, 3, LUA_TNONE);

    if (mi->allocate_object)
	p = mi->allocate_object(mi, L, ts, count, &flags);
    else
	p = default_allocate_object(mi, L, ts, count, &flags);

    /* Allocate and initialize the object.  I used to allocate just one
     * userdata big enough for both the wrapper and the object, but many free
     * functions exist, like gtk_tree_iter_free, and they expect a memory block
     * allocated by g_slice_alloc0.  Therefore this optimization is not
     * possible. */

    /* Make a Lua wrapper for it, push it on the stack.  FLAG_ALLOCATED causes
     * the _malloc_handler be used, and FLAG_NEW_OBJECT makes it not complain
     * about increasing the (non existant) refcounter. */
    lg_get_object(L, p, ts, flags);

    if (count) {
	struct object *w = (struct object*) lua_touserdata(L, -1);
	w->array_size = count;
    }
    
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
static int lg_get_osname(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TNONE);
    lua_pushliteral(L, LUAGTK_ARCH_OS);
    lua_pushliteral(L, LUAGTK_ARCH_CPU);
    return 2;
}

static int lg_void_ptr(lua_State *L)
{
    luaL_checkany(L, 1);
    luaL_checktype(L, 2, LUA_TNONE);
    struct value_wrapper *p = lg_make_value_wrapper(L, 1);
    return lg_push_vwrapper_wrapper(L, p);
}

static const char _module_info[] =
    "_VERSION\0"
    LUAGTK_VERSION "\0"
    "_DESCRIPTION\0"
    "LuaGnome is a binding to the Gnome family of librarlies, like GLib, GDK,\n"
    "Gtk and others for easy development of GUI applications.\0"
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


/**
 * When a proxy object should be destroyed right away, without waiting for
 * the garbage collection, this can be used.
 */
static int lg_destroy(lua_State *L)
{
    struct object *o = (struct object*) lua_touserdata(L, 1);

    // dec_refcount sets the pointer to NULL, which disturbs
    // lg_invalidate_object (which sets it to NULL itself).
    void *p = o->p;
    lg_dec_refcount(L, o);
    o->p = p;

    lg_invalidate_object(L, o);
    return 0;
}


/**
 * An object (or a simple pointer) should be cast to another type.
 */
static int lg_cast(lua_State *L)
{
    int t;
    void *p;

    t = lua_type(L, 1);

    if (t == LUA_TLIGHTUSERDATA) {
	p = (void*) lua_topointer(L, 1);
    } else if (t == LUA_TUSERDATA) {
	struct object *o = (struct object*) lua_topointer(L, 1);
	if (!o)
	    return luaL_error(L, "%s cast with NULL object", msgprefix);
	p = o->p;
    } else
	return luaL_argerror(L, 1,
	    "Either a widget or a simple pointer expected.");

    /* second argument is the requested type */
    const char *type_name = luaL_checkstring(L, 2);
    typespec_t ts = lg_find_struct(L, type_name, 1);
    if (!ts.value)
	    return luaL_error(L, "%s cast to unknown type %s", msgprefix,
		type_name);
    lg_get_object(L, p, ts, FLAG_NOT_NEW_OBJECT);
    return 1;
}

/* in voidptr.c */
int lg_dump_vwrappers(lua_State *L);
int lg_get_vwrapper_count(lua_State *L);

/* methods directly callable from Lua; most go through __index of
 * the individual modules, which call api->generic_index. */
static const luaL_reg gnome_methods[] = {
    {"get_osname",	lg_get_osname },
    {"void_ptr",	lg_void_ptr },
    {"dump_vwrappers",	lg_dump_vwrappers },
    {"get_vwrapper_count", lg_get_vwrapper_count },
    {"destroy",		lg_destroy },
    {"cast",		lg_cast },
    { NULL, NULL }
};


/*-
 * This is the structure accessible from library modules and the only way
 * how library modules can call into the base library.
 */
static struct lg_module_api module_api = {
    LUAGNOME_MODULE_MAJOR,
    LUAGNOME_MODULE_MINOR,
    LUAGNOME_HASH_METHOD,
    msgprefix,
    lg_register_module,
    lg_register_object_type,

    lg_get_object_name,
    lg_generic_index,
    lg_generic_new_array,
    lg_get_type_name,
    lg_find_struct,
    lg_optional_func,
    lg_call_byname,
    lg_call_function,
    lg_lua_to_gvalue_cast,
    lg_find_object_type,
    lg_gtype_from_name,
    lg_get_object,
    lg_get_object_type,
    lg_invalidate_object,
    lg_gvalue_to_lua,
    lg_object_arg,
    lg_push_constant,
    lg_get_constant,
    lg_empty_table,
    lg_find_module,
};

#ifdef RUNTIME_LINKING
extern const char gnome_dynlink_names[];
#endif

static struct dynlink gnome_dynlink = {
#ifdef LUAGTK_LIBRARIES
    dll_list: LUAGTK_LIBRARIES,
#endif
#ifdef RUNTIME_LINKING
    dynlink_names: gnome_dynlink_names,
    dynlink_table: gnome_dynlink_table,
#endif
};


extern struct call_info *ci_current;
static void lg_log_func(const gchar *domain, GLogLevelFlags log_level,
    const gchar *message, gpointer user_data)
{
    if (ci_current)
	call_info_warn(ci_current);
    fprintf(stderr, "%s\n", message);
    if (log_level & G_LOG_FLAG_FATAL)
	abort();
}

/**
 * Initialize the library, returns a table.  This function is called by Lua
 * when this library is dynamically loaded.  Note that the table is also stored
 * as the global "gnome" (by the "require" command), and that is accessed
 * from this library sometimes.
 *
 * @luaparam name  This library's name, i.e. "gnome".
 */
int luaopen_gnome(lua_State *L)
{
    // get this module's name, then discard the argument.
    lib_name = strdup(lua_tostring(L, 1));
    lg_dl_init(L, &gnome_dynlink);
    lua_settop(L, 0);
    lg_debug_flags_global(L);

    g_type_init();

    /* make the table to return, and make it global as "gnome" */
    luaL_register(L, lib_name, gnome_methods);
    _init_module_info(L);
    lg_init_object(L);
    lg_init_debug(L);
    lg_init_boxed(L);
    lg_init_closure(L);

    // an object that can be used as NIL
    lua_pushliteral(L, "NIL");
    lua_pushlightuserdata(L, NULL);
    lua_rawset(L, -3);

    // a metatable to make another table have weak values
    lua_newtable(L);			// gnome mt
    lua_pushliteral(L, "v");		// gnome mt "v"
    lua_setfield(L, -2, "__mode");	// gnome mt

    // Table with all object metatables; [name] = table.  When no objects
    // of the given type exist anymore, they may be removed if weak values
    // are used; this doesn't make much sense, as a program will most likely
    // use a certain object type again if it is used once.
    lua_newtable(L);			// gnome mt t
    lua_setfield(L, 1, LUAGTK_METATABLES);	// gnome mt
    
    // objects: not a weak table.  It only contains references to entries
    // in the aliases table; they are removed manually when the last alias
    // is garbage collected.
    lua_newtable(L);			    // gnome mt t
    lua_setfield(L, 1, LUAGTK_WIDGETS);    // gnome mt

    // gnome.objects_aliases.  It has automatic garbage collection (weak
    // values)
    lua_newtable(L);
    lua_pushvalue(L, -2);
    lua_setmetatable(L, -2);
    lua_setfield(L, 1, LUAGTK_ALIASES);    // gnome mt

    // gnome.typemap is a table that maps hash values of native types to
    // their typespec_t.  It is required in lg_type_normalize.
    lua_newtable(L);
    lua_setfield(L, 1, "typemap");

    // gnome.fundamental_map is a table that maps hash values of fundamental
    // types to their index in ffi_type_map.
    lg_create_fundamental_map(L);

    lua_pop(L, 1);			    // gnome


    /* default attribute table of an object */
    lua_newtable(L);			    // gnome t
    lua_setfield(L, 1, LUAGTK_EMPTYATTR);

    /* execute the glue library (compiled in) */
    // XXX this should be moved to the modules
    // luaL_loadbuffer(L, override_data, override_size, "override.lua");
    // lua_pcall(L, 0, 0, 0);

    // make gnome its own metatable - it contains __index and maybe other
    // special methods.
    lua_pushvalue(L, -1);
    lua_setmetatable(L, -2);

    // Add the API
    lua_pushlightuserdata(L, &module_api);
    lua_setfield(L, 1, "api");

    // Can't initialize Gtk right away: if memory tracing is used, it must
    // be activated first; otherwise, initial allocations are not noted and
    // lead to errors later on, e.g. when a block is reallocated.
    // gtk_init(NULL, NULL);

    // set up error logging to be more useful: display which function is
    // currently running before showing the error message.
    g_log_set_default_handler(lg_log_func, NULL);

    /* one retval on the stack: gnome.  This is usually not used anywhere,
     * but you have to use the global variable "gnome". */
    return 1;
}

