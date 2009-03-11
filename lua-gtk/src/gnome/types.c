/** vim:sw=4:sts=4
 * Library to use the Gtk2 object library from Lua 5.1
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * Handle type conversion from Lua to and from C (or Gtk).
 *
 * Exported symbols:
 *   lg_empty_table
 *   ffi_type_lua2ffi
 *   ffi_type_ffi2lua
 *   ffi_type_lua2struct
 *   ffi_type_struct2lua
 *   ffi_type_map
 *   core_ffi_type_names
 */
#include "luagnome.h"
#include "lg_ffi.h"

#include <lauxlib.h>
#include <string.h>	    // strcmp
#include <stdlib.h>	    // strtol
#include <math.h>	    // floor

// The order in these ENUMs must match the function pointer arrays at the
// end of this file.
enum { CONV_VOID=1, CONV_BOOL, CONV_LONG, CONV_LONGLONG,
    CONV_ENUM, CONV_DOUBLE, CONV_FLOAT, CONV_UCHAR,
    CONV_CHAR_PTR, CONV_STRUCT_PTR, CONV_INT_PTR,
    CONV_UNSIGNED_INT_PTR, CONV_LONG_UNSIGNED_INT_PTR,
    CONV_VOID_PTR, CONV_STRUCT_PTR_PTR, CONV_CHAR_PTR_PTR,
    CONV_ENUM_PTR, CONV_BOOL_PTR, CONV_ENUM_PTR_PTR,
    CONV_PTR, CONV_VARARG, CONV_FUNC_PTR, CONV_DOUBLE_PTR,
    };
// max. items: 31; curr 23

enum { STRUCTCONV_LONG=1, STRUCTCONV_ENUM, STRUCTCONV_DOUBLE,
    STRUCTCONV_VOID_PTR, STRUCTCONV_FUNC_PTR,
    STRUCTCONV_STRUCT_PTR, STRUCTCONV_STRUCT,
    STRUCTCONV_CHAR_PTR, STRUCTCONV_PTR, 
};
// max items: 15; curr 9


/**
 * Given a pointer, a bit offset and a bit length, retrieve the value.
 * This is used for non 8 bit things, like single bits.  The destination
 * is a long.
 *
 * Tested on 32 and 64 bit architectures.
 */
#define BITS_PER_INT (sizeof(unsigned long int)*8)
static void get_bits_unaligned(lua_State *L, const unsigned char *ptr,
    int bitofs, int bitlen, char *dest)
{
    unsigned long int val;

    if (bitlen && bitlen <= BITS_PER_INT) {
	ptr += bitofs >> 3;
	bitofs = bitofs & 7;
	val = (* (unsigned long*) ptr) >> bitofs;
	if (bitlen < BITS_PER_INT)
	    val &= (1L << bitlen) - 1;
	* (unsigned long*) dest = val;
	return;
    }

    LG_ERROR(10, "Access to attribute of size %d not supported.", bitlen);
}
#undef BITS_PER_INT

/**
 * Retrieve an arbitrarily long memory block, which must be byte aligned
 * and the length must be a multiple of 8 bits.  Note that if "bitlen" is
 * less than the variable "dest" points to, the additional bytes won't be
 * initialized.  Therefore, set them to zero before calling this function.
 *
 * If "bitlen" is not a multiple of 8, then get_bits_unaligned will be
 * called, which assumes that "dest" is an unsigned long integer.
 */
void get_bits_long(struct argconvs_t *ar, char *dest)
{
    int bit_offset = ar->se->bit_offset;
    int bit_length = ar->se->bit_length;

    if (((bit_offset | bit_length) & 7) == 0)
	memcpy(dest, ar->ptr + (bit_offset >> 3), bit_length >> 3);
    else
	get_bits_unaligned(ar->L, ar->ptr, bit_offset, bit_length, dest);
}



/**
 * Write a numerical field within a structure.
 *
 * Note. Writing to fields spanning more than one "unsigned long int" is not
 * supported - but this shouldn't happen anyway.
 *
 * @param ptr Pointer to the start of the structure
 * @param bitofs Offset of the field within the structure
 * @param bitlen Length of the field
 * @param val value to write into the field.
 */
static void set_bits(const unsigned char *ptr, int bitofs, int bitlen,
    unsigned long int val)
{
    unsigned long int v, mask;

    /* do byte aligned accesses */
    ptr += bitofs / 8;
    bitofs = bitofs % 8;

    if (bitlen == 0 || bitlen+bitofs > sizeof(v)*8) {
	printf("%s write to attribute of size %d not supported\n",
	    msgprefix, bitlen);
	return;
    }

    mask = (bitlen < sizeof(mask)*8) ? ((1L << bitlen) - 1) : -1L;
    mask <<= bitofs;

    // fetch the old value, replace bits with new value, write back.
    v = * (unsigned long int*) ptr;
    v &= ~mask;
    v |= (val << bitofs) & mask;
    * (unsigned long int*) ptr = v;
}

static inline void set_bits_long(lua_State *L, unsigned char *dest, int bitofs,
    int bitlen, const char *src)
{
    if (((bitofs | bitlen) & 7) == 0)
	memcpy(dest + (bitofs >> 3), src, (bitlen >> 3));
    else
	luaL_error(L, "%s unaligned access in set_bits_long", msgprefix);
}



// ----- LUA2FFI FUNCTIONS -----
// these functions retrieve a value from Lua and store it in a ffi
// value

/**
 * These functions retrieve a value from the Lua stack and store it into
 * the provided target.  They are used to convert the arguments to
 * C functions called from Lua, but also to convert the return values
 * of callbacks.
 */

static int lua2ffi_bool(struct argconv_t *ar)
{
    luaL_checktype(ar->L, ar->index, LUA_TBOOLEAN);
    ar->arg->l = (long) lua_toboolean(ar->L, ar->index);
    return 1;
}

// might be a number, or an ENUM or FLAGS.
static int lua2ffi_long(struct argconv_t *ar)
{
    if (ar->lua_type == LUA_TUSERDATA) {
	struct lg_enum_t *e = (struct lg_enum_t*)
	    luaL_checkudata(ar->L, ar->index, ENUM_META);
	ar->arg->l = e->value;
	return 1;
    }

    // If it's not userdata, must be something else useable as integer,
    // like number, or a string containing a number.
    ar->arg->l = (long) luaL_checkinteger(ar->L, ar->index);
    return 1;
}

/**
 * An unsigned char can be given as number (ASCII code), a boolean (0/1)
 * or as a string (first character is used).
 */
static int lua2ffi_uchar(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    switch (ar->lua_type) {
	case LUA_TNUMBER:
	    ar->arg->uc = (unsigned char) lua_tonumber(L, ar->index);
	    break;
	case LUA_TBOOLEAN:
	    ar->arg->uc = (unsigned char) lua_toboolean(L, ar->index);
	    break;
	case LUA_TSTRING:;
	    size_t len;
	    const char *s = lua_tolstring(L, ar->index, &len);
	    if (len > 0) {
		ar->arg->uc = (unsigned char) s[0];
		break;
	    }
	    return LG_ARGERROR(ar->func_arg_nr, 24,
		"An empty string can't be converted to character.");

	default:
	    return LG_ARGERROR(ar->func_arg_nr, 11, "Can't convert Lua type %s "
		"to char", lua_typename(L, ar->lua_type));
    }
    return 1;
}

/**
 * ENUMs can be represented by simple numbers, or by a userdata
 * that additionally contains the ENUM type, which can be used for
 * type checking.
 */
static int lua2ffi_enum(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    switch (ar->lua_type) {
	case LUA_TNUMBER:
	    ar->arg->l = (long) lua_tonumber(L, ar->index);

	    // for zero it is probably OK; like for gtk_table_attach, when
	    // xoptions should be zero.
	    if (ar->arg->l != 0) {
		LG_MESSAGE(13, "Arg %d enum (type %s) given as number\n",
		    ar->func_arg_nr, lg_get_type_name(ar->ts));
		call_info_msg(L, ar->ci, LUAGTK_WARNING);
	    }
	    return 1;
	
	case LUA_TUSERDATA:;
	    struct lg_enum_t *e = (struct lg_enum_t*) luaL_checkudata( L,
		ar->index, ENUM_META);
	    if (!lg_type_equal(L, ar->ts, e->ts)) {
		LG_MESSAGE(14, "Arg %d enum expects type %s, given %s\n",
		    ar->func_arg_nr,
		    lg_get_type_name(ar->ts),
		    lg_get_type_name(e->ts));
		call_info_msg(L, ar->ci, LUAGTK_WARNING);
	    }
	    ar->arg->l = e->value;
	    return 1;
    }

    return LG_ARGERROR(ar->func_arg_nr, 12, "Can't convert Lua type %s to enum",
	lua_typename(L, ar->lua_type));
}

static int lua2ffi_longlong(struct argconv_t *ar)
{
    ar->arg->ll = (long long) luaL_checknumber(ar->L, ar->index);
    return 1;
}

static int lua2ffi_double(struct argconv_t *ar)
{
    ar->arg->d = (double) luaL_checknumber(ar->L, ar->index);
    return 1;
}

static int lua2ffi_float(struct argconv_t *ar)
{
    ar->arg->f = (float) luaL_checknumber(ar->L, ar->index);
    return 1;
}

// XXX Might need to g_strdup() when returning a string to Gtk from a closure
// invocation.  The Lua string will be garbage collected eventually, but Gtk
// might continue to reference the string!
static int lua2ffi_char_ptr(struct argconv_t *ar)
{
    ar->arg->p = ar->lua_type == LUA_TNIL ? NULL
	: (void*) luaL_checkstring(ar->L, ar->index);
    return 1;
}

/**
 * Generic pointer - only NIL can be transported
 * XXX This function should eventually be replaced by specialized functions
 * for each pointer type, like "short*" etc.
 *
 * If required, various other Lua types could be converted: LUA_TUSERDATA,
 * LUA_TLIGHTUSERDATA, LUA_TSTRING, or even LUA_TFUNCTION?
 */
static int lua2ffi_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    if (ar->lua_type == LUA_TNIL) {
	ar->arg->p = NULL;
	return 1;
    }

    LG_MESSAGE(15, "Arg #%d type %s not supported, replaced by NULL\n",
	ar->func_arg_nr, FTYPE_NAME(ar->arg_type));
    call_info_msg(L, ar->ci, LUAGTK_WARNING);

    ar->arg->p = NULL;
    return 0;
}


/**
 * Handle pointers to structures/unions/objects/GValues.
 */
static int lua2ffi_struct_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    // The GValue is a special type of structure; it can hold almost any type
    // of value, therefore even numbers or strings can be converted to it.

    if (!strcmp(lg_get_type_name(ar->ts), "GValue")) {
	GValue gvalue = { 0 };
	GValue *p = lg_lua_to_gvalue(L, ar->index, &gvalue);

	if (p == &gvalue) {
	    // gvalue has been filled in, which is a local variable.  To
	    // preserve it until the library function has returned, allocate
	    // space and copy it there.  Also, mark it as output argument.
	    GValue *p2 = (GValue*) call_info_alloc_item(ar->ci, sizeof *p2);
	    memcpy(p2, p, sizeof(*p2));
	    struct call_arg *ca = &ar->ci->args[ar->func_arg_nr];
	    ca->is_output = 1;
	    ca->free_method = FREE_METHOD_GVALUE;
	    p = p2;
	}

	ar->arg->p = p;
	return 1;
    }

    switch (ar->lua_type) {

	// NIL is always ok
	case LUA_TNIL:
	    ar->arg->p = NULL;
	    return 1;

	// might be a object or a structure.
	case LUA_TUSERDATA:

	    if (!lua_getmetatable(L, ar->index)) {
		printf("%s object has no meta table.\n", msgprefix);
		return 0;
	    }

	    // The userdata's metatable should be of an object, in this case
	    // it has the field _typespec.  Other userdatas are not useful,
	    // like ENUMs.
	    // XXX gtk_clipboard_get expects a GdkAtom, which is represented
	    // by an ENUM...

	    lua_pushliteral(L, "_typespec");
	    lua_rawget(L, -2);
	    if (lua_isnil(L, -1)) {
		// might be an ENUM that could be used.
		lua_pop(L, 2);
		struct lg_enum_t *e = lg_get_constant(L, ar->index, ar->ts, 1);
		if (!e)
		    luaL_error(L, "%s arg #%d expects a %s, got some userdata",
			ar->ci->fi->name, ar->func_arg_nr,
			lg_get_type_name(ar->ts));

		// Determine the real indirections count.  It must be at least
		// one in order to use the constant as pointer.
		if (lg_get_type_indirections(e->ts) == 0)
		    luaL_error(L, "%s using a non-pointer constant of type %s "
			"for a struct* is not allowed", msgprefix,
			lg_get_type_name(ar->ts));

		ar->arg->p = (void*) e->value;
		return 1;
	    }

	    // The given object might be derived from the required type, which
	    // would be OK.  Check this.
	    typespec_t ts;
	    ts.value = lua_tonumber(L, -1);
	    const char *is_name = lg_get_type_name(ts);
	    // const char *is_name = lua_tostring(L, -1);
	    GType is_type = g_type_from_name(is_name);

	    const char *req_name = lg_get_type_name(ar->ts);
	    GType req_type = g_type_from_name(req_name);

	    if (is_type != req_type && !g_type_is_a(is_type, req_type)) {
		luaL_error(L, "%s arg #%d expects a %s, got %s\n",
		    ar->ci->fi->name, ar->func_arg_nr, req_name, is_name);
	    }
	    lua_pop(L, 2);

	    // all right.
	    struct object *w = (struct object*) lua_touserdata(L, ar->index);
	    ar->arg->p = w->p;
	    return 1;

	// other Lua types can't possibly be a structure pointer.
	default:
	    LG_ARGERROR(ar->func_arg_nr, 23, "%s requires %s, given %s",
		ar->ci->fi->name,
		lg_get_type_name(ar->ts),
		lua_typename(L, ar->lua_type));
    }

    return 0;
}


/**
 * A func* should be passed to a Gtk function.  Either a preallocated closure
 * (obtained by gnome.closure) or a regular Lua function can be used.
 *
 * For callbacks, the func* argument is often followed by a void* argument
 * which is passed to the callback.  This is already handled properly by
 * the void* wrapper, see voidptr.c.
 */
static int lua2ffi_func_ptr(struct argconv_t *ar)
{
    int index = ar->index;

    switch (ar->lua_type) {
	case LUA_TNIL:
	ar->arg->p = NULL;
	return 1;

	// If a function is given, and it actually is a closure for the
	// C function "lg_call_wrapper", then use the function that is
	// being pointed to directly.
	case LUA_TFUNCTION:
	if (lg_use_c_closure(ar))
	    return 1;
	
	// Not a C function, but a Lua function, or a non-library C function:
	// create a temporary closure.  It is added to the Lua stack
	// (stack_curr_top is incremented), so that it can't be garbage
	// collected until the library function is done.
	lg_create_closure(ar->L, ar->index, 1);
	ar->stack_curr_top ++;
	index = -1;
	// fall through
    }

    // userdata, or any other type - let lg_use_closure detect the error
    // if it's not a closure.
    ar->arg->p = lg_use_closure(ar->L, index, ar->ts, ar->func_arg_nr,
	ar->ci->fi->name);
    return 1;
}


/**
 * A "struct**" is most likely an output parameter, but may be out/in.
 * Allocate memory for a pointer, and set it to the given value, which may
 * be nil.  When collecting results, the output value will be used.
 *
 * @param ar  Array with a description of the argument to convert
 * @param type  0 for char**, 1 for struct**
 */
static int _ptr_ptr_helper(struct argconv_t *ar, int type)
{
    void *ptr = NULL;
    lua_State *L = ar->L;
    int is_output = 0;

    switch (ar->lua_type) {

	// what might that be good for?  Anyway only for struct**
	case LUA_TUSERDATA:
	    if (type == 1) {
		ptr = lua_touserdata(L, ar->index);
		break;
	    }
	    goto err;

	// this is most likely gnome.NIL
	case LUA_TLIGHTUSERDATA:
	    ptr = lua_touserdata(L, ar->index);
	    if (ptr == NULL)
		is_output = 1;
	    break;
	
	// use a NULL pointer
	case LUA_TNIL:
	    break;

	case LUA_TSTRING:
	    if (type == 0) {
		ptr = (void*) lua_tostring(L, ar->index);
		break;
	    }
	    /* fall through */
	
	err:
	default:
	    LG_ARGERROR(ar->func_arg_nr, 1, "Lua type %s can't be used for %s",
		lua_typename(L, ar->lua_type),
		type ? "struct**" : "char**"); 
    }

    void **p = (void**) call_info_alloc_item(ar->ci, sizeof(*p));
    *p = ptr;
    ar->arg->p = (void*) p;

    // set the arg_flag if this is an output argument.
    ar->ci->args[ar->func_arg_nr].is_output = ptr ? 1 : is_output;

    return 1;
}


static int lua2ffi_struct_ptr_ptr(struct argconv_t *ar)
{
    return _ptr_ptr_helper(ar, 1);
}


/*-
 * A char** argument should point to a memory location where a new char* can
 * be stored (output parameter).
 *
 * Exactly the same thing as a struct**.
 */
static int lua2ffi_char_ptr_ptr(struct argconv_t *ar)
{
    return _ptr_ptr_helper(ar, 0);
}


/**
 * A vararg is a table and should be converted to an array of string pointers.
 */
static void _lua2ffi_vararg_table_strings(struct argconv_t *ar)
{
    lua_State *L = ar->L;
    int items = lua_objlen(L, ar->index), i;
    int arg_nr = ar->func_arg_nr, type;
    struct call_info *ci = ar->ci;
    const char **a;
    struct call_arg *ca = &ci->args[arg_nr];

    /* allocate output array */
    ci->argtypes[arg_nr] = &ffi_type_pointer;
    a = (const char**) call_info_alloc_item(ci, sizeof(char*) * items);
    ca->ffi_arg.p = (void*) a;

    /* copy the values */
    for (i=0; i<items; i++) {
	lua_rawgeti(L, ar->index, i + 1);
	type = lua_type(L, -1);
	switch (type) {
	    case LUA_TSTRING:
	    a[i] = lua_tostring(L, -1);
	    break;

	    case LUA_TLIGHTUSERDATA:
	    a[i] = lua_touserdata(L, -1);    // works for gtk.NIL
	    break;

	    case LUA_TNUMBER:
	    break;

	}

	lua_pop(L, 1);
    }
}

static void _lua2ffi_vararg_table_boxed(struct argconv_t *ar)
{
    lua_State *L = ar->L;
    struct call_info *ci = ar->ci;
    struct call_arg *ca = &ci->args[ar->func_arg_nr];

    ci->argtypes[ar->func_arg_nr] = &ffi_type_pointer;
    // XXX this allocates some memory (a boxed value).  free?
    ca->ffi_arg.p = lg_make_boxed_value(L, ar->index);
    ca->free_method = FREE_METHOD_BOXED;
}

/**
 * A table is given as an argument for a vararg.  An optional "_type" field
 * tells what type the items should be; default is strings.
 *
 * Problem: somtimes the resulting array must be ended with a NULL pointer;
 * when you specify nil as the last item in a table it is simply discarded.
 * Use gtk.NIL instead of nil in this situation.
 */
static void _lua2ffi_vararg_table(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    /* determine the item type. */
    lua_pushliteral(L, "_type");
    lua_rawget(L, ar->index);
    if (!lua_isnil(L, -1)) {
	const char *type_str = lua_tostring(L, -1);
	if (!strcmp(type_str, "string"))
	    _lua2ffi_vararg_table_strings(ar);
	else if (!strcmp(type_str, "boxed"))
	    _lua2ffi_vararg_table_boxed(ar);
	else
	    luaL_error(L, "%s unknown type %s for vararg table conversion.",
		msgprefix, type_str);
	lua_pop(L, 1);
	return;
    }
    lua_pop(L, 1);

    /* No item type given. Make a boxed value. */
    printf("%s Warning: conversion of a table as vararg argument without "
	"_type field - default is boxed Lua value.\n", msgprefix);
    _lua2ffi_vararg_table_boxed(ar);
}

/**
 * Handle a vararg argument.  This must be the last argument for the function,
 * and collects all remaining given parameters (zero or more).
 *
 * This function must handle all Lua types and find an appropriate FFI type
 * for each of them.  The ci->argtypes must be set, too, for each argument.
 */
static int lua2ffi_vararg(struct argconv_t *ar)
{
    int stack_top = ar->stack_top, type, arg_nr = ar->func_arg_nr;
    struct call_info *ci = ar->ci;
    struct call_arg *ca;
    lua_State *L = ar->L;

    for (; ar->index <= stack_top; ar->index ++, arg_nr ++) {
	type = lua_type(L, ar->index);
	ca = &ci->args[arg_nr];
	ci->argvalues[arg_nr] = &ca->ffi_arg.l;
	ar->func_arg_nr = arg_nr;

	switch (type) {

	    case LUA_TBOOLEAN:
		ci->argtypes[arg_nr] = &ffi_type_uint;
		ca->ffi_arg.l = (long) lua_toboolean(L, ar->index);
		break;

	    case LUA_TNUMBER:;
		lua_Number val = lua_tonumber(L, ar->index);
		if (floor(val) == val) {
		    ci->argtypes[arg_nr] = &ffi_type_sint;
		    ca->ffi_arg.l = (long) val;
		} else {
		    ci->argtypes[arg_nr] = &ffi_type_double;
		    ca->ffi_arg.d = val;
		}
		break;

	    case LUA_TSTRING:
		ci->argtypes[arg_nr] = &ffi_type_pointer;
		ca->ffi_arg.p = (void*) lua_tostring(L, ar->index);
		break;

	    case LUA_TNIL:
		ci->argtypes[arg_nr] = &ffi_type_pointer;
		ca->ffi_arg.p = NULL;
		break;

	    case LUA_TLIGHTUSERDATA:
		ci->argtypes[arg_nr] = &ffi_type_pointer;
		ca->ffi_arg.p = (void*) lua_touserdata(L, ar->index);
		break;

	    // can be: enum, flags, object, boxed value
	    case LUA_TUSERDATA:
		ar->arg = &ca->ffi_arg;
		lg_userdata_to_ffi(ar, &ci->argtypes[arg_nr], 0);
		break;

	    // Array of strings, or a table to be converted to a boxed type
	    case LUA_TTABLE:
		_lua2ffi_vararg_table(ar);
		break;

	    default:
		LG_MESSAGE(16, "Arg %d: Unhandled vararg type %s\n", arg_nr+1,
		    lua_typename(L, type));
		call_info_msg(L, ci, LUAGTK_WARNING);
	    }
    }

    ar->func_arg_nr = arg_nr - 1;
    return 1;
}


/**
 * Store an integer of a given ffi_type at *p.
 * XXX might be an ENUM etc.
 * XXX the error message in case of type mismatch has a wrong argument
 * number.
 *
 * @param L  Lua State
 * @param p  Pointer to the destination; can be 4 or 8 bytes long
 * @param conv_idx  CONV_*INT_PTR to specify the type at *p
 * @param index  Where the number is on the Lua stack
 */
static void _store_int(lua_State *L, void *p, int conv_idx, int index)
{
    switch (conv_idx) {
	case CONV_INT_PTR:
	* (int*) p = luaL_checknumber(L, index);
	break;

	case CONV_UNSIGNED_INT_PTR:
	* (unsigned int*) p = luaL_checknumber(L, index);
	break;

	case CONV_LONG_UNSIGNED_INT_PTR:
	* (unsigned long int*) p = luaL_checknumber(L, index);
	break;

	case CONV_BOOL_PTR:
	luaL_checktype(L, index, LUA_TBOOLEAN);
	* (int*) p = lua_toboolean(L, index);
	break;

	default:
	luaL_error(L, "%s internal error; unhandled conv_idx %d in "
	    "_store_int", msgprefix, conv_idx);
    }
}

/**
 * Pointer to an integer - can be input or output.
 * This works for int, unsigned int, long int, unsigned long int.
 *
 * Input, e.g. for gdk_pango_layout_get_clip_region.  Use as such when an array
 * (of numbers) is given.
 * Output in other cases.  Initialize with whatever the user passed as
 * parameter.
 */
static int lua2ffi_int_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;
    int index = ar->index;
    int bytes = ar->arg_type->bit_len >> 3;
    int conv_idx = ar->arg_type->conv_idx;

    /* for a callback's output argument, copy the returned value */
    if (ar->mode == ARGCONV_CALLBACK) {
	luaL_checknumber(L, ar->index);
	* (int*) ar->arg->p = lua_tointeger(L, ar->index);
	return 1;
    }

    /* nil ... don't bother */
    if (ar->lua_type == LUA_TNIL) {
	ar->arg->p = NULL;
	return 1;
    }

    /* If no table is given, then this is an output value.  Allocate some
     * space for it, and set the pointer to it. */
    if (ar->lua_type != LUA_TTABLE) {
	ar->arg->p = call_info_alloc_item(ar->ci, bytes);
	_store_int(L, ar->arg->p, conv_idx, index);
	ar->ci->args[ar->func_arg_nr].is_output = 1;
	return 1;
    }

    /* otherwise, this is an input.  Allocate memory large enough for
     * all table items, and copy them. */
    int i, n;
    n = luaL_getn(L, index);
    char *a = (char*) call_info_alloc_item(ar->ci, bytes * n);
    ar->arg->p = (void*) a;

    for (i=0; i<n; i++) {
	lua_rawgeti(L, index, i+1);
	_store_int(L, (void*) a, conv_idx, -1);
	lua_pop(L, 1);
	a += bytes;
    }
    return 1;
}

/**
 * Array of doubles - as input
 */
static int lua2ffi_double_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;
    int index = ar->index;

    if (ar->mode == ARGCONV_CALLBACK)
	return 0;

    if (ar->lua_type == LUA_TNIL) {
	ar->arg->p = NULL;
	return 1;
    }

    /* input/output argument */
    if (ar->lua_type == LUA_TNUMBER) {
	double *a = (double*) call_info_alloc_item(ar->ci, sizeof(*a));
	*a = lua_tonumber(L, index);
	ar->arg->p = (void*) a;
	ar->ci->args[ar->func_arg_nr].is_output = 1;
	return 1;
    }


    /* A table should be given. */
    if (ar->lua_type != LUA_TTABLE)
	luaL_error(L, "%s table or nil expected for the double* argument.",
	    msgprefix);

    /* allocate an array */
    int n = luaL_getn(L, index), i;
    double *a = (double*) call_info_alloc_item(ar->ci, sizeof(*a) * n);

    for (i=0; i<n; i++) {
	lua_rawgeti(L, index, i + 1);
	a[i] = lua_tonumber(L, -1);
	lua_pop(L, 1);
    }

    ar->arg->p = (void*) a;
    return 1;
}

static int ffi2lua_double_ptr(struct argconv_t *ar)
{
    if (ar->ci->args[ar->func_arg_nr].is_output) {
	double *a = (double*) ar->arg->p;
	lua_pushnumber(ar->L, *a);
	return 1;
    }
    return 0;
}


/**
 * Array of ENUMs - as input
 */
static int lua2ffi_enum_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;
    int index = ar->index;

    switch (ar->lua_type) {
	case LUA_TNIL:
	    ar->arg->p = NULL;
	    return 1;
	
	// initialize with a number.  should be zero.
	case LUA_TNUMBER:
	    ar->arg->p = call_info_alloc_item(ar->ci, sizeof(int));
	    * (int*) ar->arg->p = lua_tonumber(L, index);
	    ar->ci->args[ar->func_arg_nr].is_output = 1;
	    return 1;
	
	// array of enums
	case LUA_TTABLE:;
	    int i, n, *a;
	    typespec_t ts;

	    n = luaL_getn(L, index);
	    a = (int*) call_info_alloc_item(ar->ci, sizeof(*a) * n);
	    ts = lg_type_modify(L, ar->ts, -1);

	    for (i=1; i<=n; i++) {
		lua_rawgeti(L, index, i);
		struct lg_enum_t *e = lg_get_constant(L, -1, ts, 0);
		if (!e)
		    luaL_error(L, "%s table element %d of arg %d is not "
			"an enum of type %s", msgprefix, i, ar->func_arg_nr,
			lg_get_type_name(ts));
		a[i - 1] = e->value;
		lua_pop(L, 1);
	    }

	    ar->arg->p = (void*) a;
	    return 1;

    }

    luaL_argerror(L, ar->func_arg_nr, "must be nil, number or table");
    return 0;
}

// enum** - can only be output, and must be a table to store the data into.
// the following argument must be int*, and is output too.
static int lua2ffi_enum_ptr_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    luaL_checktype(L, ar->index, LUA_TTABLE);
    int **a = (int**) call_info_alloc_item(ar->ci, sizeof(*a));
    ar->arg->p = (void*) a;
    ar->ci->args[ar->func_arg_nr].is_output = 1;

    // XXX check that next arg is int* -- can't.

    return 1;
}


/** ------- FFI2LUA FUNCTIONS -----
 * These functions take a ffi value and push it onto the Lua stack.  They are
 * required to convert return values from library calls back to Lua values.
 * Note that some "output arguments", like pointers to integers, are handled,
 * too.
 *
 * All of these functions return the number of arguments used; usually one, but
 * sometimes two.
 */

static int ffi2lua_void(struct argconv_t *ar)
{
    return 1;
}

static int ffi2lua_long(struct argconv_t *ar)
{
    lua_pushnumber(ar->L, ar->arg->l);
    return 1;
}

static int ffi2lua_longlong(struct argconv_t *ar)
{
    lua_pushnumber(ar->L, ar->arg->l);
    return 1;
}

static int ffi2lua_bool(struct argconv_t *ar)
{
    lua_pushboolean(ar->L, ar->arg->l);
    return 1;
}

static int ffi2lua_double(struct argconv_t *ar)
{
    lua_pushnumber(ar->L, ar->arg->d);
    return 1;
}

static int ffi2lua_enum(struct argconv_t *ar)
{
    return lg_push_constant(ar->L, ar->ts, ar->arg->l);
}

static int ffi2lua_uchar(struct argconv_t *ar)
{
    lua_pushlstring(ar->L, (char*) &ar->arg->uc, 1);
    return 1;
}


/**
 * A char* only is an output value if it is the actual function return value.
 * The string returned from the library function is freed unless it is a
 * "const char*".
 */
static int ffi2lua_char_ptr(struct argconv_t *ar)
{
    if (ar->func_arg_nr != 0)
	return 1;

    char *p = (char*) ar->arg->p;

    if (p) {
	lua_pushstring(ar->L, p);
	type_info_t ti = lg_get_type_info(ar->ts);
	if (!ti->st.is_const)
	    g_free(p);
    } else
	lua_pushnil(ar->L);

    return 1;
}


/**
 * Refcounting for GObject derived objects that are not Gtk objects is tricky.
 * These are returned by the creating function with a refcount of 1 but
 * not with a floating reference.  Therefore, g_object_ref_sink must not be
 * called.
 *
 * On the other hand, when an existing GObject derived object is returned by
 * a function, the refcount must be increased, because a new reference to it
 * is held and the refcount will be decreased upon GC of the Lua proxy object.
 *
 * It seems that functions that match the pattern gtk_*_get_ return existing
 * objects.  This is just a guess, I haven't verified them all, and maybe
 * there are others that also return existing objects but don't match this
 * naming pattern.  Currently 174 functions match this:
 * grep -c '^Gtk.*gtk_.*_get_' funclist-gtk
 *
 * Note that computing the flags in this way is only relevant when the Lua
 * proxy object doesn't exist yet, but that is determined later.  OTOH
 * lg_get_object doesn't know about the name of the function that returns
 * the object, so...
 */
static int _determine_flags(struct argconv_t *ar)
{
    // If arg flags are set, use it as-is.
    if (ar->arg_flags)
	return ar->arg_flags;

    // If this is a Gtk to Lua callback, all provided objects are not new.
    if (ar->mode == ARGCONV_CALLBACK)
	return FLAG_NOT_NEW_OBJECT;

    // This heuristic assumes that gtk_xxx_get_yyy functions return non-new
    // objects, so that their refcount needs to be increased.  This makes
    // no difference for GObject derived objects, as they have a floating
    // reference.  There are more than 150 functions matching this pattern,
    // and it would be cumbersome to tag each of them with an argument flag.

    const char *name = ar->ci->fi->name;

    if (!strncmp(name, "gtk_", 4) && strstr(name, "_get_")) {
	// printf("%p %s returns not new object???\n", ar->arg->p, name);
	return FLAG_NOT_NEW_OBJECT;
    }

    return FLAG_NEW_OBJECT;
}

static const char ok_names[] =
    "GdkGC\0"
    "GtkStyle\0"
    "GdkDisplay\0"
    "GFileEnumerator\0"
    "GFile\0"
;


/**
 * An object of type "ts" should be accessed; it might be a subclass of the
 * given type.  If the requested type is derived from GObject, the actual type
 * can be determined from the object.  In this case, set type_idx to 0, which
 * lets lg_get_object figure out the actual type of the object.
 *
 * @param p  Pointer to the object
 * @param ts  The type this object is supposed to have.
 * @return  If the object's supposed type is derived from GObject, and the
 *	actual type is known to lua-gtk, returns ts.type_idx=0, else it is
 *	returned unchanged.
 */
static typespec_t _guess_type_idx(lua_State *L, void *p, typespec_t ts)
{
    static GType go_type = 0;
    typespec_t zero = { 0 };
    zero.module_idx = ts.module_idx;

    // Type not given, or no object - do nothing.
    if (!ts.type_idx || !p)
	return ts;

    if (G_UNLIKELY(go_type == 0))
	go_type = g_type_from_name("GObject");

    // must be a native type; otherwise a type normalize would be in order.
    type_info_t ti = lg_get_type_info(ts);
    if (!ti || ti->st.genus == GENUS_NON_NATIVE)
	luaL_error(L, "%s _guess_type_idx called with non-native type %d.%d",
	    msgprefix, ts.module_idx, ts.type_idx);

    // Determine the name of the supposed type, and check whether it is derived
    // from GObject.  If not, return the given type_idx, as it can't be
    // determined automatically.
    const char *type_name = lg_get_type_name(ts);
    GType my_type = g_type_from_name(type_name);
    if (!my_type || !g_type_is_a(my_type, go_type))
	return ts;

    // The type must be known to LuaGnome; if not, automatically determining
    // the type probably will fail.  This applies e.g. to GLocalFile,
    // GDesktopAppInfo, which are types not known to lua-gtk, but are derived
    // directly from GObject instead of GFile and GAppInfo.
    my_type = G_TYPE_FROM_INSTANCE(p);
    type_name = g_type_name(my_type);

    typespec_t ts2 = lg_find_struct(L, type_name, 1);
    if (!ts2.value) {
	// If the specified type is GObject, then we can let it be determined
	// automatically.  For callbacks, this can be required, e.g. when
	// an existing GLocalFile (not in our list) is returned as GObject;
	// a GObject alias would be created for it.

	if (!strcmp(type_name, "GObject"))
	    return zero;

	// Types derived from the classes below are not known to LuaGnome,
	// but can be detected automatically.
	my_type = g_type_parent(my_type);
	if (my_type) {
	    const char *parent_name = g_type_name(my_type), *s;
	    for (s = ok_names; *s; s += strlen(s) + 1)
		if (!strcmp(parent_name, s))
		    return zero;
	}

	// known to need this, avoid the warning below.
	if (!strcmp(type_name, "GLocalFile"))
	    return ts;

	printf("no automatic type guessing for %s - keep %d.%d = %s\n",
	    type_name, ts.module_idx, ts.type_idx,
	    lg_get_type_name(ts));
	return ts;
    }

    // It is safe to automatically determine the type.
    return zero;
}

/**
 * Convert a structure pointer to a Lua value.
 */
static int ffi2lua_struct_ptr(struct argconv_t *ar)
{
    // return value of the function, or arguments to a callback?
    if (ar->mode == ARGCONV_CALLBACK || ar->func_arg_nr == 0) {
	/*
	if (ar->arg_flags)
	    printf("arg flags for ffi2lua_struct_ptr: %d\n", ar->arg_flags);
	*/
	lg_get_object(ar->L, ar->arg->p,
	    _guess_type_idx(ar->L, ar->arg->p, ar->ts), _determine_flags(ar));
	return 1;
    }

    // If a GValue should be converted, do that.  Note that the GValue needs
    // to be freed; this is handled in call.c:call_info_free.
    struct call_arg *ca = &ar->ci->args[ar->func_arg_nr];
    if (ca->free_method == FREE_METHOD_GVALUE) {
	GValue *gvalue = (GValue*) ar->arg->p;
	if (!gvalue)
	    lua_pushnil(ar->L);
	else
	    lg_gvalue_to_lua(ar->L, gvalue);
	return 1;
    }

    return 1;
}



// Get functions for output arguments; mark these specially?

// Sometimes arguments to a function can be used as OUTPUT values; push
// these to the Lua stack after they return.

// pointer to enum; might be output
static int ffi2lua_enum_ptr(struct argconv_t *ar)
{
    if (ar->arg->p) {
	int v = * (int*) ar->arg->p;
	lg_push_constant(ar->L, ar->ts, v);
    } else
	lua_pushnil(ar->L);
    return 1;
}

/**
 * Remove all entries of the given table.  Generally it would be easier to
 * just create a new table, but for tables given as arguments it is required
 * to write into them.
 */
void lg_empty_table(lua_State *L, int index)
{
    for (;;) {
	lua_pushnil(L);
	if (!lua_next(L, index))    // key, value (or nothing)
	    break;
	lua_pop(L, 1);		    // key
	lua_pushnil(L);		    // key, nil
	lua_rawset(L, index);	    // x
    }
}

/**
 * Handle enum** plus int* as output parameters.  This currently occurs only
 * in three API functions:
 *
 *  gdk_query_visual_types
 *  gtk_icon_set_get_sizes
 *  pango_tab_array_get_tabs -- requires an override, not handled here.
 *
 * The table given to the function call is filled with the result.
 */
static int ffi2lua_enum_ptr_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    luaL_checktype(L, ar->index, LUA_TTABLE);
    luaL_checktype(L, ar->index + 1, LUA_TNUMBER);

    int *a = * (int**) ar->arg->p;
    struct call_arg *arg2 = &ar->ci->args[ar->func_arg_nr + 1];
    int cnt = * (int*) arg2->ffi_arg.p;
    int i;

    // Remove another level of indirection.
    ar->ts = lg_type_modify(L, ar->ts, -1);

    lg_empty_table(L, ar->index);

    for (i=0; i<cnt; i++) {
	lg_push_constant(L, ar->ts, a[i]);
	lua_rawseti(L, ar->index, i + 1);
    }

    // the output array must sometimes be freed, sometimes not.
    const char *fname = ar->ci->fi->name;
    if (!strcmp(fname, "gtk_icon_set_get_sizes"))
	g_free(a);

    // used up two items
    return 2;
}


// generic pointer - try to make a object out of it.  It might also be a
// magic wrapper, though.
static int ffi2lua_void_ptr(struct argconv_t *ar)
{
    void *p = ar->arg->p;

    if (!p) {
	lua_pushnil(ar->L);
	return 1;
    }

    if (lg_is_vwrapper(ar->L, p))
	return lg_push_vwrapper_wrapper(ar->L, p);

    // is this a new object, or not??  guess not, new objects are not
    // returned this way; but existing objects may be given to callbacks.
    typespec_t ts = { 0 };
    lg_get_object(ar->L, ar->arg->p, ts, FLAG_NOT_NEW_OBJECT);
    if (!lua_isnil(ar->L, -1))
	return 1;

    // The return pointer wasn't nil, but get_object couldn't make
    // anything of it?
    if (ar->arg->p && runtime_flags & RUNTIME_WARN_RETURN_VALUE) {
	lua_State *L = ar->L;
	LG_MESSAGE(17, "Return value of arg %d (void*) discarded.\n",
	    ar->func_arg_nr);
	call_info_msg(L, ar->ci, LUAGTK_WARNING);
    }

    return 1;
}


/**
 * A int* type parameter can be an output parameter.  If so, push the returned
 * value onto the stack.  Note: the arg_flags for this parameter is set by
 * lua2ffi_int_ptr if a single integer was passed.
 */
static int ffi2lua_int_ptr(struct argconv_t *ar)
{
    if (ar->mode == ARGCONV_CALLBACK) {
	lua_pushnumber(ar->L, * (int*) ar->arg->p);
	ar->ci->args[ar->func_arg_nr].is_output = 1;
	return 1;
    }

    if (ar->func_arg_nr == 0)
	luaL_error(ar->L, "int* not supported as return value\n");

    if (ar->ci->args[ar->func_arg_nr].is_output)
	lua_pushnumber(ar->L, * (int*) ar->arg->p);

    return 1;
}

static int ffi2lua_unsigned_int_ptr(struct argconv_t *ar)
{
    if (ar->func_arg_nr == 0)
	luaL_error(ar->L, "unsigned int* not supported as return value\n");
    if (ar->ci->args[ar->func_arg_nr].is_output)
	lua_pushnumber(ar->L, * (unsigned int*) ar->arg->p);
    return 1;
}

static int ffi2lua_long_unsigned_int_ptr(struct argconv_t *ar)
{
    if (ar->func_arg_nr == 0)
	luaL_error(ar->L, "long_unsigned int* not supported as return value\n");
    if (ar->ci->args[ar->func_arg_nr].is_output)
	lua_pushnumber(ar->L, * (long unsigned int*) ar->arg->p);
    return 1;
}

/**
 * A Gtk function filled in a SomeStruct **p pointer.  Assume that this is a
 * regular object.
 *
 * XXX Some functions return an existing object, others create a new one,
 * and even others allocate a memory block and return that.  It seems that
 * there's no way to automatically figure out the right way.
 *
 * Returns an existing object:
 *  GtkTreeModel** (gtk_tree_selection_get_selected)
 *
 * Returns a new object:
 *
 * Returns a newly allocate memory block that must be freed:
 *  GError**, GdkRectangle**, PangoAttrList**
 *
 * Returns an existing memory block that must not be freed:
 */
static int ffi2lua_struct_ptr_ptr(struct argconv_t *ar)
{
    const char *name = lg_get_type_name(ar->ts);
    int flags = FLAG_NOT_NEW_OBJECT;

    if (!strcmp(name, "GError") || !strcmp(name, "GdkRectangle"))
	flags = FLAG_ALLOCATED | FLAG_NEW_OBJECT;

    else if (!strcmp(name, "PangoAttrList"))
	flags = FLAG_NEW_OBJECT;

    lg_get_object(ar->L, * (void**) ar->arg->p, ar->ts, flags);
    return 1;
}


/**
 * A char** argument was filled with a pointer to a newly allocated string.
 * Copy that to the Lua stack, then free the original string.
 */
static int ffi2lua_char_ptr_ptr(struct argconv_t *ar)
{
    char **s = (char**) ar->arg->p, **s2;
    int is_output = ar->ci->args[ar->func_arg_nr].is_output;

    // If the return value if a function is char**, then this is an array
    // of strings.
    int mult_ret = ar->func_arg_nr == 0;

    if (!s || !*s) {
	lua_pushnil(ar->L);
	return 1;
    }

    if (!mult_ret) {
	lua_pushstring(ar->L, *s);
    } else {
	printf("char** - multiple strings returned from %s\n",
	    ar->ci->fi->name);
	// array of char* returned - push all the strings.
	s2 = s;
	while (*s2) {
	    lua_pushstring(ar->L, *s2);
	    // XXX need to free the string at *s2?  maybe.
	    g_free(*s2);
	    s2++;
	}
    }

    // If the is_output was set by lua2ffi_char_ptr_ptr, then a NULL value was
    // passed, but now it it not NULL anymore -> most likely needs to be freed.
    if (is_output && !ar->arg_flags & FLAG_DONT_FREE) {
	printf("free char** retval %d of function %s\n",
	    ar->func_arg_nr, ar->ci->fi->name);
	g_free(*s);
    }

    return 1;
}


// ------ STRUCT2LUA ----------
// given a structure info and a pointer, extract the value from the structure
// and push it onto the Lua stack.

// for: bool, long, unsigned short int, ...
static int struct2lua_long(struct argconvs_t *ar)
{
    unsigned long v = 0;    // must initialize, because any number of bits
    // might be read and stored.
    get_bits_long(ar, (char*) &v);
    lua_pushnumber(ar->L, v);
    return 1;
}

static int struct2lua_double(struct argconvs_t *ar)
{
    double v = 0;
    get_bits_long(ar, (char*) &v);
    lua_pushnumber(ar->L, v);
    return 1;
}

// this is for a structure pointer
static int struct2lua_struct_ptr(struct argconvs_t *ar)
{
    void *p = 0;
    get_bits_long(ar, (char*) &p);
    lg_get_object(ar->L, p, _guess_type_idx(ar->L, p, ar->ts),
	FLAG_NOT_NEW_OBJECT);
    return 1;
}

// ptr must point directly to the structure.  It makes no sense to autodetect
// the type for derivations, because it can't be a derived (larger) struct.
static int struct2lua_struct(struct argconvs_t *ar)
{
    lg_get_object(ar->L, ar->ptr + ar->se->bit_offset/8, ar->ts,
	FLAG_NOT_NEW_OBJECT);
    return 1;
}

// strings
static int struct2lua_char_ptr(struct argconvs_t *ar)
{
    gchar **addr = (gchar**) (ar->ptr + ar->se->bit_offset/8);
    if (*addr)
	lua_pushstring(ar->L, *addr);
    else
	lua_pushnil(ar->L);
    return 1;
}

// generic pointer
static int struct2lua_ptr(struct argconvs_t *ar)
{
    void **addr = (void*) (ar->ptr + ar->se->bit_offset/8);
    if (addr) {
	printf("Warning: access to AT_POINTER address %p\n", *addr);
	lua_pushlightuserdata(ar->L, *addr);
    } else
	lua_pushnil(ar->L);
    return 1;
}

// enum or flags
static int struct2lua_enum(struct argconvs_t *ar)
{
    unsigned long v = 0;
    get_bits_long(ar, (char*) &v);
    lg_push_constant(ar->L, ar->ts, v);
    return 1;
}

#define UNTYPED_META "untyped"
struct lg_untyped {
    void *p;
};


/**
 * A void* pointer was returned by a Gtk function; cast it to the desired
 * type.
 *
 * @luaparam p  The void wrapper
 * @luaparam type  A string with the desired type's name
 * @luareturn  The requested object.
 */
static int untyped_cast(lua_State *L)
{
    struct lg_untyped *u = luaL_checkudata(L, 1, UNTYPED_META);
    const char *type_name = luaL_checkstring(L, 2);

    // some built in (non object) types
    if (!strcmp(type_name, "string")) {
	lua_pushstring(L, (char*) u->p);
	return 1;
    }

    // Look up the object name - find a pointer to it.
    typespec_t ts = lg_find_struct(L, type_name, 1);
    if (!ts.value)
	return luaL_error(L, "%s cast to unknown type %s", msgprefix,
	    type_name);

    lg_get_object(L, u->p, ts, FLAG_NOT_NEW_OBJECT);
    return 1;
}

static const luaL_reg untyped_methods[] = {
    { "cast", untyped_cast },
    { NULL, NULL }
};

/**
 * A void* pointer will be pushed onto the stack as a userdata with a metatable
 * that contains the function "cast".  This is similar to the void wrappers,
 * but simpler and does just enough to be usable.
 */
static int _push_untyped(lua_State *L, void *p)
{
    struct lg_untyped *u = (struct lg_untyped*) lua_newuserdata(L, sizeof(*u));
    u->p = p;

    // add a metatable with some methods
    if (luaL_newmetatable(L, UNTYPED_META)) {
	luaL_register(L, NULL, untyped_methods);
	lua_pushliteral(L, "__index");
	lua_pushvalue(L, -2);
	lua_rawset(L, -3);
    }

    lua_setmetatable(L, -2);
    return 1;
}

// a void* should be converted.
static int struct2lua_void_ptr(struct argconvs_t *ar)
{
    void *p = NULL;

    get_bits_long(ar, (char*) &p);

    // NULL pointer
    if (!p) {
	lua_pushnil(ar->L);
	return 1;
    }

    if (lg_is_vwrapper(ar->L, p))
	return lg_vwrapper_get(ar->L, p);

    return _push_untyped(ar->L, p);
}

/**
 * Handle reads of function pointers: return a closure for this function.
 */
static int struct2lua_func_ptr(struct argconvs_t *ar)
{
    struct func_info fi = { 0 };
    const unsigned char *sig;
    typespec_t ts = ar->ts;
    type_info_t ti = lg_get_type_info(ts);

    if (ti->fu.genus != GENUS_FUNCTION)
	return luaL_error(ar->L, "%s struct2lua_func_ptr on a non-function?",
	    msgprefix);

    get_bits_long(ar, (char*) &fi.func);
    fi.name = lg_get_struct_elem_name(ts.module_idx, ar->se);
    fi.module_idx = ts.module_idx;
    sig = lg_get_prototype(ts);
    fi.args_len = *sig;
    fi.args_info = sig + 1;

    return lg_push_closure(ar->L, &fi, 1);
}

// -------------------------------------------------------

static lua_Number _tonumber(lua_State *L, int index)
{
    switch (lua_type(L, index)) {
	case LUA_TNUMBER:
	    return lua_tonumber(L, index);
	
	case LUA_TBOOLEAN:
	    return lua_toboolean(L, index) ? 1 : 0;
	
	case LUA_TUSERDATA:;
	    struct lg_enum_t *e = LUAGTK_TO_ENUM(L, index);
	    return e->value;
    }

    return luaL_argerror(L, index, "can't convert to number");
}

/**
 * Write a number into a structure element
 */
static int lua2struct_long(struct argconvs_t *ar)
{
    unsigned long int v = _tonumber(ar->L, ar->index);
    set_bits(ar->ptr, ar->se->bit_offset, ar->se->bit_length, v);
    return 1;
}

static int lua2struct_double(struct argconvs_t *ar)
{
    double v = lua_tonumber(ar->L, ar->index);
    set_bits_long(ar->L, ar->ptr, ar->se->bit_offset, ar->se->bit_length,
	(char*) &v);
    return 1;
}

static int lua2struct_void_ptr(struct argconvs_t *ar)
{
    union gtk_arg_types dest;
    ffi_type *argtype;
    // XXX THIS DOES NOT WORK
    lg_userdata_to_ffi(ar, &argtype, 1);
    set_bits_long(ar->L, ar->ptr, ar->se->bit_offset, ar->se->bit_length,
	(char*) &dest.p);
    return 1;
}

/**
 * Write to a char* field in a structure.
 */
static int lua2struct_char_ptr(struct argconvs_t *ar)
{
    size_t len;
    const char *s = luaL_checklstring(ar->L, ar->index, &len);
    char *s2 = (char*) malloc(len + 1);
    memcpy(s2, s, len + 1);
    set_bits_long(ar->L, ar->ptr, ar->se->bit_offset, ar->se->bit_length,
	(char*) &s2);
    return 1;
}

static int lua2struct_enum(struct argconvs_t *ar)
{
    struct lg_enum_t *e = lg_get_constant(ar->L, ar->index, ar->ts, 1);
    set_bits(ar->ptr, ar->se->bit_offset, ar->se->bit_length, e->value);
    return 1;
}

int function_signature(lua_State *L, const struct func_info *fi, int align);

/**
 * Set a function pointer, most likely in an Iface structure.  At the given
 * index, a closure must be found (or NIL).  Note that on-the-fly generation of
 * closures doesn't make sense; it could be garbage collected anytime.
 */
static int lua2struct_func_ptr(struct argconvs_t *ar)
{
    lua_State *L = ar->L;
    void *code;
    typespec_t ts;
    int type = lua_type(L, ar->index);

    // setup ts for the structure element to be set.
    ts.module_idx = ar->ts.module_idx;
    ts.type_idx = ar->se->type_idx;

    switch (type) {
	case LUA_TNIL:
	code = NULL;
	break;

	// This might be a function wrapping a library function.  In this case,
	// the library function could be used directly, no?
	case LUA_TFUNCTION:
	if (!lua_iscfunction(L, ar->index))
	    return LG_ERROR(5, "Lua functions not allowed, use a closure.");

	// the signature of the function to use
	struct func_info *fi = lg_get_closure(L, ar->index);

	// the signature of the field to set
	struct func_info fi2;
	fi2.args_info = lg_get_prototype(ts);
	fi2.args_len = *fi2.args_info ++;
	fi2.module_idx = ts.module_idx;
	fi2.name = lg_get_struct_elem_name(ts.module_idx, ar->se);

	// check fi->args_info, fi->args_len against ar->se->type_idx
	function_signature(L, fi, 0);
	const char *s = lua_tostring(L, -1);

	function_signature(L, &fi2, 0);
	const char *s2 = lua_tostring(L, -1);

	if (fi->args_len != fi2.args_len
	    || memcmp(fi->args_info, fi2.args_info, fi->args_len))
	    return LG_ERROR(9, "Function signature mismatch: %s vs %s", s, s2);

	lua_pop(L, 2);

	code = fi->func;
	break;
	
	// might be a proper closure.
	case LUA_TUSERDATA:
	code = lg_use_closure(L, ar->index, ts, 0,
	    lg_get_struct_elem_name(ts.module_idx, ar->se));
	break;

	default:
	return LG_ERROR(6, "Invalid type %s for function pointer.",
	    lua_typename(L, type));
    }

    set_bits(ar->ptr, ar->se->bit_offset, ar->se->bit_length,
	(unsigned long int) code);
    return 1;
}


/*-
 * In order to keep each ffi_type_map entry (there are about 50 of them)
 * as small as possible (not larger than a cache line), instead of function
 * pointers there are just indices to these small pointer tables.
 *
 * The table for lua2ffi and ffi2lua have matching entries, just like
 * lua2struct and struct2lua have pairs.  Pointers may be NULL, though.
 * XXX disallow NULL, and replace with pointer to an error function.  This
 * allows skipping the checks for NULL in various places.
 */
const lua2ffi_t ffi_type_lua2ffi[] = {
    NULL,
    NULL,		    // LUA2FFI_VOID
    &lua2ffi_bool,
    &lua2ffi_long,
    &lua2ffi_longlong,
    &lua2ffi_enum,
    &lua2ffi_double,
    &lua2ffi_float,
    &lua2ffi_uchar,
    &lua2ffi_char_ptr,
    &lua2ffi_struct_ptr,
    &lua2ffi_int_ptr,
    &lua2ffi_int_ptr,	    // LUA2FFI_UNSIGNED_INT_PTR
    &lua2ffi_int_ptr,	    // LUA2FFI_LONG_UNSIGNED_INT_PTR
    &lua2ffi_void_ptr,
    &lua2ffi_struct_ptr_ptr,
    &lua2ffi_char_ptr_ptr,
    &lua2ffi_enum_ptr,
    &lua2ffi_int_ptr,	    // LUA2FFI_BOOL_PTR
    &lua2ffi_enum_ptr_ptr,
    &lua2ffi_ptr,
    &lua2ffi_vararg,
    &lua2ffi_func_ptr,
    &lua2ffi_double_ptr,
};

const ffi2lua_t ffi_type_ffi2lua[] = {
    NULL,
    &ffi2lua_void,
    &ffi2lua_bool,
    &ffi2lua_long,
    &ffi2lua_longlong,
    &ffi2lua_enum,
    &ffi2lua_double,
    &ffi2lua_double,	    // FFI2LUA_FLOAT
    &ffi2lua_uchar,
    &ffi2lua_char_ptr,
    &ffi2lua_struct_ptr,
    &ffi2lua_int_ptr,
    &ffi2lua_unsigned_int_ptr,
    &ffi2lua_long_unsigned_int_ptr,
    &ffi2lua_void_ptr,
    &ffi2lua_struct_ptr_ptr,
    &ffi2lua_char_ptr_ptr,
    &ffi2lua_enum_ptr,
    &ffi2lua_int_ptr,		// FFI2LUA_BOOL_PTR
    &ffi2lua_enum_ptr_ptr,
    NULL,			// FFI2LUA_PTR
    NULL,			// FFI2LUA_VARARG
    NULL,			// FFI2LUA_FUNC_PTR
    &ffi2lua_double_ptr,
};

const lua2struct_t ffi_type_lua2struct[] = {
    NULL,
    &lua2struct_long,
    &lua2struct_enum,
    &lua2struct_double,
    &lua2struct_void_ptr,
    &lua2struct_func_ptr,
    NULL,			// STRUCT_PTR
    NULL,			// STRUCT
    &lua2struct_char_ptr,	// CHAR_PTR
    NULL,			// PTR
};

const struct2lua_t ffi_type_struct2lua[] = {
    NULL,
    &struct2lua_long,
    &struct2lua_enum,
    &struct2lua_double,
    &struct2lua_void_ptr,
    &struct2lua_func_ptr,	// FUNC_PTR
    &struct2lua_struct_ptr,
    &struct2lua_struct,
    &struct2lua_char_ptr,
    &struct2lua_ptr,
};


#include "fundamentals.c"


