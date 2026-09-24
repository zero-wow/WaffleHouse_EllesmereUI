local _, addon = ...

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
    if InCombatLockdown() or UnitAffectingCombat("player") or IsDeadOrGhost() then return false end
    if IsMounted() or IsFlying() or UnitOnTaxi("player") or UnitInVehicle("player") then return false end
    if not IsOutdoors() or GetUnitSpeed("player") > 0 then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    return C_MountJournal and type(C_MountJournal.SummonByID) == "function"
end

local function TryAutoMount()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.autoMountAfterCombat ~= true or not CanAutoMount() then return end

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
