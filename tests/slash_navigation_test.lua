local source = arg[1] or "WaffleHouse_Slash.lua"
local calls, timers, messages = {}, {}, {}
local combat, registered = false, true
local randomized = 0
local addon = {
    EnsureOptionsRegistered = function() return registered end,
    RandomizeTransmogNow = function() randomized = randomized + 1 end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}
C_Timer = { After = function(delay, callback) assert(delay == 0); timers[#timers + 1] = callback end }
InCombatLockdown = function() return combat end
EllesmereUI = {
    NavigateToElementSettings = function(_, module, page, section, _, highlight)
        calls[#calls + 1] = { module, page, section, highlight }
    end,
}
local function flush()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end
assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
assert(SLASH_WAFFLEHOUSEOPTIONS1 == "/wh")
local slash = SlashCmdList.WAFFLEHOUSEOPTIONS
for _, example in ipairs({
    { "config", "General" },
    { "queue", "Item Queue" },
    { "adventure", "Adventure" },
    { "bags", "Bags" },
    { "automation", "Automation" },
    { "vendor", "Vendor" },
}) do
    slash(example[1]); flush()
    assert(calls[#calls][1] == "WaffleHouse_EllesmereUI" and calls[#calls][2] == example[2])
end
slash("  random transmog  "); flush()
assert(calls[#calls][2] == "Adventure" and calls[#calls][3] == "RANDOM TRANSMOG"
    and calls[#calls][4] == "Random Saved Outfit", "transmog must deep-link to its setting")
slash("frozen items"); flush()
assert(calls[#calls][2] == "Bags" and calls[#calls][3] == "MANAGEMENT")
local before = #calls
combat = true
slash("queue"); flush()
assert(#calls == before, "do not open settings during combat")
combat = false
registered = false
slash("queue"); flush()
assert(#calls == before, "do not navigate before registration")
registered = true
slash("transmog now")
assert(randomized == 1 and #calls == before, "immediate command must not open settings")
slash("help")
slash("unknown")
assert(#messages >= 4, "help and failures should explain themselves")
print("slash_navigation_test: ok")
