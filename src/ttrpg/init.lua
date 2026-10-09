--- Public entry point: `local ttrpg = require("ttrpg")`.
--
--     local engine = ttrpg.new({ seed = 42 })
--     local result = engine:roll("1d20+5")
--     print(result.total)
--
-- Everything reachable from this table is public API. Modules not exposed here are
-- internal and may change without notice.
local Engine = require("ttrpg.engine")

local ttrpg = {
    _VERSION = require("ttrpg.version"),
    errors = require("ttrpg.errors"),
    dice = require("ttrpg.core.dice"),
    RNG = require("ttrpg.core.rng"),
    Engine = Engine,
}

--- Shorthand for ttrpg.Engine.new(options).
function ttrpg.new(options)
    return Engine.new(options)
end

return ttrpg
