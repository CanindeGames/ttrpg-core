local ttrpg = require("ttrpg")
local SequenceRNG = require("support.sequence_rng")

describe("ttrpg (public API)", function()
    it("exposes a version string", function()
        assert.is_string(ttrpg._VERSION)
    end)

    it("creates independent engine instances", function()
        local a, b = ttrpg.new({ seed = 1 }), ttrpg.new({ seed = 1 })
        a:register_system({ id = "only_a", name = "A", version = "1" })
        assert.is_true(a.systems:has("only_a"))
        assert.is_false(b.systems:has("only_a"))
    end)

    it("is reproducible for the same seed", function()
        local a, b = ttrpg.new({ seed = 123 }), ttrpg.new({ seed = 123 })
        for _ = 1, 20 do
            assert.are.equal(a:roll("1d20").total, b:roll("1d20").total)
        end
    end)

    it("uses an injected rng", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({ 20 }) })
        assert.are.equal(25, engine:roll("1d20+5").total)
    end)

    it("emits dice.rolled with the roll result", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({ 4 }) })
        local seen
        engine:on("dice.rolled", function(result)
            seen = result
        end)
        local result = engine:roll("1d6")
        assert.are.equal(result, seen)
    end)

    it("runs system setup once on registration and emits system.registered", function()
        local engine = ttrpg.new({ seed = 1 })
        local setup = spy.new(function() end)
        local registered = {}
        engine:on("system.registered", function(p)
            registered[#registered + 1] = p.id
        end)

        local def = { id = "homebrew", name = "Homebrew", version = "0.1.0", setup = setup }
        engine:register_system(def)

        assert.spy(setup).was_called(1)
        assert.spy(setup).was_called_with(engine, def)
        assert.are.same({ "homebrew" }, registered)
        assert.are.equal(def, engine:get_system("homebrew"))
        assert.are.same({ "homebrew" }, engine:list_systems())
    end)

    it("surfaces structured errors to the host", function()
        local engine = ttrpg.new({ seed = 1 })
        local ok, err = ttrpg.errors.try(engine.roll, engine, "2d")
        assert.is_false(ok)
        assert.are.equal(ttrpg.errors.codes.PARSE_ERROR, err.code)
    end)

    it("rejects non-table options", function()
        local ok, err = pcall(ttrpg.new, 42)
        assert.is_false(ok)
        assert.are.equal("INVALID_ARGUMENT", err.code)
    end)
end)
