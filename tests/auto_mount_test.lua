local source = arg[1] or "WaffleHouse_AutoMount.lua"
local settings = { autoMountAfterCombat = false, autoMountProvider = "auto" }
local addon = { GetSettings = function() return settings end }
local state = {}
local timers, summons, tickers = {}, {}, {}
local frame, now = nil, 0

CreateFrame = function()
    frame = {
        RegisterEvent = function() end,
        SetScript = function(self, _, script) self.OnEvent = script end,
    }
    return frame
end
C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { due = now + delay, callback = callback }
    end,
    NewTicker = function(interval, callback)
        assert(interval >= 1, "auto mounting must use a low-frequency ticker")
        local ticker = { callback = callback, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}
C_MountJournal = {
    SummonByID = function(id) summons[#summons + 1] = id end,
    GetMountFromSpell = function(spellID) return spellID == 1234 and 42 or nil end,
}
GetTime = function() return now end
InCombatLockdown = function() return state.combat end
UnitAffectingCombat = function() return state.combat end
UnitIsDeadOrGhost = function(unit)
    assert(unit == "player")
    return state.dead
end
IsMounted = function() return state.mounted end
IsFlying = function() return state.flying end
UnitOnTaxi = function() return state.taxi end
UnitInVehicle = function() return state.vehicle end
IsOutdoors = function() return not state.indoors end
GetUnitSpeed = function() return state.moving and 7 or 0 end
UnitCastingInfo = function() return state.casting end
UnitChannelInfo = function() return state.channeling end
GetInstanceInfo = function()
    return "Test Area", state.instanceType or "none", state.difficultyID or 0,
        nil, nil, nil, nil, nil, nil, nil, state.worldTier
end

local function advance(seconds)
    now = now + seconds
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then
            timer.callback()
        else
            timers[#timers + 1] = timer
        end
    end
end

local function tick()
    for _, ticker in ipairs(tickers) do
        if not ticker.cancelled then ticker.callback() end
    end
end

local function combatCycle()
    state.combat = true
    frame:OnEvent("PLAYER_REGEN_DISABLED")
    state.combat = false
    frame:OnEvent("PLAYER_REGEN_ENABLED")
    local before = #summons
    advance(2.9)
    tick()
    assert(#summons == before, "combat exit must leave time for looting")
    advance(0.2)
    tick()
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
assert(#addon.AutoMountLocationTypes == 8, "Mounting must offer all broad location types")
local optionKeys = {}
for _, info in ipairs(addon.AutoMountLocationTypes) do
    assert(not optionKeys[info.key], "location option keys must be unique")
    optionKeys[info.key] = true
end
local optionsFile = assert(io.open("WaffleHouse_Adventure.lua", "rb"))
local optionsSource = optionsFile:read("*a")
optionsFile:close()
assert(optionsSource:find('W:SectionHeader(parent, "AUTO-MOUNT LOCATIONS"', 1, true)
    and optionsSource:find("addon.AutoMountLocationTypes", 1, true)
    and optionsSource:find("Auto Mount Out of Combat", 1, true)
    and optionsSource:find("addon.RefreshAutoMount()", 1, true),
    "Out-of-combat mounting and location switches must be surfaced on the Adventure page")

frame:OnEvent("PLAYER_LOGIN")
advance(1)
assert(#summons == 0 and #tickers == 0, "auto mounting is opt-in")

settings.autoMountAfterCombat = true
addon.RefreshAutoMount()
advance(0.9)
tick()
assert(#summons == 0, "enabling must wait for a quiet second")
advance(0.2)
tick()
assert(#summons == 1 and summons[1] == 0, "enabling out of combat must mount without a combat cycle")
tick()
assert(#summons == 1, "failed summons must not be retried every tick")
advance(12)
tick()
assert(#summons == 2, "an unmounted player must get a later retry")

state.mounted = true
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(20)
tick()
assert(#summons == 2, "a mounted player must not be summoned again")
state.mounted = false
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
tick()
assert(#summons == 2, "dismounting must still allow a quiet second")
advance(1.1)
tick()
assert(#summons == 3, "a later dismount must let auto-mounting resume")

state.mounted = true
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(2)
state.mounted = false
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(20)
tick()
assert(#summons == 3, "dismounting within five seconds must pause auto-mounting")

state.mounted = true
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(6)
state.mounted = false
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(1.1)
tick()
assert(#summons == 4, "mounting manually must re-arm a paused auto-mount")

state.mounted = true
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(1)
state.mounted = false
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(12)
tick()
assert(#summons == 4, "a second quick dismount must pause again")
combatCycle()
assert(#summons == 5, "the next combat exit must clear quick-dismount suppression")

frame:OnEvent("UNIT_SPELLCAST_SENT", "player", nil, "mount-cast", 1234)
frame:OnEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "mount-cast", 1234)
advance(12)
tick()
assert(#summons == 5, "interrupting a mount cast must pause auto-mounting")
state.mounted = true
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(6)
state.mounted = false
frame:OnEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
advance(1.1)
tick()
assert(#summons == 6, "mounting again must re-arm after an interrupted cast")

frame:OnEvent("UNIT_SPELLCAST_SENT", "player", nil, "other-cast", 999)
frame:OnEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "other-cast", 999)
advance(12)
tick()
assert(#summons == 7, "interrupting a non-mount cast must not pause auto-mounting")

state.combat = true
frame:OnEvent("PLAYER_REGEN_DISABLED")
state.combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
state.moving = true
frame:OnEvent("PLAYER_STARTED_MOVING")
local count = #summons
advance(5)
tick()
assert(#summons == count, "movement must hold mounting even after combat grace")
state.moving = false
frame:OnEvent("PLAYER_STOPPED_MOVING")
advance(0.9)
tick()
assert(#summons == count, "stopping movement must start a quiet second")
advance(0.2)
tick()
assert(#summons == count + 1, "mounting must resume after the movement quiet period")

state.combat = true
frame:OnEvent("PLAYER_REGEN_DISABLED")
state.combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
frame:OnEvent("LOOT_OPENED")
count = #summons
advance(5)
tick()
assert(#summons == count, "an open loot window must hold mounting")
frame:OnEvent("LOOT_CLOSED")
advance(0.9)
tick()
assert(#summons == count, "closing loot must start a quiet second")
advance(0.2)
tick()
assert(#summons == count + 1, "mounting must resume after looting")

state.combat = true
frame:OnEvent("PLAYER_REGEN_DISABLED")
state.combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
count = #summons
advance(2.9)
frame:OnEvent("UNIT_SPELLCAST_SENT", "player")
advance(0.2)
tick()
assert(#summons == count, "player spellcasts must extend the quiet period")
advance(0.9)
tick()
assert(#summons == count + 1, "mounting must resume after spell activity")

local filterArgs, randomStyle
_G.LiteMount = { LM = {
    MountRegistry = {
        mounts = {},
        RefreshMounts = function() end,
        FilterSearch = function(_, ...)
            filterArgs = { ... }
            return { Random = function(_, style)
                randomStyle = style
                return { mountID = 42 }
            end }
        end,
    },
    Environment = { RefreshState = function() end },
    Options = { GetOption = function(_, name)
        assert(name == "randomWeightStyle")
        return "Priority"
    end },
} }
combatCycle()
assert(summons[#summons] == 42, "LiteMount must supply the chosen journal mount")
assert(filterArgs[1] == "JOURNAL" and filterArgs[2] == "CASTABLE" and filterArgs[3] == "ENABLED",
    "LiteMount selection must honor its enabled castable journal pool")
assert(randomStyle == "Priority", "LiteMount selection must honor its random weighting")

settings.autoMountProvider = "wow"
combatCycle()
assert(summons[#summons] == 0, "explicit WoW picker must ignore LiteMount")

settings.autoMountProvider = "litemount"
_G.LiteMount.LM.MountRegistry.FilterSearch = function()
    return { Random = function() return nil end }
end
count = #summons
combatCycle()
assert(#summons == count, "an intentionally empty LiteMount pool must not bypass its settings")

_G.LiteMount = nil
combatCycle()
assert(summons[#summons] == 0, "missing LiteMount must fall back to WoW")

for _, condition in ipairs({ "mounted", "moving", "dead", "indoors", "casting" }) do
    state[condition] = true
    count = #summons
    combatCycle()
    assert(#summons == count, condition .. " must suppress auto mounting")
    state[condition] = nil
end
state.combat = true
count = #summons
tick()
assert(#summons == count, "combat must suppress auto mounting")
state.combat = false
advance(12)
count = #summons
tick()
assert(#summons == count + 1, "mounting must resume when the player becomes eligible out of combat")

state.combat = true
frame:OnEvent("PLAYER_REGEN_DISABLED")
state.combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
state.combat = true
frame:OnEvent("PLAYER_REGEN_DISABLED")
state.combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
count = #summons
advance(0.35)
assert(#summons == count, "combat grace period must apply to replacement attempts")
advance(2.75)
tick()
assert(#summons == count + 1, "a new combat must cancel the stale attempt")

local locations = {
    { key = "world", instanceType = "none" },
    { key = "dungeon", instanceType = "party" },
    { key = "raid", instanceType = "raid" },
    { key = "delve", instanceType = "scenario", difficultyID = 208 },
    { key = "scenario", instanceType = "scenario", difficultyID = 12 },
    { key = "pvp", instanceType = "pvp" },
    { key = "pvp", instanceType = "arena" },
    { key = "housing", instanceType = "neighborhood" },
    { key = "housing", instanceType = "interior" },
    { key = "other", instanceType = "party", worldTier = true },
    { key = "other", instanceType = "future-instance" },
}
for _, location in ipairs(locations) do
    state.instanceType = location.instanceType
    state.difficultyID = location.difficultyID
    state.worldTier = location.worldTier
    settings.autoMountLocations = { [location.key] = false }
    count = #summons
    combatCycle()
    assert(#summons == count, location.key .. " must block when its switch is off")
    settings.autoMountLocations[location.key] = true
    tick()
    assert(#summons == count + 1, location.key .. " must permit when its switch is on")
end
settings.autoMountLocations = nil
state.instanceType, state.difficultyID, state.worldTier = nil, nil, nil

settings.autoMountAfterCombat = false
addon.RefreshAutoMount()
count = #summons
advance(20)
tick()
assert(#summons == count and tickers[#tickers].cancelled, "disabling must cancel automatic attempts")

io.write("auto mount tests passed\n")
