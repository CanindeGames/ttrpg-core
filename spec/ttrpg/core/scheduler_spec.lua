local Scheduler = require("ttrpg.core.scheduler")

describe("ttrpg.core.scheduler", function()
    local scheduler

    before_each(function()
        scheduler = Scheduler.new()
    end)

    it("runs a task that needs no input to completion", function()
        local status = scheduler:run(function(a, b)
            return a + b
        end, 2, 3)
        assert.are.same({ status = "done", task = 1, result = 5 }, status)
        assert.are.same({}, scheduler:pending())
    end)

    it("suspends on await and resumes with the response", function()
        local status = scheduler:run(function()
            local answer = scheduler:await("choice", { options = { "a", "b" } })
            return "picked " .. answer
        end)
        assert.are.equal("waiting", status.status)
        assert.are.same(
            { id = 1, task = 1, type = "choice", options = { "a", "b" } },
            status.request
        )
        assert.are.same({ status.request }, scheduler:pending())

        local final = scheduler:respond(status.request.id, "b")
        assert.are.same({ status = "done", task = 1, result = "picked b" }, final)
        assert.are.same({}, scheduler:pending())
    end)

    it("handles several sequential awaits in one task", function()
        local status = scheduler:run(function()
            local x = scheduler:await("n")
            local y = scheduler:await("n")
            return x * y
        end)
        status = scheduler:respond(status.request.id, 6)
        assert.are.equal("waiting", status.status)
        assert.are.equal(2, status.request.id)
        assert.are.equal(42, scheduler:respond(status.request.id, 7).result)
    end)

    it("keeps independent tasks independent", function()
        local a = scheduler:run(function()
            return "a:" .. scheduler:await("x")
        end)
        local b = scheduler:run(function()
            return "b:" .. scheduler:await("x")
        end)
        assert.are.equal(2, #scheduler:pending())
        assert.are.equal("b:2", scheduler:respond(b.request.id, "2").result)
        assert.are.equal("a:1", scheduler:respond(a.request.id, "1").result)
    end)

    it("does not let request data override id/task/type", function()
        local status = scheduler:run(function()
            scheduler:await("real", { id = "x", task = "y", type = "fake" })
        end)
        assert.are.equal("real", status.request.type)
        assert.are.equal(1, status.request.id)
    end)

    describe("validation", function()
        local status
        before_each(function()
            status = scheduler:run(function()
                return scheduler:await("number", nil, function(raw)
                    if type(raw) ~= "number" then
                        error({ code = "INVALID_ARGUMENT" })
                    end
                    return raw * 10
                end)
            end)
        end)

        it("passes the validated value to the task", function()
            assert.are.equal(50, scheduler:respond(status.request.id, 5).result)
        end)

        it("raises to the caller and keeps the request open on invalid input", function()
            assert.has_error(function()
                scheduler:respond(status.request.id, "nope")
            end)
            assert.are.equal(1, #scheduler:pending())
            assert.are.equal(30, scheduler:respond(status.request.id, 3).result)
        end)
    end)

    it("reports task errors as failed with a structured error", function()
        local status = scheduler:run(function()
            scheduler:await("x")
            error("boom")
        end)
        status = scheduler:respond(status.request.id, true)
        assert.are.equal("failed", status.status)
        assert.are.equal("INTERNAL", status.error.code)
        assert.matches("boom", status.error.message)
    end)

    it("fails tasks that yield outside await", function()
        local status = scheduler:run(function()
            coroutine.yield("stray")
        end)
        assert.are.equal("failed", status.status)
        assert.are.equal("INVALID_STATE", status.error.code)
    end)

    it("cancels a waiting task and closes its request", function()
        local reached = false
        local status = scheduler:run(function()
            scheduler:await("x")
            reached = true
        end)
        assert.are.same({ status = "cancelled", task = 1 }, scheduler:cancel(status.task))
        assert.are.same({}, scheduler:pending())
        assert.is_false(reached)

        local ok, err = pcall(scheduler.respond, scheduler, status.request.id, 1)
        assert.is_false(ok)
        assert.are.equal("NOT_FOUND", err.code)
    end)

    it("raises INPUT_REQUIRED when awaiting outside a task", function()
        local ok, err = pcall(scheduler.await, scheduler, "x")
        assert.is_false(ok)
        assert.are.equal("INPUT_REQUIRED", err.code)
        assert.is_false(scheduler:in_task())
    end)

    it("raises INPUT_REQUIRED inside a foreign coroutine", function()
        local co = coroutine.create(function()
            return pcall(scheduler.await, scheduler, "x")
        end)
        local _, ok, err = coroutine.resume(co)
        assert.is_false(ok)
        assert.are.equal("INPUT_REQUIRED", err.code)
    end)

    it("knows when it is running inside a task", function()
        assert.are.equal(
            true,
            scheduler:run(function()
                return scheduler:in_task()
            end).result
        )
    end)

    it("raises NOT_FOUND for unknown ids and rejects non-callables", function()
        assert.are.equal("NOT_FOUND", select(2, pcall(scheduler.respond, scheduler, 99)).code)
        assert.are.equal("NOT_FOUND", select(2, pcall(scheduler.cancel, scheduler, 99)).code)
        assert.are.equal(
            "INVALID_ARGUMENT",
            select(2, pcall(scheduler.run, scheduler, "not a function")).code
        )
    end)
end)
