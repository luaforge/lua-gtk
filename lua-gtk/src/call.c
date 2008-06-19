/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * This module contains the routines that call Gtk functions from Lua.
 *
 * Exported functions:
 *   luagtk_call
 *   luagtk_call_byname
 *   get_next_argument
 *   call_info_alloc_item
 *   call_info_msg
 *   call_info_warn
 *   call_info_free_pool
 */

/**
 * @class module
 * @name gtk_internal.call
 */

#include "luagtk.h"
#include <lauxlib.h>	    // luaL_error
#include <string.h>	    // memset, strcmp, memcpy
#include <stdarg.h>	    // va_start etc.

#include "luagtk_ffi.h"	    // LUAGTK_FFI_TYPE() macro


/* extra arguments that have to be allocated are kept in this list. */
struct call_info_list {
    struct call_info_list *next;
    /* payload starts here */
};

/* already allocated, but discarded structures */
/* XXX for multithreading, this would have to be protected by a spinlock */
static struct call_info *ci_pool = NULL;

/**
 * Provide an unused call_info structure.  It may be taken from the pool, or
 * newly allocated.  In both cases, it is initialized to 0.
 */
static struct call_info *call_info_alloc()
{
    struct call_info *ci;

    // lock_spinlock
    if (ci_pool) {
	ci = ci_pool;
	ci_pool = ci->next;
	// unlock_spinlock
	memset(ci, 0, sizeof(*ci));
    } else {
	// unlock_spinlock
	ci = g_slice_new0(struct call_info);
    }

    return ci;
}


/**
 * Allocate space for an extra parameter.  These memory blocks are kept in
 * a singly linked list and are freed in call_info_free.
 *
 * @param ci  The call_info this memory is allocated for
 * @param size  How many bytes to allocate
 * @return  A pointer to the newly allocated memory.
 */
void *call_info_alloc_item(struct call_info *ci, int size)
{
    size += sizeof(struct call_info_list);
    struct call_info_list *item = (struct call_info_list*) g_malloc(size);
    memset(item, 0, size);
    item->next = ci->first;
    ci->first = item;
    return item + 1;
}


/**
 * Release a call_info structure.  The attached extra parameters are freed,
 * then the stucture is put into the pool.
 *
 * If a warning has been displayed, output a newline.  Note that ci->warnings
 * may be set to 2, this means that an unconditional trace caused the function
 * call to be printed; in this case, no extra newline is desired.
 *
 * @param ci   The structure to be freed
 */
static void call_info_free(struct call_info *ci)
{
    struct call_info_list *p, *next;

    for (p=ci->first; p; p=next) {
	next = p->next;
	g_free(p);
    }

    if (ci->warnings == 1)
	printf("\n");

    // lock spinlock
    ci->next = ci_pool;
    ci_pool = ci;
    // unlock spinlock
}


/**
 * At program exit (library close), free the pool.  This is not really required
 * but may help spotting memory leaks.
 */
void call_info_free_pool()
{
    struct call_info *p;

    while ((p=ci_pool)) {
	ci_pool = p->next;
	g_slice_free(struct call_info, p);
    }
}


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

const static char *_call_info_messages[] = {
    "  Debug",
    "  Info",
    "  Warning",
    "  Error"
};

/**
 * Display a warning or an error about a function call.
 *
 * @param level    Error level; 0=debug, 1=info, 2=warning, 3=error
 */
void call_info_msg(struct call_info *ci, enum luagtk_msg_level level,
    const char *format, ...)
{
    call_info_warn(ci);
    if (level > 3)
	luaL_error(ci->L, "call_info_msg(): Invalid level %d\n", level);
    printf("%s ", _call_info_messages[level]);
    va_list ap;
    va_start(ap, format);
    vprintf(format, ap);
    va_end(ap);
}


/**
 * Retrieve the next argument spec from the binary representation (data from
 * the hash table).
 *
 * As you can see, the data consists of a type number; if the high bit is set,
 * then two more bytes follow with a structure number.  The caller must take
 * care not to read past the end of the data.
 *
 * @param p    Pointer to the pointer to the current position (will be updated)
 * @param type_idx  (output) type of the next parameter
 */
inline int get_next_argument(const unsigned char **p)
{
    const unsigned char *s = *p;
    unsigned int v = *s++;
    if (v & 0x80)
	v = ((v << 8) | *s++) & 0x7fff;
    *p = s;
    return (int) v;
}


/**
 * Prepare to call the Gtk function by converting all the parameters into
 * the required format as required by libffi.
 *
 * @param L        lua_State
 * @param index    Lua stack position of first parameter
 * @param ci       call_info structure with lots more data
 *
 * Returns 0 on error, 1 otherwise.
 */
static int _call_build_parameters(lua_State *L, int index, struct call_info *ci)
{
    const unsigned char *s, *s_end;
    struct argconv_t ar;
    int arg_nr, stack_top = lua_gettop(L), idx;

    /* build the call stack by parsing the parameter list */
    ar.L = L;
    ar.ci = ci;
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    // arg_nr 1 is the first
    index--;

    // look at each required parameter for this function.
    for (arg_nr = 0; s < s_end; arg_nr++) {
	ar.type_idx = get_next_argument(&s);
	ar.type = type_list + ar.type_idx;
	ar.arg_type = ffi_type_map + ar.type->fundamental_id;

	idx = ar.arg_type->ffi_type_idx;
	if (idx == 0) {
	    call_info_msg(ci, LUAGTK_ERROR,
		"Argument %d (type %s) has no ffi type.\n",
		arg_nr, FTYPE_NAME(ar.arg_type));
	    luaL_error(L, "call error\n");
	}
	ci->argtypes[arg_nr] = LUAGTK_FFI_TYPE(idx);

	/* the first "argument" is actually the return value; no more work. */
	if (arg_nr == 0) {
	    ci->argvalues[0] = NULL;	    // just to be sure
	    continue;
	}

	// No more arguments available?
	if (index+arg_nr > stack_top) {
	    // If the current (probably last) argument is vararg, this is OK,
	    // because a vararg doesn't need any extra arguments.
	    if (strcmp(FTYPE_NAME(ar.arg_type), "vararg")) {
		call_info_msg(ci, LUAGTK_WARNING,
		    "More arguments expected -> nil used\n");
	    }
	    ar.lua_type = LUA_TNIL;
	} else 
	    ar.lua_type = lua_type(L, index+arg_nr);

	ci->argvalues[arg_nr] = &ci->ffi_args[arg_nr].l;

	// if there's a handler to convert the argument, do it
	idx = ar.arg_type->lua2ffi_idx;
	if (idx) {
	    ar.index = index + arg_nr;
	    ar.arg = &ci->ffi_args[arg_nr];
	    ar.func_arg_nr = arg_nr;
	    int st_pos_1 = lua_gettop(L);
	    ffi_type_lua2ffi[idx](&ar);

	    // Shouldn't happen.  Can be fixed, but complain anyway
	    if (lua_gettop(L) != st_pos_1) {
		call_info_msg(ci, LUAGTK_DEBUG, "lua2ffi changed the stack\n");
		lua_settop(L, st_pos_1);
	    }

	    // The function might use up more than one parameter, e.g. when
	    // handling a vararg.
	    arg_nr = ar.func_arg_nr;
	} else {
	    call_info_msg(ci, LUAGTK_WARNING,
		"Argument %d (type %s) not handled\n", arg_nr,
		FTYPE_NAME(ar.arg_type));
	    luaL_error(L, "call error\n");
	    ci->ffi_args[arg_nr].l = 0;
	}
    }

    // just to be sure
    if (arg_nr > MAX_FUNC_ARGS)
	luaL_error(L, "max. number of arguments to Gtk function exceeded"
	    " (%d > %d)", arg_nr, MAX_FUNC_ARGS);

    // The return value doesn't count, therefore -1.
    ci->arg_count = arg_nr - 1;

    // Warn about unused arguments.
    int n = stack_top - (index+arg_nr-1);
    if (n > 0) {
	call_info_msg(ci, LUAGTK_WARNING,
	    "%d superfluous argument%s\n", n, n==1?"":"s");
    }

    return 1;
}



const struct type_info *luagtk_type_modify(const struct type_info *ti,
    int ind_delta)
{
    const char *name = TYPE_NAME(ti);
    const struct ffi_type_map_t *ffi = ffi_type_map + ti->fundamental_id;
    int ind = ffi->indirections + ind_delta;
    return find_struct(name, ind);
}


/**
 * After completing a call to a Gtk function, push the return values
 * on the Lua stack.
 *
 * Note: the stack still contains the parameters to the called function;
 * these are currently not used, though.
 */
static int _call_return_values(lua_State *L, int index, struct call_info *ci)
{
    int stack_pos = lua_gettop(L), arg_nr, skip=0;
    const unsigned char *s, *s_end;
    struct argconv_t ar;

//    printf("return values for %s\n", ci->fi->name);

    ar.L = L;
    ar.ci = ci;

    /* Return the return value and output arguments.  This requires another
     * pass at parsing the argument spec. */
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    for (arg_nr = 0; s < s_end; arg_nr++) {
	ar.type_idx = get_next_argument(&s);

	if (skip) {
	    skip--;
	    continue;
	}

	ar.type = type_list + ar.type_idx;
	ar.arg_type = ffi_type_map + ar.type->fundamental_id;

	// always return the actual return value; others only if they are
	// pointers and thus can be an output value.
	if (arg_nr != 0 && ar.arg_type->indirections == 0)
	    continue;

	int idx = ar.arg_type->ffi2lua_idx;
	if (idx) {

	    // Find the type of the returned value; it's the type of the
	    // argument with one less level of indirections.
	    // XXX this should be cached.
	    if (arg_nr != 0) {
		const char *ftype_name = FTYPE_NAME(ar.arg_type);
		// struct* is not an output parameter.
		if (!strcmp(ftype_name, "struct*"))
		    continue;
		// char* is not an output parameter.
		if (!strcmp(ftype_name, "char*"))
		    continue;
		// void* is not an output parameter.
		if (!strcmp(ftype_name, "void*"))
		    continue;
		//printf("arg_type %s, idx %d\n", FTYPE_NAME(ar.arg_type), idx);
		ar.type = luagtk_type_modify(ar.type, -1);
		if (!ar.type)
		    continue;
		ar.type_idx = ar.type - type_list;
	    }

	    // return all arguments that look like output arguments.
	    ar.index = index + arg_nr - 1;
	    ar.arg = &ci->ffi_args[arg_nr];
	    ar.func_arg_nr = arg_nr;
	    ar.lua_type = arg_nr ? lua_type(L, ar.index) : LUA_TNIL;
#if 0
	    if (arg_nr > 0)
		printf("retval #%d, index %d, type %s -> %s\n", arg_nr,
		    ar.index, lua_typename(L, ar.lua_type), TYPE_NAME(ar.type));
#endif
	    int cnt = ffi_type_ffi2lua[idx](&ar);
	    if (cnt > 0)
		skip = cnt - 1;
	} else if (arg_nr == 0) {
	    // all direct return values must be handled.
	    call_info_warn(ci);
	    luaL_error(L, "%s unhandled return type %s\n",
		msgprefix, FTYPE_NAME(ar.arg_type));
	}
    }

    /* return number of return values now on the stack. */
    return lua_gettop(L) - stack_pos;
}

/**
 * Call the given function by name, and use the current Lua stack
 * as parameters.
 *
 * Note: this does NOT consider overrides, which is intentional as some
 * override functions use this to call into Gtk.
 */
int luagtk_call_byname(lua_State *L, const char *func_name)
{
    struct func_info fi;
    if (find_func(func_name, &fi))
	return luagtk_call(L, &fi, 1);
    return luaL_error(L, "%s function %s not found", msgprefix, func_name);
}


/**
 * Call a library function from Lua.  The information about parameters and
 * return values is compiled in (automatically generated). 
 *
 * Stack: parameters starting at "index".
 */
int luagtk_call(lua_State *L, struct func_info *fi, int index)
{
    struct call_info *ci;
    ffi_cif cif;
    int rc = 0;

    // If the user calls gtk_init, don't do it automatically.
    if (G_UNLIKELY(!gtk_is_initialized)) {
	if (strcmp(fi->name, "gtk_init"))
	    luagtk_init_gtk();
	else {
	    gtk_is_initialized = 1;
	}
    }

    // allocate (or re-use from the pool) a call_info structure.
    ci = call_info_alloc();
    ci->fi = fi;
    ci->L = L;
    ci->index = index;

    // trace all calls with the function signature.
    if (runtime_flags & RUNTIME_TRACE_ALL_CALLS) {
	call_info_warn(ci);
	ci->warnings = 2;
    }

    /* call the function */
    if (_call_build_parameters(L, index, ci)) {
	if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, ci->arg_count,
	    ci->argtypes[0], ci->argtypes + 1) == FFI_OK) {

	    // A trace function displaying the argument values could be called
	    // from here.  This doesn't exist yet.
	    // XXX call_info_trace(ci);

	    ffi_call(&cif, fi->func, &ci->ffi_args[0], ci->argvalues + 1);

	    /* evaluate the return values */
	    rc = _call_return_values(L, index, ci);
	} else {
	    printf("FFI call to %s couldn't be initialized\n", fi->name);
	}
    }

    call_info_free(ci);
    return rc;
}

