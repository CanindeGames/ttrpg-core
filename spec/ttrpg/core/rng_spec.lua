local RNG = require("ttrpg.core.rng")
local errors = require("ttrpg.errors")

local function draw(rng, n, min, max)
    local out = {}
    for i = 1, n do
        out[i] = rng:random(min, max)
    end
    return out
end

describe("ttrpg.core.rng", function()
    it("produces the same sequence for the same seed", function()
        assert.are.same(draw(RNG.new(42), 50, 1, 20), draw(RNG.new(42), 50, 1, 20))
    end)

    it("produces different sequences for different seeds", function()
        assert.are_not.same(draw(RNG.new(1), 20, 1, 1000), draw(RNG.new(2), 20, 1, 1000))
    end)

    it("matches the Park-Miller reference sequence", function()
        -- With state 1, minimal-standard (48271) yields 48271, then 48271^2 mod (2^31-1).
        local rng = RNG.new(0) -- seed 0 normalizes to state 1
        assert.are.equal(48271, rng:next_raw())
        assert.are.equal(182605794, rng:next_raw())
    end)

    it("accepts negative, fractional and huge seeds", function()
        for _, seed in ipairs({ -1, -123456789, 3.7, 2 ^ 40 }) do
            local value = RNG.new(seed):random(1, 6)
            assert.is_true(value >= 1 and value <= 6)
        end
    end)

    it("stays within [min, max] and covers every value", function()
        local rng = RNG.new(7)
        local seen = {}
        for _ = 1, 2000 do
            local v = rng:random(1, 6)
            assert.is_true(v >= 1 and v <= 6)
            seen[v] = true
        end
        for face = 1, 6 do
            assert.is_true(seen[face], "face " .. face .. " never rolled")
        end
    end)

    it("supports negative ranges and min == max", function()
        local rng = RNG.new(3)
        for _ = 1, 100 do
            local v = rng:random(-5, -1)
            assert.is_true(v >= -5 and v <= -1)
        end
        assert.are.equal(9, rng:random(9, 9))
    end)

    it("is roughly uniform", function()
        local rng = RNG.new(2024)
        local counts = { 0, 0, 0, 0 }
        local n = 40000
        for _ = 1, n do
            local v = rng:random(1, 4)
            counts[v] = counts[v] + 1
        end
        for face = 1, 4 do
            assert.is_true(math.abs(counts[face] / n - 0.25) < 0.02)
        end
    end)

    it("restores a snapshot to replay the same rolls", function()
        local rng = RNG.new(99)
        draw(rng, 5, 1, 20)
        local snapshot = rng:get_state()
        local first = draw(rng, 10, 1, 20)
        rng:set_state(snapshot)
        assert.are.same(first, draw(rng, 10, 1, 20))
    end)

    describe("invalid input", function()
        local function code_of(fn, ...)
            local ok, err = pcall(fn, ...)
            assert.is_false(ok)
            return errors.is(err) and err.code
        end

        it("rejects non-finite or non-numeric seeds", function()
            for _, seed in ipairs({ 0 / 0, math.huge, -math.huge, "42" }) do
                assert.are.equal("INVALID_ARGUMENT", code_of(RNG.new, seed))
            end
        end)

        it("rejects min > max", function()
            local rng = RNG.new(1)
            assert.are.equal("INVALID_ARGUMENT", code_of(rng.random, rng, 6, 1))
        end)

        it("rejects ranges wider than the generator period", function()
            local rng = RNG.new(1)
            assert.are.equal("INVALID_ARGUMENT", code_of(rng.random, rng, 0, 2 ^ 31))
        end)

        it("rejects invalid states", function()
            local rng = RNG.new(1)
            for _, state in ipairs({ 0, -1, 1.5, 2147483647, "x" }) do
                assert.are.equal("INVALID_ARGUMENT", code_of(rng.set_state, rng, state))
            end
        end)
    end)
end)
