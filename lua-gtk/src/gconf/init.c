/*- vim:sw=4:sts=4
 *
 * Binding for GConf2.  This is part of LuaGnome.
 * Copyright (C) 2009 Wolfgang Oertl
 */

// #include <gconf/gconf.h>
#include "module.h"
#include <string.h>

typedef struct _GConfEngine GConfEngine;

/**
 * Handle refcounting of GConfEngine objects, which are not derived from
 * GObject - unfortunately.
 */
static int _gconf_engine_handler(struct object *o, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    const char *name = api->get_object_name(o);
	    if (!strcmp(name, "GConfEngine"))
		return 100;
	    break;
	
	/* the refcount is in the opaque structure and can't be retrieved. */
	case WIDGET_GET_REFCOUNT:;
	    return 1;
	
	case WIDGET_REF:;
	    gconf_engine_ref(o->p);
	    return 0;
	
	case WIDGET_UNREF:
	    gconf_engine_unref(o->p);
	    return 0;
    }

    return 0;
}

int luaopen_gconf(lua_State *L)
{
    int rc = load_gnome(L);
    api->register_object_type("gconf_engine", _gconf_engine_handler);
    return rc;
}

