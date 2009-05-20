/* vim:sw=4:sts=4
 * This is part of Lua-Gtk2, the Lua binding for the Gtk2 library.
 * Functions here give access to functions, structs and enums of Gtk2.
 *
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 *
 * Exported functions:
 *   lg_dl_init
 *   lg_make_func_name
 *   lg_gtype_from_name
 *   lg_get_type_name
 *   lg_get_module
 *   lg_get_object_name
 *   find_attribute
 *   lg_find_constant
 *   lg_find_func
 *   lg_find_struct
 *   lg_find_global
 *   lg_get_type_info
 *   lg_get_ffi_type
 *   lg_type_modify
 *   lg_type_equal
 */

#include "luagnome.h"
#include "lg-hash.h"
#include "module.h"	    // LG_MODULE_MAJOR/MINOR
#include <string.h>	    // strcmp
#include <stdlib.h>	    // bsearch
#include <errno.h>

/* Globals */
struct module_info **modules;		// modules - [0] is unused!
int module_count;			// number of loaded modules
static int module_alloc;		// allocation size of global modules
const struct module_info *curr_module;	// needed for qsort and bsearch

// only works for native types!
#define TYPE_NAME(mi, ti) ((mi)->type_names + (ti)->st.name_ofs)

// --- Windows ---

#ifdef LUAGTK_win32
 #define DLLOOKUP(dl_handle, name) (FARPROC) GetProcAddress(dl_handle, name)
 #define DLCLOSE(name)
#endif

// --- Linux ---

#ifdef LUAGTK_linux
 #define DLLOOKUP(dl_handle, name) dlsym(dl_handle, name)
 #define DLCLOSE(name) dlclose(name)
#endif


/**
 * Given a class name in the form "GtkVBox" and a method name like
 * "pack_start", construct a function name like "gtk_vbox_pack_start".
 *
 * All letters are converted to lowercase, but before initially uppercase
 * letters, an underscore is inserted, unless a single letter would then
 * be surrounded by underscores (as is the case for GtkVBox, which turns
 * into gtk_vbox, and not gtk_v_box).
 *
 * Returns 0 on success, else 1.  The only possible error is that the
 * buffer is not big enough.
 */
int lg_make_func_name(cmi mi, char *buf, int buf_size, const char *class_name,
    const char *attr_name)
{
    const char *s = class_name, *s2;
    char *out = buf;

    /* If a module is given, use its prefix_func_remap table if available. */
    if (mi && (s2 = mi->prefix_func_remap)) {
	for (; *s2; s2 += *s2) {
	    int len = strlen(s2 + 1);
	    // printf("try %s for %s.%s\n", s2+1, class_name, attr_name);
	    if (!memcmp(class_name, s2 + 1, len)) {
		s += len;
		s2 += 2 + len;
		len = strlen(s2);
		memcpy(out, s2, len);
		out += len;
		break;
	    }
	}
    }

    // each loop adds one or two characters to the output; a final 0 byte
    // is also required, therefore +2.
    while (*s) {
	if (out - buf + 2 >= buf_size)
	    return 1;
	if (*s >= 'A' && *s <= 'Z') {
	    // the s==class_name+1 test allows g_context_xxx functions.
	    if (s == class_name+1 || (out >= buf+2 && out[-2] != '_'))
		*out++ = '_';
	    *out++ = *s + ('a' - 'A');
	} else {
	    *out++ = *s;
	}
	s++;
    }

    if (attr_name) {
	if (out - buf + 1 + strlen(attr_name) + 1 >= buf_size)
	    return 1;
	*out++ = '_';
	strcpy(out, attr_name);
	// printf("RESULT: %s\n", buf);
    } else
	*out = 0;

    return 0;
}


/**
 * Determine the type number for the given class.
 *
 * After using the class for the first time, g_type_from_name returns the ID;
 * otherwise is is required to call the get_type function for this class.
 *
 * @param s  Name of the type
 * @param mi  Module this type should be in (NULL if not known)
 * @return  0 if not found, else the GType (an integer)
 */
GType lg_gtype_from_name(lua_State *L, cmi mi, const char *s)
{
    GType type_nr = g_type_from_name(s);

    // Type already initialized - return it.  This is the usual case.
    if (type_nr)
	return type_nr;

    // cairo_xxx are types that are not in the GType system.  Don't try
    // to get a type_nr for them.
    if (!strncmp(s, "cairo_", 6))
	return 0;

    // Determine the name of the corresponding get_type function.
    char func_name[60];
    struct func_info fi;
    if (lg_make_func_name(mi, func_name, sizeof(func_name), s, "get_type"))
	return 0;

    // If s is not a valid type, then the _get_type function doesn't exist
    if (mi) {
	if (!lg_find_func(L, mi, func_name, &fi))
	    return 0;
    } else {
	int i;
	for (i=1; i<=module_count; i++)
	    if (lg_find_func(L, modules[i], func_name, &fi))
		goto found_it;
	return 0;
    }

found_it:;
	 // The function exists - call it.  It returns the type number.
	 GType (*func)();
	 func = fi.func;
	 type_nr = func();

	 // Force the class to be initialized - makes g_signals_list_ids work,
	 // for example.  Might not always be necessary.  Only for types that
	 // are classed - could also use g_type_query.
	 gpointer cls = g_type_class_peek(type_nr);
	 if (cls) {
	     gpointer cls = g_type_class_ref(type_nr);
	     g_type_class_unref(cls);
	 }

	 return type_nr;
}

// Helper function with different arguments.  Returns the length.
static int _get_type_name_full(cmi mi, type_info_t ti, char *buf)
{
    char *s = buf;
    const char *name;
    int len;

    // works only for native types, of course; non-native have no name.
    if (ti->st.genus == GENUS_NON_NATIVE)
	return 0;

    if (ti->st.is_const) {
	strcpy(s, "const ");
	s += 6;
    }

    // use the type's name, not the fundamental type's name.
    name = TYPE_NAME(mi, ti);
    len = strlen(name);
    if (len > LG_TYPE_NAME_LENGTH - 10) {
	fprintf(stderr, "%s type name too long (%d).\n", msgprefix, len);
	exit(1);
    }
    strcpy(s, name);
    s += len;

    // Add the pointers.
    int i;
    for (i=0; i<ti->st.indirections; i++)
	*s ++ = '*';

    // Add array dimensions
    if (ti->st.is_array) {
	int type_idx = ti - mi->type_list;
	const struct array_info *ai;
	for (ai=mi->array_list; ai->type_idx; ai++)
	    if (ai->type_idx == type_idx)
		goto found;
	printf("%s ERROR: type %s.%d is an array, but no array info found\n",
	    msgprefix, mi->name, type_idx);
found:	
	s += sprintf(s, "[%d]", ai->dim[0]);
	if (ai->dim[1])
	    s += sprintf(s, "[%d]", ai->dim[1]);
    }

    *s = 0;
    return s - buf;
}


/**
 * Writes the type's name into the given buffer.  Its length should be
 * LG_TYPE_NAME_LENGTH bytes long.
 *
 * @param L  Lua state
 * @param ts  Typespec
 * @param buf  Output buffer (must be at least LG_TYPE_NAME_LENGTH bytes long)
 */
void lg_get_type_name_full(lua_State *L, typespec_t ts, char *buf)
{
    const struct module_info *mi;

    // module_idx must be valid (1 .. module_count)
    if (ts.module_idx <= 0 || ts.module_idx > module_count)
	luaL_error(L, "%s module_idx out of range: %d", msgprefix,
		ts.module_idx);
    mi = modules[ts.module_idx];

    // type_idx must be 1 .. type_count
    if (ts.type_idx <= 0 || ts.type_idx > mi->type_count)
	luaL_error(L, "%s type_idx out of range: %d", msgprefix, ts.type_idx);

    type_info_t ti = mi->type_list + ts.type_idx;
    _get_type_name_full(mi, ti, buf);
}


const char *lg_get_object_name(struct object *o)
{
    cmi mi = modules[o->ts.module_idx];
    type_info_t ti = mi->type_list + o->ts.type_idx;
    return mi->type_names + ti->st.name_ofs;
}

// Note: works only on native types
const char *lg_get_type_name(typespec_t ts)
{
    cmi mi = modules[ts.module_idx];
    type_info_t ti = mi->type_list + ts.type_idx;
    return mi->type_names + ti->st.name_ofs;
}

type_info_t lg_get_type_info(typespec_t ts)
{
    const struct module_info *mi = modules[ts.module_idx];
    return mi->type_list + ts.type_idx;
}

/**
 * Return the number of indirections the underlying fundamental type has.
 * This may be more than what type_info.indirections specifies.
 */
int lg_get_type_indirections(typespec_t ts)
{
    type_info_t ti = lg_get_type_info(ts);
    if (ti->st.genus == GENUS_NON_NATIVE)
	return -1;
    int fid = ti->st.fundamental_idx;
    cmi mi = modules[ts.module_idx];
    if (mi->fundamental_map)
	fid = mi->fundamental_map[fid];
    const struct ffi_type_map_t *ffi = ffi_type_map + fid;
    return ffi->indirections;
}

/**
 * Given a type, change the level of indirections by "ind_delta", so for
 * example ("char**", -1) turns into "char*".  This is needed when a function
 * argument is an output argument.
 */
typespec_t lg_type_modify(lua_State *L, typespec_t ts, int ind_delta)
{
    const struct module_info *mi = modules[ts.module_idx];
    type_info_t ti = mi->type_list + ts.type_idx;
    const char *name = mi->type_names + ti->st.name_ofs;
    int ind = ti->st.indirections + ind_delta;
    return lg_find_struct(L, name, ind);
}

// ti->fu.genus must be == GENUS_FUNCTION
const unsigned char *lg_get_prototype(typespec_t ts)
{
    const struct module_info *mi = modules[ts.module_idx];
    type_info_t ti = mi->type_list + ts.type_idx;
    return mi->prototypes + ti->fu.signature_ofs;
}

const char *lg_get_struct_elem_name(int module_idx,
	const struct struct_elem *se)
{
    const struct module_info *mi = modules[module_idx];
    return mi->type_strings_elem + se->name_ofs;
}

// ts must specify a native type
const struct ffi_type_map_t *lg_get_ffi_type(typespec_t ts)
{
    const struct module_info *mi = modules[ts.module_idx];
    type_info_t ti = mi->type_list + ts.type_idx;
    int fid = ti->st.fundamental_idx;
    if (mi->fundamental_map)
	fid = mi->fundamental_map[fid];
    return ffi_type_map + fid;
}

/**
 * Determine whether two typespecs are equal, disregarding the flags that
 * may be set.
 */
int lg_type_equal(lua_State *L, typespec_t ts1, typespec_t ts2)
{
    ts1.flag = ts2.flag = 0;
    return ts1.value == ts2.value;
}


/**
 * If a typespec refers to a "non-native" type, use the hash value stored
 * there to look up the type in the table gnome.typemap.
 */
typespec_t lg_type_normalize(lua_State *L, typespec_t ts)
{
    if (!ts.module_idx || !ts.type_idx)
	return ts;
    type_info_t ti = lg_get_type_info(ts);
    if (ti->st.genus != GENUS_NON_NATIVE)
	return ts;

    lua_getglobal(L, lib_name);
    lua_getfield(L, -1, "typemap");
    lua_pushinteger(L, ti->nn.name_hash);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) {
found:;	typespec_t ts2;
	ts2.value = lua_tointeger(L, -1);
	lua_pop(L, 3);
	return ts2;
    }
    lua_pop(L, 1);

    cmi mi = modules[ts.module_idx];

    // The type isn't available (yet).  If the type specifies a module that
    // provides the type, try to load that module and try again.
    if (ti->nn.name_is_module) {
	const char *module_name = mi->type_names + ti->nn.name_ofs;

	lua_getglobal(L, "require");
	lua_pushstring(L, module_name);
	lua_call(L, 1, 0);
	
	// try again
	lua_pushinteger(L, ti->nn.name_hash);
	lua_rawget(L, -2);
	if (!lua_isnil(L, -1))
	    goto found;
	
	// still not found; should not happen.
	luaL_error(L, "%s using unresolved type %s.%d, should be defined "
	    "in module %s!",
	    msgprefix, modules[ts.module_idx]->name, ts.type_idx,
	    module_name);
    }

    // no module given, but instead the name.
    luaL_error(L, "%s using unresolved type %s.%d (%s).",
	msgprefix, modules[ts.module_idx]->name, ts.type_idx,
	ti->nn.name_ofs ? mi->type_names + ti->nn.name_ofs : "unknown");

    // not reached
    return ts;
}

/**
 * A constant has been found.  The data is encoded in a certain binary format,
 * which this function decodes.  Various encoding formats have been tried,
 * and this is the best one so far.  Even better ones might come along.
 *
 * The top 2 bits of the first byte: 00=no type, 01=8 bit type, 10=16 bit type,
 * 11=string.  If the (16 bit) type has the top bit set, this means a negative
 * number.  The other 6 bits of the first byte are used as high bits of the
 * value, unless it is a string.
 *
 * Following that is the string, or as many bytes of the value as are required
 * from high to low byte.
*
 * @param L  Lua State
 * @param ts  (output) to store the data type, if the constant has one
 * @param res  (input) Pointer to the binary encoding of the value
 * @param datalen  Length of this value
 * @param result  (output) Store the value at this location.
 * @return  1=typed value, 2=untyped, 3=string (on Lua stack).
 */
static int _decode_constant_v2(lua_State *L, typespec_t *ts,
    const unsigned char *res, int datalen, int *result)
{
    int val, type_idx = 0;
    const unsigned char *res_end = res + datalen;

    /* get the flag byte */
    unsigned char c = *res++;

    /* low 6 bits of first byte are for the value */
    val = c & 0x3f;

    switch (c >> 6) {
	case 0:	    // unyped
	break;

	case 1:	    // 8 bit type
	type_idx = *res++;
	break;

	case 2:	    // 16 bit type (high byte, then low)
	type_idx = (res[0] << 8) + res[1];
	res += 2;
	break;

	case 3:	    // string
	lua_pushlstring(L, (char*) res, datalen - 1);
	return 3;
    }

    /* collect all bytes for the number */
    while (res < res_end)
	val = (val << 8) + *res++;

    /* high bit if type_idx is the negative sign */
    if (type_idx & 0x8000) {
	type_idx &= 0x7fff;
	val = -val;
    }

    *result = val;
    ts->type_idx = type_idx;

    /* if type_idx is set, ENUM or FLAG, else regular integer */
    return type_idx ? 1 : 2;
}


/**
 * Find a constant by name in the given module.
 *
 * @param L  Lua State
 * @param ts  The typespec with its module_idx set; its type_idx field
 *	may be set as output.
 * @param key  Name of the constant to look up
 * @param keylen  Length of the name; -1 means zero terminated string
 * @param result  (output) Location where to store the resulting value
 * @return  0=not found, else see _decode_constant_v2().
 */
static int _find_constant(lua_State *L, typespec_t *ts, const char *key,
    int keylen, int *result)
{
    int datalen;
    unsigned const char *res;
    cmi mi = modules[ts->module_idx];

    if (keylen < 0)
	keylen = strlen(key);

    res = hash_search(L, mi->hash_constants, (unsigned const char*) key,
	keylen, &datalen, mi->name);
    if (!res)
	return 0;

    return _decode_constant_v2(L, ts, res, datalen, result);
}


/**
 * Search for the string in the constants table.  The result might be an enum
 * (typed integer), flags (typed integer, can be ORed together), a regular
 * integer, or a string.
 *
 * @param L  Lua State
 * @param ts  (in/out) Type Spec - module_idx can be set, but can be zero.
 * @param key The name of the constant to look for
 * @param keylen Length of key.  If -1, key must be zero terminated.
 * @param result (output) value of the constant (if ENUM, FLAGS or integer)
 * @return 0=error, 1=ENUM found (type in *ts), 2=int found (in *result),
 *    3=string found (on Lua stack)
 */
int lg_find_constant(lua_State *L, typespec_t *ts, const char *key, int keylen,
	int *result)
{
    if (ts->module_idx)
	return _find_constant(L, ts, key, keylen, result);

    int i, rc;
    for (i=1; i<=module_count; i++) {
	ts->module_idx = i;
	rc = _find_constant(L, ts, key, keylen, result);
	if (rc)
	    return rc;
    }

    return 0;
}


/**
 * Look for an attribute of the given class.  The attributes are ordered
 * by their offset within the structure, but not strictly - unions have
 * their attributes at the same offset.
 *
 * @param ts  Type of the structure to look in
 * @param attr_name  Name of the attribute being looked for
 * @return  A struct_elem or NULL
 */
const struct struct_elem *find_attribute(typespec_t ts, const char *attr_name)
{
    const struct struct_elem *e, *e_end;
    cmi mi = modules[ts.module_idx];
    type_info_t ti = mi->type_list + ts.type_idx;
    const char *name;

    /* Search up to the start of the next entry. */
    e = mi->elem_list + ti->st.elem_start;
    e_end = e + ti->st.elem_count;

    for (; e < e_end; e++) {
	name = lg_get_struct_elem_name(ts.module_idx, e);
	if (!strcmp(attr_name, name))
	    return e;
    }

    return NULL;
}


/**
 * Create and fill gnome.fundamental_map containing hash values of all
 * fundamental types supported by this core module.  Non-core modules just
 * have hashes of the names of fundamental types, which is shorter and
 * easier to look up than the full names.
 */
void lg_create_fundamental_map(lua_State *L)
{
    const char *name;
    struct hash_state state;
    unsigned int hash_value;
    int len, nr;

    state.hashfunc = HASHFUNC_JENKINS;
    state.seed = 0; // arbitrary value; must match script/xml-output.lua

    lua_newtable(L);

    for (nr=0, name=gnome_ffi_type_names; *name; name+=len+1) {
	len = strlen(name);
	hash_value = compute_hash(&state, (unsigned char*) name, len, NULL);
	lua_pushinteger(L, hash_value);
	lua_pushinteger(L, nr);
	lua_rawset(L, -3);
	nr ++;
    }

    lua_setfield(L, 1, "fundamental_map");
}


/**
 * Each module lists fundamental names' hash values which are used here to
 * build a mapping for fundamental types.
 */
static void _map_fundamental_names(lua_State *L, struct module_info *mi)
{
    int cnt = mi->fundamental_count, err=0, i;
    unsigned int hash_value;

    int *map = mi->fundamental_map = (int*) g_malloc(sizeof(*map) * (cnt+1));
    map[0] = 0;	// "INVALID" is the first entry, not stored in module list

    lua_getglobal(L, lib_name);
    lua_getfield(L, -1, "fundamental_map");
    
    for (i=0; i<cnt; i++) {
	hash_value = mi->fundamental_hash[i];
	lua_pushinteger(L, hash_value);
	lua_rawget(L, -2);
	if (lua_isnil(L, -1)) {
	    fprintf(stderr, "%s module %s - fundamental type with hash 0x%08x "
		"not found\n", msgprefix, mi->name, hash_value);
	    err ++;
	} else {
	    map[i+1] = lua_tonumber(L, -1);
	}
	lua_pop(L, 1);
    }

    lua_pop(L, 2);
    if (err > 0)
	luaL_error(L, "%s errors while resolving fundamental types in module %s",
	    msgprefix, mi->name);
}


#if 0
    int cnt, i, fid, err=0;
    const char *name;

    // count fundamental IDs
    for (cnt=0, name=mi->fundamental_names; *name; name += strlen(name) + 1)
	cnt ++;
    mi->fundamental_map_count = cnt;

    // set up mapping for fundamental IDs
    mi->fundamental_map = (int*) g_malloc(sizeof(*mi->fundamental_map) * cnt);
    for (i=0, name=mi->fundamental_names; i<cnt; i++) {

	// determine fundamental_id for name
	for (fid=0; fid<ffi_type_count; fid++)
	    if (!strcmp(name, FTYPE_NAME(ffi_type_map + fid)))
		break;
	if (fid == ffi_type_count) {
	    fprintf(stderr, "%s library %s requires unknown fundamental "
		    "type %s\n", msgprefix, mi->name, name);
	    err ++;
	}

	mi->fundamental_map[i] = fid;
	name += strlen(name) + 1;
    }

    if (err > 0)
	luaL_error(L, "Some types could not be resolved.");

}

#endif

/**
 * Add all native types of this module to the global hash list of types.
 */
static void _update_typemap_hash(lua_State *L, struct module_info *mi)
{
    type_info_t ti;
    struct hash_state state;
    char full_name[LG_TYPE_NAME_LENGTH];
    unsigned int hash_value;
    int type_idx, len, err=0;
    typespec_t ts = { 0 };

    lua_getglobal(L, lib_name);
    lua_getfield(L, -1, "typemap");
    ts.module_idx = mi->module_idx;
    state.hashfunc = HASHFUNC_JENKINS;
    state.seed = 0; // arbitrary value; must match script/xml-output.lua

    for (type_idx=1; type_idx<=mi->type_count; type_idx++) {
	ti = mi->type_list + type_idx;
	if (ti->st.genus == GENUS_NON_NATIVE)
	    continue;
	len = _get_type_name_full(mi, ti, full_name);
	hash_value = compute_hash(&state, (unsigned char*) full_name, len,
	    NULL);
	lua_pushinteger(L, hash_value);

	// is this hash value (as key) already in the type map?
	lua_rawget(L, -2);
	if (!lua_isnil(L, -1)) {
	    // yes.  if this is a fundamental type, that's ok.
	    if (ti->st.genus == GENUS_FUNDAMENTAL) {
		lua_pop(L, 1);
		continue;
	    }
	    // normal type - must not occur twice.
	    typespec_t ts2 = { lua_tointeger(L, -1) };
	    printf("Hash collision for type %d=%s with %s.%d=%s, hash %08x\n",
		type_idx, full_name,
		modules[ts2.module_idx]->name, ts2.type_idx,
		lg_get_type_name(ts2),
		hash_value);
	    err ++;
	}
	lua_pop(L, 1);

	// add to the typemap
	ts.type_idx = type_idx;
	lua_pushinteger(L, hash_value);
	lua_pushinteger(L, ts.value);
	unsigned int hash_value2 = lua_tointeger(L, -2);
	if (hash_value != hash_value2)
	    printf("ERROR %08x %08x\n", hash_value, hash_value2);
	lua_rawset(L, -3);
	// printf("typemap %s -> %08x\n", full_name, hash_value);
    }

    // remove gnome._typemap and gnome
    lua_pop(L, 2);
    if (err > 0)
	luaL_error(L, "%s Errors during typemap construction for module %s",
	    msgprefix, mi->name);
}


/**
 * Add a module to the module list.
 * This also creates a global table for that module:
 *  { new, new_array, _modinfo }
 *
 * @luaparam module_name
 */
int lg_register_module(lua_State *L, struct module_info *mi)
{
    if (mi->module_idx)
	return LG_ERROR(1, "Can't register module %s twice.", mi->name);

    // check API version compatibility
    if (mi->major != LUAGNOME_MODULE_MAJOR || mi->minor > LUAGNOME_MODULE_MINOR)
	return luaL_error(L, "incompatible API versions of gnome %d.%d and "
	    "%s %d.%d.",
	    LUAGNOME_MODULE_MAJOR, LUAGNOME_MODULE_MINOR,
	    mi->name, mi->major, mi->minor);

    const char *depends = mi->depends;

    if (depends) {
	while (*depends) {
	    lua_getglobal(L, "require");
	    lua_pushstring(L, depends);
	    lua_call(L, 1, 0);
	    depends += strlen(depends) + 1;
	}
    }

    lg_dl_init(L, &mi->dynlink);

    _map_fundamental_names(L, mi);

    // add to pointer array modules[].  Note that it is 1-based, and therefore
    // one dummy entry is allocated at the beginning.
    if (module_alloc <= module_count + 1) {
	module_alloc += 10;
	modules = (struct module_info**) g_realloc(modules, module_alloc
	    * sizeof(*modules));
	modules[0] = NULL;
    }
    modules[++ module_count] = mi;
    mi->module_idx = module_count;

    // update all typemaps if at least two modules are loaded now.
    // XXX modules with more than one library are updated multiple times
    /*
    if (module_count > 1)
	for (i=1; i<=module_count; i++)
	    _update_typemap(L, modules[i]);
    */
    _update_typemap_hash(L, mi);

    // create the new global variable
    luaL_register(L, mi->name, mi->methods);

    if (mi->overrides)
	luaL_register(L, NULL, mi->overrides);

    // set it to be its own metatable, so that __index etc. works
    lua_pushvalue(L, -1);
    lua_setmetatable(L, -2);

    lua_pushvalue(L, -1);
    mi->module_ref = luaL_ref(L, LUA_REGISTRYINDEX);

#ifdef LUAGTK_DEBUG_FUNCS
    // add _modinfo, which is required for debugging.
    lua_pushlightuserdata(L, mi);
    lua_setfield(L, -2, "_modinfo");
#endif

    return 1;
}


/**
 * Look for a structure (class) of the given name in the specified module,
 * or in all modules if module_idx isn't set.
 *
 * @param L  Lua State
 * @param type_name  Name of the type to look for
 * @param indirections  The number of "*" after the type name.
 */
typespec_t lg_find_struct(lua_State *L, const char *type_name, int indirections)
{
    char buf[80], *s;

    // build the complete name with the indirections.  Doesn't consider
    // const, array and the like.
    strcpy(buf, type_name);
    s = buf + strlen(buf);
    while (indirections > 0) {
	*s++ = '*';
	indirections --;
    }
    *s = 0;

    return lg_get_type(L, buf);
}

typespec_t lg_get_type(lua_State *L, const char *type_name)
{
    struct hash_state state;
    typespec_t ts = { 0 };
    unsigned int hash_value;

    state.hashfunc = HASHFUNC_JENKINS;
    state.seed = 0;
    hash_value = compute_hash(&state, (unsigned char*) type_name,
	strlen(type_name), NULL);

    lua_getglobal(L, lib_name);
    lua_getfield(L, -1, "typemap");
    lua_pushinteger(L, hash_value);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1))
	ts.value = lua_tointeger(L, -1);

    lua_pop(L, 3);
    return ts;
}


#if 0
/**
 * Determine the module_idx for the given module_name.
 *
 * @return  The module_idx, or 0 when it wasn't found.
 */
cmi lg_get_module(lua_State *L, const char *module_name)
{
    int i;

    for (i=1; i<= module_count; i++)
	if (!strcmp(module_name, modules[i]->name))
	    return modules[i];

    luaL_error(L, "%s unknown module %s", msgprefix, module_name);
    return NULL;
}
#endif


/**
 * Find the symbol in the shared library.  It most likely is a function, but
 * might also be a global variable.
 */
static void *_find_symbol(const struct dynlink *dyn, const char *name)
{
    void *p = NULL;

    // compile-time linked?  Note: not possible on Windows.
    if (!dyn->dll_list) {
	p = DLLOOKUP(dyn->dl_self_handle, name);
	if (!p && dyn->dl_self_handle)
	    p = DLLOOKUP(NULL, name);
	return p;
    }

    /* use the list of available handles */
    int i;

    for (i=0; i<dyn->dll_count; i++)
	if ((p = DLLOOKUP(dyn->dl_handle[i], name)))
	    break;

    return p;
}


/**
 * Look for a global variable, and return its current value if found.
 * NOTE: This doesn't support assignment.
 *
 * @param L  Lua State
 * @param mi  Module Info of the module that contains the global variable
 * @param name  Name of the global
 * @return  non-zero if a global was found and pushed on the Lua stack.
 */
int lg_find_global(lua_State *L, const struct module_info *mi, const char *name)
{
    int len = strlen(name), len2;
    const unsigned char *p = (const unsigned char*) mi->globals;

    // each entry in mi->globals is a zero-terminated string followed
    // by two bytes of type_idx.
    while (*p) {
	len2 = strlen((const char*) p);
	if (len == len2 && !memcmp(p, name, len))
	    break;
	p += len2 + 3;
    }

    if (!*p)
	return 0;

    /* Found a global.  Now get the global's address, and access the value
     * using the provided type information (the two bytes after the name). */
    p += len + 1;
    void *ptr = _find_symbol(&mi->dynlink, name);
    if (!ptr)
	return 0;

    typespec_t ts;
    ts.module_idx = mi->module_idx;
    ts.type_idx = (p[0] << 8) + p[1];
    ts = lg_type_normalize(L, ts);
    mi = modules[ts.module_idx];
    type_info_t ti = lg_get_type_info(ts);

    int fid = ti->st.fundamental_idx;
    if (mi->fundamental_map)
	fid = mi->fundamental_map[ti->st.fundamental_idx];
    const struct ffi_type_map_t *tm = ffi_type_map + fid;
    int structconv_idx = tm->structconv_idx;

    if (structconv_idx && ffi_type_struct2lua[structconv_idx]) {
	struct argconvs_t ar;
	ar.L = L;
	ar.ts = ts;

	struct struct_elem se;
	se.name_ofs = 0;
	se.bit_offset = 0;
	se.bit_length = tm->bit_len;
	se.type_idx = ar.ts.type_idx;	    // XXX what?

	ar.se = &se;
	ar.ptr = ptr;
	ar.index = 0;
	return ffi_type_struct2lua[structconv_idx](&ar);
    }

    return luaL_error(L, "%s unsupported type %s of global %s.%s.",
	msgprefix, mi->name, TYPE_NAME(mi, ti));
}


/**
 * Functions that can't be found during dynamic loading of the libraries
 * are replaced by this.  Until they are called, we can continue.
 * A pity that it's not known which function isn't available.  This could
 * be solved by using closures, but then it probably doesn't help much.
 */
static void unavailable_function()
{
    printf("%s ERROR - an unavailable function was called.\n", msgprefix);
    exit(1);
}

#ifdef LUAGTK_linux
static void *dll_load(struct dynlink *dyn, const char *name)
{
    return dlopen(name, RTLD_LAZY | RTLD_GLOBAL);
}
#endif

#ifdef LUAGTK_win32
static void *dll_load(struct dynlink *dyn, const char *name)
{
    if (!dyn || dyn->dynlink_names)
	return LoadLibrary(name);
    return GetModuleHandle(name);

}
#endif


/**
 * Find out what the handle is for the module shared object.  This is important
 * because _find_symbol needs this handle for DLLOOKUP to find the symbols
 * in the linked library.  Unfortunately, Lua stores this handle in an
 * almost inaccessible location: in the registry with a key that is
 * a string derived from the full path name of the dynamic library.
 *
 * If the handle can be found, it is stored in dyn->dl_self_handle.
 */
static int _find_my_handle(lua_State *L, struct dynlink *dyn)
{
    const char *libname = luaL_checkstring(L, 1), *s;

    lua_pushnil(L);
    while (lua_next(L, LUA_REGISTRYINDEX)) {
	if (lua_type(L, -2) == LUA_TSTRING) {
	    s = lua_tostring(L, -2);
	    if (strstr(s, libname)) {
		void **handle = (void**) lua_touserdata(L, -1);
		if (handle)
		    dyn->dl_self_handle = *handle;
		lua_pop(L, 2);
		break;
	    }
	}
	lua_pop(L, 1);
    }

    return 0;
}

/**
 * Load the dynamic libraries.  Returns 0 on error.
 *
 * On Linux with automatic linking, nothing has to be done; the dynamic linker
 * already has loaded libgtk+2.0 and its dependencies.
 *
 * Note: do _not_ use any functions that are runtime linked, e.g. g_malloc.
 *
 * @param module_name  Name of the module that is being loaded (from require)
 */
int lg_dl_init(lua_State *L, struct dynlink *dyn)
{
    _find_my_handle(L, dyn);

    if (dyn->dll_list) {
	const char *dlname;
	int cnt;

	/* count libraries, allocate array */
	for (dlname=dyn->dll_list, cnt=0; *dlname; dlname += strlen(dlname) + 1)
	    cnt ++;
	dyn->dl_handle = (void**) malloc(sizeof(void*) * cnt);

	/* load dynamic libraries */
	for (dlname=dyn->dll_list, cnt=0; *dlname; dlname+=strlen(dlname)+1) {
	    if (!(dyn->dl_handle[cnt] = dll_load(dyn, dlname))) {
		fprintf(stderr, "%s Can't load dynamic library %s\n", msgprefix,
		    dlname);
		// library loading can fail; no problem.  Not all libraries are
		// always required!
		continue;
	    }
	    cnt ++;
	}
	dyn->dll_count = cnt;
    }

    /* If this library isn't linked with the Gtk libraries, then all
     * function calls are indirect through the dynlink_table table.  Fill in
     * all these pointers.  Unavailable functions are replaced with
     * unavailable_function, see above.
     *
     * The list of names is the string dynlink_names, where the names are
     * separated by \0; at the end there's \0\0.
     */
    if (dyn->dynlink_names) {

        linkfuncptr *dl = dyn->dynlink_table;
	const char *s;

	for (s=dyn->dynlink_names; *s; s += strlen(s) + 1, dl++) {
	    if (G_UNLIKELY(!(*dl = _find_symbol(dyn, s)))) {
		printf("%s symbol %s not found in dynamic library.\n",
		    msgprefix, s);
		*dl = unavailable_function;
	    }
	}
    }

    return 1;
}


/**
 * Look for the function in the dynamic library.  If it is not found, this is
 * not an error, because many tries for different object types may be
 * necessary to find one method.
 * Returns 0 if the function hasn't been found, 1 otherwise.
 */
int lg_find_func(lua_State *L, cmi mi, const char *func_name,
    struct func_info *fi)
{
    int datalen;
    const char *lookup_name = func_name;

    // printf("function? %s\n", func_name);

    /* Find the function in the hash table.  Note that when using
     * minimal hash tables (see documentation), a function may be found
     * even if it doesn't exist.  This is NOT recommended.
     */
    fi->args_info = hash_search(L, mi->hash_functions,
	(unsigned const char*) func_name, strlen(func_name), &datalen,
	mi->name);
    if (!fi->args_info)
	return 0;

    /* handle aliases. */
    if (G_UNLIKELY(*(unsigned short*) fi->args_info == 0xffff)) {
	const unsigned char *real_name = fi->args_info + 2;
	datalen -= 3;	    // remove the 0xffff marker and the terminating 0
//	printf("ALIAS %s -> %*.*s\n", func_name, datalen, datalen, real_name);
	fi->args_info = hash_search(L, mi->hash_functions, real_name,
	    datalen, &datalen, mi->name);
	if (!fi->args_info)
	    return 0;
	lookup_name = (const char *) real_name;
    }

    fi->func = _find_symbol(&mi->dynlink, lookup_name);
    if (fi->func) {
	fi->name = func_name;
	fi->args_len = datalen;
	fi->module_idx = mi->module_idx;
	return 1;
    }

    // symbol not found - strange.
    printf("%s found func %s but not in dynamic library.\n", msgprefix,
	func_name);
    return 0;
}


/**
 * If a function is not always available in Gtk, retrieve it with
 * this helper; it throws an error if the function is not available.
 *
 * This ensures compatibility with older Gtk versions.
 */
void *lg_optional_func(lua_State *L, cmi mi, const char *name,
    const char *min_version)
{
    struct func_info fi;
    if (!lg_find_func(L, mi, name, &fi))
	luaL_error(L, "%s function %s not defined.  Please use at least %s",
	    msgprefix, name, min_version);
    return fi.func;
}


/**
 * Get a object from the Lua stack, checking its type (class).  It should at
 * least be some kind of object, not an unrelated userdata - might crash
 * otherwise.
 *
 * Note: a more thorough implementation could get the metatable and check that
 * it has a _typespec attribute etc.
 */
struct object *lg_object_arg(lua_State *L, int index, const char *name)
{
    luaL_checktype(L, index, LUA_TUSERDATA);
    struct object *o = (struct object*) lua_touserdata(L, index);
    const char *curr_name = lg_get_object_name(o);
    if (!strcmp(name, curr_name))
	return o;
    {
	char msg[100];
	snprintf(msg, sizeof(msg), "expected %s, is %s", name, curr_name);
	luaL_argerror(L, index, msg);
	return NULL;
    }
}


