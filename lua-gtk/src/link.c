
/**
 * Add every library function used to this list.
 */

const struct linkfunc dl_link[] = {
   LINK(g_type_from_name)
   LINK(g_type_parent)
   LINK(g_type_name)
   LINK(g_type_query)
   LINK(g_type_test_flags)
   LINK(g_type_interfaces)
   LINK(g_type_fundamental)
   LINK(g_type_is_a)
   LINK(g_type_check_instance_is_a)

   LINK(g_object_ref)
   LINK(g_object_unref)
   LINK(g_object_get_qdata)
   LINK(g_object_set_qdata_full)

   LINK(g_signal_lookup)
   LINK(g_signal_query)
   LINK(g_signal_connect_data)
   LINK(g_signal_handler_disconnect)

   LINK(g_free)
   LINK(g_quark_from_static_string)
   LINK(g_io_add_watch)
   LINK(g_io_channel_read_chars)
   LINK(g_io_channel_read_line)
   LINK(g_io_channel_write_chars)
   LINK(g_io_channel_flush)
#ifdef GTK_OLDER_THAN_2_10
   LINK(gtk_object_sink)
#else
   LINK(g_object_ref_sink)
#endif
   LINK(gtk_object_get_type)
   LINK(gdk_pixbuf_save_to_buffer)
   LINK(gtk_init)

	/* new */
    LINK(g_io_channel_unref)
    LINK(g_io_channel_ref)
    LINK(g_io_add_watch)
    LINK(g_io_add_watch_full)
    LINK(g_type_class_ref)
    LINK(g_object_class_find_property)
    LINK(g_object_set_property)
    LINK(g_type_class_unref)
    LINK(gtk_tree_model_get_value)
   { NULL, NULL }
};

