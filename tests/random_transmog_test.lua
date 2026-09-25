local source = arg[1] or "WaffleHouse_RandomTransmog.lua"
local settings = { randomTransmogEnabled = false, randomTransmogInterval = "5" }
local addon = { GetSettings = function() return settings end }
local state = {}
local now, frame = 0, nil
local timers, changes = {}, {}
local activeID = 1
local entries = {
    { outfitID = 1, name = "Current", isDisabled = false, isEventOutfit = false },
    { outfitID = 2, name = "Other", isDisabled = false, isEventOutfit = false },
    { outfitID = 3, name = "Event", isDisabled = false, isEventOutfit = true },
    { outfitID = 4, name = "Disabled", isDisabled = true, isEventOutfit = false },
    { outfitID = 5, name = "Locked", isDisabled = false, isEventOutfit = false },
}

CreateFrame = function()
    frame = {
        RegisterEvent = function() end,
        SetScript = function(self, _, handler) self.OnEvent = handler end,
    }
    return frame
end
C_Timer = {
    After = function(delay, callback)
        assert(delay >= 30, "randomizer must not poll rapidly")
        timers[#timers + 1] = { due = now + delay, callback = callback }
    end,
}
Enum = { TransmogSituationTrigger = { Manual = 1 } }
C_TransmogOutfitInfo = {
    GetOutfitsInfo = function() return entries end,
    GetActiveOutfitID = function() return activeID end,
    IsLockedOutfit = function(id) return id == 5 or state.lockedActive == true end,
    IsTransmogEnabled = function() return not state.transmogDisabled end,
    HasPendingOutfitTransmogs = function() return state.pending end,
    InTransmogEvent = function() return state.event end,
    ChangeDisplayedOutfit = function(id, trigger, toggleLock, allowRemove)
        assert(trigger == 1 and toggleLock == false and allowRemove == false,
            "switch must use manual trigger without clearing or toggling outfit lock")
        changes[#changes + 1] = id
        activeID = id
        frame:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
    end,
}
C_Transmog = { IsAtTransmogNPC = function() return state.atNPC end }
TransmogFrame = { IsShown = function() return state.editing end }
InCombatLockdown = function() return state.combat end
UnitAffectingCombat = function() return state.combat end
UnitIsDeadOrGhost = function() return state.dead end
UnitOnTaxi = function() return state.taxi end
UnitInVehicle = function() return state.vehicle end
GetUnitSpeed = function() return state.moving and 7 or 0 end
UnitCastingInfo = function() return state.casting end
UnitChannelInfo = function() return state.channeling end
math.random = function(count) assert(count == 1); return 1 end

local function advance(seconds)
    now = now + seconds
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then timer.callback()
        else timers[#timers + 1] = timer end
    end
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
frame:OnEvent("PLAYER_LOGIN")
advance(600)
assert(#changes == 0, "disabled randomizer must not switch")

settings.randomTransmogEnabled = true
addon.RefreshRandomTransmog()
advance(299)
assert(#changes == 0, "enabling must not immediately switch")
advance(1)
assert(#changes == 1 and changes[1] == 2, "must pick only a saved, unlocked, different outfit")
advance(299)
assert(#changes == 1, "successful change must restart interval")

activeID = 1
frame:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
advance(1)
assert(#changes == 1, "manual selection must not be immediately undone")
state.combat = true
advance(300)
assert(#changes == 1, "never switch in combat")
state.combat = false
state.moving = true
advance(30)
assert(#changes == 1, "never switch while moving")
state.moving = false
state.pending = true
advance(30)
assert(#changes == 1, "never switch with pending transmog edits")
state.pending = false
state.lockedActive = true
advance(30)
assert(#changes == 1, "never override a locked active outfit")
state.lockedActive = false
advance(300)
assert(#changes == 2, "try again at the next interval after a locked-outfit skip")

activeID = 1
frame:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
state.editing = true
advance(300)
assert(#changes == 2, "never switch while editing in the transmog frame")
state.editing = false
state.atNPC = true
advance(30)
assert(#changes == 2, "never switch at the transmog NPC")
state.atNPC = false
local getOutfits = C_TransmogOutfitInfo.GetOutfitsInfo
C_TransmogOutfitInfo.GetOutfitsInfo = nil
advance(30)
assert(#changes == 2, "missing Retail APIs must fail closed")
C_TransmogOutfitInfo.GetOutfitsInfo = getOutfits
advance(30)
assert(#changes == 3, "retry after a temporary API or safety restriction")

activeID = 1
frame:OnEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
settings.randomTransmogEnabled = false
addon.RefreshRandomTransmog()
advance(600)
assert(#changes == 3, "turning off must invalidate outstanding timers")

print("random_transmog_test: ok")
