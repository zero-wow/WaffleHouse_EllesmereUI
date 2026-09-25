local _, addon = ...

-- An absent setting means allowed, preserving the existing behavior for
-- players who have not chosen any location restrictions yet.
addon.AutoMountLocationTypes = {
    { key = "world", label = "Allow Open World",
      tooltip = "Includes cities and outdoor world zones. The existing outdoors, stationary, and safety checks still apply." },
    { key = "dungeon", label = "Allow Dungeons",
      tooltip = "Allow an automatic mount after combat in dungeon instances where the game permits mounting." },
    { key = "raid", label = "Allow Raids",
      tooltip = "Allow an automatic mount after combat in raid instances where the game permits mounting." },
    { key = "delve", label = "Allow Delves",
      tooltip = "Delves are recognized separately from other scenarios by their instance difficulty." },
    { key = "scenario", label = "Allow Other Scenarios",
      tooltip = "Scenarios other than delves, including solo story scenarios." },
    { key = "pvp", label = "Allow Battlegrounds & Arenas",
      tooltip = "Allow automatic mounting after combat in battlegrounds and arenas when permitted." },
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

local function TryAutoMount()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.autoMountAfterCombat ~= true
        or not addon.IsAutoMountLocationAllowed(settings) or not CanAutoMount() then return end

    local mountID = 0
    if settings.autoMountProvider ~= "wow" then
        local selectedID, available = PickLiteMountID()
        if available then
            if not selectedID then return end
            mountID = selectedID
        end
    end
    -- A single attempt only: failed/forbidden summons are not retried or
    -- queued, and the player can always use their normal mount key instead.
    C_MountJournal.SummonByID(mountID)
end

local sawCombat = false
local attemptToken = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        sawCombat = true
        attemptToken = attemptToken + 1
    elseif sawCombat then
        sawCombat = false
        attemptToken = attemptToken + 1
        local token = attemptToken
        -- Let lockdown end and allow the mount journal to settle after combat.
        C_Timer.After(0.35, function()
            if token == attemptToken then TryAutoMount() end
        end)
    end
end)
