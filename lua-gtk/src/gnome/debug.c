/* vim:sw=4:sts=4
 * Library to use the Gtk2 widget library from Lua 5.1
 * Copyright (C) 2055, 2007 Wolfgang Oertl
 *
 * Debugging functions - like stack trace, memory dump, call tracing, function
 * signatures etc.
 *
 * Exported symbols:
 *   lg_init_debug
 *   lg_breakfunc
 *   lg_call_trace
 *   lg_object_tostring
 *   lg_debug_flags_global
 */

#include "luagnome.h"
#include <string.h>	    // strcpy
#include <stdlib.h>	    // atexit
#include <ctype.h>	    // isspace

int runtime_flags = 0;	    // see RUNTIME_xxx constants in luagtk.h


#ifdef LUAGNOME_DEBUG_FUNCS

/**
 * While debugging you can add a call to this function anywhere in the C code,
 * then run it with the debugger (e.g. gdb) and set a breakpoint here.  Or
 * you could call it from Lua like this: gtk.breakfunc().
 */
int lg_breakfunc(lua_State *L) {
    printf("BREAK\n");
    return 0;
}

/* required only for debugging; this header file is in the Lua source tree. */
#include "lstate.h"

/**
 * Display the contents of the Lua stack.
 *
 * If a parameter is given, and is non-zero, then start at the absolute
 * stack base; else dump only the stack frame of the current function.
 *
 * Note that the standard Lua function debug.traceback() also traverses the
 * Lua stack, but only shows function calls, whereas this function shows
 * all values on the stack.  It is useful to find stack related bugs.
 */
static int _dump_stack(lua_State *L, int everything)
{
    StkId ptr;
    char s[100];

    printf("STACK DUMP\n");

    for(ptr = everything ? L->base_ci->base : L->base; ptr<L->top; ptr++) {
	switch (ptr->tt) {
	    case LUA_TBOOLEAN:
		sprintf(s, "%s", ptr->value.b ? "true" : "false");
		break;
	    case LUA_TUSERDATA:
	    case LUA_TLIGHTUSERDATA:
	    case LUA_TTABLE:
		sprintf(s, "%p", ptr->value.p);
		break;
	    case LUA_TFUNCTION:;
		GCObject *gco = ptr->value.gc;
		if (gco->cl.c.isC)
		    sprintf(s, "C function at %p", ptr->value.p);
		else {
		    struct Proto *p = gco->cl.l.p;
		    sprintf(s, "Lua function %s:%d", (char*)
			(p->source+1)+1, p->lineinfo ? p->lineinfo[0] : -1);
		}
		break;
	    case LUA_TSTRING:
		sprintf(s, "%s", ((char*)&ptr->value.gc->ts.tsv)
		    + sizeof(TString));
		break;
	    case LUA_TNUMBER:
		sprintf(s, "%f", ptr->value.n);
		break;
	    case LUA_TNIL:
		*s = 0;
		break;

	    default:
		strcpy(s, "?");
	}
	printf("  %d %s %s\n",
	    (int)(ptr - L->base + 1),
	    lua_typename(L, ptr->tt),
	    s);
    }

    return 0;
}


/**
 * Run a stack dump from the current stack frame.
 *
 * @name dump_stack
 * @luaparam everything  If true is given, dump the complete Lua stack, else
 *   only the current function's stack.
 */
static int l_dump_stack(lua_State *L)
{
    int everything = lua_gettop(L) > 0 ? lua_toboolean(L, 1) : 0;
    return _dump_stack(L, everything);
}

#endif


/**
 * Called for a structure, return a printable representation.  This is the
 * default routine if no specialized tostring exists (e.g., for GValue).
 *
 * stack: object
 */
int lg_object_tostring(lua_State *L)
{
    struct object *w = (struct object*) lua_touserdata(L, 1);
    const char *class_name;
    typespec_t ts;

    lua_getmetatable(L, -1);
    lua_pushliteral(L, "_typespec");
    lua_rawget(L, -2);
    ts.value = lua_tonumber(L, -1);
    lua_pop(L, 2);
    class_name =  lg_get_type_name(ts);

    if (strcmp(class_name, "GValue")) {
	char buf[50];
	sprintf(buf, "%s at %p/%p", class_name, w, w->p);
	lua_pushstring(L, buf);
    } else {
	GValue *gvalue = (GValue*) w->p;
	// lua_pushliteral(L, "GValue:");
	lg_gvalue_to_lua(L, gvalue);

	// convert the value to a string
	lua_getfield(L, LUA_GLOBALSINDEX, "tostring");
	lua_insert(L, -2);
	lua_call(L, 1, 1);
	// lua_concat(L, 2);
    }

    return 1;
}


/**
 * Returns the function's signature as string.  Can be accessed from Lua by
 * calling gnome.function_sig(fname).
 *
 * @param fi    Pointer to a function info struct as filled in by #lg_find_func.
 * @param align  Pad return type to this length
 * @return      A string on the Lua stack; 1 from the C function.
 */
int function_signature(lua_State *L, const struct func_info *fi,
    int align)
{
    const unsigned char *args = fi->args_info, *args_end = args + fi->args_len;
    int arg_nr, i, retval_len=0;
    struct argconv_t ar;
    const struct ffi_type_map_t *arg_type;
    const char *type_name;
    type_info_t ti;
    luaL_Buffer buf;

    luaL_buffinit(L, &buf);

    for (arg_nr=0; args < args_end; arg_nr++) {
	ar.ts.module_idx = fi->module_idx;
	get_next_argument(L, &args, &ar);
	ti = modules[ar.ts.module_idx]->type_list + ar.ts.type_idx;
	arg_type = lg_get_ffi_type(ar.ts);
	type_name = lg_get_type_name(ar.ts);

	if (arg_nr > 1)
	    luaL_addstring(&buf, ", ");

	/* type name plus one * for each level of indirection. */
	if (ti->st.is_const) {
	    luaL_addstring(&buf, "const ");
	    retval_len += 6;
	}
	luaL_addstring(&buf, type_name);
	if (ti->st.genus == 3 || ti->st.genus == 1) {
	    for (i=0; i<ti->st.indirections; i++)
		luaL_addchar(&buf, '*');
	    retval_len += ti->st.indirections;
	}


	if (arg_nr == 0) {
	    if (align) {
		retval_len += strlen(type_name);
		while (retval_len < align) {
		    luaL_addchar(&buf, ' ');
		    retval_len ++;
		}
	    }
	    luaL_addchar(&buf, ' ');
	    luaL_addstring(&buf, fi->name);
	    luaL_addchar(&buf, '(');
	}
    }

    luaL_addchar(&buf, ')');
    luaL_pushresult(&buf);

    return 1;
}


/**
 * Get the function signature for a closure that has been created for a
 * library function.  This is easier to use than the module/functionname
 * method.
 *
 * @luaparam  closure  The closure representing a library function
 * @luaparam  align  (optional) Minimum width of return value type
 * @luareturn  A string with the function signature.
 */
static int _function_sig_for_closure(lua_State *L)
{
    int align = lua_gettop(L) > 1 ? luaL_checknumber(L, 2) : 0;
    return function_signature(L, lg_get_closure(L, 1), align);
}


/**
 * Get the function signature, similar to a C declaration.  No closure needs
 * to be allocated for the function in order for this to work.
 *
 * @name function_sig
 * @luaparam module  The module the function is in (a table)
 * @luaparam name  The function name
 * @luaparam align  (optional) Minimum width of the return value
 * @luareturn A string with the function signature.
 */
static int l_function_sig(lua_State *L)
{
    int type = lua_type(L, 1);

    if (type == LUA_TFUNCTION)
	return _function_sig_for_closure(L);

    if (type != LUA_TTABLE)
	return luaL_error(L, "%s expected either a closure, or a module and "
	    "a function name.", msgprefix);

    const char *fname = luaL_checkstring(L, 2);
    struct func_info fi;
    int align = 0;

    // get the module
    lua_getfield(L, 1, "_modinfo");
    if (!lua_islightuserdata(L, -1))
	luaL_argerror(L, 1, "is not a module (e.g. glib)");
    cmi mi = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (!lg_find_func(L, mi, fname, &fi)) {
	lua_pushfstring(L, "%s%s", mi->prefix_func, fname);
	const char *tmp_name = lua_tostring(L, -1);
	if (!lg_find_func(L, mi, tmp_name, &fi)) {
	    luaL_error(L, "%s function %s not found in module %s",
		msgprefix, fname, mi->name);
	}
	lua_pop(L, 1);
    }

    if (lua_gettop(L) > 2)
	align = luaL_checknumber(L, 3);

    return function_signature(L, &fi, align);
}


/**
 * Display the current Gtk call on stderr; this is used either to trace all
 * calls or to show where an error/warning happened.  Outputs the current
 * Lua source position, return value, function name and all parameter types.
 *
 * NOTE: this is required even when debugging is off (--disable-debug) because
 * warning and error messages still have to be displayed.
 *
 * @param L  Lua State
 * @param fi  Pointer to the function information structure
 * @param index  Lua stack position of function's first argument (currently
 *	unused)
 */
void lg_call_trace(lua_State *L, struct func_info *fi, int index)
{
    /* Find out from where in the Lua code this library function has been
     * called */
    lua_Debug ar;
    if (lua_getstack(L, 1, &ar)) {
	if (lua_getinfo(L, "Sl", &ar)) {
	    fprintf(stderr, "%s(%d): ", ar.short_src, ar.currentline);
	}
    }

    if (function_signature(L, fi, 0)) {
	fprintf(stderr, "%s\n", lua_tostring(L, -1));
	lua_pop(L, 1);
    }
}

#ifdef LUAGNOME_DEBUG_FUNCS

static char spaces[] = "                                                      ";

/**
 * Dump all elements of a structure.  Recurse into substructures and optionally
 * also follow pointers.
 *
 * @param L  Lua State
 * @param ts  Typespec for the object at "obj"
 * @param obj  Pointer to the first byte of the object to show
 * @param indent  Level of indentation
 * @param follow_ptr  true if to follow pointers
 */
static void _dump_struct_1(lua_State *L, typespec_t ts, unsigned char *obj,
    int indent, int follow_ptr)
{

    /* the structure is OK, dump it */
    const char *name = lg_get_type_name(ts), *extra, *extra2;
    const struct ffi_type_map_t *arg_type;
    const struct struct_elem *se;
    int i, elem_count, size;
    type_info_t ti = lg_get_type_info(ts);
    const struct struct_elem *elem_list = modules[ts.module_idx]->elem_list;
    typespec_t ts2;

    elem_count = ti->st.elem_count;
    printf(", type %s, size %d, elements %d\n", name, ti->st.struct_size,
	elem_count);

    for (i=0; i<elem_count; i++) {
	se = elem_list + ti->st.elem_start + i;
	name = lg_get_struct_elem_name(ts.module_idx, se);
	ts2.module_idx = ts.module_idx;
	ts2.type_idx = se->type_idx;
	ts2 = lg_type_normalize(L, ts2);
	arg_type = lg_get_ffi_type(ts2);
	size = se->bit_length;
	int show_bytes = size % 8 == 0;
	extra = extra2 = "";

	// Size of (sub)structures isn't stored in the element's size field;
	// instead, it is set to 0.
	// XXX this is not true...
	if (/*size == 0 &&*/ !strcmp(FTYPE_NAME(arg_type), "struct")) {
	    printf(" %*.*s%2d %s", indent, indent, spaces, i, name);
	    _dump_struct_1(L, ts2, obj + se->bit_offset / 8, indent + 4,
		follow_ptr);
	    continue;
	}
	
	// A pointer to another structure?  If follow_ptr is enabled, show
	// the contents of that other structure as well (unless NULL)
	if (follow_ptr && !strcmp(FTYPE_NAME(arg_type), "struct*")) {
	    void *dest_ptr;
	    struct argconvs_t ar;

	    ar.ptr = obj;
	    ar.se = se;
	    ar.L = L;
	    get_bits_long(&ar, (char*) &dest_ptr);

	    if (dest_ptr) {
		printf(" %*.*s%2d %s*", indent, indent, spaces, i, name);
		_dump_struct_1(L, ts2, dest_ptr, indent + 4, follow_ptr);
		continue;
	    }

	    // Name of the structure.  FTYPE_NAME(arg_type) is just struct*,
	    // so show some more
	    extra = lg_get_type_name(ts2);
	    extra2 = " (NULL)";
	}

	// default: show the name, size and type of the structure element
	printf(" %*.*s%2d %s, size=%d %s, type=%s %s%s\n",
	    indent, indent, spaces, i, name,
	    show_bytes ? size / 8 : size,
	    show_bytes ? "bytes" : "bit",
	    FTYPE_NAME(arg_type), extra, extra2);
    }
}


/**
 * Display a structure for debugging purposes.
 *
 * @luaparam a structure, i.e. an object represented by a userdata.
 */
static int l_dump_struct(lua_State *L)
{
    typespec_t ts;

    luaL_checktype(L, 1, LUA_TUSERDATA);
    struct object *w = (struct object*) lua_touserdata(L, 1);

    if (!w) {
	printf("NIL\n");
	return 0;
    }

    unsigned char *obj = w->p;
    if (!obj) {
	printf("Object pointing to NULL\n");
	return 0;
    }

    if (!lua_getmetatable(L, 1)) {
	printf("Object doesn't have a metatable.\n");
	return 0;
    }

    // get the typespec
    lua_pushliteral(L, "_typespec");
    lua_rawget(L, -2);
    if (lua_type(L, -1) != LUA_TNUMBER) {
	lua_pop(L, 1);
	printf("Object has no _typespec information!\n");
	return 0;
    }
    ts.value = lua_tonumber(L, -1);
    lua_pop(L, 1);

    printf("Object at %p", obj);
    _dump_struct_1(L, ts, obj, 0, 1);
    return 0;
}

static void _dump_item(lua_State *L, int level, const char *name);
static const char _dump_prefix[] = "                               ";


/**
 * Dump a Lua value, possibly recurse.  It doesn't show simple values (nil,
 * string, number), but tables (with their key/value pairs), environment
 * and metatables.
 *
 * Lua Stack:
 *  [1]	    function tostring
 *  [2]	    seen table (key=object, value=true)
 *  ...
 *  [-1]    object to dump
 *
 * @param level     Indentation
 * @param name      Name of this item
 */
static void _dump_item(lua_State *L, int level, const char *name)
{
    int seen = 0;
    int type = lua_type(L, -1);
    int sep = 0;		// separator for the table items?

    // don't show simple things
    if (type == LUA_TNIL || type == LUA_TSTRING || type == LUA_TNUMBER
	|| type == LUA_TBOOLEAN)
	return;

    int has_details = (type == LUA_TTABLE || type == LUA_TFUNCTION
	|| type == LUA_TTHREAD || type == LUA_TUSERDATA);

    // for tables things that can have details, check whether already seen
    if (has_details) {
	lua_pushvalue(L, -1);
	lua_rawget(L, 2);
	seen = !lua_isnil(L, -1);
	lua_pop(L, 1);
    }

    // show the item
    lua_pushvalue(L, 1);		// tostring
    lua_pushvalue(L, -2);
    lua_call(L, 1, 1);
    printf("%*.*s%s %s%s\n", level, level, _dump_prefix, name,
	lua_tostring(L, -1), seen ? "" : "*");
    lua_pop(L, 1);

    // don't show details if it has already been seen.
    if (seen)
	return;

    // mark it as seen.
    if (has_details) {
	lua_pushvalue(L, -1);
	lua_pushboolean(L, 1);
	lua_rawset(L, 2);
    }

    // show metatable if it has any
    if (lua_getmetatable(L, -1)) {	// t k v meta(v)
	_dump_item(L, level, "Metatable");
	lua_pop(L, 1);
	sep = 1;
    }

    // some types can have an environment
    if (type == LUA_TFUNCTION || type == LUA_TTHREAD || type == LUA_TUSERDATA) {
	lua_getfenv(L, -1);
	if (!lua_isnil(L, -1))
	    _dump_item(L, level, "Environment");
	lua_pop(L, 1);
    }


    // functions can have upvalues
    if (type == LUA_TFUNCTION) {
	int i;
	const char *name;
	char name2[80];

	for (i=1; ; i++) {
	    name = lua_getupvalue(L, -1, i);
	    if (!name)
		break;
	    snprintf(name2, sizeof(name2), "Upvalue %d: %s", i, name);
	    _dump_item(L, level, name2);
	    lua_pop(L, 1);
	    sep = 1;
	}
    }

    // tables have items
    if (type != LUA_TTABLE)
	return;

    // index of the table
    int t = lua_gettop(L) - 1;
    
    lua_pushnil(L);			// t k
    while (lua_next(L, t+1)) {		// t k v

	lua_pushvalue(L, 1);		// t k v tostring
	lua_pushvalue(L, t+2);		// t k v tostring k
	lua_call(L, 1, 1);		// t k v string(k)

	lua_pushvalue(L, 1);		// t k v string(k) tostring
	lua_pushvalue(L, t+3);		// t k v string(k) tostring v
	lua_call(L, 1, 1);		// t k v string(k) string(v)
	
	if (sep) {
	    printf("%*.*sTable items\n", level, level, _dump_prefix);
	    sep = 0;
	}

	printf("%*.*s> %s = %s\n", level, level, _dump_prefix,
	    lua_tostring(L, -2), lua_tostring(L, -1));
	lua_pop(L, 2);			// t k v

	lua_insert(L, t+2);		// t v k
	_dump_item(L, level+2, "Key");
	lua_insert(L, t+2);		// t k v
	_dump_item(L, level+2, "Value");

	lua_pop(L, 1);			// t k
    }

}


static const char dont_show[] = "string\0os\0table\0math\0coroutine\0"
    "debug\0io\0";

/**
 * walk through all reachable memory objects.  Starting points:
 * - the global table
 * - the registry
 */
static int l_dump_memory(lua_State *L)
{
    const char *s;

    printf("\n** MEMORY DUMP **\n");
    lua_settop(L, 0);

    lua_getglobal(L, "tostring");	// tostring
    lua_newtable(L);			// tostring list

    lua_pushvalue(L, LUA_GLOBALSINDEX);	// tostring t

    // avoid showing the standard libraries.
    for (s=dont_show; *s; s += strlen(s) + 1) {
	lua_getglobal(L, s);
	lua_pushboolean(L, 1);
	lua_rawset(L, 2);
    }

    _dump_item(L, 0, "Global");
    lua_pop(L, 1);

    puts("\n\n** REGISTRY **\n");

    lua_pushvalue(L, LUA_REGISTRYINDEX);
    _dump_item(L, 0, "Registry");
    lua_pop(L, 1);

    lua_pop(L, 2);
    printf("** MEMORY DUMP ENDS **\n");
    return 0;
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

    struct object *w = lg_check_object(L, 1);
    if (w) {
	struct object_type *wt = lg_get_object_type(L, w);
	lua_pushinteger(L, lg_get_refcount(L, w));
	lua_pushstring(L, wt->name);
	return 2;
    }

    return 0;
}


/*-
 * To get meaningful backtraces (esp. with valgrind), I have to prevent
 * that gtk.so and other dynamic libraries are unloaded during Lua's
 * cleanup phase. So, unset the library entry... this uses undocumented
 * characteristics of Lua's loadlib.c.  
 *
 * ll_register, which is called while loading a dynamic library, creates
 * an entry in the registry with the handle of the library.  The key
 * used is LIBPREFIX plus the path of the library file.  LIBPREFIX is
 * currently defined as "LOADLIB: ".
 *
 * Note that this disables unloading for all loaded libraries, but not those
 * that are loaded after this function has been called.
 *
 * Because the path might vary, search for a matching key...
 */
static void prevent_library_unloading(lua_State *L)
{
    lua_getfield(L, LUA_REGISTRYINDEX, "_LOADLIB");
    lua_pushnil(L);

    while (lua_next(L, LUA_REGISTRYINDEX)) {
        if (lua_type(L, -1) == LUA_TUSERDATA) {
	    if (lua_getmetatable(L, -1)) {
		// stack: _LOADLIB key value metatable
		if (lua_rawequal(L, -1, -4)) {
		    void **p = (void**) lua_touserdata(L, -2);
		    *p = NULL;
		}
		lua_pop(L, 1);		// remove metatable
	    }
	}

        lua_pop(L, 1);			// remove value
    }
    // stack: _LOADLIB
    lua_pop(L, 1);
}

static const struct _debug_flags {
    const char *name;
    int only_at_startup;
    int value;
} _debug_flag_list[] = {
    { "trace", 0, RUNTIME_TRACE_ALL_CALLS },
    { "return", 0, RUNTIME_WARN_RETURN_VALUE },
    { "memory", 0, RUNTIME_DEBUG_MEMORY },
    { "gmem", 1, RUNTIME_GMEM_PROFILE },
    { "valgrind", 1, RUNTIME_VALGRIND },
    { "closure", 0, RUNTIME_DEBUG_CLOSURES },
    { "profile", 0, RUNTIME_PROFILE },
    { NULL, 0 }
};


/*-
 * The debug flags may be given as integer, or as a string.  This string
 * can consist of zero or more words separated by spaces.
 *
 * @param L  Lua State
 * @param index  Stack position where the flag is
 * @param starting  True if this is before GLib has been initialized
 */
static int _parse_debug_flag(lua_State *L, int index, int starting)
{
    const char *s = luaL_checkstring(L, index);
    const struct _debug_flags *p;

    // empty string
    if (!*s)
	return 0;

    // find the word in the list
    for (p=_debug_flag_list; p->name; p++)
	if (!strcmp(p->name, s)) {
	    if (!starting && p->only_at_startup)
		return luaL_error(L, "%s set the debug flag \"%s\" through "
		    "gnome_debug_flags", msgprefix, s);
	    return p->value;
	}


    return luaL_error(L, "Unknown debug flag %s", s);
}

/**
 * Apply the debug flags.  A few of them require interaction with GLib,
 * others are internal to LuaGnome, like "trace".
 *
 * @param L  Lua State
 * @param new_flags  A bitmask of the flags to set
 */
static int _set_debug_flags(lua_State *L, int new_flags)
{
    int ch = new_flags & ~runtime_flags;	// changes - i.e. new bits

    // collect allocation statistics, and cause g_mem_profile to be called at
    // program exit.
    if (ch & RUNTIME_GMEM_PROFILE) {
	// collect allocation statistics during runtime
	g_mem_set_vtable(glib_mem_profiler_table);

	// show a summary of memory operations at exit
	atexit(g_mem_profile);
    }

    // valgrind friendly operation
    if (ch & RUNTIME_VALGRIND) {
	atexit(call_info_free_pool);

	prevent_library_unloading(L);

	// Causes GLib to zero freed memory so that garbage memory can't be
	// mistaken for references to other blocks.  Might help valgrind's
	// analysis of reachable/lost memory (just a guess).
	g_mem_gc_friendly = 1;

	// Lots of memory within GLib/Gdk/Gtk is allocated using slices; these
	// are larger blocks of memory containing multiple "slices" of the same
	// size.  This may be good for performance, but not so for debugging.
	g_slice_set_config(G_SLICE_CONFIG_ALWAYS_MALLOC, 1);
    }

    if (ch & RUNTIME_DEBUG_CLOSURES)
	atexit(lg_done_closure);

    runtime_flags |= new_flags;
    return 0;
}


/**
 * Set runtime flags (for debugging).  The currently defined debug flags are:
 *
 *   trace     Show a trace of function calls
 *   return    Warn about returned pointers that couldn't be used
 *   memory    Show memory debuggin info (new objects, garbage collection)
 *   gmem      At exit, show the GMem profile
 *   valgrind  Do something to make valgrind run better (see source)
 *
 * @name set_debug_flags
 * @luaparam flags...  Debugging flags (zero or more may be given)
 */
static int l_set_debug_flags(lua_State *L)
{
    int new_flags = 0, i;

    for (i=1; i<=lua_gettop(L); i++)
	new_flags |= _parse_debug_flag(L, i, 0);

    return _set_debug_flags(L, new_flags);
}

static int l_unset_debug_flags(lua_State *L)
{
    int unset_flags = 0, i, ch;

    for (i=1; i<=lua_gettop(L); i++)
	unset_flags |= _parse_debug_flag(L, i, 0);
    ch = runtime_flags & unset_flags;

    if (ch & RUNTIME_DEBUG_CLOSURES)
	lg_done_closure();

    runtime_flags &= ~unset_flags;
    return 0;
}


/**
 * Certain debug flags have to be set before initializing GLib; if you set
 * the global variable "gnome_debug_flags" before loading the core library,
 * these flags can be set after all.
 */
int lg_debug_flags_global(lua_State *L)
{
    /* don't use lua_getglobal, as it may trigger a metamethod (strict) */
    lua_pushliteral(L, "gnome_debug_flags");
    lua_rawget(L, LUA_GLOBALSINDEX);

    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return 0;
    }

    lua_pushnil(L);
    int new_flags = 0;
    while (lua_next(L, -2)) {
	new_flags |= _parse_debug_flag(L, -1, 1);
	lua_pop(L, 1);
    }
    lua_pop(L, 1);

    return _set_debug_flags(L, new_flags);
}

#endif

static const luaL_reg debug_methods[] = {
    {"function_sig",	l_function_sig },

#ifdef LUAGNOME_DEBUG_FUNCS
    {"set_debug_flags", l_set_debug_flags },
    {"unset_debug_flags", l_unset_debug_flags },
    {"dump_struct",	l_dump_struct },
    {"dump_stack",	l_dump_stack },
    {"dump_memory",	l_dump_memory },
    {"get_refcount",	l_get_refcount },
    {"breakfunc",	lg_breakfunc },
#endif
    { NULL, NULL }
};

/* Register debugging methods */
void lg_init_debug(lua_State *L)
{
    luaL_register(L, NULL, debug_methods);
}

