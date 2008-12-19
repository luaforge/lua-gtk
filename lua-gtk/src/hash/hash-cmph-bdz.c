/** vim:sw=4:sts=4
 *
 * Support for the BDZ algorithm of the cmph library.  This code is copied
 * more or less verbatim from cmph's source file src/bdz.c.  That file is
 * released under the GNU General Public License Version 2, which applies
 * to this source file, too.
 *
 * This code is derived from the cmph library (http://cmph.sourceforge.net/)
 * version 0.8 by Davi de Castro Reis and Fabiano Cupertino Botelho.
 *
 * by Wolfgang Oertl 2008
 */

#include "lg-hash.h"

/* Get two bits from the array, i being the index */
#define GETVALUE(array, i) ((array[i >> 2] >> ((i & 3) << 1)) & 3)
#define UNASSIGNED 3

// This flag replaces a 256 byte table with a little code.
#define SMALL_SIZE

#ifndef SMALL_SIZE
static const unsigned char bdz_lookup_table[] =
{
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
4, 4, 4, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 3, 3, 2,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 2, 2, 2, 1,
2, 2, 2, 1, 2, 2, 2, 1, 2, 2, 2, 1, 1, 1, 1, 0
};
#endif

/**
 * Do something magical to compute a bucket number.
 */
static unsigned int rank(const struct hash_info_bdz *bdz, unsigned int vertex)
{
    int index = vertex >> bdz->b;

    // each ranktable entry is encoded as bdz->rt_item_size bytes, high->low
    int base_rank = 0;
    int i = bdz->rt_item_size;
    int idx = index * i;
    while (i) {
	base_rank = (base_rank << 8) + bdz->ranktable[idx];
	idx ++;
	i --;
    }

    int beg_idx_v = index << bdz->b;
    int beg_idx_b = beg_idx_v >> 2;
    int end_idx_b = vertex >> 2;

    while (beg_idx_b < end_idx_b) {
#ifdef SMALL_SIZE
	int idx = *(bdz->g + beg_idx_b++);
	base_rank += ((0x156a6a6a >> ((idx>>4)<<1)) & 3)
	    + ((0x156a6a6a >> ((idx&15)<<1)) & 3);
#else
	base_rank += bdz_lookup_table[*(bdz->g + beg_idx_b++)];
#endif
    }

    beg_idx_v = beg_idx_b << 2;
    while (beg_idx_v < vertex) {
	if (GETVALUE(bdz->g, beg_idx_v) != UNASSIGNED)
	    base_rank++;
	beg_idx_v++;
    }

    return base_rank;
}


/**
 * Compute a bucket number using the BDZ algorithm.
 * @param hi  Hash Info containing the data for this algorithm
 * @param key  Pointer to the key string
 * @param keylen  Length of the key
 * @param hash_value  (output) computed hash value
 * @return  The bucket number
 */
const unsigned char *hash_search_bdz(lua_State *L, const struct hash_info *hi2,
    const unsigned char *key, int keylen, int *datalen)
{
    const struct hash_info_bdz *hi = (const struct hash_info_bdz*) hi2;
    unsigned int hl[3], vertex, hash_value;

    hash_value = compute_hash(&hi->hl, key, keylen, hl);

    hl[0] = hl[0] % hi->r;
    hl[1] = hl[1] % hi->r + hi->r;
    hl[2] = hl[2] % hi->r + (hi->r << 1);
    vertex = hl[(GETVALUE(hi->g, hl[0]) + GETVALUE(hi->g, hl[1])
	+ GETVALUE(hi->g, hl[2])) % 3];

    return hash_search_cmph(L, hi2, datalen, hash_value, rank(hi, vertex));
}

