--- Dice notation parser and roller.
--
-- Grammar (case and whitespace insensitive):
--
--     expression := ["+" | "-"] term { ("+" | "-") term }
--     term       := dice | integer
--     dice       := [count] "d" (sides | "%") [ ("kh" | "kl") [n] ]
--
-- Examples: "d20", "1d20+5", "2d6 + 1d4 - 1", "4d6kh3", "2d20kl1", "d%".
--
-- Parsing and rolling are separate: `parse` returns a plain-data expression that can be
-- cached, serialized or inspected. Results come from `resolve(expression, rolls)`, which
-- takes die values from anywhere (e.g. a player's physical dice); `roll` just generates
-- those values with an RNG first. Results record every individual die, so hosts can
-- animate or audit the roll.
local errors = require("ttrpg.errors")
local util = require("ttrpg.util")

local M = {}

-- Hard caps: the engine runs inside servers and must not be DoS-able by user input.
M.MAX_COUNT = 1000
M.MAX_SIDES = 10000

local function fail(notation, message, position)
    errors.raise(errors.codes.PARSE_ERROR, message, { notation = notation, position = position })
end

local function parse_term(src, pos, notation)
    local _, e, count, sides = src:find("^(%d*)d(%d+)", pos)
    if not e then
        _, e, count = src:find("^(%d*)d%%", pos)
        sides = "100"
    end

    if e then
        count = count == "" and 1 or tonumber(count)
        sides = tonumber(sides)
        if count < 1 or count > M.MAX_COUNT then
            fail(notation, "dice count must be between 1 and " .. M.MAX_COUNT, pos)
        end
        if sides < 1 or sides > M.MAX_SIDES then
            fail(notation, "dice sides must be between 1 and " .. M.MAX_SIDES, pos)
        end

        local term = { kind = "dice", count = count, sides = sides }
        local _, ke, mode, n = src:find("^k([hl])(%d*)", e + 1)
        if ke then
            n = n == "" and 1 or tonumber(n)
            if n < 1 or n > count then
                fail(notation, "keep count must be between 1 and the number of dice", e + 1)
            end
            term.keep = { mode = mode == "h" and "highest" or "lowest", count = n }
            e = ke
        end
        return term, e + 1
    end

    local _, ce, digits = src:find("^(%d+)", pos)
    if ce then
        return { kind = "constant", value = tonumber(digits) }, ce + 1
    end

    fail(notation, "expected dice (e.g. 2d6) or a number", pos)
end

--- Parses dice notation into an expression table. Raises PARSE_ERROR on invalid input;
-- `details.position` is a 1-based index into the notation with whitespace removed.
function M.parse(notation)
    if type(notation) ~= "string" then
        errors.raise(errors.codes.INVALID_ARGUMENT, "dice notation must be a string", {
            notation = notation,
        })
    end
    local src = notation:gsub("%s+", ""):lower()
    if src == "" then
        fail(notation, "empty dice notation", 1)
    end

    local terms = {}
    local pos, sign = 1, 1
    local lead = src:sub(1, 1)
    if lead == "-" or lead == "+" then
        sign = lead == "-" and -1 or 1
        pos = 2
    end

    while true do
        local term, next_pos = parse_term(src, pos, notation)
        term.sign = sign
        terms[#terms + 1] = term
        pos = next_pos
        if pos > #src then
            break
        end
        local op = src:sub(pos, pos)
        if op == "+" then
            sign = 1
        elseif op == "-" then
            sign = -1
        else
            fail(notation, "unexpected character '" .. op .. "'", pos)
        end
        pos = pos + 1
        if pos > #src then
            fail(notation, "expression ends with an operator", pos)
        end
    end

    return { notation = notation, terms = terms }
end

-- Marks which rolls survive a keep-highest/lowest rule. Ties go to the earlier die.
local function kept_flags(rolls, keep)
    local kept = {}
    if not keep then
        for i = 1, #rolls do
            kept[i] = true
        end
        return kept
    end
    local order = {}
    for i = 1, #rolls do
        order[i] = i
        kept[i] = false
    end
    local highest = keep.mode == "highest"
    table.sort(order, function(a, b)
        if rolls[a] ~= rolls[b] then
            if highest then
                return rolls[a] > rolls[b]
            end
            return rolls[a] < rolls[b]
        end
        return a < b
    end)
    for i = 1, keep.count do
        kept[order[i]] = true
    end
    return kept
end

local function as_expression(expression)
    if type(expression) == "string" then
        return M.parse(expression)
    end
    return expression
end

--- The dice terms of an expression, in order, as plain data: `{ { count, sides, keep } }`.
-- Constants are skipped. This is the shape clients must answer with in `resolve`.
function M.dice_terms(expression)
    local out = {}
    for _, term in ipairs(as_expression(expression).terms) do
        if term.kind == "dice" then
            out[#out + 1] = { count = term.count, sides = term.sides, keep = term.keep }
        end
    end
    return out
end

local function bad_rolls(message, details)
    errors.raise(errors.codes.INVALID_ARGUMENT, message, details)
end

--- Validates die values supplied from outside (e.g. a player's physical dice).
-- `rolls[k]` is the list of faces for the k-th dice term (constants skipped), matching
-- `dice_terms`. Raises INVALID_ARGUMENT, with `details.term`/`details.die` pointing at
-- the offending value.
function M.check_rolls(expression, rolls)
    local terms = M.dice_terms(expression)
    if type(rolls) ~= "table" then
        bad_rolls("rolls must be a list with one list of faces per dice term", {
            expected_terms = #terms,
        })
    end
    if #rolls ~= #terms then
        bad_rolls("expected faces for " .. #terms .. " dice term(s), got " .. #rolls, {
            expected_terms = #terms,
            got_terms = #rolls,
        })
    end
    for k, term in ipairs(terms) do
        local faces = rolls[k]
        if type(faces) ~= "table" or #faces ~= term.count then
            bad_rolls(string.format("dice term %d needs exactly %d value(s)", k, term.count), {
                term = k,
                expected = term.count,
            })
        end
        for d = 1, term.count do
            local v = faces[d]
            if type(v) ~= "number" or v % 1 ~= 0 or v < 1 or v > term.sides then
                bad_rolls(
                    string.format("dice term %d, die %d: expected 1..%d", k, d, term.sides),
                    { term = k, die = d, value = v, sides = term.sides }
                )
            end
        end
    end
end

--- Computes a roll result from known die values (validated with `check_rolls`).
--
-- Returns `{ notation, total, terms }`, where each dice term carries `rolls` (every die,
-- in order), `kept` (parallel booleans) and `subtotal` (unsigned sum of kept dice).
function M.resolve(expression, rolls)
    expression = as_expression(expression)
    M.check_rolls(expression, rolls)

    local total = 0
    local results = {}
    local k = 0
    for i, term in ipairs(expression.terms) do
        local result
        if term.kind == "dice" then
            k = k + 1
            local faces = {}
            for d = 1, term.count do
                faces[d] = rolls[k][d]
            end
            local kept = kept_flags(faces, term.keep)
            local subtotal = 0
            for d = 1, #faces do
                if kept[d] then
                    subtotal = subtotal + faces[d]
                end
            end
            result = {
                kind = "dice",
                sign = term.sign,
                count = term.count,
                sides = term.sides,
                keep = term.keep,
                rolls = faces,
                kept = kept,
                subtotal = subtotal,
            }
        else
            result = { kind = "constant", sign = term.sign, value = term.value }
            result.subtotal = term.value
        end
        total = total + term.sign * result.subtotal
        results[i] = result
    end

    return { notation = expression.notation, total = total, terms = results }
end

--- Rolls an expression (table from `parse`, or a notation string) using `rng`, any object
-- with a `random(min, max)` method. Same result shape as `resolve`.
function M.roll(expression, rng)
    expression = as_expression(expression)
    if type(rng) ~= "table" or not util.is_callable(rng.random) then
        errors.raise(errors.codes.INVALID_ARGUMENT, "roll requires an rng with random(min, max)")
    end

    local rolls = {}
    for _, term in ipairs(M.dice_terms(expression)) do
        local faces = {}
        for d = 1, term.count do
            faces[d] = rng:random(1, term.sides)
        end
        rolls[#rolls + 1] = faces
    end
    return M.resolve(expression, rolls)
end

--- Minimum and maximum possible totals of an expression (table or notation string).
function M.range(expression)
    expression = as_expression(expression)
    local min, max = 0, 0
    for _, term in ipairs(expression.terms) do
        local lo, hi
        if term.kind == "dice" then
            local n = term.keep and term.keep.count or term.count
            lo, hi = n, n * term.sides
        else
            lo, hi = term.value, term.value
        end
        if term.sign < 0 then
            lo, hi = -hi, -lo
        end
        min, max = min + lo, max + hi
    end
    return min, max
end

return M
