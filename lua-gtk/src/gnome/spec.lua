-- vim:sw=4:sts=4

-- The core library uses glib and gobject, but doesn't provide any bindings
-- for them, which is handled by the "glib" module.  To avoid duplicating
-- the spec file, include it here.
include_spec"glib"

-- Another set of functions is used, though.  Therefore redefine this array.
linklist = {
    -- implicitly used in callback.c:_callback in the macro G_VALUE_COLLECT
    { "g_assertion_message", "glib >= '2.15'" },
    "g_boxed_type_register_static",
    "g_enum_get_value",
    "g_flags_get_first_value",
    "g_free",
    "g_malloc",
    "g_strdup",
    "g_mem_gc_friendly",
    "g_mem_profile",
    "g_mem_set_vtable",
    "g_object_is_floating",	    -- in object.c
    "g_object_ref_sink",
    "g_realloc",
    "g_slice_alloc",
    "g_slice_alloc0",
    "g_slice_free1",
    "g_slice_set_config",
    "g_type_check_value",	    -- used.
    "g_type_class_peek",
    "g_type_class_ref",
    "g_type_class_unref",
    "g_type_from_name",
    "g_type_fundamental",	    -- used.
    "g_type_init",
    "g_type_interface_peek",	    -- used.
    "g_type_interfaces",
    "g_type_is_a",
    "g_type_name",
    "g_type_parent",
    "g_value_init",
    "g_value_unset",
    "g_log_set_default_handler",
    "glib_mem_profiler_table",
}

