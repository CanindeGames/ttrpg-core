# ttrpg-core

Embeddable, system-agnostic tabletop RPG rules engine written in Lua. Run D&D 5e SRD, Pathfinder ORC or your own homebrew system inside games and game servers.

> Status: early scaffold (`0.1.0-dev`). The core provides a deterministic RNG, dice rolling (engine-rolled or player-supplied), tasks that pause while waiting for input, events and a game system registry.

## Quick start

```lua
package.path = "src/?.lua;src/?/init.lua;" .. package.path
local ttrpg = require("ttrpg")

local engine = ttrpg.new({ seed = 42 })    -- fixed seed = reproducible session
local r = engine:roll("4d6kh3")            -- also: "1d20+5", "2d20kl1", "d%", "2d6+1d4-1"
print(r.total, r.terms[1].rolls, r.terms[1].kept)

local ok, err = ttrpg.errors.try(engine.roll, engine, "2d")
-- ok == false, err.code == "PARSE_ERROR", err.message/err.details explain what failed
```

### Engine-rolled or player-supplied dice

The engine can roll dice itself or ask the client for the result (e.g. a player's physical dice). Rules run inside `engine:run`; when a value is missing, execution pauses and the host receives a serializable request:

```lua
local engine = ttrpg.new({ roll_source = "external" })   -- or "auto", or a per-actor function

local status = engine:run(function()
    return engine:roll("1d20+5", { context = { actor = "p1" } }).total
end)
-- status.status == "waiting"
-- status.request == { id = 1, task = 1, type = "roll", notation = "1d20+5",
--                     dice = { { count = 1, sides = 20 } }, min = 6, max = 25, context = {...} }

status = engine:respond(status.request.id, { rolls = { { 14 } } })  -- or { auto = true }
-- status.status == "done", status.result == 19
```

Full examples: [examples/custom_system.lua](examples/custom_system.lua) (homebrew system) and [examples/external_rolls.lua](examples/external_rolls.lua) (player rolls physical dice, NPCs are rolled by the engine).

## Development

Requires LuaJIT (or Lua 5.1+) and LuaRocks. On Windows, use Git Bash.

```sh
scripts/dev.sh setup          # install busted, luacheck, luacov into ./.luarocks
scripts/dev.sh check          # lint + format check + tests (same as CI)
scripts/dev.sh test           # tests only
scripts/dev.sh fmt            # format with StyLua (via npx if not on PATH)
scripts/dev.sh cov            # coverage -> luacov.report.out
```

## Content licensing

Third-party game content is only included when openly licensed (SRD 5.1/5.2 under CC-BY-4.0, Pathfinder under the ORC License) and always with the required attribution.
