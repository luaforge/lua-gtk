// vim:sw=4:sts=4

#include <pango/pango.h>
#include "module.h"
#include "override.h"
#include <string.h>	    // strcmp
#include <errno.h>	    // errno

// the output array size isn't easily determined.
static int l_pango_tab_array_get_tabs(lua_State *L)
{
    OBJECT_ARG(tab_array, PangoTabArray, *, 1);
    int t2, t3, i, n;

    PangoTabAlign *alignments = NULL;
    gint *locations = NULL;

    t2 = lua_type(L, 2);
    luaL_argcheck(L, t2 == LUA_TNIL || t2 == LUA_TTABLE, 2, "nil or table");

    t3 = lua_type(L, 3);
    luaL_argcheck(L, t3 == LUA_TNIL || t3 == LUA_TTABLE, 3, "nil or table");

    n = pango_tab_array_get_size(tab_array);

    pango_tab_array_get_tabs(tab_array, t2 == LUA_TNIL ? NULL : &alignments,
	t3 == LUA_TNIL ? NULL : &locations);

    // copy the values to the table
    if (alignments) {
	api->empty_table(L, 2);
	typespec_t ts = api->find_struct(L, "PangoTabAlign", 0);
	for (i=0; i<n; i++) {
	    api->push_constant(L, ts, alignments[i]);
	    lua_rawseti(L, 2, i + 1);
	}
	g_free(alignments);
    }

    if (locations) {
	api->empty_table(L, 3);
	for (i=0; i<n; i++) {
	    lua_pushnumber(L, locations[i]);
	    lua_rawseti(L, 3, i + 1);
	}
	g_free(locations);
    }

    return 0;
}

FSO(pango_attr_iterator_get_attrs, GSLIST_FREE_PANGO_ATTR);
FSO(pango_glyph_item_apply_attrs, GSLIST_FREE_PANGO_GLYPH);


#if 0
static int l_pango_attr_iterator_get_font(lua_State *L)
{
    int rc = api->call_byname(L, "pango_attr_iterator_get_font");
    // XXX this is an optional return value... where is it on the stack?
    struct object *w = (struct object*) lua_touserdata(L, WHATEVER);
    w->flags = GSLIST_FREE_PANGO_ATTR;
    return rc;
}
#endif

// strangely enough, these functions are actually defined in GDK
static int l_pango_layout_get_clip_region(lua_State *L)
{
    return api->call_function(L, "gdk", "gdk_pango_layout_get_clip_region");
}

// strangely enough, these functions are actually defined in GDK
static int l_pango_layout_line_get_clip_region(lua_State *L)
{
    return api->call_function(L, "gdk",
	"gdk_pango_layout_line_get_clip_region");
}

const luaL_reg pango_overrides[] = {
    OVERRIDE(pango_tab_array_get_tabs),
    OVERRIDE(pango_attr_iterator_get_attrs),
    OVERRIDE(pango_glyph_item_apply_attrs),
    OVERRIDE(pango_layout_get_clip_region),
    OVERRIDE(pango_layout_line_get_clip_region),
    { NULL, NULL }
};


