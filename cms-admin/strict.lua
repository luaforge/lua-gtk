--
-- strict.lua
-- checks uses of undeclared global variables
-- All global variables must be 'declared' through a regular assignment
-- (even assigning nil will do) in a main chunk before being used
-- anywhere or assigned to inside a function.
--
-- improved by Wolfgang Oertl: accesses that will be satisfied by 
-- a metatable are OK.
--

-- new global variables are only allowed in main and in C functions
local function strict_newindex(t, n, v) 
--  print("+", n)
  local d = getmetatable(t).__declared
  if not d[n] then
    local w = debug.getinfo(2, "S").what
    if w ~= "main" and w ~= "C" then
      error("assign to undeclared variable '"..n.."'", 2)
    end
    d[n] = true
  end
  rawset(t, n, v)
end

-- This function is called when an environment does not contain the
-- requested index.  Typically this should not happen often.
local function strict_index(t, n)
  local mt = getmetatable(t)
  local d = mt.__declared
  if d[n] then return rawget(t, n) end

  -- "n" hasn't been assigned in this environment; try metatable
  if mt.__old_index then
    local v = mt.__old_index[n]
    if v then return v end
  end

  -- not found -> error
    error("variable '"..n.."' is not declared", 2)
end

-- enable strict checking for the calling environment
function strict()

	local env = getfenv(2)
	local mt = getmetatable(env)
	if mt == nil then
		mt = {}
		setmetatable(env, mt)
	end
	if rawget(mt, "__declared") then
		-- print "Strict variable checking is still on!"
		return
	end	

	-- print "Enabling strict variable checking."
	mt.__declared = {}
	mt.__newindex = strict_newindex
	mt.__old_index = mt.__index
	mt.__index = strict_index
end

function strict_locked(t, n, v)
    error("LOCKED - no new globals allowed: " .. n, 2)
end

function strict_lock()
    local env = getfenv(2)
    local mt = getmetatable(env)
    mt.__newindex = strict_locked
end

