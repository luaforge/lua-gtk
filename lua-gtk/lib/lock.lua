
local base = _G
module "lock"

-- lock the module
local function _lock(t, k, v)
    base.error("module has been locked, declare this as local: " .. k, 2)
end

function lock(t)
    local mt = base.getmetatable(t) or {}
    mt.__newindex = _lock
    base.setmetatable(t, mt)
end

