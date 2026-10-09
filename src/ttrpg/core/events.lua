--- Minimal synchronous event bus.
--
-- Handlers run in subscription order. Subscribing or unsubscribing during an emit does not
-- affect the emit in progress.
local errors = require("ttrpg.errors")
local util = require("ttrpg.util")

local Events = {}
Events.__index = Events

function Events.new()
    return setmetatable({ handlers = {} }, Events)
end

--- Subscribes `handler(payload, event_name)` to `name`. Returns an unsubscribe function.
function Events:on(name, handler)
    if type(name) ~= "string" or not util.is_callable(handler) then
        errors.raise(
            errors.codes.INVALID_ARGUMENT,
            "on(name, handler) expects a string and a callable"
        )
    end
    local list = self.handlers[name]
    if not list then
        list = {}
        self.handlers[name] = list
    end
    list[#list + 1] = handler

    local active = true
    return function()
        if not active then
            return
        end
        active = false
        for i = #list, 1, -1 do
            if list[i] == handler then
                table.remove(list, i)
                return
            end
        end
    end
end

--- Calls every handler subscribed to `name`.
function Events:emit(name, payload)
    local list = self.handlers[name]
    if not list then
        return
    end
    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        snapshot[i](payload, name)
    end
end

return Events
