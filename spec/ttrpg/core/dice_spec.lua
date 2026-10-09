local dice = require("ttrpg.core.dice")
local RNG = require("ttrpg.core.rng")
local SequenceRNG = require("support.sequence_rng")

local function parse_error(notation)
    local ok, err = pcall(dice.parse, notation)
    assert.is_false(ok, "expected parse error for " .. tostring(notation))
    return err
end

describe("ttrpg.core.dice", function()
    describe("parse", function()
        it("parses a single die with implicit count", function()
            local expr = dice.parse("d20")
            assert.are.same({
                { kind = "dice", count = 1, sides = 20, sign = 1 },
            }, expr.terms)
            assert.are.equal("d20", expr.notation)
        end)

        it("parses mixed dice and constants with signs", function()
            local expr = dice.parse("2d6 + 1d4 - 3")
            assert.are.same({
                { kind = "dice", count = 2, sides = 6, sign = 1 },
                { kind = "dice", count = 1, sides = 4, sign = 1 },
                { kind = "constant", value = 3, sign = -1 },
            }, expr.terms)
        end)

        it("accepts a leading sign and is case insensitive", function()
            local expr = dice.parse("-1D6+2")
            assert.are.equal(-1, expr.terms[1].sign)
            assert.are.equal(6, expr.terms[1].sides)
        end)

        it("parses d% as d100", function()
            assert.are.equal(100, dice.parse("d%").terms[1].sides)
        end)

        it("parses keep highest / lowest", function()
            assert.are.same({ mode = "highest", count = 3 }, dice.parse("4d6kh3").terms[1].keep)
            assert.are.same({ mode = "lowest", count = 1 }, dice.parse("2d20kl").terms[1].keep)
        end)

        it("parses a constant-only expression", function()
            assert.are.same({ { kind = "constant", value = 7, sign = 1 } }, dice.parse("7").terms)
        end)

        local invalid = {
            "",
            "   ",
            "2d",
            "d",
            "abc",
            "1d20+",
            "1d20++2",
            "2d6x",
            "0d6",
            "1d0",
            "2d6kh3",
            "2d6kh0",
            "1001d6",
            "1d10001",
        }
        for _, notation in ipairs(invalid) do
            it("rejects '" .. notation .. "' with PARSE_ERROR", function()
                local err = parse_error(notation)
                assert.are.equal("PARSE_ERROR", err.code)
                assert.are.equal(notation, err.details.notation)
                assert.is_number(err.details.position)
            end)
        end

        it("rejects non-string input with INVALID_ARGUMENT", function()
            assert.are.equal("INVALID_ARGUMENT", parse_error(20).code)
            assert.are.equal("INVALID_ARGUMENT", parse_error(nil).code)
        end)
    end)

    describe("roll", function()
        it("sums dice and constants using the given rng", function()
            local rng = SequenceRNG.new({ 3, 5, 2 })
            local result = dice.roll("2d6 + 1d4 - 1", rng)
            assert.are.equal(3 + 5 + 2 - 1, result.total)
            assert.are.same({ 3, 5 }, result.terms[1].rolls)
            assert.are.same({ 2 }, result.terms[2].rolls)
            assert.are.equal(1, result.terms[3].value)
            assert.are.same(
                { { min = 1, max = 6 }, { min = 1, max = 6 }, { min = 1, max = 4 } },
                rng.calls
            )
        end)

        it("subtracts negative dice terms", function()
            local result = dice.roll("10 - 1d6", SequenceRNG.new({ 4 }))
            assert.are.equal(6, result.total)
        end)

        it("keeps the highest dice", function()
            local result = dice.roll("4d6kh3", SequenceRNG.new({ 2, 6, 1, 4 }))
            assert.are.equal(12, result.total)
            assert.are.same({ 2, 6, 1, 4 }, result.terms[1].rolls)
            assert.are.same({ true, true, false, true }, result.terms[1].kept)
        end)

        it("keeps the lowest dice (disadvantage)", function()
            local result = dice.roll("2d20kl1", SequenceRNG.new({ 17, 4 }))
            assert.are.equal(4, result.total)
            assert.are.same({ false, true }, result.terms[1].kept)
        end)

        it("breaks keep ties in favour of the earlier die", function()
            local result = dice.roll("3d6kh1", SequenceRNG.new({ 5, 5, 2 }))
            assert.are.same({ true, false, false }, result.terms[1].kept)
            assert.are.equal(5, result.total)
        end)

        it("accepts a pre-parsed expression", function()
            local expr = dice.parse("1d8+2")
            assert.are.equal(9, dice.roll(expr, SequenceRNG.new({ 7 })).total)
        end)

        it("is reproducible with a seeded RNG", function()
            local a = dice.roll("10d20", RNG.new(5))
            local b = dice.roll("10d20", RNG.new(5))
            assert.are.same(a, b)
        end)

        it("always lands within range()", function()
            local rng = RNG.new(11)
            for _, notation in ipairs({ "1d20+5", "4d6kh3", "2d8-1d4-2", "-1d6" }) do
                local min, max = dice.range(notation)
                for _ = 1, 200 do
                    local total = dice.roll(notation, rng).total
                    assert.is_true(total >= min and total <= max, notation .. " => " .. total)
                end
            end
        end)

        it("rejects a missing rng", function()
            local ok, err = pcall(dice.roll, "1d6", nil)
            assert.is_false(ok)
            assert.are.equal("INVALID_ARGUMENT", err.code)
        end)
    end)

    describe("range", function()
        it("computes min and max totals", function()
            assert.are.same({ 6, 25 }, { dice.range("1d20+5") })
            assert.are.same({ 3, 18 }, { dice.range("4d6kh3") })
            assert.are.same({ -6, -1 }, { dice.range("-1d6") })
            assert.are.same({ -2, 15 }, { dice.range("2d8-1d4") })
        end)
    end)
    describe("dice_terms", function()
        it("lists dice terms only, as plain data", function()
            assert.are.same({
                { count = 2, sides = 6 },
                { count = 4, sides = 6, keep = { mode = "highest", count = 3 } },
            }, dice.dice_terms("2d6 + 3 - 4d6kh3"))
        end)
    end)

    describe("resolve (externally supplied values)", function()
        it("computes the result from given faces, skipping constants", function()
            local result = dice.resolve("2d6 + 3 - 1d4", { { 6, 2 }, { 3 } })
            assert.are.equal(6 + 2 + 3 - 3, result.total)
            assert.are.same({ 6, 2 }, result.terms[1].rolls)
            assert.are.same({ 3 }, result.terms[3].rolls)
        end)

        it("applies keep rules to supplied faces", function()
            local result = dice.resolve("2d20kh1", { { 4, 19 } })
            assert.are.equal(19, result.total)
            assert.are.same({ false, true }, result.terms[1].kept)
        end)

        it("copies faces so later mutation of the input cannot change the result", function()
            local faces = { 5 }
            local result = dice.resolve("1d6", { faces })
            faces[1] = 1
            assert.are.equal(5, result.total)
        end)

        it("accepts an empty list for constant-only expressions", function()
            assert.are.equal(7, dice.resolve("7", {}).total)
        end)

        local cases = {
            ["a non-table"] = { "1d6", 3, {} },
            ["missing terms"] = { "1d6+1d4", { { 1 } }, { got_terms = 1, expected_terms = 2 } },
            ["extra terms"] = { "1d6", { { 1 }, { 2 } }, { got_terms = 2 } },
            ["too few faces"] = { "2d6", { { 1 } }, { term = 1, expected = 2 } },
            ["too many faces"] = { "1d6", { { 1, 2 } }, { term = 1 } },
            ["a face above sides"] = { "1d6+1d4", { { 6 }, { 5 } }, { term = 2, die = 1 } },
            ["a zero face"] = { "1d6", { { 0 } }, { die = 1 } },
            ["a fractional face"] = { "1d6", { { 2.5 } }, { die = 1 } },
            ["a string face"] = { "1d6", { { "6" } }, { die = 1 } },
        }
        for label, case in pairs(cases) do
            it("rejects " .. label .. " with INVALID_ARGUMENT", function()
                local ok, err = pcall(dice.resolve, case[1], case[2])
                assert.is_false(ok)
                assert.are.equal("INVALID_ARGUMENT", err.code)
                for k, v in pairs(case[3]) do
                    assert.are.equal(v, err.details[k], k)
                end
            end)
        end
    end)
end)
