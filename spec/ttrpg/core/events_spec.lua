local Events = require("ttrpg.core.events")

describe("ttrpg.core.events", function()
    local events

    before_each(function()
        events = Events.new()
    end)

    it("delivers payload and event name to handlers in subscription order", function()
        local log = {}
        events:on("hit", function(p, name)
            log[#log + 1] = "a:" .. p.damage .. ":" .. name
        end)
        events:on("hit", function(p)
            log[#log + 1] = "b:" .. p.damage
        end)
        events:emit("hit", { damage = 7 })
        assert.are.same({ "a:7:hit", "b:7" }, log)
    end)

    it("ignores events with no subscribers", function()
        assert.has_no.errors(function()
            events:emit("nothing")
        end)
    end)

    it("unsubscribes, idempotently", function()
        local handler = spy.new(function() end)
        local off = events:on("x", handler)
        off()
        off()
        events:emit("x")
        assert.spy(handler).was_not_called()
    end)

    it("does not affect the emit in progress when handlers change", function()
        local calls = {}
        local off_b
        events:on("x", function()
            calls[#calls + 1] = "a"
            off_b()
            events:on("x", function()
                calls[#calls + 1] = "late"
            end)
        end)
        off_b = events:on("x", function()
            calls[#calls + 1] = "b"
        end)
        events:emit("x")
        assert.are.same({ "a", "b" }, calls)
    end)

    it("rejects invalid subscriptions", function()
        local ok, err = pcall(events.on, events, "x", "not a function")
        assert.is_false(ok)
        assert.are.equal("INVALID_ARGUMENT", err.code)
    end)
end)
