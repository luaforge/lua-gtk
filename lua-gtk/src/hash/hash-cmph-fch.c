/** vim:sw=4:sts=4
 *
 * Support for the FCH algorithm of the cmph library, which is an older and
 * less powerful algorithm than BDZ, which is also supported.
 * by Wolfgang Oertl 2007
 *
 * This code is derived from the cmph library (http://cmph.sourceforge.net/)
 * version 0.6 by Davi de Castro Reis and Fabiano Cupertino Botelho.
 *
 * I could have linked lua-gtk with the cmph library, but that would have
 * resulted in an almost 50 kB larger lua-gtk.  This is so because the cmph
 * library supports more algorithms and includes the generation code too,
 * whereas I only need the very much simpler lookup code at runtime.
 */

#include "lg-hash.h"


/**
 * From fch.c.
 *
 * Note: the type of p1 and p2 was changed from float to unsigned int, because
 * they can only contain integers anyway.
 */
static int mixh10h1h12(unsigned int b, unsigned int p1, unsigned int p2,
    unsigned int i)
{
    if (i < p1) {
	i %= p2;
    } else {
	i %= b;
	if (i < p2)
	    i += p2;
    }

    return i;
}


/**
 * Hash lookup function.  Returns a bucket number; any input string results
 * in a valid bucket.  Whether the key is in the hash table has to be
 * determined later from the contents of the bucket.
 */
const unsigned char *hash_search_fch(lua_State *L, const struct hash_info *hi2,
    const unsigned char *key, int keylen, int *datalen)
{
    const struct hash_info_fch *hi = (const struct hash_info_fch*) hi2;
    unsigned int h1, h2, g, hash_value;

    // Calculate a first hash value; it is also used for comparison with the
    // hash value stored in the bucket to identify hits and misses.
    hash_value = h1 = compute_hash(&hi->h1, key, keylen, (void*)0);

    // The first hash value is used to achieve the "minimal" and "perfect"
    // properties of the hash algorithm.  Using it an entry in the "g"
    // table is looked up, which is added to the second hash value and
    // mapping it to the interval [0, n-1] without holes or duplicates.
    h1 = mixh10h1h12(hi->b, hi->p1, hi->p2, h1 % hi->m);

    // The "g" table may contain 16 or 32 bit entries depending on the
    // number of buckets; up to 2 ^ 16 it is enough to store 16 bit.
    switch (hi->g_size) {
	case 16:
	g = hi->g[h1];
	break;

	case 32:
	g = hi->g[h1 * 2] + (hi->g[h1*2 + 1] << 16);
	break;

	default:
	return (void*) 0;
    }

    // Calculate the second hash value and the final bucket number.
    h2 = compute_hash(&hi->h2, key, keylen, (void*)0) % hi->m;
    return hash_search_cmph(L, hi2, datalen, hash_value, (h2 + g) % hi->m);
}


