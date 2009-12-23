// vim:sw=4:sts=4
// Declarations used by the library modules

#include "common.h"

extern struct lg_module_api *api;
extern const char *thismodulename;
extern struct module_info *thismodule;
extern const struct luaL_reg module_methods[];
int load_gnome(lua_State *L);

/**
 * This structure is used by modules to communicate with the core (gnome)
 * module.  It basically contains version information and a jump table.  The
 * major version must match and the minor version of the core module must be >= 
 * the version of the library module.
 *
 * The jump table makes calls to the core functions easy: just do
 * retval = api->funcname(arg1, arg2);
 * 

 */
struct lg_module_api {
    int	major, minor;
    const char *hash_method;
    const char *msgprefix;
    int (*register_module)(lua_State *L, struct module_info *mi);
    int (*register_object_type)(const char *name, object_handler handler);

/* JUMP TABLE */
    const char *(*get_object_name)(struct object *o);
    int (*generic_index)(lua_State *L);
    int (*generic_new_array)(lua_State *L, cmi mi, int is_array);
    const char *(*get_type_name)(typespec_t ts);

    typespec_t (*find_struct)(lua_State *L, const char *type_name,
	int indirections);
    void *(*optional_func)(lua_State *L, cmi mi, const char *name,
	const char *min_version);
    int (*call_byname)(lua_State *L, cmi mi, const char *func_name);
    int (*call_function)(lua_State *L, const char *module_name,
	const char *func_name);
    void (*lua_to_gvalue_cast)(lua_State *L, int index, GValue *gv, GType type);
    int (*find_object_type)(const char *name);
    GType (*gtype_from_name)(lua_State *L, cmi mi, const char *s);
    void (*get_object)(lua_State *L, void *p, typespec_t ts, int flags);
    struct object_type *(*get_object_type)(lua_State *L, struct object *w);
    void (*invalidate_object)(lua_State *L, struct object *w);
    void (*push_gvalue)(lua_State *L, GValue *gv);
    struct object *(*object_arg)(lua_State *L, int index, const char *name);
    int (*push_constant)(lua_State *L, typespec_t ts, int value);
    struct lg_enum_t *(*get_constant)(lua_State *L, int index, typespec_t ts,
	int raise_error);

    void (*empty_table)(lua_State *L, int index);
    struct module_info *(*find_module)(const char *name);	/* added 2009-11-27 */
};
#define LUAGNOME_MODULE_MAJOR 0
#define LUAGNOME_MODULE_MINOR 10


