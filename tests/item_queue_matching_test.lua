-- Item Queue matching regressions for combinations and Warband appearances.
-- Run from the addon source directory:
--   lua tests/item_queue_matching_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text:gsub("\r\n", "\n")
end

local source = readFile(SOURCE)

-- These helpers have no nested local functions, so a boundary at the next
-- local declaration keeps this harness small while executing production code.
local function extractLocalFunction(name)
    local startAt = assert(source:find("local function " .. name .. "%("), "missing " .. name)
    local endAt = assert(source:find("\nend\n\nlocal function", startAt), "unterminated " .. name)
    return source:sub(startAt, endAt + #"\nend" - 1)
end

local helpers = table.concat({
    "local function IsSafeText(value) return type(value) == 'string' and value ~= '' end",
    extractLocalFunction("IsDarkmoonFaireCardTooltip"),
    extractLocalFunction("IsCombinationTooltip"),
    extractLocalFunction("IsCurrencyGrantTooltip"),
    extractLocalFunction("HasCompleteCombinationRequirements"),
    extractLocalFunction("IsIncompleteCombinationTooltip"),
    extractLocalFunction("HasCompleteDarkmoonFaireCardSet"),
    extractLocalFunction("IsAppearanceUnlockTooltip"),
    "return { IsDarkmoonFaireCardTooltip, IsCombinationTooltip, IsCurrencyGrantTooltip, HasCompleteCombinationRequirements, IsIncompleteCombinationTooltip, HasCompleteDarkmoonFaireCardSet, IsAppearanceUnlockTooltip }",
}, "\n\n")
local factory, loadErr = load(helpers, "@extracted-item-queue-matching")
assert(factory, loadErr)
local IsDarkmoonFaireCardTooltip, IsCombinationTooltip, IsCurrencyGrantTooltip,
    HasCompleteCombinationRequirements, IsIncompleteCombinationTooltip, HasCompleteDarkmoonFaireCardSet,
    IsAppearanceUnlockTooltip = (table.unpack or unpack)(factory())

local function assertTrue(value, message)
    assert(value, message or "assertion failed")
end

local function assertFalse(value, message)
    assert(not value, message or "assertion should be false")
end

local incompleteAmani = ([[
Use: Combine the Reinforced Amani Haft, Tempered Amani Spearhead, and Toughened Amani Leather Wrap to reform the Amani Warrior's Spear.
Reinforced Amani Haft 0/1
* Tempered Amani Spearhead 1/1
Toughened Amani Leather Wrap 0/1
]]):lower()

assertTrue(IsCombinationTooltip(incompleteAmani), "Amani tooltip must be recognized as a combination")
assertFalse(HasCompleteCombinationRequirements(incompleteAmani), "Amani 0/1 requirements must keep it out of the queue")
assertTrue(IsIncompleteCombinationTooltip(incompleteAmani), "incomplete Amani must be blocked before any category fallback")
assertTrue(HasCompleteCombinationRequirements("use: combine these fragments into a key"),
    "a combination without an explicit x/y requirement should defer to its own Use action")
assertTrue(HasCompleteCombinationRequirements("use: reform the set shard 1/1 component 2 / 2"),
    "a fully supplied combination should remain eligible")

local incompleteDarkmoon = ([[
Use: Combine the Ace through Eight of Hunt to complete the set.
Ace of Hunt 0/1
Two of Hunt 1/1
]]):lower()
assertTrue(IsDarkmoonFaireCardTooltip(incompleteDarkmoon), "Darkmoon card tooltip must be recognized")
assertFalse(HasCompleteDarkmoonFaireCardSet(incompleteDarkmoon), "incomplete Darkmoon set must remain excluded")

local barbedRiftwalker = ([[
Barbed Riftwalker Dirk
Use: Add this appearance to your Warband collection.
You haven't collected this appearance
]]):lower()
assertTrue(IsAppearanceUnlockTooltip(barbedRiftwalker), "Warband appearance wording must match even when wrapped across tooltip lines")
assertFalse(IsAppearanceUnlockTooltip("one-hand dagger use: equip this weapon"),
    "ordinary equippable gear must not be mistaken for a cosmetic unlock")

local pepeExplorer = ([[
A Tiny Explorer's Hat
Soulbound
Unique
Use: When summoned, Pepe will sometimes be dressed like an explorer.
(1 Sec Cooldown)
]]):lower()
assertTrue(IsAppearanceUnlockTooltip(pepeExplorer), "Pepe costume consumables must qualify as appearance unlocks")
assertFalse(IsAppearanceUnlockTooltip("trans-dimensional bird whistle use: summon pepe to ride on your head"),
    "the reusable Pepe summoning whistle must not become a costume unlock")
assertFalse(IsAppearanceUnlockTooltip("a tiny explorer's hat when summoned, pepe will sometimes be dressed like an explorer"),
    "costume flavor text without an explicit Use action must not qualify")

assertTrue(IsCurrencyGrantTooltip("use: gain a large amount of voidlight marl"),
    "a direct Voidlight Marl currency grant must be recognized for the Currency Items queue category")
assertFalse(IsCurrencyGrantTooltip("use: gain a large amount of experience"),
    "experience gains must not be mistaken for currency grants")

assertTrue(source:find('combination = not isDarkmoonCard and isCombination and HasCompleteCombinationRequirements%(tooltip%)') ~= nil,
    "combination match must use the completeness gate")
local evaluatorStart = assert(source:find("local function EvaluateItemQueueCandidate%("), "missing queue eligibility evaluator")
local evaluatorEnd = assert(source:find("\nend\n\nlocal function", evaluatorStart), "unterminated queue eligibility evaluator")
local evaluatorFunction = source:sub(evaluatorStart, evaluatorEnd)
assertTrue(evaluatorFunction:find("automaticCombinationBan") ~= nil
        and evaluatorFunction:find("incompleteDarkmoon") ~= nil
        and evaluatorFunction:find("incompleteCombination") ~= nil,
    "one evaluator must own the combination and Darkmoon eligibility gates")
assertTrue(assert(evaluatorFunction:find("if automaticCombinationBan then"))
        < assert(evaluatorFunction:find("for _, category in ipairs%(decision.categoryMatches%)")),
    "temporary incomplete-combination blocks must run before every broad category fallback")
-- The production prepass and delayed hydration behavior are exercised by
-- item_queue_scan_test.lua; comment text is not evidence that they work.
assertTrue(source:find("queuedDarkmoonSets", 1, true) ~= nil,
    "the scan must still keep one candidate per completed Darkmoon deck")
assertTrue(source:find('button:SetAttribute%("type1", "macro"%)') ~= nil
        and source:find('button:SetAttribute%("macrotext1", "/use "') ~= nil,
    "queue action must use the secure /use macro path, not the auto-equip item path")

io.write("All Item Queue matching regressions passed\n")
