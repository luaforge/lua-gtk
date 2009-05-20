// vim:sw=4:sts=4
// Declarations used by both the core module (gnome) and the library modules
// (e.g. glib, gtk)

#ifndef __LUAGNOME_COMMON_H__
#define __LUAGNOME_COMMON_H__

#include "config.h"
#include <lua.h>
#include <lauxlib.h>
#include <glib.h>
#include <glib-object.h>

/*-
 * To specify the type of an object, we need to know which module and there
 * which type.  Each type can be present in multiple modules, but only one
 * is the "native" module (that has the whole definition), and so typespecs
 * usually refer to this native module.  When this is not so, this should
 * be documented in the code.
 *
 * flag: used only in special situations (see lg_enum_t).
 * value: can be used to quickly compare for equality, or to store/retrieve
 * the whole type_spec to/from an integer.
 */
union type_spec {
    unsigned int value;
    struct {
	unsigned int type_idx : 22, module_idx : 8, flag : 2;
    };
};
typedef union type_spec typespec_t;


/*-
 * Some functions from the dynamic libraries are used from this code.  To avoid
 * linking the DLL directly, they are looked up once at init time after
 * manually loading the DLL.  Calls are redirected to function pointers;
 * see script/make-link.lua for more information.
 */
typedef void (*linkfuncptr)();

typedef const struct module_info *cmi;


/*-
 * Each entry in a module's type list describes one data type.  The "type of
 * the type" is named "genus" here for want of a better term.  
 */
union type_info {
    // non-native types
    struct {
	unsigned int
	    genus : 2,			// is GENUS_NON_NATIVE (0)
	    name_is_module : 1,		// 0=name is typename; else is modname
	    padding : 13,
	    name_ofs : 16,
	    name_hash : 32;		// hash value of the type's name
    } nn;

    // structures
    struct {
	unsigned int
	    genus : 2,			// is 1, or 3 for fundamental types
	    fundamental_idx : 6,	// refers to struct, union or struct*...
	    name_ofs : 16,
	    indirections : 2,

	    padding: 4,
	    is_const : 1,
	    is_array : 1,
	    struct_size : 11,
	    elem_start : 13,
	    elem_count : 8;
    } st;

    // functions
    struct {
	unsigned int
	    genus : 2,			// is GENUS_FUNCTION (2)
	    fundamental_idx : 6,
	    name_ofs : 16,
	    indirections : 2,

	    padding1: 6,
	    signature_ofs : 16,
	    padding2: 16;
    } fu;

};
typedef const union type_info *type_info_t;

// possible values of genus:
#define GENUS_NON_NATIVE	0
#define GENUS_STRUCTURE 1
#define GENUS_FUNCTION 2
#define GENUS_FUNDAMENTAL 3

// Specify the dimensions for data types which are arrays (is_array set)
struct array_info {
    unsigned short type_idx;	    // what type_idx (of this module)
    unsigned char dim[2];	    // [1] is zero for one-dimensional arrays
};


/* Information about a function in the shared library.  This structure
 * is filled before calling lg_call. */
struct func_info {
    void *func;			/* address of the function */
    const char *name;		/* full name in dynamic library;
				   usually malloc()ed */
    int module_idx;		/* which module this is in */
    const unsigned char *args_info;
    int args_len;
};

/*-
 * Description of one structure element.  Size: 6 bytes (48 bits).
 *
 * name_ofs: offset into type_strings_elem where the name of the element can be
 * found.
 * bit_offset: position within the structure
 * bit_length: length of this item; if 0, use type_idx
 * type_idx: index into the module's type_list
 *
 * 8 bits are still unused; the compiler probably pads to 64 bit.  It could
 * reduced to about 50 bit.
 */
struct struct_elem {
    unsigned int
	name_ofs : 16,		/* curr max 11248 */
	bit_offset : 14,	/* curr max 8224 */
	bit_length : 14,    	/* curr max ca. 600, if 0 look at type */
	type_idx : 12;		/* curr max 834 */
};


/**
 * When loading and resolving shared libraries at runtime, use this
 * structure.
 */
struct dynlink {
    const char *dll_list;			// see below
    const char *dynlink_names;
    linkfuncptr *dynlink_table;
    int dll_count;				// length of dll_list
    void **dl_handle;				// array of handles
    void *dl_self_handle;			// handle of module's .so
};

/* dll_list is needed when the libraries are to be dynamically loaded.
 * On Windows, the list is needed even without runtime linking to get the
 * module handles.
 */

/*-
 * Entry in the "aliases" table.
 *
 * Note: storing a reference to the next entry is not enough.  During garbage
 * collection, some or all of the entries in "aliases" might be removed before
 * the GC methods are called.  The references therefore don't exist anymore.
 * So instead a pointer is stored.  This is OK because before a object is
 * really free()d, it is removed from the circular list (if any).
 *
 * Size: 5*4 bytes = 20 on 32 bit, 28 byte on 64 bit architectures.
 */
struct object {
    void *p;			/* addr of the object & key to "objects" tbl */
    int own_ref;		/* ref in gtk.aliases */
    typespec_t ts;		/* could be a short LRU array */
    unsigned int
	mm_type : 8,		/* how memory management is done */
	is_deleted : 1,		/* has been freed, *p is NULL */
	is_new : 1,		/* has just been created */
	array_size : 16,	/* if this is an array, how large it is */
	flags: 10;		/* meaning depends on type_idx */
    struct object *next;	/* ptr to next alias, or NULL if just one */
};

// The fundamental_idx stored in module_info.type_info is an index to the
// fundamental_map, which points to the appropriate entries in ffi_type_map.
// This allows for runtime mapping of a module's ffi types to the numberes
// used in the core library.

// operations defined on object type handlers
typedef enum {
    WIDGET_SCORE,
    WIDGET_GET_REFCOUNT,
    WIDGET_REF,
    WIDGET_UNREF,
} object_op;

// Flags to lg_get_object.
// Available bits: 8 (usage also in function signatures).
// NOTE: must match the function_flag_map in script/util.lua.
#define FLAG_CONST_OBJECT 1	    // returned object is constant; don't free
#define FLAG_NOT_NEW_OBJECT 2	    // returned object is not new; inc refcnt
#define FLAG_DONT_FREE 4	    // don't free the output string
#define FLAG_INCREF 8		    // increase ref of retval/arg after call
#define FLAG_NOINCREF 16	    // returned object is new, but ref'd already
#define FLAG_OBJECT_FLAG 0x80	    // lower 7 bits are an object flag

// flags with values 0x0100 and above cannot be used for function arguments.
#define FLAG_NEW_OBJECT 0x0100	    // for documentation purposes
#define FLAG_ALLOCATED 0x0200
#define FLAG_ARRAY 0x0400
#define FLAG_ARRAY_ELEMENT 0x0800
#define FLAG_CHAR_PTR 0x1000
#define FLAG_CONST_CHAR_PTR 0x2000

typedef int (*object_handler)(struct object*, object_op, int);

struct object_type {
    const char *name;
    object_handler handler;
};

struct hash_info;


/**
 * Each module has such a structure to register itself with the core module,
 * describing itself and exporting its symbols.
 */
struct module_info {
    // const data
    int major, minor;				// API version expected
    const char *name;				// the module's name
    type_info_t type_list;			// array of types
    const struct struct_elem *elem_list;	// array of structure elements
    int type_count;				// length of "type_list"
    const unsigned int *fundamental_hash;	// hashes of used fund. types
    int fundamental_count;
    const struct array_info *array_list;	// info about array types

    // const data (strings)
    const char *type_strings_elem;
    const unsigned char *prototypes;
    const char *type_names;
    const char *globals;

    // functions
    const struct hash_info *hash_functions;
    const struct hash_info *hash_constants;

    void *(*allocate_object)(cmi mi, lua_State *L, typespec_t ts, int count,
	int *flags);
    void (*call_hook)(lua_State *L, struct func_info *fi);
    int (*arg_flags_handler)(lua_State *L, typespec_t ts, int arg_flags);

    // other useful strings
    const char *prefix_func;			// prefix for functions
    const char *prefix_constant;		// prefix for constants
    const char *prefix_type;			// prefix for types
    const char *prefix_func_remap;		// class name -> func prefix

    // only required during initialization
    const char *depends;
    const luaL_reg *methods;
    const luaL_reg *overrides;

    // filled in at runtime
    unsigned short *sorted_types;		// sorted list of types
    int *fundamental_map;			// see below
    int module_idx;				// index given to this module
    struct dynlink dynlink;
    int module_ref;				// ref to the module's table
};

// macros to emit translatable messages
#define LG_ERROR(id, ...) lg_error(L, thismodulename, id, __VA_ARGS__)
#define LG_ARGERROR(narg, id, ...) lg_argerror(L, narg, thismodulename, id, \
    __VA_ARGS__)

// pushes the translated message prefixed with the message id onto the Lua stack
#define LG_MESSAGE(id, ...) lg_message(L, thismodulename, id, __VA_ARGS__)

void lg_message(lua_State *L, const char *modname, int id, const char *fmt,
    ...);
int lg_error(lua_State *L, const char *modname, int id, const char *fmt, ...);
int lg_argerror(lua_State *L, int narg, const char *modname, int id,
    const char *fmt, ...);

/*-
 * ENUM and FLAG values are stored as a userdata with this structure.
 * Size: 12 bytes (96 bit)
 */
struct lg_enum_t {
    signed int	value;		// current value
    GType	gtype;		// cache for GType of ts; unsigned int
    typespec_t	ts;		// ts.flag: 1=enum, 2=flags
};
#define ENUM_META "enum_flags"
#define LUAGTK_TO_ENUM(L, idx) (struct lg_enum_t*) luaL_checkudata(L, idx, \
    ENUM_META)


// bits to be set in runtime_flags
#define RUNTIME_TRACE_ALL_CALLS	    1
#define RUNTIME_WARN_RETURN_VALUE   2	/* warn about unused return values */
#define RUNTIME_DEBUG_MEMORY	    4	/* show allocation and GC of objs */
#define RUNTIME_GMEM_PROFILE	    8	/* enable g_mem_profile */
#define RUNTIME_VALGRIND	    16	/* valgrind friendly */
#define RUNTIME_DEBUG_CLOSURES	    32	/* don't free closures until end */
#define RUNTIME_PROFILE		    64	/* runtime profiling */

#ifdef RUNTIME_LINKING
#include "link.h"
#endif

#endif

