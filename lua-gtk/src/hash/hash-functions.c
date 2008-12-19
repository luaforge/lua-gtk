/*- vim:sw=4:sts=4
 *
 * This is a collection of a few hash functions: djb2, fnv, sdbm, jenkins,
 * hsieh.  Which one is used depends on the data file, but usually jenkins will
 * be used.  These functions take a key and length, and return a hash value,
 * sometimes additionally a vector of three values.
 *
 * The reason for using jenkins is that it provides three hash values instead
 * of just one, which is required by the bdz algorithm of cmph-0.8.  The
 * tradeoff is a much more complicated algorithm that otherwise doesn't add
 * much value for this use, I guess.
 */

#include "lg-hash.h"
#include <stdio.h>		/* fprintf */
#include <stdlib.h>		/* exit */

// List of supported hash functions.  #0 is reserved.
const char hash_function_names[] =
    "-\0"
    "jenkins\0"
    "hsieh\0"
    "djb2\0"
    "fnv\0"
    "sdbm\0"
;


#ifdef HASHFUNC_DJB2

/**
 * These hash functions are all from the cmph sources, where they can be found
 * in the xxx_hash.c files.  In version 0.8, only hash_jenkins remains.  Note
 * that cmph version has an xor operation instead of the addition (a change
 * supposedly favored by Dan Bernstein, the author of this algorithm).
 */
static inline unsigned int hash_djb2(const unsigned char *key, int len)
{
    unsigned int hash = 5381;
    const unsigned char *key_end = key + len;

    while (key < key_end)
	hash = ((hash << 5) + hash) ^ *key++;	    /* hash*33 + nextbyte */

    return hash;
}

#endif

#ifdef HASHFUNC_FNV

/**
 * See http://www.isthe.com/chongo/tech/comp/fnv/.  The algorithm included in
 * cmph-0.6 is therefore "FNV-0", which is obsolete; it doesn't have a non-zero
 * initialization for "hash".
 */
static inline unsigned int hash_fnv(const unsigned char *key, int len)
{
    unsigned int hash = 0;
    unsigned const char *key_end = key + len;

    while (key < key_end) {
	/* hash *= 16777619, but in an optimized fashion */
	hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8)
	    + (hash << 24);
	hash ^= *key++;
    }

    return hash;
}

#endif

#ifdef HASHFUNC_SDBM

static inline unsigned int hash_sdbm(const unsigned char *key, int len)
{
    unsigned int hash = 0;
    unsigned const char *key_end = key + len;

    while (key < key_end) {
	hash = *key + (hash << 6) + (hash << 16) - hash;
	key ++;
    }
    
    return hash;
}

#endif


#ifdef HASHFUNC_JENKINS

 /*
 * A supposedly good hash function.
 * by Bob Jenkins
 *
 * Source:
 * http://burtleburtle.net/bob/hash/doobs.html
 */

typedef  unsigned int  ub4;   /* unsigned 4-byte quantities */
typedef  unsigned char ub1;   /* unsigned 1-byte quantities */

#define hashsize(n) ((ub4)1<<(n))
#define hashmask(n) (hashsize(n)-1)

/*
--------------------------------------------------------------------
mix -- mix 3 32-bit values reversibly.
For every delta with one or two bits set, and the deltas of all three
  high bits or all three low bits, whether the original value of a,b,c
  is almost all zero or is uniformly distributed,
* If mix() is run forward or backward, at least 32 bits in a,b,c
  have at least 1/4 probability of changing.
* If mix() is run forward, every bit of c will change between 1/3 and
  2/3 of the time.  (Well, 22/100 and 78/100 for some 2-bit deltas.)
mix() was built out of 36 single-cycle latency instructions in a 
  structure that could supported 2x parallelism, like so:
      a -= b; 
      a -= c; x = (c>>13);
      b -= c; a ^= x;
      b -= a; x = (a<<8);
      c -= a; b ^= x;
      c -= b; x = (b>>13);
      ...
  Unfortunately, superscalar Pentiums and Sparcs can't take advantage 
  of that parallelism.  They've also turned some of those single-cycle
  latency instructions into multi-cycle latency instructions.  Still,
  this is the fastest good hash I could find.  There were about 2^^68
  to choose from.  I only looked at a billion or so.
--------------------------------------------------------------------
*/
#define mix(a,b,c) \
{ \
  a -= b; a -= c; a ^= (c>>13); \
  b -= c; b -= a; b ^= (a<<8); \
  c -= a; c -= b; c ^= (b>>13); \
  a -= b; a -= c; a ^= (c>>12);  \
  b -= c; b -= a; b ^= (a<<16); \
  c -= a; c -= b; c ^= (b>>5); \
  a -= b; a -= c; a ^= (c>>3);  \
  b -= c; b -= a; b ^= (a<<10); \
  c -= a; c -= b; c ^= (b>>15); \
}

/*
--------------------------------------------------------------------
hash() -- hash a variable-length key into a 32-bit value
  k       : the key (the unaligned variable-length array of bytes)
  len     : the length of the key, counting by bytes
  initval : can be any 4-byte value
Returns a 32-bit value.  Every bit of the key affects every bit of
the return value.  Every 1-bit and 2-bit delta achieves avalanche.
About 6*len+35 instructions.

The best hash table sizes are powers of 2.  There is no need to do
mod a prime (mod is sooo slow!).  If you need less than 32 bits,
use a bitmask.  For example, if you need only 10 bits, do
  h = (h & hashmask(10));
In which case, the hash table should have hashsize(10) elements.

If you are hashing n strings (ub1 **)k, do it like this:
  for (i=0, h=0; i<n; ++i) h = hash( k[i], len[i], h);

By Bob Jenkins, 1996.  bob_jenkins@burtleburtle.net.  You may use this
code any way you wish, private, educational, or commercial.  It's free.

See http://burtleburtle.net/bob/hash/evahash.html
Use for hash table lookup, or anything where one collision in 2^^32 is
acceptable.  Do NOT use for cryptographic purposes.
--------------------------------------------------------------------
*/

/**
 * Calculate the hash value using the Jenkins algorithm.
 *
 * @param k  key string
 * @param length  length of the key
 * @param initval  previous hash, or an arbitrary value
 * @param vector  place to store the internal state variables a, b, c
 * @return  the hash value
 */
static ub4 hash_jenkins(const unsigned char *k, int length, ub4 initval,
    ub4 *vector)
{
    ub4 a, b, c, len;

    /* Set up the internal state */
    len = length;
    a = b = 0x9e3779b9;		/* the golden ratio; an arbitrary value */
    c = initval;		/* the previous hash value */

    /* handle most of the key */
    while (len >= 12) {
	a += (k[0] +((ub4)k[1]<<8) +((ub4)k[2]<<16) +((ub4)k[3]<<24));
	b += (k[4] +((ub4)k[5]<<8) +((ub4)k[6]<<16) +((ub4)k[7]<<24));
	c += (k[8] +((ub4)k[9]<<8) +((ub4)k[10]<<16)+((ub4)k[11]<<24));
	mix(a,b,c);
	k += 12; len -= 12;
    }

    /* handle the last 11 bytes */
    c += length;
    switch(len) {
	case 11: c+=((ub4)k[10]<<24);
	case 10: c+=((ub4)k[9]<<16);
	case 9 : c+=((ub4)k[8]<<8);

	/* the first byte of c is reserved for the length */
	case 8 : b+=((ub4)k[7]<<24);
    	case 7 : b+=((ub4)k[6]<<16);
	case 6 : b+=((ub4)k[5]<<8);
	case 5 : b+=k[4];

	case 4 : a+=((ub4)k[3]<<24);
	case 3 : a+=((ub4)k[2]<<16);
	case 2 : a+=((ub4)k[1]<<8);
	case 1 : a+=k[0];
    }
    mix(a,b,c);

    if (vector) {
	vector[0] = a;
	vector[1] = b;
	vector[2] = c;
    }

    return c;
}

#endif


#ifdef HASHFUNC_HSIEH

/*
 * Another hash function by Paul Hsieh, with a focus on speed as well as on
 * good distribution.  This is the code as of 2008-11-06.
 * Source: http://www.azillionmonkeys.com/qed/hash.html
 */

#include <stdint.h>

#undef get16bits
#if (defined(__GNUC__) && defined(__i386__)) || defined(__WATCOMC__) \
  || defined(_MSC_VER) || defined (__BORLANDC__) || defined (__TURBOC__)
#define get16bits(d) (*((const uint16_t *) (d)))
#endif

#if !defined (get16bits)
#define get16bits(d) ((((const uint8_t *)(d))[1] << 8)\
                      +((const uint8_t *)(d))[0])
#endif

static uint32_t hash_hsieh(const unsigned char *data, int len)
{
    uint32_t hash = len, tmp;
    int rem;

    if (len <= 0 || data == NULL)
	return 0;

    rem = len & 3;
    len >>= 2;

    /* Main loop */
    for (;len > 0; len--) {
        hash  += get16bits(data);
        tmp    = (get16bits(data+2) << 11) ^ hash;
        hash   = (hash << 16) ^ tmp;
        data  += 2*sizeof (uint16_t);
        hash  += hash >> 11;
    }

    /* Handle end cases */
    switch (rem) {
        case 3: hash += get16bits (data);
                hash ^= hash << 16;
                hash ^= data[sizeof (uint16_t)] << 18;
                hash += hash >> 11;
                break;
        case 2: hash += get16bits (data);
                hash ^= hash << 11;
                hash += hash >> 17;
                break;
        case 1: hash += *data;
                hash ^= hash << 10;
                hash += hash >> 1;
    }

    /* Force "avalanching" of final 127 bits */
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;

    return hash;
}

#endif


/**
 * Call the correct hash function depending on what was used.
 *
 * @param vector  (optional) A memory area where to store the internal state
 *  of the hash function, i.e. three 32 bit words.  Any one of them can be
 *  used as a hash value, preferably vector[2].
 */
unsigned int compute_hash(const struct hash_state *state,
    const unsigned char *key, int keylen, unsigned int *vector)
{
    int hf = state->hashfunc;

    // methods with (optional) vector output
#ifdef HASHFUNC_JENKINS
    switch (hf) {
	case HASHFUNC_JENKINS:
	    return hash_jenkins(key, keylen, state->seed, vector);
    }
#endif

    if (vector) {
	fprintf(stderr, "compute_hash called for hash method %d, which doesn't "
	    "support vectors.\n", hf);
	return -1;
    }

    // methods without vector support
    switch (hf) {
#ifdef HASHFUNC_DJB2
	case HASHFUNC_DJB2:
	    return hash_djb2(key, keylen);
#endif	
#ifdef HASHFUNC_FNV
	case HASHFUNC_FNV:
	    return hash_fnv(key, keylen);
#endif
#ifdef HASHFUNC_SDBM
	case HASHFUNC_SDBM:
	    return hash_sdbm(key, keylen);
#endif
#ifdef HASHFUNC_HSIEH
	case HASHFUNC_HSIEH:
	    return hash_hsieh(key, keylen);
#endif
    }

    fprintf(stderr, "%s Unsupported hash method %d\n", "LuaGnome:", hf);
    exit(1);
}


