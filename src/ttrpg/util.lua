--- Small internal helpers shared across modules. Not public API.
local M = {}

--- True for functions and for tables/userdata whose metatable defines __call.
function M.is_callable(value)
    if type(value) == "function" then
        return true
    end
    local mt = getmetatable(value)
    return type(mt) == "table" and type(mt.__call) == "function"
end

return M
