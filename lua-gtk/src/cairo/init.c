/*- vim:sw=4:sts=4
 *
 * Support for the Cairo library.  This is part of LuaGnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */

#include "module.h"

int luaopen_cairo(lua_State *L)
{
    return load_gnome(L);
}

