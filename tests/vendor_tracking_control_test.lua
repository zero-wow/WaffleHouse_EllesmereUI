-- Vendor tracking-pin regression harness.
-- Run from the addon source directory:
--   lua tests/vendor_tracking_control_test.lua
--
-- The harness extracts the production planner functions and supplies only
-- their required WoW frame/API surface.  It deliberately exercises pooled
-- button reuse because Vendor Bags pools its merchant-item buttons.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text
end

local function extractFunction(source, name, declarationPattern)
    local startAt = assert(source:find(declarationPattern or ("local%s+function%s+" .. name .. "%s*%("), 1),
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
        elseif char == "\"" or char == "'" then
            index = skipQuoted(index, char)
        elseif char:match("[%a_]") then
            local _, last, word = source:find("([%a_][%w_]*)", index)
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

local Object = {}
Object.__index = Object
function Object:SetSize(width, height) self.width, self.height = width, height end
function Object:SetPoint(...) self.point = { ... } end
function Object:SetFrameLevel(level) self.frameLevel = level end
function Object:GetFrameLevel() return self.frameLevel or 0 end
function Object:RegisterForClicks(...) self.clicks = { ... } end
function Object:SetPropagateMouseClicks()
    error("protected SetPropagateMouseClicks must not run while a vendor opens", 2)
end
function Object:CreateTexture()
    return setmetatable({ parent = self }, Object)
end
function Object:SetTexCoord(...) self.uv = { ... } end
function Object:SetTexture(path) self.texture = path end
function Object:SetScript(name, callback)
    self.scripts = self.scripts or {}
    self.scripts[name] = callback
end
function Object:GetScript(name) return self.scripts and self.scripts[name] end
function Object:Show() self.shown = true end
function Object:Hide() self.shown = false end
function Object:IsShown() return self.shown == true end
function Object:GetParent() return self.parent end

function CreateFrame(_, _, parent)
    return setmetatable({ parent = parent, scripts = {} }, Object)
end

local planner, notes, merchantInfo, merchantLinks
local refreshes, lastTooltip, lastPopup
local addon = {}

local function resetState()
    planner, notes = {}, {}
    merchantInfo, merchantLinks = {}, {}
    refreshes, lastTooltip, lastPopup = 0, nil, nil
end

function GetMerchantItemInfo(index)
    local info = merchantInfo[index]
    if not info then return nil end
    return info.name, info.texture, info.price
end
function GetMerchantItemLink(index)
    return merchantLinks[index]
end
function UnitGUID(unit)
    assert(unit == "npc", "planner should only look up the active merchant")
    return "Creature-0-0-0-0-12345-00000001"
end
function UnitName(unit)
    assert(unit == "npc", "planner should only name the active merchant")
    return "Test Merchant"
end

EllesmereUI = {
    ShowWidgetTooltip = function(_, text) lastTooltip = text end,
    HideWidgetTooltip = function() end,
    BuildCogPopup = function(config)
        lastPopup = config
        return nil, function() end
    end,
}

local productionSource = readFile(SOURCE)
local extracted = table.concat({
    [[
local addon = _G.__addon
local function IsSafeValue(value) return value ~= nil end
local function IsSafeText(value) return type(value) == "string" and value ~= "" end
local function IsSafeNumber(value) return type(value) == "number" end
local function GetVendorPlanner() return _G.__planner(), _G.__notes() end
]],
    extractFunction(productionSource, "GetVendorMerchantInfo"),
    extractFunction(productionSource, "GetVendorItemID"),
    extractFunction(productionSource, "GetVendorPlannerKey"),
    extractFunction(productionSource, "SaveVendorPlannerItem"),
    extractFunction(productionSource, "ShowVendorNotePopup", "ShowVendorNotePopup%s*=%s*function%s*%("),
    extractFunction(productionSource, "EnsureVendorPlannerControl"),
    [[
return {
    GetVendorPlannerKey = GetVendorPlannerKey,
    SaveVendorPlannerItem = SaveVendorPlannerItem,
    EnsureVendorPlannerControl = EnsureVendorPlannerControl,
    ShowVendorNotePopup = ShowVendorNotePopup,
}
]],
}, "\n")

_G.__addon = addon
_G.__planner = function() return planner end
_G.__notes = function() return notes end
addon.Refresh = function() refreshes = refreshes + 1 end
local chunk, loadErr = load(extracted, "@extracted-vendor-tracking-control", "t", _G)
assert(chunk, loadErr)
local production = chunk()

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertContains(text, expected, message)
    assertTrue(type(text) == "string" and text:find(expected, 1, true), message or ("missing " .. expected))
end

local function newVendorButton(itemID, index)
    index = index or 1
    local button = setmetatable({ _merchantIndex = index, _link = "|Hitem:" .. itemID .. ":0|h[Item " .. itemID .. "]|h" }, Object)
    merchantLinks[index] = button._link
    merchantInfo[index] = { name = "Item " .. itemID, texture = 134400, price = 13579 }
    return button
end

local function invoke(frame, script, ...)
    local callback = assert(frame:GetScript(script), "missing " .. script)
    return callback(frame, ...)
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end

test("left-click toggles planner membership and preserves the third merchant return as price", function()
    resetState()
    local button = newVendorButton(1001)
    production.EnsureVendorPlannerControl(button, { { amount = 5, key = "currency", name = "Marks", texture = 1 } })
    local control = button._wafflePlannerControl
    local key = production.GetVendorPlannerKey(button)

    invoke(control, "OnClick", "LeftButton")
    assertTrue(planner[key] ~= nil, "left-click should save the item")
    assertEqual(planner[key].price, 13579, "saved price must use GetMerchantItemInfo's third return")
    assertEqual(refreshes, 1, "saving should refresh once")

    production.EnsureVendorPlannerControl(button, button._waffleCosts)
    assertContains(control.icon.texture, "vendor-pin-on.tga", "saved item should use the on pin")
    invoke(control, "OnClick", "LeftButton")
    assertTrue(planner[key] == nil, "second left-click should remove the item")
    assertEqual(refreshes, 2, "removing should refresh once")
end)

test("notes alone stay off and right-click edits notes without toggling tracking", function()
    resetState()
    local button = newVendorButton(1002)
    production.EnsureVendorPlannerControl(button, {})
    local control = button._wafflePlannerControl
    local key = production.GetVendorPlannerKey(button)
    notes[key] = "already researched"

    production.EnsureVendorPlannerControl(button, {})
    assertContains(control.icon.texture, "vendor-pin-off.tga", "a note alone must not look tracked")
    invoke(control, "OnClick", "RightButton")
    assertTrue(lastPopup ~= nil, "right-click should open the note popup")
    lastPopup.rows[1].set("buy on next visit")
    assertEqual(notes[key], "buy on next visit", "popup should save the note")
    assertTrue(planner[key] == nil, "editing a note must not add the item to the planner")
    assertEqual(refreshes, 1, "saving a note should refresh once")
end)

test("pin registers both click buttons without a protected propagation call", function()
    resetState()
    local button = newVendorButton(1003)
    production.EnsureVendorPlannerControl(button, {})
    local control = button._wafflePlannerControl
    assertEqual(control.clicks[1], "LeftButtonUp", "pin should explicitly register left clicks")
    assertEqual(control.clicks[2], "RightButtonUp", "pin should explicitly register right clicks")
    assertTrue(control.parent == button, "pin must remain a child button with default click propagation")
end)

test("buyback and missing item links hide the pooled pin control", function()
    resetState()
    local button = newVendorButton(1004)
    production.EnsureVendorPlannerControl(button, {})
    local control = button._wafflePlannerControl
    assertTrue(control:IsShown(), "valid merchant item should show its pin")

    button._isBuyback = true
    production.EnsureVendorPlannerControl(button, {})
    assertTrue(not control:IsShown(), "buyback rows must hide the pin")

    button._isBuyback = nil
    button._link = nil
    merchantLinks[button._merchantIndex] = nil
    production.EnsureVendorPlannerControl(button, {})
    assertTrue(not control:IsShown(), "rows without a valid item link must hide the pin")
end)

test("a pooled button changing links updates its tracking state", function()
    resetState()
    local button = newVendorButton(1005)
    production.EnsureVendorPlannerControl(button, {})
    local control = button._wafflePlannerControl
    invoke(control, "OnClick", "LeftButton")
    local firstKey = production.GetVendorPlannerKey(button)
    assertTrue(planner[firstKey] ~= nil, "initial pooled row should save")

    button._link = "|Hitem:2005:0|h[Item 2005]|h"
    merchantLinks[button._merchantIndex] = button._link
    merchantInfo[button._merchantIndex] = { name = "Item 2005", texture = 134400, price = 24680 }
    production.EnsureVendorPlannerControl(button, {})
    local secondKey = production.GetVendorPlannerKey(button)
    assertTrue(firstKey ~= secondKey, "pooled row should derive a new key from its current link")
    assertContains(control.icon.texture, "vendor-pin-off.tga", "new item on a pooled row must not inherit old tracked state")

    invoke(control, "OnClick", "LeftButton")
    production.EnsureVendorPlannerControl(button, {})
    assertTrue(planner[firstKey] ~= nil and planner[secondKey] ~= nil, "both independently tracked items should remain saved")
    assertContains(control.icon.texture, "vendor-pin-on.tga", "newly saved pooled row should show tracked state")
end)

test("tooltip reports the current planner membership rather than note presence", function()
    resetState()
    local button = newVendorButton(1006)
    production.EnsureVendorPlannerControl(button, {})
    local control = button._wafflePlannerControl
    local key = production.GetVendorPlannerKey(button)
    notes[key] = "note only"
    invoke(control, "OnEnter")
    assertContains(lastTooltip, "Shopping List: Not tracked", "note-only item should be not tracked in tooltip")

    invoke(control, "OnClick", "LeftButton")
    invoke(control, "OnEnter")
    assertContains(lastTooltip, "Shopping List: Tracked", "saved item should be tracked in tooltip")
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
    io.write(string.format("%d of %d scenarios failed\n", failures, #tests))
    os.exit(1)
end
io.write(string.format("All %d vendor tracking-pin scenarios passed\n", #tests))
