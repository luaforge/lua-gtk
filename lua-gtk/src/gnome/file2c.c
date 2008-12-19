/** vim:sw=4:sts=4
 * Read a binary file and generate a C program on stdout that, when compiled,
 * contains a string with exactly the input data.
 * Copyright (C) 2005, 2007 Wolfgang Oertl
 */

#include <stdio.h>
#include <malloc.h>

/* how many characters per line?  Note that non-printable characters are output
 * as 4 bytes: \nnn */
#define PERLINE 40

FILE *ofile;
unsigned char *obuf;


/**
 * Write the buffer with binary data escaped to the output file.
 */
void store(int cnt, unsigned char *data)
{
    unsigned char c, *p = obuf;

    while (cnt--) {
	c = *data++;
	if (c == '"' || c == '\\')
	    *p++ = '\\';
	/* avoid trigraphs by storing ( as octal */
	if (c >= ' ' && c < 127 && c != '(')
	    *p++ = c;
	else
	    p += sprintf((char*)p, "\\%03o", c);
    }

    *p = 0;
    fputs((char*)obuf, ofile);
}


int main(int argc, char **argv)
{
    int cnt, total = 0;
    unsigned char *buf;
    char *prefix;

    if (argc != 2) {
	fprintf(stderr, "Usage: %s {prefix}.  Reads stdin, writes stdout.\n",
	    argv[0]);
	return 1;
    }

    prefix = argv[1];

    buf = (unsigned char*) malloc(PERLINE);

    // max. output size is 4 times the input size: each byte might be converted
    // to a 4 byte octal escape sequence.
    obuf = (unsigned char*) malloc(PERLINE * 4);
    ofile = stdout;

    printf("const unsigned char %s_data[] =\n", prefix);

    for (;;) {
	cnt = fread(buf, 1, PERLINE, stdin);
	if (cnt <= 0)
	    break;
	printf(" \"");
	store(cnt, buf);
	total += cnt;
	printf("\"\n");
    }

    free(obuf);
    free(buf);
    printf(";\nconst int %s_size = %d;\n", prefix, total);

    return 0;
}

