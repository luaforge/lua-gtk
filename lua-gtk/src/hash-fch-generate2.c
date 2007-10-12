/** vim:sw=4:sts=4
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
 */

#ifndef TYPE
 #error "Please define TYPE, e.g. funcs or enums."
#endif

#define XSTR(s) STR(s)
#define STR(s) #s

#define HASHFUNC2(x) fch_ ## x
#define HASHFUNC1(x) HASHFUNC2(x)
#define HASHFUNC HASHFUNC1(TYPE)

#include "hash-fch.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <malloc.h>

static buf_len = 200;


/**
 * Calculate the string length, but \xxx is considered as just one
 * character.
 */
int special_strlen(const char *s)
{
    int len = 0;

    while (*s) {
	if (*s == '\\')
	    s += 3;
	s ++;
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

    if (cnt > 20) {
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
int build_hash_table(const char *fname, struct my_fch *fch)
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

    hash_table = (unsigned int*) malloc(fch->m * sizeof(*hash_table));
    memset(hash_table, 0, fch->m * sizeof(*hash_table));
    data_table = (char**) malloc(fch->m * sizeof(*data_table));
    memset(data_table, 0, fch->m * sizeof(*data_table));

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

	/* split into key and data part */
	data = strchr(key, ',');
	if (!data) {
	    fprintf(stderr, "No data part on line %d\n", line);
	    continue;
	}
	*data = 0;
	data ++;
	keylen = data - key - 1;
	len -= keylen + 1;

	bucket_nr = my_fch_hash(fch, key, keylen, &hash_value);
	
	entry = hash_table + bucket_nr;
	if (*entry) {
	    fprintf(stderr, "Collision at %d\n", bucket_nr);
	    break;
	}

	*entry = hash_value;

	data_table[bucket_nr] = strdup(data);
    }

    free(buf);

    char *name = XSTR(TYPE);

    /* output header */
    printf("#include \"hash-fch.h\"\n\n");

    /* output the data table */
    data_offset = 0;
    printf("static const unsigned char my_data[] =\n");
    for (i=0; i<fch->m; i++) {
	printf("  \"%s\"\n", data_table[i]);
	data_offset += special_strlen(data_table[i]);
    }
    printf(";\n\n");

    /* output the hash table */
    offset_size = (data_offset < 65536) ? 2 : 4;
    printf("static const unsigned char my_hash[] = \n \"");
	
    data_offset = 0;
    for (i=0; i<fch->m; i++) {
	entry = hash_table + i;
	print_hash_entry(*entry, data_offset, offset_size);
	data_offset += special_strlen(data_table[i]);
    }

    print_hash_entry(0, data_offset, offset_size);
    printf("\";\n\n");

    /* output the master structure */
    printf("extern const struct my_fch " XSTR(HASHFUNC) ";\n");
    printf("const struct hash_info hash_info_%s = {\n", name);
    printf("  hash_func: &%s,\n", XSTR(HASHFUNC));
    printf("  data_table: my_data,\n");
    printf("  hash_table: my_hash,\n");
    printf("  offset_size: %d,\n", offset_size);
    printf("};\n");

    return 0;
}


int main(int argc, char **argv)
{
    if (argc != 2) {
	fprintf(stderr, "Usage: %s {keyfile}\n", argv[0]);
	return 1;
    }

    extern struct my_fch HASHFUNC;
    return build_hash_table(argv[1], &HASHFUNC);
}

