-- vim:sw=4:sts=4
--

local base, print, table, string, pairs, tonumber, pcall, type =
        _G, print, table, string, pairs, tonumber, pcall, type

require "gtk"
require "gtk.strict"

---
-- Read and interpret Glade-2/3 XML files and create the widgets.
--
-- It constructs widgets automatically, and autoconnects the signals.
-- NOTE.  Starting with Gtk 2.12, you can alternatively use the GtkBuilder
-- class, which is built-in into Gtk.
--
-- Interface functions:
--
--   read(filename)
--	Read the Glade XML file, parse and return the parse tree.
--
--   create(tree, widgetname)
--      Use the parse tree to find the given widget, then create it and all
--      child widgets.  Returns a table with all the created widgets.
--
-- EXAMPLE
--
--   require "gtk"
--   require "gtk.glade"

--   tree = gtk.glade.read("foo.glade")
--   widgets = gtk.glade.create(tree, "top_level_window_name")
--   gtk.main()
--
-- Copyright (C) 2007 Wolfgang Oertl
--

module "gtk.glade"
base.gtk.strict.init()

gtk = base.gtk
glib = base.glib
gdk = base.gdk

if gtk.check_version(2, 12, 0) == nil then
    print "Warning: consider using GtkBuilder for Gtk 2.12 and later."
end

-- if this were used, the garbage collector could remove the widgets.
-- base.setmetatable(widgets, {__mode="v"})

--*------------------------------------------------------------------------
-- Glade functions --------------------------------------------------------
--*------------------------------------------------------------------------

---
-- Debugging: recursively print a structure
--
function print_r(obj, prefix)
    prefix = prefix or ""
    if base.type(obj) ~= "table" then
	print("* print_r: argument is a " .. base.type(obj))
	return
    end
    for k, v in pairs(obj) do
	if base.type(v) == "table" then
	    print(prefix .. k .. " = (")
	    print_r(v, prefix .. " ")
	    print(prefix .. ")")
	else
	    print(prefix .. k .. " = " .. base.tostring(v))
	end
    end
end

-- type conversion functions for some properties are required.
child_property_type_conversion = {
    position = tonumber,
    padding = tonumber,
    x_padding = tonumber,
    y_padding = tonumber,
    top_attach = tonumber,
    bottom_attach = tonumber,
    right_attach = tonumber,
    left_attach = tonumber,
}

--
-- Attach/add etc. functions that handle the packing information from the XML
-- file, or other special situations.
--
function gtk.gtk_container_add_glade(container, child, el)
    local conv

    container:add(child)
    if el.packing then
	for k, v in pairs(el.packing) do
	    conv = child_property_type_conversion[k]
	    if conv then v = conv(v) end
	    container:child_set_property(child, k, v)
	end
    end
end

function gtk.gtk_notebook_add_glade(notebook, child, el)
    local n, page

    if el.packing and el.packing.type == "tab" then
	n = notebook:get_n_pages()
	page = notebook:get_nth_page(n-1)
	return notebook:set_tab_label(page, child)
    else
	return gtk.gtk_container_add_glade(notebook, child, el)
    end
end

--
-- Glade stores the x/y options as text, in lowercase, separated by "|".
-- The default seems to be GTK_FILL | GTK_EXPAND.
--
local function parse_xy_options(s)
    local res, v = 0

    if not s then return gtk.FILL + gtk.EXPAND end

    for v in string.gmatch(s, "([A-Z_]+)") do
	if v:sub(1, 4) == "GTK_" then
	    v = v:sub(5)
	    res = res + gtk[string.upper(v)]
	elseif v:sub(1, 4) == "GDK_" then
	    v = v:sub(5)
	    res = res + gdk[string.upper(v)]
	else
	    -- default is in gtk
	    res = res + gtk[string.upper(v)]
	end
    end

    return res
end

function gtk.gtk_table_add_glade(tbl, child, el)
    local p = el.packing
    if p then
	p.x_options = parse_xy_options(p.x_options)
	p.y_options = parse_xy_options(p.y_options)
    end
    return gtk.gtk_container_add_glade(tbl, child, el)
end

--
-- Adding a GtkMenu to a GtkMenuItem has a special call.
--
function gtk.gtk_menu_item_add_glade(menuitem, menu, el)
    if el.class == 'GtkMenu' then
	menuitem:set_submenu(menu)
    else
	gtk.gtk_container_add_glade(menuitem, menu, el)
    end
end

local function parseargs(arg, s)
    string.gsub(s, "(%w+)=([\"'])(.-)%2", function (w, _, a)
	if arg[w] then base.error("redefinition of " .. w) end
	arg[w] = a
    end)
end


---
-- Parse one line of the glade file
--
function glade_line(stack, line)
    local ni, i, j, c, label, xarg, empty, text
    local top = stack[#stack]

    i = 1
    j = 1
    while true do
	-- start, end, optional "/", tag name, args, optional "/"
	ni, j, c, label, xarg, empty = string.find(line,
	    "<(%/?)([%w_-]+)(.-)(%/?)>", j)
	if not ni then break end

	text = string.sub(line, i, ni-1)
	if not string.find(text, "^%s*$") then
	  --   if top.text then
	-- 	print("WARNING: lost some text")
	    -- end
	    -- top.text = text
	    top.text = (top.text or "") .. text
	end

	if empty == "/" then	    -- empty tag
	    local el = {label=label, empty=1}
	    parseargs(el, xarg)
	    if not top.items then top.items = {} end
	    table.insert(top.items, el)
	elseif c == "" then	    -- start tag
	    top = {label=label}
	    parseargs(top, xarg)
	    table.insert(stack, top)
	else		    	    -- end tag
	    local toclose = table.remove(stack)
	    if not toclose then
		base.error("nothing to close with " .. label)
	    end
	    if toclose.label ~= label then
		base.error("trying to close " .. toclose.label .. " with "
		    .. label)
	    end
	    top = stack[#stack]
	    if not top.items then top.items = {} end
	    table.insert(top.items, toclose)
	end

	i = j + 1
    end

    -- anything unparsed left on this line? Only case when this happens (afaik) is
    -- in the Items property of a GtkComboBox.
    if i < #line then
	top.text = (top.text or "") .. string.sub(line, i) .. "\n"
    end
end

local function glade_transform_packing(items)
    local packing, k, v, n = {}

    for k, v in pairs(items) do
	if v.label ~= "property" then
	    print("expected a property in packing, found:")
	    print(v)
	    print_r(v)
	    base.error("END")
	end

	-- may be nil
	n = v.text
	if n == "True" then n = true elseif n == "False" then n = false
	    elseif n == nil then n = "" end
	packing[v.name] = n
    end

    return packing
end

--
-- Look at the XML tree for one child.  Returns the child widget description,
-- or nil if it is just a placeholder.
--
local function glade_transform_child(child)
    local widget, packing, k, v

    for k, v in pairs(child) do
	-- print("child", k, v)
	if v.label == "widget" then
	    widget = glade_transform_widget(v)
	elseif v.label == "packing" then
	    packing = glade_transform_packing(v.items)
	elseif v.label == "placeholder" then
--	    widget = { class="GtkLabel", p={visible=true, label="Placeholder"},
--		id="" }
	else
	    base.error("invalid element '" .. v.label .. "' in child")
	end
    end

    if widget and packing then widget.packing = packing end
    return widget
end

--
-- Get the information of one widget.  It has following attributes:
--  id
--  class
--  properties (p)
--  children
--  packing
--
function glade_transform_widget(item)
    local widget, j, item2, subwidget

    -- print(item.id)

    if item.label ~= "widget" then
	base.error("expected widget")
    end

    widget = { class=item.class, p = {}, id=item.id }

    -- widget may not have subitems after all.
    if not item.items then return widget end

    for j, item2 in pairs(item.items) do
	if item2.label == "property" then
	    local v = item2.text
	    if v == "True" then v = true elseif v == "False" then v = false end
	    widget.p[item2.name] = v
	    for k, v in pairs(item2) do
		if k ~= "label" and k ~= "name" and k ~= "text" and
		    k ~= "translatable" and k ~= "comments" then
		    print("WARNING: lost attribute " .. k)
		end
	    end
	elseif item2.label == "child" then
	    subwidget = glade_transform_child(item2.items)
	    if subwidget then
		if not widget.children then
		    widget.children = {}
		    widget.childidx = {}
		end
		table.insert(widget.children, subwidget)
		widget.childidx[subwidget.id] = #widget.children
	    end
	elseif item2.label == "signal" then
	    if not widget.signals then widget.signals = {} end
	    table.insert(widget.signals, item2)
	else
	    base.error("Unknown attribute " .. item2.label .. " of widget "
		.. item.id)
	end
    end

    return widget
end

--
-- Analyze the xml parse tree and extract the glade specific information.  This
-- creates one new table per widget.
--
local function transform(xml)
    if xml[1].label ~= "glade-interface" then
	base.error("glade.transform: top level XML item must be glade-interface.")
    end

    local tree = {}
    for i, item in pairs(xml[1].items) do
	local widget = glade_transform_widget(item)
	tree[item.id] = widget
    end

    return tree
end



---
-- Parse a Glade XML file; return the resulting tree.
--
-- This is based on Roberto Ierusalimschy's XML parser as found on
-- http://lua-users.org/wiki/LuaXml. <br/>
--
-- Types of XML elements:
--  glade-interface	top level wrapper
--  widget		widget with class, id
--  property		some property with name and value
--  child		wrapper for widget + packing
--  packing		sets the packing options
--
function read(fname)
    local stack, line_nr = {}, 0
    local f = base.io.open(fname)

    if not f then
	print("Can't open input file", fname)
	return
    end

    f:read()	-- <?xml line
    f:read()	-- <!DOCTYPE line

    table.insert(stack, {items={}})
    for line in f:lines() do
	line_nr = line_nr + 1
	local ok, msg = base.pcall(glade_line, stack, line)
	if not ok then
	    print(string.format("%s(%d): %s", fname, line_nr, msg))
	end
    end

    return transform(stack[1].items)
end


--
-- Constructors for all the widgets that need special handling.  They return
-- the resulting widget and a table with keys == the properties that should not
-- be set.
--
function GtkWindow(el)
    local t = el.p.type or "WINDOW_TOPLEVEL"
    t = string.gsub(t, "^GTK_", "")
    return gtk.window_new(gtk[t]), { type=1 }
end

--
-- GtkMenuItem with automatically created GtkLabel as child.
-- label and use_underline...
--
function GtkMenuItem(el)
    local w

    __type_nr = glib.type_from_name(el.class)
    w = glib.object_newv(__type_nr, 0, nil)
    if el.p.label then
	local lbl = gtk.label_new(el.p.label)
	lbl:set_property("use-underline", el.p.use_underline)
	lbl:show()
	w:add(lbl)
    end
    return w, { label=1, use_underline=1 }
end

function GtkImageMenuItem(el)
    local w

    if el.p.use_stock then
	w = gtk.image_menu_item_new_from_stock(el.p.label, nil)
    else
	w = gtk.image_menu_item_new_with_label(el.p.label)
    end

    return w, { label=1, use_stock=1, use_underline=1 }
end

--
-- Optionally create a Text Combo Box and will with predefined items.
--
function GtkComboBox(el)
    local w

    if not el.p.items then
	return gtk.combo_box_new(), {}
    end

    w = gtk.combo_box_new_text()
    for s in string.gmatch(el.p.items, "([^\n]+)") do
	w:append_text(s)
    end

    return w, { items=1 }
end

--
-- Optionally create a Text Combo Box and will with predefined items.
--
function GtkComboBoxEntry(el)
    local w

    if not el.p.items then
	return gtk.combo_box_entry_new(), {}
    end

    w = gtk.combo_box_entry_new_text()
    for s in string.gmatch(el.p.items, "([^\n]+)") do
	w:append_text(s)
    end

    return w, { items=1 }
end

--
-- GtkButton with unknown property
--
function GtkButton(el)
    local w = gtk.button_new()
    return w, { response_id=1 }
end

property_setter = {
    adjustment = function(w, k, s)
	local a = gtk.adjustment_new(string.match(s,
	    "(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)"))
	w:set_property(k, a)
    end,

    position = function(w, k, s)
	w:set_property(s, tonumber(s))
    end,

    default = function(w, k, s)
	w:set_property(k, s)
    end,
}

-- globals (sort of) used in make_widget to reduce stack size need to be
-- declared to make gtk.strict happy.
__type_nr = 0
__handler = 0


--
-- Given a subtree of the Glade tree, create all widgets in it.
--
-- @param widgets  List of widgets (all of them)
-- @param el       child_info
-- @param parent   (optional) add new widgets to this parent
-- @return         The created widget, and inserts all created widgets into the
--                 table "widgets".
--
function make_widget(widgets, el, parent, scope)
    local w, child, ignore_prop, ok
    local scope = scope or base

    -- special handler?
    local handler = base.rawget(_M, el.class)
    if handler then
	w, ignore_prop = handler(el)
    elseif el.class == 'Custom' then
	ok, w = pcall(scope[el.p.creation_function],
                      el.p.string1, el.p.string2)
        if not ok then return nil end
	ignore_prop = {creation_function=true,string1=true,string2=true}
    else
	-- generic handler.  use a global here, to reduce stack size
	__type_nr = glib.type_from_name(el.class)
	w = glib.object_newv(__type_nr, 0, nil)
	ignore_prop = {}
    end

    -- store the widget by ID in the widgets table.
    -- gtk.luagtk_register_widget(w)
    widgets[el.id] = w

    -- hack -- have to set can_default before has_default.  also, has to be
    -- added to parent first
    if parent then
	parent:add_glade(w, el)
    end

    if el.p.can_default ~= nil then
	w:set_property("can_default", el.p.can_default)
    end

    -- set all properties except for some.
    for k, v in pairs(el.p) do
	if k ~= "visible" and not ignore_prop[k] then
	    (property_setter[k] or property_setter.default)(w, k, v)
	end
    end

    -- create children, if any, and add them to this widget
    if el.children then
	for i, child_info in pairs(el.children) do
	    child = make_widget(widgets, child_info, w, scope)
	end
    end

    -- If it has signal handlers, try to connect them.
    -- use a global (__handler) to reduce stack size.
    if el.signals then
	for k, v in pairs(el.signals) do
	    __handler = scope[v.handler]

	    -- Ok, couldn't find it. But let's try dots before gtk crashes us.
	    if not __handler then
		local it = scope
		for k in v.handler:gmatch('[.]?([^.]+)') do
		    if not it then break end; it=it[k];
		end
                if type(it) == 'function' then __handler = it end
	    end

	    __handler = __handler or gtk[v.handler]
	    if not __handler then
		print(string.format("no handler for signal %s:%s - %s",
		    el.id, v.name, v.handler))
	    else
		w:connect(v.name, __handler, v.object
		    and (widgets[v.object] or scope[v.object] or v.object))
	    end
	end
    end

    if el.p.visible then w:show() end

    return w
end

---
-- Attempt to create a widget tree.
--
-- Use the parse tree to find the given widget, then create it and all child
-- widgets.
--
-- @param tree   The widget tree as returned from read.
-- @param path   Name of the top widget, typically "window1" or similar.
-- @param scope  The scope in which to search for callbacks, etc.
-- @return       A table with all the widgets; key=name, value=widget.
--
function create(tree, path, scope)
    local w, w2
    local widgets = {}

    w = tree[path]
    if not w then
	base.error("Widget " .. w .. " is not defined")
    end

    -- Disable output buffering for stdout; else, on SEGV, not all output
    -- is displayed.
    base.io.stdout:setvbuf("no")
    make_widget(widgets, w, nil, scope)
    return widgets
end

gtk.strict.lock()

