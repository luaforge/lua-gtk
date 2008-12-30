-- vim:sw=4:sts=4
--
-- List of fundamental data types supported by this library.
--


---
-- For each fundamental type, give the FFI type to use when building
-- the parameter list, and a numerical type for handling the types in
-- a switch statement.
--
-- key = type name as it appears in types.xml
-- data = { ffi_type, { handlers, handlers_ptr, handlers_ptr_ptr, ... } }
--
--  handlers, handlers_ptr etc.: for each level of indirection the handlers
--  to use; both are optional and may be missing or nil.
--	{ lua2ffi/ffi2lua, lua2struct/struct2lua }
--
fundamental_map = {
    -- Note: ffi_type for vararg is "void".  This is not exactly true, as
    -- a vararg will be replaced by zero or more arguments of variable type in
    -- an actual function call.  types.c:lua2ffi_vararg will replace it anyway
    -- so it could be anything, but it can't be nil, because then
    -- call.c:_call_build_parameters would complain about using a type with
    -- undefined ffi_type.
    ["vararg"] = { "void", { "vararg", nil } },

    ["void"] = { "void",
	{ "void", nil },
	{ "void_ptr", "void_ptr" },
    },

    ["enum"] = { "uint",
	{ "enum", "enum" },
	{ "enum_ptr" },
	{ "enum_ptr_ptr" },
    },

    ["struct"] = { "pointer",
    	{ nil, "struct" },	-- for globals XXX may be wrong
	{ "struct_ptr", "struct_ptr" },
	{ "struct_ptr_ptr" },
	{ "ptr" },
    },
	    
    ["union"] = { "pointer",
	{ nil, "struct" },
	{ "struct_ptr", "struct_ptr" },
	{ "struct_ptr_ptr" },
    },

    ["char"] = { "schar",
	{ },
	{ "char_ptr", "char_ptr" },
	{ "char_ptr_ptr" },
    },

    ["short unsigned int"] = { "ushort", { "long", "long" } },

    ["short int"] = { "sshort", { "long", "long" } },

    ["unsigned char"] = { "uchar",
	{ "uchar" },
	{ "char_ptr", "char_ptr" },
	{ "ptr" },
    },

    ["signed char"] = { "schar", { }, { "ptr" } },

    ["long long unsigned int"] = { "uint64",
	{ "longlong" },
	{ "ptr" },
    },

    ["long unsigned int"] = { "ulong",
	{ "long", "long" },
	{ "long_unsigned_int_ptr" },
	{ "ptr" },
    },

    ["long long int"] = { "sint64", { "longlong" } },

    ["long int"] = { "slong", { "long", "long" } },

    ["int"] = { "sint",
	{ "long", "long" },
	{ "int_ptr" },
	{ "ptr" },
    },

    ["unsigned int"] = { "uint", { "long", "long" },
	{ "unsigned_int_ptr" },
	{ "ptr" },
    },

    ["long double"] = { "double", { "double" } },

    ["double"] = { "double",
	{ "double", "double" },
	{ "double_ptr" },
    },

    ["float"] = { "float", { "float" } },

    ["boolean"] = { "uint", { "bool" }, { "bool_ptr" } },

    ["func"] = { "void",
	{ },
	{ "func_ptr", "func_ptr" },
    },

    ["wchar_t"] = { nil, {}, { "ptr" }, { "ptr" }, { "ptr" } }
}

