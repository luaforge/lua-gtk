/** vim:sw=4:sts=4
 * Verify that FFI closures work.
 * Copyright (C) 2008 Wolfgang Oertl
 */

#include <ffi.h>
#include <stdio.h>	/* printf */
#include <malloc.h>	/* malloc */
#include <stdlib.h>	/* atoi */

static int my_func(int a, char *b)
{
    return a + atoi(b);
}

static void closure_caller(ffi_cif *cif, void *resp, void **args, void *data)
{
    ffi_call(cif, data, resp, args);
}

static int test_closure()
{
    ffi_closure *closure;
    ffi_cif *cif;
    ffi_type **arg_types;
    void *code;
    int arg_count = 3;	// including return value
    int (*func_ptr)(int, char*);
    int rc;

    closure = (ffi_closure*) ffi_closure_alloc(sizeof(*closure), &code);
    cif = (ffi_cif*) malloc(sizeof(*cif));
    arg_types = (ffi_type**) malloc(sizeof(*arg_types) * arg_count);

    // types of the return value and the two arguments of "my_func"
    arg_types[0] = &ffi_type_sint;
    arg_types[1] = &ffi_type_sint;
    arg_types[2] = &ffi_type_pointer;

    rc = ffi_prep_cif(cif, FFI_DEFAULT_ABI, arg_count - 1, arg_types[0],
	arg_types + 1);
    if (rc) {
	printf("ffi_prep_cif returned %d\n", rc);
	return 1;
    }

    rc = ffi_prep_closure_loc(closure, cif, closure_caller, my_func, code);
    if (rc) {
	printf("ffi_prep_closure_loc returned %d\n", rc);
	return 1;
    }

#ifdef LUAGNOME_FFI_CODE
    func_ptr = (int(*)(int,char*)) code;
#else
 #ifdef LUAGNOME_FFI_CLOSURE
    func_ptr = (int(*)(int,char*)) closure;
 #else
    #error Please define one of LUAGNOME_FFI_{CODE,CLOSURE}.
 #endif
#endif

    /* now call this closure. */
    rc = func_ptr(99, "101");
    if (rc != 200) {
	printf("ffi_closure test failed, rc=%d\n", rc);
	return 1;
    }

    /* OK */
    return 0;
}


int main(int argc, char **argv)
{
    int rc = test_closure();
    return rc;
}

