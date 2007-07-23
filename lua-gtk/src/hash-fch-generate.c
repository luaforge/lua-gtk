/** vim:sw=4:sts=4
 * Given a data file as produced by CMPH using the FCH algorithm, create
 * a compileable C file from it.  This is just the hash function, even
 * though it includes a lookup table.
 */

#include <cmph.h>
#include <cmph_structs.h>
#include <fch_structs.h>
#include <jenkins_hash.h>

#include <string.h>
#include <errno.h>

/**
 * Output the data structure.
 * Required fields:
 *  h1, h2, m, b, p1, p2, g
 */

void fch_dump(cmph_t *mphf, const char *prefix)
{
    if (mphf->algo != CMPH_FCH) {
	fprintf(stderr, "Error: only the FCH algorithm is supported.\n");
	return;
    }

    struct __fch_data_t *f = (struct __fch_data_t*) mphf->data;
    jenkins_state_t *js;
    int i, g_size, cnt=0;
    unsigned int maxval = 0;

    /* analyze the "g" table to find the maximum value. */

    for (i=0; i<f->b; i++)
	if (maxval < f->g[i])
	    maxval = f->g[i];
    g_size = maxval < 65536 ? 16 : 32;
	
    printf("/* max. value in g is %d */\n", maxval);

    printf("#include \"hash-fch.h\"\n");
    printf("const struct my_fch %s = {\n", prefix);
    printf("  m: %d,\n", f->m);
    printf("  b: %d,\n", f->b);
    printf("  g_size: %d,\n", g_size);
    printf("  p1: %f,\n", f->p1);
    printf("  p2: %f,\n", f->p2);
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
 * Load the given file using the cmph_load function of the cmph library,
 * then call the dump function.
 */
int main(int argc, char **argv)
{
    FILE *f;
    cmph_t *mphf;

    if (argc != 3) {
	fprintf(stderr, "Usage: %s {input file} {prefix}\n", argv[0]);
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

    /* dump the fch data */
    fch_dump(mphf, argv[2]);

    return 0;
}

