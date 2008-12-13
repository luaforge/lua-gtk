/** vim:sw=4:sts=4
 * Tool to generate a memory efficient hash table for a given input set.
 * (C) by Wolfgang Oertl 2005, 2008
 *
 * Terminology:
 * - hash table: a data set that maps keys to data.
 * - entry: a key/data pair
 * - hash value: a 32 bit integer computed from a hash key.
 * - hash size: the number of buckets.
 * - bucket: consists of zero or more entries.
 * - collision: multiple key/data pairs in one bucket.
 *
 * Limitations:
 * - The max. size of a value is 2^12-1 bytes (4095 bytes)
 * - The combined size of all values is limited to 2^20 bytes (1 MB)
 * - keys cannot contain NUL bytes (this could be fixed easily; data can have
 *   NUL bytes).
 *
 * Version history:
 *  2005-07-18	first version
 *  2005-07-19	better command line parsing, many options, help.
 *  2008-03-03	more comments
 *  2008-08-27	reworked into a Lua library component.  No options, which
 *		were unused anyway, instead use sensible defaults.
 *  2008-09-12	new bucket layout and chaining mechanism.
 *
 *
 * Hash algorithm for inserts:
 *  - compute the hash value from the key
 *  - calculate the bucket number from the hash value
 *  - store the entry into the bucket (linked list)
 *  - when done, use empty buckets as overflows
 *  - output the data in the bucket order
 *  - output the buckets
 *
 * Algorithm for lookup:
 *  - compute the hash value from the key
 *  - calculate the bucket number from the hash value
 *  - get the bucket contents.  If it is an overflow bucket -> not found
 *  - compare the hash value (part).  If equal -> found
 *  - while a "next overflow bucket" is set, go there and repeat at prev step
 *  - no more overflow buckets: not found.
 *
 * Layout of a bucket (64 bits in total):
 *
 *	Bits	    Content
 *	---------------------------------------
 *	1	    set if this is an overflow bucket
 *	15	    high bits of the hash value
 *	16	    next overflow bucket (0=none; 1-based)
 *	12	    data length
 *	20	    data offset
 */

#include "config.h"
#include <lua.h>
#include <lauxlib.h>
#include "lg-hash.h"
#include <ctype.h>	// toupper
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

char *hashfunc_name = "jenkins";
char *ifname = NULL;
FILE *ofile = NULL;

int bucket_count;
struct hash_item **hash_array;
int curr_ofs;
int real = 0;
int dataofs_bits;		    // bits per data offset
int hash_shift;
int hash_bits = 16;		    // initialized to the MINIMUM bits to use
int overflow_bits;		    // bits to address overflow bucket
int bucket_size;		    // bytes per bucket
unsigned int bucket_mask;
struct hash_state state;
const char *prefix;
#define MAX_CHAIN_LENGTH 30
int chain_length[MAX_CHAIN_LENGTH] = { 0 };	    // histogram

/* 1=add keys as comments to output, and show a histogram */
int debug = 0;

/* While reading the input, construct a temporary hash table in memory using
 * this structure. */
struct hash_item {
    struct hash_item *next;	/* overflow */
    unsigned int hash_value;
    unsigned int data_ofs;
    char *key;			/* for comments in the output */
    unsigned char *value;	/* may contain NUL bytes! */
    int value_len;		/* length of the value */
    int overflow_nr;		/* nr of next overflow bucket (1-based) */
    int is_overflow;		/* set if this is an overflow bucket */
};


/**
 * This is a sort of strlen, but detects \ooo escape sequences and counts them
 * as just one byte.
 *
 * @return  Length of the string
 */
static int special_strlen(char *s)
{
    size_t len = 0, i;

    for (; *s; len++, s++) {

	if (*s != '\\')
	    continue;

	s ++;
	if (*s == '\\')
	    continue;

	// skip up to three octal digits after the backslash.
	for (i=0; i<3; i++, s++)
	    if (*s < '0' || *s > '7')
		break;
	s --;
    }

    return len;
}


/**
 * Each line consists of a key and a data string, which are comma separated.
 * Both key and data could contain non-printable characters encoded as \nnn;
 * they are written as-is in the output, but for offset calculation the byte
 * count required for it will be needed.
 *
 * @param s  Input line (starting with the key)
 * @param key_len  (output) Byte count of the key
 * @param data_ptr  (output) Start of data part of the line
 * @param data_len  (output) Byte count of the data
 * @return  0 on success, -1 otherwise
 */
static int _preprocess_line(char *s, int *key_len, char **data_ptr,
    int *data_len, int line)
{
    char *pos;
    size_t len;

    // chop off trailing newline and spaces
    len = strlen(s);
    while (len > 0 && s[len-1] <= ' ')
	len--;
    s[len] = 0;

    // split into key and data parts
    pos = strchr(s, ',');
    if (!pos) {
	fprintf(stderr, "%d: line without comma, ignoring\n",
	    line);
	return -1;
    }

    *pos++ = 0;
    *data_ptr = pos;

    // determine byte requirement of both key and data
    *key_len = special_strlen(s);
    *data_len = special_strlen(pos);

    return 0;
}


/**
 * Compute how many bits are required to store the given value.
 */
static int _bits_required(size_t value)
{
    int n = 0;

    while (value) {
	n ++;
	value >>= 1;
    }

    return n;
}


/**
 * Build the hash table with the data from the input file.
 */
static void _build_hash_table(lua_State *L, FILE *ifile)
{
    struct hash_item *hash_item;
    unsigned int hash, index;
    int line, collisions=0, data_len, key_len;
    char *s, *data_ptr, buffer[BUFSIZ];

    hash_array = (struct hash_item**) calloc(bucket_count, sizeof(*hash_array));

    // determine the offset mask
    bucket_mask = (1 << _bits_required(bucket_count-1)) - 1;

    for (line=0; ; line++) {
	s = fgets(buffer, sizeof(buffer), ifile);
	if (!s)
	    break;
	if (*s == '\n')
	    continue;
	
	if (_preprocess_line(s, &key_len, &data_ptr, &data_len, line))
	    continue;

	hash = compute_hash(&state, (unsigned char*) s, key_len, NULL);

	index = hash & bucket_mask;
	if (index >= bucket_count)
	    index -= bucket_count;

	/* make item */
	hash_item = (struct hash_item*) malloc(sizeof *hash_item);
	hash_item->hash_value = hash;
	hash_item->data_ofs = 0;
	hash_item->key = strdup(s);
	hash_item->value = (unsigned char*) strdup(data_ptr);
	hash_item->value_len = data_len;
	hash_item->overflow_nr = 0;
	hash_item->is_overflow = 0;

	if ((hash_item->next = hash_array[index]))
	    collisions++;
	hash_array[index] = hash_item;
    }

}


/**
 * A hash table has been created.  There are now empty buckets as well as
 * overfilled buckets (i.e. more than one entry).  Distribute entries into
 * the empty buckets.
 */
static void _distribute(lua_State *L)
{
    struct hash_item *hi, *hi2;
    unsigned int nr, free_nr = 0;	    // where to look for free buckets
    int item_count = 0, cnt;

    for (nr=0; nr<bucket_count; nr++) {
	hi = hash_array[nr];

	// empty, or an empty bucket filled with an overflow - skip
	if (!hi || hi->is_overflow) {
	    chain_length[0] ++;
	    continue;
	}
	
	item_count ++;

	// distribute overflows
	cnt = 1;
	while (hi->next) {
	    while (hash_array[free_nr])
		free_nr ++;

	    hash_array[free_nr] = hi->next;
	    free_nr ++;
	    hi->overflow_nr = free_nr;	// store nr+1 so that 0=no overflow
	    hi2 = hi;
	    hi = hi->next;
	    hi->is_overflow = 1;	// mark this entry as relocated
	    hi2->next = NULL;
	    item_count ++;
	    cnt ++;
	}
	if (cnt >= MAX_CHAIN_LENGTH)
	    cnt = MAX_CHAIN_LENGTH - 1;
	chain_length[cnt] ++;
    }

    if (item_count != bucket_count)
	luaL_error(L, "internal error: inconsistency in item_count: %d vs. %s",
	    item_count, bucket_count);
}

struct value_t {
    unsigned char *value;	    /* the value as zero-terminated string */
    int data_ofs;
};

static int value_cmp(const void *a, const void *b)
{
    return strcmp(*(const char**)a, *(const char**)b);
}


/**
 * For each bucket, output the value, and store the offsets into the buckets.
 *
 * Duplicates of values can appear.  Store just one copy and use the same
 * value in multiple buckets.  Keep a sorted list of already seen values; do
 * a binary search for each new value.  New values are appended and qsort
 * is called.
 */
static void _output_values(lua_State *L, FILE *ofile)
{
    unsigned int curr_ofs, bucket_nr, value_count=0;
    struct hash_item *hi;
    struct value_t *values, *p;

    // make a sorted array of values.
    values = (struct value_t*) calloc(bucket_count, sizeof(*values));

    fprintf(ofile, "#include \"lg-hash.h\"\n\n");
    fprintf(ofile, "static const unsigned char _%s_data[] =\n", prefix);

    curr_ofs = 1;
    for (bucket_nr=0; bucket_nr<bucket_count; bucket_nr++) {
	hi = hash_array[bucket_nr];

	// sanity check.
	if (!hi)
	    luaL_error(L, "empty bucket nr %d", bucket_nr);
	if (hi->next)
	    luaL_error(L, "_output_values: more than one item in bucket %d",
		bucket_nr);

	// is this value already there?
	p = bsearch(&hi->value, values, value_count, sizeof(*values), value_cmp);

	if (p) {
	    hi->data_ofs = p->data_ofs;
	} else {
	    hi->data_ofs = curr_ofs;
	    values[value_count].value = hi->value;
	    values[value_count].data_ofs = curr_ofs;
	    value_count ++;
	    qsort(values, value_count, sizeof(*values), value_cmp);
	    curr_ofs += hi->value_len;
	    if (debug)
		fprintf(ofile, "  \"%s\"\t// ofs=%d\n", hi->value, hi->data_ofs);
	    else
		fprintf(ofile, "  \"%s\"\n", hi->value);
	}

    }

    free(values);
    if (debug)
    	printf("Duplicate values: %d\n", bucket_count - value_count);
    fprintf(ofile, ";\n\n");
    dataofs_bits = _bits_required(curr_ofs - hi->value_len);
}


/**
 * Output the array of hash buckets, each one with a hash value, data
 * offset, and an overflow bucket number.
 */
static void _output_buckets(lua_State *L, FILE *ofile)
{
    struct hash_item *hi;
    int bucket_nr;
    unsigned int v1, v2;

    fprintf(ofile, "static const unsigned int _%s_buckets[] = {\n", prefix);

    for (bucket_nr=0; bucket_nr<bucket_count; bucket_nr++) {
	hi = hash_array[bucket_nr];

	// first 32 bits: o=is_overflow, h=hashvalue, n=next overflow
	// ohhh hhhh hhhh hhhh nnnn nnnn nnnn nnnn
	v1 = ((hi->is_overflow & 1) << 31)
	    | (hi->hash_value & 0x7fff0000)
	    | (hi->overflow_nr & 0x0000ffff);

	// second 32 bits: l=data length, o=data offset
	// llll llll llll oooo oooo oooo oooo oooo
	v2 = ((hi->value_len & ((1<<12)-1)) << 20)
	    | (hi->data_ofs & ((1<<20)-1));
	
	if (debug)
	    fprintf(ofile, "  0x%08x, 0x%08x,  // hash %08x, key %s, ofs %d, "
		"next %d\n",
		v1, v2, hi->hash_value, hi->key, hi->data_ofs, hi->overflow_nr);
	else
	    fprintf(ofile, "  0x%08x, 0x%08x,\n", v1, v2);

    }

    fputs("};\n\n", ofile);
}

/**
 * Show some statistics
 */
static void _show_statistics()
{
    int cnt, i;

    if (!debug)
	return;

    printf("Simple hash table %s: buckets=%d, chains:", prefix, bucket_count);

    /* find highest count */
    for (cnt=MAX_CHAIN_LENGTH-1; cnt>=0; cnt--)
	if (chain_length[cnt])
	    break;

    for (i=0; i<=cnt; i++)
	printf(" %d=%d", i, chain_length[i]);
    printf("\n");
}



/* generate the meta structure of this hash */
static void _output_meta()
{
    char *name = strdup(hashfunc_name), *s;

    for (s=name; *s; s++)
	*s = toupper(*s);

    fprintf(ofile, "const struct hash_info_simple hash_info_%s = {\n"
	"\tmethod: HASH_SIMPLE,\n"
	"\thf: { HASHFUNC_%s, %d },\n"
	"\tbucket_count: %d,\n"
	"\tbucket_mask: 0x%x,\n"
	"\tbuckets: _%s_buckets,\n"
	"\tdata: _%s_data,\n"
	"};\n\n",
	prefix,
	name, state.seed,
	bucket_count, bucket_mask,
	prefix, prefix);
	

    free(name);
}

/* free all structures -- important for multiple runs. */
static void _cleanup()
{
    int bucket_nr;
    struct hash_item *hi, *hi2;

    for (bucket_nr=0; bucket_nr<bucket_count; bucket_nr++) {
	hi = hash_array[bucket_nr];
	while (hi) {
	    hi2 = hi->next;
	    free(hi->key);
	    free(hi->value);
	    free(hi);
	    hi = hi2;
	}
    }

    free(hash_array);
    hash_array = NULL;
}


/**
 * Determine the number of lines in the file.
 */
static int _count_lines(FILE *f)
{
    int count = 0, len;
    char buf[BUFSIZ];

    for (;;) {
	if (!fgets(buf, BUFSIZ, f))
	    break;
	len = strlen(buf);
	if (len > 0 && buf[len-1] == '\n')
	    count ++;
    }

    rewind(f);
    return count;
}


static int _find_hashfunc(const char *name)
{
    const char *s;
    int nr = 0;

    for (s=hash_function_names; *s; s += strlen(s) + 1) {
	if (!strcmp(s, name))
	    return nr;
	nr ++;
    }

    return -1;
}

/**
 * Generate a hash table to map the key,value pairs found in the
 * specified datafile, and write a compileable C file to the output
 * file.
 */
int generate_hash_simple(lua_State *L, const char *datafile_name,
    const char *prefix1, const char *ofname)
{
    FILE *ifile;

    state.hashfunc = _find_hashfunc(hashfunc_name);
    state.seed = 0;
    prefix = prefix1;

    ifile = fopen(datafile_name, "r");
    if (!ifile)
	return luaL_error(L, "Can't open %s for reading: %s", datafile_name,
	    strerror(errno));

    // Count the number of entries in the hash table; that's the desired
    // size of the hash table.  Each bucket should contain, on average,
    // one entry.
    bucket_count = _count_lines(ifile);
    _build_hash_table(L, ifile);
    fclose(ifile);

    _distribute(L);

    ofile = fopen(ofname, "w");
    if (!ofile)
	return luaL_error(L, "Can't open %s for writing: %s", ofname,
	    strerror(errno));
    _output_values(L, ofile);
    _output_buckets(L, ofile);
    _output_meta();
    _show_statistics();
    _cleanup();

    fclose(ofile);
    return 0;
}


