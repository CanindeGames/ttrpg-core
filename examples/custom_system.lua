--- Example: plugging a homebrew system into the engine.
--
-- Run from the repo root:  luajit examples/custom_system.lua
-- (spec/examples_spec.lua runs every example, so examples can't silently rot.)
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local ttrpg = require("ttrpg")

local engine = ttrpg.new({ seed = 42 })

engine:register_system({
    id = "two_d6",
    name = "Simple 2d6",
    version = "0.1.0",
    setup = function(eng, system)
        -- A real system would register rules, attributes, conditions, etc. here.
        system.check = function(modifier, difficulty)
            local result = eng:roll("2d6+" .. modifier)
            return result.total >= difficulty, result
        end
    end,
})

local system = engine:get_system("two_d6")
local success, result = system.check(2, 8)
print(string.format("2d6+2 vs 8 -> %d (%s)", result.total, success and "success" or "failure"))

return { success = success, total = result.total }
