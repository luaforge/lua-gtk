/** vim:sw=4:sts=4
 * Routine to look up a key in a hash table.
 */

#include <lua.h>
#include <lauxlib.h>
// #include "common.h"
#include "lg-hash.h"
#include "config.h"

extern const char msgprefix[];
const char *hash_method_names[] = { "fch", "bdz", "simple" };

const unsigned char *hash_search(lua_State *L, const struct hash_info *hi,
    const unsigned char *key, int keylen, int *datalen, const char *module_name)
{
    switch (hi->method) {
#ifdef CMPH_USE_bdz
	case HASH_CMPH_BDZ:
	    return hash_search_bdz(L, hi, key, keylen, datalen);
#endif

#ifdef CMPH_USE_fch
	case HASH_CMPH_FCH:
	    return hash_search_fch(L, hi, key, keylen, datalen);
#endif
	
	case HASH_SIMPLE:
	    return hash_search_simple(hi, key, keylen, datalen);

	default:
	    luaL_error(L, "%s Module %s is compiled with hash method %s, "
		"which is not supported by the core module \"gnome\".  "
		"Please recompile.",
		msgprefix, module_name, hash_method_names[hi->method]);
	    return NULL;
    }

}

