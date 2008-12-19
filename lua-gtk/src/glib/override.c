/* vim:sw=4:sts=4
 * Lua Gtk2 binding.
 */

#include "module.h"
#include "override.h"
#include <string.h>	    // strcmp
#include <errno.h>	    // errno

// in init.c
extern struct module_info modinfo_glib;

// in callback.c
int glib_connect(lua_State *L);
int glib_connect_after(lua_State *L);
int glib_disconnect(lua_State *L);

/**
 * Overrides for existing Gtk/Gdk functions.
 *
 * @class module
 * @name gtk.override
 */


/**
 * g_type_from_name fails unless the type has been initialized before.  Use
 * my wrapper that handles the initialization when required.
 *
 * @name g_type_from_name
 * @luaparam name  The type name to look up.
 * @luareturn  The type number, or nil on error.
 */
static int l_g_type_from_name(lua_State *L)
{
    const char *s = luaL_checkstring(L, 1);

    int type_nr = api->gtype_from_name(L, NULL, s);
    if (!type_nr)
	return 0;
    lua_pushnumber(L, type_nr);
    return 1;
}


/**
 * Perform the G_OBJECT_GET_CLASS on an object.  Try all possible *Class
 * structures in the hierarchy until one is found.
 *
 * @name g_object_get_class
 * @luaparam object
 * @luareturn The class object (GObjectClass) of the object, or nil on error.
 */
static int l_g_object_get_class(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    struct object *o = (struct object*) lua_touserdata(L, 1);
    GObjectClass *c = G_OBJECT_GET_CLASS(o->p);
    char class_name[80];
    GType type = G_TYPE_FROM_CLASS(c);

    while (type) {
	sprintf(class_name, "%sClass", g_type_name(type));
	typespec_t ts = api->find_struct(L, class_name, 1);
	if (ts.value) {
	    api->get_object(L, c, ts, FLAG_NOT_NEW_OBJECT);
	    return 1;
	}
	type = g_type_parent(type);
    }

    return luaL_error(L, "%s no Class type for type %s available.",
	api->msgprefix, api->get_object_name(o));
}

/* XXX an ad-hoc created function */
static int l_g_object_get_class_name(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    struct object *w = (struct object*) lua_touserdata(L, 1);
    lua_pushstring(L, api->get_object_name(w));
    return 1;
}


/**
 * Set a property of an object.  The difficulty is to first convert the value
 * to a GValue of the correct type, because that is what the GLib function
 * expects.
 *
 * @name g_object_set_property
 * @luaparam object   Object derived from GObject
 * @luaparam property_name
 * @luaparam value    The value to set the property to
 */
static int l_g_object_set_property(lua_State *L)
{
    struct object *w = (struct object*) lua_touserdata(L, 1);
    struct object_type *wt = api->get_object_type(L, w);

    if (!wt) {
	printf("%s invalid object in l_g_object_set_property.\n",
	    api->msgprefix);
	return 0;
    }

    // this object must be one derived from gobject or gtkwidget.
    if (strcmp(wt->name, "gobject") && strcmp(wt->name, "gtkwidget")) {
	printf("%s g_object_set_property on a %s object\n", api->msgprefix,
	    wt->name);
	return 0;
    }

    lua_getmetatable(L, 1);
    lua_getfield(L, -1, "_gtktype");
    GType type = lua_tointeger(L, -1);
    GObjectClass *oclass = (GObjectClass*) g_type_class_ref(type);
    const gchar *prop_name = luaL_checkstring(L, 2);

    // find the property; this searches all parent classes, too.
    GParamSpec *pspec = g_object_class_find_property(oclass, prop_name);
    if (!pspec) {
	printf("g_object_set_property: no property %s.%s\n",
	    api->get_object_name(w), prop_name);
	return 0;
    }

    GValue gvalue = {0};
    api->lua_to_gvalue_cast(L, 3, &gvalue, pspec->value_type);
    g_object_set_property((GObject*) w->p, prop_name, &gvalue);
    g_value_unset(&gvalue);

    g_type_class_unref(oclass);
    return 0;
}

/**
 * Provide a memory location to store each return value.  This is not possible
 * without an override.
 * XXX not implemented yet
 */
static int l_g_object_get(lua_State *L)
{
    printf("g_object_get: NOT YET IMPLEMENTED\n");
    return 0;
}


/**
 * Streaming capable converter.  It will convert as much as possible from
 * the input buffer; it may leave some bytes unused, which you should prepend
 * to any data read later.
 *
 * @name g_iconv
 * @luaparam converter  GIConv as returned from g_iconv_open
 * @luaparam inbuf  The string to convert
 * @return  status (0=ok, <1=error)
 * @return  The converted string
 * @return  Remaining unconverted string
 *
 */
static int l_g_iconv(lua_State *L)
{
    OBJECT_ARG(converter, GIConv, , 1);
    gsize ilen, olen, olen2;
    gchar *inbuf = (gchar*) luaL_checklstring(L, 2, &ilen);
    char *obuf, *obuf2;
    int rc, result=0;

    if (lua_gettop(L) != 2)
	return luaL_error(L, "%s g_iconv(converter, inbuf) not called "
	    "properly.  Note that LuaGnome's API differs from the C API.",
	    api->msgprefix);

    // happens on windows sometimes.
    if (converter == (GIConv) -1) {
	lua_pushnumber(L, 0);
	lua_pushvalue(L, 2);
	lua_pushliteral(L, "");
	return 3;
    }

    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    olen = ilen;
    obuf = g_malloc(olen);

    while (ilen > 0) {
	obuf2 = obuf;
	olen2 = olen;
	rc = g_iconv(converter, &inbuf, &ilen, &obuf2, &olen2);

	// push whatever has been converted in this run
	luaL_addlstring(&buf, obuf, obuf2 - obuf);

	if (rc < 0) {
	    // illegal sequence
	    if (errno == EILSEQ) {
		result = -errno;
		break;
	    }

	    // ends with an incomplete sequence - is ok
	    if (errno == EINVAL)
		break;

	    // full, don't worry continue
	    if (errno != E2BIG) {
		result = -errno;
		break;
	    }
		
	} else
	    result += rc;
    }

    lua_pushinteger(L, result);
    luaL_pushresult(&buf);
    lua_pushlstring(L, inbuf, ilen);
    g_free(obuf);

    return 3;
}




/**
 * Override for g_slist_free: if the "data" part of each list element
 * is to be freed, do it automatically.
 *
 * After calling g_slist_free, the list doesn't exist anymore.  This is shown
 * by setting w->p to NULL and w->is_deleted to 1.
 */
static int l_g_slist_free(lua_State *L)
{
    struct object *w = api->object_arg(L, 1, "GSList");
    void (*func)(void*) = NULL;

    switch (w->flags) {
	case GSLIST_FREE_GFREE:
	func = g_free;
	break;

	case GSLIST_FREE_PANGO_ATTR:
	func = api->optional_func(L, NULL, "pango_attribute_destroy",
	    "Pango 1.0");
	break;

	case GSLIST_FREE_PANGO_GLYPH:
	func = api->optional_func(L, NULL, "pango_glyph_item_free",
	    "Pango 1.6");
	break;
    }

    if (func) {
	GSList *l = (GSList*) w->p;
	while (l) {
	    func(l->data);
	    l->data = NULL;
	    l = l->next;
	}
    }

    int rc = api->call_byname(L, &modinfo_glib, "g_slist_free");
    api->invalidate_object(L, w);
    return rc;
}


/**
 * Handle the call to g_list_free.  A GList is usually freed automatically,
 * so this is just to prevent the second, automatic freeing which would
 * cause a SEGV.
 */
static int l_g_list_free(lua_State *L)
{
    struct object *w = api->object_arg(L, 1, "GList");
    int rc = api->call_byname(L, &modinfo_glib, "g_list_free");
    api->invalidate_object(L, w);
    return rc;
}

/**
 * This function actually frees the object.  Don't do that again when
 * collecting garbage.
 */
static int l_g_tree_destroy(lua_State *L)
{
    struct object *w = api->object_arg(L, 1, "GTree");
    int rc = api->call_byname(L, &modinfo_glib, "g_tree_destroy");
    api->invalidate_object(L, w);
    return rc;
}

/**
 * This function frees the structure; don't do it again on GC
 */
static int l_g_dir_close(lua_State *L)
{
    struct object *w = api->object_arg(L, 1, "GDir");
    int rc = api->call_byname(L, &modinfo_glib, "g_dir_close");
    api->invalidate_object(L, w);
    return rc;
}
    
/**
 * This function is a macro and therefore is missing from the function list.
 */
static int l_g_utf8_next_char(lua_State *L)
{
    const char *s = luaL_checkstring(L, 1);
    s = g_utf8_next_char(s);
    if (s && *s) {
	printf("result: %p\n", s);
	lua_pushstring(L, s);
	return 1;
    }
    return 0;
}

/**
 * The function g_atexit cannot be used.  The reason is that before such
 * atexit routines are called by libc, shared libraries may already have been
 * unloaded, or the memory containing the closure may have been freed.  This
 * all can lead to SEGV on program exit.  Disallow usage of atexit.
 */
static int l_g_atexit(lua_State *L)
{
    return luaL_error(L, "g_atexit called. This is not allowed; see "
	"documentation.");
}

/* overrides */
const luaL_reg glib_overrides[] = {
    OVERRIDE(g_type_from_name),
    OVERRIDE(g_object_get_class),
    OVERRIDE(g_object_set_property),
    OVERRIDE(g_object_get),
    OVERRIDE(g_atexit),
    OVERRIDE(g_iconv),

    /* SList freeing */
    OVERRIDE(g_slist_free),
    OVERRIDE(g_tree_destroy),
    OVERRIDE(g_list_free),

    OVERRIDE(g_object_get_class_name),
    OVERRIDE(g_dir_close),

    OVERRIDE(g_utf8_next_char),

    // in callback.c
    {"g_object_connect", glib_connect },
    {"g_object_connect_after", glib_connect_after },
    {"g_object_disconnect", glib_disconnect },

    { NULL, NULL }
};

