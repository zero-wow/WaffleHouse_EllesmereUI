-- Only the supported repair is offered; retired rules remain stored untouched.
local SOURCE = arg[1] or "WaffleHouse_BuffFrameOptions.lua"
local settings = { enabled = true, rules = { { id = 1, action = "collapse", condition = "login" } } }
local savedRules, savedRule = settings.rules, settings.rules[1]
local headers, rows, combat, repairRequests = {}, {}, false, 0
InCombatLockdown = function() return combat end
EllesmereUI = { Widgets = {
    SectionHeader = function(_, _, title) headers[#headers + 1] = title; return {}, 40 end,
    DualRow = function(_, _, _, left, right)
        rows[#rows + 1] = { left = left, right = right }
        return {}, 50
    end,
} }
local addon = {
    BuffFrameRules = { GetSettings = function() error("Options must not access retired automation rules") end },
    RepairBuffFrameAnchor = function(report)
        assert(report == true, "manual repair must report its result")
        repairRequests = repairRequests + 1
    end,
}
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
assert(loadfile(arg[2] or "WaffleHouse_BuffFrame.lua"))("WaffleHouse_EllesmereUI", addon)
for _, enabled in ipairs({ true, false }) do
    settings.enabled = enabled
    headers, rows = {}, {}
    local bottom = addon.BuildBuffFrameOptions({}, -6)
    assert(#headers == 1 and #rows == 1 and bottom == -96, "one native row must own the repair and its entire height")
    local repair = rows[1].left
    assert(repair.type == "labeledButton" and repair.buttonText == "Repair Missing Anchor", "only repair must be offered")
    assert(repair.text:find("Blizzard Edit Mode", 1, true), "placement guidance must stay visible")
    assert(not repair.disabled(), "repair must be available outside combat")
    repair.onClick()
    combat = true
    assert(repair.disabled(), "repair must be disabled during combat")
    repair.onClick()
    combat = false
    assert(settings.enabled == enabled and settings.rules == savedRules and settings.rules[1] == savedRule,
        "viewing or using the options must preserve retired preferences")
end
assert(repairRequests == 2, "combat clicks must never request a repair")
addon.RepairBuffFrameAnchor = nil
assert(rows[1].left.disabled(), "a missing repair handler must be disabled")
assert(rows[1].left.disabledTooltip():find("unavailable", 1, true))
rows[1].left.onClick()
assert(repairRequests == 2)
print("buff_frame_options_test: ok")
