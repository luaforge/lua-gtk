/* vim:sw=4:sts=4
 * Library to use the Gnome family of libraries from Lua 5.1
 * Copyright (C) 2007, 2009 Wolfgang Oertl
 *
 * Handle GObject derived objects.
 *
 * Exported symbols:
 *   lg_get_object
 *   lg_check_object
 *   lg_invalidate_object
 */

#include "luagnome.h"
#include <string.h>

static struct object *_make_object(lua_State *L, void *p, typespec_t ts,
    int flags);
static int _get_object_meta(lua_State *L, typespec_t ts);

/**
 * The Lua stack should contain a proxy object at the given stack position,
 * verify this.
 *
 * @param L  Lua state
 * @param index  Stack position
 * @return  Pointer to the object, or NULL on error.
 */
struct object *lg_check_object(lua_State *L, int index)
{
    // must be a userdata
    if (lua_type(L, index) != LUA_TUSERDATA)
	return NULL;

    // must have a metatable
    lua_getmetatable(L, index);
    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return NULL;
    }

    // the metatable must have this entry
    lua_getfield(L, -1, "_typespec");
    if (lua_isnil(L, -1)) {
	lua_pop(L, 2);
	return NULL;
    }
    typespec_t ts;
    ts.value = lua_tonumber(L, -1);
    lua_pop(L, 2);

    struct object *o = (struct object*) lua_touserdata(L, index);
    if (o->ts.value != ts.value)
	luaL_error(L, "%s lg_check_object - typespec doesn't match",
	    msgprefix);

    return o;
}

/**
 * Update/remove the entry in objects, which maps the library object's address
 * to the address of one of the aliases.
 *
 * @param L  Lua State
 * @param p  Pointer to the object
 * @param o  The object to store for that pointer; NULL to remove the entry.
 * @param old_o  The expected current reference of p; may be NULL.
 */
static void _set_object_pointer(lua_State *L, void *p, struct object *o,
    struct object *old_o)
{
    lua_getglobal(L, LUAGNOME_TBL);
    lua_getfield(L, -1, LUAGNOME_WIDGETS);	// gnome objects

    // Check that the entry in objects currently points to old_o.  If not,
    // don't update.
    if (old_o) {
	lua_pushlightuserdata(L, p);
	lua_rawget(L, -2);
	if (lua_topointer(L, -1) != old_o) {
	    /*
	    fprintf(stderr, "NOT setting object[%p] = %d (%d != %d)\n", p, ref,
		lua_tointeger(L, -1), old_ref);
	    */
	    lua_pop(L, 3);
	    return;
	}
	lua_pop(L, 1);
    }

    lua_pushlightuserdata(L, p);	    // gnome objects *p
    if (o)
	lua_pushlightuserdata(L, o);	    // gnome objects *p *o
    else
	lua_pushnil(L);

    lua_rawset(L, -3);
    lua_pop(L, 2);
}


/**
 * Get the address of one of the object's aliases.
 *
 * @param L  Lua State
 * @param p  Pointer to the object to find an alias for.
 * @return  the address, or -1 if not found.
 */
static struct object *_get_object_ref(lua_State *L, void *p)
{
    struct object *o = NULL;
    // int ref_nr = -1;

    lua_getglobal(L, LUAGNOME_TBL);		// gnome
    lua_getfield(L, -1, LUAGNOME_WIDGETS);	// gnome objects
    lua_pushlightuserdata(L, p);		// gnome objects p
    lua_rawget(L, -2);				// gnome objects *o
    if (!lua_isnil(L, -1))
	o = (struct object*) lua_topointer(L, -1);
	// ref_nr = lua_tonumber(L, -1);
    lua_pop(L, 3);				// stack empty again

    return o; // ref_nr;
}


/**
 * A Lua object is to be garbage collected, but it is not the only entry for
 * this memory location.  Remove this one from the circular list.
 *
 * @param o       The object to release
 *
 * o2: object being looked at
 */
static void _alias_unlink(lua_State *L, struct object *o)
{
    struct object *o2, *o3;

    /* Find the item o2 in the circular list with o2->next == o, and
     * remove "o" from this list. */
    for (o2=o; o2->next != o; o2 = o2->next)
	/* empty */ ;
    o2->next = (o->next == o2) ? NULL : o->next;

    /* If the entry in objects points to "o", change it to o2 */
    o3 = _get_object_ref(L, o2->p);
    if (o3 == o)
	_set_object_pointer(L, o2->p, o2, 0);

#if 0





    // what is the current reference in objects?
    curr_ref = _get_object_ref(L, o->p);

    // Find the item o2 of the circular list, which is just before o.  This
    // involves walking the whole list until o2->next == o.  At the same time
    // check whether any of the items on the list currently holds the reference
    // from gtk.objects.
    for (;;) {
	if (o2->own_ref == curr_ref)
	    have_ref = 1;
	if (o2->next == o)
	    break;
	o2 = o2->next;
    }

    // remove o from the list
    o2->next = (o->next == o2) ? NULL : o->next;

    // If this group "owns" the entry in gtk.objects, set it to o2, if it
    // currently points to o.  Note that o2 might not be present in
    // gtk.object_aliases either due to GC.
    if (have_ref && o2->own_ref != curr_ref)
	_set_object_pointer(L, o2->p, o2->own_ref, 0);
#endif
}


/**
 * When a Lua object is garbage collected, decrease the reference count of
 * the associated library object, too.  This may cause the library object to be
 * freed.
 *
 * Note that for a given library object, multiple Lua objects can exist, having
 * different types (which should be related to each other, of course).  Each
 * such Lua proxy object can have multiple Lua references, but holds only
 * one reference to the underlying library object.
 */
static int lg_object_gc(struct lua_State *L)
{
    struct object *w = (struct object*) lua_touserdata(L, 1);

    // sanity check
    if (!w) {
	printf("%s Error: lg_object_gc on a NULL pointer\n", msgprefix);
	return 0;
    }

    // The pointer must not be NULL, unless it is deleted.
    if (!w->p && !w->is_deleted) {
	printf("%s Error: lg_object_gc: pointer is NULL (%p, %s)\n",
	    msgprefix, w, lg_get_object_name(w));
	return 0;
    }

    // optionally show some debugging info
    if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_MEMORY)) {
	// find the entry in objects
	// int ref_nr = _get_object_ref(L, w->p);
	int ref_count = lg_get_refcount(L, w);
	struct object_type *wt = lg_get_object_type(L, w);

	// Lua object address - library object address - object_type -
	//   current reference counter - class name -
	//   reference in gtk.object_aliases for this Lua object -
	//   ref of next alias (if applicable) -
	//   reference for the address w->p in gtk.objects
	fprintf(stderr, "%p/%p GC %s refcnt=%d %s\n", w, w->p,
	    wt->name, ref_count, lg_get_object_name(w));
    }

    // If other aliases exist, remove this one from the linked list; otherwise,
    // unset the entry in gtk.objects.
    if (w->next)
	_alias_unlink(L, w);

    // Try to remove this object's entry in aliases; none exists if
    // this is a stack entry.
    _set_object_pointer(L, w->p, NULL, w);

    // decrease the refcount of the library object
    lg_dec_refcount(L, w);
    return 0;
}


/**
 * A object has been freed and must not be accessed anymore.  Invalidate the
 * object proxy and all aliases.
 * It should have an entry in objects, which will be removed too.
 *
 * XXX seems not to be correct.  if multiple aliases exist, remove just this
 * from the circular list and set the pointer in "objects" to one of the
 * others.
 */
void lg_invalidate_object(lua_State *L, struct object *o)
{
    void *p = o->p;

    for (;;) {
	o->p = NULL;
	o->is_deleted = 1;

	o = o->next;
	if (!o || !o->p)
	    break;
    }

    _set_object_pointer(L, p, NULL, NULL);
}


/**
 * A meta table for a class has been created on the stack.  Now
 * try to find the base class and call _get_object_meta for it, too.
 *
 * @param L  Lua State
 * @param type_nr  The GType of the class to find the parent for
 *
 * Input stack: metaclass
 * Output stack: metaclass
 *
 * @return 1 on success, 0 otherwise
 */
static int _get_object_meta_parent(lua_State *L, GType type_nr)
{
    const char *parent_name;
    GType parent_type_nr;
    GTypeQuery query;
    query.type_name = NULL;
    int rc;
    typespec_t ts;

    /* determine the name of the parent class, if any */
    parent_type_nr = g_type_parent(type_nr);
    if (!parent_type_nr) {
	/* printf("%s no parent for type 0x%x\n", msgprefix, type_nr); */
	return 1;
    }

    parent_name = g_type_name(parent_type_nr);
    /*
    printf("%s parent 0x%x -> 0x%x %s\n", msgprefix, type_nr, parent_type_nr,
	parent_name);
    */
    if (!parent_name) {
	fprintf(stderr, "%s Unknown GType 0x%x, supposed parent of %s\n",
	    msgprefix, (unsigned int) parent_type_nr, g_type_name(type_nr));
	return 1;
    }

    /* Get LuaGnome description of this structure.  It might not exist, as
     * abstract, empty base classes like GInitiallyUnowned or GBoxed are
     * not known to LuaGnome.  Also, when a base class should be handled by
     * another module, which doesn't have it or isn't loaded, this fails
     * in the same way. */
    ts = lg_find_struct(L, parent_name, 0);

    if (!ts.value) {
	/* Might be a non-native type of this module; it could be looked
	 * for by the hash value; on the other hand, non-native types are
	 * not registered anywhere, so a linear search would be required
	 * on the type list.  If found, indicates a problem; the non-native
	 * type should exist in another module. */
	if (!strcmp(parent_name, "GBoxed"))
	    return 1;
	printf("%s warning: type not found: %s\n", msgprefix, parent_name);
	return 1;
    }

    /* the parent class might actually be handled by another module. */
    ts = lg_type_normalize(L, ts);

    rc = _get_object_meta(L, ts);
    if (rc == 1) {
	/* add _parent -- used by _fe_recurse to climb up the hierarchy */
	lua_pushliteral(L, "_parent");	    // meta parentmeta name
	lua_insert(L, -2);		    // meta name parentmeta
	lua_rawset(L, -3);		    // meta
    }

    return 1;
}

/**
 * Test two objects for equality.  As just a single proxy object should
 * exist for a given object, this shouldn't be required; but in certain
 * situations this could happen, so here it is.
 */
static int l_object_compare(lua_State *L)
{
    struct object *w1 = (struct object*) lua_touserdata(L, 1);
    struct object *w2 = (struct object*) lua_touserdata(L, 2);
    return w1->p == w2->p;
}

/**
 * Return the object's type name.
 */
static int l_object_get_type(lua_State *L)
{
    struct object *o = (struct object*) lua_touserdata(L, 1);
    // GType gtype = G_TYPE_FROM_INSTANCE(o->p);
    // lua_pushstring(L, g_type_name(gtype));
    lua_pushstring(L, lg_get_object_name(o));
    return 1;
}


static const luaL_reg object_methods[] = {
    { "__index",    lg_object_index },
    { "__newindex", lg_object_newindex },
    { "__tostring", lg_object_tostring },
    { "__gc",	    lg_object_gc },
    { "__eq",	    l_object_compare },
    { "lg_get_type",l_object_get_type },
    { NULL, NULL }
};

/**
 * Given the type, retrieve or create the metaclass for this type of object.
 * If the given object type has a base class, recurse to make that, too.
 *
 * Stack input: nothing
 * Returns: 0 on error, or 1 on success.
 * Stack output: on success: the metaclass; otherwise, nothing.
 */
static int _get_object_meta(lua_State *L, typespec_t ts)
{
    const char *type_name = lg_get_type_name(ts);

    lua_getglobal(L, LUAGNOME_TBL);
    lua_getfield(L, -1, LUAGNOME_METATABLES);
    lua_remove(L, -2);				// _meta_tables
    lua_pushstring(L, type_name);		// _meta_tables name
    lua_rawget(L, -2);				// _meta_tables meta|nil

    if (!lua_isnil(L, -1)) {
	lua_remove(L, -2);			// meta
	return 1;
    }
    lua_pop(L, 1);				// _meta_tables

    /* The meta table for this structure (i.e. class) doesn't exist yet.
     * Create it with __index, _typespec, _parent, and store
     * in _meta_tables. */
    lua_newtable(L);				// _meta_tables t
    lua_pushstring(L, type_name);		// _meta_tables t name
    lua_pushvalue(L, -2);			// _meta_tables t name t
    lua_rawset(L, -4);				// _meta_tables t
    lua_remove(L, -2);				// t

    luaL_register(L, NULL, object_methods);

    /* store the structure number and the class name */
    lua_pushliteral(L, "_typespec");
    lua_pushnumber(L, ts.value);
    lua_rawset(L, -3);

    /* Determine the GType.  Structures which are not registered in the GType
     * system, e.g. GdkEvent, are not found. */
    GType type_nr = lg_gtype_from_name(L, modules[ts.module_idx],
	type_name);
    if (!type_nr)
	return 1;

    lua_pushliteral(L, "_gtktype");
    lua_pushnumber(L, type_nr);
    lua_rawset(L, -3);

    return _get_object_meta_parent(L, type_nr);
}



/**
 * A Lua object for a given library object (identified by its address) has been
 * found.  Check the address, and the type, and look for an alias with the
 * requested type.
 *
 * Returns:
 *  0 ... success
 *  1 ... error (NIL on top of stack, return that)
 *  2 ... type mismatch; need to create new Lua object
 *
 * Lua stack:
 *  [-3]=objects [-2]=aliases [-1]=w
 *
 * w may be replaced with another object (alias), but otherwise the Lua stack
 * remains unchanged.
 */
static int _find_alias(lua_State *L, void *p, typespec_t ts)
{
    struct object *w = (struct object*) lua_touserdata(L, -1), *w_start;

    if (!w) {
	printf("%s ERROR: _find_alias with nil for object at %p\n",
	    msgprefix, p);
	return 1;
    }

    w_start = w;
    do {
	// This object proxy is not new.
	w->is_new = 0;

	// internal check; all aliases must of course point to the same object
	if (G_UNLIKELY(w->p != p)) {
	    
	    // can happen when gnome.destroy was used
	    if (w->p == NULL && w->is_deleted) {
		lua_pop(L, 1);
		lua_pushnil(L);
		return 2;
	    }

	    return luaL_error(L, "%s internal error: Lua object %p should "
		"point to %p, but points to %p", msgprefix, w, p, w->p);
	}

	// don't care about the type?  Always OK.  Note that module_idx might
	// be set.
	if (!ts.type_idx)
	    goto found;

	/* Verify that the type matches.  It is possible to have different
	 * object types at the same address, e.g. GdkEvent. */
	if (ts.value == w->ts.value)
	    goto found;
	
	// XXX determine equivalents of ts in other modules

	// no chained next item - failure
	w = w->next;
	if (!w)
	    break;

    } while (w != w_start);

    // No more chained entries exist.  Return the error to _reuse_object,
    // which then adds another alias.
    return 2;

found:
    if (w == w_start)
	return 0;

    // We used the pointers to get to the Lua object.  To have it on
    // the Lua stack, we need to use the mapping of address to it in the
    // table "aliases".  It is a weak table, so the entry might have
    // been removed before garbage collection.
    lua_pushlightuserdata(L, w);	// objects aliases w *w2
    lua_rawget(L, -3);			// objects aliases w w2

    // If the entry in aliases has already been removed, stay with the
    // previously found alias and add a new alias there.
    if (lua_isnil(L, -1)) {
	lua_pop(L, 1);
	return 2;
    }

    // The entry in aliases still existed (usual case), so use the Lua object.
    lua_remove(L, -2);			// objects aliases w2
    return 0;
}


/**
 * Determine whether p points to something on the stack.
 *
 * I don't want to create reusable Lua proxy objects for library objects on the
 * stack.  Such objects are usually given to callbacks (e.g. a GdkEvent), don't
 * have refcounting, and will go away when returning from the callback.
 *
 * The user must still take care not to keep the Lua proxy object around.
 * Accessing the same address again (with lg_get_object) will return a new
 * Lua object.
 *
 * @param p  Pointer to a memory location
 * @return  true if p is on the stack
 */
static inline int _is_on_stack(void *p)
{
    volatile char c[30];    // large enough so it can't be in registers.
    long int ofs = ((char*)p) - c;
    if (ofs < 0)
	ofs = -ofs;
    return ofs < 36000;
}


/**
 * A object has been found for the given address.  It is on the Lua stack;
 * check that it matches the requested type.  If not, make a new alias.
 *
 * Lua stack: [-3]objects [-2]object_aliases [-1]w
 *
 * @param L  Lua State
 * @param p  Pointer to the object
 * @param ts  Requested type; if 0, use whatever type it has
 * @param flags  Extra flags, see FLAG_NOT_NEW_OBJECT etc.
 */
static void _reuse_object(lua_State *L, void *p, typespec_t ts, int flags)
{
    // Match, or complete failure -> return.  Doesn't change Lua stack,
    // but might replace the "w" object on the top with NIL or something else.
    if (_find_alias(L, p, ts) != 2)
	return;

    // This object obviously already exists, so unset FLAG_NEW_OBJECT.
    struct object *o2 = _make_object(L, p, ts, flags & ~FLAG_NEW_OBJECT);

    if (G_UNLIKELY(o2 == (void*) -1)) {
	lua_pop(L, 1);			    // replace w with nil
	lua_pushnil(L);
	return;
    }
	
    // objects object_aliases w1 w2
    if (o2) {
	// The old object, that already existed (with the wrong type)
	struct object *w1 = (struct object*) lua_touserdata(L, -2);

	// this is the new object; same as o2!
	struct object *w2 = (struct object*) lua_touserdata(L, -1);

	// add to circular list
	w2->next = w1->next ? w1->next : w1;
	w1->next = w2;

	if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_MEMORY))
	    fprintf(stderr, "%p %p alias %s for %p %s\n",
		w2, w2->p, lg_get_object_name(w2), w1,
		lg_get_object_name(w1));
    }

    lua_remove(L, -2);				// objects aliases w2
}



/**
 * Create or find a Lua proxy object for the object or structure at the given
 * address for later usage in Lua scripts.  If this object was already
 * registered with a different typespec, create a new alias.
 *
 * @param L  Lua state
 * @param p  Pointer to the object or structure
 * @param ts  Type of the object at *p, or 0 for auto detection.
 * @param flags  FLAG_NEW_OBJECT if this is a newly allocated/created object;
 *	FLAG_ALLOCATED if this object was created by g_slice_alloc and doesn't
 *	have refcounting.  FLAG_ARRAY if this was allocated by g_malloc and
 *	contains more than one structure.  FLAG_NOINCREF means that this is
 *	a new object, but lg_inc_refcount should not be called.
 *
 * If we already have a Lua object for this object, do NOT increase the
 * refcount of the object.  Only the Lua object has a new reference.
 *
 * You can call this function from C code to make existing library objects
 * available to Lua code: lg_get_object(L, object_ptr, 0, 0);
 */
void lg_get_object(lua_State *L, void *p, typespec_t ts, int flags)
{
    // NULL pointers are turned into nil.
    if (!p) {
	lua_pushnil(L);
	return;
    }

    // type_idx can be 0 for auto detection.
    if (ts.type_idx) {
	type_info_t ti = lg_get_type_info(ts);
	if (ti->st.genus == GENUS_NON_NATIVE)
	    luaL_error(L, "%s lg_get_object called with non-native "
		"type %d.%d", msgprefix, ts.module_idx, ts.type_idx);
    }

    // translate the address to a reference in the aliases table
    lua_getglobal(L, LUAGNOME_TBL);
    lua_getfield(L, -1, LUAGNOME_WIDGETS);
    lua_getfield(L, -2, LUAGNOME_ALIASES);	// gnome objects aliases
    lua_remove(L, -3);				// objects aliases

    lua_pushlightuserdata(L, p);		// objects aliases *w
    lua_rawget(L, -3);				// objects aliases *o/nil

    // If found, look up the address in aliases.  The address could be
    // used directly, but if the object is half garbage collected, the
    // entry might have been removed from the aliases table already.
    if (!lua_isnil(L, -1)) {
	lua_rawget(L, -2);			// objects aliases w/nil
	if (!lua_isnil(L, -1)) {
	    _reuse_object(L, p, ts, flags);
	    goto ex;
	}
    }

    lua_pop(L, 1);

    // Either the address isn't a key in gtk.objects, or the reference
    // number isn't in gtk.object_aliases.  The latter may happen when an
    // entry in object_aliases is removed by GC (weak values!), but
    // lg_object_gc hasn't been called on it yet.

    // returns NULL if the object is on the stack.
    struct object *o = _make_object(L, p, ts, flags);
    if (o && o != (void*) -1) {
	// new entry in objects table
	_set_object_pointer(L, p, o, NULL);

	if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_MEMORY
	    && !lua_isnil(L, -1))) {
	    struct object *w = (struct object*) lua_touserdata(L, -1);
	    int ref_count = lg_get_refcount(L, w);
	    struct object_type *wt = lg_get_object_type(L, w);
	    fprintf(stderr, "%p %p new %s %4d %s\n", w, w->p,
		wt->name, ref_count, lg_get_object_name(w));
	}
    }

ex:
    lua_remove(L, -2);				// objects w/nil
    lua_remove(L, -2);				// w/nil
}

/**
 * Determine the type of the object
 *
 * @param p  Pointer to the object
 * @return  A typespec_t which is zero on error.
 */
static typespec_t _determine_object_type(lua_State *L, void *p)
{
    GType type_nr = G_TYPE_FROM_INSTANCE(p);
    const char *type_name;
    typespec_t ts = { 0 };

    for (;;) {
	// g_type_query might not succeed if the type isn't completely
	// initialized. use g_type_name instead.
	type_name = g_type_name(type_nr);

	if (!type_name)
	    luaL_error(L, "invalid object at %p (type %d)", p, (int) type_nr);

	// This actually refers to a GEnumClass - a collection of possible
	// values of an ENUM, not to a specific value.  So this is not useful!
	if (G_TYPE_IS_ENUM(type_nr) || G_TYPE_IS_FLAGS(type_nr))
	    break;

	ts = lg_find_struct(L, type_name, 1);
	
	/* found? if so, perform an integrity check */
	if (ts.value) {
	    const char *name = lg_get_type_name(ts);
	    if (strcmp(name, type_name))
		luaL_error(L, "%s internal error: type names don't "
		    "match: %s - %s", msgprefix, name, type_name);
	    return ts; // find_struct already returns a normalized value.
	}

	/* This class is not known. Maybe a base class is known? */
	GType parent_type = g_type_parent(type_nr);
	if (!parent_type)
	    luaL_error(L, "%s g_type_parent failed on GType %s (%d)",
		msgprefix, type_name, type_nr);

	/* Parent found; try again with this.  Happens with GdkGCX11,
	 * which is private, but can be used as GdkGC. */
	type_nr = parent_type;
    }

    typespec_t zero = { 0 };
    return zero;
}


/**
 * Push a new Lua proxy object (struct object) onto the Lua stack.  It gets an
 * entry in the aliases table (unless it is a stack object); the caller must
 * take care of an entry in the objects table.
 *
 * @param p  pointer to the object to make the Lua object for; must not be NULL.
 * @param ts  what the pointer type is; 0 for auto detect
 * @param flags  see lg_get_object
 * @return  -1 on error (nothing pushed), NULL (stack object) or >0 (normal)
 *
 * Lua stack: unless -1 is returned, a new object is pushed.
 */
static struct object *_make_object(lua_State *L, void *p, typespec_t ts,
    int flags)
{
    struct object *o;

    // 0 is valid - for autodetection.  == module_count is OK as it is 1 based.
    if (ts.module_idx > module_count) {
	luaL_error(L, "%s invalid module_idx %d in _make_object",
	    msgprefix, ts.module_idx);
	return (void*) -1;
    }

    /* If the structure number is not given, the object must be derived from
     * GObject; otherwise, the result is undefined (probably SEGV). */
    if (!ts.type_idx) {
	ts = _determine_object_type(L, p);
	if (!ts.value)
	    return (void*) -1;
    }

    if (ts.type_idx <= 0 || ts.type_idx >= modules[ts.module_idx]->type_count) {
	luaL_error(L, "%s invalid type_idx %d in _make_object",
	    msgprefix, ts.type_idx);
	return (void*) -1;
    }

    /* make new Lua object with meta table */
    o = (struct object*) lua_newuserdata(L, sizeof(*o));
    memset(o, 0, sizeof(*o));
    o->p = p;
    o->ts = ts;
    o->is_new = 1;

    /* determine which object type to use. */
    lg_guess_object_type(L, o, flags);

    /* set metatable - shared among objects of the same type */
    _get_object_meta(L, ts);			// o meta
    lua_setmetatable(L, -2);			// o

    /* Set the environment to an empty table - used to store data with
     * arbitrary keys for a specific object.  The env can't be nil.  To avoid
     * having an unused table for each object, use the same for all and replace
     * with a private table when the first data is stored.
     */
    lua_getglobal(L, LUAGNOME_TBL);		// o gnome
    lua_getfield(L, -1, LUAGNOME_EMPTYATTR);	// o gnome emptyattr
    lua_setfenv(L, -3);				// o gnome

    // Increase refcount (but not always - see ffi2lua_struct_ptr).  flags
    // may have FLAG_NEW_OBJECT set.
    lg_inc_refcount(L, o, flags);

    // Stack objects neither get an entry in gnome.objects, nor in
    // gnome.aliases.  They can't be reused anyway.
    if (_is_on_stack(p)) {
	lua_pop(L, 1);				// o
	return NULL;
    }

    // Store the new object in the aliases table, using its own address
    // as a key.
    lua_getfield(L, -1, LUAGNOME_ALIASES);	// o gnome aliases
    lua_pushlightuserdata(L, o);		// o gnome aliases *o
    lua_pushvalue(L, -4);			// o gnome aliases *o o
    lua_rawset(L, -3);				// o gnome aliases
    lua_pop(L, 2);				// o

    return o;
}

