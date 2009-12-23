/** vim:sw=4:sts=4
 *
 * Internal structures of CMPH.
 * This applies to version 0.9.
 */

/* The hash function data is stored in "packed" form as produced by
 * CMPH starting with version 0.8.  Format:
 */
struct cmph_packed_bdz {
    cmph_uint32	algorithm, hashfunc, seed, r, ranktablesize;
    cmph_uint32 ranktable[0];	    // length is "ranktablesize" uint32's
    // after this: "b" (one byte) and the array "g" (with bytes in it).
};

struct lg_cmph_packed {
    cmph_uint32 algorithm, hashfunc, seed;
};


int lg_cmph_hashfunc_nr(CMPH_HASH func_nr);

