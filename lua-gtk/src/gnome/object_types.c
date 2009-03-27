/* vim:sw=4:sts=4
 * Library to use the Gnome family of libraries from Lua 5.1
 * Copyright (C) 2007, 2008 Wolfgang Oertl
 *
 * Handle different type of objects (objects) - refcounting, freeing.
 *
 * Exported symbols:
 *  lg_inc_refcount
 *  lg_dec_refcount
 *  lg_get_refcount
 *  lg_get_object_type
 *  lg_guess_object_type
 *  lg_register_object_type
 *  lg_init_object
 *  lg_find_object_type
 */

#include "luagnome.h"
#include <string.h>		// strcmp, strncpy
#include <glib.h>		// g_slice_free &c

static int next_type_nr = 0;
static struct object_type *object_types = NULL;

/**
 * Free a GValue.  It might contain a string, for example, meaning additional
 * allocated memory.  This is freed.
 */
static void _gvalue_free(void *p)
{
    GValue *gv = (GValue*) p;
    if (G_IS_VALUE(gv))
	g_value_unset(gv);
    g_slice_free(GValue, gv);
}


/*
 * Most functions to free a structure are called very regularly, but some
 * are not.  Therefore the class name is looked up here first, and if nothing
 * is found, a regularly named function is looked for.
 *
 * Note: such structures are usually allocated using g_slice_alloc or similar,
 * and not g_malloc.  Using an inappropriate free function (g_slice_free vs.
 * g_free) leads to memory corruption!
 */
static struct free_methods {
    const char *class_name;
    const char *func_name;
    void (*free_func)(void*);
} free_methods[] = {
    { "GdkRegion",	"gdk_region_destroy" },
    { "GdkRectangle",	NULL },		// don't bother looking
    { "GValue",	NULL, &_gvalue_free },	// special free function
    { NULL, NULL }
};

/**
 * The given structure should be freed; it has no reference counting and
 * therefore an _unref function does not exist.  Try to find a _free
 * function and call it; otherwise, just g_slice_free() it.
 *
 * @param w   Pointer to the object to be freed.
 */
static void _free_structure(struct object *w)
{
    char func_name[50];
    struct func_info fi;
    struct free_methods *fm;
    const char *obj_name = lg_get_object_name(w);

    if (!w->p) {
	fprintf(stderr, "%s Warning: trying to free NULL structure %p %s\n",
	    msgprefix, w, obj_name);
	return;
    }

    for (fm=free_methods; ; fm++) {
	if (!fm->class_name) {
	    // not found - use default name.
	    if (lg_make_func_name(func_name, sizeof(func_name), obj_name,
		"free"))
		return;
	    break;
	}

	if (!strcmp(fm->class_name, obj_name)) {

	    // direct pointer to a free function - use it.
	    if (fm->free_func) {
		fm->free_func(w->p);
		w->p = NULL;
		return;
	    }

	    // An entry with NULL function name means that g_slice_free1 should
	    // be used.  It's just an optimization, but also avoids the
	    // warning below.
	    if (!fm->func_name)
		goto free_directly;

	    strncpy(func_name, fm->func_name, sizeof(func_name));
	    break;
	}
    }

    // if no special free function is available, just free() the structure.
    cmi mi = modules[w->ts.module_idx];
    if (G_UNLIKELY(!lg_find_func(NULL, mi, func_name, &fi))) {
	if (runtime_flags & RUNTIME_DEBUG_MEMORY)
	    fprintf(stderr, "_free_structure: %s not found, using "
		"g_slice_free1\n", func_name);
free_directly:;
	// must be a native type.
	type_info_t ti = lg_get_type_info(w->ts); // OK
	g_slice_free1(ti->st.struct_size, w->p);
	w->p = NULL;
	return;
    }

    // The function exists - call it.
    if (G_UNLIKELY(runtime_flags & RUNTIME_DEBUG_MEMORY))
	fprintf(stderr, "%p %p freeing memory using %s\n", w, w->p, func_name);

    void (*func)(void*);
    func = fi.func;
    func(w->p);
    w->p = NULL;
}


/**
 * Increase the reference counter of the object by 1.
 *
 * If FLAG_NEW_OBJECT is set, then this is a "new" object, just created
 * by the appropriate function.  This may require not increasing the refcount,
 * or doing something else (think about floating references).
 */
void lg_inc_refcount(lua_State *L, struct object *w, int flags)
{
    if (flags & FLAG_NOINCREF)
	return;
    struct object_type *wt = lg_get_object_type(L, w);
    if (wt)
	wt->handler(w, WIDGET_REF, flags);
}


/**
 * Decrease the Gdk/Gtk/GObject reference counter by one.  This is done when
 * the Lua object representing it is garbage collected.
 *
 * @param w          The object
 */
void lg_dec_refcount(lua_State *L, struct object *w)
{
    // Not if deleted e.g. by s_list_free.
    if (!w->is_deleted) {
	struct object_type *wt = lg_get_object_type(L, w);
	if (wt)
	    wt->handler(w, WIDGET_UNREF, 0);
    }
}



/**
 * Return the reference counter of the Gtk object associated with this
 * object structure.  Not all objects have such a counter.
 *
 * A negative value indicates an error.
 */
int lg_get_refcount(lua_State *L, struct object *w)
{
    struct object_type *wt;

    /* NULL pointer to Lua object */
    if (!w)
	return -100;

    /* Lua object contains NULL pointer to Gtk object */
    if (!w->p)
	return -99;

    wt = lg_get_object_type(L, w);
    return wt->handler(w, WIDGET_GET_REFCOUNT, 0);
}


/**
 * Retrieve the struct object_type for the given object.
 *
 * @param w  A object
 * @return  The object_type, or NULL on error.  In this case, an error is
 *   printed on stderr, too.
 */
struct object_type *lg_get_object_type(lua_State *L, struct object *w)
{
    if (w && w->mm_type < next_type_nr)
	return object_types + w->mm_type;
    luaL_error(L, "%s %p %p lg_get_object_type: invalid object (type %d)\n",
	msgprefix, w, w ? w->p : NULL, w ? w->mm_type : 0);
    return NULL;
}


/**
 * Determine the mm_type for a new object proxy object.  This type
 * determines how the memory of this object is managed - is reference
 * counting used, should it be free()d or nothing done, etc.
 *
 * @param L  Lua State
 * @param w  The new object
 * @param flags  any of the FLAG_xxx constants: FLAG_NEW_OBJECT, FLAG_ALLOCATED
 */
void lg_guess_object_type(lua_State *L, struct object *w, int flags)
{
    int i, type_nr=-1, score=0;

    for (i=0; i<next_type_nr; i++) {
	int rc = object_types[i].handler(w, WIDGET_SCORE, flags);
	if (rc > score) {
	    score = rc;
	    type_nr = i;
	}
    }

    if (G_UNLIKELY(type_nr == -1)) {
	lua_pop(L, 1);
	luaL_error(L, "%s internal error: no appropriate mm_type found",
	    msgprefix);
    }

    w->mm_type = type_nr;
}


/**
 * Register an object type.  Widgets have types (maybe a better name could be
 * found?) that govern how their memory is managed.  To make the library more
 * extensible, they are registered at initialization.
 *
 * @param name  Short name for this object type (for debugging output)
 * @param handler  A function to handle various tasks
 * @return  The type_nr assigned to this object type.
 */
int lg_register_object_type(const char *name, object_handler handler)
{
    int type_nr = next_type_nr ++;
    object_types = (struct object_type*) g_realloc(object_types,
	next_type_nr * sizeof(*object_types));
    struct object_type *wt = object_types + type_nr;
    wt->name = name;
    wt->handler = handler;
    return type_nr;
}

int lg_find_object_type(const char *name)
{
    int i;

    for (i=0; i<next_type_nr; i++)
	if (!strcmp(name, object_types[i].name))
	    return i;

    return -1;
}

static inline int _is_on_stack(void *p)
{
    volatile char c[30];    // large enough so it can't be in registers.
    long int ofs = ((char*)p) - c;
    if (ofs < 0)
	ofs = -ofs;
    return ofs < 36000;
}

/**
 * Handler for objects that don't need memory management or refcounting; it is
 * the fallback for non-allocated objects.
 *
 * GSList: the start as well as any item of such a list has the same type.
 * Therefore, they can't be free()d automatically.  use list:free() for that.
 *
 * @param w  A object
 * @param op  Type of operation to perform
 * @param flags  If FLAG_ALLOCATED is set, rather not use this handler, else
 *   yes.
 * @return  For op==WIDGET_SCORE, the score, i.e. how well this handler would
 *   be for the given object.
 */
static int _plain_handler(struct object *w, object_op op, int flags)
{
    if (op == WIDGET_SCORE) {
	if (flags & FLAG_ARRAY_ELEMENT)
	    return 1000;
	if (!strcmp(lg_get_object_name(w), "GSList"))
	    return 10;
	if (_is_on_stack(w->p))
	    return 5;
	if (flags & FLAG_CONST_OBJECT)	    // simply ignore such objects
	    return 500;
	return (flags & FLAG_ALLOCATED) ? 1 : 2;
    }

    // returns refcount 0, and doesn't do anything on ref and unref.
    return 0;
}

/**
 * Handler for objects that are allocated by this library using g_slice_alloc,
 * and that don't have refcounting.  They exist attached to their Lua object
 * proxy and are freed when the proxy is freed.
 */
static int _malloc_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:
	    if (flags & FLAG_NEW_OBJECT)
		return flags & FLAG_ALLOCATED ? 4 : 3;
	    // Non-new objects might be allocated, but they are not owned
	    // by this library and therefore must not be freed - let the
	    // plain handler take precedence.
	    return 0;

	case WIDGET_REF:
	    if (!(flags & FLAG_NEW_OBJECT))
		fprintf(stderr, "ref a malloc()ed object of type %s?\n",
		    lg_get_object_name(w));
	    break;

	case WIDGET_UNREF:
	    _free_structure(w);
	    break;
	
	default:
	    break;
    }

    return 0;
}

static int _array_handler(struct object *w, object_op op, int flags)
{
    switch (op) {
	case WIDGET_SCORE:
	    return flags & FLAG_ARRAY ? 200 : 0;

	case WIDGET_UNREF:
	    g_free(w->p);
	    w->p = NULL;
	
	default:
	    break;
    }
    return 0;
}


/**
 * Initialize the object type handlers defined in this module.  There currently
 * is one more (in channel.c).
 */
void lg_init_object(lua_State *L)
{
    lg_register_object_type("plain", _plain_handler);
    lg_register_object_type("malloc", _malloc_handler);
    lg_register_object_type("array", _array_handler);
}


