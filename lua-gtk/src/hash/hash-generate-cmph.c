/** vim:sw=4:sts=4
 *
 * Convert a text file with (key,value) pairs into a compileable C file.  When
 * compiled, it exports one symbol, which is hash_info_{prefix}.
 *
 * It uses the CMPH library available at http://cmph.sourceforge.net/ by
 * Davi de Castro Reis and Fabiano Cupertino Botelho.  Currently the following
 * algorithms are supported: FCH, BDZ.
 *
 * Read the generated hash data, read the list of keys the associated value,
 * and write the hash table.  Each bucket is 32 bit long and contains:
 *
 *	bits		    contents
 *	hash_bits	    upper bits of the hash value
 *	offset_bits	    offset of the data in the data string
 *	length_bits	    length of the data
 *
 * When "combine" is activated, then the offsets can be in arbitrary order,
 * and the length has to be specified.  When it is off, the data offsets are
 * in ascending order, and no length is needed; the end of the data is equal
 * to the start of the next bucket's data.
 *
 * Note that both BDZ and FCH hash algorithms are not order preserving; this
 * means that each key maps to a distinct bucket number, but in an undefined
 * order.
 *
 * Following steps are required:
 *  - read all key/data pairs
 *  - calculate the bucket number for each key to determine the order
 *  - write the data in this order sequentially into a string (no
 *    combining), or check for duplicates, write data in any order.
 *  - write an index table with part of the hash value, one offset per bucket
 *    and optionally a length.
 *
 * Copyright (C) 2007, 2008 Wolfgang Oertl
 * This program is free software and can be used under the terms of the
 * GNU Lesser General Public License version 2.1.  You can find the
 * full text of this license here:
 *
 * http://opensource.org/licenses/lgpl-license.php.
 */

#include "config.h"
#include <cmph.h>
#include <cmph_types.h>
#include <cmph_structs.h>   // cmph_t definition
#ifdef CMPH_USE_fch
 #include <fch_structs.h>    // jenkins_state_t, __fch_data_t
 #define LG_CMPH_ALGO CMPH_FCH
#endif
#ifdef CMPH_USE_bdz
 #include <bdz_structs.h>
 #define LG_CMPH_ALGO CMPH_BDZ
#endif
#include <string.h>	    // strlen, strchr, strdup, memset
#include <errno.h>	    // errno
#include <lauxlib.h>	    // luaL_error
#include <ctype.h>	    // toupper
#include "lg-hash.h"

// line buffer length.
static int buf_len = 200;

// output additional comments
static int debug = 0;

// try to combine values?
static int combine = 1;

// how many bits to use for what in the buckets
static int
    hash_bits = 0,
    offset_bits = 0,
    length_bits = 0;

// Globals.  This is not a multithreaded application, so it doesn't matter.
struct bucket_t *buckets = NULL;
struct value_t *values = NULL;
int value_count = 0;
cmph_t *mphf = NULL;
const char *prefix = NULL;
int offset_size = 0;
int total_data_size = 0;
int max_data_length = 0;



/**
 * Given a CMPH hash function number, convert that to the numbers used within
 * LuaGnome.
 */
static int convert_funcnr(int nr)
{
// #ifdef CMPH_HASH_JENKINS
    if (nr == CMPH_HASH_JENKINS)
	return HASHFUNC_JENKINS;
// #endif
    fprintf(stderr, "Unsupported hash function %s (%d)\n",
	cmph_hash_names[nr], nr);
    exit(1);
}


#ifdef CMPH_USE_fch
/**
 * Output the data structure for fch.
 * Required fields:
 *  h1, h2, m, b, p1, p2, g
 */
static int dump_fch(FILE *ofile)
{
    struct __fch_data_t *f = (struct __fch_data_t*) mphf->data;
    jenkins_state_t *js1, *js2;
    int i, g_size, cnt=0;
    unsigned int maxval = 0;

    /* analyze the "g" table to find the maximum value. */
    for (i=0; i<f->b; i++)
	if (maxval < f->g[i])
	    maxval = f->g[i];
    g_size = maxval < 65536 ? 16 : 32;
    js1 = (jenkins_state_t*) f->h1;
    js2 = (jenkins_state_t*) f->h2;

    fprintf(ofile, "/* max. value in g is %d */\n"
	"  m: %d,\n"
	"  b: %d,\n"
	"  g_size: %d,\n"
	"  p1: %u,\n"
	"  p2: %u,\n"
	"  h1: { %d, %d },\n"
	"  h2: { %d, %d },\n"
	"  g: { ",
	maxval, f->m, f->b, g_size, (unsigned int) f->p1,
	(unsigned int) f->p2,
	convert_funcnr(js1->hashfunc), js1->seed,
	convert_funcnr(js2->hashfunc), js2->seed);

    for (i=0; i<f->b; i++) {
	fprintf(ofile, "%d,", f->g[i] & 0xffff);
	cnt ++;

	/* optionally 16 more bits */
	if (g_size == 32)
	    fprintf(ofile, "%d,", f->g[i] >> 16);
	cnt ++;

	/* add linebreaks */
	if (cnt > 20) {
	    fprintf(ofile, "\n  ");
	    cnt = 0;
	}
    }

    fprintf(ofile, " },\n");
    fprintf(ofile, "};\n\n");

    return 0;
}
#endif

#ifdef CMPH_USE_bdz

/**
 * Output the additional data fields specific for the BDZ algorithm.
 */
static int dump_bdz(FILE *f)
{
    struct __bdz_data_t *b = (struct __bdz_data_t*) mphf->data;
    jenkins_state_t *js;
    int i, g_size, g_count, cnt=0;
    unsigned int maxval = 0;

    /* analyze the "g" table to find the maximum value. */
    g_count = (b->n >> 2) + 1;
    for (i=0; i<g_count; i++)
	if (maxval < b->g[i])
	    maxval = b->g[i];
    g_size = maxval < 65536 ? 16 : 32;

    fprintf(f, "/* max. value in g is %d */\n"
	"  m: %d,\n"
	"  n: %d,\n"
	"  r: %d,\n"
	"  k: %d,\n"
	"  b: %d,\n",
	maxval, b->m, b->n, b->r, b->k, b->b);

    /* dump the rank table - as a string to avoid a separate array */
    int rt_bytes = 2, v, j;
    fprintf(f, "  ranktablesize: %d,\n"
	"  rt_item_size: %d,\n"
	"  ranktable: (unsigned char*) \"",
	b->ranktablesize, rt_bytes);

    for (i=0; i<b->ranktablesize; i++) {
	v = b->ranktable[i];
	for (j=rt_bytes-1; j >= 0; j--)
	    fprintf(f, "\\%03o", (v >> (j<<3)) & 0xff);
    }
    fprintf(f, "\",\n");
    js = (jenkins_state_t*) b->hl;
    fprintf(f, "  hl: { %d, %d },\n", convert_funcnr(js->hashfunc), js->seed);

    /* dump the "g" table, which is the bulk of the data */
    fprintf(f, "  g: { ");

    for (i=0; i<g_count; i++) {
	fprintf(f, "%d,", b->g[i]);
	cnt ++;
	if (cnt > 16) {
	    fprintf(f, "\n   ");
	    cnt = 0;
	}
    }
    fprintf(f, " },\n"
	"};\n\n");

    return 0;
}

#endif

/**
 * Calculate the first hash value - again, it already happened in cmph_search,
 * but it doesn't return it anywhere.  This is an unfortunate intrusion into
 * cmph internals!
 */
static unsigned int get_hash_value(const unsigned char *key, int keylen)
{
#ifdef CMPH_USE_fch
    if (mphf->algo == CMPH_FCH) {
	struct __fch_data_t *fch = (struct __fch_data_t*) mphf->data;
	return hash(fch->h1, (char*) key, keylen);
    }
#endif

#ifdef CMPH_USE_bdz
    if (mphf->algo == CMPH_BDZ) {
	struct __bdz_data_t *bdz = (struct __bdz_data_t*) mphf->data;
	return hash(bdz->hl, (char*) key, keylen);
    }
#endif
	    
    fprintf(stderr, "internal error #1 - unsupported hash algorithm %d\n",
	mphf->algo);
    exit(1);
}


/**
 * Calculate the string length, but \[0-7]{1,3} is considered as just one
 * character; this is how the C compiler sees it later.
 *
 * Note: \n, \t etc. is also detected, although no check for invalid escape
 * sequences is done.
 */
int special_strlen(const char *s)
{
    int len = 0, i;

    while (*s) {
	if (*s++ == '\\') {
	    if (*s >= 'a' && *s <= 'z')
		s ++;
	    else {
		// a \000 octal sequence is max. 3 digits.
		for (i=3; i && *s >= '0' && *s <= '7'; i--)
		    s ++;
	    }
	}
	len ++;
    }

    return len;
}

struct bucket_t {
    unsigned int hash_value;
    const char *value;	    // don't free this
    char *key;		    // for debugging purposes
};

struct value_t {
    char *value;	    // must be first element of this structure!
    int data_ofs;
    int data_length;	    // special_strlen(value)
};


/**
 * Call the appropriate dump function to create C code containing the data
 * of the cmph hash function.  It is written on stdout.
 *
 * @return 0 on success, 1 on error.
 */
static int dump_mphf(lua_State *L, FILE *f)
{
#ifdef CMPH_USE_fch
    if (mphf->algo == CMPH_FCH)
	return dump_fch(f);
#endif

#ifdef CMPH_USE_bdz
    if (mphf->algo == CMPH_BDZ)
	return dump_bdz(f);
#endif
    
    return luaL_error(L, "Unsupported algorithm %s used.",
	cmph_names[mphf->algo]);
}

static int value_cmp(const void *a, const void *b)
{
    return strcmp(*(const char**)a, *(const char**)b);
}


static void _read_keys_and_values(lua_State *L, FILE *ifile)
{
    char *buf = (char*) malloc(buf_len), *key, *data, *data2;
    int keys = cmph_size(mphf), line=0, len, keylen, bucket_nr;
    struct bucket_t *bucket;
    struct value_t *value;
    unsigned int hash_value;

    rewind(ifile);

    // read the key/value pairs, and store the values (eliminating duplicates)

    for(;;) {
	key = fgets(buf, buf_len, ifile);
	if (!key)
	    break;
	line ++;

	// line should contain at least a newline!
	len = strlen(key);
	if (len == 0) {
	    fprintf(stderr, "Nothing read on line %d\n", line);
	    break;
	}

	// should end with "\n", else line was truncated.
	if (key[len-1] != '\n') {
	    luaL_error(L, "Line truncated at line %d.  Please increase "
		"the buffer size (currently %d)\n", line, buf_len);
	}

	// chop off the newline
	len --;
	key[len] = 0;

	// split into key and data part
	data = strchr(key, ',');
	if (!data) {
	    fprintf(stderr, "No data part on line %d\n", line);
	    continue;
	}
	*data = 0;
	data ++;
	keylen = data - key - 1;
	len -= keylen + 1;

	// calculate the bucket number
	bucket_nr = cmph_search(mphf, key, keylen);
	if (bucket_nr < 0 || bucket_nr >= keys)
	    luaL_error(L, "Error: %d buckets, key %.*s maps to "
		"bucket #%d\n", keys, keylen, key, bucket_nr);

	// The bucket must be empty - that's the point about the perfect hash
	// function.
	bucket = buckets + bucket_nr;
	if (bucket->value)
	    luaL_error(L, "Collision at %d\n", bucket_nr);

	// store the hash value.
	hash_value = get_hash_value((unsigned char*) key, keylen);
	bucket->hash_value = hash_value;

	// re-use existing values
	value = combine ? bsearch(&data, values, value_count, sizeof(*values),
		value_cmp) : NULL;

	if (!value) {
	    value = values + value_count;
	    data2 = value->value = strdup(data);
	    value->data_length = special_strlen(data);
	    if (value->data_length == 0)
		luaL_error(L, "Data length zero is not allowed");
	    if (max_data_length < value->data_length)
		max_data_length = value->data_length;
	    value_count ++;
	    if (combine)
		qsort(values, value_count, sizeof(*values), value_cmp);
	} else {
	    data2 = value->value;
	}

	bucket->value = data2;
	bucket->key = strdup(key);
    }

    /*
    if (combine)
	printf("Duplicates: %d\n", keys - value_count);
    */

    free(buf);
}

static int _bits_needed(unsigned int v)
{
    int bits = 0;

    while (v) {
	bits ++;
	v >>= 1;
    }

    return bits;
}


/**
 * Determine how to allocate the bits of the 32 bits in the buckets.
 * Lowest is the length of the data; this is zero when combining is off.
 * Next is the offset, and lastly in the high bits the high part of the
 * hash value.
 */
static void _compute_sizes()
{
    offset_bits = _bits_needed(total_data_size);
    length_bits = combine ? _bits_needed(max_data_length-1) : 0;
    hash_bits = 32 - offset_bits - length_bits;
}


static void _output_values(lua_State *L, FILE *ofile)
{
    unsigned int data_offset = 0;
    int i;

    // output the data table, thereby assign the offsets and compute the total
    // length of the data.
    fprintf(ofile, "static const unsigned char _%s_data[] =\n", prefix);
    for (i=0; i<value_count; i++) {
	if (debug)
	    fprintf(ofile, "  \"%s\"\t// ofs=%d\n", values[i].value,
		data_offset);
	else
	    fprintf(ofile, "  \"%s\"\n", values[i].value);
	values[i].data_ofs = data_offset;
	data_offset += values[i].data_length;
    }

    total_data_size = data_offset;
    fprintf(ofile, ";\n/* Data size is %d bytes */\n", total_data_size);
    if (combine)
	fprintf(ofile, "/* %d duplicates removed */\n",
	    cmph_size(mphf) - value_count);

    fprintf(ofile, "\n");
}


/**
 * Output the buckets table.  Each bucket is 32 bits long and contains part
 * of the hash value, the offset of the associated data and the data length.
 */
static void _output_buckets(lua_State *L, FILE *ofile)
{
    int i, cnt=0;
    int keys = cmph_size(mphf);
    struct bucket_t *bucket;
    struct value_t *value;
    unsigned int v, hash_mask, length_mask;

    fprintf(ofile, "static const unsigned int _%s_index[] = { \n", prefix);
    hash_mask = 0xffffffff << (32 - hash_bits);
    length_mask = (1 << length_bits) - 1;
	
    for (i=0; i<keys; i++) {
	bucket = buckets + i;
	if (combine) {
	    value = bsearch(&bucket->value, values, value_count,
		sizeof(*values), value_cmp);
	} else {
	    value = values + i;
	}

	// store length-1, as length 0 is not allowed; this can save
	// a bit when max_data_length is a power of two.
	v = (bucket->hash_value & hash_mask)
	    | (value->data_ofs << length_bits)
	    | ((value->data_length - 1) & length_mask);

	if (debug) {
	    fprintf(ofile, " 0x%08x,   // hash %08x, key=%s, ofs=%d, len=%d\n",
		v, bucket->hash_value, bucket->key, value->data_ofs,
		value->data_length);
	} else {
	    fprintf(ofile, " 0x%08x,", v);
	    if (++cnt >= 6) {
		fprintf(ofile, "\n");
		cnt = 0;
	    }
	}
    }

    // Sentry so that the data size calculation will work for the last bucket.
    // Because the offset is always read as integer (4 bytes) from memory,
    // make sure the last entry has a 4 byte offset.
    if (!combine) {
	v = total_data_size << length_bits;
	fprintf(ofile, "0x%08x,", v);
    }
    if (cnt)
	fprintf(ofile, "\n");
	
    fprintf(ofile, "};\n\n");
}


static void _output_meta(lua_State *L, FILE *ofile)
{
    char *upper_algo_name = strdup(cmph_names[mphf->algo]), *s;
    unsigned int hash_mask;

    for (s=upper_algo_name; *s; s++)
	*s = toupper(*s);

    // set the upper "hash_bits" in hash_mask.
    hash_mask = 0xffffffff << (32 - hash_bits);

    // Output the master structure.
    fprintf(ofile,
	"#include \"lg-hash.h\"\n\n"
	"const struct hash_info_%s hash_info_%s = {\n"
	"  cmph: {\n"
	"    method: HASH_CMPH_%s,\n"
	"    hash_mask: 0x%08x,\n"
	"    offset_bits: %d,\n"
	"    length_bits: %d, /* max. length is %d */\n"
	"    index: _%s_index,\n"
	"    data: _%s_data,\n"
	"  },\n",
	cmph_names[mphf->algo],
	prefix,
	upper_algo_name,
	hash_mask,
	offset_bits, length_bits, max_data_length, prefix, prefix);

    free(upper_algo_name);

    dump_mphf(L, ofile);

#ifdef SHOW_DATA_HISTO
    // dump histogram to stderr
    for (i=0; i<HISTO_MAX; i++)
	fprintf(stderr, "Data size %3d: %d\n", i, data_histogram[i]);
#endif
}


/**
 * Given the already generated hash function, read the list of keys and
 * the associated value, and write the hash table.  Each bucket contains
 * exactly one entry:
 *
 *	bytes	    contents
 *	4	    hash value of the name
 *	2	    offset of the data in the data string
 *
 * The data string contains the actual data.
 */
int build_hash_table(lua_State *L, FILE *ifile, FILE *ofile)
{
    int keys = cmph_size(mphf);
    buckets = (struct bucket_t*) calloc(keys, sizeof(*buckets));
    values = (struct value_t*) calloc(keys, sizeof(*values));

    _read_keys_and_values(L, ifile);
    _output_values(L, ofile);
    _compute_sizes();
    _output_buckets(L, ofile);
    _output_meta(L, ofile);

    free(values);
    free(buckets);
    return 0;
}





/* IO Adapter that reads from a datafile that has "key,value" lines.  Return
 * only the key part to the caller, i.e. up to the first ",".
 */

typedef struct {
    lua_State *L;
    FILE *file;
    int line;
    const char *fname;
} *datafile_t;

static cmph_uint32 _datafile_count_keys(FILE *f)
{
    cmph_uint32 count = 0;
    size_t len;
    char buf[BUFSIZ];

    rewind(f);
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

static int _datafile_read(void *data, char **key, cmph_uint32 *keylen)
{
    datafile_t df = (datafile_t) data;
    char buf[BUFSIZ], *s, *p;

    s = fgets(buf, BUFSIZ, df->file);
    if (!s || feof(df->file))
	return -1;
    df->line ++;

    p = strchr(buf, ',');
    if (!p)
	luaL_error(df->L, "%s(%d): no ',' in line: %s", df->fname, df->line,
	    buf);
    *p = 0;
    *key = strdup(buf);
    *keylen = p - buf;
    return *keylen;
}

// rewind the input file
static void _datafile_rewind(void *data)
{
    datafile_t df = (datafile_t) data;
    rewind(df->file);
}

// free a key as allocated by _datafile_read
static void _datafile_dispose(void *data, char *key, cmph_uint32 keylen)
{
    free(key);
}

static cmph_io_adapter_t *io_datafile_adapter(lua_State *L,
    const char *fname, FILE *file)
{
    cmph_io_adapter_t *ad = (cmph_io_adapter_t*) malloc(sizeof(*ad));
    datafile_t df = (datafile_t) malloc(sizeof(*df));
    df->L = L;
    df->file = file;
    df->line = 0;
    df->fname = fname;

    ad->data = (void*) df;
    ad->nkeys = _datafile_count_keys(file);
    ad->read = _datafile_read;
    ad->dispose = _datafile_dispose;
    ad->rewind = _datafile_rewind;
    return ad;
}


/**
 * This function is called from gnomedev.c for the generate_hash call.
 */
int generate_hash_cmph(lua_State *L, const char *datafile_name,
    const char *_prefix, const char *ofname)
{
    FILE *datafile, *ofile;
    cmph_io_adapter_t *source;
    cmph_config_t *config;

    // generate
    datafile = fopen(datafile_name, "r");
    source = io_datafile_adapter(L, datafile_name, datafile);
    config = cmph_config_new(source);
    cmph_config_set_algo(config, LG_CMPH_ALGO);
    cmph_config_set_b(config, 128);		// the default value for -b
    // cmph_config_set_graphsize(config, c);	// for FCH
    mphf = cmph_new(config);
    cmph_config_destroy(config);
    free(source->data);
    free(source);

    if (!mphf)
	return luaL_error(L, "Unable to compute the minimal perfect hash "
	    "function for %s.", datafile_name);

    ofile = fopen(ofname, "w");
    if (!ofile)
	return luaL_error(L, "Unable to open %s for writing: %s",
	    ofname, strerror(errno));

    prefix = _prefix;
    build_hash_table(L, datafile, ofile);
    fclose(ofile);

    return 0;
}


