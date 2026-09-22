local addonName, addon = ...

-- Opt-in Retail automation for routine quest, gossip, cinematic, and merchant
-- interactions.  This module deliberately does not auto-confirm unrelated
-- popups or select a quest reward when the player has a choice to make.

local pendingActions = {}
local merchantSession = 0
local merchantInteractionActive = false
local teachingNPCKey
local teachingStartedAt
local selectingAutomationOption
local pendingCampaignConfirmation
local hooksInstalled

-- Skip Single-Option Dialogue is intentionally conservative.  A broken NPC
-- conversation can re-open the exact same one-option page immediately after
-- it is selected; without a session guard, OPTIONS_REFRESHED would click it
-- forever.  Keep this entirely session-local (never SavedVariables): one
-- exact menu may be advanced once per conversation, with a short cross-close
-- cooldown for NPCs that close and re-open their loop instead.
local singleOptionDialogueGuard = {
    active = false,
    seen = {},
    attempts = 0,
    stopped = false,
    noticeShown = false,
    recent = {},
}
local SINGLE_OPTION_DIALOGUE_MAX_STEPS = 8
local SINGLE_OPTION_DIALOGUE_REPEAT_COOLDOWN = 2

local AUTOMATION_SCOPES = {
    anywhere = "Anywhere",
    openWorld = "Open World",
    instances = "Instances",
}

local PAUSE_KEYS = {
    disabled = "Disabled",
    alt = "Alt",
    ctrl = "Ctrl",
    shift = "Shift",
}

local REPAIR_SOURCES = {
    guildThenPersonal = "Guild Bank, then Personal",
    personal = "Personal Funds Only",
    guild = "Guild Bank Only",
}

-- Ethereal Tool Racks use the generic Player Choice card UI. These spell IDs
-- identify the four stat buffs without depending on the localized card title
-- or description. Do not broaden this list to other generic Player Choices:
-- any unfamiliar card set deliberately remains a manual decision.
local ETHEREAL_TOOL_STAT_BY_SPELL_ID = {
    [1246610] = "primary", -- Celestial Carver
    [1246611] = "mastery", -- Arcanic Precision
    [1246612] = "haste", -- Energy Splinter
    [1246552] = "crit", -- Empyrean Zapper
}

local ETHEREAL_TOOL_PREFERENCES = {
    specialization = "Best for Specialization",
    primary = "Primary Stat",
    haste = "Haste",
    mastery = "Mastery",
    crit = "Critical Strike",
}

-- Primary stat comes first because the tool's five-percent bonus benefits the
-- active spec's actual Strength, Agility, or Intellect. Secondary priorities
-- are only fallbacks when the primary card is absent.
local ETHEREAL_TOOL_STAT_PRIORITY_BY_SPEC = {
    [71] = { "primary", "mastery", "crit", "haste" }, -- Arms
    [72] = { "primary", "haste", "mastery", "crit" }, -- Fury
    [73] = { "primary", "haste", "mastery", "crit" }, -- Protection Warrior
    [65] = { "primary", "crit", "mastery", "haste" }, -- Holy Paladin
    [66] = { "primary", "haste", "mastery", "crit" }, -- Protection Paladin
    [70] = { "primary", "mastery", "crit", "haste" }, -- Retribution
    [253] = { "primary", "mastery", "crit", "haste" }, -- Beast Mastery
    [254] = { "primary", "crit", "mastery", "haste" }, -- Marksmanship
    [255] = { "primary", "mastery", "crit", "haste" }, -- Survival
    [259] = { "primary", "mastery", "crit", "haste" }, -- Assassination
    [260] = { "primary", "haste", "crit", "mastery" }, -- Outlaw
    [261] = { "primary", "mastery", "crit", "haste" }, -- Subtlety
    [256] = { "primary", "mastery", "crit", "haste" }, -- Discipline
    [257] = { "primary", "mastery", "crit", "haste" }, -- Holy Priest
    [258] = { "primary", "haste", "mastery", "crit" }, -- Shadow
    [250] = { "primary", "mastery", "haste", "crit" }, -- Blood
    [251] = { "primary", "mastery", "crit", "haste" }, -- Frost
    [252] = { "primary", "mastery", "haste", "crit" }, -- Unholy
    [262] = { "primary", "mastery", "haste", "crit" }, -- Elemental
    [263] = { "primary", "mastery", "haste", "crit" }, -- Enhancement
    [264] = { "primary", "mastery", "crit", "haste" }, -- Restoration Shaman
    [62] = { "primary", "mastery", "haste", "crit" }, -- Arcane
    [63] = { "primary", "crit", "mastery", "haste" }, -- Fire
    [64] = { "primary", "mastery", "crit", "haste" }, -- Frost Mage
    [265] = { "primary", "haste", "mastery", "crit" }, -- Affliction
    [266] = { "primary", "haste", "mastery", "crit" }, -- Demonology
    [267] = { "primary", "mastery", "haste", "crit" }, -- Destruction
    [268] = { "primary", "mastery", "crit", "haste" }, -- Brewmaster
    [269] = { "primary", "crit", "mastery", "haste" }, -- Mistweaver
    [270] = { "primary", "mastery", "crit", "haste" }, -- Windwalker
    [102] = { "primary", "mastery", "haste", "crit" }, -- Balance
    [103] = { "primary", "mastery", "crit", "haste" }, -- Feral
    [104] = { "primary", "mastery", "haste", "crit" }, -- Guardian
    [105] = { "primary", "mastery", "haste", "crit" }, -- Restoration Druid
    [577] = { "primary", "crit", "mastery", "haste" }, -- Havoc
    [581] = { "primary", "mastery", "haste", "crit" }, -- Vengeance
    [1467] = { "primary", "mastery", "crit", "haste" }, -- Devastation
    [1468] = { "primary", "crit", "mastery", "haste" }, -- Preservation
    [1473] = { "primary", "mastery", "crit", "haste" }, -- Augmentation
}
local DEFAULT_ETHEREAL_TOOL_STAT_PRIORITY = { "primary", "haste", "mastery", "crit" }

local etherealToolSelection = {
    choiceID = nil,
    responseID = nil,
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function GetAutomationSettings()
    if type(addon) ~= "table" or type(addon.GetSettings) ~= "function" then return nil end
    local root = addon.GetSettings()
    if type(root) ~= "table" then return nil end

    if type(root.automation) ~= "table" then root.automation = {} end
    local settings = root.automation

    if settings.autoAcceptQuests == nil then settings.autoAcceptQuests = false end
    if settings.autoCompleteQuests == nil then settings.autoCompleteQuests = false end
    if settings.skipDialogue == nil then settings.skipDialogue = false end
    if settings.selectCampaignSkips == nil then settings.selectCampaignSkips = false end
    if settings.skipLowLevelQuests == nil then settings.skipLowLevelQuests = false end
    if settings.skipWarbandCompleted == nil then settings.skipWarbandCompleted = false end
    if settings.skipCinematics == nil then settings.skipCinematics = false end
    if settings.autoSellJunk == nil then settings.autoSellJunk = false end
    if settings.autoRepair == nil then settings.autoRepair = false end
    if settings.rememberChoices == nil then settings.rememberChoices = false end
    if settings.autoChooseEtherealTools == nil then settings.autoChooseEtherealTools = false end
    if AUTOMATION_SCOPES[settings.scope] == nil then settings.scope = "anywhere" end
    if PAUSE_KEYS[settings.pauseKey] == nil then settings.pauseKey = "shift" end
    if settings.reverseMode == nil then settings.reverseMode = false end
    if REPAIR_SOURCES[settings.repairSource] == nil then settings.repairSource = "guildThenPersonal" end
    if ETHEREAL_TOOL_PREFERENCES[settings.etherealToolPreference] == nil then
        settings.etherealToolPreference = "specialization"
    end
    if type(settings.rememberedChoices) ~= "table" then settings.rememberedChoices = {} end

    return settings
end

local function IsPauseKeyDown(key)
    if key == "disabled" then return false end
    if key == "ctrl" then return IsControlKeyDown and IsControlKeyDown() end
    if key == "shift" then return IsShiftKeyDown and IsShiftKeyDown() end
    return IsAltKeyDown and IsAltKeyDown()
end

local function IsScopeAllowed(scope)
    if scope == "anywhere" or not IsInInstance then return true end

    local inInstance, instanceType = IsInInstance()
    if scope == "openWorld" then return not inInstance end
    if scope == "instances" then
        -- Do not carry conversation automation into rated or battleground PvP.
        return inInstance and instanceType ~= "arena" and instanceType ~= "pvp"
    end
    return true
end

local function CanAutomate(settings)
    if not settings or (InCombatLockdown and InCombatLockdown()) then return false end
    if not IsScopeAllowed(settings.scope) then return false end

    -- Disabled means the optional hold-to-pause safeguard is off, not that
    -- automation itself is disabled.  Reverse Mode has no hold key to use in
    -- this state, so the normal opt-in automation behavior remains active.
    if settings.pauseKey == "disabled" then return true end

    local pauseDown = IsPauseKeyDown(settings.pauseKey)
    return settings.reverseMode and pauseDown or not pauseDown
end

local function QueueAction(key, callback, delay)
    if pendingActions[key] then return end
    pendingActions[key] = true

    local function run()
        pendingActions[key] = nil
        callback()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, run)
    else
        run()
    end
end

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff18d19eWaffle House:|r " .. message)
    end
end

local function GetEtherealToolStatPriority(settings)
    local preference = settings and settings.etherealToolPreference
    if preference and preference ~= "specialization" then
        local priority = { preference }
        for _, stat in ipairs(DEFAULT_ETHEREAL_TOOL_STAT_PRIORITY) do
            if stat ~= preference then priority[#priority + 1] = stat end
        end
        return priority
    end

    if GetSpecialization and GetSpecializationInfo then
        local specializationIndex = GetSpecialization()
        if type(specializationIndex) == "number" then
            local specializationID = GetSpecializationInfo(specializationIndex)
            local priority = ETHEREAL_TOOL_STAT_PRIORITY_BY_SPEC[specializationID]
            if priority then return priority end
        end
    end
    return DEFAULT_ETHEREAL_TOOL_STAT_PRIORITY
end

local function FindEtherealToolResponse(choiceInfo, settings)
    if not (choiceInfo and choiceInfo.uiTextureKit == "genericplayerchoice"
        and type(choiceInfo.options) == "table" and #choiceInfo.options >= 2) then
        return nil
    end

    local responseIDByStat = {}
    for _, option in ipairs(choiceInfo.options) do
        local stat = option and ETHEREAL_TOOL_STAT_BY_SPELL_ID[option.spellID]
        local button = option and option.buttons and option.buttons[1]
        -- Every offered card must be a known tool and must have exactly one
        -- available response. This is the safety boundary for all Player
        -- Choice content outside this exact Ethereal Tool Rack.
        if not (stat and option.disabledOption ~= true and type(option.buttons) == "table"
            and #option.buttons == 1 and button and button.disabled ~= true
            and type(button.id) == "number") then
            return nil
        end
        responseIDByStat[stat] = button.id
    end

    for _, stat in ipairs(GetEtherealToolStatPriority(settings)) do
        if responseIDByStat[stat] then return responseIDByStat[stat] end
    end
    return nil
end

local function TryChooseEtherealTool()
    local settings = GetAutomationSettings()
    if not (CanAutomate(settings) and settings.autoChooseEtherealTools
        and C_PlayerChoice and type(C_PlayerChoice.GetCurrentPlayerChoiceInfo) == "function"
        and type(C_PlayerChoice.SendPlayerChoiceResponse) == "function") then
        return
    end

    local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    local choiceID = choiceInfo and choiceInfo.choiceID
    if type(choiceID) ~= "number" then return end

    local responseID = FindEtherealToolResponse(choiceInfo, settings)
    if not responseID then return end
    if etherealToolSelection.choiceID == choiceID and etherealToolSelection.responseID == responseID then return end

    -- Claim before submitting: PLAYER_CHOICE_UPDATE may arrive synchronously
    -- while the client processes the response, and this prevents duplicate
    -- choices from the same rack.
    etherealToolSelection.choiceID = choiceID
    etherealToolSelection.responseID = responseID
    local ok = pcall(C_PlayerChoice.SendPlayerChoiceResponse, responseID)
    if not ok then
        etherealToolSelection.choiceID = nil
        etherealToolSelection.responseID = nil
    end
end

local function GetNPCChoiceKey()
    if not UnitGUID then return nil end
    local guid = UnitGUID("npc")
    if type(guid) ~= "string" or IsSecret(guid) then return nil end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if (unitType == "Creature" or unitType == "Vehicle") then
        npcID = tonumber(npcID)
        if npcID and npcID > 0 then return "npc:" .. npcID end
    end
    return nil
end

local function GetGossipOptions()
    if not (C_GossipInfo and type(C_GossipInfo.GetOptions) == "function") then return nil end
    local options = C_GossipInfo.GetOptions()
    return type(options) == "table" and options or nil
end

-- MerchantFrame remains shown while EllesmereUI renders its own vendor layout.
-- Treat that as an active merchant interaction even when a vendor also leaves
-- a normal-looking one-option gossip page open (for example Soul-Trader).
local function IsMerchantInteractionActive()
    local merchantFrame = _G and _G.MerchantFrame
    if merchantFrame and type(merchantFrame.IsShown) == "function" then
        merchantInteractionActive = merchantFrame:IsShown() == true
    end
    return merchantInteractionActive
end

local function GossipSignature(options)
    if type(options) ~= "table" or #options == 0 then return nil end

    local parts = {}
    for index, option in ipairs(options) do
        local optionID = option and option.gossipOptionID
        if type(optionID) ~= "number" then return nil end
        parts[index] = tostring(optionID)
    end
    return table.concat(parts, ":")
end

local function IsOptionSelectable(option)
    if not option or type(option.gossipOptionID) ~= "number" then return false end
    -- GossipOptionStatus.Available is zero.  Do not select locked, complete,
    -- or unavailable entries even if the UI happens to list just one.
    return option.status == nil or option.status == 0
end

local function HasOptionReward(option)
    return option and type(option.rewards) == "table" and #option.rewards > 0
end

-- Non-dialogue gossip options open a game service such as a vendor, trainer,
-- bank, flight path, or quest route.  Generic single-option skipping must not
-- consume any of them.  The enum check covers current and future service
-- types without guessing from localized option names.
local function IsServiceGossipOption(option)
    if not option then return false end
    local optionType = option.type
    local gossipType = Enum and Enum.GossipOptionType and Enum.GossipOptionType.Gossip
    if gossipType ~= nil and type(optionType) == "number" and optionType ~= gossipType then return true end
    if type(optionType) == "string" then
        optionType = optionType:lower()
        return optionType ~= "gossip" and optionType ~= "dialogue" and optionType ~= "normal"
    end
    return option.isVendor == true or option.isPurchaseOption == true
        or option.isTrainer == true or option.isBanker == true or option.isTaxi == true
end

local function GetGossipQuestInteractions()
    if not C_GossipInfo then return false, false end
    local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
    local available = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()
    return type(active) == "table" and #active > 0, type(available) == "table" and #available > 0
end

-- A quest-marked gossip choice is the safe exception to the normal quest
-- safeguard: it advances an active quest's NPC conversation rather than
-- accepting a new quest. The client exposes this through the option flags;
-- retain the explicit boolean fallbacks for API/test variants.
local function IsQuestAdvanceGossipOption(option)
    if not option then return false end
    return option.isQuestOption == true or option.isQuestGossip == true
        or (type(option.flags) == "number" and option.flags ~= 0)
end

local function NormalizeQuestAdvanceText(text)
    if type(text) ~= "string" or IsSecret(text) then return nil end
    text = text:lower():gsub("^%s*%d+%.%s*", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

-- A specific database entry is what lets us select safely among several
-- quest-advance choices. Generic single-option handling below remains useful
-- for linear dialogue, but a branching quest never receives a guessed click.
local function FindKnownQuestAdvanceChoice(activeQuests, options)
    local database = addon.QuestAdvanceChoices
    if type(database) ~= "table" or type(activeQuests) ~= "table" then return nil end
    local known, match
    for _, quest in ipairs(activeQuests) do
        known = quest and database[quest.questID]
        if type(known) == "table" then
            for _, option in ipairs(options or {}) do
                local name = NormalizeQuestAdvanceText(option and option.name)
                if name and known[name] and IsOptionSelectable(option) then
                    if match then return nil end -- never guess between two matches
                    match = option
                end
            end
        end
    end
    return match
end

-- Outside the curated database, the quest marker itself is enough only when
-- it identifies one quest path among otherwise ordinary NPC dialogue. Service
-- and reward options stay manual, as do real branch choices with two or more
-- quest-marked entries.
local function FindUniqueQuestAdvanceChoice(options)
    local match
    for _, option in ipairs(options or {}) do
        if IsOptionSelectable(option) then
            if IsQuestAdvanceGossipOption(option) then
                if match then return nil end
                match = option
            elseif IsServiceGossipOption(option) or HasOptionReward(option) then
                return nil
            end
        end
    end
    return match
end

local function IsCampaignSkipOption(option)
    if not (option and type(option.name) == "string") or IsSecret(option.name) then return false end
    return option.name:lower():find("campaign skip", 1, true) ~= nil
end

local function SelectGossipOption(optionID, confirmed)
    if not (C_GossipInfo and type(C_GossipInfo.SelectOption) == "function") then return false end
    selectingAutomationOption = true
    local ok = pcall(C_GossipInfo.SelectOption, optionID, nil, confirmed and true or nil)
    selectingAutomationOption = nil
    return ok
end

local function ResetSingleOptionDialogueSession()
    singleOptionDialogueGuard.active = false
    singleOptionDialogueGuard.seen = {}
    singleOptionDialogueGuard.attempts = 0
    singleOptionDialogueGuard.stopped = false
    singleOptionDialogueGuard.noticeShown = false
end

local function BeginSingleOptionDialogueSession()
    -- GOSSIP_SHOW occasionally fires again while a menu refreshes.  Only a
    -- genuine closed -> shown transition starts a new conversation, so a
    -- looping NPC cannot erase the protection by re-emitting GOSSIP_SHOW.
    if singleOptionDialogueGuard.active then return end
    ResetSingleOptionDialogueSession()
    singleOptionDialogueGuard.active = true
end

local function StopSingleOptionDialogueForSession(reason)
    if singleOptionDialogueGuard.stopped then return end
    singleOptionDialogueGuard.stopped = true
    if not singleOptionDialogueGuard.noticeShown then
        singleOptionDialogueGuard.noticeShown = true
        Print("Stopped Skip Single-Option Dialogue for this conversation (" .. reason .. ").")
    end
end

local function GetSingleOptionDialogueKey(options)
    local signature = GossipSignature(options)
    if not signature then return nil end
    return (GetNPCChoiceKey() or "npc:unknown") .. ":" .. signature
end

-- Claim before calling SelectOption, rather than after it.  Some UI updates
-- can be delivered synchronously by the client, and the pre-claim makes a
-- nested refresh see the exact menu as already handled.
local function ClaimSingleOptionDialogue(options)
    if not singleOptionDialogueGuard.active or singleOptionDialogueGuard.stopped then return nil end
    local key = GetSingleOptionDialogueKey(options)
    if not key then return nil end
    if singleOptionDialogueGuard.seen[key] then
        StopSingleOptionDialogueForSession("the same NPC menu repeated")
        return nil
    end
    if singleOptionDialogueGuard.attempts >= SINGLE_OPTION_DIALOGUE_MAX_STEPS then
        StopSingleOptionDialogueForSession("the safety limit was reached")
        return nil
    end

    local now = GetTime and GetTime() or nil
    local last = singleOptionDialogueGuard.recent[key]
    if type(now) == "number" and type(last) == "number"
        and now - last < SINGLE_OPTION_DIALOGUE_REPEAT_COOLDOWN then
        StopSingleOptionDialogueForSession("the same NPC menu reopened too quickly")
        return nil
    end

    singleOptionDialogueGuard.seen[key] = true
    singleOptionDialogueGuard.attempts = singleOptionDialogueGuard.attempts + 1
    if type(now) == "number" then singleOptionDialogueGuard.recent[key] = now end
    return key
end

local function ReleaseSingleOptionDialogueClaim(key)
    if not key then return end
    if singleOptionDialogueGuard.seen[key] then
        singleOptionDialogueGuard.seen[key] = nil
        singleOptionDialogueGuard.attempts = math.max(0, singleOptionDialogueGuard.attempts - 1)
    end
    singleOptionDialogueGuard.recent[key] = nil
end

local function IsQuestSkippedByFilter(settings, questID, isTrivial)
    if type(questID) ~= "number" or questID <= 0 then return false end

    if settings.skipLowLevelQuests then
        local trivial = isTrivial
        if trivial == nil and C_QuestLog and C_QuestLog.IsQuestTrivial then
            trivial = C_QuestLog.IsQuestTrivial(questID)
        end
        if trivial then return true end
    end

    if settings.skipWarbandCompleted and C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
        if C_QuestLog.QuestIgnoresAccountCompletedFiltering
            and C_QuestLog.QuestIgnoresAccountCompletedFiltering(questID) then
            return false
        end
        if C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) then return true end
    end

    return false
end

local function FindEligibleAvailableQuest(settings)
    if not (C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function") then return nil end
    local eligible
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if quest and type(quest.questID) == "number"
            and not IsQuestSkippedByFilter(settings, quest.questID, quest.isTrivial) then
            if eligible then return nil end
            eligible = quest
        end
    end
    return eligible
end

local function FindCompletableActiveQuest()
    if not (C_GossipInfo and type(C_GossipInfo.GetActiveQuests) == "function") then return nil end
    local completeQuest
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        local isComplete = quest and quest.isComplete
        if not isComplete and quest and C_QuestLog and C_QuestLog.ReadyForTurnIn then
            isComplete = C_QuestLog.ReadyForTurnIn(quest.questID)
        end
        if isComplete then
            if completeQuest then return nil end
            completeQuest = quest
        end
    end
    return completeQuest
end

local function SelectGossipAvailableQuest(quest)
    if C_GossipInfo and type(C_GossipInfo.SelectAvailableQuest) == "function" and quest then
        return pcall(C_GossipInfo.SelectAvailableQuest, quest.questID)
    end
    return false
end

local function SelectGossipActiveQuest(quest)
    if C_GossipInfo and type(C_GossipInfo.SelectActiveQuest) == "function" and quest then
        return pcall(C_GossipInfo.SelectActiveQuest, quest.questID)
    end
    return false
end

local function TryRememberedChoice(settings, options)
    if not settings.rememberChoices then return false end
    local npcKey = GetNPCChoiceKey()
    local signature = GossipSignature(options)
    local choice = npcKey and signature and settings.rememberedChoices[npcKey]
    local optionID = choice and choice[signature]
    if type(optionID) ~= "number" then return false end

    for _, option in ipairs(options) do
        if option.gossipOptionID == optionID and IsOptionSelectable(option) then
            return SelectGossipOption(optionID)
        end
    end
    return false
end

local function HandleGossip(clearPendingCampaign)
    local settings = GetAutomationSettings()
    if not CanAutomate(settings) then return end

    -- Merchant NPCs can expose a generic gossip option alongside the sell UI.
    -- Never make any automatic selection for the duration of that interaction;
    -- otherwise refreshed gossip can repeatedly re-open the same dialogue.
    if IsMerchantInteractionActive() then return end

    -- A fresh gossip interaction means an older selection did not ask for
    -- confirmation.  Do not clear this for an options-refresh event: that can
    -- occur while the campaign confirmation dialog is being presented.
    if clearPendingCampaign then pendingCampaignConfirmation = nil end

    local options = GetGossipOptions()
    if not options then return end

    -- A taught choice always wins. It can define a deliberate route through a
    -- multi-page NPC menu that the generic single-option skipper must leave alone.
    if TryRememberedChoice(settings, options) then return end

    if settings.selectCampaignSkips then
        local skipOption
        for _, option in ipairs(options) do
            if IsOptionSelectable(option) and IsCampaignSkipOption(option) then
                if skipOption then return end
                skipOption = option
            end
        end
        if skipOption then
            pendingCampaignConfirmation = skipOption.gossipOptionID
            if SelectGossipOption(skipOption.gossipOptionID) then return end
            pendingCampaignConfirmation = nil
        end
    end

    local completeQuest = FindCompletableActiveQuest()
    if settings.autoCompleteQuests then
        if completeQuest and SelectGossipActiveQuest(completeQuest) then return end
    end

    if settings.autoAcceptQuests then
        local availableQuest = FindEligibleAvailableQuest(settings)
        if availableQuest and SelectGossipAvailableQuest(availableQuest) then return end
    end

    if not settings.skipDialogue then return end
    if C_GossipInfo and C_GossipInfo.ForceGossip and C_GossipInfo.ForceGossip() then return end
    local hasActiveQuest, hasAvailableQuest = GetGossipQuestInteractions()
    local activeQuests = C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
    local knownQuestAdvance = FindKnownQuestAdvanceChoice(activeQuests, options)
    if knownQuestAdvance then
        local guardKey = ClaimSingleOptionDialogue(options)
        if not guardKey then return end
        if not SelectGossipOption(knownQuestAdvance.gossipOptionID) then ReleaseSingleOptionDialogueClaim(guardKey) end
        return
    end
    local uniqueQuestAdvance = FindUniqueQuestAdvanceChoice(options)
    if uniqueQuestAdvance then
        local guardKey = ClaimSingleOptionDialogue(options)
        if not guardKey then return end
        if not SelectGossipOption(uniqueQuestAdvance.gossipOptionID) then ReleaseSingleOptionDialogueClaim(guardKey) end
        return
    end
    if hasAvailableQuest then return end
    if #options ~= 1 or not IsOptionSelectable(options[1]) or HasOptionReward(options[1]) then return end
    if IsServiceGossipOption(options[1]) then return end
    -- Never auto-steal the accept path for an offered quest. An active quest,
    -- however, may present one explicitly quest-marked conversation choice
    -- such as "Encourage Kifaan..."; that is an advance/turn-in step and is
    -- exactly what Skip Single-Option Dialogue should continue.
    if hasActiveQuest and not IsQuestAdvanceGossipOption(options[1]) then return end
    local guardKey = ClaimSingleOptionDialogue(options)
    if not guardKey then return end
    if not SelectGossipOption(options[1].gossipOptionID) then
        -- A failed API call was not a selection. Let a later valid refresh try
        -- once rather than turning a transient client failure into a lockout.
        ReleaseSingleOptionDialogueClaim(guardKey)
    end
end

local function GetCurrentQuestID()
    local questID = GetQuestID and GetQuestID()
    if type(questID) == "number" and questID > 0 then return questID end
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        questID = C_QuestLog.GetSelectedQuest()
        if type(questID) == "number" and questID > 0 then return questID end
    end
    return nil
end

local function HandleQuestDetail()
    local settings = GetAutomationSettings()
    if not (CanAutomate(settings) and settings.autoAcceptQuests) then return end

    local questID = GetCurrentQuestID()
    if not IsQuestSkippedByFilter(settings, questID) and AcceptQuest then
        AcceptQuest()
    end
end

local function HandleQuestProgress()
    local settings = GetAutomationSettings()
    if not (CanAutomate(settings) and settings.autoCompleteQuests) then return end
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function HandleQuestComplete()
    local settings = GetAutomationSettings()
    if not (CanAutomate(settings) and settings.autoCompleteQuests and GetQuestReward) then return end

    -- Never guess a player reward choice. A single choice is safe to turn in;
    -- a zero-choice reward uses the standard first reward index.
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices == 0 or choices == 1 then
        GetQuestReward(1)
    end
end

local function SellJunk()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
        and C_Container.UseContainerItem) then
        return
    end

    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, type(slots) == "number" and slots or 0 do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.quality == 0 and not item.isLocked and not item.hasNoValue then
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end
end

local function RepairAll(useGuildBank)
    if not (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost and RepairAllItems) then return end
    local cost, canRepair = GetRepairAllCost()
    if canRepair and type(cost) == "number" and cost > 0 then
        RepairAllItems(useGuildBank and true or false)
    end
end

local function HandleMerchantShow(session)
    local settings = GetAutomationSettings()
    if not CanAutomate(settings) or session ~= merchantSession then return end

    if settings.autoSellJunk then SellJunk() end
    if not settings.autoRepair then return end

    -- Let vendor sales update funds before repairing. Guild-first repair gets a
    -- second personal pass only when the option explicitly permits a fallback.
    QueueAction("merchantRepair:" .. session, function()
        local current = GetAutomationSettings()
        if not (CanAutomate(current) and current.autoRepair and session == merchantSession) then return end
        if current.repairSource == "personal" then
            RepairAll(false)
        elseif current.repairSource == "guild" then
            RepairAll(true)
        else
            RepairAll(true)
            QueueAction("merchantPersonalFallback:" .. session, function()
                local fallback = GetAutomationSettings()
                if CanAutomate(fallback) and fallback.autoRepair and session == merchantSession
                    and fallback.repairSource == "guildThenPersonal" then
                    RepairAll(false)
                end
            end, 0.15)
        end
    end, 0.05)
end

local function SkipCinematic()
    local settings = GetAutomationSettings()
    if not (CanAutomate(settings) and settings.skipCinematics) then return end

    if C_Cinematic and type(C_Cinematic.StopCinematic) == "function" then
        C_Cinematic.StopCinematic()
    elseif Cinematic and type(Cinematic.StopCinematic) == "function" then
        Cinematic.StopCinematic()
    elseif type(StopCinematic) == "function" then
        StopCinematic()
    end
    if MovieFrame and MovieFrame.IsShown and MovieFrame:IsShown() then
        if MovieFrame.StopMovie then MovieFrame:StopMovie() end
        MovieFrame:Hide()
    end
end

local function StartTeachingCurrentNPC()
    local settings = GetAutomationSettings()
    if not settings or not settings.rememberChoices then
        Print("Enable Remember NPC Choices before teaching an NPC route.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        Print("NPC choice teaching is unavailable in combat.")
        return
    end

    local npcKey = GetNPCChoiceKey()
    if not npcKey then
        Print("Face the NPC first, then choose Teach Current NPC.")
        return
    end
    teachingNPCKey = npcKey
    teachingStartedAt = GetTime and GetTime() or 0
    Print("Teaching choices for this NPC. Navigate its dialogue normally; the route will be saved until the conversation closes.")
end

local function ForgetCurrentNPCChoices()
    local settings = GetAutomationSettings()
    local npcKey = GetNPCChoiceKey()
    if not (settings and npcKey) then
        Print("Face the NPC whose remembered choices you want to remove.")
        return
    end
    settings.rememberedChoices[npcKey] = nil
    Print("Forgot saved dialogue choices for this NPC.")
end

local function RememberManualGossipChoice(optionID)
    if selectingAutomationOption or type(optionID) ~= "number" then return end
    if not teachingNPCKey or teachingNPCKey ~= GetNPCChoiceKey() then return end

    if teachingStartedAt and GetTime and GetTime() - teachingStartedAt > 60 then
        teachingNPCKey, teachingStartedAt = nil, nil
        Print("NPC choice teaching timed out.")
        return
    end

    local settings = GetAutomationSettings()
    local signature = GossipSignature(GetGossipOptions())
    if not (settings and signature) then return end
    local options = GetGossipOptions()
    local found
    for _, option in ipairs(options or {}) do
        if option.gossipOptionID == optionID then found = option break end
    end
    if not IsOptionSelectable(found) then return end

    local saved = settings.rememberedChoices[teachingNPCKey]
    if type(saved) ~= "table" then
        saved = {}
        settings.rememberedChoices[teachingNPCKey] = saved
    end
    saved[signature] = optionID
end

local function InstallHooks()
    if hooksInstalled or not hooksecurefunc or not (C_GossipInfo and C_GossipInfo.SelectOption) then return end
    hooksecurefunc(C_GossipInfo, "SelectOption", RememberManualGossipChoice)
    hooksInstalled = true
end

local function GetButton(row, side)
    local region = row and row[side == "right" and "_rightRegion" or "_leftRegion"]
    return region and region._control
end

addon.BuildAutomationPage = function(parent, yOffset)
    if not (EllesmereUI and EllesmereUI.Widgets) then return yOffset end
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "AUTOMATION CONTROLS", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "dropdown",
            text = "Pause Key",
            values = PAUSE_KEYS,
            order = { "shift", "ctrl", "alt", "disabled" },
            tooltip = "Hold this key while interacting to pause all Waffle House automation. Shift is the default. Disabled removes the hold-to-pause key; Reverse Mode requires an active key.",
            getValue = function() return GetAutomationSettings().pauseKey end,
            setValue = function(value)
                local settings = GetAutomationSettings()
                settings.pauseKey = PAUSE_KEYS[value] and value or "shift"
                if settings.pauseKey == "disabled" then settings.reverseMode = false end
            end,
        },
        {
            type = "toggle",
            text = "Reverse Mode",
            tooltip = "Keep automation paused until the Pause Key is held.",
            disabled = function() return GetAutomationSettings().pauseKey == "disabled" end,
            disabledTooltip = "Choose Shift, Ctrl, or Alt as the Pause Key before enabling Reverse Mode.",
            getValue = function() return GetAutomationSettings().reverseMode == true end,
            setValue = function(value) GetAutomationSettings().reverseMode = value and true or false end,
        }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "dropdown",
            text = "Where to Automate",
            values = AUTOMATION_SCOPES,
            order = { "anywhere", "openWorld", "instances" },
            tooltip = "Limit automated interactions to the open world or to non-PvP instances, or allow them anywhere.",
            getValue = function() return GetAutomationSettings().scope end,
            setValue = function(value) GetAutomationSettings().scope = AUTOMATION_SCOPES[value] and value or "anywhere" end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "ETHEREAL TOOLS", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Auto Choose Ethereal Tools",
            tooltip = "At an Ethereal Tool Rack, choose the best available known stat card. This only acts when every card is one of the four Ethereal Tools; any other Player Choice remains manual. It follows the Pause Key and Where to Automate controls above.",
            getValue = function() return GetAutomationSettings().autoChooseEtherealTools == true end,
            setValue = function(value) GetAutomationSettings().autoChooseEtherealTools = value and true or false end,
        },
        {
            type = "dropdown",
            text = "Ethereal Tool Preference",
            values = ETHEREAL_TOOL_PREFERENCES,
            order = { "specialization", "primary", "haste", "mastery", "crit" },
            tooltip = "Best for Specialization ranks primary stat first, then uses a fallback order for your active specialization when the primary-stat tool is unavailable.",
            disabled = function() return not GetAutomationSettings().autoChooseEtherealTools end,
            disabledTooltip = "Enable Auto Choose Ethereal Tools to set its preference.",
            getValue = function() return GetAutomationSettings().etherealToolPreference end,
            setValue = function(value)
                GetAutomationSettings().etherealToolPreference = ETHEREAL_TOOL_PREFERENCES[value] and value or "specialization"
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "QUESTS & NPC DIALOGUE", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Auto Accept Quests",
            tooltip = "Accept a quest offered directly by an NPC or through a single eligible gossip quest. Quest filters below are honored.",
            getValue = function() return GetAutomationSettings().autoAcceptQuests == true end,
            setValue = function(value) GetAutomationSettings().autoAcceptQuests = value and true or false end,
        },
        {
            type = "toggle",
            text = "Auto Complete Quests",
            tooltip = "Turn in ready NPC quests. Waffle House never guesses between multiple reward choices.",
            getValue = function() return GetAutomationSettings().autoCompleteQuests == true end,
            setValue = function(value) GetAutomationSettings().autoCompleteQuests = value and true or false end,
        }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Skip Single-Option Dialogue",
            tooltip = "Advance one available no-reward dialogue option when the NPC did not force the menu open. A unique quest-marked option may continue even when ordinary dialogue remains. Competing quest branches, vendors, trainers, banks, travel, rewards, and other services stay open. The same NPC menu can be selected only once per conversation, with a safety stop for looping dialogue.",
            getValue = function() return GetAutomationSettings().skipDialogue == true end,
            setValue = function(value) GetAutomationSettings().skipDialogue = value and true or false end,
        },
        {
            type = "toggle",
            text = "Select Campaign Skips",
            tooltip = "Select one available gossip option explicitly labelled Campaign Skip. Its confirmation is accepted only when Waffle House selected that option.",
            getValue = function() return GetAutomationSettings().selectCampaignSkips == true end,
            setValue = function(value) GetAutomationSettings().selectCampaignSkips = value and true or false end,
        }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Don't Accept Low-Level Quests",
            tooltip = "Leave trivial quests unaccepted when Auto Accept Quests is enabled.",
            getValue = function() return GetAutomationSettings().skipLowLevelQuests == true end,
            setValue = function(value) GetAutomationSettings().skipLowLevelQuests = value and true or false end,
        },
        {
            type = "toggle",
            text = "Skip Warband-Completed Quests",
            tooltip = "Leave account-completed quests unaccepted when Auto Accept Quests is enabled. Quests that explicitly ignore account completion are left alone.",
            getValue = function() return GetAutomationSettings().skipWarbandCompleted == true end,
            setValue = function(value) GetAutomationSettings().skipWarbandCompleted = value and true or false end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "REMEMBERED NPC CHOICES", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Remember NPC Choices",
            tooltip = "Replay dialogue routes that you explicitly teach. Teaching never records Waffle House's own automatic selections.",
            getValue = function() return GetAutomationSettings().rememberChoices == true end,
            setValue = function(value) GetAutomationSettings().rememberChoices = value and true or false end,
        }
    ); y = y - h
    local teachRow
    teachRow, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Current NPC Route",
            buttonText = "Teach",
            tooltip = "Face an NPC, then teach a route. Navigate that conversation normally; each choice is saved until the conversation ends.",
            disabled = function() return InCombatLockdown and InCombatLockdown() end,
            disabledTooltip = "NPC choice teaching is unavailable in combat.",
        },
        {
            type = "labeledButton",
            text = "Current NPC Route",
            buttonText = "Forget",
            tooltip = "Remove every remembered dialogue choice for the NPC you are facing.",
        }
    ); y = y - h
    local teachButton = GetButton(teachRow, "left")
    if teachButton then teachButton:SetScript("OnClick", StartTeachingCurrentNPC) end
    local forgetButton = GetButton(teachRow, "right")
    if forgetButton then forgetButton:SetScript("OnClick", ForgetCurrentNPCChoices) end

    _, h = W:SectionHeader(parent, "CINEMATICS & MERCHANTS", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Skip Cinematics",
            tooltip = "Stop skippable in-game cinematics and movies as they start. Forced cinematics remain under the game's control.",
            getValue = function() return GetAutomationSettings().skipCinematics == true end,
            setValue = function(value) GetAutomationSettings().skipCinematics = value and true or false end,
        },
        {
            type = "toggle",
            text = "Auto Sell Junk",
            tooltip = "Sell gray, vendor-value items when a merchant opens. This happens before any automatic repair.",
            getValue = function() return GetAutomationSettings().autoSellJunk == true end,
            setValue = function(value) GetAutomationSettings().autoSellJunk = value and true or false end,
        }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Auto Repair",
            tooltip = "Repair at a merchant after junk is sold. Choose the repair funding source beside this option.",
            getValue = function() return GetAutomationSettings().autoRepair == true end,
            setValue = function(value) GetAutomationSettings().autoRepair = value and true or false end,
        },
        {
            type = "dropdown",
            text = "Repair Source",
            values = REPAIR_SOURCES,
            order = { "guildThenPersonal", "personal", "guild" },
            tooltip = "Use guild repairs first with an optional personal-funds fallback, or limit repairs to one funding source.",
            disabled = function() return not GetAutomationSettings().autoRepair end,
            disabledTooltip = "Enable Auto Repair to choose a repair funding source.",
            getValue = function() return GetAutomationSettings().repairSource end,
            setValue = function(value) GetAutomationSettings().repairSource = REPAIR_SOURCES[value] and value or "guildThenPersonal" end,
        }
    ); y = y - h

    return math.abs(y)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("GOSSIP_OPTIONS_REFRESHED")
events:RegisterEvent("GOSSIP_CONFIRM")
events:RegisterEvent("GOSSIP_CLOSED")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("CINEMATIC_START")
events:RegisterEvent("PLAY_MOVIE")
events:RegisterEvent("PLAYER_CHOICE_UPDATE")
events:RegisterEvent("PLAYER_CHOICE_CLOSE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        GetAutomationSettings()
        InstallHooks()
    elseif event == "GOSSIP_SHOW" then
        BeginSingleOptionDialogueSession()
        QueueAction("gossip", function() HandleGossip(true) end)
    elseif event == "GOSSIP_OPTIONS_REFRESHED" then
        QueueAction("gossipRefresh", function() HandleGossip(false) end)
    elseif event == "GOSSIP_CONFIRM" then
        local optionID = ...
        local settings = GetAutomationSettings()
        if CanAutomate(settings) and settings.selectCampaignSkips
            and optionID == pendingCampaignConfirmation then
            pendingCampaignConfirmation = nil
            QueueAction("gossipConfirm:" .. optionID, function()
                local current = GetAutomationSettings()
                if CanAutomate(current) and current.selectCampaignSkips then
                    SelectGossipOption(optionID, true)
                end
            end)
        end
    elseif event == "GOSSIP_CLOSED" then
        teachingNPCKey, teachingStartedAt, pendingCampaignConfirmation = nil, nil, nil
        ResetSingleOptionDialogueSession()
    elseif event == "QUEST_DETAIL" then
        QueueAction("questDetail", HandleQuestDetail)
    elseif event == "QUEST_PROGRESS" then
        QueueAction("questProgress", HandleQuestProgress)
    elseif event == "QUEST_COMPLETE" then
        QueueAction("questComplete", HandleQuestComplete)
    elseif event == "MERCHANT_SHOW" then
        merchantInteractionActive = true
        merchantSession = merchantSession + 1
        local session = merchantSession
        QueueAction("merchant:" .. session, function() HandleMerchantShow(session) end)
    elseif event == "MERCHANT_CLOSED" then
        merchantInteractionActive = false
        merchantSession = merchantSession + 1
    elseif event == "CINEMATIC_START" or event == "PLAY_MOVIE" then
        QueueAction("cinematic", SkipCinematic)
    elseif event == "PLAYER_CHOICE_UPDATE" then
        QueueAction("etherealToolChoice", TryChooseEtherealTool)
    elseif event == "PLAYER_CHOICE_CLOSE" then
        etherealToolSelection.choiceID = nil
        etherealToolSelection.responseID = nil
    end
end)
