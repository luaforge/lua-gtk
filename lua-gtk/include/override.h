
#define OVERRIDE(x) { #x, l_##x }

/* need to free strings: FSO=free string override */
#define FSO(x, f) static int l_##x(lua_State *L) { return lg_set_flags(L, #x, f); }

/* function argument that should be an object */
#define OBJECT_ARG(name, cls, ptr, idx) cls ptr name = \
    (cls ptr) api->object_arg(L, idx, #cls)->p

/* flags to set how to free elements of a GSList */
#define GSLIST_FREE_GFREE 1
#define GSLIST_FREE_PANGO_ATTR 2
#define GSLIST_FREE_PANGO_GLYPH 3

// in include/module.c
int lg_set_flags(lua_State *L, const char *funcname, int flag);

