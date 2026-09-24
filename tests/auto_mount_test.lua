local source = arg[1] or "WaffleHouse_AutoMount.lua"
local settings = { autoMountAfterCombat = false, autoMountProvider = "auto" }
local addon = { GetSettings = function() return settings end }
local state = {}
local timers, summons = {}, {}
local frame

CreateFrame = function()
    frame = {
        RegisterEvent = function() end,
        SetScript = function(self, _, script) self.OnEvent = script end,
    }
    return frame
end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_MountJournal = { SummonByID = function(id) summons[#summons + 1] = id end }
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

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)

local function combatCycle()
    frame:OnEvent("PLAYER_REGEN_DISABLED")
    frame:OnEvent("PLAYER_REGEN_ENABLED")
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end

frame:OnEvent("PLAYER_REGEN_ENABLED")
assert(#timers == 0, "login/reload must not start a mount attempt")
combatCycle()
assert(#summons == 0, "auto mounting is opt-in")

settings.autoMountAfterCombat = true
combatCycle()
assert(#summons == 1 and summons[1] == 0, "no LiteMount should use WoW random favorite")

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
local count = #summons
combatCycle()
assert(#summons == count, "an intentionally empty LiteMount pool must not bypass its settings")

_G.LiteMount = nil
combatCycle()
assert(summons[#summons] == 0, "missing LiteMount must fall back to WoW")

for _, condition in ipairs({ "mounted", "moving", "dead", "indoors", "casting", "combat" }) do
    state[condition] = true
    count = #summons
    combatCycle()
    assert(#summons == count, condition .. " must suppress auto mounting")
    state[condition] = nil
end

frame:OnEvent("PLAYER_REGEN_DISABLED")
frame:OnEvent("PLAYER_REGEN_ENABLED")
frame:OnEvent("PLAYER_REGEN_DISABLED")
frame:OnEvent("PLAYER_REGEN_ENABLED")
count = #summons
local pending = timers
timers = {}
for _, callback in ipairs(pending) do callback() end
assert(#summons == count + 1, "a new combat must cancel the stale attempt")

io.write("auto mount tests passed\n")
