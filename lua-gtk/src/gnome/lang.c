/* vim:sw=4:sts=4
 * 
 * Library to use the Gnome family of libraries from Lua 5.1
 * Copyright (C) 2008 Wolfgang Oertl
 * Use this software under the terms of the GPLv2 (the license of Gnome).
 *
 * Handle runtime translation of messages.
 */

#include "luagnome.h"
#include <glib.h>


/**
 * Load the translation file for the given module, and store the resulting
 * table into the module's table.  In case of error, store an empty table.
 *
 * The translation file is a simple Lua file with one table per language,
 * each containing id/text pairs.
 *
 * Lua stack in: MOD
 * Lua stack out: MOD catalog
 */
static void _load_translation_file(lua_State *L, const char *modname)
{
    int rc;
    char filename[100];

    sprintf(filename, "lang/%s.lua", modname);
    lua_newtable(L);			// the environment
    rc = luaL_loadfile(L, filename);

    if (rc == 0) {
	lua_pushvalue(L, -2);		// again, the environment
	lua_setfenv(L, -2);
	lua_call(L, 0, 0);
    } else {
	// failed to load.  stack: MOD catalog message
	printf("%s %s\n", msgprefix, lua_tostring(L, -1));
	lua_pop(L, 1);
    }

    // stack: MOD catalog
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, "_lang");

    // stack: MOD catalog
}

/**
 * Try to translate the given message similar to what gettext does.
 *
 * @param L  Lua State
 * @param modname  The module that contains the message
 * @param id  The message ID
 * @param msg  The English message
 */
static const char *lg_translate(lua_State *L, const char *modname, int id,
    const char *msg)
{
    const char *lang = "de";

    // XXX find out what the current language is; if English, return msg

    // is the language catalog already loaded?
    lua_getglobal(L, modname);
    lua_pushstring(L, "_lang");
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	_load_translation_file(L, modname);	// stack: MOD
    }

    // stack: MOD catalog
    lua_remove(L, -2);				// stack: catalog

    // translation table at the top of the stack (may be empty).  find language
    lua_getfield(L, -1, lang);			// stack: catalog langtbl
    if (!lua_isnil(L, -1)) {
	lua_rawgeti(L, -1, id);			// stack: catalog langtbl trans
	if (!lua_isnil(L, -1))
	    msg = lua_tostring(L, -1);
	lua_pop(L, 1);
    }

    lua_pop(L, 2);
    return msg;
}




/**
 * This is the same as luaL_argerror, but accepts a printf style argument list.
 *
 * Note: neither g_vasprintf nor g_strdup_printf are used, as the former is
 * only available since GLib 2.4, and both leave a memory leak as luaL_argerror
 * doesn't return (to free the allocated buffer).  This could be mitigated
 * by having a static char* buffer, and freeing it on subsequent calls.
 *
 * This function is usually called from the LG_ARGERROR macro.
 */
int lg_argerror(lua_State *L, int narg, const char *modname, int id,
    const char *fmt, ...)
{
    va_list ap;

    // try to translate.  In case of failure (or if English is selected),
    // this returns the unchanged "fmt".
    fmt = lg_translate(L, modname, id, fmt);

    // output the message signature
    va_start(ap, fmt);
    lua_pushfstring(L, "[LG %s.%d] ", modname, id);
    lua_pushvfstring(L, fmt, ap);
    va_end(ap);

    lua_concat(L, 2);
    return luaL_argerror(L, narg, lua_tostring(L, -1));
}


/**
 * Do whatever luaL_error would do, but translate the message and prepend
 * the message identifier.
 *
 * This should closely match luaL_error in lua/src/lauxlib.c.
 */
int lg_error(lua_State *L, const char *modname, int id, const char *fmt, ...)
{
    va_list ap;

    fmt = lg_translate(L, modname, id, fmt);
    luaL_where(L, 1);

    va_start(ap, fmt);
    lua_pushfstring(L, "[LG %s.%d] ", modname, id);
    lua_pushvfstring(L, fmt, ap);
    va_end(ap);

    lua_concat(L, 3);
    return lua_error(L);
}


/**
 * Push a message onto the Lua stack after translation and prefixing with
 * the message id.
 */
void lg_message(lua_State *L, const char *modname, int id,
    const char *fmt, ...)
{
    va_list ap;
    fmt = lg_translate(L, modname, id, fmt);

    va_start(ap, fmt);
    lua_pushfstring(L, "[LG %s.%d] ", modname, id);
    lua_pushvfstring(L, fmt, ap);
    va_end(ap);

    lua_concat(L, 2);
}

