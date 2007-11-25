/** vim:sw=4:sts=4
 * Test whether a vararg function can be called when typecast to a regular
 * function.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * When run, returns 0 on success, or a non-zero exit status on error; this
 * includes if terminated by segfault, which happens e.g. on amd64.
 */

#include <stdarg.h>

/**
 * This is the function with variable arguments that is called.
 */
int func1(int *a, ...)
{
    va_list ap;

    va_start(ap, a);
    int rc = *a + va_arg(ap, int) + va_arg(ap, double) + va_arg(ap, int);
    va_end(ap);

    return rc;
}

/**
 * Type of a non-vararg function with the parameters expected by func1
 */
typedef int (*func_t)(int *a, int b, double c, int d);


/**
 * Main routine: call func1, check the result.
 */
int main(int argc, char **argv)
{
    func_t f = (func_t) func1;
    int a = 10, b = 20, d = 40;
    double c = 30.0;

    int rc = f(&a, b, c, d);

    return (rc == a+b+c+d) ? 0 : 1;
}

