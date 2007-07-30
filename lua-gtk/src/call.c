/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * This module contains the routines that call Gtk functions from Lua, and
 * callbacks from Gtk to Lua.
 */

#include "luagtk.h"
#include <lauxlib.h>
#include <malloc.h>	    // free
#include <string.h>	    // memset, strcmp, memcpy
#include <stdlib.h>	    // strtol
#include "hash.h"

#ifdef MANUAL_LINKING
# include "link.c"
#endif

#ifdef DEBUG_TRACE_CALLS

/**
 * For debugging purposes, trace all calls.  Print a line to stderr with the
 * return value, function name, and all parameters.
 */
void _call_trace(lua_State *L, struct func_info *fi, int index)
{
    const unsigned char *s, *s_end;
    const struct ffi_type_map_t *arg_type;
    int arg_struct_nr, i, type;

    /* Find out from where in the Lua code this library function has been
     * called */
    lua_Debug ar;
    if (lua_getstack(L, 1, &ar)) {
	if (lua_getinfo(L, "S", &ar)) {
	    fprintf(stderr, "%s(%d): ", ar.source, ar.linedefined);
	}
    }
    
    s = fi->args_info;
    s_end = s + fi->args_len;

    for (i = -1; s < s_end; i++) {
	arg_type = &ffi_type_map[*s - '0'];
	s ++;
	if (arg_type->with_struct) {
	    arg_struct_nr = * (unsigned short*) s;
	    s += 2;
	} else {
	    arg_struct_nr = 0;
	}
	type = lua_type(L, index+i);

	if (i == -1) {
	    fprintf(stderr, "- %s %s(", arg_type->name, fi->name);
	} else {
	    fprintf(stderr, "%s%s", i == 0 ? "" : ", ", arg_type->name);
	    switch (arg_type->at)  {
		case AT_STRING:
		    if (type == LUA_TSTRING)
			fprintf(stderr, "=%s", lua_tostring(L, index+i));
		    else if (type == LUA_TNIL)
			fprintf(stderr, "=NIL");
		    else
			fprintf(stderr, "=NOT A STRING!");
		    break;

		case AT_LONG:
		    if (lua_isnumber(L, index+i))
			fprintf(stderr, "=%f", (float) lua_tonumber(L, index+i));
		    else
			fprintf(stderr, "=NOT A NUMBER");
		    break;
		case AT_BOOL:
		    if (type == LUA_TBOOLEAN)
			fprintf(stderr, "=%s", lua_toboolean(L, index+i)
			    ? "true" : "false");
		    else
			fprintf(stderr, "=NOT A BOOLEAN");
		    break;
		default:
		    break;
	    }
	}
    }
    fprintf(stderr, ")\n");
    // dump_stack(L, 0);
}

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
static void *call_info_alloc_item(struct call_info *ci, int size)
{
    size += sizeof(struct call_info_list);
    struct call_info_list *item = (struct call_info_list*) malloc(size);
    memset(item, 0, size);
    item->next = ci->first;
    ci->first = item;
    return item + 1;
}

/**
 * Free all extra parameters, and the call info structure itself.
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

    ci->first = NULL;

    // XXX lock spinlock
    ci->next = ci_pool;
    ci_pool = ci;
    // XXX unlock spinlock
}

#if 0

/**
 * At program exit (library close), free the pool.  This is not really required
 * but may help spotting memory leaks.
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
 */
void call_info_warn(struct call_info *ci)
{
#ifdef DEBUG_TRACE_CALLS
    if (!ci->warnings) {
	_call_trace(ci->L, ci->fi, ci->index);
    }
    ci->warnings = 1;
#endif
}

/**
 * Try to convert a value on the Lua stack into a GValue.  The resulting
 * type of the GValue depends on the Lua type.
 *
 * Returns NULL on failure.  The returned GValue is newly allocated, but
 * will be freed automatically.
 */
static GValue *_make_gvalue(lua_State *L, struct call_info *ci, int type,
    int index)
{
    GValue *gvalue = (GValue*) call_info_alloc_item(ci, sizeof *gvalue);

    switch (type) {
	case LUA_TNUMBER:
	// g_value_set_uint(gvalue, lua_tonumber(L, index));
	gvalue->g_type = G_TYPE_UINT;
	gvalue->data[0].v_uint = lua_tonumber(L, index);
	break;

	case LUA_TBOOLEAN:
	gvalue->g_type = G_TYPE_BOOLEAN;
	gvalue->data[0].v_uint = lua_toboolean(L, index) ? 1: 0;
	break;

	case LUA_TSTRING:;
	// try to convert to a number.
	long int val;
	char *endptr;
	val = strtol(lua_tostring(L, index), &endptr, 0);
	if (*endptr == 0) {
	    gvalue->g_type = G_TYPE_LONG;
	    gvalue->data[0].v_long = val;
	    break;
	}

	// not convertible to a number.
	gvalue->g_type = G_TYPE_POINTER;
	gvalue->data[0].v_pointer = (void*) lua_tostring(L, index);
	break;

	// if it already is a GValue, just copy the contents.
	// XXX can this lead to double free() calls??
	case LUA_TUSERDATA:
	lua_getmetatable(L, index);
	lua_pushstring(L, "_classname");
	lua_rawget(L, -2);
	const char *class_name = lua_tostring(L, -1);
	if (!strcmp(class_name, "GValue")) {
	    struct widget *w = (struct widget*) lua_topointer(L, index);
	    GValue *gv = w->p;
	    memcpy(gvalue, gv, sizeof(*gvalue));
	    lua_pop(L, 2);
	    break;
	}
	lua_pop(L, 2);

	/* fall through */

	default:
	printf("%s can't coerce type %d to GValue\n", msgprefix,type);
	gvalue = NULL;
    }
    return gvalue;
}

/**
 * A structure should be passed to a Gtk function.
 */
int _make_struct_ptr(lua_State *L, struct call_info *ci, int struct_nr,
    int index, int type, void **p)
{
    const struct struct_info *si = struct_list+struct_nr;
    const char *name = STRUCT_NAME(si);

    if (!strcmp(name, "GValue")) {
	*p = _make_gvalue(L, ci, type, index);
	return *p ? 1 : 0;
    }

    struct widget *w = (struct widget*) lua_topointer(L, index);

    if (!strcmp(name, "GObject")) {
	*p = w->p;
	return 1;
    }

    /* generic NULL pointer can be used */
    if (!w) {
	*p = NULL;
	return 1;
    }

    /* generic other structure - pass the pointer to it. */
    *p = w->p;

    /*
    call_info_warn(ci);
    printf("  Warning: Unhandled struct_ptr of type %s, addr %p\n", name, *p);
    */

    return 1;
}


/**
 * Gtk wants to call a Lua function, whose address was passed to a Gtk function
 * as callback.
 */
/*
int l_giofunc_marshal(GIOChannel *source, GIOCondition condition, gpointer data)
// int l_giofunc_marshal(lua_State *L)
{
    lua_State *L = (lua_State*) data;
    printf("callback l_giofunc_marshal...  but what??\n");
    dump_stack(L, 0);
    return 0;
}
*/


/**
 * Prepare to call the Gtk function by converting all the parameters into
 * the required format.
 *
 * Returns 0 on error, 1 otherwise.
 */
static int _call_build_parameters(lua_State *L, int index, struct call_info *ci)
{
    const unsigned char *s, *s_end;
    const struct ffi_type_map_t *arg_type;
    int arg_struct_nr, i, type;
    int stack_top = lua_gettop(L);

    /* build the call stack by parsing the parameter list */
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    for (i = -1; s < s_end; i++) {
	arg_type = &ffi_type_map[*s - '0'];
	s ++;
	if (arg_type->with_struct) {
	    arg_struct_nr = * (unsigned short*) s;
	    s += 2;
	} else {
	    arg_struct_nr = -1;
	}

	/* the first "argument" is actually the return value */
	if (i == -1) {
	    ci->ret_type = arg_type;
	    ci->ret_struct_nr = arg_struct_nr;
	    continue;
	}

	if (index+i > stack_top) {
	    if (arg_type->at != AT_VARARG) {
		call_info_warn(ci);
		printf("  Warning: more arguments expected -> nil used\n");
	    }
	    type = LUA_TNIL;
	} else 
	    type = lua_type(L, index+i);

	ci->argtypes[i] = arg_type->type;
	ci->argvalues[i] = &ci->ffi_args[i].l;

	
	/* arg_type: next argument as expected by the C function */
	/* type: next Lua argument. */

	switch (arg_type->at) {
	    case AT_BOOL:
		luaL_checktype(L, index+i, LUA_TBOOLEAN);
		ci->ffi_args[i].l = (long) lua_toboolean(L, index+i);
		break;
	    case AT_LONG:
		ci->ffi_args[i].l = (long) luaL_checknumber(L, index+i);
		break;
	    case AT_DOUBLE:
		ci->ffi_args[i].d = (double) luaL_checknumber(L, index+i);
		break;
	    case AT_STRING:
		if (type == LUA_TNIL) {
		    // printf("NULL string arg for %s arg %d\n", ci->fi->name,i+1);
		    ci->ffi_args[i].p = NULL;
		} else
		    ci->ffi_args[i].p = (void*) luaL_checkstring(L, index+i);
		break;
	    case AT_WIDGET:
		if (type == LUA_TNIL)
		    ci->ffi_args[i].p = NULL;
		else if (type == LUA_TUSERDATA) {
		    // XXX check type -- using some glib function!
#if 1
		    // check type
		    if (!lua_getmetatable(L, index+i)) {
			printf("%s widget has no meta table.\n", msgprefix);
			return 0;
		    }

		    lua_pushstring(L, "_classname");
		    lua_rawget(L, -2);

		    const char *is_name = lua_tostring(L, -1);
		    GType is_type = g_type_from_name(is_name);

		    const char *req_name = STRUCT_NAME(struct_list
			+ arg_struct_nr);
		    GType req_type = g_type_from_name(req_name);

		    if (is_type != req_type && !g_type_is_a(is_type,req_type)) {
			printf("Widget type %s is not %s\n", is_name, req_name);
			return 0;
		    }
		    lua_pop(L, 2);
#endif
		    struct widget *w = (struct widget*) lua_topointer(L,
			index + i);
		    ci->ffi_args[i].p = w->p;
		} else {
		    printf("%s incompatible argument #%d for %s (type %d)\n",
			msgprefix, i, ci->fi->name, type);
		    return 0;
		}
		break;

	    case AT_STRUCTPTR:;
		const struct struct_info *si = struct_list+arg_struct_nr;
		void *p;
		int rc = _make_struct_ptr(L, ci, arg_struct_nr, index+i, type,
		    &p);
		if (!rc) {
		    printf("%s unhandled argument #%d to %s: "
			"type=%s\n", msgprefix, i+1, ci->fi->name,
			NAME(si->name_ofs));
		    return 0;
		}
		ci->ffi_args[i].p = p;
		break;

	    /* some kind of pointer is requested */
	    /* XXX sometimes a pointer to a pointer is wanted... */
	    case AT_POINTER:
		if (type == LUA_TNIL)
		    ci->ffi_args[i].p = NULL;
		else if (type == LUA_TLIGHTUSERDATA)
		    ci->ffi_args[i].p = (void*) lua_topointer(L, index+i);
		else if (type == LUA_TUSERDATA) {
		    struct widget *w = (struct widget*)lua_topointer(L,index+i);
		    ci->ffi_args[i].p = w->p;
		} else if (type == LUA_TSTRING)
		    ci->ffi_args[i].p = (void*) lua_tostring(L, index+i);
		else if (type == LUA_TTABLE) {
		    lua_rawgeti(L, index+i, 1);
		    if (!lua_isstring(L, -1)) {
			printf("%s %s, arg #%d: invalid table (1)\n",
			    msgprefix, ci->fi->name, i+1);
			return 0;
		    }
		    const char *s = lua_tostring(L, -1);
		    if (!strcmp(s, "marshalled")) {
			lua_rawgeti(L, index+i, 2);
			ci->ffi_args[i].p = (void*) lua_topointer(L, -1);
			lua_pop(L, 2);
		    } else {
			printf("%s %s, arg #%d: invalid table (2)\n",
			    msgprefix, ci->fi->name, i+1);
			return 0;
		    }
#if 0
		} else if (type == LUA_TFUNCTION) {
		    if (!lua_iscfunction(L, index+i)) {
			printf("%s %s, arg #%d: You can't provide a Lua "
			    "function as callback.  Please use a wrapper.",
			    msgprefix, ci->fi->name, i+1);
			return 0;
		    }
		    breakfunc();
		    /* ouch.  this retrieves the address of the C function */
		    ci->ffi_args[i].p = get_c_function_address(L, index+i);
#endif
		} else {
		    printf("%s %s, arg #%d: don't know what to do with "
			"AT_POINTER of type %d, struct_nr=%d.\n", msgprefix,
			ci->fi->name, i+1, type, arg_struct_nr);
		    return 0;
		}
		break;

	    case AT_LONGPTR:
		/* Can be input: e.g. gdk_pango_layout_get_clip_region
		 * Use as such when an array (of numbers) is given.
		 */
		if (lua_istable(L, index+i)) {
		    int j, n, *ar;
		    n = luaL_getn(L, index+i);
		    ar = (int*) call_info_alloc_item(ci, sizeof(*ar) * n);
		    for (j=0; j<n; j++) {
			lua_rawgeti(L, index+i, j+1);
			ar[j] = lua_tonumber(L, -1);
			lua_pop(L, 1);
		    }
		    ci->ffi_args[i].p = (void*) ar;
		    break;
		}

		/* This is an OUTPUT value - initialize with whatever the
		 * user passed as parameter. */
		ci->ffi_args[i].p = (void*) &ci->retvals[i];
		ci->retvals[i].l = lua_tonumber(L, index+i);
		break;

	    case AT_VARARG:
		/* use the rest of the stack */
		for (; index+i <= stack_top; i++) {
		    int type = lua_type(L, index+i);
		    switch (type) {
			case LUA_TNUMBER:
			    ci->argtypes[i] = &ffi_type_uint;
			    ci->argvalues[i] = &ci->ffi_args[i].l;
			    ci->ffi_args[i].l = (long) lua_tonumber(L, index+i);
			    break;
			case LUA_TSTRING:
			    ci->argtypes[i] = &ffi_type_pointer;
			    ci->argvalues[i] = &ci->ffi_args[i].p;
			    ci->ffi_args[i].p = (void*) lua_tostring(L, index+i);
			    break;
			case LUA_TNIL:
			    ci->argtypes[i] = &ffi_type_pointer;
			    ci->argvalues[i] = &ci->ffi_args[i].p;
			    ci->ffi_args[i].p = NULL;
			    break;
			case LUA_TLIGHTUSERDATA:
			    ci->argtypes[i] = &ffi_type_pointer;
			    ci->argvalues[i] = &ci->ffi_args[i].p;
			    ci->ffi_args[i].p = (void*) lua_topointer(L, index + i);
			    break;
			case LUA_TUSERDATA:;
			    void *p = (void*) lua_topointer(L, index + i);
			    ci->argtypes[i] = &ffi_type_pointer;
			    ci->argvalues[i] = &ci->ffi_args[i].p;
			    // no metatable - pass pointer as is
			    if (!lua_getmetatable(L, index+i)) {
				ci->ffi_args[i].p = p;
				break;
			    }
			    // is this a widget? if not, pass pointer as is
			    lua_getfield(L, -1, "_classname");
			    if (lua_isnil(L, -1)) {
				lua_pop(L, 2);
				ci->ffi_args[i].p = p;
				break;
			    }
			    // this is a widget - pass the pointer
			    struct widget *w = (struct widget*) p;
			    ci->ffi_args[i].p = w->p;
			    break;
			    
			default:
			    call_info_warn(ci);
			    printf("  Unhandled vararg type %d\n", type);
		    }
		}
		/* counter the i++ of next iteration. */
		i--;
		break;

	    // XXX some types might still be missing.

	    default:
		call_info_warn(ci);
		printf("  Argument %d (type %s) not handled\n", i+1,
		    arg_type->name);
		ci->ffi_args[i].l = 0;
	}
    }

    ci->arg_count = i;

    /* any arguments left over? (note: more might be used than given -> nil) */
    int n = stack_top - (index+i-1);
    if (n > 0) {
	call_info_warn(ci);
	printf("  Warning: %d superfluous argument%s\n", n, n==1?"":"s");
    }

    return 1;
}

	    

/**
 * After completing a call to a Gtk function, push the return values
 * on the Lua stack.
 */
static int _call_return_values(lua_State *L, struct call_info *ci)
{
    int stack_pos = lua_gettop(L), i, arg_struct_nr;
    const unsigned char *s, *s_end;
    const struct ffi_type_map_t *arg_type;
    const char *s2;

    /* evaluate the return value */
    // printf("- %s: return type is %s\n", fi->name, ret_type->name);
    switch (ci->ret_type->at) {
	case AT_LONG:
	    lua_pushnumber(L, ci->retval.l);
	    break;

	case AT_BOOL:
	    lua_pushboolean(L, ci->retval.l);
	    break;

	case AT_DOUBLE:
	    lua_pushnumber(L, ci->retval.d);
	    break;

	case AT_WIDGET:
	    // If a structure nr is given, but the corresponding class is
	    // derived from GtkObject, then let get_widget (hence, make_widget)
	    // autodetect the type.  This is good if the actual object is
	    // from a derived class - with added functionality.
	    i = ci->ret_struct_nr;
	    if (i) {
		s2 = STRUCT_NAME(struct_list+ci->ret_struct_nr);
		GType my_type = g_type_from_name(s2);
		if (s2) {
		    GType go_type = g_type_from_name("GtkObject");
		    if (g_type_is_a(my_type, go_type))
			i = 0;
		}
	    }

	    // this is a new object, as returned from the function
	    get_widget(L, ci->retval.p, i, 1);
	    break;


	case AT_STRUCTPTR:
	    // a new object.  As this is not a widget, but a structure, no
	    // refcounting will be done anyway.
	    get_widget(L, ci->retval.p, ci->ret_struct_nr, 1);
	    // make_widget(L, ci->retval.p, ci->ret_struct_nr);
	    // lua_pushlightuserdata(L, ci->retval.p);
	    break;

	case AT_VOID:
	    break;

	case AT_STRING:
	    lua_pushstring(L, (char*) ci->retval.p);
	    break;

	case AT_POINTER:
	    get_widget(L, ci->retval.p, 0, 1);
	    break;

	default:
	    printf("%s unhandled return type %s of %s\n",
		msgprefix, ci->ret_type->name, ci->fi->name);
    }

    /* Return output parameters, too.  Unfortunately, this requires
     * another pass at parsing the parameters.
     */
    s = ci->fi->args_info;
    s_end = s + ci->fi->args_len;

    for (i = -1; s < s_end; i++) {
	arg_type = &ffi_type_map[*s - '0'];
	s ++;
	if (arg_type->with_struct) {
	    arg_struct_nr = * (unsigned short*) s;
	    s += 2;
	} else {
	    arg_struct_nr = 0;
	}
	if (i == -1)
	    continue;

	switch (arg_type->at) {
	    case AT_LONGPTR:
		lua_pushnumber(L, ci->retvals[i].l);
		break;

	    case AT_STRUCTPTR:;
		const struct struct_info *si = struct_list + arg_struct_nr;
		if (!strcmp(STRUCT_NAME(si), "GValue")) {
		    GValue *gvalue = (GValue*) ci->ffi_args[i].p;
		    push_a_value(L, gvalue->g_type,
			(union gtk_arg_types*) &gvalue->data, NULL, 0);
		}
		break;

	    case AT_POINTER:
		// is this a new object, or not??  guess not.
		get_widget(L, ci->ffi_args[i].p, 0, 0);
		if (!lua_isnil(L, -1))
		    break;

#ifdef DEBUG_RETURN_VALUE
		call_info_warn(ci);
		printf("  Warning: return value of arg %d discarded.\n", i+1);
#endif
		break;

	    default:
		break;
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
int do_call(lua_State *L, struct func_info *fi, int index)
{
    struct call_info *ci;
    ffi_cif cif;
    int rc = 0;

    ci = call_info_alloc();

    ci->fi = fi;
    ci->L = L;
    ci->index = index;

#ifdef DEBUG_TRACE_ALL_CALLS
    call_info_warn(ci);
    ci->warnings = 2;
#endif

    /*
     * ffi_args	    array of values passed to the function
     * argtypes	    array of types for ffi_call
     * argvalues    array of pointers to the values
     */

    do {

	if (!_call_build_parameters(L, index, ci))
	    break;

	/* call the function */
	if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, ci->arg_count,
	    ci->ret_type->type,
	    ci->argtypes) != FFI_OK) {
	    printf("FFI call to %s couldn't be initialized\n", fi->name);
	    break;
	}

	ffi_call(&cif, fi->func, &ci->retval, ci->argvalues);

	/* evaluate the return values */
	rc = _call_return_values(L, ci);
    } while (0);

    call_info_free(ci);
    return rc;
}

/**
 * Given a pointer, a bit offset and a bit length, retrieve the value.
 */
long get_bits(const unsigned char *ptr, int bitofs, int bitlen)
{
    unsigned int val;

    if (bitlen == 0 || bitlen > 32) {
	printf("%s access to attribute of size %d not supported\n",
	    msgprefix, bitlen);
	return 0;
    }

    ptr += bitofs / 8;
    bitofs = bitofs % 8;
    unsigned int mask = 0xffffffff;
    if (bitlen < 32) {
	mask = (1 << bitlen) - 1;
    }

    // XXX not tested for bitofs > 0
    // XXX possible problems with endianness
    val = ((* (unsigned int*) ptr) >> bitofs) & mask;
    return val;
}


static void set_bits(const unsigned char *ptr, int bitofs, int bitlen, unsigned int val)
{
    unsigned int v;

    if (bitlen == 0 || bitlen > 32) {
	printf("%s write to attribute of size %d not supported\n",
	    msgprefix, bitlen);
	return;
    }

    /* do byte aligned accesses */
    ptr += bitofs / 8;
    bitofs = bitofs % 8;

    unsigned int mask = 0xffffffff;
    if (bitlen < 32) {
	mask = (1 << bitlen) - 1;
	mask <<= bitofs;
    }

    v = * (unsigned int*) ptr;
    v &= ~mask;
    v |= (val << bitofs) & mask;
    * (unsigned int*) ptr = v;
}



/**
 * Given a pointer to a structure and the description of the desired element,
 * push a value onto the Lua stack with this item.
 *
 * Returns the number of pushed items, i.e. 1 on success, 0 on failure.
 */
int _push_attribute(lua_State *L, const struct struct_elem *se,
    unsigned char *ptr)
{
    const struct ffi_type_map_t *arg_type;
    long int v;

    arg_type = &ffi_type_map[se->type - '0'];
    switch (arg_type->at) {
	case AT_BOOL:	    // XXX untested
	case AT_LONG:
	    v = get_bits(ptr, se->bit_offset, se->bit_length);
	    lua_pushnumber(L, v);
	    return 1;

	case AT_WIDGET:
	    // XXX Baustelle - die nächste Zeile scheint OK
	    v = get_bits(ptr, se->bit_offset, se->bit_length);
	    // use autodetection...
	    get_widget(L, (void*) v, 0, 0); // , se->type_detail, NULL);
	    return 1;

	case AT_STRUCT:
	    get_widget(L, ptr + se->bit_offset/8, se->type_detail, 0);
	    return 1;
	
	case AT_STRING: {
	    gchar **addr = (gchar**) (ptr + se->bit_offset/8);
	    if (addr)
		lua_pushstring(L, *addr);
	    else
		lua_pushnil(L);
	    return 1;
	    }
	
	case AT_POINTER: {
	    void **addr = (void*) (ptr + se->bit_offset/8);
	    if (addr) {
		printf("Warning: access to AT_POINTER address %p\n", *addr);
		lua_pushlightuserdata(L, *addr);
	    } else
		lua_pushnil(L);
	    return 1;
	}

	// XXX handle more data types! e.g. AT_DOUBLE
	default:
	    printf("%s unhandled attribute type %s (attribute %s)\n",
		msgprefix, arg_type->name, STRUCT_NAME(se));
    }
    return 0;
}

/**
 * Write an attribute (only numeric so far), i.e. a field of a Gtk structure.
 *
 * index: the Lua stack index where the data is to be found.
 */
int _write_attribute(lua_State *L, const struct struct_elem *se,
    unsigned char *ptr, int index)
{
    const struct ffi_type_map_t *arg_type;
    long unsigned int v;

    arg_type = &ffi_type_map[se->type - '0'];
    switch (arg_type->at) {
	case AT_LONG:
	    v = lua_tonumber(L, index);
	    // printf("set bits %p %d %d to %u\n", ptr, se->bit_offset, se->bit_length, v);
	    set_bits(ptr, se->bit_offset, se->bit_length, v);
	    return 1;
	
	default:
	    printf("%s unhandled attribute write of type %s (attribute %s)\n",
		msgprefix, arg_type->name, STRUCT_NAME(se));
    }

    return 0;   
}

