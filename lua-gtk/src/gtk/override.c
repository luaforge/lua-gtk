/* vim:sw=4:sts=4
 * Lua/Gnome binding: overrides for Gtk and GDK functions.
 */

#include <gtk/gtk.h>
#include "module.h"
#include "override.h"
#include <string.h>	    // strchr, strlen

extern struct lg_module_api *api;
extern struct module_info modinfo_gtk;


/**
 * Override for gtk_tree_model_get_value.  It allows to omit the third
 * argument, which is always nil.
 *
 * @luaparam  model
 * @luaparam  iter
 * @luaparam  column
 * @luareturn  The value (GValue) from the model.
 */
static int l_gtk_tree_model_get_value(lua_State *L)
{
    if (lua_gettop(L) == 3)
	lua_pushnil(L);
    return api->call_byname(L, thismodule, "gtk_tree_model_get_value");
}


/**
 * Simplify setting an item in a list store: determine the required GValue
 * type, then try to fill the gvalue and set the value with that.
 */
static int l_gtk_list_store_set_value(lua_State *L)
{
    OBJECT_ARG(store, GtkListStore, *, 1);
    OBJECT_ARG(iter, GtkTreeIter, *, 2);
    int column = luaL_checkinteger(L, 3);

    GType t = gtk_tree_model_get_column_type((GtkTreeModel*) store, column);

    GValue gvalue = {0};
    api->lua_to_gvalue_cast(L, 4, &gvalue, t);
    gtk_list_store_set_value(store, iter, column, &gvalue);
    g_value_unset(&gvalue);

    return 0;
}


// avoid the warning about superfluous arguments if given as callback
static int l_gtk_main_quit(lua_State *L)
{
    lua_settop(L, 0);
    return api->call_byname(L, &modinfo_gtk, "gtk_main_quit");
}


/**
 * Get icon theme search path: has a gchar*** argument which is not
 * supported automatically.
 *
 * @name  gtk_icon_theme_get_search_path
 * @luareturn  A new table with the search path elements
 */
static int l_gtk_icon_theme_get_search_path(lua_State *L)
{
    OBJECT_ARG(icon_theme, GtkIconTheme, *, 1);
    gchar **path;
    gint n_elements, i;

    void *(*func)(GtkIconTheme*, gchar**[], gint*) = api->optional_func(L,
	&modinfo_gtk, "gtk_icon_theme_get_search_path", "Gtk 2.4");
    func(icon_theme, &path, &n_elements);
    lua_createtable(L, n_elements, 0);
    for (i=0; i<n_elements; i++) {
	lua_pushstring(L, path[i]);
	lua_rawseti(L, -2, i + 1);
    }
    g_strfreev(path);
    return 1;
}


/**
 * Find a table element, possibly in a subtable by considering "." elements
 * of the name.  This is similar to lauxlib.c:luaL_findtable.
 *
 * @param L  Lua State
 * @param idx  Stack position of the table to look in
 * @param fname  Name of the field to look up
 * @return  0 if OK, 1 on error.  If OK, the Lua stack contains the found
 *   item.
 */
static int resolve_dotted_name(lua_State *L, int idx, const char *fname)
{
    const char *e;
    lua_pushvalue(L, idx);

    do {
	e = strchr(fname, '.');
	if (!e)
	    e = fname + strlen(fname);
	lua_pushlstring(L, fname, e - fname);
	lua_gettable(L, -2);

	// if not found, return an error.
	if (lua_isnil(L, -1)) {
	    lua_pop(L, 2);
	    return 1;
	}

	lua_remove(L, -2);	// remove previous table
	fname = e + 1;
    } while (*e == '.');

    return 0;
}


/**
 * Connect one signal for GtkBuilder.
 *
 * The connect_object and flags are ignored.  The handlers are looked up
 * in the provided table.
 *
 * Lua stack: [1]=builder, [2]=handler table
 */
static void _connect_func(GtkBuilder *builder, GObject *object,
    const gchar *signal_name, const gchar *handler_name,
    GObject *connect_object, GConnectFlags flags, gpointer user_data)
{
    lua_State *L = (lua_State*) user_data;
    int stack_top = lua_gettop(L), arg_cnt=3;

    // first, the function to call.  It is actually an override, see
    // src/glib/callback.c:glib_connect.
    lua_getglobal(L, "glib");
    lua_getfield(L, -1, "object_connect");
    lua_remove(L, -2);

    // arg 1: object.  An object proxy has to be created anyway, because it
    // is stored as reference in the callback structure.
    typespec_t zero_ts = { 0 };
    api->get_object(L, object, zero_ts, FLAG_NOT_NEW_OBJECT);
    if (lua_isnil(L, -1)) {
	printf("%s _connect_func: failed to make a proxy object for %p\n",
	    api->msgprefix, object);
	goto ex;
    }

    // arg 2: signal name
    lua_pushstring(L, signal_name);

    // arg 3: handler function.  Look it up in the given handler table;
    // subtables can be accessed, too.
    if (resolve_dotted_name(L, 2, handler_name)) {
	printf("%s signal handler %s not found.\n", api->msgprefix,
	    handler_name);
	goto ex;
    }

    // arg 4: the optional connect object.
    if (G_UNLIKELY(connect_object)) {
	api->get_object(L, connect_object, zero_ts, FLAG_NOT_NEW_OBJECT);
	if (lua_isnil(L, -1)) {
	    printf("_connect_func: failed to find the connect_object\n");
	    goto ex;
	}
	arg_cnt ++;
    }

    // got it.
    lua_call(L, arg_cnt, 1);

ex:
    lua_settop(L, stack_top);
}


/**
 * Autoconnect all signals.  The _full variant is used because it has a 
 * callback for the connection of the functions, so we can look for an
 * appropriate Lua function here.
 *
 * @luaparam builder  A builder object
 * @luaparam tbl  A table with signal handlers (optional, default is _G)
 */
static int l_gtk_builder_connect_signals_full(lua_State *L)
{
    OBJECT_ARG(builder, GtkBuilder, *, 1);

    void (*func)(GtkBuilder*, GtkBuilderConnectFunc, gpointer)
	= api->optional_func(L, &modinfo_gtk,
	    "gtk_builder_connect_signals_full", "Gtk 2.12");

    switch (lua_gettop(L)) {
	case 1:
	    lua_pushvalue(L, LUA_GLOBALSINDEX);
	    break;
	
	case 2:
	    luaL_checktype(L, 2, LUA_TTABLE);
	    break;
	
	default:
	    return luaL_error(L, "too many arguments");
    }

    // printf("building\n");
    func(builder, _connect_func, L);
    // printf("builder done\n");
    return 0;
}


// I've run into this problem before; just use that routine.
static GType _my_get_type_from_name(GtkBuilder *builder, const gchar *name)
{
    return api->gtype_from_name(NULL, NULL, name);
}


/**
 * Plug in a better get_type_from_name.  The default routine,
 * gtk_builder_real_get_type_from_name, using _gtk_builder_resolve_type_lazily,
 * doesn't work when the executable is not linked with libgtk2.0, as is the
 * case here.
 */
static int l_gtk_builder_new(lua_State *L)
{
    GtkBuilder *(*func)(void) = api->optional_func(L, &modinfo_gtk,
	"gtk_builder_new", "Gtk 2.12");
    GtkBuilder *builder = func();
    GtkBuilderClass *c = (GtkBuilderClass*) G_OBJECT_GET_CLASS(builder);
    c->get_type_from_name = _my_get_type_from_name;
    typespec_t ts = { 0 };
    api->get_object(L, builder, ts, FLAG_NEW_OBJECT);
    return 1;
}

FSO(gtk_stock_list_ids, GSLIST_FREE_GFREE)
FSO(gtk_file_chooser_get_filenames, GSLIST_FREE_GFREE)
FSO(gtk_file_chooser_get_uris, GSLIST_FREE_GFREE)
FSO(gtk_file_chooser_list_shortcut_folders, GSLIST_FREE_GFREE);
FSO(gtk_file_chooser_list_shortcut_folder_uris, GSLIST_FREE_GFREE);

/* overrides for GTK */
const luaL_reg gtk_overrides[] = {
    OVERRIDE(gtk_tree_model_get_value),
    OVERRIDE(gtk_main_quit),

    /* SList freeing */
    OVERRIDE(gtk_stock_list_ids),
    OVERRIDE(gtk_file_chooser_get_filenames),
    OVERRIDE(gtk_file_chooser_get_uris),
    OVERRIDE(gtk_file_chooser_list_shortcut_folders),
    OVERRIDE(gtk_file_chooser_list_shortcut_folder_uris),

    OVERRIDE(gtk_list_store_set_value),
    OVERRIDE(gtk_builder_new),
    OVERRIDE(gtk_builder_connect_signals_full),
    OVERRIDE(gtk_icon_theme_get_search_path),

    { NULL, NULL }
};

