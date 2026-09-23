local addonName, addon = ...
if not addon then return end

-- A deliberately light integration layer for EllesmereUI Bags.  This owns
-- only its button and menu: it neither rewrites its frames nor reaches into
-- the bank addon's private selected-tab state.
local ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62
local REAGENT_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local TRADEGOODS_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local BAG_ICON_TEXTURE = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\bag_assistant_emblem.tga"
local ACTION_TILE_TEXTURE = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\bag_assistant_actions.tga"
local PLAY_ICON_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\play.png"
local ACTION_TILE_COORDS = {
    deposit = { 0.01, 0.49, 0.01, 0.49 },
    warband = { 0.01, 0.49, 0.01, 0.49 },
    categorize = { 0.51, 0.99, 0.01, 0.49 },
    withdraw = { 0.51, 0.99, 0.01, 0.49 },
    guild_move = { 0.51, 0.99, 0.01, 0.49 },
    sort_bags = { 0.01, 0.49, 0.51, 0.99 },
    sort_character = { 0.01, 0.49, 0.51, 0.99 },
    sort_warband = { 0.01, 0.49, 0.51, 0.99 },
    organize = { 0.51, 0.99, 0.51, 0.99 },
    guild_organize = { 0.51, 0.99, 0.51, 0.99 },
}
local GUILD_CATEGORY_ICONS = {
    Materials = "Interface\\Icons\\INV_Misc_Herb_01",
    Gear = "Interface\\Icons\\INV_Chest_Chain_05",
    Consumables = "Interface\\Icons\\INV_Potion_54",
}
local OUTDATED_GEAR_GAP = 50
local BANK_VIEWS = {
    { index = -1, label = "OneBank" },
    { index = 0, label = "All Bank Tabs" },
    { index = -3, label = "OneWarbank" },
    { index = -2, label = "All Warbank Tabs" },
}

local assistantButton
local assistantMenu
local refreshPending
local autoOrganizedThisBankVisit
local autoOrganizedAt
local attemptedDepositMaterialCount
local attemptedWarbandDepositThisBankVisit
local sortedBagsThisBankVisit
local sortedCharacterBankThisBankVisit
local sortedWarbandBankThisBankVisit
local pendingCategoryMove
local pendingGuildMove
local pendingOutdatedMove
local pendingActionUntil
local assistantRunState = "idle"
local assistantRunMode = "all"
local assistantRunSerial = 0
local assistantAdvanceQueued
local assistantActionCount = 0
local assistantWaitCount = 0
local MAX_ASSISTANT_ACTIONS = 150
local MAX_ASSISTANT_WAITS = 40
local lastActionMessage
local lastActionTask
local UpdateMenu
local GetNextTask
local AdvanceAssistant
local QueueAdvance

local function GetSettings()
    return addon.GetSettings and addon.GetSettings() or {}
end

local function IsEnabled()
    return GetSettings().bagAssistantEnabled ~= false
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function GetBags()
    return _G.EUI_Bags
end

local function GetBank()
    -- EllesmereUI keeps its Lua variable local, but creates the frame with
    -- this global name. _G.EUI_Bank is never populated by its bank module.
    return _G.EUI_BankFrame
end

local function IsBankOpen()
    local bank = GetBank()
    return bank and bank.IsVisible and bank:IsVisible() or false
end

local function IsGuildBankOpen()
    local frame = _G.GuildBankFrame
    return GetSettings().bagAssistantIncludeGuildBank == true
        and frame and frame.IsVisible and frame:IsVisible() or false
end

local function IsPortableWarbandBank()
    return C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType
        and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.AccountBanker
        and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.AccountBanker)
        or false
end

local function IsMaterialItem(itemID)
    if not (itemID and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID == REAGENT_CLASS or classID == TRADEGOODS_CLASS
end

local function CountMaterialStacks(bagID, slots)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return 0, 0
    end
    local totalSlots = slots or C_Container.GetContainerNumSlots(bagID) or 0
    local materialStacks, freeSlots = 0, 0
    for slot = 1, totalSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            if IsMaterialItem(info.itemID) then materialStacks = materialStacks + 1 end
        else
            freeSlots = freeSlots + 1
        end
    end
    return materialStacks, freeSlots
end

local function CountCarriedMaterialStacks()
    local total = 0
    for bagID = 0, 4 do
        local materials = CountMaterialStacks(bagID)
        total = total + materials
    end
    return total
end

-- The bank addon publishes physical tab metadata. The aggregate OneBank and
-- All Warbank entries are views, not separate storage destinations.
local function FindBestMaterialTab(warbandOnly)
    local bank = GetBank()
    local tabs = bank and bank._allTabs
    if type(tabs) ~= "table" or #tabs == 0 then return nil, 0 end

    local bestAvailable, availableScore
    local bestFull, fullScore
    local tabCount = 0
    local portable = IsPortableWarbandBank()
    for index, tab in ipairs(tabs) do
        if type(tab) == "table" and type(tab.bagID) == "number"
            and (warbandOnly == nil or (tab.isWarband == true) == warbandOnly)
            and (not portable or tab.isWarband == true) then
            tabCount = tabCount + 1
            local materials, freeSlots = CountMaterialStacks(tab.bagID, tab.numSlots)
            -- Existing material stacks are a strong categorization signal;
            -- available room resolves ties without moving anything for the user.
            local candidate = {
                index = index,
                bagID = tab.bagID,
                name = tab.name or (tab.isWarband and "Warband Bank" or "Bank"),
                isWarband = tab.isWarband == true,
                icon = tab.icon,
                materialStacks = materials,
                freeSlots = freeSlots,
            }
            local score = materials * 1000 + freeSlots
            if freeSlots > 0 and (not bestAvailable or score > availableScore) then
                bestAvailable, availableScore = candidate, score
            elseif freeSlots == 0 and (not bestFull or score > fullScore) then
                bestFull, fullScore = candidate, score
            end
        end
    end
    -- A full material tab is a useful signal, but it is not a destination.
    -- Prefer any tab with room; only report "bank full" when every discovered
    -- tab is full.
    return bestAvailable or bestFull, tabCount
end

-- These buttons are the bank addon's own view controls.  Clicking one runs its
-- ordinary selection/refresh path; we never write its private _selectedView.
local function GetBankViewButtons()
    local found = {}
    local bank = GetBank()
    if not (bank and bank.GetChildren) then return found end
    local function Search(parent, depth)
        if depth > 5 or not parent.GetChildren then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if type(child._viewIdx) == "number" and child.Click and child.IsVisible and child:IsVisible() then
                found[child._viewIdx] = child
            end
            Search(child, depth + 1)
        end
    end
    Search(bank, 0)
    return found
end

local function SelectBankView(viewIndex, mouseButton)
    if IsInCombat() or not IsBankOpen() then return false end
    local control = GetBankViewButtons()[viewIndex]
    if not control then return false end
    control:Click(mouseButton or "LeftButton")
    return true
end
addon.SelectBagAssistantBankView = SelectBankView

local function SafeNumber(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "number"
end

local function GetItemClass(itemID, link)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link or itemID)
    return SafeNumber(classID) and classID or nil
end

local function GetTabCategory(classID)
    if classID == REAGENT_CLASS or classID == TRADEGOODS_CLASS then return "Materials" end
    if classID == ((Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2)
        or classID == ((Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4) then return "Gear" end
    if classID == ((Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0) then return "Consumables" end
    return nil
end

local function IsGenericTabName(name)
    return name:match("^[Tt]ab %d+$") ~= nil or name:match("^[Bb]ank [Tt]ab %d+$") ~= nil
end

local function GetManagedTabCategory(name)
    if type(name) ~= "string" then return nil end
    for _, category in ipairs({ "Materials", "Gear", "Consumables" }) do
        if name:match("^" .. category .. " %d+$") then return category end
    end
end

local function IsAllowedInBankType(item, bankType)
    if not (C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation
        and ItemLocation.CreateFromBagAndSlot) then return false end
    local location = ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot)
    local allowed = C_Bank.IsItemAllowedInBankType(bankType, location)
    return (not issecretvalue or not issecretvalue(allowed)) and allowed == true
end

local function SuggestedDepositFlags(category)
    local flags = Enum and Enum.BagSlotFlags
    if not flags or not bit or not bit.bor then return nil end
    if category == "Materials" and flags.ClassProfessionGoods and flags.ClassReagents then
        return bit.bor(flags.ClassProfessionGoods, flags.ClassReagents)
    end
    if category == "Gear" then return flags.ClassEquipment end
    if category == "Consumables" then return flags.ClassConsumables end
end

local function GetVerifiedTabData(tab, characterData, accountData)
    -- _allTabs may contain generic fallback names when the bank's metadata
    -- request has not completed. Never auto-rename from those placeholders.
    local bagIndices = Enum and Enum.BagIndex
    local liveData = tab.isWarband and accountData or characterData
    if not (bagIndices and type(liveData) == "table") then return nil end
    local prefix = tab.isWarband and "AccountBankTab_" or "CharacterBankTab_"
    local maxTabs = tab.isWarband and 5 or 6
    for ordinal = 1, maxTabs do
        if bagIndices[prefix .. ordinal] == tab.bagID then
            local data = liveData[ordinal]
            return type(data) == "table" and data or nil, ordinal
        end
    end
end

local function GetEquippedItemLevel()
    if not GetAverageItemLevel then return nil end
    local overall, equipped = GetAverageItemLevel()
    local level = SafeNumber(equipped) and equipped or overall
    return SafeNumber(level) and level > OUTDATED_GEAR_GAP and level or nil
end

local function ScanBankPlan()
    local plan = { cleanups = {}, outdated = {}, tabCount = 0, categoryTabs = {}, items = {} }
    if IsInCombat() or not IsBankOpen() then return plan end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return plan
    end
    local bank = GetBank()
    local tabs = bank and bank._allTabs
    if type(tabs) ~= "table" then return plan end
    local equippedLevel = GetEquippedItemLevel()
    plan.threshold = equippedLevel and math.floor(equippedLevel - OUTDATED_GEAR_GAP) or nil
    local characterData, accountData
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType then
        characterData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
        accountData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
    end

    for index, tab in ipairs(tabs) do
        if type(tab) == "table" and SafeNumber(tab.bagID) then
            plan.tabCount = plan.tabCount + 1
            local counts, icons, iconVotes, iconScores, used = {}, {}, {}, {}, 0
            local slots = C_Container and C_Container.GetContainerNumSlots
                and C_Container.GetContainerNumSlots(tab.bagID) or 0
            if SafeNumber(slots) then
                for slot = 1, slots do
                    local info = C_Container.GetContainerItemInfo(tab.bagID, slot)
                    if info and SafeNumber(info.itemID) then
                        used = used + 1
                        local link = info.hyperlink or (C_Container.GetContainerItemLink
                            and C_Container.GetContainerItemLink(tab.bagID, slot))
                        local category = GetTabCategory(GetItemClass(info.itemID, link))
                        if category then
                            plan.items[#plan.items + 1] = {
                                bagID = tab.bagID, slot = slot, itemID = info.itemID,
                                link = link, category = category, isWarband = tab.isWarband == true,
                                locked = info.isLocked == true,
                            }
                        end
                        if category then
                            counts[category] = (counts[category] or 0) + 1
                            if SafeNumber(info.iconFileID) then
                                iconVotes[category] = iconVotes[category] or {}
                                local votes = iconVotes[category]
                                votes[info.iconFileID] = (votes[info.iconFileID] or 0) + 1
                                if votes[info.iconFileID] > (iconScores[category] or 0) then
                                    icons[category], iconScores[category] = info.iconFileID, votes[info.iconFileID]
                                end
                            end
                        end
                        if category == "Gear" and plan.threshold and C_Item and C_Item.GetDetailedItemLevelInfo then
                            local itemLevel = C_Item.GetDetailedItemLevelInfo(link or info.itemID)
                            if SafeNumber(itemLevel) and itemLevel > 0 and itemLevel <= plan.threshold then
                                local name, quality = nil, info.quality
                                if C_Item.GetItemInfo then
                                    local itemName, _, itemQuality = C_Item.GetItemInfo(link or info.itemID)
                                    name, quality = itemName, itemQuality or quality
                                end
                                if quality ~= 7 then -- heirlooms deliberately stay out of outdated-gear review
                                    plan.outdated[#plan.outdated + 1] = {
                                        bagID = tab.bagID, slot = slot, itemID = info.itemID,
                                        link = link, name = name or ("Item " .. info.itemID),
                                        level = itemLevel, tabName = tab.name or "Bank Tab", icon = info.iconFileID,
                                    }
                                end
                            end
                        end
                    end
                end
            end
            local category, dominant = nil, 0
            for _, kind in ipairs({ "Materials", "Gear", "Consumables" }) do
                if (counts[kind] or 0) > dominant then category, dominant = kind, counts[kind] end
            end
            local liveData, ordinal = GetVerifiedTabData(tab, characterData, accountData)
            local rawName = liveData and (liveData.name or (tab.isWarband and "Tab " or "Bank Tab ") .. ordinal)
            local namedCategory = GetManagedTabCategory(rawName)
            if namedCategory then
                plan.categoryTabs[#plan.categoryTabs + 1] = {
                    bagID = tab.bagID, name = rawName, category = namedCategory,
                    isWarband = tab.isWarband == true,
                    freeSlots = math.max(0, slots - used),
                }
            end
            local confident = category and used >= 4 and dominant / used >= 0.7
            local desiredCategory = confident and category or namedCategory
            if desiredCategory and rawName and liveData then
                local managed = IsGenericTabName(rawName) or namedCategory ~= nil
                local suggestedName = managed and confident and (desiredCategory .. " " .. index) or rawName
                local suggestedIcon = managed and confident
                    and (icons[desiredCategory] or liveData.icon) or liveData.icon
                local depositFlags = SuggestedDepositFlags(desiredCategory) or liveData.depositFlags or 0
                if SafeNumber(suggestedIcon) and (suggestedName ~= rawName
                    or suggestedIcon ~= liveData.icon or depositFlags ~= (liveData.depositFlags or 0)) then
                    plan.cleanups[#plan.cleanups + 1] = {
                        index = index, bagID = tab.bagID, isWarband = tab.isWarband == true,
                        name = suggestedName, icon = suggestedIcon, depositFlags = depositFlags,
                    }
                end
            end
        end
    end
    table.sort(plan.outdated, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.bagID ~= b.bagID then return a.bagID < b.bagID end
        return a.slot < b.slot
    end)
    table.sort(plan.categoryTabs, function(left, right)
        if left.isWarband ~= right.isWarband then return left.isWarband end
        return left.bagID < right.bagID
    end)
    -- Main Bags also take part in categorization, but frozen slots and carried
    -- gear are excluded: an active gear set must never be banked by inference.
    for bagID = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bagID)
        if SafeNumber(slots) then
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if info and SafeNumber(info.itemID) and not info.isLocked
                    and not (addon.IsFrozenBagSlot and addon.IsFrozenBagSlot(bagID, slot, info)) then
                    local link = info.hyperlink or (C_Container.GetContainerItemLink
                        and C_Container.GetContainerItemLink(bagID, slot))
                    local category = GetTabCategory(GetItemClass(info.itemID, link))
                    if category and category ~= "Gear" then
                        plan.items[#plan.items + 1] = {
                            bagID = bagID, slot = slot, itemID = info.itemID,
                            link = link, category = category, isCarried = true,
                        }
                    end
                end
            end
        end
    end
    local organizedSource = {}
    for _, tab in ipairs(plan.categoryTabs) do organizedSource[tab.bagID] = tab.category end
    for _, item in ipairs(plan.items) do
        if not item.locked then
            for _, target in ipairs(plan.categoryTabs) do
                if target.category == item.category and target.bagID ~= item.bagID
                    and target.freeSlots > 0 and (not item.isWarband or target.isWarband)
                    and (not IsPortableWarbandBank() or (target.isWarband
                        and (item.isCarried or item.isWarband)))
                    and (item.isCarried or organizedSource[item.bagID] ~= item.category
                        or (target.isWarband and not item.isWarband)) then
                    local allowed = true
                    if item.isCarried or (target.isWarband and not item.isWarband) then
                        local bankType = target.isWarband and Enum.BankType.Account or Enum.BankType.Character
                        allowed = IsAllowedInBankType(item, bankType)
                    end
                    if allowed then
                        plan.move = { source = item, target = target }
                        break
                    end
                end
            end
        end
        if plan.move then break end
    end
    return plan
end

addon.GetBagAssistantPlan = ScanBankPlan

-- Guild tabs belong to a shared store. Only the selected source tab and a
-- populated, viewable destination are considered; no unseen or empty tab is
-- guessed to be a safe destination from an unfilled client cache.
local function ScanGuildPlan()
    local plan = { tabs = {}, items = {} }
    if IsInCombat() or not IsGuildBankOpen() or not (GetNumGuildBankTabs
        and GetGuildBankTabInfo and GetGuildBankItemInfo and GetGuildBankItemLink
        and GetCurrentGuildBankTab) then return plan end
    local selectedTab = GetCurrentGuildBankTab()
    local tabCount = GetNumGuildBankTabs()
    if not SafeNumber(selectedTab) or not SafeNumber(tabCount) then return plan end
    local slotCount = MAX_GUILDBANK_SLOTS_PER_TAB or 98
    for tabIndex = 1, tabCount do
        local name, icon, viewable, canDeposit, numWithdrawals, remainingWithdrawals =
            GetGuildBankTabInfo(tabIndex)
        if viewable == true and type(name) == "string" then
            local tab = {
                index = tabIndex, name = name, icon = icon, canDeposit = canDeposit == true,
                canWithdraw = (SafeNumber(numWithdrawals) and numWithdrawals < 0)
                    or (SafeNumber(remainingWithdrawals) and remainingWithdrawals > 0),
                category = GetManagedTabCategory(name), items = {}, freeSlots = 0,
                counts = {}, icons = {}, used = 0,
            }
            for slot = 1, slotCount do
                local texture, _, locked = GetGuildBankItemInfo(tabIndex, slot)
                if texture then
                    local link = GetGuildBankItemLink(tabIndex, slot)
                    if type(link) == "string" then
                        tab.used = tab.used + 1
                        local category = GetTabCategory(GetItemClass(nil, link))
                        if category then
                            tab.counts[category] = (tab.counts[category] or 0) + 1
                            tab.icons[category] = tab.icons[category] or texture
                            if tabIndex == selectedTab and locked ~= true then
                                tab.items[#tab.items + 1] = {
                                    tab = tabIndex, slot = slot, link = link, category = category,
                                }
                            end
                        end
                    end
                else
                    tab.freeSlots = tab.freeSlots + 1
                end
            end
            plan.tabs[#plan.tabs + 1] = tab
            if tabIndex == selectedTab then plan.selected = tab end
        end
    end
    local selected = plan.selected
    if selected and IsGenericTabName(selected.name) and selected.used >= 4
        and CanEditGuildBankTabInfo and CanEditGuildBankTabInfo() then
        local category, dominant
        dominant = 0
        for _, kind in ipairs({ "Materials", "Gear", "Consumables" }) do
            if (selected.counts[kind] or 0) > dominant then
                category, dominant = kind, selected.counts[kind]
            end
        end
        if category and dominant / selected.used >= 0.7 then
            plan.cleanup = {
                tab = selected.index, name = category .. " " .. selected.index,
                icon = GUILD_CATEGORY_ICONS[category] or selected.icon,
            }
        end
    end
    if selected and selected.canWithdraw then
        for _, item in ipairs(selected.items) do
            if selected.category ~= item.category then
                for _, target in ipairs(plan.tabs) do
                    if target.index ~= selected.index and target.category == item.category
                        and target.canDeposit and target.used > 0 and target.freeSlots > 0 then
                        plan.move = { source = item, target = target }
                        break
                    end
                end
            end
            if plan.move then break end
        end
    end
    return plan
end
addon.GetBagAssistantGuildPlan = ScanGuildPlan

local function ApplyGuildTabCleanup()
    if IsInCombat() or not IsGuildBankOpen() or not SetGuildBankTabInfo
        or not CanEditGuildBankTabInfo or not CanEditGuildBankTabInfo() then
        return false, "Guild tab editing is unavailable."
    end
    local change = ScanGuildPlan().cleanup
    if not change or not change.icon then return false, "No safe Guild Bank tab cleanup is ready." end
    SetGuildBankTabInfo(change.tab, change.name, change.icon)
    return true, "Set Guild Bank tab " .. change.tab .. " to " .. change.name .. "."
end

local function MoveGuildCategoryItem()
    if IsInCombat() or not IsGuildBankOpen() or not PickupGuildBankItem
        or not CursorHasItem or CursorHasItem() then
        return false, "Open the Guild Bank out of combat with an empty cursor."
    end
    local proposal = ScanGuildPlan().move
    if not proposal then return false, "No permitted Guild Bank transfer is ready." end
    local source, target = proposal.source, proposal.target
    if GetCurrentGuildBankTab() ~= source.tab
        or GetGuildBankItemLink(source.tab, source.slot) ~= source.link then
        return false, "The selected guild item changed; scan again."
    end
    local destSlot
    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        local texture = GetGuildBankItemInfo(target.index, slot)
        if not texture then destSlot = slot; break end
    end
    if not destSlot then return false, "The destination Guild Bank tab filled." end
    PickupGuildBankItem(source.tab, source.slot)
    if not CursorHasItem() then return false, "Could not pick up the guild item." end
    PickupGuildBankItem(target.index, destSlot)
    if CursorHasItem() then
        if not GetGuildBankItemLink(source.tab, source.slot) then
            PickupGuildBankItem(source.tab, source.slot)
        end
        return false, "Could not place the guild item. Check your cursor."
    end
    pendingGuildMove = { source = source, target = target, slot = destSlot }
    return true, "Moved one " .. source.category .. " item to Guild Bank " .. target.name .. "."
end
addon.MoveBagAssistantGuildItem = MoveGuildCategoryItem

local function CountAccessibleCleanups(plan)
    local portable = IsPortableWarbandBank()
    local count = 0
    for _, change in ipairs(plan.cleanups) do
        if change.isWarband or not portable then count = count + 1 end
    end
    return count
end

local function GetAdvice()
    local carried = CountCarriedMaterialStacks()
    if IsGuildBankOpen() then
        local plan = ScanGuildPlan()
        return {
            state = "guild", carried = carried,
            tab = plan.move and plan.move.target,
            text = plan.cleanup and ("Guild Bank tab " .. plan.cleanup.tab
                .. " can be named and skinned for its contents.")
                or (plan.move and ("Next: move one " .. plan.move.source.category
                    .. " item to " .. plan.move.target.name .. ".")
                    or "Guild Bank scanned. No permitted category move is ready."),
        }
    end
    if not IsBankOpen() then
        local suffix = carried > 0 and (" " .. carried .. " material stack" .. (carried == 1 and " is" or "s are") .. " ready.") or ""
        return {
            state = "away",
            carried = carried,
            text = "Bank closed — visit a banker to scan tabs and deposit materials." .. suffix,
        }
    end

    local best, tabCount = FindBestMaterialTab()
    if not best then
        return {
            state = "loading",
            carried = carried,
            text = "Bank tabs are still loading. Try again in a moment.",
        }
    end

    if best.freeSlots <= 0 then
        return {
            state = "full",
            carried = carried,
            tab = best,
            text = "Bank is full — make room in " .. best.name .. " before depositing materials.",
        }
    end

    local materialText = best.materialStacks > 0
        and (best.materialStacks .. " material stack" .. (best.materialStacks == 1 and "" or "s"))
        or "no material stacks yet"
    return {
        state = "ready",
        carried = carried,
        tab = best,
        text = "Suggested tab: " .. best.name .. " — " .. materialText .. ", "
            .. best.freeSlots .. " free slot" .. (best.freeSlots == 1 and "" or "s") .. ".",
        tabCount = tabCount,
    }
end

addon.GetBagAssistantAdvice = GetAdvice

local function ShowTooltip(owner)
    if not GameTooltip then return end
    local advice = GetAdvice()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Bag Assistant", 1, 1, 1)
    GameTooltip:AddLine(advice.text, 0.72, 0.72, 0.72, true)
    local _, nextLabel = GetNextTask and GetNextTask(true)
    GameTooltip:AddLine(assistantRunState == "paused" and "Paused — left- or right-click to resume."
        or (assistantRunState == "running" and "Running automatically — right-click to pause."
            or "Left-click: run all available actions"),
        ACCENT_R, ACCENT_G, ACCENT_B, true)
    if assistantRunState ~= "idle" then
        GameTooltip:AddLine("Next: " .. (nextLabel or "check the bank"), 0.72, 0.72, 0.72, true)
    end
    GameTooltip:AddLine(assistantRunState == "idle" and "Right-click: open the full planner."
        or "Right-click: pause/resume. Shift-right-click: full planner.",
        0.72, 0.72, 0.72, true)
    if lastActionMessage then GameTooltip:AddLine(lastActionMessage, 0.72, 0.72, 0.72, true) end
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function MakeMenuAction(parent, y)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
    button:SetHeight(24)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    button:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("LEFT")
    button:SetScript("OnEnter", function(self)
        if self._enabled then self:SetBackdropColor(0.10, 0.22, 0.20, 0.96) end
        if self._tooltipLink and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self._tooltipLink)
            if self._tooltipTabName then GameTooltip:AddLine(self._tooltipTabName, 0.72, 0.72, 0.72) end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, self._enabled and 0.88 or 0.45)
        if self._tooltipLink then HideTooltip() end
    end)
    return button
end

local function SetMenuAction(button, text, enabled, callback)
    button._enabled = enabled == true
    button._tooltipLink = nil
    button._tooltipTabName = nil
    button.label:SetText(text)
    button.label:SetTextColor(enabled and 0.92 or 0.48, enabled and 0.92 or 0.48, enabled and 0.92 or 0.48, 1)
    button:EnableMouse(enabled == true)
    button:SetBackdropColor(0.08, 0.08, 0.08, enabled and 0.88 or 0.45)
    button:SetScript("OnClick", enabled and callback or nil)
end

local function Deposit(bankType)
    if IsInCombat() or not IsBankOpen() then return false, "Open the bank out of combat first." end
    if addon.HasFrozenBagSlots and addon.HasFrozenBagSlots() then
        return false, "Frozen bag items are present; bulk deposit could move them. Unfreeze them or use a selective transfer."
    end
    if not (C_Bank and C_Bank.AutoDepositItemsIntoBank and bankType) then
        return false, "Bank deposit is unavailable."
    end
    C_Bank.AutoDepositItemsIntoBank(bankType)
    C_Timer.After(0, function()
        if addon.RefreshBagAssistant then addon.RefreshBagAssistant() end
    end)
    return true, "Asked the bank to deposit eligible items. Check the result before another transfer."
end

local function TidyMainBags()
    if IsInCombat() then return false, "Wait until combat ends to sort bags." end
    if addon.HasFrozenBagSlots and addon.HasFrozenBagSlots() then
        if not addon.SortUnfrozenBagSlots then return false, "Frozen-aware sorting is unavailable." end
        addon.SortUnfrozenBagSlots()
        return true, "Sorting only unfrozen Main Bags items."
    end
    if not (C_Container and C_Container.SortBags) then return false, "Sort Bags is unavailable." end
    -- The host button does a visual-only sort in category views. The assistant
    -- always requests a physical Main Bags sort, independently of that view.
    C_Container.SortBags()
    return true, "Asked the client to sort Main Bags."
end

local function SortBank(bankType)
    if IsInCombat() or not IsBankOpen() then return false, "Open the bank out of combat first." end
    if not (C_Container and C_Container.SortBank and bankType) then
        return false, "Bank sorting is unavailable."
    end
    -- Same client API used by EllesmereUI Bags' bank sort button.  This runs
    -- only from the user's click, never from the bank event or a timer.
    C_Container.SortBank(bankType)
    return true, "Asked the bank to sort its "
        .. (bankType == Enum.BankType.Account and "Warband" or "character") .. " tabs."
end

local function ApplyTabCleanup()
    if IsInCombat() or not IsBankOpen() or not (C_Bank and C_Bank.UpdateBankTabSettings
        and Enum and Enum.BankType) then return false, "Bank tab editing is unavailable." end
    local plan = ScanBankPlan()
    local submitted = 0
    for _, change in ipairs(plan.cleanups) do
        if change.isWarband or not IsPortableWarbandBank() then
            local bankType = change.isWarband and Enum.BankType.Account or Enum.BankType.Character
            -- One explicit click applies the high-confidence batch. Custom
            -- names/icons stay intact; their deposit category may be updated.
            C_Bank.UpdateBankTabSettings(bankType, change.bagID, change.name,
                change.icon, change.depositFlags)
            submitted = submitted + 1
        end
    end
    if submitted == 0 then return false, "No tabs qualify for automatic settings." end
    return true, "Submitted " .. submitted .. " tab settings update" .. (submitted == 1 and "" or "s") .. "."
end
addon.ApplyBagAssistantTabCleanup = ApplyTabCleanup

GetNextTask = function(ignorePaused)
    if assistantRunState == "paused" and not ignorePaused then
        return "paused", "Resume Bag Assistant"
    end
    if IsInCombat() then return "wait", "Wait until combat ends" end
    if addon.IsFrozenBagSortActive and addon.IsFrozenBagSortActive() then
        return "wait", "Wait for frozen-aware sorting"
    end
    if pendingActionUntil and GetTime and GetTime() < pendingActionUntil then
        return "wait", "Wait for the last action to finish"
    end
    pendingActionUntil = nil
    if IsGuildBankOpen() and not IsBankOpen() then
        if pendingGuildMove then
            local source = pendingGuildMove.source
            if GetGuildBankItemLink(source.tab, source.slot) == source.link
                or GetGuildBankItemLink(pendingGuildMove.target.index, pendingGuildMove.slot) ~= source.link then
                return "wait", "Wait for the last Guild Bank transfer"
            end
            pendingGuildMove = nil
        end
        local guildPlan = ScanGuildPlan()
        if guildPlan.cleanup then return "guild_organize", "Organize selected Guild Bank tab" end
        if guildPlan.move then
            return "guild_move", "Move " .. guildPlan.move.source.category
                .. " to Guild Bank " .. guildPlan.move.target.name
        end
        return "menu", "Review Guild Bank organization"
    end
    if not IsBankOpen() then return "visit", "Visit a bank, then click again" end
    local advice = GetAdvice()
    if advice.state == "loading" then return "wait", "Wait for bank tabs to load" end

    local plan = ScanBankPlan()
    if pendingOutdatedMove then
        local source = pendingOutdatedMove.source
        local oldItem = C_Container.GetContainerItemInfo(source.bagID, source.slot)
        local destItem = C_Container.GetContainerItemInfo(pendingOutdatedMove.bagID, pendingOutdatedMove.slot)
        if (oldItem and oldItem.itemID == source.itemID)
            or not (destItem and destItem.itemID == source.itemID) then
            return "wait", "Wait for the last gear withdrawal"
        end
        pendingOutdatedMove = nil
    end
    if assistantRunMode == "withdraw" and assistantRunState ~= "idle" then
        if #plan.outdated > 0 and C_Container and C_Container.PickupContainerItem
            and CursorHasItem and not CursorHasItem() then
            return "withdraw", "Withdraw outdated bank gear"
        end
        return "menu", "Outdated-gear withdrawal complete"
    end
    if autoOrganizedThisBankVisit and CountAccessibleCleanups(plan) > 0 then
        if GetTime and autoOrganizedAt and GetTime() - autoOrganizedAt < 3 then
            return "wait", "Wait for bank tab settings to refresh"
        end
        return "menu", "Check unconfirmed bank tab settings"
    end
    if not autoOrganizedThisBankVisit and C_Bank and C_Bank.UpdateBankTabSettings
        and Enum and Enum.BankType and CountAccessibleCleanups(plan) > 0 then
        return "organize", "Organize bank tab settings"
    end

    local characterTab = not IsPortableWarbandBank() and FindBestMaterialTab(false)
    local frozenBags = addon.HasFrozenBagSlots and addon.HasFrozenBagSlots()
    if not frozenBags and advice.carried > 0 and characterTab and characterTab.freeSlots > 0
        and attemptedDepositMaterialCount ~= advice.carried
        and C_Bank and C_Bank.AutoDepositItemsIntoBank
        and Enum and Enum.BankType and Enum.BankType.Character then
        return "deposit", "Deposit eligible reagents"
    end
    local warbandTab = FindBestMaterialTab(true)
    if not frozenBags and warbandTab and warbandTab.freeSlots > 0 and not attemptedWarbandDepositThisBankVisit
        and C_Bank and C_Bank.AutoDepositItemsIntoBank
        and Enum and Enum.BankType and Enum.BankType.Account then
        return "warband", "Deposit eligible Warbound items"
    end
    if pendingCategoryMove then
        local source = pendingCategoryMove.source
        local oldItem = C_Container.GetContainerItemInfo(source.bagID, source.slot)
        local destItem = C_Container.GetContainerItemInfo(pendingCategoryMove.bagID, pendingCategoryMove.slot)
        if (oldItem and oldItem.itemID == source.itemID)
            or not (destItem and destItem.itemID == source.itemID) then
            return "wait", "Wait for the last bank transfer"
        end
        pendingCategoryMove = nil
    end
    if plan.move and C_Container and C_Container.PickupContainerItem and CursorHasItem
        and not CursorHasItem() then
        return "categorize", "Move " .. plan.move.source.category .. " to " .. plan.move.target.name
    end
    if #plan.outdated > 0 and C_Container and C_Container.PickupContainerItem
        and CursorHasItem and not CursorHasItem() then
        return "withdraw", "Withdraw outdated bank gear"
    end
    if not sortedBagsThisBankVisit and ((frozenBags and addon.SortUnfrozenBagSlots)
        or (C_Container and C_Container.SortBags)) then
        return "sort_bags", "Sort Main Bags"
    end
    if not sortedCharacterBankThisBankVisit and not IsPortableWarbandBank()
        and characterTab and C_Container and C_Container.SortBank
        and Enum and Enum.BankType and Enum.BankType.Character then
        return "sort_character", "Sort character bank"
    end
    if not sortedWarbandBankThisBankVisit and warbandTab
        and C_Container and C_Container.SortBank
        and Enum and Enum.BankType and Enum.BankType.Account then
        return "sort_warband", "Sort Warband bank"
    end
    return "menu", "Review other bank actions"
end
addon.GetBagAssistantNextTask = GetNextTask

local function MoveCategoryItem()
    if IsInCombat() or not IsBankOpen() or (CursorHasItem and CursorHasItem()) then
        return false, "Open the bank out of combat with an empty cursor."
    end
    if not (C_Container and C_Container.PickupContainerItem and CursorHasItem) then
        return false, "Bank transfers are unavailable."
    end
    local proposal = ScanBankPlan().move
    if not proposal then return false, "No safe category transfer is ready." end
    local source, target = proposal.source, proposal.target
    local current = C_Container.GetContainerItemInfo(source.bagID, source.slot)
    if not (current and current.itemID == source.itemID and not current.isLocked) then
        return false, "The source item changed; scan again."
    end
    if source.link and current.hyperlink and source.link ~= current.hyperlink then
        return false, "The source item changed; scan again."
    end
    if source.isCarried and addon.IsFrozenBagSlot
        and addon.IsFrozenBagSlot(source.bagID, source.slot, current) then
        return false, "That item is frozen; it will not be moved."
    end
    if IsPortableWarbandBank() and not target.isWarband then
        return false, "The character bank is not accessible here."
    end
    if (source.isCarried or (target.isWarband and not source.isWarband))
        and not IsAllowedInBankType(source, target.isWarband and Enum.BankType.Account
            or Enum.BankType.Character) then
        return false, "The destination bank no longer accepts that item."
    end
    local slots = C_Container.GetContainerNumSlots(target.bagID) or 0
    local destSlot
    for slot = 1, slots do
        if not C_Container.GetContainerItemInfo(target.bagID, slot) then
            destSlot = slot
            break
        end
    end
    if not destSlot then return false, "The destination tab filled; scan again." end
    C_Container.PickupContainerItem(source.bagID, source.slot)
    if not CursorHasItem() then return false, "Could not pick up the item." end
    C_Container.PickupContainerItem(target.bagID, destSlot)
    if CursorHasItem() then
        if not C_Container.GetContainerItemInfo(source.bagID, source.slot) then
            C_Container.PickupContainerItem(source.bagID, source.slot)
        end
        return false, "Could not place the item. Check your cursor."
    end
    pendingCategoryMove = { source = source, bagID = target.bagID, slot = destSlot }
    return true, "Moved " .. source.category .. " to " .. target.name .. "."
end
addon.MoveBagAssistantCategoryItem = MoveCategoryItem

local function FindFreeCarriedSlot()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    for bagID = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, slots do
            if not C_Container.GetContainerItemInfo(bagID, slot) then return bagID, slot end
        end
    end
end

local function WithdrawOutdatedGear(candidate)
    if IsInCombat() or not IsBankOpen() then return false, "Open the bank out of combat first." end
    if not (candidate and C_Container and C_Container.GetContainerItemInfo
        and C_Container.PickupContainerItem and CursorHasItem) then
        return false, "Item transfer is unavailable."
    end
    if CursorHasItem() then return false, "Put down the item on your cursor first." end
    local current = C_Container.GetContainerItemInfo(candidate.bagID, candidate.slot)
    if not (current and current.itemID == candidate.itemID and not current.isLocked) then
        return false, "That bank slot changed; scan it again."
    end
    if candidate.link and current.hyperlink and current.hyperlink ~= candidate.link then
        return false, "That bank item changed; scan it again."
    end
    -- Revalidate against a fresh scan so a new gear threshold or tab contents
    -- cannot turn a stale suggestion into a different withdrawal.
    local stillOutdated = false
    for _, entry in ipairs(ScanBankPlan().outdated) do
        if entry.bagID == candidate.bagID and entry.slot == candidate.slot
            and entry.itemID == candidate.itemID then stillOutdated = true; break end
    end
    if not stillOutdated then return false, "This item is no longer flagged as outdated." end
    local destBag, destSlot = FindFreeCarriedSlot()
    if not destBag then return false, "No free space in your bags." end

    -- Revalidate each source and destination immediately before moving it.
    C_Container.PickupContainerItem(candidate.bagID, candidate.slot)
    if not CursorHasItem() then return false, "Could not pick up the bank item." end
    C_Container.PickupContainerItem(destBag, destSlot)
    if CursorHasItem() then
        if not C_Container.GetContainerItemInfo(candidate.bagID, candidate.slot) then
            C_Container.PickupContainerItem(candidate.bagID, candidate.slot)
        end
        return false, "Could not place the item. Check your cursor."
    end
    pendingOutdatedMove = { source = candidate, bagID = destBag, slot = destSlot }
    return true, "Moved " .. candidate.name .. " to your bags."
end
addon.WithdrawBagAssistantOutdatedGear = WithdrawOutdatedGear

local function SetMenuNotice(message)
    if assistantMenu and assistantMenu.hint then assistantMenu.hint:SetText(message or "") end
end

UpdateMenu = function()
    if not assistantMenu then return end
    local advice = GetAdvice()
    assistantMenu.status:SetText(advice.text)
    if IsGuildBankOpen() and not IsBankOpen() then
        local guildPlan = ScanGuildPlan()
        local nextTask = GetNextTask()
        SetMenuAction(assistantMenu.reagents, "Character-bank deposit — unavailable here", false)
        SetMenuAction(assistantMenu.warbound, "Warband deposit — unavailable here", false)
        SetMenuAction(assistantMenu.tidy, "Tidy & Categorize Guild Bank",
            nextTask ~= "wait" and nextTask ~= "paused" and not IsInCombat(),
            function() AdvanceAssistant(false, "all") end)
        for _, view in ipairs(BANK_VIEWS) do
            SetMenuAction(assistantMenu.viewButtons[view.index], view.label, false)
        end
        assistantMenu.tabLabel:SetText(guildPlan.selected
            and ("SELECTED GUILD TAB  " .. guildPlan.selected.name)
            or "SELECTED GUILD TAB  Waiting for guild data")
        SetMenuAction(assistantMenu.openTab, "Guild tab selection stays in the bank", false)
        SetMenuAction(assistantMenu.editTab, "Edit guild tab", false)
        SetMenuAction(assistantMenu.organize,
            guildPlan.cleanup and ("Name and skin selected tab as " .. guildPlan.cleanup.name)
                or "No safe Guild Bank tab edit",
            guildPlan.cleanup ~= nil and not IsInCombat(), function()
                local _, message = ApplyGuildTabCleanup()
                UpdateMenu()
                SetMenuNotice(message)
            end)
        assistantMenu.gearLabel:SetText(guildPlan.move
            and ("CATEGORY TRANSFER  " .. guildPlan.move.source.category .. " to "
                .. guildPlan.move.target.name)
            or "CATEGORY TRANSFER  No permitted move from the selected tab")
        SetMenuAction(assistantMenu.nextGear, "Select a different guild tab in the bank", false)
        SetMenuAction(assistantMenu.withdrawGear, "Move one item to matching guild tab",
            guildPlan.move ~= nil and not IsInCombat(), function()
                local _, message = MoveGuildCategoryItem()
                UpdateMenu()
                SetMenuNotice(message)
            end)
        assistantMenu.withdrawGear._tooltipLink = guildPlan.move and guildPlan.move.source.link
        assistantMenu.withdrawGear._tooltipTabName = guildPlan.move and guildPlan.move.target.name
        assistantMenu.hint:SetText("Guild Bank moves need your click and current guild permissions.")
        return
    end
    local plan = ScanBankPlan()
    assistantMenu.plan = plan
    local viewControls = IsBankOpen() and GetBankViewButtons() or {}
    local frozenBags = addon.HasFrozenBagSlots and addon.HasFrozenBagSlots()

    local canDepositCharacter = not frozenBags and IsBankOpen() and not IsInCombat() and not IsPortableWarbandBank()
        and C_Bank and C_Bank.AutoDepositItemsIntoBank and Enum and Enum.BankType and Enum.BankType.Character
        and true or false
    local canDepositWarband = not frozenBags and IsBankOpen() and not IsInCombat()
        and C_Bank and C_Bank.AutoDepositItemsIntoBank
        and Enum and Enum.BankType and Enum.BankType.Account and true or false
    local nextTask, nextLabel = GetNextTask()

    SetMenuAction(assistantMenu.reagents,
        canDepositCharacter and "Deposit Reagents"
            or (frozenBags and "Deposit Reagents — frozen slots present"
                or "Deposit Reagents — visit a character bank"),
        canDepositCharacter,
        function() Deposit(Enum.BankType.Character) end)
    SetMenuAction(assistantMenu.warbound,
        canDepositWarband and "Deposit Warbound Items"
            or (frozenBags and "Deposit Warbound Items — frozen slots present"
                or "Deposit Warbound Items — bank unavailable"),
        canDepositWarband,
        function() Deposit(Enum.BankType.Account) end)
    SetMenuAction(assistantMenu.tidy,
        "Tidy & Categorize All",
        nextTask ~= "wait" and not IsInCombat(),
        function() AdvanceAssistant(false, "all") end)

    for _, view in ipairs(BANK_VIEWS) do
        local control = viewControls[view.index]
        local selected = control and control._isSelected
        SetMenuAction(assistantMenu.viewButtons[view.index],
            (selected and "• " or "") .. view.label, control ~= nil and not IsInCombat(),
            function()
                SelectBankView(view.index)
                UpdateMenu()
            end)
    end

    local tab = advice.tab
    if tab then
        assistantMenu.tabLabel:SetText("SUGGESTED PHYSICAL TAB  " .. tab.name .. "  ·  "
            .. tab.freeSlots .. " free")
        local tabControl = viewControls[tab.index]
        SetMenuAction(assistantMenu.openTab, "Open suggested tab", tabControl ~= nil and not IsInCombat(),
            function()
                SelectBankView(tab.index)
                UpdateMenu()
            end)
        SetMenuAction(assistantMenu.editTab, "Edit tab settings", tabControl ~= nil and not IsInCombat(),
            function()
                if SelectBankView(tab.index, "RightButton") then
                    assistantMenu:Hide()
                end
            end)
    elseif advice.state == "away" then
        assistantMenu.tabLabel:SetText("SUGGESTED PHYSICAL TAB  Open the bank to scan")
        SetMenuAction(assistantMenu.openTab, "Open suggested tab", false)
        SetMenuAction(assistantMenu.editTab, "Edit tab settings", false)
    else
        assistantMenu.tabLabel:SetText("SUGGESTED PHYSICAL TAB  Waiting for bank tabs")
        SetMenuAction(assistantMenu.openTab, "Open suggested tab", false)
        SetMenuAction(assistantMenu.editTab, "Edit tab settings", false)
    end

    local accessibleCleanups = CountAccessibleCleanups(plan)
    local canOrganize = IsBankOpen() and not IsInCombat() and accessibleCleanups > 0
        and C_Bank and C_Bank.UpdateBankTabSettings and Enum and Enum.BankType and true or false
    SetMenuAction(assistantMenu.organize,
        accessibleCleanups > 0 and ("Organize " .. accessibleCleanups .. " bank tab" .. (accessibleCleanups == 1 and "" or "s")
            .. " (name, icon, deposit settings)") or "No tabs qualify for auto-organize",
        canOrganize,
        function()
            local _, message = ApplyTabCleanup()
            UpdateMenu()
            SetMenuNotice(message)
        end)

    local gearCount = #plan.outdated
    assistantMenu.gearIndex = math.min(math.max(assistantMenu.gearIndex or 1, 1), math.max(gearCount, 1))
    local candidate = plan.outdated[assistantMenu.gearIndex]
    if candidate then
        assistantMenu.gearLabel:SetText("OUTDATED GEAR  " .. assistantMenu.gearIndex .. "/" .. gearCount
            .. "  ·  ilvl " .. candidate.level .. " / " .. plan.threshold .. " cutoff\n"
            .. candidate.name)
    else
        assistantMenu.gearLabel:SetText(plan.threshold
            and ("OUTDATED GEAR  No bank gear at ilvl " .. plan.threshold .. " or lower")
            or "OUTDATED GEAR  Open the bank to compare item levels")
    end
    SetMenuAction(assistantMenu.nextGear,
        gearCount > 1 and "Next item" or "No more items", gearCount > 1,
        function()
            assistantMenu.gearIndex = assistantMenu.gearIndex % gearCount + 1
            UpdateMenu()
        end)
    SetMenuAction(assistantMenu.withdrawGear,
        gearCount > 0 and ("Withdraw all " .. gearCount .. " outdated gear") or "No outdated gear to withdraw",
        candidate ~= nil and not IsInCombat() and CursorHasItem and C_Container
            and C_Container.PickupContainerItem and true or false,
        function()
            AdvanceAssistant(false, "withdraw")
            assistantMenu.gearIndex = 1
            UpdateMenu()
            SetMenuNotice(lastActionMessage)
        end)
    assistantMenu.withdrawGear._tooltipLink = candidate and candidate.link
    assistantMenu.withdrawGear._tooltipTabName = candidate and candidate.tabName
    assistantMenu.hint:SetText(tab and not viewControls[tab.index]
        and "Individual tabs are hidden in the bank sidebar; show them there to open or edit one."
        or "Numbered tabs hold items; auto-deposit still follows the bank's deposit flags.")
end

local function BuildMenu()
    if assistantMenu then return assistantMenu end
    local menu = CreateFrame("Frame", "WaffleHouseBagAssistantMenu", UIParent, "BackdropTemplate")
    menu:SetSize(390, 480)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.025, 0.025, 0.025, 0.97)
    menu:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)

    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", 10, -9)
    menu.title:SetText("BAG ASSISTANT")
    menu.title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)

    menu.status = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.status:SetPoint("TOPLEFT", 10, -28)
    menu.status:SetPoint("TOPRIGHT", -10, -28)
    menu.status:SetJustifyH("LEFT")
    menu.status:SetJustifyV("TOP")
    menu.status:SetWordWrap(true)
    menu.status:SetTextColor(0.78, 0.78, 0.78)
    menu.status:SetHeight(44)

    menu.reagents = MakeMenuAction(menu, -80)
    menu.warbound = MakeMenuAction(menu, -107)
    menu.tidy = MakeMenuAction(menu, -134)

    local function Divider(y)
        local line = menu:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
        line:SetSize(370, 1)
        line:SetColorTexture(1, 1, 1, 0.12)
    end
    local function Caption(y, text)
        local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
        label:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, y)
        label:SetJustifyH("LEFT")
        label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        label:SetText(text)
        return label
    end
    local function HalfAction(y, right)
        local button = MakeMenuAction(menu, y)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", right and 199 or 10, y)
        button:SetSize(181, 24)
        return button
    end

    Divider(-166)
    Caption(-175, "BANK VIEWS")
    menu.viewButtons = {}
    for index, view in ipairs(BANK_VIEWS) do
        menu.viewButtons[view.index] = HalfAction(index <= 2 and -193 or -220, index % 2 == 0)
    end
    Divider(-252)
    menu.tabLabel = Caption(-260, "SUGGESTED PHYSICAL TAB")
    menu.tabLabel:SetWordWrap(true)
    menu.tabLabel:SetHeight(30)
    menu.openTab = HalfAction(-298, false)
    menu.editTab = HalfAction(-298, true)
    menu.organize = MakeMenuAction(menu, -329)
    Divider(-361)
    menu.gearLabel = Caption(-369, "OUTDATED GEAR")
    menu.gearLabel:SetWordWrap(true)
    menu.gearLabel:SetHeight(35)
    menu.nextGear = HalfAction(-412, false)
    menu.withdrawGear = HalfAction(-412, true)
    menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.hint:SetPoint("TOPLEFT", 10, -446)
    menu.hint:SetPoint("TOPRIGHT", -10, -446)
    menu.hint:SetJustifyH("LEFT")
    menu.hint:SetTextColor(0.54, 0.54, 0.54)
    menu.hint:SetWordWrap(true)

    menu:SetScript("OnShow", UpdateMenu)
    menu:Hide()
    assistantMenu = menu
    return menu
end

local function UpdateButton()
    if not assistantButton then return end
    assistantButton.icon:SetTexture(BAG_ICON_TEXTURE)
    assistantButton.icon:SetDesaturated(false)
    assistantButton.icon:SetVertexColor(1, 1, 1, 1)
    local task = GetNextTask and GetNextTask(true)
    if task == "wait" then
        task = (pendingActionUntil or pendingCategoryMove or pendingGuildMove or pendingOutdatedMove
            or (addon.IsFrozenBagSortActive and addon.IsFrozenBagSortActive()))
            and lastActionTask or nil
    end
    local coords = ACTION_TILE_COORDS[task]
    assistantButton.actionTile:SetShown(coords ~= nil)
    assistantButton.actionAccent:SetShown(coords ~= nil)
    if coords then
        assistantButton.actionTile:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        if task == "warband" or task == "sort_warband" then
            assistantButton.actionAccent:SetColorTexture(0.58, 0.37, 0.96, 1)
        elseif task == "guild_move" or task == "guild_organize" then
            assistantButton.actionAccent:SetColorTexture(0.33, 0.66, 1, 1)
        else
            assistantButton.actionAccent:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end
    end
    local running = assistantRunState == "running"
    assistantButton.stateBorder:Show()
    assistantButton.stateBackground:Show()
    assistantButton.pauseLeft:SetShown(running)
    assistantButton.pauseRight:SetShown(running)
    assistantButton.playIcon:SetShown(not running)
    assistantButton.icon:SetAlpha(assistantButton._hovering and 1 or 0.9)
end

local function ToggleMenu()
    if IsInCombat() then return end
    local menu = BuildMenu()
    if menu:IsShown() then
        menu:Hide()
        return
    end
    HideTooltip()
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", assistantButton, "BOTTOMRIGHT", 0, -5)
    UpdateMenu()
    menu:Show()
end

QueueAdvance = function(delay)
    if assistantRunState ~= "running" or assistantAdvanceQueued then return end
    local serial = assistantRunSerial
    assistantAdvanceQueued = true
    C_Timer.After(delay or 0.8, function()
        if serial ~= assistantRunSerial then return end
        assistantAdvanceQueued = nil
        if assistantRunState == "running" then AdvanceAssistant(true) end
    end)
end

local function PauseAssistant(message)
    assistantRunState = "paused"
    assistantRunSerial = assistantRunSerial + 1
    assistantAdvanceQueued = nil
    lastActionMessage = message
    UpdateButton()
end

AdvanceAssistant = function(fromQueue, requestedMode)
    if IsInCombat() then
        if assistantRunState == "running" then
            lastActionMessage = "Paused by combat; the run will resume when combat ends."
            UpdateButton()
        end
        return
    end
    if assistantRunState == "paused" then
        if fromQueue then return end
        if requestedMode then assistantRunMode = requestedMode end
        assistantRunState = "running"
        assistantActionCount = 0
        assistantWaitCount = 0
    elseif assistantRunState == "idle" then
        assistantRunMode = requestedMode or "all"
        assistantRunState = "running"
        assistantActionCount = 0
        assistantWaitCount = 0
    elseif requestedMode then
        assistantRunMode = requestedMode
    end
    local task = GetNextTask()
    local message, succeeded
    if task == "organize" then
        succeeded, message = ApplyTabCleanup()
        if succeeded then
            autoOrganizedThisBankVisit = true
            autoOrganizedAt = GetTime and GetTime() or nil
        end
    elseif task == "deposit" then
        local carried = CountCarriedMaterialStacks()
        succeeded, message = Deposit(Enum.BankType.Character)
        if succeeded then attemptedDepositMaterialCount = carried end
    elseif task == "warband" then
        succeeded, message = Deposit(Enum.BankType.Account)
        if succeeded then attemptedWarbandDepositThisBankVisit = true end
    elseif task == "categorize" then
        succeeded, message = MoveCategoryItem()
    elseif task == "withdraw" then
        succeeded, message = WithdrawOutdatedGear(ScanBankPlan().outdated[1])
    elseif task == "guild_organize" then
        succeeded, message = ApplyGuildTabCleanup()
    elseif task == "guild_move" then
        succeeded, message = MoveGuildCategoryItem()
    elseif task == "sort_bags" then
        succeeded, message = TidyMainBags()
        if succeeded then sortedBagsThisBankVisit = true end
    elseif task == "sort_character" then
        succeeded, message = SortBank(Enum.BankType.Character)
        if succeeded then sortedCharacterBankThisBankVisit = true end
    elseif task == "sort_warband" then
        succeeded, message = SortBank(Enum.BankType.Account)
        if succeeded then sortedWarbandBankThisBankVisit = true end
    elseif task == "visit" then
        message = "Visit a banker; Bag Assistant will continue when the bank opens."
    elseif task == "wait" then
        message = "Waiting for the bank or last transfer to finish."
    else
        message = "Automatic run complete. Choose a specific action from the planner if needed."
    end

    if task == "menu" then
        assistantRunState = "idle"
        assistantRunMode = "all"
        assistantRunSerial = assistantRunSerial + 1
        assistantAdvanceQueued = nil
    end
    if ACTION_TILE_COORDS[task] then lastActionTask = task end
    lastActionMessage = message
    HideTooltip()
    if assistantMenu and assistantMenu:IsShown() then
        UpdateMenu()
        SetMenuNotice(message)
    end
    if succeeded then
        assistantActionCount = assistantActionCount + 1
        assistantWaitCount = 0
        pendingActionUntil = GetTime and (GetTime() + 0.8) or nil
        if assistantActionCount >= MAX_ASSISTANT_ACTIONS then
            PauseAssistant("Stopped after 150 actions; review the bank before resuming.")
        else
            QueueAdvance(0.85)
        end
    elseif task == "wait" and not IsInCombat() then
        assistantWaitCount = assistantWaitCount + 1
        if assistantWaitCount >= MAX_ASSISTANT_WAITS then
            PauseAssistant("The bank did not confirm the last action; review it before resuming.")
        elseif IsBankOpen() or IsGuildBankOpen() then
            QueueAdvance(0.3)
        end
    elseif task ~= "visit" and task ~= "menu" then
        PauseAssistant(message or "The action could not finish; review the bank before resuming.")
    end
    UpdateButton()
end

local function CreateAssistantButton()
    if assistantButton or not IsEnabled() or IsInCombat() then return assistantButton end
    local bags = GetBags()
    local header = bags and bags.Header
    local bagsButton = bags and bags._bagsBtn
    if not (header and bagsButton) then return nil end

    local button = CreateFrame("Button", nil, header)
    button:SetSize(24, 24)
    -- EllesmereUI Bags uses the exact same gap between Show Bags and Sort.
    button:SetPoint("RIGHT", bagsButton, "LEFT", -6, 0)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(BAG_ICON_TEXTURE)
    button.icon:SetAlpha(0.9)
    -- The bronze satchel remains visible behind a 14px, rounded-square
    -- action tile. The small edge color identifies its destination type.
    button.actionTile = button:CreateTexture(nil, "OVERLAY")
    button.actionTile:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.actionTile:SetSize(14, 14)
    button.actionTile:SetTexture(ACTION_TILE_TEXTURE)
    button.actionAccent = button:CreateTexture(nil, "OVERLAY")
    button.actionAccent:SetPoint("TOPRIGHT", button.actionTile, "TOPRIGHT", -1, -2)
    button.actionAccent:SetSize(1, 10)
    button.stateBorder = button:CreateTexture(nil, "OVERLAY")
    button.stateBorder:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.stateBorder:SetSize(11, 11)
    button.stateBorder:SetColorTexture(0.72, 0.48, 0.19, 1)
    button.stateBackground = button:CreateTexture(nil, "OVERLAY")
    button.stateBackground:SetPoint("CENTER", button.stateBorder, "CENTER")
    button.stateBackground:SetSize(9, 9)
    button.stateBackground:SetColorTexture(0.035, 0.035, 0.035, 1)
    button.pauseLeft = button:CreateTexture(nil, "OVERLAY")
    button.pauseLeft:SetPoint("CENTER", button.stateBorder, "CENTER", -1.75, 0)
    button.pauseLeft:SetSize(2, 6)
    button.pauseLeft:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    button.pauseRight = button:CreateTexture(nil, "OVERLAY")
    button.pauseRight:SetPoint("CENTER", button.stateBorder, "CENTER", 1.75, 0)
    button.pauseRight:SetSize(2, 6)
    button.pauseRight:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    button.playIcon = button:CreateTexture(nil, "OVERLAY")
    button.playIcon:SetPoint("CENTER", button.stateBorder, "CENTER", 0.5, 0)
    button.playIcon:SetSize(8, 8)
    button.playIcon:SetTexture(PLAY_ICON_TEXTURE)
    button.playIcon:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    button:SetScript("OnEnter", function(self)
        self._hovering = true
        self.icon:SetAlpha(1)
        ShowTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self._hovering = nil
        self.icon:SetAlpha(0.9)
        HideTooltip()
    end)
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown and IsShiftKeyDown() or assistantRunState == "idle" then
                ToggleMenu()
            else
                if assistantRunState == "running" then
                    PauseAssistant("Paused; no new actions will start.")
                else
                    assistantRunState = "running"
                    assistantActionCount = 0
                    assistantWaitCount = 0
                    lastActionMessage = "Resuming automatic run."
                    UpdateButton()
                    QueueAdvance(0.1)
                end
            end
        elseif mouseButton == "LeftButton" then
            AdvanceAssistant()
        end
    end)
    assistantButton = button
    UpdateButton()
    return button
end

function addon.RefreshBagAssistant()
    if IsInCombat() then return end
    local button = CreateAssistantButton()
    if button then
        button:SetShown(IsEnabled())
        UpdateButton()
    end
    if assistantMenu and assistantMenu:IsShown() then UpdateMenu() end
end

local function QueueRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = nil
        addon.RefreshBagAssistant()
        if assistantRunState == "running" then QueueAdvance(0.2) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("BANK_TABS_CHANGED")
events:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
for _, eventName in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS" }) do
    pcall(events.RegisterEvent, events, eventName)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if assistantRunState == "running" and name == addonName then
            PauseAssistant("WoW blocked an automatic action. Run stopped to prevent repeated errors.")
        end
        return
    end
    if event == "ADDON_LOADED" and name ~= "EllesmereUIBags" then return end
    if event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
        autoOrganizedThisBankVisit = nil
        autoOrganizedAt = nil
        attemptedDepositMaterialCount = nil
        attemptedWarbandDepositThisBankVisit = nil
        sortedBagsThisBankVisit = nil
        sortedCharacterBankThisBankVisit = nil
        sortedWarbandBankThisBankVisit = nil
        pendingCategoryMove = nil
        pendingOutdatedMove = nil
        pendingActionUntil = nil
    end
    if event == "GUILDBANKFRAME_CLOSED" then
        pendingGuildMove = nil
        pendingActionUntil = nil
    elseif event == "GUILDBANKFRAME_OPENED" and GetSettings().bagAssistantIncludeGuildBank == true
        and GetNumGuildBankTabs and GetGuildBankTabInfo and QueryGuildBankTab then
        local count = GetNumGuildBankTabs()
        if SafeNumber(count) then
            for tabIndex = 1, count do
                local _, _, viewable = GetGuildBankTabInfo(tabIndex)
                if viewable == true then QueryGuildBankTab(tabIndex) end
            end
        end
    end
    QueueRefresh()
    -- EllesmereUI Bags creates its Header in a 0.5s PLAYER_LOGIN timer.
    -- The immediate login refresh sees no header, so attach after that timer
    -- and retry once if another addon delays the host's initialization.
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.8, QueueRefresh)
        C_Timer.After(2, function()
            if not assistantButton and IsEnabled() then QueueRefresh() end
        end)
    end
    -- The bank addon's tab discovery is intentionally deferred one frame after
    -- opening; refresh after it has populated EUI_Bank._allTabs as well.
    if event == "BANKFRAME_OPENED" then C_Timer.After(0.15, QueueRefresh) end
end)
