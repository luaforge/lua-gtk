/* vim:sw=4:sts=4
 *
 * Handle boxed values, i.e. a new type registered with glib's type system
 * that can hold an arbitrary Lua value.  This is useful e.g. to store
 * Lua values in a GtkListStore.
 *
 * Exported symbols:
 *  lg_boxed_value_type
 *  lg_make_boxed_value
 *  lg_get_boxed_value
 *  lg_boxed_to_ffi
 *  lg_boxed_free
 *  lg_init_boxed
 *
 * New functions:
 *  gnome.box
 *  gnome.box_debug
 */

#include "luagnome.h"
#include "lg_ffi.h"
#include <string.h>	    // strcmp
#define LUAGNOME_BOXED "LuaValue"

int lg_boxed_value_type = 0;
static int boxed_count = 0; // count currently allocated boxed objects

// To wrap a Lua value, it will be stored using the reference mechanism.
struct boxed_lua_value {
    int	ref;		    // reference in the registry
    lua_State *L;	    // the Lua State the registry belongs to
    typespec_t ts;	    // if nonzero, specifies which type to cast to
    int	is_userdata : 1;    // if set, allocated via lua_newuserdata
};



static void _fill_boxed_value(lua_State *L, struct boxed_lua_value *b,
    int index)
{
    b->L = L;
    lua_pushvalue(L, index);
    b->ref = luaL_ref(L, LUA_REGISTRYINDEX);
}


/**
 * Access the object stored in the boxed value.  The type casting
 * for objects is not really useful, is it?
 *
 * If the Lua value is a table or a userdata, try to access its fields.
 *
 * @luaparam box  The boxed value (a userdata)
 * @luaparam key  The key to access in b
 */
static int l_boxed_index(lua_State *L)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_touserdata(L, 1);
    lua_State *bL = b->L;
    int btop = lua_gettop(bL);
    int key_type = lua_type(L, 2);

    // get the Lua object onto the stack
    lua_rawgeti(bL, LUA_REGISTRYINDEX, b->ref);		// box key object

    // if it is a string, check for the field "value".
    if (key_type == LUA_TSTRING) {
	const char *key = lua_tostring(L, 2);

	if (!strcmp(key, "value")) {
	    // no type cast added - simply return the value.
	    if (!b->ts.value)
		return 1;

	    // for this to work, the Lua value must be an object.
	    struct object *w = lg_check_object(L, -1);
	    if (!w)
		return luaL_error(L, "%s %s doesn't contain a object, cast "
		    "impossible.", msgprefix, LUAGNOME_BOXED);

	    const char *type_name = lg_get_type_name(b->ts);
	    typespec_t ts = lg_find_struct(L, type_name, 1);
	    lg_get_object(L, w->p, ts, FLAG_NOT_NEW_OBJECT);
	    return 1;
	}
    }

    // for all other keys, try to access fields of the wrapped object
    // if it is a table, access its fields
    lua_insert(bL, 2);		    // Stack: box object key
    lua_gettable(L, -2);	    // Stack: box value
    if (bL != L) {
	lua_xmove(bL, L, 1);
	lua_settop(bL, btop);
    }
    return 1;
}


// pretty printing
static int l_boxed_tostring(lua_State *L)
{
    lua_pushfstring(L, LUAGNOME_BOXED " at %p", lua_topointer(L, 1));
    return 1;
}

/**
 * Write into a field of the Boxed value, which works only if that value is
 * a table or a userdata with an appropriate metamethod.
 *
 * Input stack: box - key - value
 */
static int l_boxed_newindex(lua_State *L)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_touserdata(L, 1);
    lua_State *bL = b->L;

    if (bL != L)
	luaL_error(L, "%s l_boxed_newindex cannot handle multiple stacks.",
	    msgprefix);
	
    lua_rawgeti(L, LUA_REGISTRYINDEX, b->ref);	    // box key value object
    lua_insert(L, 2);				    // box object key value
    lua_settable(L, 2);
    return 0;
}

static int l_boxed_gc(lua_State *L)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_touserdata(L, 1);
    if (b->ref)
	luaL_unref(b->L, LUA_REGISTRYINDEX, b->ref);
    boxed_count --;
    return 0;
}

static const luaL_reg boxed_methods[] = {
    { "__index",    l_boxed_index },
    { "__tostring", l_boxed_tostring },
    { "__newindex", l_boxed_newindex },
    { "__gc",	    l_boxed_gc },
    { NULL,	    NULL }
};


/**
 * GObject wants to copy a boxed value.  We now need another reference for the
 * Lua value.
 */
static gpointer _boxed_copy(gpointer val)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) val, *b2;

    b2 = g_slice_new(struct boxed_lua_value);
    memcpy(b2, b, sizeof(*b2));
    lua_rawgeti(b2->L, LUA_REGISTRYINDEX, b2->ref);
    b2->ref = luaL_ref(b2->L, LUA_REGISTRYINDEX);
    b2->is_userdata = 0;
    boxed_count ++;
    return (gpointer) b2;
}


/**
 * When GObject wants to free a boxed value, unreference the Lua value
 * associated with it, and release the memory.
 *
 * Note: should the boxed value have been allocated by lua_newuserdata, then
 * it can't be freed this way, obviously.  An error message is printed instead.
 */
void lg_boxed_free(gpointer val)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) val;
    luaL_unref(b->L, LUA_REGISTRYINDEX, b->ref);
    boxed_count --;
    if (b->is_userdata)
	fprintf(stderr, "%s Error: a GBoxed value freed by GObject, but it "
	    "was allocated by Lua!\n", msgprefix);
    else
	g_slice_free(struct boxed_lua_value, val);
}




/**
 * Create a boxed value for a Lua value, and return that pointer.  Note that
 * the caller needs to take care of this allocated region.
 */
void *lg_make_boxed_value(lua_State *L, int index)
{
    int type = lua_type(L, index);

    if (type == LUA_TNIL)
	return NULL;

    // that stack position might already be a boxed value?  If so, copy it,
    // don't just return it - it will be freed.
    if (type == LUA_TUSERDATA) {
	lua_getmetatable(L, index);
	luaL_getmetatable(L, LUAGNOME_BOXED);
	int rc = lua_rawequal(L, -1, -2);
	lua_pop(L, 2);
	if (rc)
	    return _boxed_copy(lua_touserdata(L, index));
    }

    // this is not a boxed value.  create a new one.
    struct boxed_lua_value *b = g_slice_new(struct boxed_lua_value);
    _fill_boxed_value(L, b, index);
    boxed_count ++;
    b->ts.value = 0;
    b->is_userdata = 0;
    return b;
}


/**
 * Sometimes an automatic boxing of Lua values is not possible.  In this case,
 * the user can explicitely box a value.  You can also provide a type name
 * to typecast the value to.
 *
 * @luaparam value  A value to box
 * @luaparam type  (optional) a string describing the type you want to cast
 *   the value to.
 * @return  The boxed value
 */
static int l_box(lua_State *L)
{
    luaL_checkany(L, 1);
    const char *type_name = luaL_optstring(L, 2, NULL);
    typespec_t ts = { 0 };

    if (type_name)
	ts = lg_get_type(L, type_name);
    
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_newuserdata(L,
	sizeof(*b));
    _fill_boxed_value(L, b, 1);
    boxed_count ++;
    b->is_userdata = 1;
    b->ts = ts;

    if (luaL_newmetatable(L, LUAGNOME_BOXED))
	luaL_register(L, NULL, boxed_methods);
    lua_setmetatable(L, -2);

    return 1;
}


/**
 * Push the Lua value wrapped in the LuaValue box onto the Lua stack.
 *
 * @param L  Lua State
 * @param p  Pointer to the boxed value
 * @return  1, and the Lua value on the Lua stack
 */
int lg_get_boxed_value(lua_State *L, const void *p)
{
    if (!p) {
	lua_pushnil(L);
	return 1;
    }
    const struct boxed_lua_value *b = (const struct boxed_lua_value*) p;
    lua_rawgeti(b->L, LUA_REGISTRYINDEX, b->ref);
    if (L != b->L)
	lua_xmove(b->L, L, 1);
    return 1;
}


/**
 * A boxed value should now be used to fill a gtk_arg_types.
 */
void lg_boxed_to_ffi(struct argconv_t *ar, ffi_type **argtype)
{
    lua_State *L = ar->L;

    struct boxed_lua_value *b = (struct boxed_lua_value*)
	lua_touserdata(L, ar->index);

    // a box without a typespec set; it can be used when a boxed value is
    // expected.
    if (!b->ts.value) {
	ar->arg->p = b;
	*argtype = &ffi_type_pointer;
	return;
    }

    // Otherwise, cast to the requested type by calling the appropriate
    // lua2ffi conversion function.
    lua_pushvalue(L, ar->index);		// save the boxed value
    lua_rawgeti(L, LUA_REGISTRYINDEX, b->ref);
    lua_replace(L, ar->index);

    ar->ts = b->ts;
    ar->mi = modules[ar->ts.module_idx];
    ar->arg_type = lg_get_ffi_type(ar->ts);
    ar->lua_type = lua_type(L, ar->index);

    int idx = ar->arg_type->ffi_type_idx;
    *argtype = LUAGNOME_FFI_TYPE(idx);

    idx = ar->arg_type->conv_idx;
    if (!idx || !ffi_type_lua2ffi[idx])
	luaL_error(L, "%s unhandled type %s in boxed_to_ffi",
	    msgprefix, lg_get_type_name(b->ts));

    ffi_type_lua2ffi[idx](ar);

    lua_replace(L, ar->index);		    // put boxed value back
}


/**
 * Return the number of currently allocated boxed objects.
 */
static int l_box_debug(lua_State *L)
{
    lua_pushinteger(L, boxed_count);
    return 1;
}

static const luaL_reg gnome_methods[] = {
    {"box",		    l_box },
    {"box_debug",	    l_box_debug },
    { NULL, NULL }
};

/**
 * Initialize this module.
 *
 * @luaparam gnome  The "gnome" table
 */
void lg_init_boxed(lua_State *L)
{
    lg_boxed_value_type = g_boxed_type_register_static("LuaValue",
	_boxed_copy, lg_boxed_free);

    luaL_register(L, NULL, gnome_methods);

    // required: if you want a TreeStore or similar to hold such boxed values,
    // use gnome.boxed_type.
    lua_pushinteger(L, lg_boxed_value_type);
    lua_setfield(L, -2, "boxed_type");
}

