/* vim:sw=4:sts=4
 * Lua/Gnome binding: overrides for Clutter functions.
 */

#include <clutter/clutter.h>
#include "module.h"
#include "override.h"
#include <string.h>	    // strchr, strlen

extern struct lg_module_api *api;


/**
 * Override for clutter.init() .  It allows to omit all arguments.
 *
 */
static int l_clutter_init(lua_State *L)
{
    int t = lua_gettop(L);

    switch (t) {
	case 0:
	lua_pushinteger(L, 0);
	/* fall through */

	case 1:
	lua_pushnil(L);
    }

    return api->call_byname(L, thismodule, "clutter_init");
}


/**
 * Override for clutter.rectangle_new_with_color().  It allows to pass a
 * 4-element table (or 4 distinct number values) as a constructor for Color.
 *
 */
static int l_clutter_rectangle_new_with_color(lua_State *L)
{
    if (lua_gettop(L) == 4) {
        ClutterColor *color = (ClutterColor*) g_malloc(sizeof(*color));
	color->red = lua_tointeger(L, 1);
	color->green = lua_tointeger(L, 2);
	color->blue = lua_tointeger(L, 3);
	color->alpha = lua_tointeger(L, 4);
        lua_settop(L, 0);
	typespec_t ts = api->find_struct(L, "ClutterColor", 1);
	api->get_object(L, color, ts, 0);
    } else if (lua_istable(L, 1)) {
	printf("color as table not yet supported\n");
    }

    return api->call_byname(L, thismodule, "clutter_rectangle_new_with_color");
}
    
/* overrides for Clutter */
const luaL_reg clutter_overrides[] = {
      OVERRIDE(clutter_init),
      OVERRIDE(clutter_rectangle_new_with_color),
      { NULL, NULL}
};

