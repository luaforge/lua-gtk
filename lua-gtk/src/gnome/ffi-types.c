/* vim:sw=4:sts=4
 *
 * Generate an include file with typedefs for each FFI data type, which will
 * be used instead of pointers to identify each type.  This allows to save lots
 * of space in ffi_type_map.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * Note: for this scheme to work, all ffi_type_xxx structures must be
 * evenly spaced (padding allowed) in the FFI library - which is the case.
 */

#include <ffi.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>

/* List of all relevant data types.  Note that the first part (uchar etc.)
 * contains aliases for one of the entries of the second part; it depends
 * on the processor architecture (32/64 bit), how the mapping is. */
static struct info {
    const char *name;
    const ffi_type *t;
} info_map[] = {
    { "void", &ffi_type_void },

    { "uchar", &ffi_type_uchar },
    { "schar", &ffi_type_schar },
    { "ushort", &ffi_type_ushort },
    { "sshort", &ffi_type_sshort },
    { "uint", &ffi_type_uint },
    { "sint", &ffi_type_sint },
    { "ulong", &ffi_type_ulong },
    { "slong", &ffi_type_slong },

    { "uint8", &ffi_type_uint8 },
    { "sint8", &ffi_type_sint8 },
    { "uint16", &ffi_type_uint16 },
    { "sint16", &ffi_type_sint16 },
    { "uint32", &ffi_type_uint32 },
    { "sint32", &ffi_type_sint32 },
    { "uint64", &ffi_type_uint64 },
    { "sint64", &ffi_type_sint64 },
    { "float", &ffi_type_float },
    { "double", &ffi_type_double },
    { "pointer", &ffi_type_pointer },
    { "longdouble", &ffi_type_longdouble }
};
#define INFO_MAP_ITEMS (sizeof(info_map) / sizeof(*info_map))

static void str_toupper(const char *s, char *p)
{
   while (*s)
   	*p++ = toupper(*s++);
    *p = 0;
}

// sort by offset
static int info_map_compare(const void *_a, const void *_b)
{
    const struct info *a = (const struct info*) _a;
    const struct info *b = (const struct info*) _b;

    if (a->t == b->t)
	return 0;

    return a->t < b->t ? -1 : 1;
}


/**
 * Determine the offsets of each ffi_type_xxx entry, the first one, their
 * relative offsets (which must be a multiple of a constant); output one
 * #define per entry and a formula to calculate the offset given the
 * first item.
 *
 * Note: the index 0 will be "undefined", and 1 the first item etc.
 */
int main()
{
    char buf[50];
    int err = 0, i, dist, ofs;

    // sort by address
    qsort(info_map, INFO_MAP_ITEMS, sizeof(*info_map), info_map_compare);

    // determine distance
    dist = ((char*)info_map[1].t) - ((char*)info_map[0].t);
    printf("#define LUAGNOME_FFI_TYPE(nr) ((ffi_type*)(((char*)&ffi_type_%s)"
	"+((nr)-1)*%d))\n", info_map[0].name, dist);
    for (i=0; i<INFO_MAP_ITEMS; i++) {
	ofs = ((char*)info_map[i].t) - ((char*)info_map[0].t);

	if (ofs % dist) {
	    printf("// Misaligned entry %s by %d\n", info_map[i].name,
		ofs % dist);
	    err ++;
	} else {
	    str_toupper(info_map[i].name, buf);
	    printf("#define LUAGNOME_FFI_TYPE_%s %d\n",
		buf,
		ofs / dist + 1);
	}
    }

    return err;
}
    
	

