/*- vim:sw=4:sts=4
 *
 * Support for the Gtk library.  This is part of LuaGnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */


#include <gtk/gtk.h>
#include <string.h>		// strcmp
#include "module.h"

static int gtk_is_initialized = 0;

/*-
 * For some classes, no _new function exists, but a _free function does.
 * Newer Gtk versions tend to use GSlice, but this hasn't always been so.
 * In order to make lua-gtk compatible with older versions, in certain
 * cases g_malloc has to be used to allocate certain classes.
 *
 * Note that the _runtime_ Gtk version is compared and not the compile time;
 * this ensures that even when compiled with a new Gtk library, it will work
 * with older versions.
 *
 * See http://svn.gnome.org/viewvc/gtk%2B/
 */
#define _VERSION(x,y,z) ((x)*10000 + (y)*100 + (z))
static const struct special_alloc {
    const char *type_name;		// name of class concerned
    int version_from, version_to;	// range of Gtk versions selected
    int what;				// 1=g_malloc, 2=GdkColor
} special_alloc[] = {
    { "GtkTreeIter", 0, _VERSION(2,10,11), 1 },	// SVN version 17761
    { "GdkColor", 0, _VERSION(2,8,8), 2 },	// SVN version 14359
    { NULL, 0, 0, 0 }
};

/**
 * Determine how to allocate a given structure.
 *
 * @param ts  Typespec of the structure to allocate
 * @return 0=use g_slice_alloc, 1=use g_malloc, 2=special case for GdkColor
 */
static int _special_alloc(typespec_t ts)
{
    const struct special_alloc *p;
    const char *type_name = api->get_type_name(ts);
    int version = _VERSION(gtk_major_version, gtk_minor_version,
	gtk_micro_version);

    for (p=special_alloc; p->type_name; p++)
	if (!strcmp(type_name, p->type_name)
	    && p->version_from <= version && version <= p->version_to)
	    return p->what;

    return 0;
}
#undef _VERSION


void *gtk_allocate_object(cmi mi, lua_State *L, typespec_t ts, int count,
    int *flags)
{
    int rc;
    type_info_t ti;
    void *p;

    if (count) {
	rc = 1;
	*flags = FLAG_ARRAY | FLAG_NEW_OBJECT;
    } else {
	rc = _special_alloc(ts);
	*flags = FLAG_ALLOCATED | FLAG_NEW_OBJECT;
    }

    ti = mi->type_list + ts.type_idx;
    switch (rc) {
	case 0:
	    p = g_slice_alloc0(ti->st.struct_size);
	    break;
	
	case 1:
	    p = g_malloc(ti->st.struct_size * count);
	    break;
	
	case 2:;
	    // No gdk_color_new function exists.  Instead, call the copy
	    // function with allocates it.  This works for any Gtk version, but
	    // is required before 2.8.8.
	    GdkColor c = { 0, 0, 0, 0 };
	    p = (void*) gdk_color_copy(&c);
	    break;
	
	default:
	    luaL_error(L, "%s _special_alloc returned invalid value %d",
		api->msgprefix, rc);
	    p = NULL;
    }

    return p;
}

/**
 * Initialize Gtk if it hasn't happened yet.  This function is called every
 * time before a library function is called through this module.
 */
void gtk_call_hook(lua_State *L, struct func_info *fi)
{
    if (gtk_is_initialized)
	return;

    if (strcmp(fi->name, "gtk_init")) {
	gtk_is_initialized = 1;
	gtk_init(NULL, NULL);
    }

    gtk_is_initialized = 1;
}


/**
 * Handler for GTK_IS_OBJECT objects.
 * This is almost the same as the GObject handler, but uses gtk_object_ref_sink
 * for older GTK libraries.
 */
static int _gtkwidget_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:
	    if (flags & FLAG_ALLOCATED)
		return 0;
	    GType type_nr = g_type_from_name(api->get_object_name(w));
	    GType type_of_gobject = g_type_from_name("GObject");
	    if (!g_type_is_a(type_nr, type_of_gobject))
		return 0;
	    if (GTK_IS_OBJECT(w->p))
		return 101;
	    return 0;

	case WIDGET_GET_REFCOUNT:
	    return ((GObject*)w->p)->ref_count;

	case WIDGET_REF:
#ifdef GTK_OLDER_THAN_2_10
	    // GtkObjects are created with a floating ref, so this code
	    // works no matter whether it is a new or existing object.
	    g_object_ref(w->p);
	    gtk_object_sink((GtkObject*) w->p);
#else
	    // GtkObject derived objects are referenced when new.
	    g_object_ref_sink(w->p);
#endif
	    break;

	case WIDGET_UNREF:;
	    int ref_count = ((GObject*)w->p)->ref_count;
	    if (ref_count <= 0) {
		fprintf(stderr, "%p %p GC  %d %s - free with this refcount?\n",
		    w, w->p, ref_count, api->get_object_name(w));
		return 0;
	    }
	    g_object_unref(w->p);
	    w->p = NULL;
	    break;
    }

    return -1;
}

int luaopen_gtk(lua_State *L)
{
    int rc = load_gnome(L);
    api->register_object_type("gtkwidget", _gtkwidget_handler);
    return rc;
}

