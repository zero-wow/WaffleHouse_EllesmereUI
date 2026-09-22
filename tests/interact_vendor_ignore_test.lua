-- Saved-vendor Interact-key regression checks.
-- Run from the addon source directory:
--   lua tests/interact_vendor_ignore_test.lua WaffleHouse_EllesmereUI.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(SOURCE, "rb"))
local source = file:read("*a")
file:close()

local function section(first, following)
    local start = assert(source:find(first, 1, true), "missing source boundary: " .. first)
    local finish = assert(source:find(following, start + #first, true), "missing source boundary: " .. following)
    return source:sub(start, finish - 1)
end

local guids, settings, combat, closed = {}, {}, false, 0
function strsplit(separator, text)
    local values = {}
    for value in tostring(text or ""):gmatch("[^" .. separator .. "]+") do
        values[#values + 1] = value
    end
    return table.unpack(values)
end
function UnitGUID(unit) return guids[unit] end
function InCombatLockdown() return combat end
C_GossipInfo = { CloseGossip = function() closed = closed + 1 end }

local extracted = [[
local function GetSettings() return _G.__interactVendorSettings end
]] .. section("local function GetNPCIDFromGUID", "local function EnsureIgnoredInteractBindingFrames()") .. [[
return {
    GetNPCIDFromGUID = GetNPCIDFromGUID,
    GetSoftInteractVendorNPCID = GetSoftInteractVendorNPCID,
    IsIgnoredInteractVendor = addon.IsIgnoredInteractVendor,
    CloseIgnoredVendorGossip = addon.CloseIgnoredVendorGossip,
}
]]

_G.__interactVendorSettings = settings
addon = {}
local chunk = assert(load(extracted, "@extracted-interact-vendor-ignore", "t", _G))
local production = chunk()

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

settings.ignoreInteractVendorsInCombat = true
settings.ignoreInteractVendorsOutOfCombat = true
settings.ignoredInteractVendorNPCs = { [27914] = true }

equal(production.GetNPCIDFromGUID("Creature-0-1-2-3-27914-00000001"), 27914,
    "Creature vendor IDs must remain supported")
equal(production.GetNPCIDFromGUID("Vehicle-0-1-2-3-27914-00000001"), 27914,
    "Vehicle vendor IDs must remain supported")
equal(production.GetNPCIDFromGUID("Pet-0-4234-0-6610-27914-0202F859E9"), 27914,
    "summoned vendor pets must use the GUID's stable creature ID")
equal(production.GetNPCIDFromGUID("BattlePet-0-00000338F951"), nil,
    "journal-only BattlePet GUIDs are not interactable service creatures")

guids.npc = "Pet-0-4234-0-6610-27914-0202F859E9"
combat = false
equal(production.CloseIgnoredVendorGossip(), false, "outside combat must preserve intentional vendor dialogue")
equal(closed, 0, "outside-combat dialogue must not be closed")

combat = true
equal(production.CloseIgnoredVendorGossip(), true, "saved vendor pets must close their gossip in combat")
equal(closed, 1, "combat dismissal must call CloseGossip once")

guids.npc = nil
guids.softinteract = "Pet-0-4234-0-6610-27914-0202F859E9"
equal(production.CloseIgnoredVendorGossip(), true, "soft-interact fallback must handle the vendor before npc resolves")
equal(closed, 2, "soft-interact dismissal must call CloseGossip once")

guids.softinteract = "Pet-0-4234-0-6610-12345-0202F859E9"
equal(production.CloseIgnoredVendorGossip(), false, "unsaved vendor pets must remain usable in combat")
equal(closed, 2, "unsaved vendors must not be closed")

guids.softinteract = "Pet-0-4234-0-6610-27914-0202F859E9"
settings.ignoreInteractVendorsInCombat = false
equal(production.CloseIgnoredVendorGossip(), false, "out-of-combat-only ignores must not close combat dialogue")
equal(closed, 2, "combat-only dismissal must obey its checkbox")
settings.ignoreInteractVendorsInCombat = true

-- Exercise the secure state snippet with the same two phase choices that the
-- live options expose. Binding keys are stored before combat; the state driver
-- then releases or restores them without an insecure combat-time API call.
local owner
UIParent = {}
function CreateFrame(_, name)
    local frame = {name = name, attributes = {}, bindings = {}}
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetAlpha() end
    function frame:RegisterForClicks() end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:ClearBindings() self.bindings = {} end
    function frame:SetBindingClick(_, key, buttonName) self.bindings[key] = buttonName end
    if name == "WaffleHouseIgnoredInteractBindingOwner" then owner = frame end
    return frame
end
function RegisterStateDriver(frame, stateID, driver)
    equal(frame, owner, "combat state driver must belong to the binding owner")
    equal(stateID, "combat", "binding driver must observe combat state")
    equal(driver, "[combat] combat; peace", "binding driver must cover both phases")
end
function ClearOverrideBindings(frame) frame:ClearBindings() end
function SetOverrideBindingClick(frame, _, key, buttonName) frame:SetBindingClick(false, key, buttonName) end
function GetBindingKey(action)
    equal(action, "INTERACTTARGET", "only the Interact With Target action may be blocked")
    return "F", "G"
end

local bindingChunk = [[
local ignoredInteractBindingOwner, ignoredInteractBlocker
local UpdateIgnoredInteractBinding
local function GetSettings() return _G.__interactVendorSettings end
local GetSoftInteractVendorNPCID = _G.__testGetSoftInteractVendorNPCID
]] .. section("local function EnsureIgnoredInteractBindingFrames()", "addon.RefreshIgnoredInteractBinding = UpdateIgnoredInteractBinding") .. [[
return UpdateIgnoredInteractBinding
]]
_G.__testGetSoftInteractVendorNPCID = production.GetSoftInteractVendorNPCID
local updateBinding = assert(load(bindingChunk, "@extracted-interact-binding", "t", _G))()
local function phase(state)
    local snippet = owner:GetAttribute("_onstate-combat")
    assert(type(snippet) == "string", "secure combat-state snippet must be installed")
    assert(load("return function(self, newstate) " .. snippet .. " end", "@secure-state"))()(owner, state)
end
local function hasBinding()
    return owner.bindings.F == "WaffleHouseIgnoredInteractBlocker"
        and owner.bindings.G == "WaffleHouseIgnoredInteractBlocker"
end

combat = false
for _, options in ipairs({
    {out = true, inCombat = false},
    {out = false, inCombat = true},
    {out = true, inCombat = true},
    {out = false, inCombat = false},
}) do
    settings.ignoreInteractVendorsOutOfCombat = options.out
    settings.ignoreInteractVendorsInCombat = options.inCombat
    updateBinding()
    equal(hasBinding(), options.out, "out-of-combat bindings must follow their own checkbox")
    phase("combat")
    equal(hasBinding(), options.inCombat, "combat bindings must follow their own checkbox")
    phase("peace")
    equal(hasBinding(), options.out, "combat exit must restore only out-of-combat bindings")
end

guids.softinteract = "Pet-0-4234-0-6610-12345-0202F859E9"
updateBinding()
equal(next(owner.bindings), nil, "a different soft target must release both saved key overrides")

-- Existing single-toggle SavedVariables carry their old behavior forward.
local settingsChunk = [[local BAG_FREEZE_MARKER_POSITIONS = { TOPRIGHT = true }
]] .. section("local function GetSettings()", "-- Feature modules share") .. [[
return GetSettings
]]
local migrate = assert(load(settingsChunk, "@extracted-interact-settings", "t", _G))()
for _, oldValue in ipairs({true, false}) do
    WaffleHouseDB = {ignoreInteractVendors = oldValue}
    local saved = migrate()
    equal(saved.ignoreInteractVendorsInCombat, oldValue, "old toggle must migrate its combat setting")
    equal(saved.ignoreInteractVendorsOutOfCombat, oldValue, "old toggle must migrate its out-of-combat setting")
end
WaffleHouseDB = {ignoreInteractVendors = true, ignoreInteractVendorsInCombat = false, ignoreInteractVendorsOutOfCombat = true}
local saved = migrate()
equal(saved.ignoreInteractVendorsInCombat, false, "explicit new combat setting must not be overwritten by legacy data")
equal(saved.ignoreInteractVendorsOutOfCombat, true, "explicit new out-of-combat setting must remain independent")

assert(source:find('events:RegisterEvent("GOSSIP_SHOW")', 1, true),
    "the main event frame must observe newly opened NPC dialogue")
assert(source:find('event == "GOSSIP_SHOW" and addon.CloseIgnoredVendorGossip and addon.CloseIgnoredVendorGossip()', 1, true),
    "GOSSIP_SHOW must synchronously dismiss only ignored combat vendors")

io.write("Interact vendor ignore tests passed\n")
