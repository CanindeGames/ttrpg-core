--- Test double: an RNG that returns a scripted sequence of values, so dice tests can assert
-- exact outcomes. Raises if the code under test draws more values than were scripted, or a
-- scripted value falls outside the requested range.
local SequenceRNG = {}
SequenceRNG.__index = SequenceRNG

function SequenceRNG.new(values)
    return setmetatable({ values = values, index = 0, calls = {} }, SequenceRNG)
end

function SequenceRNG:random(min, max)
    self.index = self.index + 1
    local value = self.values[self.index]
    assert(value ~= nil, "SequenceRNG exhausted after " .. (self.index - 1) .. " values")
    assert(
        value >= min and value <= max,
        string.format("scripted value %d outside requested range [%d, %d]", value, min, max)
    )
    self.calls[#self.calls + 1] = { min = min, max = max }
    return value
end

return SequenceRNG
