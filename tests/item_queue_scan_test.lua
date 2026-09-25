-- End-to-end queue regressions: execute the production tooltip scanner,
-- category matcher, eligibility evaluator, bag scan, and button refresh.
-- Only external WoW APIs and frame presentation are mocked.
-- Run from the source directory: lua tests/item_queue_scan_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(SOURCE, "rb"))
local source = file:read("*a")
file:close()

local function section(first, following)
    local beginAt = assert(source:find(first, 1, true), "missing production boundary: " .. first)
    local endAt = assert(source:find(following, beginAt + #first, true), "missing production boundary: " .. following)
    return source:sub(beginAt, endAt - 1)
end

local preamble = source:sub(1, assert(source:find("local function GetSettings()", 1, true)) - 1)
local queueCode = section("local function NormalizeItemQueueTooltipText", "local function GetQueueItemName")
local diagnosticsCode = section("local function QueueDiagnosticYesNo", "local function SetItemQueueAuditButtonText")
local combatVisibilityCode = section("UpdateItemQueueCombatVisibility = function()", "local function EnsureItemQueueButton")
local refreshCode = section("local function GetQueueItemColor", "local function GetMerchantCosts")
local eventCode = assert(source:match([[events:SetScript%("OnEvent", function[%s%S]*end%)%s*$]]),
    "missing production event handler")
local apiCode = [[
return {
    scan = ScanItemQueue,
    evaluate = EvaluateItemQueueCandidate,
    refresh = RefreshItemQueue,
    schedule = ScheduleItemQueueRefresh,
    candidates = function() return itemQueueCandidates end,
    banUntilReload = function(id) sessionBannedItems[id] = true end,
    diagnostics = BuildItemQueueDiagnosticDetails,
    automaticBlock = function(id) return incompleteCombinationItems[id] end,
    lastDecisions = function() return itemQueueLastDecisions end,
    event = function(name, ...) return testState.events.onEvent(testState.events, name, ...) end,
}
]]

local function check(value, message)
    assert(value, message or "queue regression failed")
end

local function tooltip(...)
    local lines = {}
    for _, text in ipairs({...}) do lines[#lines + 1] = { leftText = text } end
    return { lines = lines }
end

local AMANI_ID = 265543
local HAFT_ID = 265554
local AMANI_TOOLTIP = tooltip("Tempered Amani Spearhead", "Use: Combine the pieces to reform the Amani Warrior's Spear.")
local AMANI_INCOMPLETE_TOOLTIP = tooltip("Tempered Amani Spearhead", "Use: Combine the pieces to reform the Amani Warrior's Spear.",
    "Reinforced Amani Haft 0/1", "Tempered Amani Spearhead 1/1", "Toughened Amani Leather Wrap 0/1")

local function amaniSchematic()
    local slots = {}
    for _, id in ipairs({HAFT_ID, AMANI_ID, 265560}) do
        slots[#slots + 1] = { required = true, quantityRequired = 1, reagentType = 1, reagents = {{ itemID = id }} }
    end
    return { reagentSlotSchematics = slots }
end

local function item(id, data)
    data = data or {}
    data.itemID = id
    data.name = data.name or ("Item " .. tostring(id))
    data.hyperlink = "item:" .. tostring(id)
    data.stackCount = data.stackCount or 1
    data.iconFileID = 1
    return data
end

local function fixture(items, options)
    local state = options or {}
    state.items = items
    state.bags = state.bags or {}
    state.bags[0] = state.items
    state.numBagSlots = state.numBagSlots or 0
    state.timers = {}
    state.tooltipReads = {}
    state.containerReads = {}
    state.counts = state.counts or {}
    state.settings = state.settings or {
        enabled = true, hideInCombat = false, hideCompletedItems = true,
        pinnedItems = {}, bannedItems = {}, categories = {},
        order = {"combination", "darkmoon", "containers", "currency", "custom"},
    }
    local byID = {}
    for _, entry in ipairs(items) do byID[entry.itemID] = entry end
    for bag, contents in pairs(state.bags) do
        if bag ~= 0 then
            for _, entry in ipairs(contents) do byID[entry.itemID] = entry end
        end
    end
    local function bagItems(bag)
        return bag == 0 and state.items or (state.bags[bag] or {})
    end
    local function bagSlotKey(bag, slot)
        return bag == 0 and slot or (tostring(bag) .. ":" .. tostring(slot))
    end

    local label = {}
    function label:SetText(value) self.text = value end
    function label:GetStringWidth() return #(self.text or "") * 6 end
    function label:SetTexture(value) self.texture = value end
    local function newLabel() return setmetatable({}, {__index = label}) end
    local button = {
        attributes = {}, shown = false,
        _queueTitle = newLabel(), _queueSub = newLabel(),
        _queueAction = newLabel(), _queueIcon = newLabel(),
    }
    local function protected(operation)
        check(not state.combat, "protected " .. operation .. " attempted during combat")
    end
    function button:Show() protected("Show"); self.shown = true end
    function button:Hide() protected("Hide"); self.shown = false end
    function button:SetAttribute(key, value) protected("SetAttribute"); self.attributes[key] = value end
    function button:SetWidth(value) protected("SetWidth"); self.width = value end
    state.button = button
    state.gate = {Show = function() protected("combat gate Show") end}
    state.events = {
        SetScript = function(self, name, callback)
            check(name == "OnEvent", "test event frame only supports OnEvent")
            self.onEvent = callback
        end,
    }

    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.NUM_BAG_SLOTS = state.numBagSlots
    env.Enum = { BagIndex = {ReagentBag = 5}, CraftingReagentType = {Basic = 0, Modifying = 1, Finishing = 2} }
    env.InCombatLockdown = function() return state.combat == true end
    env.RegisterStateDriver = function(_, _, value) protected("RegisterStateDriver"); state.visibilityDriver = value end
    env.UnregisterStateDriver = function() protected("UnregisterStateDriver"); state.visibilityDriver = nil end
    env.UIParent = {GetWidth = function() return 1920 end}
    env.C_Container = {
        GetContainerNumSlots = function(bag) return #bagItems(bag) end,
        GetContainerItemInfo = function(bag, slot)
            local key = bagSlotKey(bag, slot)
            state.containerReads[key] = (state.containerReads[key] or 0) + 1
            return bagItems(bag)[slot]
        end,
    }
    env.C_TooltipInfo = {
        GetBagItem = function(bag, slot)
            local entry = bagItems(bag)[slot]
            if not entry then return nil end
            local key = bagSlotKey(bag, slot)
            local count = (state.tooltipReads[key] or 0) + 1
            state.tooltipReads[key] = count
            if entry.tooltips then return entry.tooltips[math.min(count, #entry.tooltips)] end
            return entry.tooltip
        end,
    }
    env.C_Item = {
        IsItemDataCachedByID = function(id) return byID[id] and byID[id].cached ~= false end,
        RequestLoadItemDataByID = function() state.loadRequests = (state.loadRequests or 0) + 1 end,
        GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, byID[id] and byID[id].classID or 0 end,
        GetItemInfo = function(id) return byID[id] and byID[id].name or ("Item " .. id), nil, 1 end,
        GetItemSpell = function(id) return "Combine", byID[id] and byID[id].spellID end,
        GetItemCount = function(id, includeBank)
            if includeBank then return (state.counts[id] or 0) + (state.bankCounts and state.bankCounts[id] or 0) end
            return state.counts[id] or 0
        end,
        IsUsableItem = function(id) return not byID[id] or byID[id].usable ~= false end,
    }
    env.C_TradeSkillUI = {GetRecipeSchematic = function(spellID)
        state.schematicReads = (state.schematicReads or 0) + 1
        return state.schematics and state.schematics[spellID]
    end}
    env.C_CurrencyInfo = {GetCurrencyInfo = function(id)
        return state.currencies and state.currencies[id] and {quantity = state.currencies[id], name = "Currency " .. id}
    end}
    env.C_Timer = {After = function(delay, callback) state.timers[#state.timers + 1] = {delay = delay, callback = callback} end}
    env.testState = state

    local stubs = [[
local function GetItemQueueSettings() return testState.settings end
local function IsSafeText(v) return type(v) == "string" and v ~= "" end
local function IsSafeNumber(v) return type(v) == "number" end
local function EnsureItemQueueButton()
    assert(itemQueueButton or not testState.combat, "protected queue button initialized during combat")
    itemQueueButton = testState.button
    itemQueueCombatGate = testState.gate
    return itemQueueButton
end
local function GetItemQueueColor() return 1, 1, 1 end
local function HideItemQueueTooltip() end
local function ShowItemQueueTooltip() end
local function SetItemQueueActionState() end
local events = testState.events
local function InstallHooks() end
local function QueueRefresh() testState.vendorRefreshes = (testState.vendorRefreshes or 0) + 1 end
]]
    local factory, err = load(preamble .. stubs .. queueCode .. diagnosticsCode .. combatVisibilityCode .. refreshCode .. eventCode .. apiCode,
        "@production-item-queue-scan", "t", env)
    check(factory, err)
    state.api = factory("WaffleHouse_EllesmereUI", {})
    return state
end

local passed, failures = 0, {}
local function test(name, run)
    local ok, err = pcall(run)
    if ok then
        passed = passed + 1
        io.write("PASS: " .. name .. "\n")
    else
        failures[#failures + 1] = name .. ": " .. tostring(err)
        io.write("FAIL: " .. failures[#failures] .. "\n")
    end
end

local function timerCount(state, delay)
    local count = 0
    for _, timer in ipairs(state.timers) do
        if timer.delay == delay then count = count + 1 end
    end
    return count
end

local function runTimers(state, delay)
    local due, remaining = {}, {}
    for _, timer in ipairs(state.timers) do
        if timer.delay == delay then due[#due + 1] = timer else remaining[#remaining + 1] = timer end
    end
    state.timers = remaining
    check(#due > 0, "missing timer at " .. tostring(delay))
    for _, timer in ipairs(due) do timer.callback() end
end

test("raw Amani tooltip without rendered reagent rows cannot bypass schematic requirements", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001, classID = 1})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1},
    })
    state.settings.order = {"custom", "containers", "combination", "darkmoon"}
    state.settings.pinnedItems[AMANI_ID] = true
    check(#state.api.scan() == 0, "missing Haft/Wrap must reject pinned/container fallback even though raw tooltip has no x/y rows")
    state.api.refresh()
    check(not state.button.shown, "incomplete Amani must never be displayed")
end)

test("one immutable tooltip snapshot per bag item prevents second-read partial overwrite", function()
    local state = fixture({item(AMANI_ID, {tooltips = {AMANI_INCOMPLETE_TOOLTIP, AMANI_TOOLTIP}, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1},
    })
    check(#state.api.scan() == 0, "first known missing-components result must survive the scan")
    check(state.tooltipReads[1] == 1, "bag scan must classify the same snapshot it checked")
end)

test("all carried components automatically restore eligibility", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1},
    })
    check(#state.api.scan() == 0, "fixture must initially be incomplete")
    state.counts[HAFT_ID], state.counts[265560] = 1, 1
    local candidates = state.api.scan()
    check(#candidates == 1 and candidates[1].category == "combination", "complete recipe must clear automatic block")
    state.api.refresh()
    check(state.button.shown and state.button.attributes.macrotext1 == "/use [nocombat] 0 1",
        "complete combination must arm its occupied slot with a combat guard")
end)

test("bank-only reagents do not satisfy carried-component use", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1}, bankCounts = {[HAFT_ID] = 1, [265560] = 1},
    })
    check(#state.api.scan() == 0, "bank-only Haft/Wrap must not satisfy bag-use requirements")
end)

test("cold tooltip and missing schematic data defer then recover", function()
    local entry = item(AMANI_ID, {tooltip = tooltip("Tempered Amani Spearhead"), spellID = 9001, cached = false})
    local state = fixture({entry}, {schematics = {}, counts = {[AMANI_ID] = 1, [HAFT_ID] = 1, [265560] = 1}})
    state.settings.pinnedItems[AMANI_ID] = true
    check(#state.api.scan() == 0, "cold pinned item must defer")
    check(#state.timers > 0, "cold data must schedule retry")
    entry.cached, entry.tooltip = true, AMANI_TOOLTIP
    check(#state.api.scan() == 0, "missing schematic must defer, never cache an empty-requirements success")
    state.schematics[9001] = amaniSchematic()
    local timers = state.timers
    state.timers = {}
    for _, timer in ipairs(timers) do timer.callback() end
    check(state.button.shown and #state.api.candidates() == 1,
        "queued retry must read the later schematic and display the complete combination without another bag event")
end)

test("known incomplete state survives a later unavailable schematic", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1},
    })
    check(#state.api.scan() == 0, "initial missing components must block")
    state.schematics[9001] = nil
    check(#state.api.scan() == 0, "a transient missing schematic must not clear a verified block")
end)

test("legitimate combination with an available empty schematic remains eligible", function()
    local state = fixture({item(42, {tooltip = tooltip("Fragments", "Use: Combine these fragments into a key."), spellID = 9002})}, {
        schematics = {[9002] = {reagentSlotSchematics = {}}},
    })
    local candidates = state.api.scan()
    check(#candidates == 1 and candidates[1].category == "combination", "no-component combination must remain usable")
end)

test("currency grants queue under the dedicated currency category", function()
    local state = fixture({item(265784, {
        name = "Nahuut's Second-Favorite Chew Toy",
        tooltip = tooltip("Nahuut's Second-Favorite Chew Toy", "Use: Gain a large amount of Voidlight Marl."),
    })})
    local candidates = state.api.scan()
    check(#candidates == 1 and candidates[1].category == "currency",
        "a usable Voidlight Marl grant must show as a Currency Item instead of being excluded")
end)

test("Surplus Auchenai Weaponry's numeric Garrison Resources grant reaches the popup", function()
    local state = fixture({item(116118, {
        name = "Surplus Auchenai Weaponry",
        tooltip = tooltip("Surplus Auchenai Weaponry", "Soulbound",
            "Use: Gain 100 Garrison Resources.", "No sell price"),
    })})
    local candidates = state.api.scan()
    check(#candidates == 1 and candidates[1].category == "currency",
        "numeric Garrison Resources grants must enter the Currency category")
    state.api.refresh()
    check(state.button.shown and state.button._queueItem.itemID == 116118,
        "the popup should show the usable Auchenai currency item")
end)

test("Pepe costume use wording reaches the appearance queue and secure item button", function()
    local state = fixture({item(42, {
        name = "A Tiny Explorer's Hat", usable = false,
        tooltip = tooltip("|cff1eff00A Tiny Explorer's Hat|r", "Soulbound", "Unique",
            "|cff1eff00Use: When summoned, Pepe will", "sometimes be dressed like an explorer.|r", "(1 Sec Cooldown)"),
    })})
    state.settings.order = { "appearances", "pets", "custom" }
    local candidates = state.api.scan()
    check(#candidates == 1 and candidates[1].category == "appearances",
        "the screenshot's wrapped/colorized costume wording must qualify even when IsUsableItem misses the cosmetic")
    state.api.refresh()
    check(state.button.shown and state.button._queueTitle.text == "A Tiny Explorer's Hat",
        "recognized Pepe costumes must appear on the actual queue button")
    check(state.button.attributes.macrotext1 == "/use 0 1", "Pepe must retain the secure manual bag-use action")
end)

test("Pepe costumes retain completion, category, and explicit-ban gates", function()
    local function makeState(known)
        local state = fixture({item(42, { name = "A Tiny Explorer's Hat",
            tooltip = tooltip("A Tiny Explorer's Hat", "Use: When summoned, Pepe will sometimes be dressed like an explorer.",
                known and "Already Known" or "Soulbound"),
        })})
        state.settings.order = { "appearances", "custom" }
        return state
    end
    local state = makeState(true)
    check(#state.api.scan() == 0, "already-known costumes must remain hidden")
    state = makeState(false); state.settings.categories.appearances = false
    check(#state.api.scan() == 0, "disabling Appearance Unlocks must hide Pepe costumes")
    state = makeState(false); state.settings.bannedItems[42] = true
    check(#state.api.scan() == 0, "a permanent ban must still win over Pepe recognition")
    state = makeState(false); state.api.banUntilReload(42)
    check(#state.api.scan() == 0, "a session hide must still win over Pepe recognition")
end)

test("reusable Pepe whistles do not become costume queue candidates", function()
    local state = fixture({item(43, { name = "Trans-Dimensional Bird Whistle",
        tooltip = tooltip("Trans-Dimensional Bird Whistle", "Use: Summon Pepe to ride on your head."),
    })})
    state.settings.order = { "appearances", "pets", "custom" }
    check(#state.api.scan() == 0, "mentioning Pepe or summoning him must not match costume unlocks")
end)

test("required item alternatives and currencies are counted while optional reagents are ignored", function()
    local state = fixture({item(43, {tooltip = tooltip("Assembly", "Use: Reform the assembly."), spellID = 9003})}, {
        schematics = {[9003] = {reagentSlotSchematics = {
            {required = true, quantityRequired = 2, reagents = {{itemID = 501}, {itemID = 502}}},
            {required = true, quantityRequired = 3, reagents = {{currencyID = 7}}},
            {required = false, quantityRequired = 99, reagents = {{itemID = 503}}},
        }}}, counts = {[501] = 1, [502] = 1}, currencies = {[7] = 2},
    })
    check(#state.api.scan() == 0, "missing required currency must block an otherwise supplied combination")
    state.currencies[7] = 3
    check(#state.api.scan() == 1, "alternative ranks must sum and absent optional reagents must not block")
    state.counts[501] = 0
    check(#state.api.scan() == 0, "losing one required alternative must block again")
end)

test("diagnostics show live requirements and retained admission evidence without changing eligibility state", function()
    local entry = item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})
    local state = fixture({entry}, {schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1}})
    check(#state.api.scan() == 0 and state.api.automaticBlock(AMANI_ID), "fixture must record an actual rejected scan")
    local lastDecision = state.api.lastDecisions()["0:1"]
    state.counts[HAFT_ID], state.counts[265560] = 1, 1
    local timerCount = #state.timers
    local report = state.api.diagnostics(entry, 0, 1)
    for _, fragment in ipairs({"Bag / slot: 0 / 1", "Item ID: " .. AMANI_ID, "Normalized scanner data:",
        "Use spell: 9001", "carried/required=1/1", "Category matches:", "Final decision:", "LAST ACTUAL SCAN:",
        "Temporarily blocked:"}) do
        check(report:find(fragment, 1, true), "diagnostic is missing " .. fragment)
    end
    check(state.api.automaticBlock(AMANI_ID), "fresh diagnostic must not mutate the last automatic block")
    check(state.api.lastDecisions()["0:1"] == lastDecision, "fresh diagnostic must retain the actual scan record")
    check(#state.timers == timerCount and not state.button.shown, "read-only diagnostics must not schedule or display a queue item")
end)

local function darkmoonTooltip(missing)
    local lines = {"Ace of Hunt", "Use: Combine the Ace through Eight of Hunt to complete the set."}
    for index, name in ipairs({"Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"}) do
        lines[#lines + 1] = name .. " of Hunt " .. ((missing and index == 1) and "0/1" or "1/1")
    end
    return tooltip(table.unpack(lines))
end

test("incomplete Darkmoon deck cannot use a pinned fallback", function()
    local state = fixture({item(101, {tooltip = darkmoonTooltip(true)})})
    state.settings.pinnedItems[101] = true
    state.settings.order = {"custom", "darkmoon", "combination", "containers", "currency"}
    check(#state.api.scan() == 0, "incomplete pinned Darkmoon must stay excluded")
end)

test("completed Darkmoon deck is deduplicated across pinned category priority", function()
    local state = fixture({item(101, {tooltip = darkmoonTooltip(false)}), item(102, {tooltip = darkmoonTooltip(false)})})
    state.settings.pinnedItems[101], state.settings.pinnedItems[102] = true, true
    state.settings.order = {"custom", "darkmoon", "combination", "containers", "currency"}
    check(#state.api.scan() == 1, "one completed deck must produce exactly one candidate even when pinned category wins")
end)

test("automatic unblocking preserves permanent and until-reload bans", function()
    local state = fixture({item(42, {tooltip = tooltip("Fragments", "Use: Combine these fragments into a key."), spellID = 9002})}, {
        schematics = {[9002] = {reagentSlotSchematics = {}}},
    })
    state.settings.bannedItems[42] = true
    check(#state.api.scan() == 0, "permanent ban must remain authoritative")
    state.settings.bannedItems[42] = nil
    state.api.banUntilReload(42)
    check(#state.api.scan() == 0, "until-reload ban must remain authoritative")
end)

test("refresh clears stale displayed item and secure action when no candidates remain", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1, [HAFT_ID] = 1, [265560] = 1},
    })
    state.api.refresh()
    check(state.button.shown and state.button._queueItem, "initial complete item must display")
    state.counts[HAFT_ID] = 0
    state.api.refresh()
    check(not state.button.shown and not state.button._queueItem, "rejected item must not remain as displayed/current candidate")
    check(not state.button.attributes.type1 and not state.button.attributes.macrotext1, "empty queue must clear old secure use action out of combat")
end)

test("scheduled combination follow-up replaces the initial displayed decision with fresh component counts", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1, [HAFT_ID] = 1, [265560] = 1},
    })
    state.api.schedule()
    check(timerCount(state, 0.1) == 1 and timerCount(state, 0.4) == 0,
        "initial event work must be debounced before deciding whether a follow-up is needed")
    runTimers(state, 0.1)
    check(state.button.shown, "initial complete snapshot must display")
    check(timerCount(state, 0.4) == 1, "combination requirement data must retain its targeted hydration follow-up")
    state.counts[265560] = 0
    runTimers(state, 0.4)
    check(not state.button.shown and not state.button._queueItem,
        "follow-up scan must remove an item whose newly hydrated counts show missing components")
end)

test("unrelated item-data events do not read carried tooltips", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.refresh()
    local reads = state.tooltipReads[1]
    state.api.event("GET_ITEM_INFO_RECEIVED", 999999, true)
    state.api.event("ITEM_DATA_LOAD_RESULT", 999999, false)
    check(#state.timers == 0, "untracked or failed item-data events must not schedule queue work")
    check(state.tooltipReads[1] == reads, "unrelated item-data events must not read queue tooltips")
end)

test("one item-data notification refreshes every matching stack and no other slot", function()
    local state = fixture({
        item(42, {tooltip = tooltip("Cache A", "Use: Open to receive rewards."), classID = 1}),
        item(42, {tooltip = tooltip("Cache B", "Use: Open to receive rewards."), classID = 1}),
        item(43, {tooltip = tooltip("Cache C", "Use: Open to receive rewards."), classID = 1}),
    })
    state.api.refresh()
    local first, second, other = state.tooltipReads[1], state.tooltipReads[2], state.tooltipReads[3]
    state.api.event("GET_ITEM_INFO_RECEIVED", 42, true)
    check(timerCount(state, 0.1) == 1, "matching carried item data must create one debounce")
    runTimers(state, 0.1)
    check(state.tooltipReads[1] == first + 1 and state.tooltipReads[2] == second + 1,
        "all stacks of the matching item ID must refresh")
    check(state.tooltipReads[3] == other, "targeted item data must not rescan other slots")
end)

test("multiple item-data notifications merge into one targeted refresh", function()
    local state = fixture({
        item(42, {tooltip = tooltip("Cache A", "Use: Open to receive rewards."), classID = 1}),
        item(43, {tooltip = tooltip("Cache B", "Use: Open to receive rewards."), classID = 1}),
        item(44, {tooltip = tooltip("Cache C", "Use: Open to receive rewards."), classID = 1}),
    })
    state.api.refresh()
    local first, second, other = state.tooltipReads[1], state.tooltipReads[2], state.tooltipReads[3]
    state.api.event("GET_ITEM_INFO_RECEIVED", 42, true)
    state.api.event("ITEM_DATA_LOAD_RESULT", 43, true)
    check(timerCount(state, 0.1) == 1, "bursty item data must share one debounce timer")
    runTimers(state, 0.1)
    check(state.tooltipReads[1] == first + 1 and state.tooltipReads[2] == second + 1,
        "coalesced item IDs must each refresh once")
    check(state.tooltipReads[3] == other, "coalesced item IDs must preserve unrelated cached slots")
end)

test("tooltip data updates resolve ownership through the captured instance", function()
    local trackedTooltip = tooltip("Cache A", "Use: Open to receive rewards.")
    trackedTooltip.dataInstanceID = 701
    local state = fixture({
        item(42, {tooltip = trackedTooltip, classID = 1}),
        item(43, {tooltip = tooltip("Cache B", "Use: Open to receive rewards."), classID = 1}),
    })
    state.api.refresh()
    local first, other = state.tooltipReads[1], state.tooltipReads[2]
    state.api.event("TOOLTIP_DATA_UPDATE", 999)
    check(#state.timers == 0, "unknown tooltip instances must not refresh the queue")
    state.api.event("TOOLTIP_DATA_UPDATE", 701)
    runTimers(state, 0.1)
    check(state.tooltipReads[1] == first + 1 and state.tooltipReads[2] == other,
        "known tooltip instances must refresh only their owning item")
end)

test("targeted cache refresh preserves Darkmoon deduplication and candidate priority", function()
    local state = fixture({item(101, {tooltip = darkmoonTooltip(false)}), item(102, {tooltip = darkmoonTooltip(false)})})
    state.settings.pinnedItems[101], state.settings.pinnedItems[102] = true, true
    state.settings.order = {"custom", "darkmoon", "combination", "containers", "currency"}
    state.api.refresh()
    check(#state.api.candidates() == 1 and state.api.candidates()[1].itemID == 101,
        "initial cache must keep one highest-priority deck candidate")
    state.api.event("GET_ITEM_INFO_RECEIVED", 101, true)
    runTimers(state, 0.1)
    check(#state.api.candidates() == 1 and state.api.candidates()[1].itemID == 101,
        "refreshing one deck card must retain cached duplicate suppression and ordering")
end)

test("targeted refresh reconciles a moved or removed slot before arming it", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.refresh()
    check(state.button.shown and state.button._queueItem, "fixture must first display the occupied slot")
    state.items = {}
    state.api.refresh({[42] = true})
    check(not state.button.shown and not state.button._queueItem,
        "a targeted notification after removal must invalidate the stale cached slot")
end)

test("bag updates disarm a changed displayed slot before the delayed bag reconciliation", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.refresh()
    check(state.button.shown and state.button.attributes.macrotext1, "fixture must arm the initial bag slot")
    state.items = {}
    state.api.event("BAG_UPDATE", 0)
    check(not state.button.shown and not state.button._queueItem and not state.button.attributes.macrotext1,
        "a changed bag must immediately disarm its stale secure action")
    check(#state.timers == 0, "per-bag notifications only mark dirty state until BAG_UPDATE_DELAYED")
    state.api.event("BAG_UPDATE_DELAYED")
    check(timerCount(state, 0.1) == 1, "BAG_UPDATE_DELAYED must schedule the dirty-bag reconciliation")
    runTimers(state, 0.1)
    check(#state.api.candidates() == 0, "the delayed dirty-bag scan must retain the removed-slot result")
end)

test("a dirty bag refresh does not read or enumerate an unchanged second bag", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache A", "Use: Open to receive rewards."), classID = 1})}, {
        numBagSlots = 1,
        bags = {[1] = {item(43, {tooltip = tooltip("Cache B", "Use: Open to receive rewards."), classID = 1})}},
    })
    state.api.refresh()
    local otherTooltipReads, otherContainerReads = state.tooltipReads["1:1"], state.containerReads["1:1"]
    state.items[1].stackCount = 2
    state.api.event("BAG_UPDATE", 0)
    state.api.event("BAG_UPDATE_DELAYED")
    runTimers(state, 0.1)
    check(state.tooltipReads["1:1"] == otherTooltipReads,
        "a dirty bag must not reread tooltip data from an unchanged bag")
    check(state.containerReads["1:1"] == otherContainerReads,
        "a dirty bag must not enumerate unchanged-bag slot metadata")
end)

test("a bag change rechecks a combination dependency in another bag", function()
    local state = fixture({item(HAFT_ID, {tooltip = tooltip("Reinforced Amani Haft", "Crafting Reagent"), classID = 1})}, {
        numBagSlots = 1,
        bags = {[1] = {item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}},
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1, [HAFT_ID] = 1, [265560] = 1},
    })
    state.api.refresh()
    check(state.button.shown and state.button._queueItem.itemID == AMANI_ID, "fixture must first queue the complete cross-bag combination")
    local combinationReads = state.tooltipReads["1:1"]
    state.items = {}
    state.counts[HAFT_ID] = 0
    state.api.event("BAG_UPDATE", 0)
    state.api.event("BAG_UPDATE_DELAYED")
    runTimers(state, 0.1)
    check(state.tooltipReads["1:1"] == combinationReads + 1,
        "changed carried components must re-evaluate an unchanged combination slot")
    check(not state.button.shown and #state.api.candidates() == 0,
        "missing a carried component in another bag must remove the combination candidate")
end)

test("a pending dirty-bag and item-data batch refreshes the unchanged bag item", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache A", "Use: Open to receive rewards."), classID = 1})}, {
        numBagSlots = 1,
        bags = {[1] = {item(43, {tooltip = tooltip("Cache B", "Use: Open to receive rewards."), classID = 1})}},
    })
    state.api.refresh()
    local otherReads = state.tooltipReads["1:1"]
    state.items[1].stackCount = 2
    state.api.event("BAG_UPDATE", 0)
    state.api.event("GET_ITEM_INFO_RECEIVED", 43, true)
    state.api.event("BAG_UPDATE_DELAYED")
    check(timerCount(state, 0.1) == 1, "bag and item-data notifications must merge into one refresh")
    runTimers(state, 0.1)
    check(state.tooltipReads["1:1"] == otherReads + 1,
        "same-batch item data must still refresh its unchanged-bag item")
end)

test("tooltip retries refresh only unresolved items", function()
    local cold = item(42, {tooltip = tooltip("Cold cache"), cached = false, classID = 1})
    local state = fixture({cold, item(43, {tooltip = tooltip("Warm cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.refresh()
    local warmReads = state.tooltipReads[2]
    check(timerCount(state, 0.25) == 1, "cold tooltip data must retain its bounded retry")
    runTimers(state, 0.25)
    check(state.tooltipReads[2] == warmReads, "retrying unresolved data must not reread ordinary cached items")
end)

test("ordinary complete full refreshes do not add a delayed follow-up", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.schedule()
    check(timerCount(state, 0.1) == 1, "full scheduling must use its debounce")
    runTimers(state, 0.1)
    check(timerCount(state, 0.4) == 0, "ordinary complete items must not cause a full delayed rescan")
end)

test("event scheduling respects disabled and combat gates", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})})
    state.api.refresh()
    local reads = state.tooltipReads[1]
    state.settings.enabled = false
    state.api.event("GET_ITEM_INFO_RECEIVED", 42, true)
    check(#state.timers == 0 and state.tooltipReads[1] == reads, "disabled queue must ignore item-data work")
    state.settings.enabled = true
    state.combat = true
    state.api.event("GET_ITEM_INFO_RECEIVED", 42, true)
    check(#state.timers == 0, "combat must defer item-data refresh without protected work")
    state.combat = false
    state.api.event("PLAYER_REGEN_ENABLED")
    check(timerCount(state, 0.1) == 1, "leaving combat must schedule the deferred full refresh")
end)

test("combat refresh never changes protected visibility, size, or action attributes", function()
    local state = fixture({item(AMANI_ID, {tooltip = AMANI_TOOLTIP, spellID = 9001})}, {
        schematics = {[9001] = amaniSchematic()}, counts = {[AMANI_ID] = 1, [HAFT_ID] = 1, [265560] = 1},
    })
    state.api.refresh()
    check(state.visibilityDriver == "[combat] hide; show", "combination queue must use a secure combat visibility driver")
    state.combat = true
    state.api.refresh()
    state.counts[HAFT_ID] = 0
    state.api.refresh()
    state.settings.enabled = false
    state.api.refresh()
    state.combat = false
    state.api.refresh()
    check(not state.button.shown and not state.button._queueItem, "post-combat refresh must clear stale candidate")
end)

test("first queue refresh during combat defers protected frame initialization", function()
    local state = fixture({item(42, {tooltip = tooltip("Cache", "Use: Open to receive rewards."), classID = 1})}, {combat = true})
    state.api.refresh()
    check(not state.button.shown and not state.button.attributes.macrotext1, "combat initialization must leave secure action untouched")
    state.combat = false
    state.api.refresh()
    check(state.button.shown, "deferred first refresh must initialize normally after combat")
end)

check(#failures == 0, tostring(#failures) .. " Item Queue scanner/refresh regressions failed")
io.write("All " .. tostring(passed) .. " Item Queue scanner/refresh regressions passed\n")
