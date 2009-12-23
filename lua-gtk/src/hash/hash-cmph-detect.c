/* vim:sw=4:sts=4
 *
 * This helper program simply prints out the cmph algorithm to use, which is
 * either fch or, if available, bdz.  The latter is better: it generates
 * a smaller hash function in less time.
 */

#include <cmph_types.h>
#include <string.h>
#include <stdio.h>

static const char *supported[] = {
    // "chd_ph",
    "bdz",
    "fch",
    NULL
};

int main(int argc, char **argv)
{
    const char **algo, **s;

    for (algo=supported; *algo; algo++) {
	for (s=cmph_names; *s; s++)
	    if (!strcmp(*s, *algo)) {
		printf("%s\n", *algo);
		return 0;
	    }
    }

    fprintf(stderr,
	"hash-cmph-detect: no supported algorithm found in your cmph library.");
    return 1;
}

