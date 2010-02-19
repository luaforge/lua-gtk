/*- vim:sw=4:sts=4
 *
 * Support for the Cairo library.  This is part of LuaGnome.
 * Copyright (C) 2008, 2010 Wolfgang Oertl
 */

#include "module.h"
#include "override.h"
#include <string.h>

extern struct module_info modinfo_cairo;
typedef void cairo_t;

/**
 * This function actually frees the cairo state.
 * TODO  arrange for the normal garbage collection to also use
 *       cairo_destroy
 */
static int l_cairo_destroy(lua_State *L)
{
    struct object *w = api->object_arg(L, 1, "cairo");
    int rc = api->call_byname(L, &modinfo_cairo, "cairo_destroy");
    api->invalidate_object(L, w);
    return rc;
}



const luaL_reg cairo_overrides[] = {
    OVERRIDE(cairo_destroy),
    { NULL, NULL }
};

static int _cairo_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    const char *s = api->get_object_name(w);
	    return strcmp(s, "cairo") ? 0 : 100;
	
	case WIDGET_UNREF:
	    cairo_destroy(w->p);
	    return 0;
	
	default:
	    break;
    }

    /* other operations are not handled and are passed to the
     * default handler. */
    return api->call_object_handler(w, op, flags, "malloc");
}



int luaopen_cairo(lua_State *L)
{
    int rc = load_gnome(L);
    api->register_object_type("cairo", _cairo_handler);
    return rc;
}

