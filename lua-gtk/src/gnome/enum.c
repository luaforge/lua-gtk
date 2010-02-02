/** vim:sw=4:sts=4
 *
 * Handle ENUMs and FLAGs.
 * This is part of lua-gtk, the binding of Gtk2 to Lua.
 *
 * Exported symbols:
 *   lg_push_constant
 *   lg_get_constant
 */

#include "luagnome.h"

// current max length of a type name is 45, plus "const " and ***
#define TYPE_NAME_VAR(varname, ts) char varname[LG_TYPE_NAME_LENGTH]; \
    lg_get_type_name_full(L, ts, varname)



/**
 * Return a string representation of the given ENUM or FLAGS.  It is in the
 * form enumtype:value|value|value
 */
static int enum_tostring(lua_State *L)
{
    struct lg_enum_t *e;
    GEnumValue *ev = NULL;
    luaL_Buffer buf;

    e = (struct lg_enum_t*) luaL_checkudata(L, 1, ENUM_META);
    luaL_buffinit(L, &buf);

    TYPE_NAME_VAR(name, e->ts);
    luaL_addstring(&buf, name);
    luaL_addchar(&buf, ':');

    if (e->gtype != 0) {
	if (e->ts.flag == 1) {
	    gpointer enum_class = g_type_class_ref(e->gtype);
	    ev = g_enum_get_value(enum_class, e->value);
	    g_type_class_unref(enum_class);
	    if (ev) {
		luaL_addstring(&buf, ev->value_name);
	    } else {
		lua_pushnumber(L, e->value);
		luaL_addvalue(&buf);
	    }
	} else if (e->ts.flag == 2) {
	    gpointer flags_class = g_type_class_ref(e->gtype);
	    guint value = e->value;
	    GFlagsValue *fv;
	    int not_first = 0;

	    while (value) {
		fv = g_flags_get_first_value(flags_class, value);
		if (!fv)
		    break;
		if (not_first)
		    luaL_addchar(&buf, '|');
		not_first = 1;
		luaL_addstring(&buf, fv->value_nick ? fv->value_nick
		    : fv->value_name);
		value -= fv->value;
	    }
	}

	// If value is not zero now, then some bits of the flags are
	// not defined.  Don't care about that.
    } else {
	// unregistered enum.  Just show the numeric value.
	lua_pushnumber(L, e->value);
	luaL_addvalue(&buf);
    }

    luaL_pushresult(&buf);

    return 1;
}

/**
 * In order to see the numerical value of ENUM or FLAG, or to compare it
 * with a number, use this method.
 *
 * value = enum_var:tonumber()
 *
 * @luaparam enum
 * @luareturn  the integer value (may be negative)
 */
static int enum_tonumber(lua_State *L)
{
    struct lg_enum_t *e = LUAGNOME_TO_ENUM(L, 1);
    lua_pushnumber(L, (int) e->value);
    return 1;
}



/**
 * Perform an "addition" or "subtraction" on an enum.
 *
 * The enum must actually be a flag field; do a bitwise OR with the
 * parameter, which must be a flags field of the same type.
 *
 * @param mode     0=addition, 1=subtraction
 */
static int enum_add_sub(lua_State *L, int mode)
{
    struct lg_enum_t *e1, *e2;
    unsigned int v1, v2;

    if (lua_type(L, 1) == LUA_TNUMBER) {
	e1 = NULL;
	v1 = lua_tonumber(L, 1);
    } else {
	e1 = LUAGNOME_TO_ENUM(L, 1);
	v1 = e1->value;
    }

    if (lua_type(L, 2) == LUA_TNUMBER) {
	e2 = NULL;
	v2 = lua_tonumber(L, 2);
    } else {
	e2 = LUAGNOME_TO_ENUM(L, 2);
	v2 = e2->value;
    }

    // if both arguments are ENUMs, they must match in type.
    if (e1 && e2 && e1->ts.value != e2->ts.value) {
	TYPE_NAME_VAR(name1, e1->ts);
	TYPE_NAME_VAR(name2, e2->ts);
	return luaL_error(L, "[gtk] type mismatch in flag add: %s vs. %s",
	    name1, name2);
	return 0;
    }

    // one (or both) must be a flag, i.e. a bitfield.
    if ((e1 && e1->ts.flag != 2) || (e2 && e2->ts.flag != 2)) {
	return luaL_error(L, "[gtk] can't add ENUMs of type %s - not a flag.",
	    lg_get_type_name(e1->ts));
	return 0;
    }

    // the result is an enum of this type
    v1 = (mode == 0) ? v1 | v2 : v1 & ~v2;
    lg_push_constant(L, e1 ? e1->ts : e2->ts, v1);
    return 1;
}

static int enum_add(lua_State *L)
{
    return enum_add_sub(L, 0);
}

static int enum_sub(lua_State *L)
{
    return enum_add_sub(L, 1);
}

static int enum_eq(lua_State *L)
{
    struct lg_enum_t *e1, *e2;

    e1 = LUAGNOME_TO_ENUM(L, 1);
    e2 = LUAGNOME_TO_ENUM(L, 2);
    if (e1->ts.value != e2->ts.value) {
	TYPE_NAME_VAR(name1, e1->ts);
	TYPE_NAME_VAR(name2, e2->ts);
	luaL_error(L, "Can't compare different enum types: %s vs. %s",
	    name1, name2);
    }
    lua_pushboolean(L, e1->value == e2->value);
    return 1;
}

/**
 * Use this to check a FLAG
 */
static int enum_mod(lua_State *L)
{
    struct lg_enum_t *e1, *e2;

    e1 = LUAGNOME_TO_ENUM(L, 1);
    e2 = LUAGNOME_TO_ENUM(L, 2);
    if (e1->ts.value != e2->ts.value) {
	TYPE_NAME_VAR(name1, e1->ts);
	TYPE_NAME_VAR(name2, e2->ts);
	luaL_error(L, "Can't compare different enum types: %s vs. %s",
	    name1, name2);
    }
    lua_pushboolean(L, e1->value & e2->value);
    return 1;
}


static const luaL_reg enum_methods[] = {
    {"__tostring", enum_tostring },
    {"__add", enum_add },
    {"__sub", enum_sub },
    {"__eq", enum_eq },
    {"__mod", enum_mod },
    {"tonumber", enum_tonumber },
    { NULL, NULL }
};


/**
 * Create a userdata representing an ENUM value
 *
 * @return 1
 */
int lg_push_constant(lua_State *L, typespec_t ts, int value)
{
    if (!ts.value)
	return luaL_error(L, "%s lg_push_constant called with unset type",
	    msgprefix);
    struct lg_enum_t *e = (struct lg_enum_t*) lua_newuserdata(L,
	sizeof(*e));
    e->value = value;
    e->ts = ts;

    // determine the GType - not all enums are registered with the GType
    // system, especially Cairo ENUMs are not.
    const char *name = lg_get_type_name(ts);
    e->gtype = lg_gtype_from_name(L, modules[ts.module_idx], name);
    if (G_TYPE_IS_ENUM(e->gtype))
	e->ts.flag = 1;
    else if (G_TYPE_IS_FLAGS(e->gtype))
	e->ts.flag = 2;
    else
	e->ts.flag = 0;

    // add a metatable with some methods
    if (luaL_newmetatable(L, ENUM_META)) {
	luaL_register(L, NULL, enum_methods);
	lua_pushliteral(L, "__index");
	lua_pushvalue(L, -2);
	lua_rawset(L, -3);
    }

    lua_setmetatable(L, -2);
    return 1;
}


/**
 * Retrieve the value of an enum on the Lua stack.  Optionally check the
 * enum type.
 */
struct lg_enum_t *lg_get_constant(lua_State *L, int index,
    typespec_t ts, int raise_error)
{
    struct lg_enum_t *e = (struct lg_enum_t*) lua_touserdata(L, index);

    if (!e) {
	if (raise_error)
	    luaL_error(L, "%s enum expected, got %s", msgprefix,
		lua_typename(L, lua_type(L, index)));
	return NULL;
    }

    if (!lua_getmetatable(L, index)) {
	if (raise_error)
	    luaL_error(L, "%s userdata not an enum", msgprefix);
	return NULL;
    }

    lua_getfield(L, LUA_REGISTRYINDEX, ENUM_META);
    if (!lua_rawequal(L, -1, -2)) {
	if (raise_error)
	    luaL_error(L, "%s userdata not an enum", msgprefix);
	lua_pop(L, 2);
	return NULL;
    }
    lua_pop(L, 2);

    if (ts.value && !lg_type_equal(L, e->ts, ts)) {
	if (raise_error) {
	    TYPE_NAME_VAR(name1, ts);
	    TYPE_NAME_VAR(name2, e->ts);
	    luaL_error(L, "%s incompatible ENUM: expected %s (%s.%d), "
		"given %s (%s.%d)", msgprefix,
		name1, modules[ts.module_idx]->name, ts.type_idx,
		name2, modules[e->ts.module_idx]->name, e->ts.type_idx);
	}
	return NULL;
    }

    return e;
}
    

