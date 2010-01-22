#! /usr/bin/env lua
-- vim:sw=4:sts=4:encoding=utf-8

require "gtk"
require "lfs"

local main		-- contains all the widgets
local proc_dir = "/proc"
local my_uid		-- own UID is stored here
local only_own		-- true if only own processes should be shown
local proclist		-- last read process list
local pagesize = 4

-- If only own processes are to be shown, non-own processes in the path to
-- own processes still have to be shown.  Determine if the process "pid"
-- has any child processes with my_uid.
local function _has_own(proclist, p)
    if p._uid == my_uid then return true end
    for _, p in pairs(proclist[p.pid] or {}) do
	if _has_own(proclist, p) then return true end
    end
end

function on_only_own_toggled(btn)
    insert_proclist()
end

function on_btn_about_clicked()
    main.aboutdialog:run()
end

function on_aboutdialog_response(dlg, result)
    dlg:hide()
end

-- Add all child processes of the given ppid (parent PID) to the given
-- iterator.  For a start, use ppid == 0 and parent_iter = nil.
local function _insert_recursively(proclist, ppid, parent_iter)
    local ar, iter, weight

    ar = proclist[ppid] or {}

    for _, p in ipairs(ar) do
	if (not only_own) or _has_own(proclist, p) then

	    iter = iter or gtk.new "TreeIter"
	    weight = 400
	    if p._uid == my_uid then
		weight = 800
	    end

	    main.procs:append(iter, parent_iter)
	    main.procs:set(iter,
		0, gnome.box(p),
		1, p.name,
		2, tonumber(p.rss),
		3, weight,
		-1)
	    _insert_recursively(proclist, p.pid, iter)
	end
    end

end

function insert_proclist()
    main.procs:clear()
    only_own = main.only_own:get_active()
    _insert_recursively(proclist, 0)
    main.proctree:expand_all()
end

function on_process_select(view)
    local model, sel, iter, p, m, pos, sum

    model = view:get_model()
    sel = view:get_selection()
    iter = gtk.new "TreeIter"
    if not sel:get_selected(model, iter) then
	return
    end

    p = model:get_value(iter, 0)

    -- get current statistics
    update_memory(p)

    -- set the labels
    main.proc_name:set_text(p.name)
    main.proc_rss:set_text(p.rss)
    main.proc_pid:set_text(p.pid)

    -- fill the memory map (if available)
    m = main.memmap
    m:clear()
    pos = 0
    sum = 0
    for _, smap in pairs(p._smaps or {}) do
	m:insert_with_values(nil, pos,
	    0, tostring(smap[1]),
	    1, tonumber(smap[2]),
	    -1)
	pos = pos + 1
	sum = sum + smap[2]
    end

    main.proc_pss:set_text(sum)
end

-- re-read the processes
function on_processlist_refresh()
    read_process_tree()
end

function init_processes()
    my_uid = lfs.attributes(proc_dir .. "/self", "uid")
end

function read_process_tree()
    local d, f, s, p, ar

    proclist = {}
    for name in lfs.dir(proc_dir) do
	if string.match(name, "^%d+$") then
	    d = proc_dir .. "/" .. name .. "/"
	    p = {}
	    p._uid = lfs.attributes(d, "uid")

	    -- read the stat file
	    f = io.open(d .. "stat")
	    s = f:read"*a"
	    f:close()
	    p.pid, p.name, p.status, p.ppid = string.match(s,
		"^(%d+) %((.-)%) (%S) (%d+)")
	    p.pid = tonumber(p.pid)
	    p.ppid = tonumber(p.ppid)
	    if not p.ppid then
		print("Process without ppid?", s, p.name)
	    end

	    -- read other files as well if desired, like
	    -- cmdline, io, statm
	    -- read statm, smaps on demand.
	    -- read /usr/src/linux/Documentation/filesystems/proc.txt
	    f = io.open(d .. "statm")
	    s = f:read"*a"
	    f:close()

	    -- these sizes are in pages, not in kB.
	    p.vmsize, p.rss, p.shared = string.match(s, "^(%d+) (%d+) (%d+)")
	    p.vmsize = p.vmsize * pagesize
	    p.rss = p.rss * pagesize
	    p.shared = p.shared * pagesize
	    ar = proclist[p.ppid] or {}
	    ar[#ar + 1] = p
	    proclist[p.ppid] = ar
	end
    end

    -- now insert all these processes hierarchically.
    insert_proclist()
end

local function smap_sorter(a, b)
    return a[1] < b[1]
end

function update_memory(p)
    local f, begin_addr, end_addr, flags, n, name, k, v, smaps, smaps2

    f = io.open(proc_dir .. "/" .. p.pid .. "/" .. "smaps")
    if not f then return end

    smaps = {}
    while true do
	s = f:read"*l"
	if not s then break end
	begin_addr, end_addr, flags, n = s:match
	    "^(%x+)%-(%x+) (....) %x+ %S+ %d+%s+(.*)$"
	if begin_addr then
	    -- new section
	    name = n
	else
	    k, v = s:match"^(%S+):%s*(%d+)"
	    if k == "Pss" and name then
		smaps[name] = (smaps[name] or 0) + v
	    end
	end
    end
    f:close()

    -- sort
    smaps2 = {}
    for k, v in pairs(smaps) do
	smaps2[#smaps2 + 1] = { k, v }
    end
    table.sort(smaps2, smap_sorter)
    p._smaps = smaps2

end


function build_ui()
    local b, fname, rc, err, main

    b = gtk.builder_new()
    fname = string.gsub(arg[0], "%.lua", ".ui")
    rc, err = b:add_from_file(fname, nil)
    if err then print(err.message); return end
    b:connect_signals_full(_G)

    -- access some widgets
    main = {}
    for _, name in ipairs { "proctree", "memmap", "proc_name", "proc_rss",
	    "proc_pid", "proc_pss", "only_own", "aboutdialog" } do
	main[name] = assert(b:get_object(name))
    end

    -- make the treestore.  It has a "GBoxed" column which can't be
    -- created from Glade, at least I haven't found out how.
    local store = gtk.tree_store_new(4,
	gnome.boxed_type,	-- 0: the table with the data
	glib.TYPE_STRING,	-- 1: name
	glib.TYPE_UINT,		-- 2: size
	glib.TYPE_INT)		-- 3: font weight
    main.proctree:set_model(store)
    main.procs = store

    return main
end

main = build_ui()
init_processes()
read_process_tree()
gtk.main()

