--- Deterministic, seedable random number generator.
--
-- Lehmer / Park-Miller "minimal standard" (multiplier 48271, modulus 2^31 - 1). Every
-- intermediate product fits exactly in a double, so the sequence is identical on Lua 5.1,
-- 5.2, 5.3, 5.4 and LuaJIT without needing bit operations. Never use math.random inside
-- the engine: a seeded RNG is what makes rolls reproducible, replayable and testable.
local errors = require("ttrpg.errors")

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 48271

local RNG = {}
RNG.__index = RNG

local function normalize_seed(seed)
    if type(seed) ~= "number" or seed ~= seed or seed == math.huge or seed == -math.huge then
        errors.raise(errors.codes.INVALID_ARGUMENT, "seed must be a finite number", {
            seed = seed,
        })
    end
    -- Map any integer onto the valid state range [1, MODULUS - 1].
    return math.floor(seed) % (MODULUS - 1) + 1
end

--- Creates a generator. `seed` defaults to os.time(); pass one explicitly for determinism.
function RNG.new(seed)
    return setmetatable({ state = normalize_seed(seed or os.time()) }, RNG)
end

--- Advances the generator and returns the raw state, in [1, MODULUS - 1].
function RNG:next_raw()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return self.state
end

--- Uniform integer in [min, max] (inclusive), without modulo bias.
function RNG:random(min, max)
    if type(min) ~= "number" or type(max) ~= "number" or min > max then
        errors.raise(errors.codes.INVALID_ARGUMENT, "random(min, max) requires min <= max", {
            min = min,
            max = max,
        })
    end
    min, max = math.floor(min), math.floor(max)
    local range = max - min + 1
    if range > MODULUS - 1 then
        errors.raise(errors.codes.INVALID_ARGUMENT, "random range too large", { range = range })
    end
    -- Rejection sampling: discard the tail that would make some values more likely.
    local limit = math.floor((MODULUS - 1) / range) * range
    local x
    repeat
        x = self:next_raw() - 1
    until x < limit
    return min + x % range
end

--- Opaque state snapshot, for save games and replays.
function RNG:get_state()
    return self.state
end

function RNG:set_state(state)
    if type(state) ~= "number" or state < 1 or state >= MODULUS or state % 1 ~= 0 then
        errors.raise(errors.codes.INVALID_ARGUMENT, "invalid RNG state", { state = state })
    end
    self.state = state
end

return RNG
