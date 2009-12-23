/** vim:sw=4:sts=4
 * Hash functions and methods as used in LuaGnome.
 *
 * A "hash function" computes a hash value for a key.
 *
 * A "hash method" maps a key to a bucket, and requires at least one hash
 *   function to do this, as well as some kind of bucket list with the data.
 */


/* Complete information on what hash algorithm to use, plus optional extra
 * data depending on the algorithm. */
struct hash_state {
    int hashfunc;		/* which hash function to use, see below */
    int seed;			/* for jenkins */
};

// Define all the hash functions you want to include, but don't change the
// numbers.
#define HASHFUNC_JENKINS 1
#define HASHFUNC_HSIEH 2
#define HASHFUNC_DJB2 3
#define HASHFUNC_FNV 4
#define HASHFUNC_SDBM 5

extern const char hash_function_names[];

// must not change, only append, to maintain binary compatibility
typedef enum { HASH_CMPH_FCH, HASH_CMPH_BDZ, HASH_SIMPLE } method_t;

// all hash_info structures begin like this.
struct hash_info {
    method_t method;
};


/* SIMPLE HASH */

// In order to make the code simple, a fixed bucket layout is used.
typedef struct {
    unsigned int
	is_overflow	: 1,
	hash_bits	: 15,
	next_overflow	: 16,
	data_length	: 12,
	data_offset	: 20;
} bucket_t;

// Data structure for the simple hash algorithm
struct hash_info_simple {
    method_t method;
    struct hash_state hf;	/* hash function to use */
    unsigned int bucket_count;
    unsigned int bucket_mask;
    unsigned const int *buckets;	/* 2*32 bit per entry */
    unsigned const char *data;
};

// common for all cmph based methods
struct hash_info_cmph {
    method_t method;
    unsigned int hash_mask;
    unsigned int offset_bits, length_bits;
    const unsigned int *index;	    // hash value, data offset and length
    const unsigned char *data;	    // actual data
    const unsigned char packed[];    // packed hash function
};

extern const char *hash_method_names[];

#ifndef lua_h
typedef struct lua_State lua_State;
#endif

// Generic search
const unsigned char *hash_search(lua_State *L, const struct hash_info *hi,
    const unsigned char *key, int keylen, int *datalen,
    const char *module_name);
unsigned int compute_hash(const struct hash_state *state,
    const unsigned char *key, int keylen, unsigned int *vector);

// internal functions for cmph
const unsigned char *hash_search_cmph(lua_State *L, const struct hash_info *hi,
    int *datalen, unsigned int hash_value, unsigned int bucket_nr);
const unsigned char *hash_search_bdz(lua_State *L, const struct hash_info *hi2,
    const unsigned char *key, int keylen, int *datalen);
const unsigned char *hash_search_fch(lua_State *L, const struct hash_info *hi2,
    const unsigned char *key, int keylen, int *datalen);

// internal functions for simple hash
const unsigned char *hash_search_simple(const struct hash_info *hi,
    const unsigned char *key, int keylen, int *datalen);

