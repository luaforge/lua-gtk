/** vim:sw=4:sts=4
 * Test whether a vararg function can be called when typecast to a regular
 * function.
 * Copyright (C) 2007 Wolfgang Oertl
 */

#include <stdarg.h>

int func1(int *a, ...)
{
    va_list ap;

    va_start(ap, a);
    int rc = *a + va_arg(ap, int) + va_arg(ap, double) + va_arg(ap, int);
    va_end(ap);

    return rc;
}

typedef int (*func_t)(int *a, int b, double c, int d);

int main(int argc, char **argv)
{
    func_t f = (func_t) func1;
    int a = 10, b = 20, d = 40;
    double c = 30.0;

    int rc = f(&a, b, c, d);

    return (rc == a+b+c+d) ? 0 : 1;
}

