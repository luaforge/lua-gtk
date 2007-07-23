/* vim:sw=4:sts=4
 * Lua binding for the Gtk 2 toolkit.
 *
 * This is a "hack" because it requires a Lua internal header file.
 */

#include "lobject.h"

/**
 * Determine the address of a C function.  This is currently not used anywhere,
 * but might be useful when a callback needs to be passed to a Gtk function.
 * 
 * Input stack: a C function
 * Output stack: unchanged
 * Returns: the address of the function.
 */
void *get_c_function_address(lua_State *L, int index)
{
    Closure *cl = (Closure*) lua_topointer(L, index);
    return cl->c.f;
}

