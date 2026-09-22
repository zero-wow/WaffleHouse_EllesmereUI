local addonName, addon = ...
if not addon then return end

-- A deliberately light integration layer for EllesmereUI Bags.  This owns
-- only its button and menu: it neither rewrites its frames nor reaches into
-- the bank addon's private selected-tab state.
local ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62
local REAGENT_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local TRADEGOODS_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local BAG_ICON_TEXTURE = "Interface\\Buttons\\UI-RefreshButton"
local WARBAND_ICON_TEXTURE = 1542854
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
local UpdateMenu

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

local function GetSortButton()
    local bags = GetBags()
    return bags and bags._sortBtn
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
local function FindBestMaterialTab()
    local bank = GetBank()
    local tabs = bank and bank._allTabs
    if type(tabs) ~= "table" or #tabs == 0 then return nil, 0 end

    local bestAvailable, availableScore
    local bestFull, fullScore
    local tabCount = 0
    for index, tab in ipairs(tabs) do
        if type(tab) == "table" and type(tab.bagID) == "number" then
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
    local plan = { cleanups = {}, outdated = {}, tabCount = 0 }
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
            if category and used >= 4 and dominant / used >= 0.7 and rawName
                and IsGenericTabName(rawName) then
                local suggestedName = category .. " " .. index
                local suggestedIcon = icons[category] or liveData.icon
                if SafeNumber(suggestedIcon) and (suggestedName ~= rawName or suggestedIcon ~= liveData.icon) then
                    plan.cleanups[#plan.cleanups + 1] = {
                        index = index, bagID = tab.bagID, isWarband = tab.isWarband == true,
                        name = suggestedName, icon = suggestedIcon, depositFlags = liveData.depositFlags or 0,
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
    return plan
end

addon.GetBagAssistantPlan = ScanBankPlan

local function GetAdvice()
    local carried = CountCarriedMaterialStacks()
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
    GameTooltip:AddLine("Click for deposit actions and bank guidance.", ACCENT_R, ACCENT_G, ACCENT_B, true)
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
    if IsInCombat() or not IsBankOpen() then return end
    if not (C_Bank and C_Bank.AutoDepositItemsIntoBank and bankType) then return end
    -- This runs synchronously from the user's click; never queue or replay a
    -- protected inventory action from an event/timer.
    C_Bank.AutoDepositItemsIntoBank(bankType)
    C_Timer.After(0, function()
        if addon.RefreshBagAssistant then addon.RefreshBagAssistant() end
    end)
end

local function TidyMainBags()
    if IsInCombat() then return end
    local sortButton = GetSortButton()
    if not (sortButton and sortButton.Click) then return end
    -- Route through EllesmereUI Bags' own button.  That preserves its normal
    -- visual sort and Waffle House's frozen-slot sort interception alike.
    sortButton:Click("LeftButton")
end

local function ApplyTabCleanup()
    if IsInCombat() or not IsBankOpen() or not (C_Bank and C_Bank.UpdateBankTabSettings
        and Enum and Enum.BankType) then return false, "Bank tab editing is unavailable." end
    local plan = ScanBankPlan()
    local submitted = 0
    for _, change in ipairs(plan.cleanups) do
        if change.isWarband or not IsPortableWarbandBank() then
            local bankType = change.isWarband and Enum.BankType.Account or Enum.BankType.Character
            -- One explicit click applies the high-confidence batch. Preserve
            -- each tab's existing deposit flags, and never overwrite a custom
            -- name: ScanBankPlan only proposes changes for generic names.
            C_Bank.UpdateBankTabSettings(bankType, change.bagID, change.name,
                change.icon, change.depositFlags)
            submitted = submitted + 1
        end
    end
    if submitted == 0 then return false, "No generic tabs qualify for cleanup." end
    return true, "Submitted " .. submitted .. " tab name/icon update" .. (submitted == 1 and "" or "s") .. "."
end
addon.ApplyBagAssistantTabCleanup = ApplyTabCleanup

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
    if not (current and current.itemID == candidate.itemID) then
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

    -- Both pickups happen synchronously inside the user's Withdraw click.
    -- Never schedule or repeat a protected inventory action from a timer.
    C_Container.PickupContainerItem(candidate.bagID, candidate.slot)
    if not CursorHasItem() then return false, "Could not pick up the bank item." end
    C_Container.PickupContainerItem(destBag, destSlot)
    if CursorHasItem() then
        if not C_Container.GetContainerItemInfo(candidate.bagID, candidate.slot) then
            C_Container.PickupContainerItem(candidate.bagID, candidate.slot)
        end
        return false, "Could not place the item. Check your cursor."
    end
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
    local plan = ScanBankPlan()
    assistantMenu.plan = plan
    local viewControls = IsBankOpen() and GetBankViewButtons() or {}

    local canDepositCharacter = IsBankOpen() and not IsInCombat() and not IsPortableWarbandBank()
        and C_Bank and C_Bank.AutoDepositItemsIntoBank and Enum and Enum.BankType and Enum.BankType.Character
        and true or false
    local canDepositWarband = IsBankOpen() and not IsInCombat() and C_Bank and C_Bank.AutoDepositItemsIntoBank
        and Enum and Enum.BankType and Enum.BankType.Account and true or false
    local sortButton = GetSortButton()
    local canTidy = not IsInCombat() and sortButton and sortButton.Click and true or false

    SetMenuAction(assistantMenu.reagents,
        canDepositCharacter and "Deposit Reagents" or "Deposit Reagents — visit a character bank",
        canDepositCharacter,
        function() Deposit(Enum.BankType.Character) end)
    SetMenuAction(assistantMenu.warbound,
        canDepositWarband and "Deposit Warbound Items" or "Deposit Warbound Items — bank unavailable",
        canDepositWarband,
        function() Deposit(Enum.BankType.Account) end)
    SetMenuAction(assistantMenu.tidy,
        canTidy and "Tidy & Categorize Main Bags" or "Tidy Main Bags — unavailable",
        canTidy,
        TidyMainBags)

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

    local canOrganize = IsBankOpen() and not IsInCombat() and #plan.cleanups > 0
        and C_Bank and C_Bank.UpdateBankTabSettings and Enum and Enum.BankType and true or false
    SetMenuAction(assistantMenu.organize,
        #plan.cleanups > 0 and ("Organize " .. #plan.cleanups .. " generic tab" .. (#plan.cleanups == 1 and "" or "s")
            .. " (name + icon)") or "No generic tabs qualify for auto-organize",
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
    SetMenuAction(assistantMenu.withdrawGear, "Withdraw selected gear",
        candidate ~= nil and not IsInCombat() and CursorHasItem and C_Container
            and C_Container.PickupContainerItem and true or false,
        function()
            local _, message = WithdrawOutdatedGear(candidate)
            assistantMenu.gearIndex = 1
            UpdateMenu()
            SetMenuNotice(message)
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
    local advice = GetAdvice()
    if IsBankOpen() then
        local icon = advice.tab and advice.tab.icon or WARBAND_ICON_TEXTURE
        assistantButton.icon:SetTexture(icon)
        assistantButton.icon:SetDesaturated(false)
        assistantButton.icon:SetVertexColor(1, 1, 1, 1)
    else
        assistantButton.icon:SetTexture(BAG_ICON_TEXTURE)
        assistantButton.icon:SetDesaturated(true)
        assistantButton.icon:SetVertexColor(0.72, 0.72, 0.72, 1)
    end
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
    local autoCleanupNotice
    if IsBankOpen() and not autoOrganizedThisBankVisit then
        local submitted, message = ApplyTabCleanup()
        if submitted then
            autoOrganizedThisBankVisit = true
            autoCleanupNotice = message
        end
    end
    UpdateMenu()
    menu:Show()
    if autoCleanupNotice then SetMenuNotice(autoCleanupNotice) end
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
    button:SetScript("OnClick", ToggleMenu)
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
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("BANK_TABS_CHANGED")
events:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "EllesmereUIBags" then return end
    if event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
        autoOrganizedThisBankVisit = nil
    end
    QueueRefresh()
    -- The bank addon's tab discovery is intentionally deferred one frame after
    -- opening; refresh after it has populated EUI_Bank._allTabs as well.
    if event == "BANKFRAME_OPENED" then C_Timer.After(0.15, QueueRefresh) end
end)
