--- Structured errors.
--
-- Every error the engine raises is a table with a stable, machine-readable `code`, a
-- human-readable `message` and an optional `details` table. Hosts (and AI agents) should
-- branch on `code`, never on `message` text.
--
--     local ok, err = pcall(engine.roll, engine, "2d")
--     if not ok and errors.is(err, errors.codes.PARSE_ERROR) then ... end
local M = {}

M.codes = {
    INVALID_ARGUMENT = "INVALID_ARGUMENT",
    PARSE_ERROR = "PARSE_ERROR",
    NOT_FOUND = "NOT_FOUND",
    ALREADY_EXISTS = "ALREADY_EXISTS",
    -- External input was needed outside engine:run(), so there is no task to suspend.
    INPUT_REQUIRED = "INPUT_REQUIRED",
    -- An operation is not valid in the current state (e.g. a stray coroutine.yield).
    INVALID_STATE = "INVALID_STATE",
    INTERNAL = "INTERNAL",
}

local Error = {}
Error.__index = Error

function Error.__tostring(e)
    return string.format("[%s] %s", e.code, e.message)
end

--- Builds an error object without raising it.
function M.new(code, message, details)
    assert(M.codes[code], "unknown error code: " .. tostring(code))
    return setmetatable({ code = code, message = message, details = details }, Error)
end

--- Raises a structured error.
function M.raise(code, message, details)
    error(M.new(code, message, details))
end

--- True if `value` is an engine error (optionally, with the given code).
function M.is(value, code)
    return getmetatable(value) == Error and (code == nil or value.code == code)
end

--- Calls `fn(...)` in protected mode. Returns `true, result` or `false, err`, where `err`
-- is always a structured error (foreign errors are wrapped as INTERNAL).
function M.try(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return true, result
    end
    if M.is(result) then
        return false, result
    end
    return false, M.new(M.codes.INTERNAL, tostring(result))
end

return M
