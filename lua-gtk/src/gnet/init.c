/*- vim:sw=4:sts=4
 *
 * Support for the GNet library.  This is part of lua-gnome.
 * Copyright (C) 2009 Wolfgang Oertl
 */


#include <gnet.h>
#include <string.h>	    /* strcmp */
#include "module.h"
#include "override.h"

const char gnet_func_remap[] =
    "\55GInetAddrNewAsyncID\0gnet_inetaddr_new_async\0"
    "\31GInetAddr\0gnet_inetaddr\0"
    "\17GMD5\0gnet_md5\0"
    "\17GURI\0gnet_uri\0"
    "\17GSHA\0gnet_sha\0"
    "\0";


/**
 * Memory Handler for the type GInetAddr.
 */
static int _inetaddr_handler(struct object *o, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    const char *name = api->get_object_name(o);
	    if (!strcmp(name, "GInetAddr"))
		return 100;
	    return 0;

	case WIDGET_GET_REFCOUNT:
	    break;
	
	case WIDGET_REF:
	    gnet_inetaddr_ref((GInetAddr*)o->p);
	    break;
	
	case WIDGET_UNREF:
	    gnet_inetaddr_unref((GInetAddr*)o->p);
	    break;
    }

    return -1;
}


static int _async_id_handler(struct object *o, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:;
	    const char *name = api->get_object_name(o);
	    if (!strcmp(name, "GInetAddrNewAsyncID"))
		return 100;
	    return 0;

	default:
	    break;
    }

    return -1;
}

/**
 * The wrapped function returns a binary string, so the usual tostring
 * won't work properly.
 */
static int l_gnet_md5_get_digest(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    struct object *o = (struct object*) lua_touserdata(L, 1);
    gchar *s = gnet_md5_get_digest(o->p);
    lua_pushlstring(L, s, GNET_MD5_HASH_LENGTH);
    return 1;
}

static int l_gnet_sha_get_digest(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TUSERDATA);
    struct object *o = (struct object*) lua_touserdata(L, 1);
    gchar *s = gnet_sha_get_digest(o->p);
    lua_pushlstring(L, s, GNET_SHA_HASH_LENGTH);
    return 1;
}

const luaL_reg gnet_overrides[] = {
    OVERRIDE(gnet_md5_get_digest),
    OVERRIDE(gnet_sha_get_digest),
    { NULL, NULL }
};


int luaopen_gnet(lua_State *L)
{
    int rc = load_gnome(L);
    if (api) {
	api->register_object_type("inetaddr", _inetaddr_handler);
	api->register_object_type("async_id", _async_id_handler);
	gnet_init();
    }
    return rc;
}

