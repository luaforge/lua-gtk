/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * This module contains the routines that call Gtk functions from Lua.
 *
 * Exported functions:
 *   lg_call
 *   lg_call_byname
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

#include "luagnome.h"
#include <string.h>	    // memset, strcmp, memcpy
#include <stdarg.h>	    // va_start etc.

#include "lg_ffi.h"	    // LUAGTK_FFI_TYPE() macro


/* extra arguments that have to be allocated are kept in this list. */
struct call_info_list {
    struct call_info_list *next;
    /* payload starts here */
};

/* already allocated, but discarded structures */
/* XXX for multithreading, this would have to be protected by a spinlock */
static struct call_info *ci_pool = NULL;

/* the currently running function; XXX not suitable for multithreading */
/* required by init.c:lg_log_func. */
struct call_info *ci_current = NULL;

/**
 * Provide an unused call_info structure.  It may be taken from the pool, or
 * newly allocated.  In both cases, it is initialized to 0.
 */
struct call_info *call_info_alloc()
{
    struct call_info *ci;

    // lock_spinlock
    if (ci_pool) {
	ci = ci_pool;
	ci_pool = ci->next;
	// unlock_spinlock
	
	// Zero out the arguments, if any, that were used by the last call.
	// Can't just clear the whole structure, because arg_alloc and args
	// need to be kept.
	if (ci->args) {
	    int n = ci->arg_count;
	    memset(ci->args, 0, sizeof(*ci->args) * n);
	    memset(ci->argtypes, 0, sizeof(*ci->argtypes) * n);
	    memset(ci->argvalues, 0, sizeof(*ci->argvalues) * n);
	}
	ci->L = NULL;
	ci->index = 0;
	ci->fi = NULL;
	ci->arg_count = 0;
	ci->warnings = 0;
	ci->first = NULL;
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

static void call_info_free_arg(struct call_info *ci, int idx)
{
    lua_State *L = ci->L;
    struct call_arg *ca = &ci->args[idx];
    int method = ca->free_method;

    switch (method) {
	case FREE_METHOD_BOXED:
	    lg_boxed_free(ca->ffi_arg.p);
	    break;
	
	case FREE_METHOD_GVALUE:
	    g_value_unset((GValue*) ca->ffi_arg.p);
	    break;
	
	default:
	    luaL_error(L, "%s internal error: undefined free_method %d in "
		"call_info_free_arg", msgprefix, method);
    }
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
void call_info_free(struct call_info *ci)
{
    struct call_info_list *p, *next;
    int i;

    // free all extra memory allocated for arguments
    for (p=ci->first; p; p=next) {
	next = p->next;
	g_free(p);
    }

    // possibly free more arguments
    for (i=0; i<ci->arg_count; i++)
	if (ci->args[i].free_method)
	    call_info_free_arg(ci, i);

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
	if (p->args) {
	    g_free(p->args);
	    g_free(p->argtypes);
	    g_free(p->argvalues);
	    p->args = NULL;
	    p->argtypes = NULL;
	    p->argvalues = NULL;
	}
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
	lg_call_trace(ci->L, ci->fi, ci->index);
    ci->warnings = 1;
}

const static char *_call_info_messages[] = {
    "  Debug",
    "  Info",
    "  Warning",
    "  Error"
};

/**
 * Display a warning or an error about a function call.  The message is
 * on top of the Lua stack.
 *
 * @param level    Error level; 0=debug, 1=info, 2=warning, 3=error
 */
void call_info_msg(lua_State *L, struct call_info *ci, enum lg_msg_level level)
{
    call_info_warn(ci);
    if (level > 3)
	luaL_error(ci->L, "call_info_msg(): Invalid level %d\n", level);
    printf("%s %s\n", _call_info_messages[level], lua_tostring(L, -1));
    lua_pop(L, 1);
}


/**
 * Make sure that the given number of arguments are allocated for the
 * function call.  The additional space must be zeroed.
 */
void call_info_check_argcount(struct call_info *ci, int n)
{
    int old_n;

    if (ci->arg_alloc >= n)
	return;

    n = (n | 15) + 1;
    old_n = ci->arg_alloc;

#define ALLOC_MORE(p, type) p = (type*) g_realloc(p, n * sizeof(*p)); \
    memset(p + old_n, 0, sizeof(*p) * (n - old_n))
    ALLOC_MORE(ci->args, struct call_arg);
    ALLOC_MORE(ci->argtypes, ffi_type*);
    ALLOC_MORE(ci->argvalues, void*);
#undef ALLOC_MORE

    ci->arg_alloc = n;
}


/**
 * Retrieve the next argument spec from the binary representation (data from
 * the hash table).  Only native types are returned.
 *
 * The types are sorted by descending frequency, so that lower type numbers
 * are more common.  If the type number is less than 128, it is encoded in
 * one byte; if more, two bytes are required.
 *
 * A type number can be preceded by flags (zero byte + flag byte).
 *
 * The caller must take care not to read past the end of the data.
 * The caller must set ar->ts.module_idx.
 *
 * @param p  Pointer to the pointer to the current position (will be updated)
 * @param ar  Argument conversion structure.  It has the fields arg_flags, ts
 */
inline void get_next_argument(lua_State *L, const unsigned char **p,
    struct argconv_t *ar)
{
    const unsigned char *s = *p;
    unsigned int v = *s++;

    // a zero byte means that a flag byte follows, then the actual value.
    ar->arg_flags = 0;
    if (G_UNLIKELY(!v)) {
	ar->arg_flags = *s++;
	v = *s++;
    }

    // high bit set - use two bytes (high order byte first).
    if (v & 0x80)
	v = ((v << 8) | *s++) & 0x7fff;
    *p = s;
    ar->ts.type_idx = (int) v;

    // immediately resolve non-native types.
    ar->ts = lg_type_normalize(L, ar->ts);	// OK

    /*
    type_info_t ti = lg_get_type_info(ar->ts);
    const struct ffi_type_map_t *ffi = lg_get_ffi_type(ar->ts);
    printf("%s arg #%d: %s.%d = %s*%d - %s\n",
	ar->ci->fi->name, ar->func_arg_nr,
	modules[ar->ts.module_idx]->name, ar->ts.type_idx,
	lg_get_type_name(ar->ts),
	ti->st.indirections,
	FTYPE_NAME(ffi));
    */
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
    struct call_arg *ca;
    int arg_nr, idx;

    /* build the call stack by parsing the parameter list */
    memset(&ar, 0, sizeof(ar));
    ar.stack_top = lua_gettop(L);	    // last argument's index
    ar.stack_curr_top = ar.stack_top;	    // expected top (for debugging)
    ar.L = L;
    ar.ci = ci;
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    // arg_nr 1 is the first
    index--;

    // Check that enough space for arguments (+1 for the return value)
    // is allocated.
    int arg_count = ar.stack_top - index + 1;
    call_info_check_argcount(ci, arg_count);

    // look at each required parameter for this function.
    for (arg_nr = 0; s < s_end; arg_nr++) {
	ar.func_arg_nr = arg_nr;
	ar.ts.module_idx = ci->fi->module_idx;
	get_next_argument(L, &s, &ar);
	ar.arg_type = lg_get_ffi_type(ar.ts);

	idx = ar.arg_type->ffi_type_idx;
	if (idx == 0) {
	    LG_MESSAGE(18, "Argument %d (type %s) has no ffi type.\n",
		arg_nr, FTYPE_NAME(ar.arg_type));
	    call_info_msg(L, ci, LUAGTK_ERROR);
	    luaL_error(L, "call error\n");
	}
	ci->argtypes[arg_nr] = LUAGTK_FFI_TYPE(idx);

	/* the first "argument" is actually the return value; no more work. */
	if (arg_nr == 0) {
	    ci->argvalues[0] = NULL;	    // just to be sure
	    continue;
	}

	// No more arguments available?
	if (index+arg_nr > ar.stack_top) {
	    // If the current (probably last) argument is vararg, this is OK,
	    // because a vararg doesn't need any extra arguments.
	    if (strcmp(FTYPE_NAME(ar.arg_type), "vararg")) {
		LG_MESSAGE(19, "More arguments expected -> nil used\n");
		call_info_msg(L, ci, LUAGTK_WARNING);
	    }
	    ar.lua_type = LUA_TNIL;
	} else 
	    ar.lua_type = lua_type(L, index+arg_nr);

	ca = &ci->args[arg_nr];
	ci->argvalues[arg_nr] = &ca->ffi_arg;

	// if there's a handler to convert the argument, do it
	idx = ar.arg_type->conv_idx;
	if (idx && ffi_type_lua2ffi[idx]) {
	    ar.index = index + arg_nr;
	    ar.arg = &ci->args[arg_nr].ffi_arg;
//	    int st_pos_1 = lua_gettop(L);
	    ffi_type_lua2ffi[idx](&ar);

	    // Shouldn't happen.  Can be fixed, but complain anyway
	    if (lua_gettop(L) != ar.stack_curr_top) {
		LG_MESSAGE(20, "lua2ffi changed the stack\n");
		call_info_msg(L, ci, LUAGTK_DEBUG);
		lua_settop(L, ar.stack_curr_top);
	    }

	    // The function might use up more than one parameter, e.g. when
	    // handling a vararg.
	    arg_nr = ar.func_arg_nr;
	} else {
	    LG_MESSAGE(21, "Argument %d (type %s) not handled\n", arg_nr,
		FTYPE_NAME(ar.arg_type));
	    call_info_msg(L, ci, LUAGTK_WARNING);
	    luaL_error(L, "call error\n");
	    ci->args[arg_nr].ffi_arg.l = 0;
	}
    }

    // The return value is included (no -1)
    ci->arg_count = arg_nr;

    // Warn about unused arguments.
    int n = ar.stack_top - (index+arg_nr-1);
    if (n > 0) {
	LG_MESSAGE(22, "%d superfluous argument%s\n", n, n==1?"":"s");
	call_info_msg(L, ci, LUAGTK_WARNING);
    }

    return 1;
}


/**
 * After completing a call to a Gtk function, push the return values
 * on the Lua stack.
 *
 * @param L  Lua State
 * @param index  Stack position of the function's first argument.
 * @param ci  Call Info of the called function.
 */
static int _call_return_values(lua_State *L, int index, struct call_info *ci)
{
    int stack_pos = lua_gettop(L), arg_nr, skip=0;
    const unsigned char *s, *s_end;
    struct argconv_t ar;

    ar.L = L;
    ar.ci = ci;
    ar.mode = ARGCONV_CALL;

    /* Return the return value and output arguments.  This requires another
     * pass at parsing the argument spec. */
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    for (arg_nr = 0; s < s_end; arg_nr++) {
	ar.func_arg_nr = arg_nr;
	ar.ts.module_idx = ci->fi->module_idx;
	get_next_argument(L, &s, &ar);

	// ffi2lua_xxx functions may use more than one argument.
	if (skip) {
	    skip--;
	    continue;
	}

	ar.arg_type = lg_get_ffi_type(ar.ts);
	int idx = ar.arg_type->conv_idx;

	/* The INCREF flag means to increase the refcount of a function's
	 * argument - required when the called function takes ownership
	 * of the argument without increasing its refcount.  This would lead
	 * to an invalid decrease in refcount when the Lua proxy object
	 * is garbage collected. */
	if (arg_nr > 0 && ar.arg_flags & FLAG_INCREF) {
	    struct object *o = (struct object*) lua_touserdata(L,
		index + arg_nr - 1);
	    lg_inc_refcount(L, o, 0);
	}

	if (arg_nr == 0) {

	    // The actual return value must be handled.
	    if (idx == 0) {
		call_info_warn(ci);
		luaL_error(L, "%s unhandled return type %s\n",
		    msgprefix, FTYPE_NAME(ar.arg_type));
	    }
	} else if (ar.arg_type->indirections == 0) {
	    // only pointers can be output types.
	    continue;
	    // XXX could automatically skip "const" items.  This doesn't
	    // really help as output arguments are explicitely marked and
	    // so these are automatically ignored. 
	} else if (ci->args[arg_nr].is_output == 0) {
	    // not marked as output during first argument scanning
	    continue;
	} else if (!idx || !ffi_type_ffi2lua[idx]) {
	    // no type conversion defined
	    continue;
	} else {
	    // Remove one level of indirections from the type.  This will
	    // be the output type.
	    ar.ts = lg_type_modify(L, ar.ts, -1);
	    if (!ar.ts.value) {
		printf("could not modify type!\n");
		continue;
	    }
	}

	ar.index = index + arg_nr - 1;
	ar.arg = &ci->args[arg_nr].ffi_arg;
	ar.lua_type = arg_nr ? lua_type(L, ar.index) : LUA_TNIL;
	int cnt = ffi_type_ffi2lua[idx](&ar);
	if (cnt > 0)
	    skip = cnt - 1;

	// if a special arg_flag is given, try to call the handler of the
	// module (of the function, not of the argument).
	if (cnt == 1 && (ar.arg_flags & 0xf0)) {
	    cmi mi = modules[ar.ci->fi->module_idx];
	    if (mi->arg_flags_handler)
		mi->arg_flags_handler(L, ar.ts, ar.arg_flags);
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
int lg_call_byname(lua_State *L, cmi mi, const char *func_name)
{
    struct func_info fi;
    if (lg_find_func(L, mi, func_name, &fi))
	return lg_call(L, &fi, 1);
    return luaL_error(L, "%s function %s not found", msgprefix, func_name);
}

/**
 * Similar to lg_call_byname, but when the module of the function is
 * provided as name and not directly.
 */
int lg_call_function(lua_State *L, const char *mod_name, const char *func_name)
{
    int i;
    struct func_info fi;
    cmi mi;

    for (i=1; i<=module_count; i++) {
	mi = modules[i];
	if (mod_name && strcmp(mod_name, mi->name))
	    continue;
	if (lg_find_func(L, mi, func_name, &fi))
	    return lg_call(L, &fi, 1);
    }
    return luaL_error(L, "%s function %s not found", msgprefix, func_name);
}


/**
 * Call a library function from Lua.  The information about parameters and
 * return values is compiled in (automatically generated). 
 *
 * @param L  Lua State
 * @param fi  Description of the library function to call
 * @param index  Lua stack position where the first argument is
 * @return  The number of results on the Lua stack
 */
int lg_call(lua_State *L, struct func_info *fi, int index)
{
    struct call_info *ci;
    ffi_cif cif;
    int rc = 0;

    cmi mi = modules[fi->module_idx];
    if (mi->call_hook)
	mi->call_hook(L, fi);

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
	if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, ci->arg_count - 1,
	    ci->argtypes[0], ci->argtypes + 1) == FFI_OK) {

	    // A trace function displaying the argument values could be called
	    // from here.  This doesn't exist yet.
	    // XXX call_info_trace(ci);

	    struct call_info *tmp = ci_current;
	    ci_current = ci;
	    ffi_call(&cif, fi->func, &ci->args[0].ffi_arg, ci->argvalues + 1);
	    ci_current = tmp;

	    /* evaluate the return values */
	    rc = _call_return_values(L, index, ci);
	} else {
	    return luaL_error(L, "%s FFI call to %s couldn't be initialized.",
		msgprefix, fi->name);
	}
    }

    call_info_free(ci);
    return rc;
}

