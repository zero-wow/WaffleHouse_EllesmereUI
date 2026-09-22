-- Run from the source folder:
-- lua tests/soiree_ui_test.lua WaffleHouse_SoireeRules.lua WaffleHouse_Soiree.lua
local RULES_SOURCE = arg[1] or "WaffleHouse_SoireeRules.lua"
local UI_SOURCE = arg[2] or "WaffleHouse_Soiree.lua"

unpack = table.unpack
local frames, sentResponses = {}, 0
local combat, currentChoice = false, nil

local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetScale(scale) self.scale = scale end
function methods:SetPoint(...)
    self.point = { ... }; self.points = self.points or {}; table.insert(self.points, self.point)
end
function methods:ClearAllPoints() self.point = nil; self.points = {} end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetFont(...) self.font = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetText(value) self.text = value end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:IsEnabled() return self.enabled ~= false end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown == true end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:HookScript(name, callback)
    self.hooks = self.hooks or {}; self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
local function invoke(frame, name)
    if frame.scripts and frame.scripts[name] then frame.scripts[name](frame) end
    for _, callback in ipairs(frame.hooks and frame.hooks[name] or {}) do callback(frame) end
end
function methods:Show() if not self.shown then self.shown = true; invoke(self, "OnShow") end end
function methods:Hide() if self.shown then self.shown = false; invoke(self, "OnHide") end end
function methods:CreateTexture()
    local texture = setmetatable({ parent = self, kind = "Texture" }, { __index = methods })
    table.insert(frames, texture)
    return texture
end
function methods:CreateFontString()
    local label = setmetatable({ parent = self, kind = "FontString" }, { __index = methods })
    table.insert(frames, label)
    return label
end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, enabled = true, shown = true,
        mouse = kind == "Button" }, { __index = methods })
    table.insert(frames, frame)
    if name then _G[name] = frame end
    return frame
end

_G = _G or _ENV
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
UISpecialFrames = {}
SlashCmdList = {}
STANDARD_TEXT_FONT = "font.ttf"
local tooltipText, tooltipAnchor, tooltipOptions
EllesmereUI = {
    EXPRESSWAY = "native-eui-font.ttf",
    GetFontPath = function() return "wrong-game-font.ttf" end,
    ShowWidgetTooltip = function(anchor, text, opts) tooltipAnchor, tooltipText, tooltipOptions = anchor, text, opts end,
    HideWidgetTooltip = function() tooltipAnchor, tooltipText = nil, nil end,
}
InCombatLockdown = function() return combat end
C_Timer = { After = function(_, callback) callback() end }
C_Reputation = { GetFactionDataByID = function(id)
    return ({ [2711] = { name = "Magisters" }, [2712] = { name = "Blood Knights" },
        [2713] = { name = "Farstriders" }, [2714] = { name = "Shades of the Row" } })[id]
end }
C_PlayerChoice = {
    GetCurrentPlayerChoiceInfo = function() return currentChoice end,
    SendPlayerChoiceResponse = function() sentResponses = sentResponses + 1 end,
}
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    GetOwner = function(self) return self.owner end,
    ClearLines = function() end, AddLine = function() end, AddDoubleLine = function() end,
    Show = function(self) self.shown = true end, Hide = function(self) self.shown = false; self.owner = nil end,
}
hooksecurefunc = function(host, method, callback)
    host.secureHooks = host.secureHooks or {}; host.secureHooks[method] = host.secureHooks[method] or {}
    table.insert(host.secureHooks[method], callback)
end
local function runSecure(host, method)
    for _, callback in ipairs(host.secureHooks and host.secureHooks[method] or {}) do callback() end
end

local root = { soireeHelper = { enabled = true, askEachVisit = false } }
local addon = { GetSettings = function() return root end }
assert(loadfile(RULES_SOURCE))("WaffleHouse_EllesmereUI", addon)
assert(loadfile(UI_SOURCE))("WaffleHouse_EllesmereUI", addon)

local function iter(list)
    local index = 0
    return function() index = index + 1; return list[index] end
end

local function choiceOption(id, factionID, favor)
    local names = { [2711] = "Magisters", [2712] = "Blood Knights", [2713] = "Farstriders", [2714] = "Shades of the Row" }
    return {
        id = id, header = "Guest " .. id, subHeader = names[factionID],
        description = "+50 " .. names[factionID], buttons = { { id = id + 1000 } },
        rewardInfo = { itemRewards = favor and { { itemId = 238987, quantity = favor } } or {},
            repRewards = { { factionId = factionID, quantity = 50 } } },
    }
end

local options = { choiceOption(101, 2711), choiceOption(102, 2712), choiceOption(103, 2713, 1), choiceOption(104, 2714) }
currentChoice = { options = options }

local host = CreateFrame("Frame", "PlayerChoiceFrame", UIParent)
host:SetFrameLevel(50)
host.optionPools = { active = {}, EnumerateActive = function(pool) return iter(pool.active) end }
host.SetupOptions = function(self) runSecure(self, "SetupOptions") end
host.SetupFrame = function(self) runSecure(self, "SetupFrame") end

local function makeOption(optionInfo, artWidth)
    local option = CreateFrame("Frame", nil, host)
    option:SetFrameLevel(60)
    option.optionInfo = optionInfo
    option.Artwork = CreateFrame("Frame", nil, option)
    option.Artwork:SetSize(artWidth or 180, 150)
    option.Artwork:Show()
    option.OptionButtonsContainer = { buttonFramePool = { active = {} } }
    function option.OptionButtonsContainer.buttonFramePool:EnumerateActive() return iter(self.active) end
    local button = CreateFrame("Button", nil, option)
    button:SetFrameLevel(64); button:Show(); button.enabled = true
    option.OptionButtonsContainer.buttonFramePool.active[1] = { Button = button }
    return option, button
end

local optionFrames, nativeButtons = {}, {}
for index, optionInfo in ipairs(options) do
    optionFrames[index], nativeButtons[index] = makeOption(optionInfo)
    host.optionPools.active[index] = optionFrames[index]
end

local events
for _, frame in ipairs(frames) do
    if frame.events and frame.events.PLAYER_LOGIN then events = frame end
end
assert(events and events.scripts.OnEvent, "Soiree event frame must register its lifecycle events")
local function event(name, value) events.scripts.OnEvent(events, name, value) end
local function directChildren(parent)
    local result = {}
    for _, frame in ipairs(frames) do if frame.parent == parent then result[#result + 1] = frame end end
    return result
end
local function overlayFor(option)
    for _, frame in ipairs(directChildren(option)) do if frame.badge and frame.edge then return frame end end
end
local function hasPoint(frame, point, relative, x, y)
    for _, anchor in ipairs(frame.points or {}) do
        if anchor[1] == point and anchor[2] == relative and anchor[4] == x and anchor[5] == y then return true end
    end
end
local function clickByText(parent, label)
    for _, frame in ipairs(directChildren(parent)) do
        if frame.kind == "Button" and frame.label and frame.label.text == label then
            assert(frame.scripts.OnClick, "choice button must be clickable")
            frame.scripts.OnClick(frame)
            return
        end
    end
    error("missing button: " .. label)
end

-- The native frame opens first, then the helper chooses a remembered focus without selecting a response.
event("PLAYER_LOGIN")
host:Show()
local chooser = _G.WaffleHouseSoireeFocus
assert(chooser and chooser:IsShown(), "first invitation open must prompt for a focus")
assert(chooser.width == 548 and chooser.height == 532 and chooser.scale == 1,
    "chooser must use its intended desktop dimensions")
assert(root.soireeHelper.askEachVisit == true and root.soireeHelper.stylePreviewRevision == 1,
    "styling migration must reset an existing false preference to show every visit")
assert(#chooser.choices == 5 and chooser.choices[1].recommended and chooser.choices[1].status.text == "RECOMMENDED",
    "current unique Favor winner must highlight the useful default focus")
assert(chooser.choices[1].detail.text:find("Farstriders", 1, true), "recommendation must explain which live faction supplies the bonus")
local seenCopy = {}
local previousBottom = 108
for _, row in ipairs(chooser.choices) do
    assert(row.label.font[1] == EllesmereUI.EXPRESSWAY, "chooser must use native EUI typography")
    assert(row.detail.text ~= "" and not seenCopy[row.detail.text], "each goal needs distinct flavor")
    seenCopy[row.detail.text] = true
    local x, top = row.point[2], -row.point[3]
    assert(x >= 24 and x + row.width <= chooser.width - 24, "choice row must stay inside horizontal gutters")
    assert(top >= previousBottom + 6 and top + row.height <= 442, "choice rows must clear one another and footer divider")
    previousBottom = top + row.height
    local infoLeft = row.width + row.info.point[2] - row.info.width
    local infoTop = row.height - row.info.point[3] - row.info.height
    assert(row.detail.point[2] + row.detail.width <= infoLeft - 12, "description must clear the info hit target")
    assert(-row.status.point[3] + row.status.height <= infoTop - 4, "status text must clear info button border")
end
local infoButton = chooser.choices[2].info
invoke(infoButton, "OnEnter")
assert(tooltipAnchor == infoButton and tooltipText:find("Magisters", 1, true)
    and tooltipText:find("%+50") and tooltipOptions.justify == "LEFT", "info hover must use native EUI tooltip with live tradeoffs")
invoke(infoButton, "OnClick")
invoke(infoButton, "OnLeave")
assert(tooltipAnchor == infoButton, "clicking info must keep details visible after leaving")
invoke(infoButton, "OnClick")
assert(tooltipAnchor == nil, "clicking pinned info again must dismiss details")
assert(sentResponses == 0, "helper must never submit a PlayerChoice response")
clickByText(chooser, "Extra Favor")
assert(root.soireeHelper.focus == "favor" and not chooser:IsShown(), "chosen focus must be saved and dismiss the chooser")
assert(sentResponses == 0, "saving focus must not choose an invitation")

-- Normal PlayerChoice cards all receive a hover badge, while only the recommended card and its button use the EUI accent.
for index, option in ipairs(optionFrames) do
    local overlay = assert(overlayFor(option), "normal card " .. index .. " must receive an info overlay")
    assert(overlay:IsShown() and overlay.badge:IsShown(), "info badge must remain visible")
    assert(overlay.badge.height == 36 and hasPoint(overlay.badge, "BOTTOMLEFT", option.Artwork, 8, 8),
        "portrait badge must stay inside the artwork with an 8px gutter")
    assert(hasPoint(overlay.badge, "BOTTOMRIGHT", option.Artwork, -8, 8),
        "portrait badge must anchor to the native art, not the text or response")
    if index == 3 then
        assert(overlay.edge:IsShown() and nativeButtons[index]:GetFrameLevel() < 75,
            "recommended card must receive the whole-card accent edge and elevated button border")
        local bordered = false
        for _, child in ipairs(directChildren(nativeButtons[index])) do if child.kind == "Frame" and child:IsShown() then bordered = true end end
        assert(bordered, "recommended native response button must receive an accent border")
    else
        assert(not overlay.edge:IsShown(), "non-recommended cards must keep only their info badge")
    end
end

-- The badge itself is the compact focus control after the initial prompt.
local recommendedBadge = overlayFor(optionFrames[3]).badge
recommendedBadge.scripts.OnClick(recommendedBadge)
assert(chooser:IsShown(), "clicking an invitation info badge must reopen the focus chooser")
chooser:Hide()
assert(sentResponses == 0, "badge focus control must not activate the native invitation")

-- No fabricated recommendation for tied or missing Favor, including live updates while open.
recommendedBadge.scripts.OnClick(recommendedBadge)
options[1].rewardInfo.itemRewards = { { itemId = 238987, quantity = 1 } }
event("PLAYER_CHOICE_UPDATE")
assert(not chooser.choices[1].recommended, "tied rewards must clear the chooser's recommended state")
options[1].rewardInfo.itemRewards = {}
event("PLAYER_CHOICE_UPDATE")
assert(chooser.choices[1].recommended, "a new unique reward must refresh a visible chooser")
chooser:Hide()

-- This is a one-time reset: later user changes remain respected.
root.soireeHelper.askEachVisit = false
event("PLAYER_CHOICE_CLOSE")
host:Hide(); host:Show()
assert(not chooser:IsShown() and root.soireeHelper.askEachVisit == false,
    "styling reset must not force the toggle back on after the user changes it")

-- Closing clears every owned visual. Reusing the pool for unrelated choice content never leaks cards or toolbar.
event("PLAYER_CHOICE_CLOSE")
for _, option in ipairs(optionFrames) do assert(not overlayFor(option):IsShown(), "close must hide old card overlay") end
host:Hide()
currentChoice = { options = { choiceOption(201, 2711), choiceOption(202, 2712), choiceOption(203, 2713) } }
host:Show()
for _, option in ipairs(optionFrames) do assert(not overlayFor(option):IsShown(), "unrelated reused pool must not show stale overlay") end

-- Combat immediately hides decoration and defers all rebuilding until regen.
currentChoice = { options = options }
host:Hide(); host:Show()
assert(overlayFor(optionFrames[1]):IsShown(), "valid choice must rebuild when shown again")
combat = true
event("PLAYER_REGEN_DISABLED")
for _, option in ipairs(optionFrames) do assert(not overlayFor(option):IsShown(), "combat must remove overlay") end
event("PLAYER_CHOICE_UPDATE")
for _, option in ipairs(optionFrames) do assert(not overlayFor(option):IsShown(), "combat update must remain deferred") end
combat = false
event("PLAYER_REGEN_ENABLED")
assert(overlayFor(optionFrames[1]):IsShown(), "regen must restore a current valid choice")

-- Quest acceptance follows the same first-open chooser policy; ask-each-visit overrides a remembered focus.
root.soireeHelper.askEachVisit = true
event("PLAYER_CHOICE_CLOSE")
assert(not chooser:IsShown())
event("QUEST_ACCEPTED", 89289)
assert(chooser:IsShown(), "Favor of the Court acceptance must offer focus chooser")
chooser:Hide()
event("QUEST_ACCEPTED", 12345)
assert(not chooser:IsShown(), "unrelated quest acceptance must not prompt")

-- FitChooser leaves a usable scaled dialog on the smallest supported screen, and the portrait badge keeps its hit target.
UIParent:SetSize(240, 240)
event("DISPLAY_SIZE_CHANGED")
assert(chooser.scale and chooser.scale >= 0.1 and chooser.scale < 1, "small display must scale chooser into view")
local badge = overlayFor(optionFrames[1]).badge
assert(badge.height == 36 and badge.mouse == true and optionFrames[1].Artwork:GetWidth() >= 140,
    "badge must retain a 36px hover hit target only on sufficiently wide portrait art")

-- A card whose art cannot contain the 36px strip plus 8px vertical gutters receives no overlay.
local smallOption = makeOption(options[1], 139)
smallOption.Artwork:SetHeight(51)
host.optionPools.active = { smallOption }
event("PLAYER_CHOICE_UPDATE")
assert(overlayFor(smallOption) == nil, "narrow or short portrait art must safely skip the badge")

assert(sentResponses == 0, "no lifecycle or chooser action may auto-select a guest")
print("soiree_ui_test: ok")
