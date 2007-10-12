/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * This module contains the routines that call Gtk functions from Lua.
 *
 * Exported functions:
 *   luagtk_call
 *   call_info_alloc_item
 *   call_info_warn
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_error
#include <malloc.h>	    // free
#include <string.h>	    // memset, strcmp, memcpy

#ifdef MANUAL_LINKING
# include "link.c"
#endif


/* extra arguments that have to be allocated are kept in this list. */
struct call_info_list {
    struct call_info_list *next;
};

/* already allocated, but discarded structures */
/* XXX for multithreading, this would have to be protected by a spinlock */
static struct call_info *ci_pool = NULL;

/**
 * Allocate a new call info structure and initialize it, unless an empty item
 * is in the pool; in this case it is removed and reused.
 */
static struct call_info *call_info_alloc()
{
    struct call_info *ci;

    // XXX lock_spinlock
    if (ci_pool) {
	ci = ci_pool;
	ci_pool = ci->next;
	// XXX unlock_spinlock
    } else {
	// XXX unlock_spinlock
	ci = (struct call_info*) malloc(sizeof(*ci));
    }

    memset(ci, 0, sizeof(*ci));

    return ci;
}

/**
 * Allocate an extra parameter; keep them in a singly linked list for
 * freeing later.
 */
void *call_info_alloc_item(struct call_info *ci, int size)
{
    size += sizeof(struct call_info_list);
    struct call_info_list *item = (struct call_info_list*) malloc(size);
    memset(item, 0, size);
    item->next = ci->first;
    ci->first = item;
    return item + 1;
}

/**
 * Free all extra parameters, then put the call_info structure into the
 * empty pool.
 *
 * If a warning has been displayed, output a newline.  Note that ci->warnings
 * may be set to 2, this means that an unconditional trace caused the function
 * call to be printed; in this case, no extra newline is desired.
 */
static void call_info_free(struct call_info *ci)
{
    struct call_info_list *p, *next;

    for (p=ci->first; p; p=next) {
	next = p->next;
	free(p);
    }

    if (ci->warnings == 1)
	printf("\n");

    // first & next are a union.
    // ci->first = NULL;

    // XXX lock spinlock
    ci->next = ci_pool;
    ci_pool = ci;
    // XXX unlock spinlock
}

#if 0

/**
 * At program exit (library close), free the pool.  This is not really required
 * but may help spotting memory leaks.  It is not called from anywhere, yet,
 * maybe from a gtk.done() function?
 */
static void call_info_free_pool()
{
    struct call_info *p;

    while ((p=ci_pool)) {
	ci_pool = p->next;
	free(p);
    }
}

#endif

/**
 * Before showing a warning message, call this function, which shows
 * the function call, but only for the first warning.
 *
 * If full tracing is enabled, then the function signature has already
 * been shown.
 */
void call_info_warn(struct call_info *ci)
{
    if (!ci->warnings)
	luagtk_call_trace(ci->L, ci->fi, ci->index);
    ci->warnings = 1;
}


/**
 * Retrieve the next argument spec from the binary representation (data from
 * the hash table).
 */
static inline void get_next_argument(const unsigned char **p, int *type_nr,
    int *struct_nr)
{
    const unsigned char *s = *p;

    *type_nr = *s++;
    if (*type_nr & 0x80) {
	*type_nr &= 0x7f;
	*struct_nr = * (unsigned short*) s;
	s += 2;
    } else {
	*struct_nr = 0;
    }

    *p = s;
}



/**
 * Prepare to call the Gtk function by converting all the parameters into
 * the required format.
 *
 * @param index    Lua stack position of first parameter
 * @param ci       call_info structure with lots more data
 *
 * Returns 0 on error, 1 otherwise.
 */
static int _call_build_parameters(lua_State *L, int index, struct call_info *ci)
{
    const unsigned char *s, *s_end;
    struct lua2ffi_arg_t ar;
    int arg_nr, stack_top = lua_gettop(L);

    /* build the call stack by parsing the parameter list */
    ar.L = L;
    ar.ci = ci;
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    // arg_nr 1 is the first
    index--;

    // look at each required parameter for this function.
    for (arg_nr = 0; s < s_end; arg_nr++) {
	get_next_argument(&s, &ar.ffi_type_nr, &ar.arg_struct_nr);
	ar.arg_type = &ffi_type_map[ar.ffi_type_nr];

	/* the first "argument" is actually the return value */
	if (arg_nr == 0) {
	    ci->argtypes[arg_nr] = ar.arg_type->type;
	    continue;
	}

	if (index+arg_nr > stack_top) {
	    // if the current (probably last) argument is vararg, this is OK,
	    // because a vararg doesn't need any extra arguments.
	    if (strcmp(ar.arg_type->name, "vararg")) {
		call_info_warn(ci);
		printf("  Warning: more arguments expected -> nil used\n");
	    }
	    ar.lua_type = LUA_TNIL;
	} else 
	    ar.lua_type = lua_type(L, index+arg_nr);

	ci->argtypes[arg_nr] = ar.arg_type->type;
	ci->argvalues[arg_nr] = &ci->ffi_args[arg_nr].l;

	lua2ffi_t func = ar.arg_type->lua2ffi;
	if (func) {
	    ar.index = index + arg_nr;
	    ar.arg = &ci->ffi_args[arg_nr];
	    ar.func_arg_nr = arg_nr;
	    int st_pos_1 = lua_gettop(L);
	    func(&ar);

	    if (lua_gettop(L) != st_pos_1) {
		call_info_warn(ci);
		printf("  Internal warning: lua2ffi changed stack\n");
		lua_settop(L, st_pos_1);
	    }

	    // The function might use up more than one parameter, e.g. when
	    // handling a vararg.
	    arg_nr = ar.func_arg_nr;
	} else {
	    call_info_warn(ci);
	    printf("  Argument %d (type %s) not handled\n", arg_nr+1,
		ar.arg_type->name);
	    ci->ffi_args[arg_nr].l = 0;
	}
    }

    // The return value doesn't count, therefore -1.
    ci->arg_count = arg_nr - 1;

    // Warn about unused arguments.
    int n = stack_top - (index+arg_nr-1);
    if (n > 0) {
	call_info_warn(ci);
	printf("  Warning: %d superfluous argument%s\n", n, n==1?"":"s");
    }

    return 1;
}


/**
 * After completing a call to a Gtk function, push the return values
 * on the Lua stack.
 *
 * Note: the stack still contains the parameters to the called function;
 * these are currently not used, though.
 */
static int _call_return_values(lua_State *L, struct call_info *ci)
{
    int stack_pos = lua_gettop(L), arg_nr, arg_struct_nr, ffi_type_nr;
    const unsigned char *s, *s_end;
    const struct ffi_type_map_t *arg_type;
    struct ffi2lua_arg_t ar;
    ffi2lua_t func;

    ar.L = L;

    /* Return the return value and output arguments.  This requires another
     * pass at parsing the argument spec.
     */
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    for (arg_nr = 0; s < s_end; arg_nr++) {
	get_next_argument(&s, &ffi_type_nr, &arg_struct_nr);
	arg_type = &ffi_type_map[ffi_type_nr];

	// always return the actual return value; others only if they are
	// pointers and thus can be an output value.
	if (arg_nr != 0 && arg_type->indirections == 0)
	    continue;
	
	// return all arguments that look like output arguments.
	func = arg_type->ffi2lua;
	if (func) {
	    ar.func_arg_nr = arg_nr;
	    ar.arg = &ci->ffi_args[arg_nr];
	    ar.arg_struct_nr = arg_struct_nr;
	    func(&ar);
	} else if (arg_nr == 0) {
	    // all direct return values must be handled.
	    call_info_warn(ci);
	    luaL_error(L, "%s unhandled return type %s\n",
		msgprefix, arg_type->name);
	}
    }

    /* return number of return values now on the stack. */
    return lua_gettop(L) - stack_pos;
}


/**
 * This is the most important function in this module.  Call a function of
 * the dynamically loaded library, using the information about parameters
 * compiled in from automatically generated configuration files.
 *
 * Stack: parameters starting at "index".
 */
int luagtk_call(lua_State *L, struct func_info *fi, int index)
{
    struct call_info *ci;
    ffi_cif cif;
    int rc = 0;

    ci = call_info_alloc();

    ci->fi = fi;
    ci->L = L;
    ci->index = index;

    // trace all calls with the function signature.
    if (runtime_flags & RUNTIME_TRACE_ALL_CALLS) {
	call_info_warn(ci);
	ci->warnings = 2;
    }

    /*
     * ffi_args	    array of values passed to the function; [0] = retval
     * argtypes	    array of types for ffi_call, [0] = type of retval
     * argvalues    array of pointers to the values
     */

    do {

	if (!_call_build_parameters(L, index, ci))
	    break;

	/* call the function */
	if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, ci->arg_count,
	    ci->argtypes[0],
	    ci->argtypes + 1) != FFI_OK) {
	    printf("FFI call to %s couldn't be initialized\n", fi->name);
	    break;
	}

	// A trace function displaying the argument values could be called
	// from here.  This doesn't exist yet.
	// XXX call_info_trace(ci);

	ffi_call(&cif, fi->func, &ci->ffi_args[0], ci->argvalues + 1);

	/* evaluate the return values */
	rc = _call_return_values(L, ci);
    } while (0);

    call_info_free(ci);
    return rc;
}

