/*- vim:sw=4:sts=4
 *
 * Binding for GtkSpell.  This is part of LuaGnome.
 * Copyright (C) 2009 Wolfgang Oertl
 */

#include "module.h"

int luaopen_gtkspell(lua_State *L)
{
    return load_gnome(L);
}

