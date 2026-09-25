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
    GetActiveOutfitID = function() return activeID end,
    IsLockedOutfit = function(id) return id == 5 or state.lockedActive == true end,
    IsTransmogEnabled = function() return not state.disabled end,
    ChangeDisplayedOutfit = function() error("protected C API must never be called by addon Lua") end,
}
math.random = function(count) assert(count == 1); return 1 end

local function advance(seconds)
    now = now + seconds
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then timer.callback() else timers[#timers + 1] = timer end
    end
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
events:OnEvent("PLAYER_LOGIN")
assert(button and button.visible and button.attributes.type == "outfit"
    and button.attributes["outfit-index"] == 2
    and button.attributes.action == "change" and button.attributes["shift-type1"] == "",
    "must arm a non-toggling secure action for a different valid outfit")
assert(button.back.path:find("button-back.png", 1, true)
    and button.front.path:find("button-front.png", 1, true)
    and button.fill.path:find("button-fill-atlas.png", 1, true)
    and #button.gems == 4, "button must layer artwork, fill, bezel and gems")

advance(150)
button:OnUpdate(0.2)
assert(button.lastFrame > 25 and button.lastFrame < 38, "channel fills halfway through reminder")
advance(150)
button:OnUpdate(0.2)
assert(button.lastFrame == 63 and activeID == 1, "timer fills but never performs protected change")

-- Simulate WoW's secure dispatch; addon Lua only receives the resulting event.
assert(button.attributes["outfit-index"] == 2)
activeID = 2
events:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
button:PostClick("LeftButton")
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

state.lockedActive = true
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes.type == nil, "locked outfit must disarm the button")
state.lockedActive = false
events:OnEvent("TRANSMOG_OUTFITS_CHANGED")
advance(0)
assert(button.attributes.type == "outfit")

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
