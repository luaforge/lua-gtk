/** vim:sw=4:sts=4
 * Test whether a vararg function can be called when typecast to a regular
 * function.
 * Copyright (C) 2007 Wolfgang Oertl
 *
 * When run, returns 0 on success, or a non-zero exit status on error; this
 * includes if terminated by segfault, which happens e.g. on amd64 - unless
 * the specific workaround is enabled.
 */

#include "config.h"
#include <stdarg.h>
#include <stdio.h>

int a = 1, b = 10, d = 1000;
double c = 100.0;

/**
 * This is the function with variable arguments that is called.
 */
int _callback(int *a2, ...)
{
    va_list ap;
    int rc, a1, b1, d1;
    double c1;

    va_start(ap, a2);
    a1 = *a2;
    b1 = va_arg(ap, int);
    c1 = va_arg(ap, double);
    d1 = va_arg(ap, int);
    // doing this makes it work on mips.  strange.
    // printf("%d %d %f %d\n", a1, b1, c1, d1);
    rc = a1 + b1 + c1 + d1;
    va_end(ap);

    return rc;
}

/**
 * Type of a non-vararg function with the parameters expected by func1
 */
typedef int (*func_t)(int *a, int b, double c, int d);


#ifdef LUAGTK_linux_amd64
static int _callback_amd64(void *dummy, ...);
asm(
".text\n"
"	.type _callback_amd64, @function\n"
"_callback_amd64:\n"
"	movq	$1, %rax\n"
"	jmp	_callback\n"
"	.size	_callback_amd64, . - _callback_amd64\n"
);
#define CALL_FUNC _callback_amd64
void dummy()
{
    _callback(0);
}
#else
#define CALL_FUNC _callback
#endif

/**
 * Main routine: call _callback, check the result.
 */
int main(int argc, char **argv)
{
    int expected, rc, err=0;
    func_t f = (func_t) CALL_FUNC;

    /* test conversion from double to int. */
    rc = c;
    if (rc != 100) {
	printf("double to int conversion failure: %f != %d\n", c, rc);
	err ++;
    }

    expected = a + b + ((int)c) + d;

    /* call the vararg function directly. */
    rc = _callback(&a, b, c, d);
    if (rc != expected) {
	printf("first test failed.  Got %d instead of %d\n", rc, expected);
	err ++;
    }

    /* call the vararg function as normal function. */
    rc = f(&a, b, c, d);
    if (rc != expected) {
	printf("second test failed.  Got %d instead of %d\n", rc, expected);
	err ++;
    }

    return err;
}

