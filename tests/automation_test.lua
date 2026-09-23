-- Run from the addon source directory:
--   lua tests/automation_test.lua
--
-- Exercises WaffleHouse_Automation.lua through its public event frame with a
-- small Retail API mock. No test-only production hooks are required.

local SOURCE = arg[1] or "WaffleHouse_Automation.lua"

local frames = {}
function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    frames[#frames + 1] = frame
    return frame
end

local settings = {}
local options, availableQuests, activeQuests = {}, {}, {}
local selectedOptions, selectedRewards, selectedPlayerChoices, acceptedQuests, usedItems, repairs = {}, {}, {}, 0, {}, {}
local altDown, inCombat, now = false, false, 0
local playerChoiceInfo

C_Timer = { After = function(_, callback) callback() end }
C_GossipInfo = {
    GetOptions = function() return options end,
    GetAvailableQuests = function() return availableQuests end,
    GetActiveQuests = function() return activeQuests end,
    ForceGossip = function() return false end,
    SelectOption = function(optionID, _, confirmed)
        selectedOptions[#selectedOptions + 1] = { optionID = optionID, confirmed = confirmed }
    end,
    SelectAvailableQuest = function() end,
    SelectActiveQuest = function() end,
}
C_PlayerChoice = {
    GetCurrentPlayerChoiceInfo = function() return playerChoiceInfo end,
    SendPlayerChoiceResponse = function(responseID) selectedPlayerChoices[#selectedPlayerChoices + 1] = responseID end,
}
C_QuestLog = {
    IsQuestTrivial = function() return false end,
    IsQuestFlaggedCompletedOnAccount = function() return false end,
    QuestIgnoresAccountCompletedFiltering = function() return false end,
    ReadyForTurnIn = function() return false end,
    GetSelectedQuest = function() return 42 end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then return { quality = 0, isLocked = false, hasNoValue = false } end
    end,
    UseContainerItem = function(bag, slot) usedItems[#usedItems + 1] = { bag, slot } end,
}

NUM_BAG_SLOTS = 0
InCombatLockdown = function() return inCombat end
IsAltKeyDown = function() return altDown end
IsControlKeyDown = function() return false end
IsShiftKeyDown = function() return false end
IsInInstance = function() return false, "none" end
GetQuestID = function() return 42 end
GetTime = function() return now end
AcceptQuest = function() acceptedQuests = acceptedQuests + 1 end
IsQuestCompletable = function() return true end
CompleteQuest = function() end
GetNumQuestChoices = function() return 0 end
GetQuestReward = function(index) selectedRewards[#selectedRewards + 1] = index end
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return 100, true end
RepairAllItems = function(useGuild) repairs[#repairs + 1] = useGuild end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local addon = {
    GetSettings = function() return settings end,
}
local databaseSource = SOURCE:gsub("WaffleHouse_Automation%.lua$", "WaffleHouse_QuestAdvanceChoices.lua")
assert(databaseSource ~= SOURCE, "could not determine quest-advance database path")
assert(loadfile(databaseSource))("WaffleHouse_EllesmereUI", addon)
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
local events = assert(frames[1], "automation module must create an event frame")
local onEvent = assert(events.scripts.OnEvent, "automation module must register an event handler")

local function fire(event, ...)
    onEvent(events, event, ...)
end

local function reset()
    -- The production guard deliberately survives GOSSIP_CLOSED briefly so an
    -- NPC that closes and instantly reopens the same loop cannot restart it.
    -- Advance mock time between independent tests, then close any prior menu
    -- or merchant interaction held in module-local state.
    now = now + 10
    fire("GOSSIP_CLOSED")
    fire("MERCHANT_CLOSED")
    settings = {}
    options, availableQuests, activeQuests = {}, {}, {}
    selectedOptions, selectedRewards, selectedPlayerChoices, acceptedQuests, usedItems, repairs = {}, {}, {}, 0, {}, {}
    altDown, inCombat = false, false
    playerChoiceInfo = nil
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end
local function assertEqual(actual, expected, message)
    assert(actual == expected, string.format("%s (expected %s, got %s)", message or "values differ", tostring(expected), tostring(actual)))
end

test("single no-reward dialogue advances only when explicitly enabled", function()
    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 100, status = 0, rewards = {} } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "enabled single dialogue should advance")
    assertEqual(selectedOptions[1].optionID, 100, "wrong dialogue option selected")

    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 101, status = 0, rewards = { { id = 1 } } } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "reward-bearing option must remain untouched")
end)

test("pause and reverse gates prevent unwanted dialogue clicks", function()
    reset()
    settings.automation = { skipDialogue = true, pauseKey = "alt" }
    options = { { gossipOptionID = 100, status = 0, rewards = {} } }
    altDown = true
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "holding the pause key must stop automation")

    settings.automation.reverseMode = true
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "reverse mode must automate while the key is held")
end)

test("Shift is the default pause key and Disabled removes only the hold-to-pause modifier", function()
    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 125, status = 0, rewards = {} } }
    IsShiftKeyDown = function() return true end
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "the default Shift pause key must stop automation")

    fire("GOSSIP_CLOSED")
    settings.automation.pauseKey = "disabled"
    settings.automation.reverseMode = true -- stale setting from before Disabled was chosen
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "Disabled must leave normal automation active even with stale Reverse Mode")
    IsShiftKeyDown = function() return false end
end)

test("single-option dialogue cannot loop on repeated menus or rapid NPC reopen", function()
    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 151, status = 0, rewards = {} } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "initial single-option dialogue should advance once")

    -- A repeated refresh (and even a duplicate SHOW) must not erase the
    -- session claim and click the exact same menu again.
    fire("GOSSIP_OPTIONS_REFRESHED")
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "same menu must be blocked for the open conversation")

    -- Some broken conversations close and immediately reopen instead.  The
    -- short cross-close cooldown must catch that variant too.
    fire("GOSSIP_CLOSED")
    now = now + 0.25
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "rapid NPC reopen must not restart the loop")

    -- This is not a permanent lockout: after the safety window, a real new
    -- interaction with the NPC can still use the enabled feature once.
    fire("GOSSIP_CLOSED")
    now = now + 2.1
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 2, "a later new conversation should be allowed")
end)

test("active quest advances but offered quests keep single-option dialogue open", function()
    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 808, isComplete = true } }
    options = { { gossipOptionID = 160, status = 0, rewards = {}, flags = 0 } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "unmarked dialogue must not steal focus from a ready turn-in")

    -- A quest-marked single choice advances the active quest conversation; it
    -- is not a new quest accept and should not leave the player stuck here.
    options = { { gossipOptionID = 161, status = 0, rewards = {}, flags = 1 } }
    fire("GOSSIP_OPTIONS_REFRESHED")
    assertEqual(#selectedOptions, 1, "quest-marked active dialogue must advance")
    assertEqual(selectedOptions[1].optionID, 161, "wrong active quest dialogue selected")

    reset()
    settings.automation = { skipDialogue = true }
    availableQuests = { { questID = 809 } }
    options = { { gossipOptionID = 162, status = 0, rewards = {} } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "an offered quest must keep dialogue open")
end)

test("curated quest-advance database chooses only its verified multi-option branch", function()
    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93396, isComplete = false } }
    options = {
        { gossipOptionID = 180, status = 0, name = "Ask Kifaan to wait", flags = 1, rewards = {} },
        { gossipOptionID = 181, status = 0, name = "Encourage Kifaan to talk to his sister", flags = 1, rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "verified multi-option quest advance should select")
    assertEqual(selectedOptions[1].optionID, 181, "database selected the wrong quest branch")

    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93396, isComplete = false } }
    options = {
        { gossipOptionID = 182, status = 0, name = "Ask Kifaan to wait", flags = 1, rewards = {} },
        { gossipOptionID = 183, status = 0, name = "Say nothing", flags = 1, rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "unverified quest branches must remain for the player")
end)

test("one quest-marked active choice advances alongside ordinary dialogue", function()
    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93401, isComplete = false } }
    options = {
        { gossipOptionID = 184, status = 0, name = "Where does this voice lead?", flags = 1, rewards = {} },
        { gossipOptionID = 185, status = 0, name = "This sounds like a terrible idea.", flags = 0, rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "the one quest-marked active dialogue choice should advance")
    assertEqual(selectedOptions[1].optionID, 184, "the quest-marked dialogue choice should win")

    reset()
    settings.automation = { skipDialogue = true }
    availableQuests = { { questID = 93402 } }
    options = {
        { gossipOptionID = 190, status = 0, name = "Where does this voice lead?", flags = 1, rewards = {} },
        { gossipOptionID = 191, status = 0, name = "This sounds like a terrible idea.", flags = 0, rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "a unique quest-marked path should advance even before the quest is active")
    assertEqual(selectedOptions[1].optionID, 190, "the unique quest-marked path should win over ordinary dialogue")

    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93401, isComplete = false } }
    options = {
        { gossipOptionID = 186, status = 0, flags = 1, rewards = {} },
        { gossipOptionID = 187, status = 0, flags = 1, rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "multiple quest-marked branches must remain for the player")

    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93401, isComplete = false } }
    options = {
        { gossipOptionID = 188, status = 0, flags = 1, rewards = {} },
        { gossipOptionID = 189, status = 0, type = "vendor", rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "the quest continuation must win over a vendor service")
    assertEqual(selectedOptions[1].optionID, 188, "the vendor option must not open before the quest continuation")
end)

test("quest continuation stays first for active merchants and quest offers", function()
    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93403, isComplete = false } }
    options = {
        { gossipOptionID = 192, status = 0, type = "vendor", rewards = {} },
        { gossipOptionID = 193, status = 0, flags = 1, rewards = {} },
    }
    fire("MERCHANT_SHOW")
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "an open merchant must not suppress a quest continuation")
    assertEqual(selectedOptions[1].optionID, 193, "the quest continuation must be selected before merchant handling")

    reset()
    settings.automation = { skipDialogue = true, autoAcceptQuests = true }
    availableQuests = { { questID = 93404 } }
    options = {
        { gossipOptionID = 194, status = 0, flags = 1, rewards = {} },
        { gossipOptionID = 195, status = 0, type = "vendor", rewards = {} },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "a quest continuation must run before an offered quest is opened")
    assertEqual(selectedOptions[1].optionID, 194, "the continuation must win over both quest-offer and vendor routes")

    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 93405, isComplete = false } }
    options = {
        { gossipOptionID = 196, status = 0, type = "vendor", rewards = {} },
        { gossipOptionID = 197, status = 0, flags = 1, rewards = {} },
    }
    IsShiftKeyDown = function() return true end
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "holding the default Shift pause key must leave the quest continuation alone")
    IsShiftKeyDown = function() return false end
end)

test("a sole vendor service opens while other services remain manual", function()
    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 170, status = 0, rewards = {}, type = "vendor" } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "a one-option vendor menu should open its merchant")
    assertEqual(selectedOptions[1].optionID, 170, "wrong vendor option selected")
    fire("GOSSIP_OPTIONS_REFRESHED")
    assertEqual(#selectedOptions, 1, "the same vendor menu must not be selected again")

    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 171, status = 0, rewards = {}, isPurchaseOption = true } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "an explicitly marked sole vendor purchase option should open")

    reset()
    settings.automation = { skipDialogue = true }
    Enum = { GossipOptionType = { Gossip = 0, Vendor = 1, Trainer = 2 } }
    options = { { gossipOptionID = 172, status = 0, rewards = {}, type = Enum.GossipOptionType.Trainer } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "a trainer must remain manual")
    options = { { gossipOptionID = 173, status = 0, rewards = {}, type = Enum.GossipOptionType.Vendor } }
    fire("GOSSIP_OPTIONS_REFRESHED")
    assertEqual(#selectedOptions, 1, "the Retail vendor enum should open a sole merchant option")
    Enum = nil
end)

test("vendor auto-open preserves quest, choice, pause, and active-merchant safeguards", function()
    reset()
    settings.automation = { skipDialogue = true }
    options = {
        { gossipOptionID = 175, status = 0, rewards = {}, type = "vendor" },
        { gossipOptionID = 176, status = 0, rewards = {}, type = "gossip" },
    }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "a vendor among multiple gossip choices must stay manual")

    reset()
    settings.automation = { skipDialogue = true }
    activeQuests = { { questID = 809 } }
    options = { { gossipOptionID = 177, status = 0, rewards = {}, type = "vendor" } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "an active quest must not lose focus to vendor auto-open")

    reset()
    settings.automation = { skipDialogue = true }
    availableQuests = { { questID = 810 } }
    options = { { gossipOptionID = 178, status = 0, rewards = {}, type = "vendor" } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "an offered quest must not lose focus to vendor auto-open")

    reset()
    settings.automation = { skipDialogue = true, pauseKey = "alt" }
    altDown = true
    options = { { gossipOptionID = 179, status = 0, rewards = {}, type = "vendor" } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "the pause key must also pause vendor auto-open")

    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 180, status = 0, rewards = {}, type = "vendor" } }
    fire("MERCHANT_SHOW")
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 0, "an already-open merchant must not be reopened by gossip")
end)

test("a forced sole vendor opens but forced story dialogue stays visible", function()
    reset()
    settings.automation = { skipDialogue = true }
    local originalForceGossip = C_GossipInfo.ForceGossip
    C_GossipInfo.ForceGossip = function() return true end
    options = { { gossipOptionID = 181, status = 0, rewards = {}, type = "vendor" } }
    fire("GOSSIP_SHOW")
    local vendorSelections = #selectedOptions

    reset()
    settings.automation = { skipDialogue = true }
    options = { { gossipOptionID = 182, status = 0, rewards = {}, type = "gossip" } }
    fire("GOSSIP_SHOW")
    local storySelections = #selectedOptions
    C_GossipInfo.ForceGossip = originalForceGossip

    assertEqual(vendorSelections, 1, "forced one-option vendor gossip should still open the merchant")
    assertEqual(storySelections, 0, "forced ordinary dialogue must remain for the player")
end)

test("campaign confirmation is accepted only for Waffle House's selected skip", function()
    reset()
    settings.automation = { selectCampaignSkips = true }
    options = { { gossipOptionID = 200, status = 0, name = "Campaign Skip", rewards = {} } }
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 1, "campaign skip should be selected")
    fire("GOSSIP_CONFIRM", 999)
    assertEqual(#selectedOptions, 1, "unrelated confirmation must not be accepted")
    fire("GOSSIP_CONFIRM", 200)
    assertEqual(#selectedOptions, 2, "selected campaign skip should be confirmed")
    assertEqual(selectedOptions[2].confirmed, true, "campaign skip confirmation must set confirmed")
end)

test("quest filters prevent accepting trivial or warband-completed quests", function()
    reset()
    settings.automation = { autoAcceptQuests = true, skipLowLevelQuests = true }
    C_QuestLog.IsQuestTrivial = function() return true end
    fire("QUEST_DETAIL")
    assertEqual(acceptedQuests, 0, "trivial quest must not be accepted")

    C_QuestLog.IsQuestTrivial = function() return false end
    C_QuestLog.IsQuestFlaggedCompletedOnAccount = function() return true end
    settings.automation.skipWarbandCompleted = true
    fire("QUEST_DETAIL")
    assertEqual(acceptedQuests, 0, "warband-completed quest must not be accepted")

    C_QuestLog.IsQuestFlaggedCompletedOnAccount = function() return false end
    fire("QUEST_DETAIL")
    assertEqual(acceptedQuests, 1, "eligible quest should be accepted")
end)

test("quest turn-in never guesses among multiple rewards", function()
    reset()
    settings.automation = { autoCompleteQuests = true }
    GetNumQuestChoices = function() return 2 end
    fire("QUEST_COMPLETE")
    assertEqual(#selectedRewards, 0, "multiple reward choices must remain for the player")

    GetNumQuestChoices = function() return 1 end
    fire("QUEST_COMPLETE")
    assertEqual(#selectedRewards, 1, "a single reward choice should turn in")
    assertEqual(selectedRewards[1], 1, "single reward must use the first reward index")
end)

test("known Ethereal Tool racks choose the active specialization's best available stat", function()
    reset()
    settings.automation = { autoChooseEtherealTools = true }
    playerChoiceInfo = {
        choiceID = 7001,
        uiTextureKit = "genericplayerchoice",
        options = {
            { spellID = 1246612, buttons = { { id = 702 } } }, -- Haste
            { spellID = 1246610, buttons = { { id = 700 } } }, -- Primary
            { spellID = 1246611, buttons = { { id = 701 } } }, -- Mastery
            { spellID = 1246552, buttons = { { id = 703 } } }, -- Critical Strike
        },
    }
    fire("PLAYER_CHOICE_UPDATE")
    assertEqual(#selectedPlayerChoices, 1, "known Ethereal Tool rack should receive one selection")
    assertEqual(selectedPlayerChoices[1], 700, "primary-stat Ethereal Tool should be preferred")

    fire("PLAYER_CHOICE_UPDATE")
    assertEqual(#selectedPlayerChoices, 1, "a repeated Player Choice update must not submit twice")

    GetSpecialization = function() return 1 end
    GetSpecializationInfo = function() return 63 end -- Fire Mage
    fire("PLAYER_CHOICE_CLOSE")
    playerChoiceInfo = {
        choiceID = 7004,
        uiTextureKit = "genericplayerchoice",
        options = {
            { spellID = 1246612, buttons = { { id = 742 } } }, -- Haste
            { spellID = 1246611, buttons = { { id = 741 } } }, -- Mastery
            { spellID = 1246552, buttons = { { id = 743 } } }, -- Critical Strike
        },
    }
    fire("PLAYER_CHOICE_UPDATE")
    assertEqual(selectedPlayerChoices[2], 743, "Fire fallback should prefer critical strike")
    GetSpecialization, GetSpecializationInfo = nil, nil
end)

test("Ethereal Tool chooser leaves partial or paused player choices alone", function()
    reset()
    settings.automation = { autoChooseEtherealTools = true }
    playerChoiceInfo = {
        choiceID = 7002,
        uiTextureKit = "genericplayerchoice",
        options = {
            { spellID = 1246610, buttons = { { id = 710 } } },
            { spellID = 999999, buttons = { { id = 711 } } },
        },
    }
    fire("PLAYER_CHOICE_UPDATE")
    assertEqual(#selectedPlayerChoices, 0, "a mixed generic Player Choice must remain manual")

    playerChoiceInfo = {
        choiceID = 7003,
        uiTextureKit = "genericplayerchoice",
        options = {
            { spellID = 1246610, buttons = { { id = 720 } } },
            { spellID = 1246612, buttons = { { id = 722 } } },
        },
    }
    altDown = true
    settings.automation.pauseKey = "alt"
    fire("PLAYER_CHOICE_UPDATE")
    assertEqual(#selectedPlayerChoices, 0, "the existing pause key must stop Ethereal Tool selection")
end)

test("merchant automation sells before guild then personal repair", function()
    reset()
    settings.automation = { autoSellJunk = true, autoRepair = true, repairSource = "guildThenPersonal" }
    fire("MERCHANT_SHOW")
    assertEqual(#usedItems, 1, "gray item should be sold")
    assertEqual(#repairs, 2, "guild-first repair should make a personal fallback pass")
    assertEqual(repairs[1], true, "first repair must use guild funds")
    assertEqual(repairs[2], false, "second repair must use personal funds")
end)

test("Automation EUI page builds every control row with scrollable height", function()
    reset()
    local rowCount, headerCount = 0, 0
    local function button()
        return { SetScript = function() end }
    end
    EllesmereUI = {
        Widgets = {
            SectionHeader = function(_, _, _, _)
                headerCount = headerCount + 1
                return {}, 24
            end,
            DualRow = function(_, _, _, _, rightCfg)
                rowCount = rowCount + 1
                return {
                    _leftRegion = { _control = button() },
                    _rightRegion = rightCfg and { _control = button() } or nil,
                }, 50
            end,
        },
    }
    local totalHeight = addon.BuildAutomationPage({}, -6)
    assertEqual(headerCount, 5, "Automation page should group controls into five sections")
    assertEqual(rowCount, 10, "Automation page should build all control rows")
    assert(totalHeight >= 620, "Automation page must reserve enough scroll height for every row")
    EllesmereUI = nil
end)

test("taught NPC choices replay without recording the replay as a new choice", function()
    reset()
    settings.automation = { rememberChoices = true }
    options = { { gossipOptionID = 301, status = 0, rewards = {} } }
    UnitGUID = function() return "Creature-0-0-0-0-12345-0" end
    strsplit = function(_, value)
        local parts = {}
        for part in value:gmatch("[^-]+") do parts[#parts + 1] = part end
        return table.unpack(parts)
    end
    hooksecurefunc = function(target, method, callback)
        local original = target[method]
        target[method] = function(...)
            original(...)
            callback(...)
        end
    end
    fire("PLAYER_LOGIN")

    local rows = {}
    local function button()
        return {
            SetScript = function(self, name, callback)
                if name == "OnClick" then self.onClick = callback end
            end,
        }
    end
    EllesmereUI = {
        Widgets = {
            SectionHeader = function() return {}, 24 end,
            DualRow = function(_, _, _, _, rightCfg)
                local row = {
                    _leftRegion = { _control = button() },
                    _rightRegion = rightCfg and { _control = button() } or nil,
                }
                rows[#rows + 1] = row
                return row, 50
            end,
        },
    }
    addon.BuildAutomationPage({}, -6)
    assert(rows[8]._leftRegion._control.onClick, "Teach button must have an OnClick handler")
    rows[8]._leftRegion._control.onClick()
    C_GossipInfo.SelectOption(301)
    assertEqual(#selectedOptions, 1, "manual taught selection should happen once")
    assertEqual(settings.automation.rememberedChoices["npc:12345"] and settings.automation.rememberedChoices["npc:12345"]["301"], 301,
        "manual taught selection should be saved for this NPC menu")
    fire("GOSSIP_SHOW")
    assertEqual(#selectedOptions, 2, "remembered option should replay on the same NPC menu")
    EllesmereUI, UnitGUID, strsplit = nil, nil, nil
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, err = pcall(entry.callback)
    if not ok then
        failures = failures + 1
        io.stderr:write("FAIL: " .. entry.name .. "\n" .. tostring(err) .. "\n")
    end
end

if failures > 0 then
    io.stderr:write(string.format("%d of %d automation scenarios failed\n", failures, #tests))
    os.exit(1)
end

io.write(string.format("All %d automation scenarios passed\n", #tests))
