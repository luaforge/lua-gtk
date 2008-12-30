/* vim:sw=4:sts=4
 *
 * This helper program simply prints out the cmph algorithm to use, which is
 * either fch or, if available, bdz.  The latter is better: it generates
 * a smaller hash function in less time.
 */

#include <cmph_types.h>
#include <string.h>
#include <stdio.h>

static int find_cmph_algo(const char *name)
{
    int i;

    for (i=0; i<CMPH_COUNT; i++) {
	if (!strcmp(cmph_names[i], name)) {
	    printf("%s\n", name);
	    return 1;
	}
    }

    return 0;
}


int main(int argc, char **argv)
{
    if (!find_cmph_algo("bdz") && !find_cmph_algo("fch")) {
	fprintf(stderr, "neither bdz nor fch algorithm is supported.");
	return 1;
    }

    return 0;
}

