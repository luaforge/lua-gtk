/** vim:sw=4:sts=4
 *
 * Convert a text file with (key,value) pairs and the corresponding CMPH file
 * into a compileable C file.  When compiled, it exports one symbol,
 * which is hash_info_{prefix}.
 *
 * It uses the CMPH library available at http://cmph.sourceforge.net/ by
 * Davi de Castro Reis and Fabiano Cupertino Botelho.  Only the FCH
 * algorithm is supported.
 *
 * Given the generated (and compiled) FCH function, read the list of keys
 * the associated value, and write the hash table.  Each bucket contains
 * exactly one entry:
 *
 *	bytes	    contents
 *	4	    hash value of the name
 *	2	    offset of the data in the data string
 *
 * The data string contains the actual data.  Note that the FCH hash is not
 * order preserving; this means that each key maps to a distinct bucket number,
 * but in an undefined order.
 *
 * Following steps are required:
 *  - read all key/data pairs
 *  - calculate the bucket number for each key to determine the order
 *  - write the buckets (data) in this order sequentially into a string
 *  - write an index table with one offset per bucket
 *
 * Copyright (C) 2007 Wolfgang Oertl
 * This program is free software and can be used under the terms of the
 * GNU Lesser General Public License version 2.1.  You can find the
 * full text of this license here:
 *
 * http://opensource.org/licenses/lgpl-license.php.
 */

#include "cmph_structs.h"   // cmph_t definition
#include "fch_structs.h"    // jenkins_state_t, __fch_data_t
#include <string.h>	    // strlen, strchr, strdup, memset
#include <errno.h>	    // errno


// line buffer length.
static int buf_len = 200;

/**
 * Output the data structure.
 * Required fields:
 *  h1, h2, m, b, p1, p2, g
 */
static void fch_dump(cmph_t *mphf, const char *prefix)
{
    struct __fch_data_t *f = (struct __fch_data_t*) mphf->data;
    jenkins_state_t *js;
    int i, g_size, cnt=0;
    unsigned int maxval = 0;


    if (mphf->algo != CMPH_FCH) {
	fprintf(stderr, "Error: only the FCH algorithm is supported.\n");
	return;
    }

    /* analyze the "g" table to find the maximum value. */
    for (i=0; i<f->b; i++)
	if (maxval < f->g[i])
	    maxval = f->g[i];
    g_size = maxval < 65536 ? 16 : 32;

    printf("/* max. value in g is %d */\n", maxval);

    printf("#include \"hash-fch.h\"\n\n");
    printf("static const struct my_fch _%s_fch = {\n", prefix);
    printf("  m: %d,\n", f->m);
    printf("  b: %d,\n", f->b);
    printf("  g_size: %d,\n", g_size);
    printf("  p1: %u,\n", (unsigned int) f->p1);
    printf("  p2: %u,\n", (unsigned int) f->p2);
    js = (jenkins_state_t*) f->h1;
    printf("  h1: { %d, %d },\n", js->hashfunc, js->seed);
    js = (jenkins_state_t*) f->h2;
    printf("  h2: { %d, %d },\n", js->hashfunc, js->seed);
    printf("  g: { ");

    for (i=0; i<f->b; i++) {
	printf("%d,", f->g[i] & 0xffff);
	cnt ++;

	/* optionally 16 more bits */
	if (g_size == 32)
	    printf("%d,", f->g[i] >> 16);
	cnt ++;

	/* add linebreaks */
	if (cnt > 20) {
	    printf("\n  ");
	    cnt = 0;
	}
    }

    printf(" },\n");
    printf("};\n");
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


/**
 * Output one hash entry.  This consists of the hash value followed by a two
 * or four bytes offset to the data.  The information is printed as individual
 * octal bytes.
 */
void print_hash_entry(unsigned int hash_value, unsigned int data_offset,
    int offset_size)
{
    int j;
    static int cnt = 0;

    cnt += 4;
    for (j=4; j; j--) {
	printf("\\%o", hash_value & 0xff);
	hash_value >>= 8;
    }

    cnt += offset_size;
    for (j=offset_size; j; j--) {
	printf("\\%o", data_offset & 0xff);
	data_offset >>= 8;
    }

    // add line breaks to make it prettier
    if (cnt > 16) {
	printf("\"\n \"");
	cnt = 0;
    }
}

/**
 * Given the already generated FCH hash function, read the list of keys and
 * the associated value, and write the hash table.  Each bucket contains
 * exactly one entry:
 *
 *	bytes	    contents
 *	4	    hash value of the name
 *	2	    offset of the data in the data string
 *
 * The data string contains the actual data.
 */
int build_hash_table(cmph_t *mphf, const char *fname, const char *prefix)
{
    int bucket_nr, len, keylen, line=0, i;
    FILE *f;
    char *buf, *key, *data, **data_table;
    unsigned int data_offset=0, offset_size, hash_value;
    unsigned int *hash_table, *entry;

    f = fopen(fname, "r");
    if (!f) {
	fprintf(stderr, "Can't open %s: %s\n", fname, strerror(errno));
	return 2;
    }

    buf = (char*) malloc(buf_len);

    int keys = cmph_size(mphf);

    // for each bucket, the hash value.
    hash_table = (unsigned int*) malloc(keys * sizeof(*hash_table));
    memset(hash_table, 0, keys * sizeof(*hash_table));

    // for each bucket, the data
    data_table = (char**) malloc(keys * sizeof(*data_table));
    memset(data_table, 0, keys * sizeof(*data_table));

    for(;;) {
	key = fgets(buf, buf_len, f);
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
	    fprintf(stderr, "Line truncated at line %d.  Please increase "
		"the buffer size (currently %d)\n", line, buf_len);
	    return 1;
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
	if (bucket_nr < 0 || bucket_nr >= keys) {
	    fprintf(stderr, "Error: %d buckets, key %.*s maps to bucket #%d\n",
		keys, keylen, key, bucket_nr);
	    return 1;
	}

	// The bucket must be empty - that's the point about the perfect hash
	// function.
	entry = hash_table + bucket_nr;
	if (*entry) {
	    fprintf(stderr, "Collision at %d\n", bucket_nr);
	    break;
	}

	// Calculate the first hash value - again, it already happened in
	// cmph_search, but it doesn't return it anywhere.  This is an
	// unfortunate intrusion into cmph internals!
	struct __fch_data_t *fch = (struct __fch_data_t*) mphf->data;
	hash_value = hash(fch->h1, key, keylen);
	
	// store hash value and the data.
	*entry = hash_value;
	data_table[bucket_nr] = strdup(data);
    }

    free(buf);

    // output the data table, thereby compute the total length of the data.
    data_offset = 0;
    printf("static const unsigned char _%s_data[] =\n", prefix);
    for (i=0; i<keys; i++) {
	printf("  \"%s\"\n", data_table[i]);
	data_offset += special_strlen(data_table[i]);
    }
    printf(";\n\n");

    /* output the index table (i.e. the buckets) */
    offset_size = (data_offset < 65536) ? 2 : 4;
    printf("static const unsigned char _%s_index[] = \n \"", prefix);
	
    data_offset = 0;
    for (i=0; i<keys; i++) {
	entry = hash_table + i;
	print_hash_entry(*entry, data_offset, offset_size);
	data_offset += special_strlen(data_table[i]);
    }

    // Sentry so that the data size calculation will work for the last bucket.
    // Because the offset is always read as integer (4 bytes) from memory,
    // make sure the last entry has a 4 byte offset.
    print_hash_entry(0, data_offset, 4);
    printf("\";\n\n");

    // Output the master structure.
    printf(
	"const struct hash_info hash_info_%s = {\n"
	"  hash_func: &_%s_fch,\n"
	"  index: _%s_index,\n"
	"  data: _%s_data,\n"
	"  offset_size: %d,\n"
	"};\n", prefix, prefix, prefix, prefix, offset_size);

    return 0;
}


/**
 * Check that only supported algorithms are used.
 *
 * @return 0 on success, 1 on error.
 */
int validate_mphf(cmph_t *mphf)
{
    if (mphf->algo != CMPH_FCH) {
	fprintf(stderr, "algorithm is not FCH, but %s\n",
	    cmph_names[mphf->algo]);
	return 1;
    }

    return 0;
}


/**
 * Load the given file using the cmph_load function of the cmph library,
 * then write the hash function data; then read the (key,value) file and
 * write that out, too, in the correct order.
 */
int main(int argc, char **argv)
{
    FILE *f;
    cmph_t *mphf;

    if (argc != 4) {
	fprintf(stderr, "Usage: %s {cmph file} {keyfile} {prefix}\n", argv[0]);
	return 1;
    }

    f = fopen(argv[1], "r");
    if (!f) {
	fprintf(stderr, "Unable to open input file %s: %s\n",
	    argv[1], strerror(errno));
	return 2;
    }

    mphf = cmph_load(f);
    fclose(f);

    if (!mphf) {
	fprintf(stderr, "Input file %s contains no valid cmph data.\n",
	    argv[1]);
	return 3;
    }

    if (validate_mphf(mphf))
	return 4;

    /* dump the fch data */
    fch_dump(mphf, argv[3]);

    // read the data, map in the correct order, write it
    return build_hash_table(mphf, argv[2], argv[3]);
}

