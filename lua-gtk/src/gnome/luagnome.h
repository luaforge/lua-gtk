// vim:sw=4:sts=4
//
// Include for the core module.  Here are functions and types that are used
// only within the "gnome" module, without being accessible directly by
// modules.
//

#include "common.h"

#ifdef LUAGTK_linux
#include <dlfcn.h>
#include <ffi.h>		/* foreign function interface library */
// #define EXPORT
#endif

#ifdef LUAGTK_win32
#include <windows.h>
#include "ffi.h"
// #define EXPORT __declspec(dllexport)
#ifndef __GNUC_PREREQ
# define __GNUC_PREREQ(maj,min) 0
#endif
#endif

// keys in the gtk module
extern char *lib_name;
#define LUAGTK_TBL	    lib_name
#define LUAGTK_METATABLES   "metatables"
#define LUAGTK_WIDGETS	    "objects"
#define LUAGTK_ALIASES	    "aliases"
#define LUAGTK_EMPTYATTR    "emptyattr"

// Access to type and structure element names
#define FTYPE_NAME(t) (gnome_ffi_type_names + (t)->name_ofs)

extern int module_count;
extern struct module_info **modules;

// structure to store values that were converted from Lua to C (i.e. FFI)
union gtk_arg_types {
    void	*p;		// 4 or 8 bytes
    long	l;
    long long	ll;		// 8 bytes
    double	d;
    float	f;
    int		i;
    signed char	sc;
    unsigned char uc;
};




/*-
 * All the lua2ffi_xxx and ffi2lua_xxx functions in types.c get this structure
 * as argument.  Passing the values individually would just be too much.
 *
 * If the function to be called is a Gtk function (Lua to Gtk), then ci->fi
 * is set.  Otherwise, a Lua function is to be called (as callback from Gtk
 * to Lua), ci->fi is not set.
 *
 * The typespec of the argument is already converted to the function's
 * module, so ts.module_idx need not be checked.
 */
struct argconv_t {
    lua_State	*L;
    int		mode;			// 0=call, 1=callback
    int		func_arg_nr;		// number of argument to function
    cmi		mi;			// module the type belogs to
    typespec_t	ts;			// luagtk type of the argument
    int		arg_flags;		// flags for this argument (see below)
    int		index;			// location of the input value
    union gtk_arg_types *arg;		// location of the output value
    const struct ffi_type_map_t *arg_type;
    int		lua_type;		// type of the input value
    struct call_info *ci;
    int		stack_top;		// index of last argument
    int		stack_curr_top;		// see below
};
#define ARGCONV_CALL 0
#define ARGCONV_CALLBACK 1
// stack_curr_top: While converting the Lua arguments to FFI values, the
// lua2ffi function shouldn't modify the Lua stack.  This is checked after
// each call.  When this is required, however, the lua2ffi function must
// update this variable.
//
// arg_flags: set for individual function's arguments in the library's config
// file.  Known flags are listed here, compare script/xml-types.lua
//#define ARG_FLAG_CONST 1		// immutable object, don't refcnt/free
//#define ARG_FLAG_CHAR_PTR 2		// treat as char* (not const char*)
//#define ARG_FLAG_NOT_NEW_OBJECT 4	// need to increase refcount

// argument to lua2struct/struct2lua functions
struct argconvs_t {
    lua_State	*L;
    typespec_t	ts;			// type of the _structure_
    const struct struct_elem *se;	// info about the element to r/w
    unsigned char *ptr;			// base address of the structure
    int index;				// for lua2struct, stack index of input
};

typedef int (*lua2ffi_t)(struct argconv_t*);
typedef int (*ffi2lua_t)(struct argconv_t*);
typedef int (*lua2struct_t)(struct argconvs_t*);
typedef int (*struct2lua_t)(struct argconvs_t*);

/*-
 * One entry in the type map.  By replacing pointers by indices to separate
 * tables, the size of each entry is just 8 bytes.
 */
struct ffi_type_map_t {
    unsigned int
	name_ofs : 10,		// offset into gnome_ffi_type_names (625)
	bit_len : 9,		// length in bits; max. 256
	indirections : 2,	// how many levels of pointers? max. 3
	conv_idx : 5,		// index into ffi_type_lua2ffi/ffi2lua
	structconv_idx : 4,	// index into ffi_type_lua2struct/struct2lua
	ffi_type_idx : 4;	// arg for FFI_TYPE() -> ffi_type*
};
extern struct ffi_type_map_t ffi_type_map[];
extern const int ffi_type_count;
extern const char gnome_ffi_type_names[];
extern const lua2ffi_t ffi_type_lua2ffi[];
extern const ffi2lua_t ffi_type_ffi2lua[];
extern const lua2struct_t ffi_type_lua2struct[];
extern const struct2lua_t ffi_type_struct2lua[];

// in types.c
void lg_empty_table(lua_State *L, int index);

// in voidptr.c
struct value_wrapper;
struct value_wrapper *lg_make_value_wrapper(lua_State *L, int index);
int lg_push_vwrapper_wrapper(lua_State *L, struct value_wrapper *wrp);
int lua2ffi_void_ptr(struct argconv_t *ar);
int lg_is_vwrapper(lua_State *L, void *p);
void lg_userdata_to_ffi(struct argconv_t *ar, ffi_type **argtype,
    int only_ptr);
int lg_vwrapper_get(lua_State *L, struct value_wrapper *wrp);

// in enum.c
int lg_push_constant(lua_State *L, typespec_t ts, int value);
struct lg_enum_t *lg_get_constant(lua_State *L, int index, typespec_t ts,
    int raise_error);

/*-
 * entry (type "userdata") in the meta table of a object.  These entries are
 * created on the first access to a method or attribute to make later
 * uses quicker.
 */
struct meta_entry {
    typespec_t ts;			/* 0=function */
    union {
	struct func_info fi;		/* 16 bytes */
	const struct struct_elem *se;   /* 4 bytes */
    };
    typespec_t iface_ts;		/* see below */
    GType iface_type_id;		/* GType of the interface */
    char name[0];
};
/* iface_*: if the meta_entry refers to a function found in an Interface,
 * then it can be overridden.  To make this assignment easier, i.e. avoid
 * searching all interfaces again, the type_idx of the interface is stored
 * here.  If 0, then this is not a virtual function.
 */

/*-
 * Objects are represented in Lua by this userdata.  It also has a metatable
 * that contains more information, see gtk2.c:get_object_meta.
 *
 * The table "gnome.objects" maps the object address to a reference in a second
 * table, aliases. These aliases can form a singly linked circular list.
 * Entries in the object table are not weak; entries in the aliases table are.
 * Garbage collection of aliases works like this:
 *
 *  - get the matching entry in "objects" using the "p" field (pointer)
 *  - if "next" is not 0, follow until an alias is found whose "next" points
 *    to the current alias; set its "next" to this "next" or 0
 *  - if the "first" of the alias entry points here, set it to this "next";
 *    if this was the last alias, remove the entry in objects.
 *
 * mm_type: index into the object_types table with names and pointers to
 * handler functions; these functions manage refcounting, which differs
 * between different types of objects.
 */


#define OBJECT_NAME(o) lg_get_object_name(o)

// Max. length of a complete type name
#define LG_TYPE_NAME_LENGTH 60

/*-
 * Information about one argument to a library function, or to a callback.
 */
struct call_arg {
    union gtk_arg_types ffi_arg;		// the actual value
    unsigned int is_output : 1,			// set if its an output arg
	free_method : 8;			// set if needs to be freed
};
#define FREE_METHOD_BOXED 1
#define FREE_METHOD_GVALUE 2


/*-
 * This structure holds all the variables describing a C function call.
 * Using this structure, the complex call function can be split into multiple
 * parts easily.  Additionally, elimination of global variables is good
 * for reentrancy (which isn't required, but still...).
 *
 * For each argument, various things have to be given to libffi, mainly the
 * type of the argument (ffi_type*), a void* to the location of the argument's
 * value (argvalues) besides other things.  These two have to be arrays and
 * therefore can't be put into struct call_arg.
 */
struct call_info {
    /* function info */
    lua_State *L;
    int index;			/* stack index of first parameter */
    struct func_info *fi;
    int warnings;		/* 0=no warning, 1=warning, 2=traced */
    int arg_count;		/* number of arguments including the retval */
    int arg_alloc;		/* number of slots allocated in args */

    /* arguments. [0] is for the return value */
    ffi_type **argtypes;
    void **argvalues;			    /* [0] not used */
    struct call_arg *args;

    union {
	struct call_info_list *first;	    /* allocated extra memory */
	struct call_info *next;		    /* chain of free call_infos */
    };
};

// in data.c
void lg_create_fundamental_map(lua_State *L);
int lg_register_module(lua_State *L, struct module_info *mi);
int lg_dl_init(struct dynlink *dyn);
int lg_make_func_name(char *buf, int buf_size, const char *class_name,
    const char *attr_name);
GType lg_gtype_from_name(lua_State *L, cmi mi, const char *s);
void lg_get_type_name_full(lua_State *L, typespec_t ts, char *buf);
const char *lg_get_type_name(typespec_t ts);
int lg_find_func(lua_State *L, cmi mi, const char *func_name,
    struct func_info *fi);
int lg_find_global(lua_State *L, cmi mi, const char *name);
typespec_t lg_find_struct(lua_State*, const char *type_name, int indir);
typespec_t lg_get_type(lua_State *L, const char *type_name);
const struct struct_elem *find_attribute(typespec_t ts, const char *attr_name);
int lg_find_constant(lua_State *L, typespec_t *ts, const char *key,
    int keylen, int *result);
const char *lg_get_object_name(struct object *o);
int lg_type_equal(lua_State *L, typespec_t ts1, typespec_t ts2);
type_info_t lg_get_type_info(typespec_t ts);
const unsigned char *lg_get_prototype(typespec_t ts);
const char *lg_get_struct_elem_name(int module_idx,
    const struct struct_elem *se);
const struct ffi_type_map_t *lg_get_ffi_type(typespec_t ts);
void *lg_optional_func(lua_State *L, cmi mi, const char *name,
    const char *min_version);
typespec_t lg_type_normalize(lua_State *L, typespec_t ts);
struct object *lg_object_arg(lua_State *L, int index, const char *name);
/* cmi lg_get_module(lua_State *L, const char *module_name); */
int lg_get_type_indirections(typespec_t ts);
typespec_t lg_type_modify(lua_State *L, typespec_t ts, int ind_delta);

// in debug.c
void lg_init_debug(lua_State *L);
int lg_debug_flags_global(lua_State *L);
int lg_breakfunc(lua_State *L);
int lg_object_tostring(lua_State *L);
void lg_call_trace(lua_State *L, struct func_info *fi, int index);

extern int runtime_flags;

// in object.c
void lg_get_object(lua_State *L, void *p, typespec_t ts, int flags);
struct object *lg_check_object(lua_State *L, int index);
void lg_invalidate_object(lua_State *L, struct object *w);

// in object_types.c
void lg_init_object(lua_State *L);
void lg_guess_object_type(lua_State *L, struct object *w, int flags);
int lg_register_object_type(const char *name, object_handler handler);
int lg_find_object_type(const char *name);
int lg_get_refcount(lua_State *L, struct object *w);
void lg_inc_refcount(lua_State *L, struct object *w, int flags);
void lg_dec_refcount(lua_State *L, struct object *w);
struct object_type *lg_get_object_type(lua_State *L, struct object *w);

// in object_meta.c
int lg_object_index(lua_State *L);
int lg_object_newindex(lua_State *L);


// in init.c
extern const char msgprefix[];
int lg_push_closure(lua_State *L, struct func_info *fi);

// in boxed.c
extern int lg_boxed_value_type;
void	lg_init_boxed(lua_State *L);
void*	lg_make_boxed_value(lua_State *L, int index);
int	lg_get_boxed_value(lua_State *L, const void *p);
void	lg_boxed_to_ffi(struct argconv_t *ar, ffi_type **argtype);
void	lg_boxed_free(gpointer val);

// in call.c
enum lg_msg_level { LUAGTK_DEBUG=0, LUAGTK_INFO, LUAGTK_WARNING, LUAGTK_ERROR };
int lg_call(lua_State *L, struct func_info *fi, int index);
int lg_call_byname(lua_State *L, cmi mi, const char *func_name);
int lg_call_function(lua_State *L, const char *mod_name, const char *func_name);
void call_info_warn(struct call_info *ci);
void call_info_msg(struct call_info *ci, enum lg_msg_level level,
    const char *format, ...);
struct call_info *call_info_alloc();
void *call_info_alloc_item(struct call_info *ci, int size);
void call_info_check_argcount(struct call_info *ci, int n);
void call_info_free(struct call_info *ci);
void call_info_free_pool();
inline void get_next_argument(lua_State *L, const unsigned char **p,
    struct argconv_t *ar);

// closure.c
void lg_init_closure(lua_State *L);
void lg_done_closure();
int lg_create_closure(lua_State *L, int index, int is_automatic);
void *lg_use_closure(lua_State *L, int index, typespec_t ts,
    int arg_nr, const char *func_name);

// gvalue.c
void lg_lua_to_gvalue_cast(lua_State *L, int index, GValue *gv, GType gtype);
GValue *lg_lua_to_gvalue(lua_State *L, int index, GValue *gvalue);
void lg_gvalue_to_lua(lua_State *L, GValue *gv);

