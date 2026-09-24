local source = arg[1] or "WaffleHouse_CVarProtector.lua"
local names = {
    "nameplateShowFriendlyNpcs",
    "nameplateShowFriendlyPlayerGuardians",
    "nameplateShowFriendlyPlayerMinions",
    "nameplateShowFriendlyPlayerPets",
}
local values, writes, timers, controls, notices = {}, {}, {}, {}, {}
for _, name in ipairs(names) do values[name] = "1" end
local now, combat, frame = 0, false, nil
local settings = {}
local addon = { GetSettings = function() return settings end }

GetTime = function() return now end
InCombatLockdown = function() return combat end
C_CVar = { GetCVar = function(name) return values[name] end }
SetCVar = function(name, value)
    assert(values[name] ~= nil, "only allowlisted CVars may be changed")
    writes[#writes + 1] = { name, value }
    values[name] = value
end
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { due = now + delay, callback = callback }
end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) notices[#notices + 1] = message end }
CreateFrame = function()
    frame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        SetScript = function(self, _, callback) self.OnEvent = callback end,
    }
    return frame
end
EllesmereUI = { Widgets = {} }
function EllesmereUI.Widgets:SectionHeader(_, text)
    controls[text] = { text = text }
    return {}, 24
end
function EllesmereUI.Widgets:DualRow(_, _, left, right)
    controls[left.text] = left
    controls[right.text] = right
    return {}, 50
end

local function runTimers()
    local i = 1
    while i <= #timers do
        if timers[i].due <= now then
            local callback = table.remove(timers, i).callback
            callback()
        else
            i = i + 1
        end
    end
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
assert(frame.events.CVAR_UPDATE and frame.events.PLAYER_REGEN_ENABLED and frame.events.PLAYER_LOGIN)
frame:OnEvent("PLAYER_LOGIN")
assert(#writes == 0, "defaults must not modify the player's CVars")
for _, name in ipairs(names) do
    assert(settings.nameplateCVarTargets[name] == "0")
    assert(settings.nameplateCVarProtected[name] == false)
end

addon.BuildNameplateCVarOptions({}, 0)
assert(controls["NAMEPLATE CVAR PROTECTOR"] and controls["Apply All Targets Now"])
assert(controls["Protect Selected Nameplate CVars"].type == "toggle")
for _, label in ipairs({ "Friendly NPCs", "Friendly Guardians", "Friendly Minions", "Friendly Pets" }) do
    assert(controls[label .. " Target"].type == "dropdown")
    assert(controls["Protect " .. label].type == "toggle")
end

addon.SetNameplateCVarTarget(names[1], "0")
controls["Protect Friendly NPCs"].setValue(true)
assert(#writes == 0, "a row opted in under a disabled master must not change game settings")
controls["Protect Selected Nameplate CVars"].setValue(true)
assert(#writes == 1 and values[names[1]] == "0", "only the opted-in row should be applied")
for i = 2, #names do assert(values[names[i]] == "1", "unprotected CVars must be untouched") end

values[names[1]] = "1"
frame:OnEvent("CVAR_UPDATE", names[1]:upper())
assert(values[names[1]] == "1", "CVAR_UPDATE must coalesce until the next tick")
runTimers()
assert(values[names[1]] == "0" and #writes == 2, "external changes should be restored")
frame:OnEvent("CVAR_UPDATE", names[1])
runTimers()
assert(#writes == 2, "a self-generated update must not write again")

combat = true
values[names[1]] = "1"
frame:OnEvent("CVAR_UPDATE", names[1])
runTimers()
assert(values[names[1]] == "1", "no CVar writes in combat")
combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
assert(values[names[1]] == "0", "queued write must run after combat")

combat = true
values[names[1]] = "1"
frame:OnEvent("CVAR_UPDATE", names[1])
runTimers()
controls["Protect Friendly NPCs"].setValue(false)
combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
assert(values[names[1]] == "1", "disabling a row must cancel its queued write")
controls["Protect Friendly NPCs"].setValue(true)
assert(values[names[1]] == "0")

-- An addon that repeatedly flips the value must not trigger endless writes.
now = 20
addon.SetNameplateCVarTarget(names[1], "1")
addon.SetNameplateCVarTarget(names[1], "0")
local before = #writes
for _ = 1, 7 do
    values[names[1]] = "1"
    frame:OnEvent("CVAR_UPDATE", names[1])
    runTimers()
end
assert(#writes - before == 6, "automatic writes must be capped during a conflict")
assert(values[names[1]] == "1" and #notices == 1, "conflict should pause and warn once")
now = 31
frame:OnEvent("CVAR_UPDATE", names[1])
runTimers()
assert(values[names[1]] == "1", "pause must survive the 10-second counting window")
now = 50
runTimers()
assert(values[names[1]] == "0", "protector should retry after the cooldown")

controls["Protect Selected Nameplate CVars"].setValue(false)
values[names[1]] = "1"
frame:OnEvent("CVAR_UPDATE", names[1])
runTimers()
assert(values[names[1]] == "1", "turning off the master must stop restoration")

-- The explicit button applies targets once even when no rows are protected.
for _, name in ipairs(names) do values[name] = "1" end
local count = #writes
controls["Apply All Targets Now"].onClick()
assert(#writes == count + 4, "manual apply must write all four targets")
for _, name in ipairs(names) do assert(values[name] == "0") end
assert(notices[#notices]:find("4 applied", 1, true), "manual apply must confirm its result")

for _, name in ipairs(names) do values[name] = "1" end
combat = true
count = #writes
local queued = addon.ApplyNameplateCVarTargetsNow()
assert(queued.queued == 4 and #writes == count, "manual writes must defer in combat")
combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
for _, name in ipairs(names) do assert(values[name] == "0") end

values[names[1]] = "1"
SetCVar = function() return false end
local failed = addon.ApplyNameplateCVarTargetsNow()
assert(failed.failed == 1 and failed.already == 3,
    "a refused game API write must be reported, not claimed as applied")
assert(notices[#notices]:find("1 failed", 1, true))

io.write("nameplate CVar protector tests passed\n")
