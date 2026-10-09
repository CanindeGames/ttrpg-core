# ttrpg-core

Engine em Lua, embarcável e agnóstica de sistema, para rodar regras de RPG de mesa (D&D 5e SRD, Pathfinder ORC, sistemas próprios) dentro de jogos e servidores de jogo.

> Estado: scaffold inicial (`0.1.0-dev`). O núcleo tem RNG determinístico, rolagem de dados (automática ou enviada pelo cliente), tasks que pausam esperando input, eventos e registro de sistemas.

## Uso rápido

```lua
package.path = "src/?.lua;src/?/init.lua;" .. package.path
local ttrpg = require("ttrpg")

local engine = ttrpg.new({ seed = 42 })    -- seed fixo = sessão reproduzível
local r = engine:roll("4d6kh3")            -- também: "1d20+5", "2d20kl1", "d%", "2d6+1d4-1"
print(r.total, r.terms[1].rolls, r.terms[1].kept)

local ok, err = ttrpg.errors.try(engine.roll, engine, "2d")
-- ok == false, err.code == "PARSE_ERROR", err.message/err.details explicam onde falhou
```

### Rolagens autônomas ou enviadas pelo cliente

A engine pode rolar sozinha ou pedir o valor ao cliente (por exemplo, dado físico do jogador). As regras rodam dentro de `engine:run`; quando falta um valor, a execução pausa e o host recebe um pedido serializável:

```lua
local engine = ttrpg.new({ roll_source = "external" })   -- ou "auto", ou uma função por ator

local status = engine:run(function()
    return engine:roll("1d20+5", { context = { actor = "p1" } }).total
end)
-- status.status == "waiting"
-- status.request == { id = 1, task = 1, type = "roll", notation = "1d20+5",
--                     dice = { { count = 1, sides = 20 } }, min = 6, max = 25, context = {...} }

status = engine:respond(status.request.id, { rolls = { { 14 } } })  -- ou { auto = true }
-- status.status == "done", status.result == 19
```

Exemplos completos: [examples/custom_system.lua](examples/custom_system.lua) (sistema próprio) e [examples/external_rolls.lua](examples/external_rolls.lua) (jogador rola dado físico, NPC é automático).

## Desenvolvimento

Requer LuaJIT (ou Lua 5.1+) e LuaRocks. No Windows, use Git Bash.

```sh
scripts/dev.sh setup          # instala busted, luacheck, luacov em ./.luarocks
scripts/dev.sh check          # lint + formatação + testes (o mesmo que o CI)
scripts/dev.sh test           # só testes
scripts/dev.sh fmt            # formata com StyLua (via npx se não estiver no PATH)
scripts/dev.sh cov            # cobertura -> luacov.report.out
```

## Licenças de conteúdo

Conteúdo de terceiros só entra se for licenciado abertamente (SRD 5.1/5.2 sob CC-BY-4.0, Pathfinder sob ORC) e com o texto de atribuição exigido.
