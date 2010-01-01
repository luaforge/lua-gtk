/** vim:sw=4:sts=4
 * Hash lookup routines for minimal perfect hashes as generated by the
 * cmph utility.
 */

#include "../gnome/luagnome.h"	    /* lua_State, msgprefix */
#include "lg-hash.h"		    /* hash_info, bdz_search etc. */
#include <cmph_types.h>
#include <stdio.h>		    /* NULL */


/**
 * Convert the hash function number as used by CMPH to LuaGnome's numbering.
 * This ensures that the numbers in LuaGnome modules always mean the same,
 * regardless of the CMPH library version.
 */
int lg_cmph_hashfunc_nr(CMPH_HASH func_nr)
{
    if (func_nr == CMPH_HASH_JENKINS)
	return HASHFUNC_JENKINS;

    printf("could not convert hashfunc from cmph to luagnome: %d\n",
	func_nr);
    return -1;
}

#if 0
#ifdef LUAGTK_win32_i386
  #define __BIG_ENDIAN 1
  #define __BYTE_ORDER 0
#else
#include <endian.h>
#endif
#endif

/**
 * After computing a hash value and a bucket number using whatever CMPH hash
 * function was used, verify that the key exists and then retrieve the
 * associated value.
 *
 * Each bucket is 32 bit in size and contains, in a variable number of bits,
 * part of the hash value and the offset to the data.  If bucket merging
 * is enabled, the data length is also stored.
 * 
 * Returns: NULL on failure, otherwise the pointer to the data; *datalen is
 * filled with the length in bytes of the data.
 */
const unsigned char *hash_search_cmph(lua_State *L, const struct hash_info *hi2,
    int *datalen, unsigned int hash_value, unsigned int bucket_nr)
{
    const struct hash_info_cmph *hi = (const struct hash_info_cmph*) hi2;
    unsigned int bucket;

    // Check the hash value, but only the bits set in the hash mask.
    bucket = hi->index[bucket_nr];
    if ((hash_value ^ bucket) & hi->hash_mask)
	return NULL;

    // Found, now determine data offset and length.  If length_bits is set,
    // then the bucket already contains the length.
    bucket &= ~hi->hash_mask;
    if (hi->length_bits) {
	*datalen = (bucket & ((1 << hi->length_bits) - 1)) + 1;
	return hi->data + (bucket >> hi->length_bits);
    }

    // Not using combining, which is not likely.  The length of the data
    // is determined by the data offset of the next bucket.
    unsigned int bucket2 = hi->index[bucket_nr + 1] & ~hi->hash_mask;
    *datalen = bucket2 - bucket;
    return hi->data + bucket;
}

