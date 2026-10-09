--- Example: mixing autonomous rolls with rolls supplied by the client.
--
-- Run from the repo root:  luajit examples/external_rolls.lua
--
-- The rules code (`attack`) is written once, linearly. A policy decides who rolls: the
-- player rolls physical dice (external), the goblin is rolled by the engine (auto). When
-- the engine needs the player's dice, `run`/`respond` return status "waiting" with a
-- plain-data request; a real host would send it to the client over its socket/API and
-- call `respond` when the answer arrives.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local ttrpg = require("ttrpg")

local engine = ttrpg.new({
    seed = 7,
    roll_source = function(info)
        return info.context.actor == "player" and "external" or "auto"
    end,
})

local function attack(attacker, bonus, armor_class)
    local roll =
        engine:roll("1d20+" .. bonus, { context = { actor = attacker, reason = "attack" } })
    local hit = roll.total >= armor_class
    print(
        string.format(
            "%s attacks: %d (%s) -> %s",
            attacker,
            roll.total,
            roll.source,
            hit and "hit" or "miss"
        )
    )
    return hit
end

local function round()
    local goblin_hit = attack("goblin", 4, 15)
    local player_hit = attack("player", 5, 13)
    return { goblin_hit = goblin_hit, player_hit = player_hit }
end

-- Host loop: answer every request until the task finishes. Here the "client" always
-- reports a natural 14; a real host would wait for the player's input instead.
local status = engine:run(round)
while status.status == "waiting" do
    local request = status.request
    print(string.format("engine asks %s to roll %s", request.context.actor, request.notation))
    status = engine:respond(request.id, { rolls = { { 14 } } })
end

assert(status.status == "done", status.error and tostring(status.error))
return status.result
