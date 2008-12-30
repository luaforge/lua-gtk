-- vim:sw=4:sts=4

name = "Gtk"
pkg_config_name = "gtk+-2.0"
required = true

libraries = {}
libraries.linux = { "/usr/lib/libgtk-x11-2.0.so" }
libraries.win32 = { "libgtk-win32-2.0-0.dll" }

include_dirs = { "gtk-2.0/gtk" }

path_gtk = "/usr/include/gtk-2.0"

headers = {
    { path_gtk .. "/gtk/gtkstock.h", false },
}

includes = { all = { "<gtk/gtk.h>" } }


-- Defines for make-xml.lua

-- #undef __OPTIMIZE_: Avoid trouble with -O regarding __builtin_clzl.
-- Seems to have no other side effects (XML file exactly the same).
-- Suggested by Michael Kolodziejczyk on 2007-10-23

defs = {}
defs.all = {
--   "#undef __OPTIMIZE__",
    "#define GTK_DISABLE_DEPRECATED 1",
    "#define GDK_DISABLE_DEPRECATED 1",
    "#define GDK_PIXBUF_ENABLE_BACKEND 1",
}
defs.win32 = {
--	"#define G_OS_WIN32",
    -- workaround for compilation error in gtk-2.0/gdk/gdk.h:189
    "#define __declspec(x)",
    "#define dllexport",
    "#define __GTK_DEBUG_H__",
}
-- defs.linux = {
-- 	"#define G_STDIO_NO_WRAP_ON_UNIX",
-- }


-- entry: function name = { [arg_nr]=flags, ... }
-- arg_nr start with 1 for the return value.  If only the return value is
-- specified, can be just "flags".
function_flags = {
    gtk_file_chooser_get_current_folder = CHAR_PTR,
    gtk_clipboard_get = CONST_OBJECT,
    gtk_text_tag_table_lookup = NOT_NEW_OBJECT, 	-- like a _get function
    gtk_text_buffer_create_tag = NOT_NEW_OBJECT,	-- owned by text tag table
    gtk_text_buffer_create_mark = CONST_OBJECT,
    gtk_text_view_get_buffer = NOT_NEW_OBJECT,

    -- configuration of the char_ptr return values - whether to free the
    -- resulting string or not.

    gtk_file_chooser_get_current_folder = CHAR_PTR,
    gtk_file_chooser_get_filename = CHAR_PTR,
    gtk_file_chooser_get_preview_filename = CHAR_PTR,
    gtk_icon_info_get_filename = CONST_CHAR_PTR,
    gtk_icon_source_get_filename = CONST_CHAR_PTR,

    -- arch win32

    gtk_file_chooser_get_current_folder_utf8 = CHAR_PTR,
    gtk_file_chooser_get_filename_utf8 = CHAR_PTR,
    gtk_file_chooser_get_preview_filename_utf8 = CHAR_PTR,
    gtk_icon_info_get_filename_utf8 = CONST_CHAR_PTR,
    gtk_icon_source_get_filename_utf8 = CONST_CHAR_PTR,

    -- arch all

    gtk_combo_box_get_active_text = CHAR_PTR,

    gtk_entry_get_text = CONST_CHAR_PTR,
    gtk_file_chooser_get_uri = CHAR_PTR,
    gtk_file_chooser_get_current_folder_uri = CHAR_PTR,
    gtk_file_chooser_get_preview_uri = CHAR_PTR,

    gtk_about_dialog_get_comments = CONST_CHAR_PTR,
    gtk_about_dialog_get_copyright = CONST_CHAR_PTR,
    gtk_about_dialog_get_license = CONST_CHAR_PTR,
    gtk_about_dialog_get_logo_icon_name = CONST_CHAR_PTR,
    gtk_about_dialog_get_program_name = CONST_CHAR_PTR,
    gtk_about_dialog_get_translator_credits = CONST_CHAR_PTR,
    gtk_about_dialog_get_version = CONST_CHAR_PTR,
    gtk_about_dialog_get_website = CONST_CHAR_PTR,
    gtk_about_dialog_get_website_label = CONST_CHAR_PTR,

    gtk_window_get_title = CONST_CHAR_PTR,
    gtk_window_get_role = CONST_CHAR_PTR,
    gtk_window_get_icon_name = CONST_CHAR_PTR,

    -- documentation is wrong, the code is right.  A bug has been filed
    -- already.
    gtk_widget_get_composite_name = CHAR_PTR,

    gtk_widget_get_name = CONST_CHAR_PTR,
    gtk_widget_get_tooltip_markup = CHAR_PTR,
    gtk_widget_get_tooltip_text = CHAR_PTR,
    gtk_ui_manager_get_ui = CHAR_PTR,

    gtk_tree_view_column_get_title = CONST_CHAR_PTR,
    gtk_tree_path_to_string = CHAR_PTR,
    gtk_tree_model_get_string_from_iter = CHAR_PTR,

    gtk_tool_button_get_label = CONST_CHAR_PTR,
    gtk_tool_button_get_stock_id = CONST_CHAR_PTR,
    gtk_tool_button_get_icon_name = CONST_CHAR_PTR,

    gtk_text_mark_get_name = CONST_CHAR_PTR,
    gtk_text_buffer_get_slice = CHAR_PTR,
    gtk_text_buffer_get_text = CHAR_PTR,
    gtk_text_iter_get_slice = CHAR_PTR,
    gtk_text_iter_get_text = CHAR_PTR,
    gtk_text_iter_get_visible_slice = CHAR_PTR,
    gtk_text_iter_get_visible_text = CHAR_PTR,

    gtk_recent_chooser_get_current_uri = CHAR_PTR,
    gtk_recent_filter_get_name = CONST_CHAR_PTR,
    gtk_recent_info_get_description = CONST_CHAR_PTR,
    gtk_recent_info_get_display_name = CONST_CHAR_PTR,
    gtk_recent_info_get_mime_type = CONST_CHAR_PTR,
    gtk_recent_info_get_short_name = CHAR_PTR,
    gtk_recent_info_get_uri = CONST_CHAR_PTR,
    gtk_recent_info_get_uri_display = CHAR_PTR,
    gtk_recent_info_last_application = CHAR_PTR,

    gtk_print_settings_get = CONST_CHAR_PTR,
    gtk_print_settings_get_default_source = CONST_CHAR_PTR,
    gtk_print_settings_get_dither = CONST_CHAR_PTR,
    gtk_print_settings_get_finishings = CONST_CHAR_PTR,
    gtk_print_settings_get_media_type = CONST_CHAR_PTR,
    gtk_print_settings_get_output_bin = CONST_CHAR_PTR,
    gtk_print_settings_get_printer = CONST_CHAR_PTR,

    gtk_editable_get_chars = CHAR_PTR,
    gtk_entry_completion_get_completion_prefix = CONST_CHAR_PTR,
    gtk_expander_get_label = CONST_CHAR_PTR,

    -- from here on not verified!
    gtk_accelerator_get_label = CHAR_PTR,
    gtk_accelerator_name = CHAR_PTR,
    gtk_action_get_accel_path = CONST_CHAR_PTR,
    gtk_action_get_name = CONST_CHAR_PTR,
    gtk_action_group_get_name = CONST_CHAR_PTR,
    gtk_action_group_translate_string = CONST_CHAR_PTR,
    gtk_assistant_get_page_title = CONST_CHAR_PTR,
    gtk_buildable_get_name = CONST_CHAR_PTR,
    gtk_builder_get_translation_domain = CONST_CHAR_PTR,
    gtk_button_get_label = CONST_CHAR_PTR,
    gtk_check_version = CONST_CHAR_PTR,
    gtk_clipboard_wait_for_text = CHAR_PTR,
    gtk_color_button_get_title = CONST_CHAR_PTR,
    gtk_color_selection_palette_to_string = CHAR_PTR,
    gtk_combo_box_get_title = CONST_CHAR_PTR,
    gtk_file_chooser_button_get_title = CONST_CHAR_PTR,
    gtk_file_filter_get_name = CONST_CHAR_PTR,
    gtk_font_button_get_font_name = CONST_CHAR_PTR,
    gtk_font_button_get_title = CONST_CHAR_PTR,
    gtk_font_selection_dialog_get_font_name = CHAR_PTR,
    gtk_font_selection_dialog_get_preview_text = CONST_CHAR_PTR,
    gtk_font_selection_get_font_name = CHAR_PTR,
    gtk_font_selection_get_preview_text = CONST_CHAR_PTR,
    gtk_frame_get_label = CONST_CHAR_PTR,
    gtk_icon_info_get_display_name = CONST_CHAR_PTR,
    gtk_icon_size_get_name = CONST_CHAR_PTR,
    gtk_icon_source_get_icon_name = CONST_CHAR_PTR,
    gtk_icon_theme_get_example_icon_name = CHAR_PTR,
    gtk_label_get_label = CONST_CHAR_PTR,
    gtk_label_get_text = CONST_CHAR_PTR,
    gtk_link_button_get_uri = CONST_CHAR_PTR,
    gtk_menu_get_title = CONST_CHAR_PTR,
    gtk_notebook_get_menu_label_text = CONST_CHAR_PTR,
    gtk_notebook_get_tab_label_text = CONST_CHAR_PTR,
    gtk_paper_size_get_default = CONST_CHAR_PTR,
    gtk_paper_size_get_display_name = CONST_CHAR_PTR,
    gtk_paper_size_get_name = CONST_CHAR_PTR,
    gtk_paper_size_get_ppd_name = CONST_CHAR_PTR,
    gtk_print_operation_get_status_string = CONST_CHAR_PTR,
    gtk_progress_bar_get_text = CONST_CHAR_PTR,
    gtk_rc_find_module_in_path = CHAR_PTR,
    gtk_rc_find_pixmap_in_path = CHAR_PTR,
    gtk_rc_get_im_module_file = CHAR_PTR,
    gtk_rc_get_im_module_path = CHAR_PTR,
    gtk_rc_get_module_dir = CHAR_PTR,
    gtk_rc_get_theme_dir = CHAR_PTR,
    gtk_recent_chooser_get_current_uri = CHAR_PTR,
    gtk_recent_filter_get_name = CONST_CHAR_PTR,
    gtk_recent_info_get_uri_display = CHAR_PTR,
    gtk_set_locale = CHAR_PTR,
    gtk_status_icon_get_icon_name = CONST_CHAR_PTR,
    gtk_status_icon_get_stock = CONST_CHAR_PTR,

    -- prototypes
    ["GtkBuildableIface.get_name"] = CONST_CHAR_PTR,
    ["GtkContainerClass.composite_name"] = CHAR_PTR,
    ["GtkRecentChooserIface.get_current_uri"] = CHAR_PTR,

    -- verified inconsistency.
    ["gtk_action_group_set_translate_func.func"] = CONST_CHAR_PTR,
    ["gtk_stock_set_translate_func.func"] = CHAR_PTR,

    -- set the object->flag on some return values
    gtk_stock_list_ids = "GSLIST_FREE_GFREE",

}

-- flags that can be used by name in the function_flags table
flag_table = {
    GSLIST_FREE_GFREE	    = 1,
}



-- extra types to include even though they are not used in functions
-- or structures:
include_types = {
    "GtkFileChooserWidget*",
    "GtkFileChooserDialog*",
    "GtkInputDialog*",
    "GtkHBox*",
    "GtkVBox*",
    "GtkDrawingArea*",
    "GtkCheckButton*",
    "GtkVSeparator*",
    "GtkHSeparator*",
    "GtkCellRendererPixbuf*",
    "GtkHPaned*",
    "GtkVPaned*",
    "GtkHScale*",
    "GtkVScale*",

    -- needed for GtkSourceView
    "GtkTextBuffer",

    -- might be useful?
    -- GtkAccelGroup, GtkProgressBar, GtkSpinButton,
    -- GtkRadioButton
}

-- Functions used from the dynamic libraries (GLib, GDK, Gtk)
linklist = {
    "g_malloc",
    "g_object_ref_sink",
    "g_object_unref",
    "g_slice_alloc0",
    "g_type_check_instance_is_a",	-- used!
    "g_type_from_name",
    "g_type_is_a",
    "g_strfreev",
    "g_value_unset",
    "gdk_color_copy",
    "gtk_init",
    "gtk_object_get_type",		-- used!
    "gtk_tree_model_get_value",
    "gtk_major_version",
    "gtk_minor_version",
    "gtk_micro_version",
    "gtk_tree_model_get_column_type",
    "gtk_list_store_set_value",
}

-- extra settings for the module_info structure
module_info = {
    allocate_object = "gtk_allocate_object",
    call_hook = "gtk_call_hook",
    prefix_func = '"gtk_"',
    prefix_constant = '"GTK_"',
    prefix_type = '"Gtk"',
    depends = '"gdk\\0"',
    overrides = 'gtk_overrides',
}

