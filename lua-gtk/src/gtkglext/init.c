/* vim:sw=4:sts=4
 *
 * Binding for the GtkGLExt library.  This is part of LuaGnome.
 * Copyright (C) 2009 Wolfgang Oertl
 */

#include <gdk/gdkgl.h>
#include <gtk/gtkgl.h>
#include "module.h"
#include <string.h>

static int gtkglext_is_initialized = 0;

void gtkglext_call_hook(lua_State *L, struct func_info *fi)
{
    if (gtkglext_is_initialized)
	return;

    if (strcmp(fi->name, "gtk_gl_init")) {
	gtkglext_is_initialized = 1;
	struct module_info *mi = api->find_module("gtk");
	if (mi) {
	    /* This call fails unless Gtk is initialized. */
	    mi->call_hook(L, fi);
	}
	gtk_gl_init(NULL, NULL);
    }

    gtkglext_is_initialized = 1;
}

int luaopen_gtkglext(lua_State *L)
{
    int rc = load_gnome(L);
    return rc;
}


