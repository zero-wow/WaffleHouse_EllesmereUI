-- Run from the addon source directory:
--   lua tests/vendor_options_test.lua WaffleHouse_VendorOptions.lua

local SOURCE = arg[1] or "WaffleHouse_VendorOptions.lua"
local objects, controls, refreshes, bindings = {}, {}, 0, 0
local combat = false
local unitIDs = { softinteract = 444, target = 555, npc = 666 }
local unitNames = { softinteract = "Soft Vendor", target = "Target Vendor", npc = "NPC Vendor" }

local Frame = {}
Frame.__index = Frame
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:GetWidth() return self.width or 0 end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:HookScript(event, callback)
    self.hooks = self.hooks or {}
    self.hooks[event] = self.hooks[event] or {}
    self.hooks[event][#self.hooks[event] + 1] = callback
end
function Frame:CreateFontString()
    local text = setmetatable({ scripts = {} }, Frame)
    objects[#objects + 1] = text
    return text
end
function Frame:SetFont(path) self.font = path end
function Frame:SetText(value) self.text = value end
function Frame:SetTextColor() end
function Frame:SetJustifyH() end
function Frame:SetWordWrap() end
function Frame:SetMaxLines() end
function Frame:SetWidth(width) self.width = width end
function Frame:Click() if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end end
function Frame:Fire(event)
    if self.scripts and self.scripts[event] then self.scripts[event](self) end
    for _, callback in ipairs((self.hooks and self.hooks[event]) or {}) do callback(self) end
end

function CreateFrame(_, _, parent)
    local frame = setmetatable({ parent = parent, scripts = {} }, Frame)
    objects[#objects + 1] = frame
    return frame
end

function InCombatLockdown() return combat end
function UnitName(unit) return unitNames[unit] end

local function newControl(label)
    local control = setmetatable({ scripts = {}, label = label }, Frame)
    controls[label] = control
    return control
end

local tooltip = { hides = 0 }
EllesmereUI = {
    Widgets = {},
    RefreshPage = function(_, force) assert(force == true, "layout changes must force a rebuild"); refreshes = refreshes + 1 end,
    MakeStyledButton = function(button, _, _, _, callback)
        button:SetScript("OnClick", function() if callback then callback() end end)
    end,
    RB_COLOURS = {},
    _font = "EUI Expressway",
    ShowWidgetTooltip = function(owner, text) tooltip.owner, tooltip.text = owner, text end,
    HideWidgetTooltip = function() tooltip.hides, tooltip.owner = tooltip.hides + 1, nil end,
}
function EllesmereUI.Widgets:DualRow(_, _, left, right)
    local row = { _leftRegion = {}, _rightRegion = {} }
    if left.type ~= "spacer" then
        row._leftRegion._control = newControl(left.text)
        controls[left.text].cfg = left
        if left.type == "button" then EllesmereUI.MakeStyledButton(row._leftRegion._control, left.text, 13, {}, left.onClick) end
    end
    if right and right.type ~= "spacer" then
        row._rightRegion._control = newControl(right.text)
        controls[right.text].cfg = right
        if right.type == "button" then EllesmereUI.MakeStyledButton(row._rightRegion._control, right.text, 13, {}, right.onClick) end
    end
    return row, 50
end
function EllesmereUI.Widgets:SectionHeader() return {}, 40 end
function EllesmereUI.Widgets:WideButton(_, text, _, callback)
    controls[text] = newControl(text)
    controls[text]:SetScript("OnClick", function() if callback then callback() end end)
    return controls[text], 57
end
function EllesmereUI.Widgets:WideDualButton(_, first, second, _, firstCallback, secondCallback)
    controls[first] = newControl(first); controls[first]:SetScript("OnClick", function() if firstCallback then firstCallback() end end)
    controls[second] = newControl(second); controls[second]:SetScript("OnClick", function() if secondCallback then secondCallback() end end)
    return {}, 57
end

local settings = { ignoredInteractVendorNPCs = { [27914] = true } }
local addon = {
    GetSettings = function() return settings end,
    GetInteractVendorNPCID = function(unit) return unitIDs[unit or "softinteract"] end,
    RefreshIgnoredInteractBinding = function() bindings = bindings + 1 end,
}
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function build(width, y)
    controls, objects = {}, {}
    local parent = setmetatable({ width = width }, Frame)
    return addon.BuildIgnoredVendorOptions(parent, y or -100), parent
end

local collapsed = build(1005)
equal(collapsed, -150, "collapsed editor reserves only its manage row")
controls["Ignored Vendor NPCs"]:Click()
assert(settings.ignoredInteractVendorNPCs[444] == nil, "opening the editor must not mutate saved IDs")
local expanded = build(1005)
equal(expanded, -408, "one saved vendor must reserve one table row and the editor actions")
assert(controls["NPC ID"] and controls["Optional Name"], "manual add inputs must be present when expanded")
controls["Current Soft Target"]:Click()
assert(settings.ignoredInteractVendorNPCs[444] == nil, "current-target add must remain draft-only")
build(1005)
controls["Save"]:Click()
assert(settings.ignoredInteractVendorNPCs[27914] and settings.ignoredInteractVendorNPCs[444], "save must retain prior IDs and apply the current target")
equal(settings.ignoredInteractVendorNames[444], "Soft Vendor", "a safe current unit name must be cached with its ID")
equal(bindings, 1, "only save may refresh the secure interact binding")
equal(build(1005), -150, "save must release expanded layout height")

controls["Ignored Vendor NPCs"]:Click(); build(1005)
controls["NPC ID"].cfg.setValue("98765")
controls["Optional Name"].cfg.setValue("Manual Vendor")
controls["Add Vendor to Draft"]:Click()
assert(settings.ignoredInteractVendorNPCs[98765] == nil, "manual add must remain draft-only")
build(1005)
controls["NPC ID"].cfg.setValue("24680")
controls["Optional Name"].cfg.setValue("")
controls["Add Vendor to Draft"]:Click()
build(1005)
local unknownName = false
for _, object in ipairs(objects) do if object.text == "Unknown NPC" then unknownName = true end end
assert(unknownName, "unnamed manual IDs must visibly remain Unknown NPC")
controls["Cancel"]:Click()
assert(settings.ignoredInteractVendorNPCs[98765] == nil, "cancel must discard manual draft entries")
equal(build(1005), -150, "cancel must release expanded layout height")

settings.ignoredInteractVendorNPCs, settings.ignoredInteractVendorNames = {}, {}
controls["Ignored Vendor NPCs"]:Click()
local emptyExpanded = build(1005)
equal(emptyExpanded, -408, "empty expanded editor must reserve its empty-state row")
controls["Cancel"]:Click()
equal(build(1005), -150, "empty-state cancel must release its height")

settings.ignoredInteractVendorNPCs = { [101] = true, [202] = true, [303] = true }
controls["Ignored Vendor NPCs"]:Click()
local manyExpanded = build(640)
equal(manyExpanded, -488, "three rows must reserve one 40px row per saved vendor")
local sawHeader, sawRow, sawNativeFont = false, false, false
for _, object in ipairs(objects) do
    if object.text == "NPC NAME" and object.font == "EUI Expressway" then sawNativeFont = true end
    local columns = object._waffleColumns
    if columns then
        sawHeader = true
        assert(columns.name >= 20, "narrow table must retain a visible name column")
        equal(columns.name + columns.id + columns.remove + columns.gutter * 2, columns.total,
            "table columns must fit without overlap at narrow width")
        equal(columns.padding, 14, "table labels and controls must keep an inner border gutter")
        if object._waffleNPCID then sawRow = true end
    end
end
assert(sawHeader and sawRow and sawNativeFont, "expanded table must use aligned native-font header and row frames")

local remove
for _, object in ipairs(objects) do
    if object._waffleRemoveID == 202 then remove = object break end
end
assert(remove, "each saved vendor needs a Remove control")
remove:Click()
assert(settings.ignoredInteractVendorNPCs[202], "remove must remain draft-only until Save")
build(640)
controls["Save"]:Click()
assert(settings.ignoredInteractVendorNPCs[101] and settings.ignoredInteractVendorNPCs[303]
    and not settings.ignoredInteractVendorNPCs[202], "save must apply only the final draft rows")
equal(build(640), -150, "save must release many-row expansion height")

local savedBinding = bindings
controls["Ignored Vendor NPCs"]:Click(); build(640)
combat = true
controls["Current Soft Target"]:Click()
controls["Save"]:Click()
assert(settings.ignoredInteractVendorNPCs[101] and settings.ignoredInteractVendorNPCs[303]
    and not settings.ignoredInteractVendorNPCs[202] and not settings.ignoredInteractVendorNPCs[444],
    "combat actions must not alter saved IDs")
equal(bindings, savedBinding, "combat actions must not touch the secure binding")
combat = false

controls["NPC ID"].cfg.setValue("not-an-id")
controls["Add Vendor to Draft"]:Click()
equal(tooltip.owner, controls["Add Vendor to Draft"], "invalid manual ID must own its error tooltip")
local hidesBeforeLeave = tooltip.hides
controls["Add Vendor to Draft"]:Fire("OnLeave")
equal(tooltip.hides, hidesBeforeLeave + 1, "leaving the error control must clear its tooltip")

controls["NPC ID"].cfg.setValue("still-not-an-id")
controls["Add Vendor to Draft"]:Click()
local manualOwner = controls["Add Vendor to Draft"]
unitIDs.softinteract, unitIDs.target, unitIDs.npc = nil, nil, nil
controls["Current Soft Target"]:Click()
equal(tooltip.owner, controls["Current Soft Target"], "no target error must replace an older control tooltip")
local hidesBeforeOlderHide = tooltip.hides
manualOwner:Fire("OnHide")
equal(tooltip.hides, hidesBeforeOlderHide, "an older control must not clear a newer error tooltip")
controls["Current Soft Target"]:Fire("OnLeave")
equal(tooltip.hides, hidesBeforeOlderHide + 1, "current error owner must clear its tooltip on leave")

io.write("vendor options tests passed\n")
