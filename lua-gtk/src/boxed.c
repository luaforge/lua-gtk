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
 */

#include "luagtk.h"
#include <lauxlib.h>

int luagtk_boxed_value_type = 0;

// To wrap a Lua value, it will be stored using the reference mechanism.
struct boxed_lua_value {
    int	ref;
    lua_State *L;
};

static gpointer _boxed_copy(gpointer val)
{
    struct boxed_lua_value *b = (struct boxed_lua_value*) val, *b2;

    b2 = g_slice_new(struct boxed_lua_value);
    // printf("boxed copy %p -> %p\n", b, b2);

    b2->L = b->L;
    lua_rawgeti(b->L, LUA_REGISTRYINDEX, b->ref);
    b2->ref = luaL_ref(b->L, LUA_REGISTRYINDEX);

    return (gpointer) b2;
}

static void _boxed_free(gpointer val)
{
    // printf("boxed free %p\n", val);
    struct boxed_lua_value *b = (struct boxed_lua_value*) val;
    luaL_unref(b->L, LUA_REGISTRYINDEX, b->ref);
    g_slice_free(struct boxed_lua_value, val);
}

static void _fill_boxed_value(lua_State *L, struct boxed_lua_value *b,
    int index)
{
    b->L = L;
    lua_pushvalue(L, index);
    b->ref = luaL_ref(L, LUA_REGISTRYINDEX);
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
    // printf("new boxed value at %p\n", b);
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
    { NULL, NULL }
};

void luagtk_init_boxed(lua_State *L)
{
    luaL_register(L, NULL, gtk_methods);
}

// register a new boxed type with GObject that allows to wrap an arbitrary
// Lua value.
void luagtk_boxed_register()
{
    luagtk_boxed_value_type = g_boxed_type_register_static("LuaValue",
	_boxed_copy, _boxed_free);
}

