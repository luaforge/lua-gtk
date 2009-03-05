-- vim:sw=4:sts=4
-- This file specifies the menu structure of the generated, static
-- documentation pages.
--
-- Format of an entry: { "basename", "Title", { subentry1, ... } }
--

menu = {
    { "index", "Home" },
    { "examples", "Examples", {
	{ "ex_request", "HTTP Request" },
	{ "ex_pixmap", "Pixmap" },
	{ "ex_iconview", "Iconview" },
	{ "ex_weather", "Weather Update" },
	{ "ex_raedic", "Dictionary Lookup" },
    } },
    { "installation", "Installation" },
    { "reference", "Reference", {
	{ "gnome", "Gnome functions" },
	{ "call", "Function calls" },
	{ "closure", "Closures" },
	{ "objects", "Objects" },
	{ "vararg", "Variable Argument List" },
	{ "boxed", "Boxed Values" },
	{ "voidptr", "Void Pointer Handling" },
	{ "debug", "Debugging Tools" },
	{ "migration", "Migration Guide to 1.0" },
	{ "architecture", "Internal Architecture", {
	    { "modularization", "Modularization" },
	    { "hashtables", "Hash Tables" },
	    { "datatypes", "Data Types" },
	    { "constants", "Constants" },
	    { "variables", "Variables in Gnome" },
	} },
	{ "pitfalls", "Pitfalls" },
	{ "messages", "Message List", {
	    { "messages-gnome", "Gnome" },
	} },
    } },
    { "docgen", "About this document", {
	{ "docmenu", "Menu Definition" },
	{ "docinput", "Input Files" },
    } },
}

