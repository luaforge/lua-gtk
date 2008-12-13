/* vim:sw=4:sts=4
 * Lua Gtk2 binding - handle GValues.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * Exported functions:
 *  lg_lua_to_gvalue_cast
 *  lg_lua_to_gvalue
 *  lg_gvalue_to_lua
 *  lg_gvalue_to_ffi
 */

#include "luagnome.h"
#include <string.h>	    // strcpy
#include <stdlib.h>	    // strtol
#include <ctype.h>	    // isspace


/**
 * Try to convert the string to a boolean value.  Recognized strings are
 * "true", "false", "1", "0".
 *
 * @param L  Lua State
 * @param index  Stack position of the string.
 * @return 0=false, 1=true
 */
static int _to_boolean(lua_State *L, int index)
{
    const char *s = lua_tostring(L, index);

    if (!strcasecmp(s, "true"))
	return 1;
    if (!strcasecmp(s, "false"))
	return 0;
    if (s[1] == 0 && (s[0] == '0' || s[0] == '1'))
	return s[0] - '0';

    return luaL_error(L, "%s Can't convert \"%s\" to boolean.\n", msgprefix, s);
}

/**
 * Conversion of a string to float.
 *
 * This function doesn't depend on a library function and therefore is
 * immune to locale settings.  I found it unreliable to set/reset the
 * locale for every conversion.
 *
 * It sets *ok to 0 on error, or 1 on success.
 */
static double _string_to_double(lua_State *L, int index, int *ok)
{
    const char *s = lua_tostring(L, index);
    const char *pos = s;
    char c;
    double v = 0;

    /* digits before the decimal point */
    for (;;) {
	c = *pos++;
	if (c == '.' || c == 0)
	    break;
	if (c >= '0' && c <= '9')
	    v = v * 10 + (c - '0');
	else
	    goto conv_error;
    }

    /* more digits after the decimal point? */
    if (c == '.') {
	double div = 10;
	for (;;) {
	    c = *pos++;
	    if (c == 0)
		break;
	    if (c >= '0' && c <= '9') {
		v = v + (c - '0') / div;
		div = div * 10;
	    } else
		goto conv_error;
	}
    }

    *ok = 1;
    return v;

conv_error:
    *ok = 0;
    return luaL_error(L, "%s GValue: can't convert string \"%s\" to float.",
	msgprefix, s);
}


/**
 * Get the floating point number from the given Lua value.  If it is a string,
 * a conversion has to be done.  The decimal point is always ".", disregarding
 * the current locale setting.
 */
static double _to_double(lua_State *L, int index, int *ok)
{
    int type = lua_type(L, index);

    if (type == LUA_TNUMBER)
	return lua_tonumber(L, index);

    if (type == LUA_TSTRING)
	return _string_to_double(L, index, ok);

    *ok = 0;
    return 0;
}


/**
 * Convert the string of given length to a positive integer.
 *
 * @return 0 on error, 1 on success
 */
static int _parse_integer(const char *s, int len, int *val)
{
    int v = 0;
    char c;

    while (len--) {
	c = *s++;
	if (c >= '0' && c <= '9')
	    v = v * 10 + (c - '0');
	else
	    return 0;
    }

    *val = v;
    return 1;
}


/**
 * The GValue should contain flags.  The given value may be a number, or
 * a string; in this case split it by "|" and look up each item individually.
 */
static int _fill_gvalue_flags(lua_State *L, GValue *gv, int luatype, int index)
{

    switch (luatype) {
	case LUA_TSTRING:;
	    const char *s = lua_tostring(L, index), *s2;
	    int val = 0, rc, val2, len;

	    for (;;) {

		// skip whitespace
		while (*s && *s == ' ')
		    s ++;

		// find separator; might not find one at end of string.
		s2 = strchr(s, '|');
		len = s2 ? s2 - s : strlen(s);

		// trim whitespace at end
		while (len > 0 && isspace(s[len-1]))
		    len --;

		// might be an integer? 0=yes, 1=no
		rc = _parse_integer(s, len, &val2);
		if (rc == 0) {
		    // The string should be an ENUM.  Look up the value.
		    typespec_t ts = { 0 };
		    switch (lg_find_constant(L, &ts, s, len, &val2)) {
			case 1:	    // ENUM/FLAG found
			case 2:	    // integer found
			rc = 1;
			break;

			case 3:	    // string found
			return luaL_error(L, "No string constants allowed "
			    "here");
		    }
		}

		// XXX ts of the enum is not checked.  If there are
		// multiple items ORed together, they should be of the same
		// type_idx.

		if (rc == 1) {
		    val |= val2;
		    if (!s2)
			break;
		    s = s2 + 1;
		    continue;
		}

		char *tmp = (char*) alloca(len + 1);
		memcpy(tmp, s, len);
		tmp[len] = 0;
		return luaL_error(L, "[gtk] gtk.%s not found", tmp);
	    }
	    
	    gv->data[0].v_int = val;
	    break;

	case LUA_TNUMBER:
	    gv->data[0].v_int = lua_tointeger(L, index);
	    break;

	default:
	    return luaL_error(L, "%s GValue: Can't convert Lua type %s to "
		"enum.", msgprefix, lua_typename(L, luatype));
    }

    return 1;
}


/**
 * Convert the value at the given stack position to a lua_Integer.  Accepts
 * integer, string with an appropriate content.
 */
static lua_Integer _to_number(lua_State *L, int type, int index, int *ok)
{

    if (type == LUA_TNUMBER)
	return lua_tointeger(L, index);

    if (type == LUA_TSTRING) {
	const char *s = lua_tostring(L, index);
	char *endptr;
	lua_Integer v = strtol(s, &endptr, 0);
	if (!*endptr)
	    return v;

	// hm... a single character can be converted, but this is not clean.
	// what about "1" - could be converted to 0x01 or 0x31.  Required
	// for the "invisible-char" property of GtkEntry, which is a "guint".
	if (s[1] == 0)
	    return (unsigned char) s[1];

	luaL_error(L, "%s Can't convert string \"%s\" to integer for GValue",
	    msgprefix, s);
    }

    *ok = 0;
    return 0;
}


/**
 * Set a GValue from a Lua stack entry, thereby enforcing a specific data type.
 *
 * NOTE: the GValue is set; be sure to call g_value_unset or simliar on it to
 * avoid refcounting problems.
 * 
 * @param L  Lua State
 * @param index  Lua stack position of the source value
 * @param gv  (output) The GValue to be set
 * @param gtype  The G_TYPE_xxx type that *gv should have
 */
void lg_lua_to_gvalue_cast(lua_State *L, int index, GValue *gv, GType gtype)
{
    int type = lua_type(L, index);
    int ok = 1;
    const char *type_name = NULL;
    typespec_t ts = { 0 };

    /* be optimistic that this type can actually be produced. */
    if (G_IS_VALUE(gv))
	g_value_unset(gv);
    g_value_init(gv, gtype);

    /* Set the GValue depending on the fundamental data type. */
    switch (G_TYPE_FUNDAMENTAL(gtype)) {

	case G_TYPE_BOOLEAN:
	    if (type == LUA_TBOOLEAN)
		gv->data[0].v_int = lua_toboolean(L, index) ? 1: 0;
	    else if (type == LUA_TSTRING) {
		gv->data[0].v_int = _to_boolean(L, index);
	    } else {
		ok = 0;
		break;
	    }
		
	    break;

	// numerical integer types...
	case G_TYPE_INT:
	    gv->data[0].v_int = _to_number(L, type, index, &ok);
	    break;

	case G_TYPE_LONG:
	    gv->data[0].v_long = _to_number(L, type, index, &ok);
	    break;

	case G_TYPE_INT64:
	    gv->data[0].v_int64 = _to_number(L, type, index, &ok);
	    break;

	case G_TYPE_UINT:
	    gv->data[0].v_uint = _to_number(L, type, index, &ok);
	    break;

	case G_TYPE_UINT64:
	    gv->data[0].v_uint64 = _to_number(L, type, index, &ok);
	    break;

	case G_TYPE_ULONG:
	    gv->data[0].v_ulong = _to_number(L, type, index, &ok);
	    break;

	/* if it is an ENUM, use numbers directly, and convert strings */
	case G_TYPE_ENUM:
	    switch (type) {
		case LUA_TSTRING:;
		    const char *s = lua_tostring(L, index);
		    // must zero, because the constant might have fewer bytes
		    gv->data[0].v_int = 0;
		    if (!lg_find_constant(L, &ts, s, -1, &gv->data[0].v_int))
			luaL_error(L, "%s \"%s\" is not an enum", msgprefix, s);
		    break;

		case LUA_TNUMBER:
		    gv->data[0].v_int = lua_tointeger(L, index);
		    break;

		case LUA_TUSERDATA:;
		    const char *name = g_type_name(gv->g_type);
		    ts = lg_find_struct(L, name, 0);
		    struct lg_enum_t *e = lg_get_constant(L, index, ts, 1);
		    gv->data[0].v_int = e->value;
		    break;

		default:
		    /*
		    printf("%s Can't convert Lua type %s to enum.\n",
			msgprefix, lua_typename(L, type));
		    return 0;
		    */
		    ok = 0;
		    break;
	    }
		    
	    break;

	// similar to ENUM, but can be a string like this: A | B | C
	case G_TYPE_FLAGS:
	    _fill_gvalue_flags(L, gv, type, index);
	    break;
	
	case G_TYPE_STRING:
	    // the Lua value might be numeric; lua_tostring converts it to a
	    // string in this case.
	    {
		size_t len;
		char *l_string, *g_string;

		l_string = (char*) lua_tolstring(L, index, &len);
		g_string = (char*) g_malloc(len + 1);
		memcpy(g_string, l_string, len + 1);
		gv->data[0].v_pointer = (void*) g_string;
		gv->data[1].v_uint = 0;	    // free the string later
	    }
	    break;
	
	case G_TYPE_FLOAT:
	    gv->data[0].v_float = _to_double(L, index, &ok);
	    break;
	
	case G_TYPE_DOUBLE:
	    gv->data[0].v_double = _to_double(L, index, &ok);
	    break;
	
	// an object of the correct type must be given.
	case G_TYPE_OBJECT:;
	    struct object *w = (struct object*) lua_touserdata(L, index);
	    if (!w || !w->p) {
		ok = 0;
		break;
	    }

	    // Check that this is actually a object of the correct type.
	    // XXX currently it must be equal; could be a derived object?
	    const char *object_name = lg_get_object_name(w);
	    if (!strcmp(g_type_name(gv->g_type), object_name)) {
		gv->data[0].v_pointer = w->p;
		// We have to increase the refcount!
		g_object_ref_sink(w->p);
		break;
	    }

	    // not found.
	    type_name = object_name;
	    ok = 0;
	    break;

	// A LuaValue?  If so, create a boxed value.
	case G_TYPE_BOXED:;
	    if (gtype == lg_boxed_value_type) {
		void *p = lg_make_boxed_value(L, index);
		gv->data[0].v_pointer = p;
		break;
	    }
	    // fall through - other, unknown boxed types

	default:
	    /*
	    printf("%s GValue: type %d (%d = %s) not supported\n",
		msgprefix, (int) G_TYPE_FUNDAMENTAL(gtype), (int) gtype,
		    g_type_name(gtype));
	    */
	    ok = 0;
    }

    if (!ok) {
	luaL_error(L, "%s fill_gvalue: can't set GType %s from Lua type %s",
	    msgprefix, g_type_name(gtype),
	    type_name ? type_name : lua_typename(L, type));
    }
}


/**
 * Try to convert a value on the Lua stack into a GValue.  The resulting
 * type of the GValue depends on the Lua type.
 *
 * @param L  Lua State
 * @param index  Lua stack position of the input value
 * @param gvalue  Pointer to a GValue structure which must be set to zero
 *  (output)
 * @return  The given "gvalue", if it is filled in, or pointer to an existing
 *  GValue.
 */
GValue *lg_lua_to_gvalue(lua_State *L, int index, GValue *gvalue)
{
    int type = lua_type(L, index);

    switch (type) {
	case LUA_TNIL:
	gvalue->g_type = G_TYPE_INVALID;
	break;

	case LUA_TNUMBER:
	gvalue->g_type = G_TYPE_INT;
	gvalue->data[0].v_int = lua_tonumber(L, index);
	break;

	case LUA_TBOOLEAN:
	gvalue->g_type = G_TYPE_BOOLEAN;
	gvalue->data[0].v_uint = lua_toboolean(L, index) ? 1: 0;
	break;

	case LUA_TSTRING:;
	char *s, *s2;
	size_t len;

	// Note that gvalue->data[1].v_uint is zero, which means that the
	// string value is allocated and must be freed.  See
	// g_value_set_string() in glib/gobject/gvaluetypes.c.
	gvalue->g_type = G_TYPE_STRING;
	s = (char*) lua_tolstring(L, index, &len);
	s2 = (char*) g_malloc(len + 1);	    // final \0
	memcpy(s2, s, len + 1);
	gvalue->data[0].v_pointer = (void*) s2;
	break;

	// userdata can be: enum/flag, GValue, or something else (=unusable)
	case LUA_TUSERDATA:
	lua_getmetatable(L, index);

	// might be an enum/flag?
	lua_getfield(L, LUA_REGISTRYINDEX, ENUM_META);
	if (lua_rawequal(L, -1, -2)) {
	    gvalue->g_type = G_TYPE_LONG;
	    struct lg_enum_t *e = (struct lg_enum_t*) lua_touserdata(L, index);
	    gvalue->data[0].v_long = e->value;
	    lua_pop(L, 2);
	    break;
	}
	lua_pop(L, 1);

	lua_pushliteral(L, "_typespec");
	lua_rawget(L, -2);
	typespec_t ts;
	ts.value = lua_tonumber(L, -1);
	lua_pop(L, 2);
	const char *class_name = lg_get_type_name(ts);

	if (class_name) {
	    if (!strcmp(class_name, "GValue")) {
		// This already is a GValue; just point to it.  It will not
		// be freed in call.c:call_info_free_arg.
		struct object *w = (struct object*) lua_touserdata(L, index);
		return (GValue*) w->p;
	    }
	    luaL_error(L, "%s can't coerce type %s to GValue", msgprefix,
		class_name);
	}

	/* fall through */

	default:
	luaL_error(L, "%s can't coerce Lua type %s to GValue", msgprefix,
	    lua_typename(L, type));
    }

    return gvalue;
}



/*-
 * The GValue at *gv is of a fundamental type.  Push the appropriate value
 * on the Lua stack.  If the type is not handled, a Lua error is raised.
 */
static void _push_gvalue_fundamental(lua_State *L, GValue *gv)
{
    GType type = gv->g_type;
    gchar c;

    // see /usr/include/glib-2.0/gobject/gtype.h for type numbers.
    switch (G_TYPE_FUNDAMENTAL(type)) {
	case G_TYPE_INVALID:
	    lua_pushnil(L);
	    return;

	case G_TYPE_NONE:
	    printf("strange... an argument of type NONE?\n");
	    return;

	// missing: G_TYPE_INTERFACE

	case G_TYPE_CHAR:;
	    c = gv->data[0].v_int;
	    lua_pushlstring(L, &c, 1);
	    return;

	case G_TYPE_UCHAR:;
	    c = (gchar) gv->data[0].v_uint;
	    lua_pushlstring(L, &c, 1);
	    return;

	case G_TYPE_BOOLEAN:
	    lua_pushboolean(L, gv->data[0].v_int);
	    return;

	case G_TYPE_INT:
	    lua_pushnumber(L, gv->data[0].v_int);
	    return;

	case G_TYPE_UINT:
	    lua_pushnumber(L, gv->data[0].v_uint);
	    return;

	case G_TYPE_LONG:
	    lua_pushnumber(L, gv->data[0].v_long);
	    return;

	case G_TYPE_ULONG:
	    lua_pushnumber(L, gv->data[0].v_ulong);
	    return;

	case G_TYPE_INT64:
	    lua_pushnumber(L, gv->data[0].v_int64);
	    return;

	case G_TYPE_UINT64:
	    lua_pushnumber(L, gv->data[0].v_uint64);
	    return;

	// try to determine the correct ENUM/FLAG type.
	case G_TYPE_ENUM:
	case G_TYPE_FLAGS:;
	    if (G_TYPE_IS_DERIVED(type)) {
		typespec_t ts = lg_find_struct(L, g_type_name(type), 0);
		if (ts.value) {
		    lg_push_constant(L, ts, gv->data[0].v_int);
		    return;
		}
	    }
	    lua_pushnumber(L, gv->data[0].v_int);
	    return;

	case G_TYPE_FLOAT:
	    lua_pushnumber(L, gv->data[0].v_float);
	    return;

	case G_TYPE_DOUBLE:
	    lua_pushnumber(L, gv->data[0].v_double);
	    return;

	case G_TYPE_STRING:
	    lua_pushstring(L, (char*) gv->data[0].v_pointer);
	    return;

	case G_TYPE_POINTER:
	    // Some opaque structure.  This is very seldom and it is
	    // not useful to try to override it.  There's a reason for
	    // parameters being opaque...
	    lua_pushlightuserdata(L, (void*) gv->data[0].v_pointer);
	    return;

	// missing: G_TYPE_BOXED
	// missing: G_TYPE_PARAM
	// missing: G_TYPE_OBJECT

	default:
	    luaL_error(L, "_push_gvalue_fundamental: unhandled fundamental "
		"type %d\n", (int) type >> 2);
    }
}



/**
 * A parameter for a callback must be pushed onto the stack, or a return
 * value from Gtk converted to a Lua type.  A value is always pushed; in the
 * case of error, NIL.
 *
 * @param L  Lua State
 * @param gv  The GValue to be pushed
 */
void lg_gvalue_to_lua(lua_State *L, GValue *gv)
{
    if (!gv)
	luaL_error(L, "%s lg_gvalue_to_lua called with NULL data", msgprefix);

    GType gtype = gv->g_type;
    void *data = (void*) &gv->data;

    // fundamental types (char, int, ...) handled here
    if (G_TYPE_IS_FUNDAMENTAL(gtype)) {
	_push_gvalue_fundamental(L, gv);
	return;
    }

    // enum and flags also handled there.
    switch (G_TYPE_FUNDAMENTAL(gtype)) {
	case G_TYPE_ENUM:
	case G_TYPE_FLAGS:
	    _push_gvalue_fundamental(L, gv);
	    return;
    }

    // maybe it's a boxed lua value
    if (gtype == lg_boxed_value_type) {
	lg_get_boxed_value(L, gv->data[0].v_pointer);
	return;
    }


    /* not a fundamental type */
    const char *name = g_type_name(gtype);
    if (!name)
	luaL_error(L, "%s callback argument GType %d invalid", msgprefix,
	    gtype);

    /* If this type is actually derived from GObject, then let make_object
     * find out the exact type itself.  Maybe it is a type derived from the
     * one specified, then better use that.
     */
    int type_of_gobject = g_type_from_name("GObject");
    typespec_t ts = { 0 };
    if (g_type_is_a(gtype, type_of_gobject)) {
	// pushes nil on error.
	lg_get_object(L, * (void**) data, ts, FLAG_NOT_NEW_OBJECT);
	return;
    }
    
    ts = lg_find_struct(L, name, 1);
    if (!ts.value) {
	printf("%s structure not found for callback arg: %s\n",
	    msgprefix, name);
	lua_pushnil(L);
	return;
    }

    /* Find or create a Lua wrapper for the given object. */
    lg_get_object(L, * (void**) data, ts, FLAG_NOT_NEW_OBJECT);
}

#if 0

/**
 * A GValue should be used to set a ffi parameter, which is not a GValue,
 * but of the type that is contained in the GValue.
 */
void lg_gvalue_to_ffi(lua_State *L, GValue *gv, union gtk_arg_types *dest,
    ffi_type **argtype)
{
    ffi_type_lua2ffi[idx](&ar);
}

#endif

