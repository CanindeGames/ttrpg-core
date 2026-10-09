-- Every file in examples/ must run without errors: examples are documentation that AI agents
-- and integrators copy from, so they are tested like code.
local examples = { "examples/custom_system.lua", "examples/external_rolls.lua" }

describe("examples", function()
    for _, path in ipairs(examples) do
        it(path .. " runs", function()
            local chunk = assert(loadfile(path))
            local original_print = print
            _G.print = function() end -- keep test output clean
            local ok, err = pcall(chunk)
            _G.print = original_print
            assert(ok, err)
        end)
    end
end)
