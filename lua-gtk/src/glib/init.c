/*- vim:sw=4:sts=4
 *
 * Support for the GLib and GObject libraries.  This is part of lua-gnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */


#include "module.h"

/**
 * Handler for GObject derived objects.  They have refcounting, so when a Lua
 * proxy object is created, the refcount usually is increased by one, and when
 * it is garbage collected, it must be decreased again.  Of course, there are
 * various fine points to it...
 */
static int _gobject_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    // not applicable to objects that have been malloc()ed directly.
	    if (flags & FLAG_ALLOCATED)
		return 0;
	    GType type_nr = g_type_from_name(api->get_object_name(w));
	    GType type_of_gobject = g_type_from_name("GObject");
	    return g_type_is_a(type_nr, type_of_gobject) ? 100 : 0;

	case WIDGET_GET_REFCOUNT:
	    return ((GObject*)w->p)->ref_count;

	case WIDGET_REF:
	    // new objects need not be referenced.
	    if (flags & FLAG_NEW_OBJECT)
		break;

#ifdef GOBJECT_OLDER_THAN_2_10
	    /* XXX wrong if _is_on_stack.  is_new is 1, but actually it
	     * isn't, so the refcount isn't increased... */
	    // Normal objects are created with one reference.  Only add
	    // another one of this is not a new object.
	    g_object_ref(w->p);
#else
	    // non-Gtk objects (e.g. GdkDrawable, GtkStyle, PangoLayout) are
	    // not referenced if new.
	    g_object_ref_sink(w->p);
#endif
	    /*
	    fprintf(stderr, "%p %p %s ref - refcnt after = %d, floating=%d\n",
		w, w->p, api->get_object_name(w), ((GObject*)w->p)->ref_count,
		g_object_is_floating(w->p));
	    */
	    break;

	case WIDGET_UNREF:;
	    int ref_count = ((GObject*)w->p)->ref_count;
	    if (ref_count <= 0) {
		fprintf(stderr, "%p %p GC  %d %s - free with this refcount?\n",
		    w, w->p, ref_count, api->get_object_name(w));
		return 0;
	    }

	    // fprintf(stderr, "Unref %p %p %s\n", w, w->p, api->get_object_name(w));

	    // sometimes triggers a glib error here. w->p is a valid object,
	    // ref_count == 1.
	    g_object_unref(w->p);

	    /*
	    fprintf(stderr, "%p %p %s unref - refcnt now %d\n",
		w, w->p, api->get_object_name(w), ((GObject*)w->p)->ref_count);
	    */

	    w->p = NULL;
	    break;
    }

    return -1;
}

/**
 * Any object derived from GInitiallyUnowned has a floating reference after
 * creation.  As this reference is then "owned" by the Lua proxy object,
 * g_object_ref_sink has to be called on new objects.
 */
static int _ginitiallyunowned_handler(struct object *w, object_op op, int flags)
{
    static GType giu_type = 0;

    switch (op) {
	case WIDGET_SCORE:;
	    // not applicable to objects that have been malloc()ed directly.
	    if (flags & FLAG_ALLOCATED)
		return 0;
	    GType type_nr = g_type_from_name(api->get_object_name(w));
	    if (!giu_type)
		giu_type = g_type_from_name("GInitiallyUnowned");
	    return g_type_is_a(type_nr, giu_type) ? 103 : 0;

	case WIDGET_GET_REFCOUNT:
	    return ((GObject*)w->p)->ref_count;

	case WIDGET_REF:
	    g_object_ref_sink(w->p);
	    return 0;

	case WIDGET_UNREF:;
	    int ref_count = ((GObject*)w->p)->ref_count;
	    if (ref_count <= 0) {
		fprintf(stderr, "%p %p GC  %d %s - free with this refcount?\n",
		    w, w->p, ref_count, api->get_object_name(w));
		return -1;
	    }

	    // sometimes triggers a glib error here. w->p is a valid object,
	    // ref_count == 1.
	    g_object_unref(w->p);
	    w->p = NULL;
	    return 0;
    }

    return -1;
}




void glib_init_channel(lua_State *L);

int luaopen_glib(lua_State *L)
{
    int rc = load_gnome(L);
    glib_init_channel(L);
    api->register_object_type("gobject", _gobject_handler);
    api->register_object_type("ginitiallyunowned", _ginitiallyunowned_handler);
    return rc;
}

