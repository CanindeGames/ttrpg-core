--- Engine instance: the unit a host embeds.
--
-- All state lives in the instance (no module-level mutable state), so a server can run
-- many independent engines (one per table/session) in the same Lua state.
--
-- The engine works autonomously (it rolls its own dice) or driven by external input (it
-- asks the host for values, e.g. a player's physical dice). See ttrpg.core.scheduler for
-- the run/await/respond model.
local Events = require("ttrpg.core.events")
local RNG = require("ttrpg.core.rng")
local Registry = require("ttrpg.core.registry")
local Scheduler = require("ttrpg.core.scheduler")
local dice = require("ttrpg.core.dice")
local errors = require("ttrpg.errors")
local util = require("ttrpg.util")

local Engine = {}
Engine.__index = Engine

local ROLL_SOURCES = { auto = true, external = true }

local function check_roll_source(source)
    if not ROLL_SOURCES[source] and not util.is_callable(source) then
        errors.raise(
            errors.codes.INVALID_ARGUMENT,
            "roll source must be 'auto', 'external' or a callable returning one of them",
            { source = source }
        )
    end
end

--- Creates an engine.
--
-- options.seed         number    RNG seed (defaults to os.time(); set it for reproducibility)
-- options.rng          table     custom RNG with random(min, max); overrides `seed`
-- options.roll_source  string    "auto" (default): the engine rolls; "external": the host
--                      | fn      supplies die values. A callable receives
--                                { notation, context } and returns "auto" or "external",
--                                e.g. to let players roll physical dice while NPCs don't.
function Engine.new(options)
    options = options or {}
    if type(options) ~= "table" then
        errors.raise(errors.codes.INVALID_ARGUMENT, "engine options must be a table")
    end
    local roll_source = options.roll_source or "auto"
    check_roll_source(roll_source)
    return setmetatable({
        rng = options.rng or RNG.new(options.seed),
        roll_source = roll_source,
        events = Events.new(),
        systems = Registry.new(),
        scheduler = Scheduler.new(),
    }, Engine)
end

--- Registers a game system and runs its `setup(engine, system)`. Emits "system.registered".
function Engine:register_system(def)
    self.systems:register(def)
    if def.setup then
        def.setup(self, def)
    end
    self.events:emit("system.registered", { id = def.id })
    return def
end

function Engine:get_system(id)
    return self.systems:get(id)
end

function Engine:list_systems()
    return self.systems:list()
end

local function validate_roll_response(expression, response)
    if type(response) ~= "table" then
        errors.raise(
            errors.codes.INVALID_ARGUMENT,
            "roll response must be { rolls = { {faces...}, ... } } or { auto = true }"
        )
    end
    if response.auto == true then
        return { auto = true }
    end
    dice.check_rolls(expression, response.rolls)
    return { rolls = response.rolls }
end

--- Rolls dice notation (or a parsed expression). Emits "dice.rolled".
--
-- options.source   "auto" | "external"  overrides the engine's roll_source for this roll
-- options.context  table                free-form plain data passed to the host and kept in
--                                       the result (e.g. { actor = "p1", reason = "attack" })
--
-- With source "external" the current task suspends with a request
-- `{ type = "roll", notation, dice = { {count, sides, keep}... }, min, max, context }`.
-- The host answers with `{ rolls = { {faces of dice term 1}, ... } }`, or `{ auto = true }`
-- to let the engine roll instead (e.g. the player timed out). Outside engine:run() an
-- external roll raises INPUT_REQUIRED.
--
-- The result has the shape of ttrpg.core.dice.resolve plus `source` ("auto"|"external")
-- and `context`.
function Engine:roll(notation, options)
    options = options or {}
    if type(options) ~= "table" then
        errors.raise(errors.codes.INVALID_ARGUMENT, "roll options must be a table")
    end
    local expression = type(notation) == "string" and dice.parse(notation) or notation

    local source = options.source or self.roll_source
    check_roll_source(source)
    if util.is_callable(source) then
        local chosen = source({ notation = expression.notation, context = options.context })
        if not ROLL_SOURCES[chosen] then
            errors.raise(
                errors.codes.INVALID_ARGUMENT,
                "roll_source callable must return 'auto' or 'external'",
                { returned = chosen }
            )
        end
        source = chosen
    end

    local result
    if source == "external" then
        local min, max = dice.range(expression)
        local response = self.scheduler:await("roll", {
            notation = expression.notation,
            dice = dice.dice_terms(expression),
            min = min,
            max = max,
            context = options.context,
        }, function(raw)
            return validate_roll_response(expression, raw)
        end)
        if response.auto then
            result = dice.roll(expression, self.rng)
            result.source = "auto"
        else
            result = dice.resolve(expression, response.rolls)
            result.source = "external"
        end
    else
        result = dice.roll(expression, self.rng)
        result.source = "auto"
    end
    result.context = options.context

    self.events:emit("dice.rolled", result)
    return result
end

--- Subscribes to an engine event. Returns an unsubscribe function.
function Engine:on(name, handler)
    return self.events:on(name, handler)
end

local function announce(self, status)
    if status.status == "waiting" then
        self.events:emit("input.requested", status.request)
    end
    return status
end

--- Runs `fn(...)` as a task that may pause for external input. Returns a status table
-- (see ttrpg.core.scheduler). Emits "input.requested" whenever the task starts waiting.
function Engine:run(fn, ...)
    return announce(self, self.scheduler:run(fn, ...))
end

--- Answers an open request and resumes its task. Returns the task's new status.
-- Invalid responses raise INVALID_ARGUMENT and leave the request open.
function Engine:respond(request_id, response)
    return announce(self, self.scheduler:respond(request_id, response))
end

--- Abandons a task that is waiting for input.
function Engine:cancel(task_id)
    return self.scheduler:cancel(task_id)
end

--- Open requests, oldest first (plain data, safe to serialize).
function Engine:pending()
    return self.scheduler:pending()
end

--- Low-level hook for systems that need other kinds of input (choose a target, use a
-- reaction?, ...). Must be called inside engine:run(). See Scheduler:await.
function Engine:await(kind, data, validate)
    return self.scheduler:await(kind, data, validate)
end

return Engine
