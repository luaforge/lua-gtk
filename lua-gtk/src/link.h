
/**
 * To avoid linking the lua-gtk2 library directly with any Gtk libraries,
 * this header provides some glue code.
 *
 * It is optional to use it.  See MANUAL_LINKING in luagtk.h.
 */

/* functions from the DLLs */
/* add the _ptr declaration, a #define, and also an entry in call.c */

/* g_type functions */
int (*g_type_from_name_ptr)(const char *class_name);
int (*g_type_parent_ptr)(int class_nr);
const char *(*g_type_name_ptr)(int class_nr);
void (*g_type_query_ptr)(int type_nr, GTypeQuery *query);
gboolean (*g_type_test_flags_ptr)(GType type, guint flags);
GType *(*g_type_interfaces_ptr)(GType type, guint *n_interfaces);
gboolean (*g_type_check_instance_is_a_ptr)(GTypeInstance *instance,
    GType iface_type);
GType (*g_type_fundamental_ptr)(GType type_id);
gboolean (*g_type_is_a_ptr)(GType type, GType is_a_type);

/* g_object functions */
gpointer (*g_object_ref_ptr)(gpointer object);
void (*g_object_unref_ptr)(gpointer object);
gpointer (*g_object_get_qdata_ptr)(GObject*, GQuark);
void (*g_object_set_qdata_full_ptr)(GObject*, GQuark, gpointer,
    GDestroyNotify);
void (*gtk_object_sink_ptr)(GtkObject *object);

/* g_signal functions */
int (*g_signal_lookup_ptr)(const char *name, GType type);
void (*g_signal_query_ptr)(int signal_id, GSignalQuery *query);
int (*g_signal_connect_data_ptr)(gpointer instance, const char *signame,
    GCallback c_handler, gpointer data, GClosureNotify destroy_data,
    GConnectFlags connect_flags);
void (*g_signal_handler_disconnect_ptr)(gpointer instance,
    gulong handler_id);
gboolean (*gdk_pixbuf_save_to_buffer_ptr)(GdkPixbuf *pixbuf, gchar **buffer,
	gsize *buffer_size, const char *type, GError **error, ...);

/* others */
GtkType (*gtk_object_get_type_ptr)(void);
#define gtk_object_get_type gtk_object_get_type_ptr

GQuark (*g_quark_from_static_string_ptr)(const gchar *string);
#define g_quark_from_static_string g_quark_from_static_string_ptr

void (*g_free_ptr)(void*);
#define g_free g_free_ptr

guint (*g_io_add_watch_ptr)(GIOChannel *channel, GIOCondition condition,
	GIOFunc func, gpointer user_data);
#define g_io_add_watch g_io_add_watch_ptr

GIOStatus (*g_io_channel_read_chars_ptr)(GIOChannel *channel, gchar *buf,
	gsize count, gsize *bytes_read, GError **error);
#define g_io_channel_read_chars g_io_channel_read_chars_ptr

GIOStatus (*g_io_channel_read_line_ptr)(GIOChannel *channel, gchar **str_return,
	gsize *length, gsize *terminator_pos, GError **error);
#define g_io_channel_read_line g_io_channel_read_line_ptr

GIOStatus (*g_io_channel_write_chars_ptr)(GIOChannel *channel, const gchar *buf,
	gssize count, gsize *bytes_written, GError **error);
#define g_io_channel_write_chars g_io_channel_write_chars_ptr

GIOStatus (*g_io_channel_flush_ptr)(GIOChannel *channel, GError **error);
#define g_io_channel_flush g_io_channel_flush_ptr

void (*gtk_init_ptr)(int *argc, char **argv);
#define gtk_init gtk_init_ptr



#define LINK(s) { #s, (void (*)) &s##_ptr },
#define g_type_from_name g_type_from_name_ptr
#define g_type_parent g_type_parent_ptr
#define g_type_name g_type_name_ptr
#define g_type_query g_type_query_ptr
#define g_type_test_flags g_type_test_flags_ptr
#define g_type_interfaces g_type_interfaces_ptr
#define g_type_fundamental g_type_fundamental_ptr
#define g_type_check_instance_is_a g_type_check_instance_is_a_ptr
#define g_type_is_a g_type_is_a_ptr

#define g_object_ref g_object_ref_ptr
#define g_object_unref g_object_unref_ptr
#define g_object_get_qdata g_object_get_qdata_ptr
#define g_object_set_qdata_full g_object_set_qdata_full_ptr

#define g_signal_lookup g_signal_lookup_ptr
#define g_signal_query g_signal_query_ptr
#define g_signal_connect_data g_signal_connect_data_ptr
#define g_signal_handler_disconnect g_signal_handler_disconnect_ptr

#define gtk_object_sink gtk_object_sink_ptr

#define gdk_pixbuf_save_to_buffer gdk_pixbuf_save_to_buffer_ptr





/* new */
void        (*g_io_channel_unref_ptr)  (GIOChannel    *channel);
#define g_io_channel_unref g_io_channel_unref_ptr

GIOChannel *(*g_io_channel_ref_ptr)    (GIOChannel    *channel);
#define g_io_channel_ref g_io_channel_ref_ptr

guint     (*g_io_add_watch_full_ptr)   (GIOChannel      *channel,
				 gint             priority,
				 GIOCondition     condition,
				 GIOFunc          func,
				 gpointer         user_data,
				 GDestroyNotify   notify);
#define g_io_add_watch_full g_io_add_watch_full_ptr

gpointer (*g_type_class_ref_ptr)(GType type);
#define g_type_class_ref g_type_class_ref_ptr

void (*g_type_class_unref_ptr)(gpointer g_class);
#define g_type_class_unref g_type_class_unref_ptr

GParamSpec* (*g_object_class_find_property_ptr)(GObjectClass *oclass,
	const gchar *property_name);
#define g_object_class_find_property g_object_class_find_property_ptr

void (*g_object_set_property_ptr)(GObject *object, const gchar *property_name,
	const GValue *value);
#define g_object_set_property g_object_set_property_ptr

void (*gtk_tree_model_get_value_ptr)(GtkTreeModel *tree_model,
	GtkTreeIter *iter, gint column, GValue *value);
#define gtk_tree_model_get_value gtk_tree_model_get_value_ptr






#if 0
/* redirect common functions to save on dynamic relocation data */
/* this can save memory of maybe 0.5 kB - not very effective... */
static void lua_pushstring_i(lua_State *L, const char *s) { lua_pushstring(L, s); }
#define lua_pushstring lua_pushstring_i
static void lua_settop_i(lua_State *L, int i) { lua_settop(L, i); }
#define lua_settop lua_settop_i
static void lua_pushvalue_i(lua_State *L, int i) { lua_pushvalue(L, i); }
#define lua_pushvalue lua_pushvalue_i
static int lua_gettop_i(lua_State *L) { return lua_gettop(L); }
#define lua_gettop lua_gettop_i
static void lua_rawset_i(lua_State *L, int i) { lua_rawset(L, i); }
#define lua_rawset lua_rawset_i
static const void *lua_topointer_i(lua_State *L, int i) { return lua_topointer(L, i); }
#define lua_topointer lua_topointer_i
static int printf_i(const char *fmt, ...) { va_list va; va_start(va, fmt);
 return vprintf(fmt, va); }
#define printf printf_i
#endif


