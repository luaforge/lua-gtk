/*- vim:sw=4:sts=4
 *
 * Support for the GDK libraries.  This is part of LuaGnome.
 * Copyright (C) 2008 Wolfgang Oertl
 */


#include <gdk/gdk.h>
#include "module.h"
#include "override.h"		// macro "OVERRIDE"
#include <string.h>		// strcmp

// Globals
static int gdk_is_initialized = 0;

// see spec.lua:module_info
void gdk_call_hook(lua_State *L, struct func_info *fi)
{
    if (gdk_is_initialized)
	return;
    if (strcmp(fi->name, "gdk_init") && strcmp(fi->name, "gdk_init_check"))
	gdk_init(NULL, NULL);
    gdk_is_initialized = 1;
}

static int _gdk_atom_handler(struct object *w, object_op op, int flags)
{
    if (op == WIDGET_SCORE) {
	if (!strcmp(api->get_object_name(w), "GdkAtom"))
	    return 1000;
    }

    // returns refcount 0, and doesn't do anything on ref and unref.
    return 0;
}

/**
 * Call this function and return the result as a Lua string.
 * 
 * @name gdk_pixbuf_save_to_buffer
 * @luaparam pixbuf  The pixbuf to convert
 * @luaparam type  The output format, e.g. "jpeg"
 * @luareturn  The converted pixbuf as string, or nil on error
 */
static int l_gdk_pixbuf_save_to_buffer(lua_State *L)
{
    struct object *w = (struct object*) lua_touserdata(L, 1);
    GdkPixbuf *pixbuf = (GdkPixbuf*) w->p;
    gchar *buffer = NULL;
    gsize buffer_size = 0;
    const char *type = lua_tostring(L, 2);
    GError *error = NULL;
    gboolean rc;

    rc = gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, type, &error,
	NULL);
    if (buffer) {
	lua_pushlstring(L, buffer, buffer_size);
	g_free(buffer);
	return 1;
    }

    return 0;
}

const luaL_reg gdk_overrides[] = {
    OVERRIDE(gdk_pixbuf_save_to_buffer),
    { NULL, NULL }
};

int luaopen_gdk(lua_State *L)
{
    int rc = load_gnome(L);
    api->register_object_type("gtk_atom", _gdk_atom_handler);
    return rc;
}

