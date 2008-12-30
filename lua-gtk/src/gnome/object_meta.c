/* vim:sw=4:sts=4
 * Library to use the Gnome family of libraries from Lua 5.1
 * Copyright (C) 2007, 2008 Wolfgang Oertl
 *
 * Functions for the object's meta table.
 *
 * Exported symbols:
 *  lg_object_index
 *  lg_object_newindex
 */

#include "luagnome.h"
#include <string.h>	    /* strlen, strncmp, strcpy, memset, memcpy */


/**
 * Override?  This can be one defined in the gtk_methods[] array, i.e.
 * implemented in C, or one defined in override.lua; these functions
 * must also be inserted into the gtk table.
 *
 * Input stack: 1=unused, [2]=key, [-2]=dest metatable, [-1]=curr metatable
 * Output stack: same on failure (returns 0), or an additional item (returns 1)
 */
static int _check_override(lua_State *L, int module_idx, const char *name)
{
    cmi mi = modules[module_idx];
    if (!mi)
	luaL_error(L, "%s internal error - _check_override called without "
	    "module for %s", msgprefix, name);

    lua_rawgeti(L, LUA_REGISTRYINDEX, mi->module_ref);
    lua_pushstring(L, name);		// module name
    lua_rawget(L, -2);			// module item/null
    lua_remove(L, -2);			// item/null

    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return 0;
    }

    lua_pushvalue(L, 2);	// mt mt item key
    lua_pushvalue(L, -2);	// mt mt item key item
    lua_rawset(L, -5);		// mt mt item	-- was: 3
    return 1;
}

/**
 * An entry has been found.  Store this fact in the object's meta table,
 * and then handle the entry.
 *
 * Called from: _find_element.
 *
 * Stack: [1]=object [2]=key ... [-2]=dest mt [-1]=curr mt
 * Output stack: meta entry added.
 */
static int _found_function(lua_State *L, const char *name, struct func_info *fi)
{
    struct meta_entry *me = (struct meta_entry*) lua_newuserdata(L,
	sizeof(*me) + strlen(name) + 1);
    memset(me, 0, sizeof(*me));
    memcpy(&me->fi, fi, sizeof(me->fi));
    me->fi.name = me->name;
    strcpy(me->name, name);
    lua_pushvalue(L, 2);
    lua_pushvalue(L, -2);   // ... dest mt, curr mt, me, key, me
    lua_rawset(L, -5);	    // was:3
    return 2;		    // ... dest mt, curr mt, me
}

/**
 * Look at the current metatable.  If it contains the desired item, copy it
 * into the base meta table and return 2.
 * 
 * Input stack: 1=object, 2=key, [-2]=dest metatable, [-1]=curr metatable
 *
 * @param L  lua_State
 * @param recursed  true if current metatable is not the object's metatable.
 */
static int _fe_check_metatable(lua_State *L, int recursed)
{
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);	    // was: 4

    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return 0;
    }

    if (recursed) {
	lua_pushvalue(L, 2);	    // mt mt value key
	lua_pushvalue(L, -2);	    // mt mt value key value    -- was:5
	lua_rawset(L, -5);	    // mt mt value  -- was:3
    }

    // return 2 for meta entry (only this is allowed in the metatable)
    return 2;
}


/**
 * Maybe the element being looked for is an attribute of the Gtk object,
 * i.e. part of its C structure.
 *
 * Stack: [1]=object [2]=key [-2]=dest mt [-1]=curr mt
 */
static int _fe_check_struct(lua_State *L, const char *attr_name, typespec_t ts)
{
    const struct struct_elem *se = find_attribute(ts, attr_name);
    if (!se)
	return 0;

    /* Found. Create an appropriate meta entry. */
    struct meta_entry *me = (struct meta_entry*) lua_newuserdata(L,
	sizeof(*me) + strlen(attr_name) + 1);
    memset(me, 0, sizeof(*me));

    ts.type_idx = se->type_idx;
    me->ts = ts;		    // typespec of the structure
    me->se = se;
    strcpy(me->name, attr_name);
    lua_pushvalue(L, 2);	    // mt mt me key
    lua_pushvalue(L, -2);	    // mt mt me key me
    lua_rawset(L, -5);		    // mt mt me	    // was:3
    return 2;
}

/**
 * The class being looked at may implement interfaces; look for these
 * functions, too.
 *
 * Returns: 0=nothing found, 1=found something
 * Stack: [1]=object [2]=key ... [-2]=dest mt [-1]=curr mt
 */
static int _fe_check_interfaces(lua_State *L, const char *attr_name)
{
    guint n_interfaces;
    int i, rc=0;
    const char *class_name;
    GType *gtypes;
    char tmp_name[80];
    struct func_info fi;
    cmi mi;

    /* retrieve the class type, an element of the meta table */
    lua_pushliteral(L, "_gtktype");
    lua_rawget(L, -2);				// in curr mt
    int gtk_type = lua_tonumber(L, -1);
    lua_pop(L, 1);

    // struct object *o = (struct object*) lua_touserdata(L, 1);
    // cmi my_mi = modules[o->ts.module_idx], mi;

    gtypes = g_type_interfaces(gtk_type, &n_interfaces);

    for (i=0; i<n_interfaces; i++) {
	class_name = g_type_name(gtypes[i]);

	// Find that class;  It is perfectly OK not to find that class; at
	// least, it should be in this module's list, but may not be mapped
	// to anything, e.g. Atk not loaded.
	typespec_t ts = lg_find_struct(L, class_name, 1);
	if (!ts.value)
	    continue;

	if (lg_make_func_name(tmp_name, sizeof(tmp_name), class_name,
	    attr_name))
	    break;

	// an override might exist - use it.
	if (_check_override(L, ts.module_idx, tmp_name)) {
	    rc = 1;
	    break;
	}

	// regular function in that module?
	mi = modules[ts.module_idx];
	if (lg_find_func(L, mi, tmp_name, &fi)) {
#ifdef LUAGTK_win32
found_func:
#endif
	    rc = _found_function(L, tmp_name, &fi);
	    if (rc == 2) {
		// Try to find the structure for this interface.  This is not
		// always possible, e.g. GtkEditableIface doesn't exist.  If
		// found, writing to it is possible.
		char *iface_name = g_malloc(strlen(class_name) + 10);
		sprintf(iface_name, "%sIface", class_name);
		typespec_t ts2 = lg_find_struct(L, iface_name, 1);
		g_free(iface_name);	// ok
		struct meta_entry *me = (struct meta_entry*) lua_touserdata(L,
		    -1);
		if (ts2.value)
		    me->iface_ts = ts2;
		me->iface_type_id = gtypes[i];
	    }
	    break;
	}

#ifdef LUAGTK_win32
	strcat(tmp_name, "_utf8");
	if (lg_find_func(L, mi, tmp_name, &fi))
	    goto found_func;
#endif
    }

    g_free(gtypes); // ok
    return rc;
}


/**
 * Look in the object's environment for a given key.
 *
 * @luaparam stack[1]  The object
 * @luaparam stack[2]  Key
 * @luaparam stack[-1]  Metatable of the object
 * @luareturn  The value, or nothing
 */
static int _fe_check_env(lua_State *L)
{
    lua_getfenv(L, 1);		// ... env
    lua_pushvalue(L, 2);		// ... env k
    lua_rawget(L, -2);		// ... env value/nil
    lua_remove(L, -2);		// ... value/nil
    if (!lua_isnil(L, -1))
	return 1;

    lua_pop(L, 1);			// stack back to how it was
    return 0;
}

/**
 * Look for a function with the desired name.
 *
 * Input stack: [1]=object [2]=key [-2]=object's metatable [-1]=curr metatable
 * Returns 0 if not found, >0 otherwise.
 */
static int _fe_check_function(lua_State *L, int recursed, typespec_t ts)
{
    const char *class_name, *attr_name;
    char tmp_name[80];
    struct func_info fi;

    /* check for a (not yet mapped) function? */
    attr_name = lua_tostring(L, 2);
    class_name = lg_get_type_name(ts);
    if (lg_make_func_name(tmp_name, sizeof(tmp_name), class_name, attr_name))
	return 0;

    if (_check_override(L, ts.module_idx, tmp_name))
	return 1;

    // look in the module that handles that type
    cmi mi = modules[ts.module_idx];
    if (lg_find_func(L, mi, tmp_name, &fi))
	return _found_function(L, tmp_name, &fi);

    /* maybe an UTF8 variant for Windows? */
#ifdef LUAGTK_win32
    strcat(tmp_name, "_utf8");
    if (lg_find_func(L, mi, tmp_name, &fi))
	return _found_function(L, tmp_name, &fi);
#endif

    /* maybe a gdk_ function for GdkSomething objects? */
    /* XXX - HACK */
    #if 0
    if (!recursed && !strncmp(class_name, "Gdk", 3)) {
	sprintf(tmp_name, "gdk_%s", attr_name);
	if (lg_find_func(L, mi, tmp_name, &fi))
	    return _found_function(L, tmp_name, &fi);
    }
    #endif

    return 0;
}


/**
 * Search an object's class and parent classes for an attribute.
 *
 * @luaparam stack[1] object
 * @luaparam stack[2] key
 * @luaparam stack[-2] mt1  The object's metatable
 * @luaparam stack[-1] mt2  Metatable of object or one of its parents.
 */
static int _fe_recurse(lua_State *L, int must_exist)
{
    int recursed = 0, rc;
    const char *attr_name;
    typespec_t ts, top_ts;

    attr_name = lua_tostring(L, 2);

    for (;;) {
	/* retrieve the typespec of the class, an element of the meta table */
	lua_pushliteral(L, "_typespec");
	lua_rawget(L, -2);
	if (lua_isnil(L, -1))
	    return luaL_error(L, "internal error: metatable of an object has "
		"no _typespec attribute.");
	ts.value = lua_tonumber(L, -1);
	lua_pop(L, 1);
	if (!recursed)
	    top_ts = ts;

	// may be stored in the metatable from previous lookups (optimization),
	// or an item with arbitrary key stored by the user, possibly
	// overriding functions.
	rc = _fe_check_metatable(L, recursed);
	if (rc)
	    return rc;

	// catch read accesses to structure elements
	rc = _fe_check_struct(L, attr_name, ts);
	if (rc)
	    return rc;

	// may be a function name in the form gtk_some_thing_method_name
	rc = _fe_check_function(L, recursed, ts);
	if (rc)
	    return rc;

	// check functions of all interfaces of the class
	rc = _fe_check_interfaces(L, attr_name);
	if (rc)
	    return rc;

	// replace [-1] with base class, if any.
	lua_pushliteral(L, "_parent");
	lua_rawget(L, -2);	// was: 4
	if (lua_isnil(L, -1)) {
	    lua_pop(L, 1);
	    break;
	}

	lua_remove(L, -2);	// was: 4
	recursed = 1;
    }

    // Last try: the method name can be given completely in case of ambiguities
    cmi mi = modules[top_ts.module_idx];
    struct func_info fi;
    if (lg_find_func(L, mi, attr_name, &fi))
	return _found_function(L, attr_name, &fi);

    /* Give up.  Note that this is not an error when called from
     * gtk_newindex.  Shows the class of the object. */
    if (must_exist) {
	struct object *o = (struct object*) lua_touserdata(L, 1);
	return luaL_error(L, "%s %s.%s not found.", msgprefix,
	    lg_get_object_name(o), attr_name);
    }
    return 0;
}


/**
 * Try to access one element of an array.
 *
 * @param L  Lua State
 * @param o  The object (also on Lua Stack position 1)
 */
static int _array_access(lua_State *L, struct object *o)
{
    int index = lua_tonumber(L, 2);
    lua_settop(L, 1);

    // this must be a array.
    if (o->array_size == 0)
	luaL_error(L, "%s not an array", msgprefix);

    // access to element #1 is easy - it's the object itself.
    if (index == 1)
	return 1;

    if (index < 1 || index > o->array_size)
	luaL_error(L, "%s index %d is out of bounds", msgprefix, index);

    type_info_t ti = lg_get_type_info(o->ts); // OK
    if (ti->st.genus == GENUS_NON_NATIVE)
	luaL_error(L, "%s access to non-native type %d in module %s",
	    msgprefix, o->ts.type_idx, modules[o->ts.module_idx]->name);

    int struct_size = ti->st.struct_size;
    lg_get_object(L, o->p + (index - 1) * struct_size, o->ts,
	FLAG_NOT_NEW_OBJECT | FLAG_ARRAY_ELEMENT);

    return 1;
}


/**
 * Look for a method or attribute of the given object.
 *
 * It handles accesses to methods and attributes found in this class or any
 * base class.  Once the method or attribute has been found, it is inserted
 * into the object's table to avoid looking it up again.
 *
 * Input Stack: 1=object, 2=key
 * Output Stack: depends on the return value.
 *
 * @param L  lua_State
 * @param must_exist  Set to 1 to print an error message on failure
 * @return
 *	0	nothing found
 *	1	found an entry or function (returned on the stack)
 *	2	found a meta entry (meta entry returned)
 *	-1	other error
 */
static int _find_element(lua_State *L, int must_exist)
{
    struct object *w;
    const char *attr_name;
    int type;

    /* check arguments. */
    if (lua_type(L, 1) != LUA_TUSERDATA)
	return luaL_error(L, "find_element called on something other than "
	    "userdata.\n");

    // can't be NULL - it's not a lightuserdata.
    w = (struct object*) lua_touserdata(L, 1);

    if (!lua_getmetatable(L, 1))
	return luaL_error(L, "find_element called with a userdata without "
	    "metatable - can't be an object.\n");

    type = lua_type(L, 2);
    switch (type) {
	case LUA_TNUMBER:
	    return _array_access(L, w);
	
	case LUA_TSTRING:
	    attr_name = lua_tostring(L, 2);
	    break;
	
	default:
	    return luaL_argerror(L, 2, "key must be string");
    }

    if (!w->p) {
	printf("%s access to %s.%s on NULL object\n",
	    msgprefix, lg_get_object_name(w), attr_name);
	lua_pop(L, 1);
	return -1;
    }

    // Stack: [1]=w [2]=key [-1]=mt.  Have a look at the object's environment.
    if (_fe_check_env(L))
	return 1;

    /* Duplicate the metatable; [-2] is the metatable of the object, and [-1]
     * is the current metatable as we ascend the object hierarchy. */
    lua_pushvalue(L, -1);

    /* stack: 1=object, 2=key, -2=destination metatable, -1=current metatable */
    return _fe_recurse(L, must_exist);
}





/**
 * Given a pointer to a structure and the description of the desired element,
 * push a value onto the Lua stack with this item.
 *
 * Returns the number of pushed items, i.e. 1 on success, 0 on failure.
 */
static int _push_attribute(lua_State *L, typespec_t ts,
    const struct struct_elem *se, unsigned char *ptr)
{
    const struct ffi_type_map_t *arg_type;
    int idx;

    // the type might be non-native.
    ts.type_idx = se->type_idx;
    ts = lg_type_normalize(L, ts);
    arg_type = lg_get_ffi_type(ts);

    idx = arg_type->structconv_idx;
    if (idx && ffi_type_struct2lua[idx]) {
	struct argconvs_t ar;
	ar.L = L;
	ar.se = se;
	ar.ptr = ptr;
	ar.ts = ts;
	return ffi_type_struct2lua[idx](&ar);
    }

    return luaL_error(L, "%s unhandled attribute type %s (%s.%s)\n",
	msgprefix, FTYPE_NAME(arg_type), lg_get_type_name(ts),
	lg_get_struct_elem_name(ts.module_idx, se));
}


/**
 * A meta entry is on the top of the stack; use it to retrieve the method
 * pointer or attribute value.
 *
 * Stack: 1=object, 2=key, 3=dest metatable, 4=current metatable,... meta entry
 */
static int _read_meta_entry(lua_State *L)
{
    /* An override, built in or set by the user -- just return it. */
    if (lua_type(L, -1) != LUA_TUSERDATA)
	return 1;

    /* For functions, set up a c closure with one upvalue, which is the pointer
     * to the function info */
    const struct meta_entry *me = lua_touserdata(L, -1);
    if (me->ts.value == 0)
	return lg_push_closure(L, &me->fi, 0);

    /* otherwise, handle attribute access */
    struct object *o = (struct object*) lua_touserdata(L, 1);
    return _push_attribute(L, me->ts, me->se, o->p);
}


/**
 * __index function for the metatable used for userdata (objects).  This is
 * to access a method or an attribute of the class, or a value stored by
 * the user with an arbitrary key.
 *
 * @luaparam object  The Lua object (a userdata of type struct object) to
 *   examine
 * @luaparam key  The key to look up
 * @luareturn  The resulting object, or nothing in case of failure.  It can
 *   be a function, a meta entry describing a structure element, or any
 *   object that the user stored.
 */
int lg_object_index(lua_State *L)
{
    int rc;

    rc = _find_element(L, 1);

    /* Stack: 1=object, 2=key, 3=metatable, 4=metatable,
     * 5=func or meta entry (if found) */
    switch (rc) {
	case 0:
	case 1:
	    return rc;
	
	case 2:
	    /* meta entry */
	    return _read_meta_entry(L);
	
	default:
	    printf("%s invalid return code %d from find_element\n", msgprefix,
		rc);
	    return 0;
    }
}

/**
 * Try to overwrite a function, which is possible if it is in the virtual
 * table of an interface.
 *
 * @param L  Lua State
 * @param index  Stack position with a closure object
 */
static int _try_overwrite_function(lua_State *L, int index)
{
    const struct meta_entry *me = lua_touserdata(L, -1);
    struct object *w = (struct object*) lua_touserdata(L, 1);
    const char *name = lua_tostring(L, 2);
    struct argconvs_t ar;

    // only virtual functions of an interface can be set.
    if (!me->iface_ts.value)
	return luaL_error(L, "%s overwriting method %s.%s not supported.",
	    msgprefix, lg_get_object_name(w), name);

    const struct struct_elem *se = find_attribute(me->iface_ts, name);
    if (G_UNLIKELY(!se))
	return luaL_error(L, "%s attribute %s.%s not found",
	    msgprefix, lg_get_type_name(me->iface_ts), name);

    typespec_t ts2 = me->iface_ts;
    ts2.type_idx = se->type_idx;
    const struct ffi_type_map_t *arg_type = lg_get_ffi_type(ts2);
    int idx = arg_type->structconv_idx;
    if (!idx || !ffi_type_lua2struct[idx])
	return luaL_error(L, "%s can't set closure %s.%s - not implemented.",
	    msgprefix, lg_get_type_name(me->iface_ts), name);

    // set the function pointer in the object's interface table.
    void *p = G_TYPE_INSTANCE_GET_INTERFACE(w->p, me->iface_type_id, void);

    ar.L = L;
    ar.ts = me->iface_ts;
    ar.se = se;
    ar.ptr = p;
    ar.index = index; // -1;

    ffi_type_lua2struct[idx](&ar);
    // lua_pop(L, 1); XXX is that OK?

    // not used.
    return 0;
}


/**
 * Assignment to an attribute of a structure.  Must not be a built-in
 * method, but basically could be...
 * Stack: 1=object, 2=key, ... [-1]=meta entry
 *
 * @param index  Lua stack position where the value is at
 */
static int _write_meta_entry(lua_State *L, int index)
{
    const struct meta_entry *me = lua_touserdata(L, -1);
    struct object *w = (struct object*) lua_touserdata(L, 1);

    /* the meta entry must describe a structure element, not a method. */
    if (G_UNLIKELY(me->ts.value == 0))
	return _try_overwrite_function(L, index);

    /* write to attribute using a type-specific handler */
    typespec_t ts = me->ts;
    ts.type_idx = me->se->type_idx;
    ts = lg_type_normalize(L, ts);
    const struct ffi_type_map_t *arg_type = lg_get_ffi_type(ts);
    int idx = arg_type->structconv_idx;

    if (idx && ffi_type_lua2struct[idx]) {
	struct argconvs_t ar;
	ar.L = L;
	ar.ts = me->ts;
	ar.se = me->se;
	ar.ptr = w->p;
	ar.index = index;
	return ffi_type_lua2struct[idx](&ar);
    }

    /* no write operation defined for this type */
    return luaL_error(L, "%s can't write %s.%s (unsupported type %s.%d = %s)",
	msgprefix, lg_get_object_name(w),
	lg_get_struct_elem_name(me->ts.module_idx, me->se),
	modules[me->ts.module_idx]->name,
	me->ts.type_idx,
	FTYPE_NAME(arg_type));
}



/**
 * Set existing attributes of an object, or arbitrary values.
 * The environment of the userdata will be used to store additional values.
 *
 * Input stack: 1=object, 2=key, 3=value
 */
int lg_object_newindex(lua_State *L)
{
    /* check parameters */
    if (lua_gettop(L) != 3) {
	printf("%s gtk_object_newindex not called with 3 parameters\n",
	    msgprefix);
	return 0;
    }

    /* Is this an attribute of the underlying object? */
    int rc = _find_element(L, 0);

    switch (rc) {
	case -1:
	    return 0;

	case 2:
	    _write_meta_entry(L, 3);
	    return 0;
    }

    /* Not found, or existing entry in the object's environment table.  In both
     * cases store the value in the environment table. */

    lua_getfenv(L, 1);				// w k v env

    /* Is this the default empty table?  If so, create a new one private to
     * this object. */
    lua_getglobal(L, LUAGTK_TBL);
    lua_getfield(L, -1, LUAGTK_EMPTYATTR);	// w k v env gtk ea
    if (lua_equal(L, -1, -3)) {
	lua_newtable(L);			// w k v env gtk ea t
	lua_pushvalue(L, -1);			// w k v env gtk ea t t
	lua_setfenv(L, 1);			// w k v env gtk ea t
    } else {
	lua_pop(L, 2);				// w k v env
    }

    /* the top of the stack now has the table where to put the data */
    lua_replace(L, 1);				// env k v [...]
    lua_settop(L, 3);				// env k v
    lua_rawset(L, 1);				// env 

    return 0;
}


