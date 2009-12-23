-- vim:sw=4:sts=4

name = "Atk"
pkg_config_name = "atk"

libraries = {}
libraries.linux = { "/usr/lib/libatk-1.0.so.0" }
libraries.win32 = { "libatk-1.0-0.dll" }

include_dirs = { "atk-1.0" }

includes = {}
includes.all = {
    "<atk/atk.h>",
    "<atk/atk-enum-types.h>",
}

include_types = {
    "AtkAttribute*",
    "AtkNoOpObject*",
    "AtkNoOpObjectFactory*",
    "AtkImplementorIface*",
}

function_flags = {
    -- not verified!
    atk_action_get_description = CONST_CHAR_PTR,
    atk_action_get_keybinding = CONST_CHAR_PTR,
    atk_action_get_localized_name = CONST_CHAR_PTR,
    atk_action_get_name = CONST_CHAR_PTR,
    atk_document_get_attribute_value = CONST_CHAR_PTR,
    atk_document_get_document_type = CONST_CHAR_PTR,
    atk_document_get_locale = CONST_CHAR_PTR,
    atk_get_toolkit_name = CONST_CHAR_PTR,
    atk_get_toolkit_version = CONST_CHAR_PTR,
    atk_get_version = CONST_CHAR_PTR,
    atk_hyperlink_get_uri = CHAR_PTR,
    atk_image_get_image_description = CONST_CHAR_PTR,
    atk_image_get_image_locale = CONST_CHAR_PTR,
    atk_object_get_description = CONST_CHAR_PTR,
    atk_object_get_name = CONST_CHAR_PTR,
    atk_relation_type_get_name = CONST_CHAR_PTR,
    atk_role_get_localized_name = CONST_CHAR_PTR,
    atk_role_get_name = CONST_CHAR_PTR,
    atk_state_type_get_name = CONST_CHAR_PTR,
    atk_streamable_content_get_mime_type = CONST_CHAR_PTR,
    atk_streamable_content_get_uri = CHAR_PTR,
    atk_table_get_column_description = CONST_CHAR_PTR,
    atk_table_get_row_description = CONST_CHAR_PTR,
    atk_text_attribute_get_name = CONST_CHAR_PTR,
    atk_text_attribute_get_value = CONST_CHAR_PTR,
    atk_text_get_selection = CHAR_PTR,
    atk_text_get_text = CHAR_PTR,
    atk_text_get_text_after_offset = CHAR_PTR,
    atk_text_get_text_at_offset = CHAR_PTR,
    atk_text_get_text_before_offset = CHAR_PTR,

-- Function prototypes

    ["AtkActionIface.get_description"] = CONST_CHAR_PTR,
    ["AtkDocumentIface.get_document_type"] = CONST_CHAR_PTR,
    ["AtkDocumentIface.get_document_attribute_value"] = CONST_CHAR_PTR,
    ["AtkImageIface.get_image_description"] = CONST_CHAR_PTR,
    ["AtkStreamableContentIface.get_mime_type"] = CONST_CHAR_PTR,
    ["AtkStreamableContentIface.get_uri"] = CONST_CHAR_PTR,
    ["AtkTableIface.get_column_description"] = CONST_CHAR_PTR,

-- AtkTextIface.* verified
    ["AtkTextIface.get_text"] = CHAR_PTR,
    ["AtkTextIface.get_text_after_offset"] = CHAR_PTR,
    ["AtkTextIface.get_selection"] = CHAR_PTR,

    ["AtkActionIface.get_name"] = CONST_CHAR_PTR,
    ["AtkActionIface.get_keybinding"] = CONST_CHAR_PTR,
    ["AtkActionIface.get_localized_name"] = CONST_CHAR_PTR,
    ["AtkDocumentIface.get_document_locale"] = CONST_CHAR_PTR,
    ["AtkImageIface.get_image_locale"] = CONST_CHAR_PTR,
    ["AtkTableIface.get_row_description"] = CONST_CHAR_PTR,
    ["AtkTextIface.get_text_at_offset"] = CHAR_PTR,
    ["AtkTextIface.get_text_before_offset"] = CHAR_PTR,
}

-- extra settings for the module_info structure
module_info = {
    prefix_func = '"atk_"',
    prefix_constant = '"ATK_"',
    prefix_type = '"Atk"',
    depends = '""',
}

