-- Item Queue eligibility regressions for tooltip readiness and broad-category
-- fallbacks. Run from the addon source directory:
--   lua tests/item_queue_eligibility_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text:gsub("\r\n", "\n")
end

local source = readFile(SOURCE)

local function extractLocalFunction(name)
    local startAt = assert(source:find("local function " .. name .. "%(", 1), "missing " .. name)
    local endAt = assert(source:find("\nend\n\nlocal function", startAt, true), "unterminated " .. name)
    return source:sub(startAt, endAt + #"\nend" - 1)
end

local prelude = [[
local ITEM_QUEUE_ORDER = { "combination", "darkmoon", "containers", "custom" }
local ITEM_QUEUE_TYPES = {
    combination = { label = "Combination Items" },
    darkmoon = { label = "Darkmoon Faire Cards" },
    containers = { label = "Boxes & Caches" },
    custom = { label = "Pinned Items" },
}
local sessionBannedItems = {}
local incompleteCombinationItems = {}
local itemQueueTooltipRetryPending = {}
local itemQueueTooltipInstances = {}
local retryRequests = 0
local scenario
local settings = { bannedItems = {}, categories = {}, order = ITEM_QUEUE_ORDER }

local function GetItemQueueSettings() return settings end
local function IsSafeText(value) return type(value) == "string" and value ~= "" end
local function IsSafeNumber(value) return type(value) == "number" end
local function GetItemQueueMatchData()
    return scenario.tooltip, scenario.snapshot, nil, scenario.matches
end
local function IsItemQueueTooltipReady(_, snapshot) return snapshot.ready == true end
local function IsCompletedQueueItem() return false end
local function CanUseQueueItem() return scenario.usable ~= false end
local function RequestItemQueueTooltipRetry() retryRequests = retryRequests + 1 end
local function GetDarkmoonFaireCardSetKey() return "test-deck" end
]]

local helpers = table.concat({
    extractLocalFunction("NormalizeItemQueueTooltipText"),
    extractLocalFunction("GetBagItemTooltipSnapshot"),
    extractLocalFunction("IsDarkmoonFaireCardTooltip"),
    extractLocalFunction("IsCombinationTooltip"),
    extractLocalFunction("HasCompleteCombinationRequirements"),
    extractLocalFunction("IsIncompleteCombinationTooltip"),
    extractLocalFunction("HasCompleteDarkmoonFaireCardSet"),
    extractLocalFunction("UpdateIncompleteCombinationItem"),
    extractLocalFunction("EvaluateItemQueueCandidate"),
    "return GetBagItemTooltipSnapshot, EvaluateItemQueueCandidate, function(value) scenario = value end, function() return retryRequests end",
}, "\n\n")

local factory, loadErr = load(prelude .. "\n" .. helpers, "@extracted-item-queue-eligibility")
assert(factory, loadErr)
local GetBagItemTooltipSnapshot, EvaluateItemQueueCandidate, setScenario, getRetryRequests = factory()

local function assertTrue(value, message)
    assert(value, message or "assertion failed")
end

local function assertFalse(value, message)
    assert(not value, message or "assertion should be false")
end

C_TooltipInfo = {
    GetBagItem = function()
        return {
            lines = {
                { leftText = "|cffffffffTempered Amani Spearhead|r" },
                { leftText = "Use: Combine the pieces." },
                { leftText = "Reinforced Amani Haft 0/1" },
            },
        }
    end,
}
local snapshot = GetBagItemTooltipSnapshot(0, 1)
assertTrue(snapshot.available and snapshot.lineCount == 3, "scanner must retain every readable tooltip line")
assertTrue(snapshot.normalized:find("use: combine", 1, true) ~= nil
        and snapshot.normalized:find("reinforced amani haft 0/1", 1, true) ~= nil,
    "scanner normalization must preserve the Combine action and exact component count")

local function decisionFor(tooltip, ready, matches)
    setScenario({
        matches = matches or { custom = true, containers = true, combination = false, darkmoon = false },
        snapshot = { normalized = tooltip, ready = ready,
            combinationRequirements = ready and { ready = true, rows = {}, incomplete = false } or nil },
        tooltip = tooltip,
        usable = true,
    })
    return EvaluateItemQueueCandidate(235500, 0, 1)
end

local incompleteAmani = ([[
use: combine the reinforced amani haft, tempered amani spearhead, and toughened amani leather wrap to reform the amani warrior's spear.
reinforced amani haft 0/1
tempered amani spearhead 1/1
toughened amani leather wrap 0/1
]]):gsub("%s+", " ")

local decision = decisionFor(incompleteAmani, true)
assertFalse(decision.category, "an incomplete Combine/Reform item must not fall through to pinned or container categories")
assertTrue(decision.checks.automaticCombinationBan, "a fully scanned incomplete combination must create the temporary block")
assertTrue(decision.reason:find("Temporarily blocked", 1, true) ~= nil,
    "the temporary block must be the final decision before generic category matching")

decision = decisionFor("", false)
assertFalse(decision.category, "a later empty tooltip must retain the temporary incomplete-combination block")
assertTrue(decision.checks.automaticCombinationBan, "a partial snapshot must not clear the earlier verified missing-component state")

local completeAmani = ([[
use: combine the reinforced amani haft, tempered amani spearhead, and toughened amani leather wrap to reform the amani warrior's spear.
reinforced amani haft 1/1
tempered amani spearhead 1/1
toughened amani leather wrap 1/1
]]):gsub("%s+", " ")
decision = decisionFor(completeAmani, true, { combination = true, darkmoon = false, containers = true, custom = true })
assertTrue(decision.category == "combination", "a complete combination must clear the temporary block and queue by its real category")
assertFalse(decision.checks.automaticCombinationBan, "a complete component list must automatically unban the item")

decision = decisionFor("", false, { custom = true, containers = true, combination = false, darkmoon = false })
assertFalse(decision.category, "a cold tooltip snapshot must not become a pinned or container candidate")
assertTrue(decision.reason:find("Tooltip data is not ready", 1, true) ~= nil,
    "a cold tooltip must be deferred rather than cached as eligible")
assertTrue(getRetryRequests() > 0, "a cold tooltip must request a retry")

local incompleteDarkmoon = ([[
use: combine the ace through eight of hunt to complete the set.
ace of hunt 0/1
two of hunt 1/1
]]):gsub("%s+", " ")
decision = decisionFor(incompleteDarkmoon, true, { custom = true, containers = true, combination = false, darkmoon = false })
assertFalse(decision.category, "an incomplete Darkmoon deck must not fall through to pinned or container categories")
assertTrue(decision.checks.incompleteDarkmoon, "the Darkmoon completeness gate must be reported")

local noRequirementCombination = "use: combine these fragments into a key"
decision = decisionFor(noRequirementCombination, true, { combination = true, darkmoon = false, containers = false, custom = false })
assertTrue(decision.category == "combination", "a legitimate combination with no listed requirements must remain queueable")

io.write("All Item Queue eligibility regressions passed\n")
