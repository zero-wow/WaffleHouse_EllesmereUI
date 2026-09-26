local source = arg[1] or "WaffleHouse_RandomTransmog.lua"
local settings = { randomTransmogEnabled = true, randomTransmogInterval = "5", randomTransmogButtonEnabled = true }
local addon = { GetSettings = function() return settings end }
local state, now, events, button, timers, messages = {}, 0, nil, nil, {}, {}
local activeID = 1
local entries = {
    { outfitID = 1, playerFacingOutfitIndex = 1, name = "Current", isDisabled = false, isEventOutfit = false },
    { outfitID = 2, playerFacingOutfitIndex = 2, name = "Other", isDisabled = false, isEventOutfit = false },
    { outfitID = 3, playerFacingOutfitIndex = 3, name = "Event", isDisabled = false, isEventOutfit = true },
    { outfitID = 4, playerFacingOutfitIndex = 4, name = "Disabled", isDisabled = true, isEventOutfit = false },
    { outfitID = 5, playerFacingOutfitIndex = 5, name = "Locked", isDisabled = false, isEventOutfit = false },
    { outfitID = 6, playerFacingOutfitIndex = 6, name = "Outfit", icon = 134400,
        isDisabled = false, isEventOutfit = false },
    { outfitID = 7, playerFacingOutfitIndex = 7, name = "  Outfit  ", icon = 134400,
        isDisabled = false, isEventOutfit = false },
}

GetTime = function() return now end
UIParent = { GetCenter = function() return 500, 400 end }
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return state.ctrl end
InCombatLockdown = function() return state.combat end
RegisterStateDriver = function() end
UnregisterStateDriver = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { due = now + delay, callback = callback } end }

local function newTexture()
    return {
        SetAllPoints = function() end,
        SetTexture = function(self, value) self.path = value end,
        SetTexCoord = function(self, ...) self.texCoord = { ... } end,
        SetRotation = function(self, value) self.rotation = value end,
        SetAlpha = function(self, value) self.alpha = value end,
    }
end

CreateFrame = function(kind, _, _, template)
    if kind == "Button" then
        assert(template == "SecureActionButtonTemplate", "outfits must use the secure button")
        button = {
            attributes = {},
            SetFrameStrata = function() end, SetMovable = function() end,
            SetClampedToScreen = function() end, RegisterForClicks = function() end,
            RegisterForDrag = function() end, EnableMouseWheel = function() end,
            CreateTexture = newTexture,
            SetSize = function(self, width) self.size = width end,
            ClearAllPoints = function() end, SetPoint = function() end,
            Show = function(self) self.visible = true end,
            Hide = function(self) self.visible = false end,
            StopMovingOrSizing = function() end,
            SetAttribute = function(self, key, value)
                assert(not state.combat, "never change secure attributes in combat")
                self.attributes[key] = value
            end,
            GetAttribute = function(self, key) return self.attributes[key] end,
            IsShown = function(self) return self.visible == true end,
            HookScript = function(self, event, handler) self[event] = handler end,
            SetScript = function(self, event, handler) self[event] = handler end,
        }
        return button
    end
    events = { RegisterEvent = function() end, SetScript = function(self, _, handler) self.OnEvent = handler end }
    return events
end

C_TransmogOutfitInfo = {
    GetOutfitsInfo = function() return entries end,
    GetOutfitInfo = function(id)
        for _, entry in ipairs(entries) do if entry.outfitID == id then return entry end end
    end,
    GetOutfitInfoByPlayerFacingIndex = function(index) return entries[index] end,
    GetActiveOutfitID = function() return activeID end,
    IsLockedOutfit = function(id) return id == 5 or state.lockedActive == true end,
    IsTransmogEnabled = function() return not state.disabled end,
    ChangeDisplayedOutfit = function() error("protected C API must never be called by addon Lua") end,
}
math.random = function(count) assert(count > 0); return 1 end

local function advance(seconds)
    now = now + seconds
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then timer.callback() else timers[#timers + 1] = timer end
    end
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
entries[2].playerFacingOutfitIndex = nil -- absent index may resolve to the live slot
events:OnEvent("PLAYER_LOGIN")
assert(button and button.visible and button.attributes.type == "outfit"
    and button.attributes["outfit-index"] == 2
    and button.candidateCount == 1
    and button.attributes.action == "change" and button.attributes["shift-type1"] == "",
    "must arm only a named saved outfit, excluding purchased empty Outfit slots")
assert(button.attributes.useOnKeyDown == false, "secure outfit click must explicitly use mouse-up")
assert(button.back.path:find("button-back.png", 1, true)
    and button.front.path:find("button-front.png", 1, true)
    and button.fill.path:find("button-fill-atlas.png", 1, true)
    and #button.gems == 4, "button must layer artwork, fill, bezel and gems")

local reverseLookup = C_TransmogOutfitInfo.GetOutfitInfoByPlayerFacingIndex
C_TransmogOutfitInfo.GetOutfitInfoByPlayerFacingIndex = function() return nil end
entries[2].playerFacingOutfitIndex = 2
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes["outfit-index"] == 2,
    "stable outfit ID lookup must keep named outfits armed when reverse index lookup is temporarily empty")
C_TransmogOutfitInfo.GetOutfitInfoByPlayerFacingIndex = reverseLookup

advance(150)
button:OnUpdate(0.2)
assert(button.lastFrame > 25 and button.lastFrame < 38, "channel fills halfway through reminder")
advance(150)
button:OnUpdate(0.2)
assert(button.lastFrame == 63 and activeID == 1, "timer fills but never performs protected change")

-- Simulate WoW's secure dispatch; addon Lua only receives the resulting event.
assert(button.attributes["outfit-index"] == 2)
button:PostClick("LeftButton")
advance(0)
assert(button.attributes.type == nil and button.queuedOutfitID == nil,
    "a pending outfit change must not re-arm that same outfit while the active ID is stale")
activeID = 2
events:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
advance(0)
assert(button.attributes["outfit-index"] == 1, "next secure click must select another outfit")
for _ = 1, 20 do button:OnUpdate(0.1) end
assert(button.manualProgress == false, "confirmed click finishes channel sweep")

state.ctrl = true
button:OnMouseWheel(1)
assert(button.size == 68 and settings.randomTransmogButtonSize == 68,
    "Ctrl+wheel should resize the complete layered button")
for _ = 1, 20 do button:OnMouseWheel(-1) end
assert(button.size == 16, "smallest supported size is 16 pixels")
for _ = 1, 50 do button:OnMouseWheel(1) end
assert(button.size == 160, "largest supported size is 160 pixels")
state.combat = true
button:OnMouseWheel(-1)
assert(button.size == 160, "never resize a protected frame in combat")
state.combat = false
events:OnEvent("PLAYER_REGEN_ENABLED")

entries[1].playerFacingOutfitIndex = 2
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes["outfit-index"] == 1,
    "a stale player-facing index must be checked against its stable outfit ID")
entries[1].playerFacingOutfitIndex = 1

state.lockedActive = true
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes.type == nil, "locked outfit must disarm the button")
state.lockedActive = false
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes.type == "outfit")

entries[1].isDisabled, entries[1].isEventOutfit = nil, nil
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes.type == "outfit" and button.attributes["outfit-index"] == 1,
    "missing optional outfit flags must not disarm a usable saved outfit")
addon.ReportRandomTransmogStatus()
assert(messages[#messages - 1]:find("candidates 1", 1, true), "status must show armed candidate count")

local before = #messages
button:PostClick("LeftButton", true)
assert(button.clickCount == 1, "mouse-down must not start another outfit confirmation")
button:PostClick("LeftButton")
assert(button.clickCount == 2, "click diagnostics must record physical button callbacks")
advance(3)
assert(#messages > before and messages[#messages]:find("did not change", 1, true),
    "silent failed secure click must report its queued slot")
assert(button.queuedOutfitID == 1,
    "a failed click must re-arm the sole genuinely saved alternative")

entries[6] = { outfitID = 6, playerFacingOutfitIndex = 6, name = "Sixth" }
entries[7] = { outfitID = 7, playerFacingOutfitIndex = 7, name = "Seventh" }
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.queuedOutfitID == 6 and button.queuedOutfitIndex == 6,
    "use a different existing outfit with its player-facing index")
button:PostClick("LeftButton")
advance(0)
assert(button.queuedOutfitID == 7, "the next click must use another saved outfit; got " .. tostring(button.queuedOutfitID))
activeID = 6
events:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
advance(0)
assert(button.queuedOutfitID == 7, "outfit events must keep a valid unclicked choice stable")
button:PostClick("LeftButton")
advance(0)
assert(button.queuedOutfitID == 1, "rotation must exhaust other outfits before repeating")
local warningsBefore = #messages
advance(3)
assert(#messages == warningsBefore + 1 and messages[#messages]:find("queued slot 7", 1, true),
    "a confirmed earlier click must not be reported as failed after another click")

entries[6], entries[7] = nil, nil
activeID = 2
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.queuedOutfitID == 1, "the other saved outfit must remain selectable")
button:PostClick("LeftButton")
advance(0)
assert(button.attributes.type == nil, "a second click before confirmation must not reset the queued outfit")
activeID = 1
events:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
advance(0)
assert(button.queuedOutfitID == 2, "a confirmed change must arm the alternate outfit")
button:PostClick("LeftButton")
advance(0)
activeID = 2
events:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
advance(0)
assert(button.queuedOutfitID == 1,
    "two-outfit rotation must resume after history resets without reapplying the active outfit")

settings.randomTransmogButtonEnabled = false
addon.RefreshRandomTransmogButton()
assert(button.visible == false)
assert(addon.RandomizeTransmogNow() == true and button.visible == true,
    "slash action may arm and reveal, but not simulate a protected click")
assert(#messages > 0)

local file = assert(io.open(source, "rb"))
local text = file:read("*a")
file:close()
assert(not text:find("outfits.ChangeDisplayedOutfit%(", 1), "protected C API must not be invoked")
print("random_transmog_test: ok")
