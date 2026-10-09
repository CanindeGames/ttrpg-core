--- Tasks that can pause to wait for external input.
--
-- Rules code runs inside a task (a coroutine). When it needs something only the host can
-- provide (a player's physical die roll, a choice of target, ...), it calls `await`, which
-- suspends the task and hands the host a plain-data request. The host answers later with
-- `respond(request_id, response)` and the task continues from where it stopped. Rules code
-- therefore stays linear whether input is immediate or arrives minutes later over a socket.
--
-- Every `run`, `respond` and `cancel` returns a status table:
--
--     { status = "done",      task = id, result = <first return value of fn> }
--     { status = "waiting",   task = id, request = { id, task, type, ... } }
--     { status = "failed",    task = id, error = <structured error> }
--     { status = "cancelled", task = id }
--
-- Caveat: on PUC Lua 5.1 a task cannot be suspended from inside pcall (LuaJIT and Lua 5.2+
-- can), so code that may await should not be wrapped in pcall/errors.try.
local errors = require("ttrpg.errors")
local util = require("ttrpg.util")

local Scheduler = {}
Scheduler.__index = Scheduler

-- Yielded alongside a request so tasks can tell our suspensions from stray yields.
local AWAIT = {}

function Scheduler.new()
    return setmetatable({
        next_task = 0,
        next_request = 0,
        tasks = {}, -- task id -> task
        requests = {}, -- request id -> { public, task, validate }
        by_coroutine = setmetatable({}, { __mode = "k" }),
    }, Scheduler)
end

local function finish(self, task)
    self.tasks[task.id] = nil
    self.by_coroutine[task.co] = nil
    if task.request then
        self.requests[task.request] = nil
        task.request = nil
    end
end

local function step(self, task, ...)
    local ok, first, request = coroutine.resume(task.co, ...)
    if not ok then
        finish(self, task)
        local err = errors.is(first) and first or errors.new(errors.codes.INTERNAL, tostring(first))
        return { status = "failed", task = task.id, error = err }
    end
    if coroutine.status(task.co) == "dead" then
        finish(self, task)
        return { status = "done", task = task.id, result = first }
    end
    if first ~= AWAIT then
        finish(self, task)
        return {
            status = "failed",
            task = task.id,
            error = errors.new(
                errors.codes.INVALID_STATE,
                "task yielded outside of await(); use engine input APIs to pause a task"
            ),
        }
    end
    return { status = "waiting", task = task.id, request = request }
end

--- Starts `fn(...)` as a task and runs it until it finishes or awaits input.
function Scheduler:run(fn, ...)
    if not util.is_callable(fn) then
        errors.raise(errors.codes.INVALID_ARGUMENT, "run(fn, ...) expects a callable")
    end
    self.next_task = self.next_task + 1
    local task = {
        id = self.next_task,
        co = coroutine.create(function(...)
            return fn(...)
        end),
    }
    self.tasks[task.id] = task
    self.by_coroutine[task.co] = task
    return step(self, task, ...)
end

--- True when called from inside one of this scheduler's tasks.
function Scheduler:in_task()
    local co = coroutine.running()
    return co ~= nil and self.by_coroutine[co] ~= nil
end

--- Suspends the current task until the host responds. `data` fields are copied into the
-- public request (keep them plain data: they may be sent over the wire). `validate`, if
-- given, receives the raw response and returns the value handed back to the task; it
-- should raise INVALID_ARGUMENT for bad input, which leaves the request open.
function Scheduler:await(kind, data, validate)
    local co = coroutine.running()
    local task = co and self.by_coroutine[co]
    if not task then
        errors.raise(
            errors.codes.INPUT_REQUIRED,
            "input of type '" .. tostring(kind) .. "' requires running inside engine:run(...)",
            { type = kind }
        )
    end

    self.next_request = self.next_request + 1
    local request = {}
    for k, v in pairs(data or {}) do
        request[k] = v
    end
    request.id = self.next_request
    request.task = task.id
    request.type = kind

    self.requests[request.id] = { public = request, task = task, validate = validate }
    task.request = request.id
    return coroutine.yield(AWAIT, request)
end

--- Answers request `id` and resumes its task. Raises NOT_FOUND for unknown/closed
-- requests; validation errors propagate to the caller and keep the request open.
function Scheduler:respond(id, response)
    local entry = self.requests[id]
    if not entry then
        errors.raise(errors.codes.NOT_FOUND, "no open request with id " .. tostring(id), {
            id = id,
        })
    end
    local value = response
    if entry.validate then
        value = entry.validate(response)
    end
    self.requests[id] = nil
    entry.task.request = nil
    return step(self, entry.task, value)
end

--- Abandons a suspended task (its code does not run any further).
function Scheduler:cancel(task_id)
    local task = self.tasks[task_id]
    if not task then
        errors.raise(errors.codes.NOT_FOUND, "no active task with id " .. tostring(task_id), {
            task = task_id,
        })
    end
    finish(self, task)
    return { status = "cancelled", task = task_id }
end

--- Open requests, oldest first.
function Scheduler:pending()
    local list = {}
    for _, entry in pairs(self.requests) do
        list[#list + 1] = entry.public
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

return Scheduler
