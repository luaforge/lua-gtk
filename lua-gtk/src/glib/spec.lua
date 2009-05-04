-- vim:sw=4:sts=4

name = "GObject"
pkg_config_name = "gobject-2.0"
required = true

include_dirs = { "glib-2.0" }

libraries = {}
libraries.linux = {
    "/usr/lib/libgobject-2.0.so",
    "/usr/lib/libgmodule-2.0.so",
    "/usr/lib/libgthread-2.0.so",
}
libraries.win32 = {
    "libglib-2.0-0.dll",
    "libgobject-2.0-0.dll",
    "libgmodule-2.0-0.dll",
}

path_glib = "/usr/include/glib-2.0"

headers = {
    { path_glib .. "/gobject/gtype.h", false },
    { path_glib .. "/gio/gfileinfo.h", false },
    { path_glib .. "/gio/gvolumemonitor.h", false },
    { path_glib .. "/glib/gmain.h", true },
}

includes = {}
includes.all = {
    "<glib-object.h>",
    "<glib.h>",
    "<gmodule.h>",
    "<glib/gstdio.h>",
}

defs = {}
defs.all  = {
    "#undef __OPTIMIZE__",
}
defs.win32 = {
    "#define G_OS_WIN32",
}
defs.linux = {
    "#define G_STDIO_NO_WRAP_ON_UNIX",
}

include_types = {		-- used in which other module:
    "GInitiallyUnowned",
    "size_t",
    "tm*",
    "stat*",
    "time_t",
    "time_t*",
    "timespec",
    "FILE*",
--    "va_list",

    "gint8*",			-- gdk
    "guint**",			-- gdk
    "const GTimeVal*",		-- gdk
    "guchar**",			-- gdk
    "gint**",			-- gdk
    "guint32*",			-- gdk
    "const gint",		-- gdk
    "const gint*",		-- gdk

    "GMarkupParser*",		-- gtk
    "gfloat*",			-- gtk
    "GList**",			-- gtk
    "guint16*",			-- gtk
    "GOptionEntry*",		-- gtk
    "const GParamSpec*"	,	-- gtk

    "gint16",			-- gio

    "GSList**",			-- gtkhtml

    "short int*",		-- clutter
}

function_flags = {
    g_main_context_default = CONST_OBJECT,		-- don't free retval
    g_ascii_stroll = { nil, DONT_FREE },		-- don't free 2nd arg

--    GCompletion.func = CONST_CHAR_PTR,
--    GTypeValueTable.collect_value = CHAR_PTR,
--    GTypeValueTable.lcopy_value = CHAR_PTR,
--    funcptr.GCompletionFunc = CONST_CHAR_PTR,
--    funcptr.GTranslateFunc = CONST_CHAR_PTR,
--    funcptr.GtkTranslateFunc = CHAR_PTR,

    g_array_free = CHAR_PTR,
    g_ascii_dtostr = CHAR_PTR,
    g_ascii_formatd = CHAR_PTR,
    g_ascii_strdown = CHAR_PTR,
    g_ascii_strup = CHAR_PTR,
    g_base64_encode = CHAR_PTR,
    g_basename = CONST_CHAR_PTR,
    g_bookmark_file_get_description = CHAR_PTR,
    g_bookmark_file_get_mime_type = CHAR_PTR,
    g_bookmark_file_get_title = CHAR_PTR,
    g_bookmark_file_to_data = CHAR_PTR,
    g_build_filename = CHAR_PTR,
    g_build_filenamev = CHAR_PTR,
    g_build_path = CHAR_PTR,
    g_build_pathv = CHAR_PTR,
--    g_completion_new.func = CHAR_PTR,
    g_convert = CHAR_PTR,
    g_convert_with_fallback = CHAR_PTR,
    g_convert_with_iconv = CHAR_PTR,
    g_dir_read_name = CONST_CHAR_PTR,
    g_dir_read_name_utf8 = CONST_CHAR_PTR,
    g_file_read_link = CHAR_PTR,
    g_filename_display_basename = CHAR_PTR,
    g_filename_display_name = CHAR_PTR,
    g_filename_from_uri = CHAR_PTR,
    g_filename_from_uri_utf8 = CHAR_PTR,
    g_filename_from_utf8 = CHAR_PTR,
    g_filename_from_utf8_utf8 = CHAR_PTR,
    g_filename_to_uri = CHAR_PTR,
    g_filename_to_uri_utf8 = CHAR_PTR,
    g_filename_to_utf8 = CHAR_PTR,
    g_filename_to_utf8_utf8 = CHAR_PTR,
    g_find_program_in_path = CHAR_PTR,
    g_find_program_in_path_utf8 = CHAR_PTR,
    g_get_application_name = CONST_CHAR_PTR,
    g_get_current_dir = CHAR_PTR,
    g_get_current_dir_utf8 = CHAR_PTR,
    g_get_home_dir = CONST_CHAR_PTR,
    g_get_home_dir_utf8 = CONST_CHAR_PTR,
    g_get_host_name = CONST_CHAR_PTR,
    g_get_prgname = CHAR_PTR,
    g_get_real_name = CONST_CHAR_PTR,
    g_get_real_name_utf8 = CONST_CHAR_PTR,
    g_get_tmp_dir = CONST_CHAR_PTR,
    g_get_tmp_dir_utf8 = CONST_CHAR_PTR,
    g_get_user_cache_dir = CONST_CHAR_PTR,
    g_get_user_config_dir = CONST_CHAR_PTR,
    g_get_user_data_dir = CONST_CHAR_PTR,
    g_get_user_name = CONST_CHAR_PTR,
    g_get_user_name_utf8 = CONST_CHAR_PTR,
    g_get_user_special_dir = CONST_CHAR_PTR,
    g_getenv = CONST_CHAR_PTR,
    g_getenv_utf8 = CONST_CHAR_PTR,
    g_intern_static_string = CONST_CHAR_PTR,
    g_intern_string = CONST_CHAR_PTR,
    g_io_channel_get_encoding = CONST_CHAR_PTR,
    g_io_channel_get_line_term = CONST_CHAR_PTR,
    g_key_file_get_comment = CHAR_PTR,
    g_key_file_get_locale_string = CHAR_PTR,
    g_key_file_get_start_group = CHAR_PTR,
    g_key_file_get_string = CHAR_PTR,
    g_key_file_get_value = CHAR_PTR,
    g_key_file_to_data = CHAR_PTR,
    g_locale_from_utf8 = CHAR_PTR,
    g_locale_to_utf8 = CHAR_PTR,
    g_mapped_file_get_contents = CHAR_PTR,
    g_markup_escape_text = CHAR_PTR,
    g_markup_parse_context_get_element = CONST_CHAR_PTR,
    g_markup_printf_escaped = CHAR_PTR,
    g_markup_vprintf_escaped = CHAR_PTR,
    g_match_info_expand_references = CHAR_PTR,
    g_match_info_fetch = CHAR_PTR,
    g_match_info_fetch_named = CHAR_PTR,
    g_match_info_get_string = CONST_CHAR_PTR,
    g_module_build_path = CHAR_PTR,
    g_module_error = CONST_CHAR_PTR,
    g_module_name = CONST_CHAR_PTR,
    g_module_name_utf8 = CONST_CHAR_PTR,
    g_option_context_get_description = CONST_CHAR_PTR,
    g_option_context_get_help = CHAR_PTR,
    g_option_context_get_summary = CONST_CHAR_PTR,
--    g_option_context_set_translate_func.func = CONST_CHAR_PTR,
--    g_option_group_set_translate_func.func = CONST_CHAR_PTR,
    g_param_spec_get_blurb = CONST_CHAR_PTR,
    g_param_spec_get_name = CONST_CHAR_PTR,
    g_param_spec_get_nick = CONST_CHAR_PTR,
    g_path_get_basename = CHAR_PTR,
    g_path_get_dirname = CHAR_PTR,
    g_path_skip_root = CONST_CHAR_PTR,
    g_quark_to_string = CONST_CHAR_PTR,
    g_regex_escape_string = CHAR_PTR,
    g_regex_get_pattern = CONST_CHAR_PTR,
    g_regex_replace = CHAR_PTR,
    g_regex_replace_eval = CHAR_PTR,
    g_regex_replace_literal = CHAR_PTR,
    g_shell_quote = CHAR_PTR,
    g_shell_unquote = CHAR_PTR,
    g_signal_name = CONST_CHAR_PTR,
    g_stpcpy = CHAR_PTR,
    g_strcanon = CHAR_PTR,
    g_strchomp = CHAR_PTR,
    g_strchug = CHAR_PTR,
    g_strcompress = CHAR_PTR,
    g_strconcat = CHAR_PTR,
    g_strdelimit = CHAR_PTR,
    g_strdown = CHAR_PTR,
    g_strdup = CHAR_PTR,
    g_strdup_printf = CHAR_PTR,
    g_strdup_value_contents = CHAR_PTR,
    g_strdup_vprintf = CHAR_PTR,
    g_strerror = CONST_CHAR_PTR,
    g_strescape = CHAR_PTR,
    g_string_chunk_insert = CHAR_PTR,
    g_string_chunk_insert_const = CHAR_PTR,
    g_string_chunk_insert_len = CHAR_PTR,
    g_string_free = CHAR_PTR,
    g_strip_context = CONST_CHAR_PTR,
    g_strjoin = CHAR_PTR,
    g_strjoinv = CHAR_PTR,
    g_strndup = CHAR_PTR,
    g_strnfill = CHAR_PTR,
    g_strreverse = CHAR_PTR,
    g_strrstr = CHAR_PTR,
    g_strrstr_len = CHAR_PTR,
    g_strsignal = CONST_CHAR_PTR,
    g_strstr_len = CHAR_PTR,
    g_strup = CHAR_PTR,
    g_time_val_to_iso8601 = CHAR_PTR,
    g_type_name = CONST_CHAR_PTR,
    g_type_name_from_class = CONST_CHAR_PTR,
    g_type_name_from_instance = CONST_CHAR_PTR,
    g_ucs4_to_utf8 = CHAR_PTR,
    g_ucs4_to_utf16 = CHAR_PTR,
    g_utf16_to_utf8 = CHAR_PTR,
    g_utf8_to_ucs4 = CHAR_PTR,
    g_utf8_to_utf16 = CHAR_PTR,
    g_utf8_casefold = CHAR_PTR,
    g_utf8_collate_key = CHAR_PTR,
    g_utf8_collate_key_for_filename = CHAR_PTR,
    g_utf8_find_next_char = CONST_CHAR_PTR, -- inconsistency
    g_utf8_find_prev_char = CONST_CHAR_PTR, -- inconsistency
    g_utf8_normalize = CHAR_PTR,
    g_utf8_offset_to_pointer = CONST_CHAR_PTR,	-- inconsistency
    g_utf8_prev_char = CONST_CHAR_PTR,	-- inconsistency
    g_utf8_strchr = CONST_CHAR_PTR,	-- inconsistency
    g_utf8_strdown = CHAR_PTR,
    g_utf8_strncpy = CONST_CHAR_PTR,	-- inconsistency
    g_utf8_strrchr = CONST_CHAR_PTR,	-- inconsistency
    g_utf8_strreverse = CHAR_PTR,
    g_utf8_strup = CHAR_PTR,
    g_value_dup_string = CHAR_PTR,
    g_value_get_string = CONST_CHAR_PTR,
}

ignore_functions = {
    glib_dummy_decl = true,
    g_string_append_c_inline = true,
}

aliases = {
    g_pattern_spec_match_string = "g_pattern_match_string",
}

linklist = {
    "g_free",
    "g_malloc",
    "g_iconv",
    "g_idle_add",
    "g_object_class_find_property",
    "g_object_get_property",
    "g_object_set_property",
    "g_object_unref",
    "g_object_ref_sink",
    "g_object_ref",
    "g_timeout_add",
    "g_type_class_ref",
    "g_type_class_unref",
    "g_type_from_name",
    "g_type_name",
    "g_type_parent",
    "g_value_unset",
    "g_assertion_message",
    "g_signal_connect_data",
    "g_signal_handler_disconnect",
    "g_signal_lookup",
    "g_signal_query",
    "g_slice_alloc",			-- used!
    "g_slice_free1",			-- used!
    "g_type_value_table_peek",		-- used!
    "g_type_is_a",
    "g_value_init",
    "g_utf8_skip",

    -- in channel.c
    "g_io_add_watch_full",
    "g_io_channel_flush",
    "g_io_channel_read_chars",
    "g_io_channel_read_line",
    "g_io_channel_ref",
    "g_io_channel_unref",
    "g_io_channel_write_chars",
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"g_"',
    prefix_constant = '"G_"',
    prefix_type = '"G"',
    depends = '""',
    overrides = "glib_overrides",
}

