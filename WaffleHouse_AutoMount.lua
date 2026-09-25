local _, addon = ...

-- An absent setting means allowed, preserving the existing behavior for
-- players who have not chosen any location restrictions yet.
addon.AutoMountLocationTypes = {
    { key = "world", label = "Allow Open World",
      tooltip = "Includes cities and outdoor world zones. The existing outdoors, stationary, and safety checks still apply." },
    { key = "dungeon", label = "Allow Dungeons",
      tooltip = "Allow automatic mounting in dungeon instances where the game permits it." },
    { key = "raid", label = "Allow Raids",
      tooltip = "Allow automatic mounting in raid instances where the game permits it." },
    { key = "delve", label = "Allow Delves",
      tooltip = "Delves are recognized separately from other scenarios by their instance difficulty." },
    { key = "scenario", label = "Allow Other Scenarios",
      tooltip = "Scenarios other than delves, including solo story scenarios." },
    { key = "pvp", label = "Allow Battlegrounds & Arenas",
      tooltip = "Allow automatic mounting in battlegrounds and arenas when permitted." },
    { key = "housing", label = "Allow Housing",
      tooltip = "Housing neighborhoods and interiors. Indoor areas remain blocked by the existing outdoors check." },
    { key = "other", label = "Allow Other Instances",
      tooltip = "Unrecognized instance types and world-tier instances such as Lairs. New instance types remain allowed unless you turn this off." },
}

local function CurrentLocationType()
    if type(GetInstanceInfo) ~= "function" then return "other" end
    local _, instanceType, difficultyID, _, _, _, _, _, _, _, hasWorldTier = GetInstanceInfo()
    if difficultyID == 208 then return "delve" end
    if instanceType == nil or instanceType == "none" then return "world" end
    if hasWorldTier == true then return "other" end
    if instanceType == "party" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    if instanceType == "scenario" then return "scenario" end
    if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
    if instanceType == "neighborhood" or instanceType == "interior" then return "housing" end
    return "other"
end

function addon.IsAutoMountLocationAllowed(settings)
    local locations = settings and settings.autoMountLocations
    return type(locations) ~= "table" or locations[CurrentLocationType()] ~= false
end

-- SummonByID is the journal's direct mount path. LiteMount's secure buttons
-- can also cast forms, use items, and run macros; those actions must not be
-- programmatically clicked from a combat-exit event.
local function PickLiteMountID()
    local button = _G.LiteMount
    local lm = button and button.LM
    local registry = lm and lm.MountRegistry
    local environment = lm and lm.Environment
    local options = lm and lm.Options
    if not (registry and registry.mounts and registry.RefreshMounts and registry.FilterSearch
        and environment and environment.RefreshState and options and options.GetOption) then
        return nil, false
    end

    local ok, mountID = pcall(function()
        registry:RefreshMounts()
        environment:RefreshState()
        local mounts = registry:FilterSearch("JOURNAL", "CASTABLE", "ENABLED")
        if not (mounts and mounts.Random) then return end
        local mount = mounts:Random(options:GetOption("randomWeightStyle"))
        return mount and mount.mountID
    end)
    if not ok then return nil, false end
    -- An empty LiteMount pool is intentional (for example all mounts disabled).
    -- Do not bypass that choice by summoning a WoW favorite.
    return mountID, true
end

local function CanAutoMount()
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return false end
    if IsMounted() or IsFlying() or UnitOnTaxi("player") or UnitInVehicle("player") then return false end
    if not IsOutdoors() or GetUnitSpeed("player") > 0 then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    return C_MountJournal and type(C_MountJournal.SummonByID) == "function"
end

local ticker
local lastMounted
local respectDismount = false
local nextAttemptAt = 0
local idleUntil = 0
local lootOpen = false
local attemptToken = 0
local sawCombat = false

local function WaitForIdle(seconds)
    idleUntil = math.max(idleUntil, GetTime() + seconds)
end

local function ObserveMountState()
    local mounted = IsMounted()
    if lastMounted and not mounted and not InCombatLockdown() then
        respectDismount = true
    end
    lastMounted = mounted
    if mounted then nextAttemptAt = 0 end
end

local function TryAutoMount()
    ObserveMountState()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.autoMountAfterCombat ~= true or respectDismount then return end
    if InCombatLockdown() or UnitAffectingCombat("player") then return end
    if not addon.IsAutoMountLocationAllowed(settings) then return end
    if lootOpen or GetUnitSpeed("player") > 0
        or UnitCastingInfo("player") or UnitChannelInfo("player") then
        WaitForIdle(1)
        return
    end
    if GetTime() < idleUntil or GetTime() < nextAttemptAt or not CanAutoMount() then return end

    local mountID = 0
    if settings.autoMountProvider ~= "wow" then
        local selectedID, available = PickLiteMountID()
        if available then
            if not selectedID then
                nextAttemptAt = GetTime() + 12
                return
            end
            mountID = selectedID
        end
    end
    -- Some areas reject mounts even outdoors. Retry slowly instead of
    -- hammering the journal every tick if the summon does not take.
    nextAttemptAt = GetTime() + 12
    C_MountJournal.SummonByID(mountID)
end

function addon.RefreshAutoMount()
    local settings = addon.GetSettings and addon.GetSettings()
    local enabled = settings and settings.autoMountAfterCombat == true
    attemptToken = attemptToken + 1
    if not enabled then
        if ticker then ticker:Cancel(); ticker = nil end
        return
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then sawCombat = true end
    if not ticker then
        lastMounted = IsMounted()
        respectDismount = false
        nextAttemptAt = 0
        WaitForIdle(1)
        ticker = C_Timer.NewTicker(1, TryAutoMount)
    end
    local token = attemptToken
    C_Timer.After(0.35, function()
        if token == attemptToken then TryAutoMount() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
events:RegisterEvent("PLAYER_STARTED_MOVING")
events:RegisterEvent("PLAYER_STOPPED_MOVING")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        addon.RefreshAutoMount()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        ObserveMountState()
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        WaitForIdle(1)
    elseif event == "LOOT_OPENED" then
        lootOpen = true
        WaitForIdle(1)
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        WaitForIdle(1)
    elseif event == "UNIT_SPELLCAST_SENT" then
        if unit == "player" then WaitForIdle(1) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        sawCombat = true
        attemptToken = attemptToken + 1
    elseif event == "PLAYER_REGEN_ENABLED" and sawCombat then
        sawCombat = false
        respectDismount = false
        -- A mount lost during combat is not an out-of-combat manual dismount,
        -- even if its display-change event was missed.
        lastMounted = IsMounted()
        nextAttemptAt = 0
        WaitForIdle(3)
        addon.RefreshAutoMount()
    end
end)
