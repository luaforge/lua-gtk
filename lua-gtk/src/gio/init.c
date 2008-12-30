/*- vim:sw=4:sts=4
 *
 * Support for the GIO library.  This is part of lua-gnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */


#include "module.h"

int luaopen_gio(lua_State *L)
{
    return load_gnome(L);
}
