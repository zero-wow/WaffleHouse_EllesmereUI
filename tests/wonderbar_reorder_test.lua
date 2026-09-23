-- Wonderbar drag-reorder regression harness.
--
-- Run from the addon source directory:
--   lua tests/wonderbar_reorder_test.lua
--
-- The live DataBars module owns its saved order.  This test extracts Waffle
-- House's geometry and rollback helpers from production, then exercises them
-- against DataBars' documented pre-removal MoveBlockTo contract.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text:gsub("\r\n", "\n")
end

local function extractFunction(source, name)
    local startAt = assert(source:find("local%s+function%s+" .. name .. "%s*%(", 1),
        "could not find function " .. name)
    local depth, index = 0, startAt

    local function skipQuoted(pos, quote)
        pos = pos + 1
        while pos <= #source do
            local char = source:sub(pos, pos)
            if char == "\\" then
                pos = pos + 2
            elseif char == quote then
                return pos + 1
            else
                pos = pos + 1
            end
        end
        return pos
    end

    while index <= #source do
        local char, nextTwo = source:sub(index, index), source:sub(index, index + 1)
        if nextTwo == "--" then
            local newline = source:find("\n", index + 2, true)
            index = newline and newline + 1 or #source + 1
        elseif char == '"' or char == "'" then
            index = skipQuoted(index, char)
        elseif char:match("[%a_]") then
            local first, last, word = source:find("([%a_][%w_]*)", index)
            index = last + 1
            if word == "function" or word == "if" or word == "for" or word == "while" or word == "repeat" then
                depth = depth + 1
            elseif word == "end" or word == "until" then
                depth = depth - 1
                if depth == 0 then return source:sub(startAt, last) end
            end
        else
            index = index + 1
        end
    end
    error("unterminated function " .. name)
end

local source = readFile(SOURCE)
assert(source:find('drag%.ns%.MoveBlockTo%(drag%.barId, drag%.blockId, boundary%)'),
    "drag preview must commit through the exported DataBars MoveBlockTo API")
assert(source:find('RestoreWonderbarBlockOrder%(drag%.ns, drag%.barId, drag%.originalOrder%)'),
    "cancelled drags must restore the original DataBars block order")
assert(source:find('RegisterStateDriver, overlay, "visibility", "%[combat%] hide; %[mod:shift%] show; hide"'),
    "reorder overlays must be securely hidden except while Shift is held out of combat")
local _, shiftGuardCount = source:gsub('if not %(IsShiftKeyDown and IsShiftKeyDown%(%)%) then return end', '')
assert(shiftGuardCount >= 2,
    "starting a reorder drag and showing its hint must each require Shift")
assert(source:find('if not %(IsShiftKeyDown and IsShiftKeyDown%(%)%) then\n        EndWonderbarDrag%(false%)'),
    "releasing Shift during a reorder drag must cancel and restore the original order")

local helpers = table.concat({
    extractFunction(source, "GetWonderbarBlockIndex"),
    extractFunction(source, "CopyWonderbarBlockOrder"),
    extractFunction(source, "GetWonderbarDropBoundary"),
    extractFunction(source, "RestoreWonderbarBlockOrder"),
    "return GetWonderbarBlockIndex, CopyWonderbarBlockOrder, GetWonderbarDropBoundary, RestoreWonderbarBlockOrder",
}, "\n\n")
local chunk, loadErr = load(helpers, "@extracted-wonderbar-helpers", "t", _G)
assert(chunk, loadErr)
local GetWonderbarBlockIndex, CopyWonderbarBlockOrder, GetWonderbarDropBoundary, RestoreWonderbarBlockOrder = chunk()

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. "\nexpected: " .. tostring(expected) .. "\nactual:   " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function makeSlot(x, y)
    return { GetCenter = function() return x, y end }
end

local function makeBar(vertical)
    return {
        id = 11,
        orientation = vertical and "V" or "H",
        blocks = {
            { id = "A" }, { id = "B" }, { id = "C" }, { id = "D" },
        },
    }
end

local function orderString(blocks)
    local ids = {}
    for index, block in ipairs(blocks) do ids[index] = block.id end
    return table.concat(ids, ",")
end

local function makeDataBarsMock(bar)
    local ns = {}
    function ns.GetBar(id)
        return id == bar.id and bar or nil
    end
    function ns.MoveBlockTo(barId, blockId, newIndex)
        assertEqual(barId, bar.id, "MoveBlockTo received the wrong bar")
        local from
        for index, block in ipairs(bar.blocks) do
            if block.id == blockId then from = index break end
        end
        assertTrue(from ~= nil, "MoveBlockTo received an unknown block")
        local block = table.remove(bar.blocks, from)
        local to = newIndex or (from + 1)
        if to > from then to = to - 1 end
        if to < 1 then to = 1 end
        if to > #bar.blocks + 1 then to = #bar.blocks + 1 end
        table.insert(bar.blocks, to, block)
    end
    return ns
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end

test("drop boundaries follow horizontal entry centers", function()
    local bar = makeBar(false)
    local rec = { slots = { A = makeSlot(50, 0), B = makeSlot(150, 0), C = makeSlot(250, 0), D = makeSlot(350, 0) } }
    assertEqual(GetWonderbarDropBoundary(bar, rec, 10, 0), 1, "before the first entry")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 100, 0), 2, "between A and B")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 200, 0), 3, "between B and C")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 500, 0), 5, "after the final entry")
end)

test("drop boundaries follow vertical top-to-bottom entry centers", function()
    local bar = makeBar(true)
    local rec = { slots = { A = makeSlot(0, 350), B = makeSlot(0, 250), C = makeSlot(0, 150), D = makeSlot(0, 50) } }
    assertEqual(GetWonderbarDropBoundary(bar, rec, 0, 500), 1, "above the first entry")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 0, 300), 2, "between A and B")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 0, 200), 3, "between B and C")
    assertEqual(GetWonderbarDropBoundary(bar, rec, 0, 10), 5, "below the final entry")
end)

test("DataBars pre-removal boundaries produce the intended forward and backward positions", function()
    local bar, ns = makeBar(false), nil
    ns = makeDataBarsMock(bar)
    ns.MoveBlockTo(bar.id, "A", 4)
    assertEqual(orderString(bar.blocks), "B,C,A,D", "forward drop should place A after C")

    bar = makeBar(false)
    ns = makeDataBarsMock(bar)
    ns.MoveBlockTo(bar.id, "D", 2)
    assertEqual(orderString(bar.blocks), "A,D,B,C", "backward drop should place D before B")
end)

test("cancelling a drag restores the exact original entry order via public API", function()
    local bar = makeBar(false)
    local original = CopyWonderbarBlockOrder(bar.blocks)
    local ns = makeDataBarsMock(bar)
    ns.MoveBlockTo(bar.id, "A", 5)
    ns.MoveBlockTo(bar.id, "C", 1)
    assertEqual(orderString(bar.blocks), "C,B,D,A", "test setup must alter the order")
    RestoreWonderbarBlockOrder(ns, bar.id, original)
    assertEqual(orderString(bar.blocks), "A,B,C,D", "rollback must restore the drag-start order")
    assertEqual(GetWonderbarBlockIndex(bar.blocks, "C"), 3, "restored block index")
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, err = xpcall(entry.callback, debug.traceback)
    if ok then
        io.write("PASS  " .. entry.name .. "\n")
    else
        failures = failures + 1
        io.write("FAIL  " .. entry.name .. "\n" .. err .. "\n")
    end
end

if failures > 0 then
    io.write(string.format("%d of %d Wonderbar reorder scenarios failed\n", failures, #tests))
    os.exit(1)
end
io.write(string.format("All %d Wonderbar reorder scenarios passed\n", #tests))
