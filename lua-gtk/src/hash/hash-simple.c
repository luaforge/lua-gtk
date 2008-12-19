/** vim:sw=4:sts=4
 * Simple hash lookup function (i.e., not using a minimal perfect hash
 * function).  It is always available, easy to understand, and has little code.
 * It is therefore always compiled in.
 *
 * by Wolfgang 2006, 2007, 2008
 *
 * Space requirement: per (key, value pair) 64 bit plus the value.
 */

#include <string.h>
#include "lg-hash.h"
#include "config.h"

/**
 * Given a key, look it up in the hash table.  Returns NULL if not found,
 * or a pointer to the data of this entry.
 *
 * Layout of each 64 bit bucket:
 *  1 bit	    set if it is an overflow bucket
 *  15 bit	    high bits of the hash value
 *  16 bit	    number of the next overflow bucket
 *  20 bit	    offset of the data
 *  12 bit	    length of the data
 *
 * When the number of buckets is larger, then more of the hash value is used
 * to compute the bucket number.  No need to have more bits for the hash value
 * in the bucket.
 */
const unsigned char *hash_search_simple(const struct hash_info *_hi,
    const unsigned char *key, int keylen, int *datalen)
{
    unsigned int bucket_nr, v, hash;
    const struct hash_info_simple *hi = (const struct hash_info_simple*) _hi;

    /* calculate hash and get the bucket_nr */
    hash = compute_hash(&hi->hf, key, keylen, NULL);
    bucket_nr = hash & hi->bucket_mask;
    if (bucket_nr >= hi->bucket_count)
	bucket_nr -= hi->bucket_count;

    /* look at the bucket and its overflow buckets */

    /* the first bucket must not be an overflow, which would be indicated by
     * the high bit being set - this makes the (signed) number negative. */
    v = hi->buckets[bucket_nr << 1];
    if (((signed)v) < 0)
	return NULL;

    for (;;) {

	/* compare the upper 15 bits of hash value - if it matches, found. */
	if (((v ^ hash) & 0x7fff0000) == 0)
	    break;
	
	/* otherwise, go to next bucket */
	bucket_nr = v & 0x0000ffff;
	if (bucket_nr == 0)
	    return NULL;
	bucket_nr --;
	v = hi->buckets[bucket_nr << 1];
    }

    /* found; get data offset and length */
    v = hi->buckets[(bucket_nr<<1) + 1];

    *datalen = v >> 20;
    return hi->data + (v & ((1<<20)-1)) - 1;
}

