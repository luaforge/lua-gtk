/** vim:sw=4:sts=4
 *
 * Support for the BDZ algorithm of the cmph library.  This code is copied
 * more or less verbatim from cmph's source file src/bdz.c.  That file is
 * released under the GNU General Public License Version 2, which applies
 * to this source file, too.
 *
 * This code is derived from the cmph library (http://cmph.sourceforge.net/)
 * version 0.9 by Davi de Castro Reis and Fabiano Cupertino Botelho.
 *
 * by Wolfgang Oertl 2008, 2009
 */

#include "lg-hash.h"
#include <cmph_types.h>
#include "hash-cmph.h"

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

static inline int BDZ_LOOKUP_TABLE(int idx)
{
    return bdz_lookup_table[idx];
}
#else
static inline int BDZ_LOOKUP_TABLE(int idx)
{
	return ((0x156a6a6a >> ((idx>>4)<<1)) & 3)
	    + ((0x156a6a6a >> ((idx&15)<<1)) & 3);
}

#endif

#if 0
// Generate the table to verify that it is correct.  It is.
int test_lookup_table()
{
    int i, v;

    for (i=0; i<256; i++) {
	v = BDZ_LOOKUP_TABLE(i);
	printf("%d, ", v);
	if (i % 16 == 15)
	    printf("\n");
    }
}
#endif



/**
 * Do something magical to compute a bucket number.
 */
static unsigned int rank(cmph_uint32 b, const cmph_uint32 *ranktable,
    const cmph_uint8 *g, cmph_uint32 vertex)
{
    int index = vertex >> b;

    // each ranktable entry is encoded as bdz->rt_item_size bytes, high->low
    int base_rank = ranktable[index];
    int beg_idx_v = index << b;
    int beg_idx_b = beg_idx_v >> 2;
    int end_idx_b = vertex >> 2;

    while (beg_idx_b < end_idx_b)
	base_rank += BDZ_LOOKUP_TABLE(*(g + beg_idx_b++));

    beg_idx_v = beg_idx_b << 2;
    while (beg_idx_v < vertex) {
	if (GETVALUE(g, beg_idx_v) != UNASSIGNED)
	    base_rank ++;
	beg_idx_v ++;
    }

    return base_rank;
}


/**
 * Compute a bucket number using the BDZ algorithm.
 *
 * @param hi  Hash Info containing the data for this algorithm
 * @param key  Pointer to the key string
 * @param keylen  Length of the key
 * @param hash_value  (output) computed hash value
 * @return  The bucket number
 */
const unsigned char *hash_search_bdz(lua_State *L, const struct hash_info *hi2,
    const unsigned char *key, int keylen, int *datalen)
{
    const struct hash_info_cmph *hi = (const struct hash_info_cmph*) hi2;
    const struct cmph_packed_bdz *bdz = (const struct cmph_packed_bdz*)
	hi->packed;
    unsigned int hl[3], vertex, hash_value;
    const cmph_uint8 *g = (cmph_uint8*) (bdz->ranktable + bdz->ranktablesize);
    cmph_uint8 b = *g++;
    cmph_uint32 r = bdz->r;

    /*
    printf("hash-search-bdz: hi=%p, method=%d, mask=%08x, offset_bits=%d,\n"
	"  length_bits=%d, index=%p, data=%p, bdz=%p, hashfunc=%d\n",
	hi, hi->method, hi->hash_mask, hi->offset_bits, hi->length_bits,
	hi->index, hi->data,
	bdz, bdz->hashfunc);
    */

    struct hash_state state = { hashfunc: lg_cmph_hashfunc_nr(bdz->hashfunc),
	seed: bdz->seed };

    hash_value = compute_hash(&state, key, keylen, hl);

    hl[0] = hl[0] % r;
    hl[1] = hl[1] % r + r;
    hl[2] = hl[2] % r + (r << 1);
    vertex = hl[(GETVALUE(g, hl[0]) + GETVALUE(g, hl[1])
	+ GETVALUE(g, hl[2])) % 3];

    return hash_search_cmph(L, hi2, datalen, hash_value, rank(b, bdz->ranktable,
	g, vertex));
}

