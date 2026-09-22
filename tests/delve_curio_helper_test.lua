-- Run from the source folder: lua tests/delve_curio_helper_test.lua
local settings = { showDelveCurioHelper = true, autoEquipBestDelveCurios = false }
local frames = {}
local active = { [10] = 102, [20] = 202 }
local commits = 0
local combat = false

local frameMethods = {}
function frameMethods:SetSize(w, h) self.width, self.height = w, h end
function frameMethods:GetWidth() return self.width end
function frameMethods:GetHeight() return self.height end
function frameMethods:GetLeft() return self.left or 450 end
function frameMethods:GetRight() return self.right or 850 end
function frameMethods:GetBottom() return self.bottom or 200 end
function frameMethods:GetTop() return self.top or 600 end
function frameMethods:SetPoint(...) self.point = { ... } end
function frameMethods:ClearAllPoints() self.point = nil end
function frameMethods:SetAllPoints() end
function frameMethods:SetColorTexture(...) self.color = { ... } end
function frameMethods:SetTextColor(...) self.textColor = { ... } end
function frameMethods:SetTexture(value) self.texture = value end
function frameMethods:SetTexCoord(...) end
function frameMethods:SetFont(...) end
function frameMethods:SetJustifyH(...) end
function frameMethods:SetText(value) self.text = value end
function frameMethods:SetWidth(value) self.width = value end
function frameMethods:SetFrameStrata(...) end
function frameMethods:SetClampedToScreen(...) end
function frameMethods:EnableMouse(...) end
function frameMethods:SetEnabled(value) self.isEnabled = value end
function frameMethods:CreateTexture() return setmetatable({}, { __index = frameMethods }) end
function frameMethods:CreateFontString() return setmetatable({}, { __index = frameMethods }) end
function frameMethods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function frameMethods:HookScript(name, callback)
    self.hooks = self.hooks or {}
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
function frameMethods:RegisterEvent(...) end
function frameMethods:IsShown() return self.shown == true end
function frameMethods:Show()
    self.shown = true
    for _, callback in ipairs(self.hooks and self.hooks.OnShow or {}) do callback(self) end
end
function frameMethods:Hide()
    self.shown = false
    for _, callback in ipairs(self.hooks and self.hooks.OnHide or {}) do callback(self) end
end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent }, { __index = frameMethods })
    table.insert(frames, frame)
    return frame
end

UIParent = CreateFrame("Frame")
UIParent:SetWidth(1600)
UIParent.height = 900
DelvesCompanionConfigurationFrame = CreateFrame("Frame")
DelvesCompanionConfigurationFrame.playerCompanionID = 1
DelvesCompanionConfigurationFrame.left = 450
DelvesCompanionConfigurationFrame.right = 850

Enum = { CurioType = { Combat = 1, Utility = 2 } }
C_DelvesUI = {
    GetTraitTreeForCompanion = function() return 8 end,
    GetCurioNodeForCompanion = function(curioType) return curioType == 1 and 10 or 20 end,
}
C_Traits = {
    GetConfigIDByTreeID = function() return 9 end,
    GetNodeInfo = function(_, nodeID)
        return { entryIDs = nodeID == 10 and { 101, 102 } or { 201, 202 },
            activeEntry = { entryID = active[nodeID] } }
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
    GetDefinitionInfo = function(definitionID)
        return { spellID = ({ [101] = 1248876, [102] = 1000, [201] = 1305684, [202] = 2000 })[definitionID] }
    end,
    SetSelection = function(_, nodeID, entryID) active[nodeID] = entryID; return true end,
    IsReadyForCommit = function() return true end,
    CommitConfig = function() commits = commits + 1 end,
}
C_Spell = { GetSpellInfo = function(spellID) return { name = "Spell " .. spellID, iconID = spellID } end }
C_Timer = { After = function(_, callback) callback() end }
EllesmereUI = { GetFontPath = function() return "font.ttf" end }
STANDARD_TEXT_FONT = "font.ttf"
GetSpecialization = function() return 2 end
GetSpecializationInfo = function() return 70, "Retribution" end
UnitClass = function() return "Paladin" end
InCombatLockdown = function() return combat end

local addon = {
    GetSettings = function() return settings end,
    OptionsSectionIntro = function() end,
}
assert(loadfile(arg[1] or "WaffleHouse_Adventure.lua"))("WaffleHouse_EllesmereUI", addon)
local events = frames[#frames]
events.scripts.OnEvent(events, "PLAYER_LOGIN")
DelvesCompanionConfigurationFrame:Show()

local panel
for _, frame in ipairs(frames) do if frame.rows and frame.auto then panel = frame end end
assert(panel and panel:IsShown(), "helper must open with companion window")
assert(panel.context.text == "Retribution Paladin", "helper must show current specialization")
assert(panel.point[1] == "TOPLEFT" and panel.point[4] == 8,
    "helper must prefer a padded position beside companion window")

DelvesCompanionConfigurationFrame:Hide()
DelvesCompanionConfigurationFrame.left, DelvesCompanionConfigurationFrame.right = 500, 1400
DelvesCompanionConfigurationFrame:Show()
assert(panel.point[1] == "TOPRIGHT" and panel.point[4] == -8,
    "helper must switch sides when right side lacks room")
DelvesCompanionConfigurationFrame:Hide()
DelvesCompanionConfigurationFrame.left, DelvesCompanionConfigurationFrame.right = 300, 1300
DelvesCompanionConfigurationFrame.bottom = 300
DelvesCompanionConfigurationFrame:Show()
assert(panel.point[1] == "TOP" and panel.point[4] == 0 and panel.point[5] == -8,
    "helper must move below when neither side fits")
DelvesCompanionConfigurationFrame:Hide()
DelvesCompanionConfigurationFrame.bottom = 100
DelvesCompanionConfigurationFrame.top = 550
DelvesCompanionConfigurationFrame:Show()
assert(panel.point[1] == "BOTTOM" and panel.point[4] == 0 and panel.point[5] == 8,
    "helper must move above when below also lacks room")
DelvesCompanionConfigurationFrame:Hide()
DelvesCompanionConfigurationFrame.left, DelvesCompanionConfigurationFrame.right = 450, 850
DelvesCompanionConfigurationFrame:Show()
assert(commits == 0, "auto apply must remain opt-in")
assert(panel.rows.Combat.button.isEnabled and panel.rows.Utility.button.isEnabled,
    "both unlocked recommendations must be actionable")

panel.rows.Combat.button.scripts.OnClick()
assert(active[10] == 101 and active[20] == 202 and commits == 1,
    "a row Apply button must change only its curio and commit")
assert(not panel.rows.Combat.button.isEnabled, "equipped recommendation must no longer be actionable")

panel.auto.scripts.OnClick()
assert(settings.autoEquipBestDelveCurios == true, "panel checkbox must enable auto apply")
assert(active[20] == 201 and commits == 2, "enabling auto apply must equip remaining curio")

DelvesCompanionConfigurationFrame:Hide()
assert(not panel:IsShown(), "helper must close with companion window")
active[10], active[20] = 102, 202
DelvesCompanionConfigurationFrame:Show()
assert(panel:IsShown() and active[10] == 101 and active[20] == 201 and commits == 3,
    "auto apply must equip both recommendations on next open")

combat = true
DelvesCompanionConfigurationFrame:Hide()
active[10] = 102
DelvesCompanionConfigurationFrame:Show()
assert(commits == 3 and not panel.rows.Combat.button.isEnabled,
    "combat must block recommendation changes")
combat = false
DelvesCompanionConfigurationFrame:Hide()
settings.showDelveCurioHelper = false
DelvesCompanionConfigurationFrame:Show()
assert(not panel:IsShown(), "disabled helper must stay hidden")

print("Delve Curio Helper tests passed")
