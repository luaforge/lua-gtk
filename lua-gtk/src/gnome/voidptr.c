/*- vim:sw=4:sts=4
 * Handle void* wrappers.
 * This is part of lua-gnome.
 *
 * Exported symbols:
 *   l_dump_vwrappers
 *   l_get_vwrapper_count
 *   lg_is_vwrapper
 *   lg_make_value_wrapper
 *   lg_push_vwrapper_wrapper
 *   lg_userdata_to_ffi
 */

#include "luagnome.h"
#include <string.h>	    // strcmp

#define LUAGNOME_WRAPPER "void* wrapper"
#define VALUE_WRAPPER_MAGIC1 0x89737948
#define VALUE_WRAPPER_MAGIC2 0xa0d7dfaa

struct value_wrapper {
    unsigned int magic1;
    unsigned int magic2;
    int ref;
    int refcount;			/* count Lua objects for this wrapper */
#ifdef LUAGNOME_DEBUG_FUNCS
    struct value_wrapper *prev, *next;	/* for debugging */
    int currentline;
    char *short_src;
#endif
};

#ifdef LUAGNOME_DEBUG_FUNCS
static struct value_wrapper *wrap_first = NULL;

/* Keep track of how many wrappers exist.  Use this to catch leaks. */
static int vwrapper_count = 0,	    /* number of currently existant wrappers */
    vwrapper_total_count = 0,	    /* total allocations so far */
    vwrapper_objects = 0;	    /* Lua wrappers for void* wrappers */


int lg_dump_vwrappers(lua_State *L)
{
    struct value_wrapper *w;
    printf("%s void* wrappers: current=%d, total=%d, Lua objects=%d\n",
	msgprefix, vwrapper_count, vwrapper_total_count, vwrapper_objects);

    for (w=wrap_first; w; w=w->next)
	printf("> %p refcnt=%d %s:%d\n", w, w->refcount, w->short_src,
	    w->currentline);
    return 0;
}

int lg_get_vwrapper_count(lua_State *L)
{
    lua_pushinteger(L, vwrapper_count);
    lua_pushinteger(L, vwrapper_total_count);
    lua_pushinteger(L, vwrapper_objects);
    return 3;
}
#else
int lg_dump_vwrappers(lua_State *L)
{
    printf("dump_vwrappers: compiled without debug functions.\n");
    return 0;
}

int lg_get_vwrapper_count(lua_State *L)
{
    printf("get_vwappers_count: compiled without debug functions.\n");
    return 0;
}
#endif

/* content of a userdata that wraps the wrapper... duh. */
struct _value_wrapper2 {
    struct value_wrapper *wrapper;
};


/**
 * Determine whether the void* points to a value wrapper; it relies on
 * a "magic" signature, which might give false positives in pathological
 * cases.
 */
int lg_is_vwrapper(lua_State *L, void *p)
{
    struct value_wrapper *wrp = (struct value_wrapper*) p;
    if (wrp->magic1 != VALUE_WRAPPER_MAGIC1
	|| wrp->magic2 != VALUE_WRAPPER_MAGIC2)
	return 0;

    if (wrp->refcount <= 0 || wrp->ref == 0)
	return luaL_error(L, "%s accessing invalid void* wrapper at %p",
	    msgprefix, wrp);
    
    return 1;
}


/**
 * Push the Lua object wrapped by the given value_wrapper onto the stack.
 */
int lg_vwrapper_get(lua_State *L, struct value_wrapper *wrp)
{
    lua_rawgeti(L, LUA_REGISTRYINDEX, wrp->ref);
    return 1;
}


/**
 * Try to convert a Userdata to a pointer.
 *
 * @param ar  Structure with L, index, output address
 * @param argtype  FFI type to use for the argument, most likely pointer.
 * @param only_ptr  Only accept a pointer type; otherwise, ENUM (integer) is OK
 */
void lg_userdata_to_ffi(struct argconv_t *ar, ffi_type **argtype,
    int only_ptr)
{
    lua_State *L = ar->L;
    int index = ar->index;
    union gtk_arg_types *dest = ar->arg;

    void *p = (void*) lua_touserdata(L, index);

    // NULL pointer or no metatable - pass pointer as is
    if (p == NULL || !lua_getmetatable(L, index)) {
	printf("%s Warning: converting userdata without metatable to pointer\n",
	    msgprefix);
	dest->p = p;
	*argtype = &ffi_type_pointer;
	return;
    }
    // stack: metatable

    // is this an enum/flag?
    // XXX this meta might not be initialized yet
    lua_getfield(L, LUA_REGISTRYINDEX, ENUM_META);
    if (lua_rawequal(L, -1, -2)) {
	if (only_ptr)
	    luaL_error(L, "ENUM given for a pointer parameter\n");
	dest->l = ((struct lg_enum_t*)p)->value;
	*argtype = &ffi_type_uint;
	lua_pop(L, 2);
	return;
    }
    lua_pop(L, 1);

    // Is this a value wrapper wrapper?  If so, pass the wrapper.
    lua_getfield(L, LUA_REGISTRYINDEX, LUAGNOME_WRAPPER);
    if (lua_rawequal(L, -1, -2)) {
	struct _value_wrapper2 *wrp = (struct _value_wrapper2*) p;
	dest->p = wrp->wrapper;
	*argtype = &ffi_type_pointer;
	lua_pop(L, 2);
	return;
    }
    lua_pop(L, 1);

    // Is is a boxed value?
    lua_getfield(L, LUA_REGISTRYINDEX, "LuaValue");
    if (lua_rawequal(L, -1, -2)) {	// stack: value LuaValue LuaValue
	lua_pop(L, 2);
	return lg_boxed_to_ffi(ar, argtype);
    }
    lua_pop(L, 1);

    // is this an object? if so, pass its address
    lua_getfield(L, -1, "_typespec");
    // stack: metatable, _typespec/nil
    if (!lua_isnil(L, -1)) {
	// this is an object - pass the pointer
	dest->p = ((struct object*)p)->p;
	*argtype = &ffi_type_pointer;
	lua_pop(L, 2);
	return;
    }
    lua_pop(L, 2);

    // this is something else...
    printf("%s Warning: converting unknown userdata to pointer\n", msgprefix);
    dest->p = p;
    *argtype = &ffi_type_pointer;
}


/**
 * Garbage collection of a Lua wrapper.  Free the referenced C wrapper if
 * its refcount now drops to zero.
 */
static int wrapper_gc(lua_State *L)
{
    struct _value_wrapper2 *a = (struct _value_wrapper2*) lua_touserdata(L, 1);
    struct value_wrapper *wrp = a->wrapper;

#ifdef LUAGNOME_DEBUG_FUNCS
    vwrapper_objects --;
#endif
    if (wrp->refcount <= 0) {
	// if this happens, something strange is going on.
	printf("%s ERROR: wrapper_gc: refcount of void* wrapper at %p is %d\n",
	    msgprefix, wrp, wrp->refcount);
	return 0;
    }
    if (--wrp->refcount == 0) {
	luaL_unref(L, LUA_REGISTRYINDEX, wrp->ref);
	wrp->ref = 0;
	// wrp->magic1 = 0;
	// wrp->magic2 = 0;
#ifdef LUAGNOME_DEBUG_FUNCS
	if (wrp->prev)
	    wrp->prev->next = wrp->next;
	if (wrp->next)
	    wrp->next->prev = wrp->prev;
	if (wrap_first == wrp)
	    wrap_first = wrp->next;
	if (wrp->short_src)
	    g_free(wrp->short_src);
	vwrapper_count --;
#endif
	g_free(wrp);
    }
    a->wrapper = NULL;
    return 0;
}


/**
 * The :destroy method decreases the refcount by one, if it is > 1.  It must
 * not be set to 0, because the userdata object will be garbage collected
 * eventually, and then the refcount is decreased again.
 */
static int wrapper_destroy(lua_State *L)
{
    struct _value_wrapper2 *a = (struct _value_wrapper2*) lua_touserdata(L, 1);
    if (!lg_is_vwrapper(L, a->wrapper))
	return luaL_error(L, "%s wrapper_destroy: invalid wrapper at %p",
	    msgprefix, a->wrapper);
    a->wrapper->refcount --;
    return 0;
}


/**
 * Access to a wrapper's fields - value or destroy().  __index in the metatable
 * points to this function instead of itself, because in case of value, a
 * function must be called.
 */
static int wrapper_index(lua_State *L)
{
    const struct _value_wrapper2 *a = lua_touserdata(L, 1);
    if (!lg_is_vwrapper(L, a->wrapper))
	luaL_error(L, "%s wrapper_index: invalid wrapper at %p",
	    msgprefix, a->wrapper);
    lua_rawgeti(L, LUA_REGISTRYINDEX, a->wrapper->ref);

    // special index "value" and "destroy"
    if (lua_type(L, 2) == LUA_TSTRING) {
	const char *key = lua_tostring(L, 2);
	if (!strcmp(key, "value"))
	    return 1;
	if (!strcmp(key, "destroy")) {
	    lua_pushcfunction(L, wrapper_destroy);
	    return 1;
	}
    }

    // any other index - use to look into the wrapped object, which must
    // be a table or metadata.
    lua_replace(L, 1);
    lua_gettable(L, 1);
    return 1;
}


/**
 * Call settable on the wrapped Lua value
 * Lua stack: [void* wrapper] key value
 */
static int wrapper_newindex(lua_State *L)
{
    const struct _value_wrapper2 *a = lua_touserdata(L, 1);
    lua_rawgeti(L, LUA_REGISTRYINDEX, a->wrapper->ref);
    lua_replace(L, 1);
    lua_settable(L, 1);
    return 0;
}


/**
 * Retrieve the length of the wrapped Lua value.
 */
static int wrapper_len(lua_State *L)
{
    const struct _value_wrapper2 *a = lua_touserdata(L, 1);
    lua_rawgeti(L, LUA_REGISTRYINDEX, a->wrapper->ref);
    lua_pushinteger(L, lua_objlen(L, -1));
    return 1;
}


/**
 * Debug function: show the wrapper's address and content.
 */
static int wrapper_tostring(lua_State *L)
{
    const struct _value_wrapper2 *a = lua_touserdata(L, 1);
    lua_pushfstring(L, "[void* wrapper at %p: ", a->wrapper);
    lua_getglobal(L, "tostring");
    lua_rawgeti(L, LUA_REGISTRYINDEX, a->wrapper->ref);
    lua_call(L, 1, 1);
    lua_pushliteral(L, ", refcount=");
    lua_pushnumber(L, a->wrapper->refcount);
    lua_pushliteral(L, "]");
    lua_concat(L, 5);
    return 1;
}


static const luaL_reg wrapper_methods[] = {
    { "__index", wrapper_index },
    { "__newindex", wrapper_newindex },
    { "__len", wrapper_len },
    { "__gc", wrapper_gc },
    { "__tostring", wrapper_tostring },
    { NULL, NULL }
};


/**
 * A value should be passed to a Gtk function as void*.  This is most likely
 * a "data" argument that will be given to a callback, or a value in a
 * collection class like a tree etc.  Allocate a C structure and put a 
 * reference to that value into it.
 *
 * Note: This wrapper is initialized with a refcount of 0.  This function
 * is either called by gtk.void_ptr(), which immediately creates a Lua
 * wrapper for it, or by lua2ffi_void_ptr.  In the latter case, refcount
 * is set to 1 nevertheless, so the user must call the :destroy() method
 * on it eventually.
 */
struct value_wrapper *lg_make_value_wrapper(lua_State *L, int index)
{
    lua_pushvalue(L, index);
    struct value_wrapper *wrp = (struct value_wrapper*) g_malloc(sizeof(*wrp));

#ifdef LUAGNOME_DEBUG_FUNCS
    wrp->next = wrap_first;
    wrp->prev = NULL;
    if (wrap_first)
	wrap_first->prev = wrp;
    wrap_first = wrp;

    lua_Debug ar;
    wrp->currentline = -1;
    wrp->short_src = NULL;
    if (lua_getstack(L, 1, &ar)) {
	if (lua_getinfo(L, "Sl", &ar)) {
	    wrp->short_src = g_strdup(ar.short_src);
	    wrp->currentline = ar.currentline;
#if 0
	    printf("%s(%d): new vwrapper at %p\n", ar.short_src, ar.currentline,
		wrp);
#endif
	}
    }
    vwrapper_count ++;
    vwrapper_total_count ++;
#endif

    wrp->magic1 = VALUE_WRAPPER_MAGIC1;
    wrp->magic2 = VALUE_WRAPPER_MAGIC2;
    wrp->ref = luaL_ref(L, LUA_REGISTRYINDEX);
    wrp->refcount = 0;
    return wrp;
}


/**
 * Make a Lua wrapper for the C wrapper for the Lua value.
 */
int lg_push_vwrapper_wrapper(lua_State *L, struct value_wrapper *wrp)
{
    struct _value_wrapper2 *p = lua_newuserdata(L, sizeof(*p));
    p->wrapper = wrp;
    wrp->refcount ++;
#ifdef LUAGNOME_DEBUG_FUNCS
    vwrapper_objects ++;
#endif

    // add a metatable with some methods
    if (luaL_newmetatable(L, LUAGNOME_WRAPPER))
	luaL_register(L, NULL, wrapper_methods);

    lua_setmetatable(L, -2);
    return 1;
} 


/**
 * The C function expects a void* pointer.  Any datatype should be permissible;
 * nil and lightuserdata are easy; userdata may be ENUM or contain an object.
 * For other data types, a reference is created, which is then wrapped in a
 * small memory block with a "magic" signature.  This signature will then be
 * recognized in ffi2lua_void_ptr.
 *
 * The problem is that it's unknown how long this value is required.  The C
 * function might store it somewhere (e.g. g_tree_insert key and value) or not
 * (e.g. g_tree_foreach user_data), so it can't be freed automatically.
 */
int lua2ffi_void_ptr(struct argconv_t *ar)
{
    lua_State *L = ar->L;

    switch (ar->lua_type) {
	case LUA_TNIL:
	    ar->arg->p = NULL;
	    break;
	
	case LUA_TLIGHTUSERDATA:
	    ar->arg->p = (void*) lua_touserdata(L, ar->index);
	    break;
	
	case LUA_TUSERDATA:;
	    ffi_type *argtype;
	    lg_userdata_to_ffi(ar, &argtype, 1); // L, ar->index, ar->arg, &argtype, 1);
	    break;
	
	default:;
	    struct value_wrapper *w = lg_make_value_wrapper(ar->L, ar->index);
	    /* this reference isn't owned...  leak unless :destroy is called */
	    w->refcount ++;
	    ar->arg->p = w;
    }

    return 1;
}

