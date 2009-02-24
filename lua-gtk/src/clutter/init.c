/*- vim:sw=4:sts=4
 *
 * Support for the Clutter library.  This is part of LuaGnome.
 * Copyright (C) 2009 Michal Kolodziejczyk, Wolfgang Oertl
 */

#include "module.h"

int luaopen_clutter(lua_State *L)
{
    return load_gnome(L);
}

