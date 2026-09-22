-- Regression for native BuffFrame taint: a state setter can install Blizzard's
-- OnUpdate under addon execution, with failures deferred until later combat.
local SOURCE = arg[1] or "WaffleHouse_BuffFrame.lua"
local timers, frames, now = {}, {}, 0
function CreateFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    frames[#frames + 1] = frame
    return frame
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
GetTime = function() return now end
InCombatLockdown = function() return _G.combat == true end
C_Secrets = { ShouldAurasBeSecret = function() return _G.restricted == true end }
MouseIsOver = function() return false end
IsInGroup = function() return false end
IsMounted = function() return false end
IsInInstance = function() return false end

local stateWrites, nativeReads, nativeUpdates = 0, 0, 0
local originalOnUpdate = function() end
local originalClick = function() end
BuffFrame = {
    isExpanded = true,
    OnUpdate = originalOnUpdate,
    CollapseAndExpandButton = { IsEnabled = function() return true end, OnClick = originalClick },
    IsExpanded = function(self) nativeReads = nativeReads + 1; return self.isExpanded end,
    SetBuffsExpandedState = function(self, value)
        stateWrites = stateWrites + 1
        self.isExpanded = value
        self:Update()
    end,
    Update = function(self)
        nativeUpdates = nativeUpdates + 1
        -- Models the dangerous deferred handler installation, not WoW secrets.
        self.OnUpdate = function() error("native secret aura handler ran tainted") end
    end,
}
local settings = {
    enabled = true,
    ownOnlyCollapsed = true, euiSkin = true,
    rules = { { id = 1, enabled = true, condition = "login", action = "collapse", delay = 0 } },
}
local savedRules, savedRule = settings.rules, settings.rules[1]
local addon = { BuffFrameRules = {
    GetSettings = function() return settings end,
    Evaluate = function()
        return { expanded = false, delay = 0, stateRule = 1, stateCondition = "login" }
    end,
} }
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
local function flush()
    local rounds = 0
    while #timers > 0 do
        rounds = rounds + 1; assert(rounds < 20, "timer loop")
        local ready = timers; timers = {}
        for _, fn in ipairs(ready) do fn() end
    end
end
local function event(name)
    for _, frame in ipairs(frames) do
        if frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name) end
    end
    flush()
end
addon.RefreshBuffFrameControls(); flush()
event("PLAYER_LOGIN")
assert(stateWrites == 0 and nativeUpdates == 0,
    "automatic controls must not call Blizzard's state setter or install a tainted aura update")
assert(addon.BuffFrameAutomationAvailable == false, "options must be told native automation is unavailable")
assert(settings.enabled and settings.rules == savedRules and settings.rules[1] == savedRule,
    "disabling unsafe runtime behavior must preserve saved settings and rules")
assert(settings.ownOnlyCollapsed and settings.euiSkin, "legacy aura preferences must be preserved")

for _, restricted in ipairs({ false, true }) do
    _G.restricted = restricted
    for _, combat in ipairs({ false, true }) do
        _G.combat = combat
        for _, enabled in ipairs({ true, false }) do
            settings.enabled = enabled
            addon.RefreshBuffFrameControls(); flush()
            for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "PLAYER_REGEN_DISABLED",
                "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do event(name) end
            for _, frame in ipairs(frames) do
                for _ = 1, 100 do
                    now = now + 0.2
                    if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.2) end
                end
            end
            local status = addon.GetBuffFrameStatus()
            assert(status:find("unavailable", 1, true) and status:find("Edit Mode", 1, true),
                "status must explain unavailable automation and native placement")
        end
    end
end
assert(stateWrites == 0 and nativeUpdates == 0 and nativeReads == 0, "all native state access must be absent")
assert(BuffFrame.OnUpdate == originalOnUpdate and BuffFrame.CollapseAndExpandButton.OnClick == originalClick,
    "Blizzard's update and manual click handlers must remain unchanged")
assert(#frames == 0 and #timers == 0, "unavailable controls must not create event drivers or poll")

-- Even an unreadable native frame must be harmless: status and refresh are
-- addon-only operations, including when Blizzard has not loaded the frame.
BuffFrame = setmetatable({}, { __index = function() error("native frame was accessed") end })
addon.RefreshBuffFrameControls(); assert(addon.GetBuffFrameStatus())
BuffFrame = nil
addon.RefreshBuffFrameControls(); assert(addon.GetBuffFrameStatus())
print("buff_frame_runtime_test: ok")
