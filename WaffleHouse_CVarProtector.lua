local _, addon = ...

-- Keep this allowlist narrow. The names are Retail CVars; the Guardian name
-- is plural even when a CVar browser truncates its final character.
local CVARS = {
    { name = "nameplateShowFriendlyNpcs", label = "Friendly NPCs",
      description = "Whether nameplates are shown for friendly NPCs." },
    { name = "nameplateShowFriendlyPlayerGuardians", label = "Friendly Guardians",
      description = "Whether friendly player guardian nameplates are shown." },
    { name = "nameplateShowFriendlyPlayerMinions", label = "Friendly Minions",
      description = "Whether friendly player minion nameplates are shown." },
    { name = "nameplateShowFriendlyPlayerPets", label = "Friendly Pets",
      description = "Whether friendly player pet nameplates are shown." },
}

local byLowerName = {}
for _, entry in ipairs(CVARS) do byLowerName[entry.name:lower()] = entry end

local pending, pendingManual, scheduled = {}, {}, {}
local attempts, conflictWarned, writeWarned = {}, {}, {}

local function GetSettings()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings then return end
    if settings.nameplateCVarProtectorEnabled == nil then
        settings.nameplateCVarProtectorEnabled = false
    end
    if type(settings.nameplateCVarTargets) ~= "table" then settings.nameplateCVarTargets = {} end
    if type(settings.nameplateCVarProtected) ~= "table" then settings.nameplateCVarProtected = {} end
    for _, entry in ipairs(CVARS) do
        if settings.nameplateCVarTargets[entry.name] ~= "1" then
            settings.nameplateCVarTargets[entry.name] = "0"
        end
        if settings.nameplateCVarProtected[entry.name] == nil then
            settings.nameplateCVarProtected[entry.name] = false
        end
    end
    return settings
end

local function IsProtected(settings, name)
    return settings.nameplateCVarProtectorEnabled == true
        and settings.nameplateCVarProtected[name] == true
end

local function ReportOnce(name, reason, reported)
    if reported[name] then return end
    reported[name] = true
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffbb44Waffle House CVar Protector:|r " .. name .. " " .. reason)
    end
end

local function CanAttempt(name, manual)
    if manual then
        attempts[name] = nil
        return true
    end
    local now = GetTime()
    local state = attempts[name]
    if state and now < state.pauseUntil then return false end
    if not state or now - state.started > 10 then
        state = { started = now, count = 0, pauseUntil = 0 }
        attempts[name] = state
    end
    if state.count >= 6 then
        state.pauseUntil = now + 30
        ReportOnce(name, "keeps being changed; automatic writes are paused for 30 seconds to avoid an addon conflict.", conflictWarned)
        C_Timer.After(30, function()
            local settings = GetSettings()
            if settings and IsProtected(settings, name) then addon.RefreshNameplateCVarProtection(name) end
        end)
        return false
    end
    state.count = state.count + 1
    return true
end

local function ApplyOne(name, manual)
    local entry = byLowerName[type(name) == "string" and name:lower() or ""]
    if not entry then return "failed" end
    name = entry.name
    local settings = GetSettings()
    if not settings then return "failed" end
    if not manual and not IsProtected(settings, name) then return "skipped" end
    if InCombatLockdown and InCombatLockdown() then
        pending[name] = true
        if manual then pendingManual[name] = true end
        return "queued"
    end
    if not (C_CVar and C_CVar.GetCVar) then
        ReportOnce(name, "cannot be restored because this client has no CVar getter.", writeWarned)
        return "failed"
    end
    local writeCVar = type(SetCVar) == "function" and SetCVar or C_CVar.SetCVar
    if type(writeCVar) ~= "function" then
        ReportOnce(name, "cannot be restored because this client has no CVar setter.", writeWarned)
        return "failed"
    end
    local desired = settings.nameplateCVarTargets[name]
    local current = C_CVar.GetCVar(name)
    if current == nil then
        ReportOnce(name, "is not available as a CVar on this client.", writeWarned)
        return "failed"
    end
    if current == desired then return "already" end
    if not CanAttempt(name, manual) then return "paused" end

    -- Prefer FrameXML's SetCVar wrapper for secure CVars outside combat;
    -- the direct API is a fallback for clients without that wrapper.
    local ok, result = pcall(writeCVar, name, desired)
    if not ok or result == false or C_CVar.GetCVar(name) ~= desired then
        ReportOnce(name, "could not be restored by this client; check the in-game Nameplates settings.", writeWarned)
        return "failed"
    end
    return "applied"
end

function addon.RefreshNameplateCVarProtection(name)
    if name then
        ApplyOne(name, false)
        return
    end
    for _, entry in ipairs(CVARS) do ApplyOne(entry.name, false) end
end

function addon.ApplyNameplateCVarTargetsNow()
    local counts = { applied = 0, already = 0, queued = 0, failed = 0, paused = 0 }
    for _, entry in ipairs(CVARS) do
        local result = ApplyOne(entry.name, true)
        if counts[result] ~= nil then counts[result] = counts[result] + 1 end
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff6fe4cbWaffle House CVar Protector:|r %d applied, %d already correct, %d queued until combat ends, %d failed. Checked Protect rows stay enforced while the master switch is on.",
            counts.applied, counts.already, counts.queued, counts.failed + counts.paused))
    end
    return counts
end

function addon.SetNameplateCVarTarget(name, value)
    local entry = byLowerName[type(name) == "string" and name:lower() or ""]
    local settings = GetSettings()
    if not entry or not settings then return end
    settings.nameplateCVarTargets[entry.name] = value == "1" and "1" or "0"
    if IsProtected(settings, entry.name) then ApplyOne(entry.name, true) end
end

local function QueueCheck(name)
    local entry = byLowerName[type(name) == "string" and name:lower() or ""]
    if not entry or scheduled[entry.name] then return end
    local settings = GetSettings()
    if not settings or not IsProtected(settings, entry.name) then return end
    scheduled[entry.name] = true
    C_Timer.After(0, function()
        scheduled[entry.name] = nil
        ApplyOne(entry.name, false)
    end)
end

function addon.BuildNameplateCVarOptions(parent, y)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return y end
    local _, h
    _, h = W:SectionHeader(parent, "NAMEPLATE CVAR PROTECTOR", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Protect Selected Nameplate CVars",
            tooltip = "Opt in to restoring only the nameplate CVars you protect below. Targets default to Off (0). Changes are watched through CVAR_UPDATE; secure CVars wait until combat ends. Turning this off stops restoration but does not change your current game settings.",
            getValue = function() return GetSettings().nameplateCVarProtectorEnabled == true end,
            setValue = function(value)
                GetSettings().nameplateCVarProtectorEnabled = value and true or false
                if value then addon.RefreshNameplateCVarProtection() end
            end,
        },
        {
            type = "button",
            text = "Apply All Targets Now",
            tooltip = "Set all four nameplate CVars to their chosen target values once, even if their Protect switches are off. Only checked Protect rows stay enforced afterward. Writes requested during combat wait until combat ends; the result appears in chat.",
            onClick = function() addon.ApplyNameplateCVarTargetsNow() end,
        }
    ); y = y - h

    for _, entry in ipairs(CVARS) do
        local name = entry.name
        _, h = W:DualRow(parent, y,
            {
                type = "dropdown",
                text = entry.label .. " Target",
                values = { ["0"] = "Off (0)", ["1"] = "On (1)" },
                order = { "0", "1" },
                tooltip = name .. "\n" .. entry.description .. " Choosing a target changes the game setting immediately only when both this Protect switch and the master protector are enabled. Use Apply All Targets Now for a one-time change to every row.",
                getValue = function() return GetSettings().nameplateCVarTargets[name] end,
                setValue = function(value) addon.SetNameplateCVarTarget(name, value) end,
            },
            {
                type = "toggle",
                text = "Protect " .. entry.label,
                tooltip = "Keep " .. name .. " at the chosen target while the master protector is on. If another addon changes it, restore it on the next CVar update; pause writes during combat.",
                getValue = function() return GetSettings().nameplateCVarProtected[name] == true end,
                setValue = function(value)
                    GetSettings().nameplateCVarProtected[name] = value and true or false
                    if value then addon.RefreshNameplateCVarProtection(name) end
                end,
            }
        ); y = y - h
    end
    return y
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "CVAR_UPDATE" then
        QueueCheck(name)
    elseif event == "PLAYER_REGEN_ENABLED" then
        for cvar in pairs(pending) do
            local manual = pendingManual[cvar] == true
            pending[cvar], pendingManual[cvar] = nil, nil
            ApplyOne(cvar, manual)
        end
    else
        addon.RefreshNameplateCVarProtection()
    end
end)
