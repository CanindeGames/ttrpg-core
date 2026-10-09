-- Engine driven by external input: rolls supplied by the host instead of the engine RNG.
local ttrpg = require("ttrpg")
local SequenceRNG = require("support.sequence_rng")

local function error_of(fn, ...)
    local ok, err = pcall(fn, ...)
    assert.is_false(ok)
    return err
end

describe("engine input (external rolls)", function()
    it("rolls autonomously by default, inside or outside a task", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({ 11, 12 }) })
        assert.are.equal("auto", engine:roll("1d20").source)
        local status = engine:run(function()
            return engine:roll("1d20").total
        end)
        assert.are.same({ status = "done", task = 1, result = 12 }, status)
    end)

    it("suspends an external roll and resumes with the client's faces", function()
        local engine = ttrpg.new({ seed = 1, roll_source = "external" })
        local status = engine:run(function()
            local attack = engine:roll("1d20+5", { context = { actor = "p1", reason = "attack" } })
            return attack.total >= 15
        end)

        assert.are.equal("waiting", status.status)
        assert.are.same({
            id = 1,
            task = 1,
            type = "roll",
            notation = "1d20+5",
            dice = { { count = 1, sides = 20 } },
            min = 6,
            max = 25,
            context = { actor = "p1", reason = "attack" },
        }, status.request)

        local final = engine:respond(status.request.id, { rolls = { { 12 } } })
        assert.are.same({ status = "done", task = 1, result = true }, final)
    end)

    it("returns a full result marked as external", function()
        local engine = ttrpg.new({ seed = 1 })
        local result
        local status = engine:run(function()
            result = engine:roll("4d6kh3", { source = "external" })
        end)
        engine:respond(status.request.id, { rolls = { { 1, 6, 4, 3 } } })
        assert.are.equal("external", result.source)
        assert.are.equal(13, result.total)
        assert.are.same({ false, true, true, true }, result.terms[1].kept)
    end)

    it("does not consume the engine RNG for external rolls", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({}), roll_source = "external" })
        local status = engine:run(function()
            return engine:roll("2d6").total
        end)
        assert.are.equal(7, engine:respond(status.request.id, { rolls = { { 3, 4 } } }).result)
    end)

    it("falls back to an engine roll when the host answers { auto = true }", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({ 17 }), roll_source = "external" })
        local result
        local status = engine:run(function()
            result = engine:roll("1d20")
        end)
        engine:respond(status.request.id, { auto = true })
        assert.are.equal(17, result.total)
        assert.are.equal("auto", result.source)
    end)

    it("rejects invalid faces and keeps waiting for a valid answer", function()
        local engine = ttrpg.new({ seed = 1, roll_source = "external" })
        local status = engine:run(function()
            return engine:roll("1d6").total
        end)
        local id = status.request.id

        assert.are.equal(
            "INVALID_ARGUMENT",
            error_of(engine.respond, engine, id, { rolls = { { 7 } } }).code
        )
        assert.are.equal("INVALID_ARGUMENT", error_of(engine.respond, engine, id, "six").code)
        assert.are.equal("INVALID_ARGUMENT", error_of(engine.respond, engine, id, {}).code)
        assert.are.equal(1, #engine:pending())

        assert.are.equal(6, engine:respond(id, { rolls = { { 6 } } }).result)
    end)

    it("mixes sources per roll via a roll_source policy", function()
        local engine = ttrpg.new({
            rng = SequenceRNG.new({ 9 }),
            roll_source = function(info)
                return info.context and info.context.actor == "player" and "external" or "auto"
            end,
        })
        local log = {}
        local status = engine:run(function()
            log[#log + 1] = engine:roll("1d20", { context = { actor = "goblin" } }).total
            log[#log + 1] = engine:roll("1d20", { context = { actor = "player" } }).total
            return log
        end)
        assert.are.same({ 9 }, log) -- goblin rolled automatically, player is pending
        assert.are.equal("player", status.request.context.actor)
        assert.are.same({ 9, 15 }, engine:respond(status.request.id, { rolls = { { 15 } } }).result)
    end)

    it("lets a per-roll source override the engine default", function()
        local engine = ttrpg.new({ rng = SequenceRNG.new({ 2 }), roll_source = "external" })
        assert.are.equal(2, engine:roll("1d4", { source = "auto" }).total)
    end)

    it("raises INPUT_REQUIRED for an external roll outside run()", function()
        local engine = ttrpg.new({ seed = 1, roll_source = "external" })
        assert.are.equal("INPUT_REQUIRED", error_of(engine.roll, engine, "1d20").code)
    end)

    it("emits input.requested and dice.rolled", function()
        local engine = ttrpg.new({ seed = 1, roll_source = "external" })
        local requested, rolled = {}, {}
        engine:on("input.requested", function(request)
            requested[#requested + 1] = request.type
        end)
        engine:on("dice.rolled", function(result)
            rolled[#rolled + 1] = result.source
        end)
        local status = engine:run(function()
            engine:roll("1d6")
        end)
        assert.are.same({ "roll" }, requested)
        assert.are.same({}, rolled)
        engine:respond(status.request.id, { rolls = { { 1 } } })
        assert.are.same({ "external" }, rolled)
    end)

    it("exposes await for custom input types", function()
        local engine = ttrpg.new({ seed = 1 })
        local status = engine:run(function()
            return engine:await("choose_target", { options = { "orc", "goblin" } })
        end)
        assert.are.same({ "orc", "goblin" }, engine:pending()[1].options)
        assert.are.equal("orc", engine:respond(status.request.id, "orc").result)
    end)

    it("cancels a task waiting for a roll", function()
        local engine = ttrpg.new({ seed = 1, roll_source = "external" })
        local status = engine:run(function()
            engine:roll("1d20")
        end)
        assert.are.equal("cancelled", engine:cancel(status.task).status)
        assert.are.same({}, engine:pending())
    end)

    describe("invalid configuration", function()
        it("rejects unknown roll sources", function()
            assert.are.equal(
                "INVALID_ARGUMENT",
                error_of(ttrpg.new, { roll_source = "maybe" }).code
            )
            local engine = ttrpg.new({ seed = 1 })
            assert.are.equal(
                "INVALID_ARGUMENT",
                error_of(engine.roll, engine, "1d6", { source = "maybe" }).code
            )
            assert.are.equal("INVALID_ARGUMENT", error_of(engine.roll, engine, "1d6", "auto").code)
        end)

        it("rejects a policy that returns an unknown source", function()
            local engine = ttrpg.new({
                seed = 1,
                roll_source = function()
                    return "dunno"
                end,
            })
            local err = error_of(engine.roll, engine, "1d6")
            assert.are.equal("INVALID_ARGUMENT", err.code)
            assert.are.equal("dunno", err.details.returned)
        end)
    end)
end)
