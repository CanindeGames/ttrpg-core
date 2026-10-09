--- Registry of game systems (rulesets) available to an engine instance.
--
-- A system definition is a plain table:
--
--     {
--         id = "my_system",          -- required, ^[a-z][a-z0-9_-]*$
--         name = "My System",        -- required
--         version = "1.0.0",         -- required
--         license = {                -- optional for homebrew; mandatory for bundled
--             name = "CC-BY-4.0",    -- third-party content (SRD/ORC attribution)
--             attribution = "...",
--         },
--         setup = function(engine, system) end, -- optional, called once on registration
--     }
--
-- Built-in systems (D&D 5e SRD, Pathfinder ORC, ...) must go through this same public
-- path; there is no privileged registration API.
local errors = require("ttrpg.errors")
local util = require("ttrpg.util")

local Registry = {}
Registry.__index = Registry

local function invalid(message, details)
    errors.raise(errors.codes.INVALID_ARGUMENT, message, details)
end

local function validate(def)
    if type(def) ~= "table" then
        invalid("system definition must be a table")
    end
    if type(def.id) ~= "string" or not def.id:find("^[a-z][a-z0-9_%-]*$") then
        invalid("system id must match ^[a-z][a-z0-9_-]*$", { id = def.id })
    end
    for _, field in ipairs({ "name", "version" }) do
        if type(def[field]) ~= "string" or def[field] == "" then
            invalid("system '" .. def.id .. "' requires a non-empty string '" .. field .. "'", {
                id = def.id,
                field = field,
            })
        end
    end
    if def.license ~= nil then
        if type(def.license) ~= "table" or type(def.license.name) ~= "string" then
            invalid("system license must be a table with a string 'name'", { id = def.id })
        end
    end
    if def.setup ~= nil and not util.is_callable(def.setup) then
        invalid("system setup must be callable", { id = def.id })
    end
end

function Registry.new()
    return setmetatable({ systems = {} }, Registry)
end

--- Validates and stores a system definition. Raises ALREADY_EXISTS on duplicate ids.
function Registry:register(def)
    validate(def)
    if self.systems[def.id] then
        errors.raise(errors.codes.ALREADY_EXISTS, "system already registered: " .. def.id, {
            id = def.id,
        })
    end
    self.systems[def.id] = def
    return def
end

function Registry:has(id)
    return self.systems[id] ~= nil
end

--- Returns the system with `id`. Raises NOT_FOUND if absent.
function Registry:get(id)
    local def = self.systems[id]
    if not def then
        errors.raise(errors.codes.NOT_FOUND, "unknown system: " .. tostring(id), { id = id })
    end
    return def
end

--- Sorted list of registered system ids.
function Registry:list()
    local ids = {}
    for id in pairs(self.systems) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

return Registry
