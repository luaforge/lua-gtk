/* vim:sw=4:sts=4
 * Boilerplate code for GtkHTML.  This is part of LuaGnome, a binding of
 * Gnome libraries to Lua 5.
 */

#include "module.h"

const char gtkhtml3_func_remap[] =
    "\21GtkHTML\0gtk_html"
    "\0";

int luaopen_gtkhtml3(lua_State *L)
{
    return load_gnome(L);
}

