rockspec_format = "3.0"
package = "ttrpg-core"
version = "dev-1"

source = {
    url = "git+https://github.com/CanindeGames/ttrpg-core.git",
}

description = {
    summary = "Embeddable, system-agnostic tabletop RPG rules engine.",
    detailed = [[
        Pure-Lua engine for running tabletop RPG systems digitally (SRD/ORC content and
        homebrew systems) inside games and game servers.
    ]],
    license = "TBD",
}

dependencies = {
    "lua >= 5.1",
}

test_dependencies = {
    "busted",
}

test = {
    type = "busted",
}

build = {
    type = "builtin",
    modules = {
        ["ttrpg"] = "src/ttrpg/init.lua",
        ["ttrpg.version"] = "src/ttrpg/version.lua",
        ["ttrpg.errors"] = "src/ttrpg/errors.lua",
        ["ttrpg.util"] = "src/ttrpg/util.lua",
        ["ttrpg.engine"] = "src/ttrpg/engine.lua",
        ["ttrpg.core.rng"] = "src/ttrpg/core/rng.lua",
        ["ttrpg.core.dice"] = "src/ttrpg/core/dice.lua",
        ["ttrpg.core.events"] = "src/ttrpg/core/events.lua",
        ["ttrpg.core.registry"] = "src/ttrpg/core/registry.lua",
        ["ttrpg.core.scheduler"] = "src/ttrpg/core/scheduler.lua",
    },
}
