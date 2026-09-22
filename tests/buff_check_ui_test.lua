-- Run from the source folder: lua tests/buff_check_ui_test.lua
-- Loads the real UI with an independent data model and a small frame API.
-- Coordinates verify containment; protected mutations fail while in combat.
local SOURCE = arg[1] or "WaffleHouse_BuffCheckUI.lua"
_G.unpack = table.unpack or unpack
local function eq(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local combat, grouped, secureDriver = false, true, false
local objects, timers, tickers, drivers, controls = {}, {}, {}, {}, {}
local framesCreated, attributeWrites, collects = 0, 0, 0
local invalidations = {}
local auraChecks, visibilityChecks = 0, 0
local auraRelevant, visibilityWatch, visibilityChanges = true, true, {}
local function protect(frame)
    if combat and not secureDriver and frame.kind ~= "FontString" and frame.kind ~= "Texture" then
        local ancestor = frame
        while ancestor do
            assert(not ancestor.protected, "protected frame changed in combat")
            ancestor = ancestor.parent
        end
    end
end
local Frame = {}
Frame.__index = Frame
local function object(kind, parent, template)
    local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, attributes = {},
        events = {}, shown = true, enabled = true, width = 0, height = 0 }, Frame)
    if parent then parent.children[#parent.children + 1] = f end
    objects[#objects + 1] = f
    if template and template:find("Secure") then
        local ancestor = f
        while ancestor and ancestor ~= UIParent do ancestor.protected = true; ancestor = ancestor.parent end
    end
    return f
end
function CreateFrame(kind, name, parent, template)
    local f = object(kind, parent, template)
    framesCreated = framesCreated + 1
    if name then _G[name] = f end
    return f
end
function Frame:SetSize(w, h) protect(self); assert(type(w) == "number" and type(h) == "number"); self.width, self.height = w, h end
function Frame:SetWidth(w) self:SetSize(w, self.height) end
function Frame:SetHeight(h) self:SetSize(self.width, h) end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetPoint(point, relative, relativePoint, x, y)
    protect(self)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point
    elseif relative == nil then relative, relativePoint, x, y = self.parent, point, 0, 0 end
    self.anchor = { point, relative, relativePoint or point, x or 0, y or 0 }
end
function Frame:ClearAllPoints() protect(self); self.anchor = nil end
local function fraction(point)
    local x = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local y = point:find("TOP") and 0 or point:find("BOTTOM") and 1 or 0.5
    return x, y
end
function Frame:GetLeft()
    if not self.anchor then return 0 end
    local a = self.anchor
    local ownX = fraction(a[1]); local otherX = fraction(a[3])
    return a[2]:GetLeft() + a[2]:GetWidth() * otherX + a[4] - self.width * ownX
end
function Frame:GetTop()
    if self == UIParent then return 1080 end
    if not self.anchor then return 1080 end
    local a = self.anchor
    local _, ownY = fraction(a[1]); local _, otherY = fraction(a[3])
    return a[2]:GetTop() - a[2]:GetHeight() * otherY + a[5] + self.height * ownY
end
function Frame:GetRight() return self:GetLeft() + self.width end
function Frame:GetBottom() return self:GetTop() - self.height end
function Frame:SetAllPoints() self:SetPoint("TOPLEFT"); self:SetSize(self.parent.width, self.parent.height) end
function Frame:SetShown(value) protect(self); self.shown = not not value end
function Frame:Show() self:SetShown(true) end
function Frame:Hide() self:SetShown(false) end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:SetEnabled(value) self.enabled = not not value end
function Frame:SetAttribute(key, value) protect(self); self.attributes[key] = value; attributeWrites = attributeWrites + 1 end
function Frame:GetAttribute(key) return self.attributes[key] end
function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:Fire(event, ...) if self.scripts[event] then self.scripts[event](self, ...) end end
function Frame:Click() if self.enabled and self:IsVisible() then self:Fire("OnClick") end end
function Frame:CreateFontString() return object("FontString", self) end
function Frame:CreateTexture() return object("Texture", self) end
function Frame:SetFont(_, size) self.height = size end
function Frame:SetText(text) self.text = text end
function Frame:SetHighlightTexture() self.highlight = object("Texture", self) end
function Frame:GetHighlightTexture() return self.highlight end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetTexture(value) self.texture = value end
for _, method in ipairs({ "SetTextColor", "SetJustifyH", "SetWordWrap", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "SetTexCoord", "SetShadowOffset",
    "SetVertexColor", "SetDesaturated", "SetAlpha", "SetOwner", "AddLine", "StartMoving", "StopMovingOrSizing" }) do Frame[method] = function() end end
UIParent = object("Frame"); UIParent:SetSize(1920, 1080)
GameTooltip = object("Frame", UIParent)
function InCombatLockdown() return combat end
function IsInGroup() return grouped end
function issecretvalue() return false end
function UnitIsUnit(unit, other) return unit == other or (unit == "raid1" and other == "player") end
function RegisterStateDriver(frame, state, expression) drivers[#drivers + 1] = { frame = frame, state = state, expression = expression } end
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end,
    NewTicker = function(delay, callback)
        local t = { delay = delay, callback = callback, cancelled = false }
        function t:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}
local function flush()
    local queued = timers; timers = {}
    for _, timer in ipairs(queued) do timer.callback() end
end
local function liveTickers()
    local count = 0
    for _, t in ipairs(tickers) do if not t.cancelled then count = count + 1 end end
    return count
end
local function event(name, ...)
    for _, f in ipairs(objects) do if f.events[name] then f:Fire("OnEvent", name, ...) end end
end
local function setCombat(value)
    combat = value
    for _, driver in ipairs(drivers) do
        -- Execute the actual registered secure snippet in its tiny environment.
        local snippet = driver.frame:GetAttribute("_onstate-" .. driver.state)
        secureDriver = true
        local env = { self = driver.frame, newstate = combat and "combat" or "peace" }
        if setfenv then local fn = assert(loadstring(snippet)); setfenv(fn, env); fn()
        else assert(load(snippet, "state-driver", "t", env))() end
        secureDriver = false
    end
    event(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local settings = { enabled = true, groupedOnly = true, hideReady = false, collapsed = false }
local assignments, roster, state = {}, {}, { groups = {}, targets = {}, size = 40, skipped = 0 }
local B = { groupDefs = {}, targetDefs = {} }
function B.GetSettings() return settings end
function B.GetAssignments() return assignments end
function B.GetRoster() return roster end
function B.Invalidate(unit) invalidations[#invalidations + 1] = unit or "all" end
function B.Collect(incremental) eq(incremental, true, "UI must request the incremental model state"); collects = collects + 1; return state end
function B.AuraUpdateRelevant(unit, updateInfo) auraChecks = auraChecks + 1; return auraRelevant end
function B.CheckVisibility() visibilityChecks = visibilityChecks + 1; return visibilityChanges end
function B.HasVisibilityWatch() return visibilityWatch end
function B.SpellName(def) return def.name end
C_Spell = { GetSpellTexture = function(id) return id end }
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
SlashCmdList = {}
for i = 1, 40 do roster[i] = { unit = "raid" .. i, guid = "guid-" .. i, name = ("Member %02d"):format(i), class = "PRIEST", role = "DAMAGER" } end
for i, id in ipairs({ 1126, 6673, 21562, 1459, 364342, 462854 }) do
    local def = { key = "group" .. i, name = "Group buff " .. i, class = "PRIEST", spellID = id }
    B.groupDefs[i] = def
    state.groups[i] = { def = def, missing = { roster[1] }, covered = 39, eligible = 40, unknown = 0, castable = i == 1 }
end
for i, id in ipairs({ 53563, 156910, 369459, 360827, 20707, 974, 408233 }) do
    local def = { key = "target" .. i, name = "Target buff " .. i, spellID = id }
    B.targetDefs[i] = def
    state.targets[i] = { def = def, member = roster[i], status = "missing", castable = true }
end
EllesmereUI = { Widgets = {} }
function EllesmereUI.Widgets:SectionHeader() return object("Frame", UIParent), 24 end
function EllesmereUI.Widgets:DualRow(parent, y, left, right)
    local row = object("Frame", parent)
    for _, spec in ipairs({ left, right }) do
        controls[spec.text] = spec
        if spec.type == "labeledButton" then
            local control = object("Button", row)
            spec.control = control
            row[spec == left and "_leftRegion" or "_rightRegion"] = { _control = control }
        end
    end
    return row, 40
end
local addon = { BuffCheck = B }
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
event("PLAYER_LOGIN"); flush()
local panel = assert(WaffleHouseBuffCheck)
local picker
for _, child in ipairs(panel.children) do if child.rows and #child.rows == 8 then picker = child end end
assert(picker, "assignment picker created")
local function inside(child, parent, gutter, message)
    gutter = gutter or 0
    assert(child:GetLeft() >= parent:GetLeft() + gutter, message .. " left overflow")
    assert(child:GetRight() <= parent:GetRight() - gutter, message .. " right overflow")
    assert(child:GetTop() <= parent:GetTop() - gutter, message .. " top overflow")
    assert(child:GetBottom() >= parent:GetBottom() + gutter, message .. " bottom overflow")
end
local function verifyPanelBounds()
    for _, icon in ipairs(panel.groupIcons) do if icon:IsVisible() then inside(icon, panel, 4, "group icon") end end
    local last
    for _, row in ipairs(panel.rows) do
        if row:IsVisible() then
            inside(row, panel, 4, "assignment row")
            inside(row.cast, row, 0, "assignment action")
            assert(row.select:GetRight() <= row.cast:GetLeft() - 8, "name and action need gutter")
            if last then assert(last:GetBottom() >= row:GetTop(), "assignment rows overlap") end
            last = row
        end
    end
    if panel.body:IsShown() then
        inside(panel.footer, panel, 4, "footer")
        if last then assert(last:GetBottom() >= panel.footer:GetTop() + 4, "footer crowds rows") end
    end
end
eq(#panel.groupIcons, 6, "six group buff slots")
eq(#panel.rows, 4, "bounded assignment row allocation")
eq(liveTickers(), 1, "one reconciliation timer")
eq(tickers[1].delay, 5, "low-frequency reconciliation")
eq(drivers[1].expression, "[combat] combat; peace", "secure combat state condition")
verifyPanelBounds()
for i = 2, 6 do assert(panel.groupIcons[i]:GetLeft() - panel.groupIcons[i - 1]:GetRight() >= 8, "group icon gutter") end
eq(panel.groupIcons[1]:GetAttribute("spell"), 1126, "group spell assignment")
eq(panel.groupIcons[1]:GetAttribute("unit"), "player", "group buffs cast on self")
eq(panel.groupIcons[2]:GetAttribute("type1"), nil, "other class coverage cannot cast")
eq(panel.rows[1].cast:GetAttribute("unit"), "raid1", "target action unit")
eq(panel.rows[1].cast.clicks[1], "AnyDown", "keydown supported")
eq(panel.rows[1].cast.clicks[2], "AnyUp", "keyup supported")

eq(panel.close.label.text, "×", "official Buff Check panel has a close character")
assert(panel.close:GetLeft() >= panel.collapse:GetRight() + 2, "close must sit beside, not overlap, minimize")

local allocations = framesCreated
panel.next:Click()
eq(panel.rows[1].entry.def, B.targetDefs[5], "second target page")
eq(panel.rows[4]:IsShown(), false, "unused fourth row hidden")
eq(panel.next.enabled, false, "end page disables next")
verifyPanelBounds()
panel.previous:Click()
eq(panel.rows[1].entry.def, B.targetDefs[1], "first target page restored")
eq(framesCreated, allocations, "pagination reuses frames")

panel.rows[1].select:Click()
eq(picker.counter.text, "1 / 5", "40 recipients split into five pages")
local seen = {}
for p = 1, 5 do
    for _, row in ipairs(picker.rows) do
        assert(row:IsVisible(), "eight picker rows visible")
        inside(row, picker, 10, "picker row")
        assert(not seen[row.member.guid], "picker repeats recipient")
        seen[row.member.guid] = true
    end
    inside(picker.previous, picker, 10, "picker previous")
    inside(picker.next, picker, 10, "picker next")
    assert(picker.rows[8]:GetBottom() >= picker.next:GetTop() + 8, "picker footer gutter")
    picker.next:Click()
end
eq(picker.counter.text, "5 / 5", "picker end page bounded")
picker.rows[8]:Click()
eq(assignments.target1, "guid-40", "assignment stores stable GUID")
eq(picker:IsShown(), false, "selection closes picker")
invalidations = {}
panel.rows[1].select:Click(); picker.clear:Click()
eq(assignments.target1, nil, "clear removes assignment")
eq(#invalidations, 1, "clearing a recipient invalidates cached target coverage")
eq(invalidations[1], "all", "clearing a recipient forces a full assignment refresh")

assignments.target2 = "guid-40"
panel.rows[1].select:Click()
for p = 1, 5 do
    for _, row in ipairs(picker.rows) do if row:IsShown() then assert(row.member.guid ~= "guid-40", "beacons cannot share recipient") end end
    picker.next:Click()
end
picker.close:Click(); assignments.target2 = nil
B.targetDefs[1].noSelf = true; B.targetDefs[1].healerOnly = true
roster[1].role, roster[2].role = "HEALER", "HEALER"
panel.rows[1].select:Click()
eq(picker.rows[1].member.guid, "guid-2", "healer-only and no-self filtering")
eq(picker.rows[2]:IsShown(), false, "ineligible recipients omitted")
picker.close:Click(); B.targetDefs[1].noSelf, B.targetDefs[1].healerOnly = nil, nil
local savedGUID = roster[1].guid
roster[1].guid = nil
panel.rows[1].select:Click()
for _, row in ipairs(picker.rows) do if row:IsShown() then assert(row.member.guid, "unidentifiable recipients cannot be assigned") end end
picker.close:Click(); roster[1].guid = savedGUID

panel.collapse:Click()
eq(panel:GetHeight(), 32, "collapsed panel only reserves header")
eq(panel.body:IsShown(), false, "collapsed content hidden")
panel.collapse:Click(); verifyPanelBounds()
eq(settings.collapsed, false, "expanded setting restored")

SlashCmdList.WAFFLEHOUSEBUFFS("preview")
eq(panel.summary.text, "Preview · 40 players", "sample raid preview")
local previewCollects, previewInvalidations = collects, #invalidations
for _ = 1, 20 do event("UNIT_AURA", "raid2", { isFullUpdate = false }) end
eq(#timers, 0, "preview aura updates must queue no model work")
eq(collects, previewCollects, "preview aura updates must not collect")
eq(#invalidations, previewInvalidations, "preview aura updates must not invalidate")
eq(liveTickers(), 0, "preview cancels the visibility ticker")
for _, icon in ipairs(panel.groupIcons) do eq(icon:GetAttribute("type1"), nil, "preview group actions disabled") end
for _, row in ipairs(panel.rows) do eq(row.cast:GetAttribute("type1"), nil, "preview target actions disabled") end
panel.rows[1].select:Click(); eq(picker:IsShown(), false, "preview cannot change assignments")
verifyPanelBounds()
panel.close:Click()
eq(panel:IsShown(), false, "close hides the official preview panel")
eq(picker:IsShown(), false, "close also hides any recipient picker")
SlashCmdList.WAFFLEHOUSEBUFFS("preview")
eq(panel.summary.text, "Preview · 40 players", "preview reopens after a close")
SlashCmdList.WAFFLEHOUSEBUFFS("preview")
eq(panel.rows[1].cast:GetAttribute("unit"), "raid1", "real assignment restored after preview")

local before = collects
invalidations = {}
auraRelevant = false
for _ = 1, 100 do event("UNIT_AURA", "raid2", { isFullUpdate = false }) end
eq(#timers, 0, "irrelevant aura bursts must queue no work")
eq(collects, before, "irrelevant aura bursts must not collect")
eq(#invalidations, 0, "irrelevant aura bursts must not invalidate")
eq(auraChecks, 100, "each distinct irrelevant aura update is filtered by the model")

auraRelevant = true
for _ = 1, 10 do event("UNIT_AURA", "raid2", { isFullUpdate = false }) end
eq(#timers, 1, "same-unit aura burst coalesces")
eq(timers[1].delay, 0.2, "aura updates debounced")
eq(collects, before, "aura events do not immediately rescan")
flush(); eq(collects, before + 1, "one collection per same-unit burst")
eq(#invalidations, 1, "same-unit burst invalidates once")
eq(invalidations[1], "raid2", "same-unit invalidation remains specific")

invalidations = {}
event("UNIT_AURA", "raid2", { isFullUpdate = false })
event("UNIT_AURA", "raid3", { isFullUpdate = false })
event("UNIT_AURA", "raid4", { isFullUpdate = false })
event("UNIT_AURA", "raid2", { isFullUpdate = false })
eq(#timers, 1, "multi-unit aura updates share one debounce")
flush(); eq(collects, before + 2, "multi-unit burst still collects once")
local merged = {}; for _, unit in ipairs(invalidations) do merged[unit] = true end
eq(#invalidations, 3, "multi-unit burst invalidates each affected unit once")
assert(merged.raid2 and merged.raid3 and merged.raid4, "multi-unit invalidations retain every changed token")

invalidations = {}
event("UNIT_NAME_UPDATE", "raid2")
eq(#timers, 1, "name updates request a full cached-roster refresh")
flush(); eq(#invalidations, 1, "name refresh invalidates the cached roster once")
eq(invalidations[1], "all", "name refresh uses full invalidation")
invalidations = {}
event("PLAYER_ROLES_ASSIGNED")
eq(#timers, 1, "role updates request a full cached-roster refresh")
flush(); eq(#invalidations, 1, "role refresh invalidates the cached roster once")
eq(invalidations[1], "all", "role refresh uses full invalidation")

visibilityChanges, invalidations = {}, {}
local visibilityBaseline, collectBaseline = visibilityChecks, collects
tickers[#tickers].callback()
eq(visibilityChecks, visibilityBaseline + 1, "visibility ticker probes cached availability")
eq(#timers, 0, "unchanged visibility probe queues no refresh")
eq(collects, collectBaseline, "unchanged visibility probe does not collect")
visibilityChanges = { raid4 = true }
tickers[#tickers].callback()
eq(#timers, 1, "changed visibility queues the affected member")
flush(); eq(#invalidations, 1, "changed visibility invalidates only one member")
eq(invalidations[1], "raid4", "changed visibility keeps its unit scope")
visibilityChanges = {}
local invalidated = #invalidations
event("UNIT_AURA", "target"); event("UNIT_AURA", "nameplate1"); event("UNIT_AURA", nil)
eq(#invalidations, invalidated, "unrelated unit events ignored")

invalidations = {}
event("UNIT_AURA", "raid2", { isFullUpdate = false }) -- Queued OOC work must be harmless after combat begins.
local queuedCollects, queuedInvalidations = collects, #invalidations
local writes = attributeWrites
setCombat(true)
eq(panel:IsShown(), false, "driver hides during combat")
eq(liveTickers(), 0, "no reconciliation ticker in combat")
flush()
eq(collects, queuedCollects, "cancelled aura callback must not collect after combat starts")
eq(#invalidations, queuedInvalidations, "cancelled aura callback must not invalidate after combat starts")
addon.RefreshBuffCheck(); event("UNIT_AURA", "raid3")
panel.collapse:Fire("OnClick")
eq(attributeWrites, writes, "protected attributes untouched during combat")
eq(settings.collapsed, false, "combat control gated")
setCombat(false)
eq(panel:IsShown(), false, "driver does not expose stale slots on combat exit")
state.targets[1].member = roster[9]
flush()
eq(panel:IsShown(), true, "fresh refresh shows panel")
eq(panel.rows[1].cast:GetAttribute("unit"), "raid9", "fresh target before visibility")
eq(liveTickers(), 1, "ticker restored outside combat")
for _, rosterEvent in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    invalidations = {}
    panel.rows[1].select:Click()
    event(rosterEvent)
    eq(panel:IsShown(), false, "roster change immediately hides stale casting targets")
    eq(picker:IsShown(), false, "roster change closes stale recipient list")
    state.targets[1].member = roster[10]
    flush()
    eq(#invalidations, 1, "roster/world transition refreshes the cached roster once")
    eq(invalidations[1], "all", "roster/world transition uses full invalidation")
    eq(panel:IsShown(), true, "fresh roster refresh shows panel")
    eq(panel.rows[1].cast:GetAttribute("unit"), "raid10", "roster change installs current unit")
end

addon.BuildBuffCheckPage(object("Frame", UIParent), 0)
assert(controls["Hide Ready Buffs"] and controls["Situations"],
    "Hide Ready Buffs and Situations must share the same options row")
assert(controls[""] == nil, "Situations must not create an empty placeholder control")
settings.groupedOnly, settings.visibilitySeeded, settings.enabled = nil, nil, false
controls["Enable Buff Check"].setValue(true)
eq(settings.groupedOnly, true, "first enable seeds only-show-in-group")
eq(settings.visibilitySeeded, true, "first enable records the one-time seed")
controls["Only Show in a Group"].setValue(false)
controls["Enable Buff Check"].setValue(false)
controls["Enable Buff Check"].setValue(true)
eq(settings.groupedOnly, false, "later enables never overwrite a visibility choice")
controls["Only Show in a Group"].setValue(true)
controls["Enable Buff Check"].setValue(false)
eq(panel:IsShown(), false, "disable hides panel")
eq(liveTickers(), 0, "disable cancels reconciliation")
local excludedCollects, excludedInvalidations = collects, #invalidations
event("UNIT_AURA", "raid1"); eq(#timers, 0, "disabled aura events ignored")
eq(collects, excludedCollects, "disabled aura events do not collect")
eq(#invalidations, excludedInvalidations, "disabled aura events do not invalidate")
controls["Enable Buff Check"].setValue(true)
grouped = false; controls["Only Show in a Group"].setValue(true)
eq(panel:IsShown(), false, "solo grouped-only hidden")
eq(liveTickers(), 0, "no ticker while grouped-only solo")
excludedCollects, excludedInvalidations = collects, #invalidations
event("UNIT_AURA", "player"); eq(#timers, 0, "grouped-only solo aura events ignored")
eq(collects, excludedCollects, "grouped-only solo aura events do not collect")
eq(#invalidations, excludedInvalidations, "grouped-only solo aura events do not invalidate")
controls["Only Show in a Group"].setValue(false)
eq(panel:IsShown(), true, "solo setting shows panel")
settings.position = { x = 200, y = -300 }
controls["Panel Position"].control:Click()
eq(settings.position, nil, "reset clears saved position")
eq(panel:GetLeft(), 30, "reset horizontal position")
eq(panel:GetTop() - UIParent:GetHeight(), -240, "reset vertical position")
controls["Panel Preview"].control:Click()
setCombat(true)
local combatPosition = settings.position
controls["Panel Position"].control:Fire("OnClick")
controls["Panel Preview"].control:Fire("OnClick")
eq(settings.position, combatPosition, "position reset blocked in combat")
eq(panel:IsShown(), false, "preview control cannot expose panel in combat")
setCombat(false); flush()
eq(panel.summary.text, "Preview · 40 players", "settings preview button")
controls["Panel Preview"].control:Click()

for _, entry in ipairs(state.groups) do entry.missing = {} end
for _, entry in ipairs(state.targets) do entry.status = "ready" end
-- Keep the panel open for the row-level Hide Ready assertions. The runtime
-- default intentionally hides the whole panel once no attention is needed.
settings.onlyWhenNeeded = false
controls["Hide Ready Buffs"].setValue(true)
for _, icon in ipairs(panel.groupIcons) do eq(icon:IsShown(), false, "ready group hidden") end
for _, row in ipairs(panel.rows) do eq(row:IsShown(), false, "ready target hidden") end
eq(panel.footer.text, "All set", "empty ready state")
verifyPanelBounds()
controls["Hide Ready Buffs"].setValue(false)
eq(panel.footer.text, "All set", "all-ready visible assignments have no selection prompt")
verifyPanelBounds()
settings.onlyWhenNeeded = true

SlashCmdList.WAFFLEHOUSEBUFFS("off")
eq(liveTickers(), 0, "slash disable cancels ticker")
eq(panel:IsShown(), false, "slash disable hides panel")

-- Smoke-test the actual data model and UI together, especially stable-GUID
-- assignments after raid slots change.  Only engine functions are mocked.
objects, timers, tickers, drivers = { UIParent, GameTooltip }, {}, {}, {}
grouped = true
local integrationSettings = { buffCheck = { enabled = true, hideReady = false, groupedOnly = true } }
local integration = { GetSettings = function() return integrationSettings end }
local function member(unit)
    if unit == "player" then return roster[1] end
    local index = unit:match("^raid(%d+)$")
    return index and roster[tonumber(index)]
end
for i, class in ipairs({ "SHAMAN", "PRIEST", "DRUID", "MAGE", "WARRIOR", "EVOKER" }) do roster[i].class = class end
function UnitGUID(unit) local m = member(unit); return m and m.guid end
function UnitName(unit) local m = member(unit); return m and m.name end
function UnitFullName(unit) return UnitName(unit), "" end
function UnitClass(unit) local m = member(unit); return m and m.class, m and m.class end
function UnitGroupRolesAssigned(unit) local m = member(unit); return m and m.role end
function UnitExists(unit) return member(unit) ~= nil end
UnitIsVisible, UnitIsConnected = UnitExists, UnitExists
function UnitIsDeadOrGhost() return false end
function IsInRaid() return true end
function GetNumGroupMembers() return 40 end
function GetNumSubgroupMembers() return 0 end
function IsPlayerSpell(id) return id == 974 or id == 462854 end
IsSpellKnown = IsPlayerSpell
C_Spell.GetSpellName = function(id) return "Spell " .. id end
C_Secrets = { ShouldSpellAuraBeSecret = function() return false end, ShouldAurasBeSecret = function() return false end }
C_UnitAuras = { GetUnitAuraBySpellID = function() return nil end, GetPlayerAuraBySpellID = function() return nil end }
local modelSource = SOURCE:gsub("WaffleHouse_BuffCheckUI%.lua$", "WaffleHouse_BuffCheck.lua")
assert(modelSource ~= SOURCE, "cannot determine model path from UI source")
assert(loadfile(modelSource))("WaffleHouse_EllesmereUI", integration)
integration.BuffCheck.GetAssignments().earth_shield = roster[40].guid
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", integration)
event("PLAYER_LOGIN"); flush()
local realPanel = WaffleHouseBuffCheck
eq(realPanel.summary.text, "40 players", "real model roster consumed by UI")
eq(realPanel.rows[1].cast:GetAttribute("unit"), "raid40", "real model assignment resolves recipient")
eq(realPanel.rows[1].cast:GetAttribute("spell"), 974, "real model Earth Shield action")
for _, icon in ipairs(realPanel.groupIcons) do
    eq(icon:IsShown(), true, "all six provider buffs shown")
    eq(icon.count.text, "40", "real missing raid count")
end
roster[2].guid, roster[40].guid = roster[40].guid, roster[2].guid
roster[2].name, roster[40].name = roster[40].name, roster[2].name
event("GROUP_ROSTER_UPDATE")
eq(realPanel:IsShown(), false, "real model stale raid slot shielded immediately")
flush()
eq(realPanel.rows[1].cast:GetAttribute("unit"), "raid2", "real model follows GUID across raid reorder")

-- Feed the real model complete aura snapshots, including instance IDs. With
-- only-when-needed enabled, full tracked group coverage and the assigned
-- Earth Shield must hide the panel without a polling expiry timer.
local auraReads, liveAuras, nextInstance = {}, {}, 1000
for index = 1, 40 do
    local unit = "raid" .. index
    liveAuras[unit] = {}
    for _, def in ipairs(integration.BuffCheck.groupDefs) do
        nextInstance = nextInstance + 1
        liveAuras[unit][def.auraIDs[1]] = { auraInstanceID = nextInstance }
    end
end
local earthShield
for _, def in ipairs(integration.BuffCheck.targetDefs) do
    if def.key == "earth_shield" then earthShield = def; break end
end
assert(earthShield, "real model must expose Earth Shield")
nextInstance = nextInstance + 1
liveAuras.raid2[earthShield.auraIDs[1]] = { auraInstanceID = nextInstance, isFromPlayerOrPlayerPet = true }
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, spellID)
        auraReads[unit] = (auraReads[unit] or 0) + 1
        return liveAuras[unit] and liveAuras[unit][spellID] or nil
    end,
}
integration.RefreshBuffCheck()
eq(realPanel:IsShown(), false, "complete group coverage and assigned Earth Shield hide only-when-needed")

local missingDef = integration.BuffCheck.groupDefs[1]
local expiredInstance = liveAuras.raid5[missingDef.auraIDs[1]].auraInstanceID
liveAuras.raid5[missingDef.auraIDs[1]] = nil
local untouchedReads = auraReads.raid6 or 0
event("UNIT_AURA", "raid5", { isFullUpdate = false, removedAuraInstanceIDs = { expiredInstance } })
eq(#timers, 1, "tracked sparse aura removal queues one refresh")
flush()
eq(realPanel:IsShown(), true, "tracked aura expiration reopens the needed panel")
local missingIcon
for _, icon in ipairs(realPanel.groupIcons) do if icon.entry and icon.entry.def == missingDef then missingIcon = icon; break end end
assert(missingIcon, "expired tracked buff remains represented in the group panel")
eq(missingIcon.count.text, "1", "sparse removal reports one missing group member")
eq(auraReads.raid6 or 0, untouchedReads, "untouched raid member aura data is not requeried by sparse removal")

local groupCount = 40
function GetNumGroupMembers() return groupCount end
groupCount = 39
event("GROUP_ROSTER_UPDATE")
eq(realPanel:IsShown(), false, "group shrink hides old secured raid targets immediately")
flush()
eq(realPanel.summary.text, "39 players", "real model rebuilds its cached roster after group shrink")
groupCount = 40
event("GROUP_ROSTER_UPDATE")
eq(realPanel:IsShown(), false, "group join also hides old secured raid targets immediately")
flush()
eq(realPanel.summary.text, "40 players", "real model rebuilds its cached roster after group join")
setCombat(true); eq(realPanel:IsShown(), false, "integrated panel hides in combat")
eq(liveTickers(), 0, "integrated ticker stops in combat")
setCombat(false); eq(realPanel:IsShown(), false, "integrated panel waits for refresh")
flush(); eq(realPanel:IsShown(), true, "integrated panel resumes after refresh")
print("PASS: buff check UI layout, pagination, assignments, secure lifecycle, event coalescing, settings and real-model integration")
