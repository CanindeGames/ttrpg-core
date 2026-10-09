local util = require("ttrpg.util")

describe("ttrpg.util", function()
    describe("is_callable", function()
        it("accepts functions and tables with __call", function()
            assert.is_true(util.is_callable(print))
            assert.is_true(util.is_callable(setmetatable({}, { __call = function() end })))
        end)

        it("rejects everything else", function()
            for _, value in ipairs({ 1, "f", true, {}, setmetatable({}, { __call = 1 }) }) do
                assert.is_false(util.is_callable(value))
            end
            assert.is_false(util.is_callable(nil))
        end)
    end)
end)
