/* vim:sw=4:sts=4
 * Glue code for the GtkSourceView module.
 */

#include "module.h"

int luaopen_gtksourceview(lua_State *L)
{
    return load_gnome(L);
}
