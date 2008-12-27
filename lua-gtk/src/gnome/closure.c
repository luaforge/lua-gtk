/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2007, 2008 Wolfgang Oertl
 *
 * This module provides the new Lua data type "Closure", that represents
 * a Lua function and can be passed to Gtk functions as callbacks.  Note
 * that this is not used to connect signals, this is simpler and is handled
 * in src/callback.c.
 *
 * Exported symbols:
 *   lg_use_closure
 *   lg_create_closure
 *   lg_init_closure
 *   lg_done_closure
 */

#include "luagnome.h"
#include "lg_ffi.h"
#include <string.h>	    // memset
#include <stdlib.h>	    // exit

#define LUAGTK_CLOSURE "LuaClosure"
#define CLOSURE_MAGIC1 0x8c94aa30

struct lua_closure {
    int magic1;				// validate correctness
    lua_State *L;
    int func_ref;			// reference to the wrapped Lua function
    typespec_t ts;			// type of the function
    void *code;				// points to somewhere in closure
    ffi_closure *closure;		// closure allocated by FFI
    ffi_cif *cif;			// cif - spec of retval/args types
    ffi_type **arg_types;		// allocated array
    int is_automatic;			// true if allocated automatically
};

// For debugging purposes, when a closure is garbage collected, keep the memory
// it references alive and free it later.
struct closure_keeper {
    struct closure_keeper *next;
    ffi_closure *closure;
    ffi_cif *cif;
    ffi_type **arg_types;
};
static struct closure_keeper *unused = NULL;


/**
 * Call the appropriate function to convert the return value(s) of the Lua
 * function to a FFI value.  This is a simple wrapper to allow using
 * pcall() to catch conversion errors.
 *
 * @luaparam value  A Lua value of arbitrary type.
 * @luaparam ar  A struct argconv_t
 */
static int _convert_retval(lua_State *L)
{
    struct argconv_t *ar = (struct argconv_t*) lua_touserdata(L, 2);
    int idx = ar->arg_type->conv_idx;
    ffi_type_lua2ffi[idx](ar);
    return 0;
}



/**
 * Push all arguments for the Lua closure on the stack by using the
 * ffi2lua conversion functions.
 */
static void _closure_push_arguments(lua_State *L, struct lua_closure *cl,
	struct argconv_t *ar, void **args)
{
    const unsigned char *sig = lg_get_prototype(cl->ts);
    const unsigned char *sig_end = sig + 1 + *sig;
    int arg_nr;
    sig++;
    

    // push the arguments to the Lua stack
    for (arg_nr=0; sig < sig_end; arg_nr ++) {
	ar->ts = cl->ts;	    // copy ts.module_idx
	get_next_argument(L, &sig, ar);
	call_info_check_argcount(ar->ci, arg_nr + 1);
	if (arg_nr == 0)    // skip retval
	    continue;
	ar->func_arg_nr = arg_nr;
	ar->arg_type = lg_get_ffi_type(ar->ts);
	int idx = ar->arg_type->conv_idx;

	if (idx && ffi_type_ffi2lua[idx]) {
	    ar->index = arg_nr;
	    ar->arg = (union gtk_arg_types*) args[arg_nr - 1];
	    ar->lua_type = lua_type(L, ar->index);
	    ffi_type_ffi2lua[idx](ar);
	} else
	    luaL_error(L, "%s unhandled argument type %s in closure",
		    msgprefix, FTYPE_NAME(ar->arg_type));
    }
}



/**
 * Convert all return values to FFI, i.e. return them to the C caller.
 * Multiple return values may be given - for the output arguments.  The
 * first result is stored in *retval (if not void), the others are used
 * one by one for the output arguments in order.
 *
 * Lua Stack: [index] = first return value
 *
 * @param L  Lua State
 * @param cl  Information about the callback function that was just called
 * @param ar  argconv_t structure, partly initialized (esp. with ar->ci)
 * @param index  Stack position of the first return value from the callback
 * @param args  Array of the arguments passed by the caller
 * @param retval  Location where to store the callback's return value
 */
static void _closure_return_values(lua_State *L, struct lua_closure *cl,
	struct argconv_t *ar, int index, void **args, void *retval)
{
    int idx, arg_nr, top = lua_gettop(L);
    const unsigned char *sig = lg_get_prototype(cl->ts);
    const unsigned char *sig_end = sig + 1 + *sig;
    sig ++;


    for (arg_nr=0; sig<sig_end; arg_nr++) {
	ar->ts = cl->ts;	    // copy ts.module_idx
	get_next_argument(L, &sig, ar);

	// only consider the return value and output arguments.
	if (arg_nr > 0 && !ar->ci->args[arg_nr].is_output)
	    continue;

	// ar->type = type_list + ar->type_idx;
	// ar->arg_type = ffi_type_map + ar->type->fundamental_id;
	ar->arg_type = lg_get_ffi_type(ar->ts);

	// If index is 0, no lua2ffi function is defined for this type.
	idx = ar->arg_type->conv_idx;
	if (!idx || !ffi_type_lua2ffi[idx])
	    continue;

	// Otherwise, this type can be converted.  There should be at least
	// one more value on the Lua stack.
	if (index > top) {
	    lua_Debug debug;
	    lua_rawgeti(L, LUA_REGISTRYINDEX, cl->func_ref);
	    if (lua_getinfo(L, ">S", &debug))
		luaL_error(L, "%s insufficient return values from callback "
			"at %s line %d", msgprefix, debug.source,
			debug.linedefined);
	    // without extra info when lua_getinfo failed.
	    luaL_error(L, "insufficient return values from callback");
	}

	// The output position is either the return value, or the corresponding
	// argument (which is an output argument, i.e. a pointer to somewhere).
	if (arg_nr == 0)
	    ar->arg = (union gtk_arg_types*) retval;
	else
	    ar->arg = (union gtk_arg_types*) args[arg_nr-1];
	ar->lua_type = lua_type(L, index);

	// In order to show a meaningful error message in case of type
	// conversion failure, do a protected call.  Copy the next Lua
	// return value to the stack for that call.  It is therefore not
	// possible for a type conversion to use more or less than 1 arg.
	ar->index = 1;
	lua_pushcfunction(L, _convert_retval);
	lua_pushvalue(L, index);
	lua_pushlightuserdata(L, ar);
	int rc = lua_pcall(L, 2, 0, 0);
	if (rc) {
	    luaL_error(L, "failed to convert the callback's return value: "
		    "%s", lua_tostring(L, -1));
	}

	// Move to the next return value (of the Lua callback).
	index ++;
    }

    int n = top + 1 - index;
    if (n) {
	lua_Debug debug;
	lua_rawgeti(L, LUA_REGISTRYINDEX, cl->func_ref);
	lua_getinfo(L, ">S", &debug);
	printf("%s Warning: %d unused return value%s from callback at %s "
	    "line %d\n", msgprefix, n, n == 1 ? "" : "s", debug.source,
	    debug.linedefined);
    }
}


/**
 * Call the Lua function from C, passing the required parameters.
 *
 * Cave: when a struct lua_closure is freed, and a new one is allocated
 * in exactly the same location (not improbable), then the arguments in "args"
 * won't match the Lua function's signature - leading to SEGV or similar.
 * How can this be detected??
 *
 * @param cif  The "cif", specification of the arguments
 * @param retval  Location where to store the return value
 * @param args  Array of arguments
 * @param userdata  Pointer to the "struct lua_closure"
 */
static void closure_handler(ffi_cif *cif, void *retval, void **args,
	void *userdata)
{
    struct lua_closure *cl = (struct lua_closure*) userdata;

    // the main test here is on cif.  A new closure might have already been
    // allocated at the same location (*userdata), but in this case even
    // though it has the same magic signature, the cif pointer will differ.
    if (cl->magic1 != CLOSURE_MAGIC1 || cl->cif != cif) {
	fprintf(stderr, "%s closure handler detected a garbage collected "
		"closure at %p!\n", msgprefix, cl);
	exit(1);
    }

    lua_State *L = cl->L;
    int top = lua_gettop(L);
    struct argconv_t ar;
    struct call_info *ci;

    // Initialize the argconv_t structure.
    ci = call_info_alloc();
    ar.L = L;
    ar.ci = ci;
    ar.mode = ARGCONV_CALLBACK;

    // get the callback at [top+1]
    lua_rawgeti(L, LUA_REGISTRYINDEX, cl->func_ref);

    _closure_push_arguments(L, cl, &ar, args);

    // tracing
    if (G_UNLIKELY(runtime_flags & RUNTIME_TRACE_ALL_CALLS)) {
	struct func_info fi;
	const unsigned char *sig = lg_get_prototype(cl->ts);
	fi.func = NULL;
	fi.name = "callback";
	fi.args_info = sig + 1;
	fi.args_len = *sig;
	fi.module_idx = cl->ts.module_idx;
	lg_call_trace(L, &fi, top+1);
    }

    // call the lua function, expect any number of return values
    int arg_cnt = lua_gettop(L) - top - 1;
    lua_call(L, arg_cnt, LUA_MULTRET);
    _closure_return_values(L, cl, &ar, top+1, args, retval);

    // clean up
    lua_settop(L, top);
    call_info_free(ci);
}


/**
 * Initialize the arg_types array with the types taken from the function's
 * signature.  If called with arg_types == NULL, just count the number of args.
 *
 * The first byte is the length of the following data.
 *
 * @param ts  Type of the function to call
 * @param arg_types  Location to store the ffi argument types (may be NULL)
 * @return  The number of arguments.
 */
static int set_ffi_types(lua_State *L, typespec_t ts, ffi_type **arg_types)
{
    int arg_nr=0;
    const unsigned char *sig = lg_get_prototype(ts);
    const unsigned char *sig_end = sig + 1 + *sig;
    const struct ffi_type_map_t *ffi;
    struct argconv_t ar = { 0 };
    sig ++;

    while (sig < sig_end) {
	ar.ts = ts;
	get_next_argument(L, &sig, &ar);
	if (arg_types) {
	    ffi = lg_get_ffi_type(ar.ts);
	    arg_types[arg_nr] =  LUAGTK_FFI_TYPE(ffi->ffi_type_idx);
	}
	arg_nr ++;
    }

    return arg_nr;
}

// really free all memory of the closure.
static void _free_closure(ffi_closure *closure, ffi_cif *cif,
    ffi_type **arg_types)
{
    ffi_closure_free(closure);

    if (cif) {
	memset(cif, 0, sizeof(*cif));
	g_free(cif);
    }
    if (arg_types)
	g_free(arg_types);
}


/**
 * Garbage collection of a closure.  Note that the user must ensure it won't
 * be called again!  Otherwise, random SEGV are likely to occur.
 */
static int l_closure_gc(lua_State *L)
{
    struct lua_closure *cl = (struct lua_closure*) lua_touserdata(L, 1);

    if (cl->closure) {
	if (!(runtime_flags & RUNTIME_DEBUG_CLOSURES)) {
	    _free_closure(cl->closure, cl->cif, cl->arg_types);
	} else {
	    struct closure_keeper *k = g_slice_alloc(sizeof(*k));
	    k->next = unused;
	    k->closure = cl->closure;
	    k->cif = cl->cif;
	    k->arg_types = cl->arg_types;
	    unused = k;
	}
    }

    // Overwrite this magic signature.  This ensures that GC'd closures
    // can be detected in closure_handler.
    if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_CLOSURES))
	printf("%p GC closure %s\n", cl, lg_get_type_name(cl->ts));
    memset(cl, 0, sizeof(*cl));
    return 0;
}


/**
 * Normally, a closure should be called by a C library.  It is possible,
 * though, to call it from Lua too.  Simply replace the closure object
 * with the function, then call with all arguments given and return all
 * return values.
 */
static int l_closure_call(lua_State *L)
{
    struct lua_closure *cl = (struct lua_closure*) lua_touserdata(L, 1);
    lua_rawgeti(L, LUA_REGISTRYINDEX, cl->func_ref);
    lua_replace(L, 1);
    lua_call(L, lua_gettop(L) - 1, LUA_MULTRET);
    return lua_gettop(L);
}


/**
 * Pretty printing of a closure
 */
static int l_closure_tostring(lua_State *L)
{
    struct lua_closure *cl = (struct lua_closure*) lua_touserdata(L, 1);
    lua_pushfstring(L, "Closure (%s) at %p", cl->is_automatic ? "automatic"
	: "manual", cl);

#ifdef LUAGTK_DEBUG_FUNCS
    lua_Debug debug;
    lua_rawgeti(L, LUA_REGISTRYINDEX, cl->func_ref);
    lua_getinfo(L, ">S", &debug);
    lua_pushfstring(L, " at %s line %d", debug.source, debug.linedefined);
    lua_concat(L, 2);
#endif

    return 1;
}

static const luaL_reg closure_methods[] = {
    { "__gc",    l_closure_gc },
    { "__call",  l_closure_call },
    { "__tostring", l_closure_tostring },
    { NULL, NULL }
};

#ifdef LUAGTK_DEBUG_FUNCS


// There are about 200 functions that have a function pointer as argument.
// currently 73 of them can be called with automatic closures; in order to
// avoid listing all of them, the data types are checked.
static const char _check_types_whitelist[] =

    // Gtk
    "GtkTreeModelForeachFunc\0"
    "GtkTreeSelectionForeachFunc\0"
    "GtkTreeViewMappingFunc\0"
    "GtkAccelGroupFindFunc\0"
    "GtkBuilderConnectFunc\0"
    "GtkIconViewForeachFunc\0"
    "GtkMenuPositionFunc\0"
    "GtkPrintSettingsFunc\0"
    "GtkAccelMapForeach\0"
    "GtkTextIterCharPredicate\0"
    "GtkTextTagTableForeach\0"
    "GtkCallback\0"

    // glib
    "GCompareFunc\0"
    "GCompareDataFunc\0"
    "GHFunc\0"
    "GDataForeachFunc\0"
    "GHRFunc\0"
    "GHookFindFunc\0"
    "GHookCompareFunc\0"
    "GFunc\0"
    "GNodeForeachFunc\0"
    "GCopyFunc\0"
    "GNodeTraverseFunc\0"
    "GHashFunc\0"
    "GEqualFunc\0"
    "GSequenceIterCompareFunc\0"
    "GTraverseFunc\0"
    "GRegexEvalCallback\0"

    // GDK
    "GdkPixbufSaveFunc\0"
    "GdkSpanFunc\0"

    // pango
    "PangoAttrFilterFunc\0"
    "PangoFontsetForeachFunc\0"

    // libxml2
    "xmlListWalker\0"
    "xmlHashCopier\0"

    // cairo
    "cairo_read_func\0"
    "cairo_write_func\0"
;


// Here are functions that have one of the above arguments types, but still
// can't be called with automatic closures.  Listed behind each function is
// the offending data type.
static const char _check_funcs_blacklist[] =
    "g_tree_new\0"				// GCompareFunc
    "g_tree_new_full\0"				// GCompareDataFunc
    "g_tree_new_with_data\0"			// GCompareDataFunc
    "g_thread_pool_set_sort_function\0"		// GCompareDataFunc
    "g_thread_pool_new\0"			// GFunc
    "g_cache_new\0"				// GHashFunc, GEqualFunc
    "g_hash_table_new\0"			// GHashFunc, GEqualFunc
    "g_hash_table_new_full\0"			// GHashFunc, GEqualFunc
;

static int _list_search(const char *list, const char *s)
{
    size_t len;

    while (*list) {
	len = strlen(list) + 1;
	if (!memcmp(list, s, len))
	    return 1;
	list += len;
    }

    // not found
    return 0;
}


/**
 * Disallow the usage of automatic closures, which are created on-the-fly
 * and destroyed after the called function returns, in certain situations.
 */
static void _check_automatic(lua_State *L, struct lua_closure *cl,
    int arg_nr, const char *func_name)
{
    // not an automatic closure - ok
    if (!cl->is_automatic)
	return;

    // make sure the type is in the whitelist, and the function not in the
    // blacklist.
    const char *type_name = lg_get_type_name(cl->ts);
    if (_list_search(_check_types_whitelist, type_name)
	&& !_list_search(_check_funcs_blacklist, func_name))
	return;

    // can't do it.
    if (arg_nr > 0)
	luaL_argerror(L, arg_nr, "Can't use an automatic closure here");
    else
	luaL_error(L, "%s Can't use an automatic closure for type %s",
	    msgprefix, type_name);
}

#else
#define _check_automatic(L, cl, func_name, type_name)
#endif


/**
 * The first time a closure is used, it is configured for the arguments
 * that can be expected from the caller, i.e. the function signature.
 */
static void _setup_closure(lua_State *L, struct lua_closure *cl,
    typespec_t ts, int arg_nr, const char *func_name)
{
    int arg_count;

    // check that a temporary closure isn't used for one of the known
    // callback types.
    cl->ts = ts;
    _check_automatic(L, cl, arg_nr, func_name);

    // cl->sig = lg_get_prototype(ts);
    cl->closure = (ffi_closure*) ffi_closure_alloc(sizeof(*cl->closure),
	&cl->code);
    cl->cif = (ffi_cif*) g_malloc(sizeof(*cl->cif));

    // The count includes the return value, and therefore must be at least 1.
    arg_count = set_ffi_types(L, ts, NULL);
    if (arg_count <= 0)
	luaL_error(L, "_setup_closure: invalid signature");

    // allocate and fill arg_types, then ffi_cif
    cl->arg_types = (ffi_type**) g_malloc(sizeof(ffi_type*) * arg_count);
    set_ffi_types(L, ts, cl->arg_types);
    ffi_prep_cif(cl->cif, FFI_DEFAULT_ABI, arg_count-1, cl->arg_types[0],
	cl->arg_types+1);
    ffi_prep_closure_loc(cl->closure, cl->cif, closure_handler, (void*) cl,
	cl->code);
}


/**
 * A closure should now be used as a function argument, or stored in a
 * structure's virtual table.  Now that the signature of the function is known,
 * setup the ffi closure.
 *
 * @param L  Lua state
 * @param index  Stack position of a Lua function
 * @param ts  The typespec (and therefore, signature) of the function to call
 * @param arg_nr  If this is an argument to a function, which argument
 * @param func_name  Name of the called function, or structure element name
 * @return  Pointer to a new closure
 */
void *lg_use_closure(lua_State *L, int index, typespec_t ts, int arg_nr,
    const char *func_name)
{
    luaL_checktype(L, index, LUA_TUSERDATA);

    struct lua_closure *cl = (struct lua_closure*) lua_touserdata(L, index);
    if (G_UNLIKELY(cl->magic1 != CLOSURE_MAGIC1)) {
	if (arg_nr)
	    luaL_argerror(L, arg_nr, "must be a closure, use gtk.closure");
	else
	    luaL_error(L, "[LG gnome 7] Value must be a closure");
    }

    if (!cl->ts.value)
	_setup_closure(L, cl, ts, arg_nr, func_name);
    else if (cl->ts.value != ts.value)
	luaL_error(L, "[LG gnome 8] Closure used with different signature");

    // It would be logical to always call "code", but sometimes "closure" must
    // be called instead.  The configure script determines which one works.
#ifdef LUAGTK_FFI_CODE
    return (void*) cl->code;
#else
 #ifdef LUAGTK_FFI_CLOSURE
    return (void*) cl->closure;
 #else
    #error Please define one of LUAGTK_FFI_{CODE,CLOSURE}.
 #endif
#endif
}


/**
 * Create a new userdata representing a closure.  The function signature will
 * be known later, when this closure is used somewhere, e.g. as argument
 * to a Gtk function.
 */
static int l_closure(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TFUNCTION);
    return lg_create_closure(L, 1, 0);
}

/**
 * Create a new closure for the function at the given index, and push that
 * onto the Lua stack.  Note that such closures don't include any extra
 * arguments, just the function.
 *
 * @param L  Lua State
 * @param index  Position on the Lua stack where the function object is
 * @param is_automatic  The corresponding field in the new closure is set to
 *  this value.
 */
int lg_create_closure(lua_State *L, int index, int is_automatic)
{
    struct lua_closure *cl = (struct lua_closure*) lua_newuserdata(L,
	sizeof(*cl));
    memset(cl, 0, sizeof(*cl));

    // add a metatable with garbage collection
    if (luaL_newmetatable(L, LUAGTK_CLOSURE))
	luaL_register(L, NULL, closure_methods);
    lua_setmetatable(L, -2);

    cl->magic1 = CLOSURE_MAGIC1;
    cl->L = L;
    cl->is_automatic = is_automatic;
    lua_pushvalue(L, index);
    cl->func_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_CLOSURES))
	printf("%p new closure\n", cl);

    return 1;
}

// additional functions in gnome
static const luaL_reg closure_functions[] = {
    { "closure",    l_closure },
    { NULL, NULL }
};

void lg_init_closure(lua_State *L)
{
    luaL_register(L, NULL, closure_functions);
}


/**
 * If the user has set the RUNTIME_DEBUG_CLOSURES flag, closures are not
 * freed but kept in a singly linked list to detect accesses to already
 * freed closures.  At program termination, or when this debug flag is unset,
 * free them.
 */
void lg_done_closure()
{
    struct closure_keeper *k;

    while (unused) {
	k = unused;
	unused = k->next;
	_free_closure(k->closure, k->cif, k->arg_types);
	g_slice_free(struct closure_keeper, k);
    }
}

