/*- vim:sw=4:sts=4
 *
 * Binding for LibXML2.  This is part of LuaGnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */

#include "module.h"

int luaopen_libxml2(lua_State *L)
{
    return load_gnome(L);
}

