/* vim:sw=4:sts=4
 */

#include <pango/pango.h>
#include <string.h>
#include "module.h"


/**
 * PangoAttrList implements refcounting and isn't derived from GObject!  What
 * a nuisance.  It has its own, incompatible refcounting.
 */
static int _pango_attr_list_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    return strcmp(api->get_object_name(w), "PangoAttrList") ? 0 : 100;
	
	case WIDGET_REF:
	    // New objects already have their refcount set to 1.
	    if (!(flags & FLAG_NEW_OBJECT))
		pango_attr_list_ref(w->p);
	    return 0;
	
	case WIDGET_UNREF:
	    pango_attr_list_unref(w->p);
	    return 0;
	
	// See pango-attributes.c of libpango sources, which contains the
	// definition of struct _PangoAttrList.  The first element is the
	// refcount.
	case WIDGET_GET_REFCOUNT:
	    return * ((guint*) w->p);
    }

    return -1;
}

int luaopen_pango(lua_State *L)
{
    int rc = load_gnome(L);
    api->register_object_type("pangoattrlist", _pango_attr_list_handler);
    return rc;
}

