/* vim:sw=4:sts=4
 * Boilerplate code for GtkHTML.  This is part of LuaGnome, a binding of
 * Gnome libraries to Lua 5.
 */

#include "module.h"

int luaopen_gtkhtml(lua_State *L)
{
    return load_gnome(L);
}

