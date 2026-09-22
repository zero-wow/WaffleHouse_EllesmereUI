-- Run with: lua tests/buff_frame_rules_test.lua WaffleHouse_BuffFrameRules.lua
local SOURCE = arg[1] or "WaffleHouse_BuffFrameRules.lua"
local SECRET = {}
issecretvalue = function(value) return value == SECRET end

local root = {}
local addon = { GetSettings = function() return root end }
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
local R = assert(addon.BuffFrameRules)

local settings = R.GetSettings()
assert(settings.enabled == false and settings.anchorEnabled == true)
assert(settings.target == "player" and settings.point == "RIGHT" and settings.relativePoint == "LEFT")
assert(settings.x == -12 and settings.y == 0 and settings.ownOnlyCollapsed == true)
assert(#settings.rules == 2 and settings.nextRuleID == 3)
assert(R.ConditionLabels.outOfCombat and #R.AnchorOrder == 9 and #R.TargetOrder == 5)

-- Frequent evaluation must not replace the rules array or valid rule tables:
-- controls may hold a direct rule reference between refreshes.
local initialRules, initialRule = settings.rules, settings.rules[1]
assert(R.GetSettings().rules == initialRules and settings.rules[1] == initialRule)
initialRule.action = "own"
local retained = R.Evaluate(settings, { hover = true })
assert(settings.rules == initialRules and settings.rules[1] == initialRule)
assert(retained.ownOnly == true and retained.filterRule == initialRule.id)
initialRule.action = "expand"

-- A user-cleared rule list stays cleared and leaves native state untouched.
settings.rules = {}
settings = R.GetSettings()
assert(#settings.rules == 0)
local noRules = R.Evaluate(settings, { combat = false })
assert(noRules.expanded == nil and noRules.ownOnly == true and noRules.delay == nil)

settings.rules = {
    { id = 10, enabled = true, condition = "always", action = "collapse", delay = 12 },
    { id = 11, enabled = true, condition = "always", action = "expand", delay = 99 },
    { id = 12, enabled = true, condition = "always", action = "normal" },
    { id = 13, enabled = true, condition = "always", action = "own" },
}
local conflicts = R.Evaluate(settings, {})
assert(conflicts.expanded == false and conflicts.delay == 12 and conflicts.stateRule == 10)
assert(conflicts.ownOnly == false and conflicts.filterRule == 12)

-- State and filter fields are independent: a later matching filter still
-- contributes after the first state rule has won.
settings.rules = {
    { id = 20, enabled = true, condition = "hover", action = "expand", delay = 3 },
    { id = 21, enabled = true, condition = "always", action = "own" },
}
local independent = R.Evaluate(settings, { hover = true })
assert(independent.expanded == true and independent.delay == nil and independent.stateRule == 20)
assert(independent.ownOnly == true and independent.filterRule == 21)

settings.rules = {
    { id = 30, enabled = false, condition = "always", action = "collapse", delay = 1 },
    { id = 31, enabled = true, condition = "unknown", action = "expand", delay = 1 },
    { id = 32, enabled = true, condition = "always", action = "unknown", delay = 1 },
    { id = 33, enabled = true, condition = "outOfCombat", action = "expand", delay = 1 },
}
local invalid = R.Evaluate(settings, { combat = false })
assert(invalid.expanded == true and invalid.stateRule == 33)
assert(invalid.ownOnly == true and invalid.filterRule == nil)

-- Malformed SavedVariables (including protected/secret values) are bounded.
settings.enabled, settings.anchorEnabled = "yes", SECRET
settings.target, settings.point, settings.relativePoint = "bad", "bad", "bad"
settings.x, settings.y, settings.rules = math.huge, -999999, {
    { id = 1.8, enabled = true, condition = "always", action = "collapse", delay = 9999 },
    { id = 2, enabled = true, condition = "always", action = "expand", delay = SECRET },
    { id = 2, enabled = true, condition = "always", action = "own" },
}
settings.nextRuleID = 1
settings = R.GetSettings()
assert(settings.enabled == false and settings.anchorEnabled == true)
assert(settings.target == "player" and settings.point == "RIGHT" and settings.relativePoint == "LEFT")
assert(settings.x == -12 and settings.y == -2000)
assert(settings.rules[1].id == 2 and settings.rules[1].delay == 300)
assert(settings.rules[2].delay == 0 and settings.rules[3].id ~= settings.rules[2].id)
assert(settings.nextRuleID > settings.rules[3].id)

-- Compaction discards malformed entries but keeps valid table references. A
-- UI write through that retained table is observed by later evaluation.
local first = { id = 40, enabled = true, condition = "always", action = "collapse", delay = 7 }
local second = { id = 40, enabled = true, condition = "always", action = "normal" }
local stableRules = { first, "malformed", second }
settings.rules = stableRules
settings = R.GetSettings()
assert(settings.rules == stableRules and #stableRules == 2)
assert(stableRules[1] == first and stableRules[2] == second and first.id ~= second.id)
first.action = "expand"
local uiWrite = R.Evaluate(settings, {})
assert(settings.rules == stableRules and stableRules[1] == first)
assert(uiWrite.expanded == true and uiWrite.stateRule == first.id)
assert(R.GetSettings().rules == stableRules and stableRules[1] == first)

local added = R.AddRule(settings)
assert(added.id == settings.nextRuleID - 1 and #settings.rules == 3)
assert(R.MoveRule(settings, added.id, -1) == true)
assert(R.MoveRule(settings, settings.rules[1].id, -1) == false)
assert(R.RemoveRule(settings, added.id) == true and R.RemoveRule(settings, added.id) == false)

print("buff_frame_rules_test: ok")
