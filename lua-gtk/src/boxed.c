/* vim:sw=4:sts=4
 *
 * Handle boxed values, i.e. a new type registered with glib's type system
 * that can hold an arbitrary Lua value.  This is useful e.g. to store
 * Lua values in a GtkListStore.
 *
 * Exported symbols:
 *
 *  luagtk_boxed_value_type
 *  luagtk_make_boxed_value
 *  luagtk_get_boxed_value
 *  luagtk_init_boxed
 *  luagtk_boxed_register
 *
 * New functions:
 *  gtk.make_boxed_value
 *  gtk.get_boxed_value
 */

#include "luagtk.h"
#include <lauxlib.h>
#include <string.h>	    // strcmp
#define LUAGTK_BOXED "LuaValue"

int luagtk_boxed_value_type = 0;

// To wrap a Lua value, it will be stored using the reference mechanism.
struct boxed_lua_value {
    int	ref;		    // reference in the registry
    lua_State *L;	    // the Lua State the registry belongs to
    GType type;		    // if nonzero, specifies which type to cast to
};


static void _fill_boxed_value(lua_State *L, struct boxed_lua_value *b,
    int index)
{
    b->L = L;
    lua_pushvalue(L, index);
    b->ref = luaL_ref(L, LUA_REGISTRYINDEX);
    b->type = 0;
}

/**
 * Experiment - access the object stored in the boxed value.  The type casting
 * for widgets is not really useful, is it?
 */
static int l_boxed_index(lua_State *L)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_topointer(L, 1);
    const char *key = lua_tostring(L, 2);
    if (!strcmp(key, "value")) {
	lua_rawgeti(b->L, LUA_REGISTRYINDEX, b->ref);

	// no type cast added - simply return the value.
	if (!b->type)
	    return 1;

	// for this to work, the Lua value must be a widget.
	struct widget *w = luagtk_check_widget(L, -1);
	if (!w)
	    return luaL_error(L, "%s %s is not a widget, cast impossible.",
		msgprefix, LUAGTK_BOXED);

	GTK_INITIALIZE();
	const char *type_name = g_type_name(b->type);
	const struct type_info *ti = find_struct(type_name, 1);
	luagtk_get_widget(L, w->p, ti - type_list, 0);
	return 1;
    }
    return 0;
}

// pretty printing
static int l_boxed_tostring(lua_State *L)
{
    lua_pushfstring(L, LUAGTK_BOXED " at %p", lua_topointer(L, 1));
    return 1;
}

static const luaL_reg boxed_methods[] = {
    { "__index",    l_boxed_index },
    { "__tostring", l_boxed_tostring },
    { NULL,	    NULL }
};

// On the top of the stack is the new userdata.  Set an appropriate metatable
static void _set_boxed_metatable(lua_State *L)
{
    if (luaL_newmetatable(L, LUAGTK_BOXED))
	luaL_register(L, NULL, boxed_methods);
    lua_setmetatable(L, -2);
}

/**
 * Create a boxed value for a Lua value, and return that pointer.  Note that
 * the caller needs to take care of this allocated region.
 */
void *luagtk_make_boxed_value(lua_State *L, int index)
{
    if (lua_isnil(L, index))
	return NULL;
    struct boxed_lua_value *b = g_slice_new(struct boxed_lua_value);
    _fill_boxed_value(L, b, index);
    return b;
}


/**
 * Sometimes an automatic boxing of Lua values is not possible.  In this case,
 * the user can explicitely box a value.
 *
 * @luaparam  A value to box
 * @return  The boxed value
 */
static int l_make_boxed_value(lua_State *L)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_newuserdata(L,
	sizeof(*b));
    _fill_boxed_value(L, b, 1);
    return 1;
}


/**
 * Sometimes the automatic type conversion fails for vararg parameters, e.g.
 * when an integer is given, and a double is required.  To enforce a type
 * in this case, you can use gtk.cast("typename", value).
 */
static int l_cast(lua_State *L)
{
    const char *type_name = luaL_checkstring(L, 1);
    luaL_checkany(L, 2);
    GTK_INITIALIZE();
    GType type = luagtk_g_type_from_name(type_name);
    if (!type)
	return luaL_error(L, "%s unknown type %s", msgprefix, type_name);

    struct boxed_lua_value *b = (struct boxed_lua_value*) lua_newuserdata(L,
	sizeof(*b));
    _fill_boxed_value(L, b, 2);
    _set_boxed_metatable(L);
    b->type = type;

    return 1;
}


/**
 * Push the Lua value wrapped in the LuaValue box onto the Lua stack.
 *
 * @param L  Lua State
 * @param p  Pointer to the boxed value
 * @return  1, and the Lua value on the Lua stack
 */
int luagtk_get_boxed_value(lua_State *L, const void *p)
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
void luagtk_boxed_to_ffi(lua_State *L, int index, union gtk_arg_types *dest,
    const ffi_type **argtype)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*)
	lua_topointer(L, index);
    const char *type_name = g_type_name(b->type);
    lua_rawgeti(L, LUA_REGISTRYINDEX, b->ref);

    // printf("luagtk_boxed_to_ffi: %p %s\n", b, type_name);

    if (!strcmp(type_name, "gdouble")) {
	dest->d = lua_tonumber(L, -1);
	*argtype = &ffi_type_double;
	lua_pop(L, 1);
	return;
    }

    luaL_error(L, "%s boxed value contains unsupported type %s", msgprefix,
	type_name);
}


/**
 * Given a boxed value, retrieve its contents.  Usually such boxed values
 * should be returned as GValue, which automatically "unwraps" such a box.
 */
static int l_get_boxed_value(lua_State *L)
{
    return luagtk_get_boxed_value(L, lua_topointer(L, 1));
}


static const luaL_reg gtk_methods[] = {
    {"make_boxed_value",    l_make_boxed_value },
    {"get_boxed_value",	    l_get_boxed_value },
    {"cast",		    l_cast },
    { NULL, NULL }
};

void luagtk_init_boxed(lua_State *L)
{
    luaL_register(L, NULL, gtk_methods);
}

/**
 * GObject wants to copy a boxed value.  We now need another reference for the
 * Lua value.
 */
static gpointer _boxed_copy(gpointer val)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) val, *b2;

    b2 = g_slice_new(struct boxed_lua_value);
    b2->L = b->L;
    lua_rawgeti(b->L, LUA_REGISTRYINDEX, b->ref);
    b2->ref = luaL_ref(b->L, LUA_REGISTRYINDEX);

    return (gpointer) b2;
}

/**
 * When GObject wants to free a boxed value, unreference the Lua value
 * associated with it, and release the memory.
 */
static void _boxed_free(gpointer val)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) val;
    luaL_unref(b->L, LUA_REGISTRYINDEX, b->ref);
    g_slice_free(struct boxed_lua_value, val);
}

/**
 * Register a new boxed type with GObject that allows to wrap an arbitrary Lua
 * value.
 */
void luagtk_boxed_register()
{
    luagtk_boxed_value_type = g_boxed_type_register_static("LuaValue",
	_boxed_copy, _boxed_free);
}

