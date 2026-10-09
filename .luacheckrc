-- luacheck config. Run from the repo root: `scripts/dev.sh lint`.
-- "min" = only globals present in every Lua version (5.1-5.4 and LuaJIT). The engine is
-- embedded in hosts we don't control, so src/ must stay portable.
std = "min"
max_line_length = 100
self = false -- methods defined with `:` may legitimately ignore self

exclude_files = {
    ".luarocks/**",
    "node_modules/**",
}

files["spec/**"] = { std = "+busted" }
