local Registry = require("ttrpg.core.registry")

local function system(overrides)
    local def = { id = "homebrew", name = "Homebrew", version = "1.0.0" }
    for k, v in pairs(overrides or {}) do
        def[k] = v
    end
    return def
end

local function error_of(fn, ...)
    local ok, err = pcall(fn, ...)
    assert.is_false(ok)
    return err
end

describe("ttrpg.core.registry", function()
    local registry

    before_each(function()
        registry = Registry.new()
    end)

    it("registers and retrieves systems", function()
        local def = registry:register(system())
        assert.are.equal(def, registry:get("homebrew"))
        assert.is_true(registry:has("homebrew"))
        assert.is_false(registry:has("other"))
    end)

    it("lists ids sorted", function()
        registry:register(system({ id = "zeta" }))
        registry:register(system({ id = "alpha" }))
        assert.are.same({ "alpha", "zeta" }, registry:list())
    end)

    it("rejects duplicates with ALREADY_EXISTS", function()
        registry:register(system())
        assert.are.equal("ALREADY_EXISTS", error_of(registry.register, registry, system()).code)
    end)

    it("raises NOT_FOUND for unknown ids", function()
        local err = error_of(registry.get, registry, "ghost")
        assert.are.equal("NOT_FOUND", err.code)
        assert.are.equal("ghost", err.details.id)
    end)

    it("accepts an optional license", function()
        assert.has_no.errors(function()
            registry:register(system({
                license = { name = "CC-BY-4.0", attribution = "SRD 5.1 by Wizards of the Coast" },
            }))
        end)
    end)

    local invalid = {
        ["a non-table definition"] = "dnd5e",
        ["a missing id"] = system({ id = false }),
        ["an uppercase id"] = system({ id = "DnD" }),
        ["an id starting with a digit"] = system({ id = "5e" }),
        ["an id with spaces"] = system({ id = "my system" }),
        ["a missing name"] = system({ name = false }),
        ["an empty version"] = system({ version = "" }),
        ["a license without name"] = system({ license = { attribution = "x" } }),
        ["a non-function setup"] = system({ setup = "nope" }),
    }
    for label, def in pairs(invalid) do
        it("rejects " .. label .. " with INVALID_ARGUMENT", function()
            assert.are.equal("INVALID_ARGUMENT", error_of(registry.register, registry, def).code)
        end)
    end
end)
