local addonName, addon = ...
if not addon then return end

-- Waffle House deliberately layers this onto EllesmereUI Bags at runtime.  It
-- never changes the Bags addon files or its SavedVariables.
local FROZEN_TEXTURE = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\bag_slot_frozen_eui.tga"
-- The lock texture remains square. An 11px default keeps its intentionally
-- broad silhouette inside a compact bag-button footprint.
local FREEZE_MARKER_DEFAULT_SIZE = 11
local FREEZE_MARKER_MIN_SIZE = 10
local FREEZE_MARKER_MAX_SIZE = 22
local MARKER_POSITION_VALUES = {
    TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
local MARKER_POSITION_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local visuals = setmetatable({}, { __mode = "k" })
local sortHookButton
local sortHookHandler
local refreshPending
local refreshFollowupPending
local visualHooksInstalled
local frozenSlotManagerOpen
local frozenSlotManagerDraft
local sortRunActive
addon.IsFrozenBagSortActive = function() return sortRunActive == true end
local SORT_MOVE_DELAY = 0.04
local MAX_SORT_MOVE_RETRIES = 8
local MAX_SORT_REPLANS = 2

local function GetSettings()
    return addon.GetSettings and addon.GetSettings() or {}
end

local function GetFrozenSlots()
    local settings = GetSettings()
    if type(settings.bagFrozenSlots) ~= "table" then settings.bagFrozenSlots = {} end
    return settings.bagFrozenSlots
end

local function GetMarkerSize()
    local size = tonumber(GetSettings().bagSlotFreezeMarkerSize) or FREEZE_MARKER_DEFAULT_SIZE
    return math.max(FREEZE_MARKER_MIN_SIZE, math.min(FREEZE_MARKER_MAX_SIZE, math.floor(size + 0.5)))
end

local function SlotKey(bag, slot)
    return tostring(bag) .. ":" .. tostring(slot)
end

local function CopyFrozenRecord(record)
    return {
        itemID = record.itemID,
        itemGUID = record.itemGUID,
    }
end

-- A slot is only a location, not the identity of the frozen item. Retail's
-- container info supplies a GUID for a specific stack, so preserve that
-- identity when an item is manually moved or EllesmereUI recycles a button.
local function ReconcileFrozenSlots()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    local frozen = GetFrozenSlots()
    if not next(frozen) then return end

    local liveByKey, liveByGUID, liveByItemID = {}, {}, {}
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local entry = { bag = bag, slot = slot, key = SlotKey(bag, slot), info = info }
                liveByKey[entry.key] = entry
                if type(info.itemGUID) == "string" and info.itemGUID ~= "" then
                    liveByGUID[info.itemGUID] = entry
                end
                local sameItem = liveByItemID[info.itemID] or {}
                sameItem[#sameItem + 1] = entry
                liveByItemID[info.itemID] = sameItem
            end
        end
    end

    local reconciled = {}
    for key, record in pairs(frozen) do
        if type(record) == "table" and type(record.itemID) == "number" then
            local atSavedSlot = liveByKey[key]
            local location
            if atSavedSlot and atSavedSlot.info.itemID == record.itemID
                and (not record.itemGUID or record.itemGUID == atSavedSlot.info.itemGUID) then
                location = atSavedSlot
            elseif type(record.itemGUID) == "string" and record.itemGUID ~= "" then
                location = liveByGUID[record.itemGUID]
            else
                -- Saved data from before GUID tracking can be repaired only
                -- when precisely one carried copy exists. Never guess between
                -- duplicate stacks and freeze the wrong item.
                local matches = liveByItemID[record.itemID]
                if matches and #matches == 1 then location = matches[1] end
            end
            if location and not reconciled[location.key] then
                local restored = CopyFrozenRecord(record)
                restored.itemID = location.info.itemID
                if type(location.info.itemGUID) == "string" and location.info.itemGUID ~= "" then
                    restored.itemGUID = location.info.itemGUID
                end
                reconciled[location.key] = restored
            end
        end
    end
    GetSettings().bagFrozenSlots = reconciled
end

local function IsFreezeModifierDown()
    local key = GetSettings().bagSlotFreezeModifier
    if key == "shift" then return IsShiftKeyDown and IsShiftKeyDown() end
    if key == "alt" then return IsAltKeyDown and IsAltKeyDown() end
    if key == "ctrl" then return IsControlKeyDown and IsControlKeyDown() end
    return false
end

local function GetSlotData(button)
    if not (button and button.GetParent and button.GetID and C_Container
        and C_Container.GetContainerItemInfo) then return nil end
    local parent = button:GetParent()
    local bag, slot = parent and parent.GetID and parent:GetID(), button:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > 4 or slot < 1 then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    return bag, slot, info
end

local function IsSavedFrozen(bag, slot, info)
    local frozen = GetFrozenSlots()
    local key = SlotKey(bag, slot)
    local record = frozen[key]
    if type(record) ~= "table" then return false end
    return info and info.itemID and record.itemID == info.itemID
        and (not record.itemGUID or record.itemGUID == info.itemGUID) or false
end
addon.IsFrozenBagSlot = function(bag, slot, info)
    return GetSettings().bagSlotFreezeEnabled ~= false and IsSavedFrozen(bag, slot, info)
end

local function GetMainBagsLabel()
    return EllesmereUI and EllesmereUI.L and EllesmereUI.L("Main Bags") or "Main Bags"
end

local function IsMainBagsButton(button)
    local bag, slot, info = GetSlotData(button)
    if not bag then return false end
    local bags = _G.EUI_Bags
    local child = bags and bags._scrollChild
    local parent = button:GetParent()
    if not (child and parent and parent.GetTop) then return false end
    local slotTop = parent:GetTop()
    if not slotTop then return false end

    local closest, distance
    for _, candidate in ipairs({ child:GetChildren() }) do
        local label = candidate and candidate._label
        local text = label and label.GetText and label:GetText()
        local bottom = candidate and candidate.GetBottom and candidate:GetBottom()
        if type(text) == "string" and bottom and bottom >= slotTop then
            local gap = bottom - slotTop
            if not distance or gap < distance then
                closest, distance = text, gap
            end
        end
    end
    local mainLabel = GetMainBagsLabel()
    return type(closest) == "string" and closest:sub(1, #mainLabel) == mainLabel
end

local function GetVisibleItemButtons()
    local bags = _G.EUI_Bags
    local child = bags and bags._scrollChild
    if not (child and child.GetChildren) then return {} end

    local buttons = {}
    for _, parent in ipairs({ child:GetChildren() }) do
        local button = parent and parent.GetChildren and parent:GetChildren()
        if button and button.GetID and parent.GetID and button:IsShown() and parent:IsShown() then
            local bag, slot = parent:GetID(), button:GetID()
            if type(bag) == "number" and type(slot) == "number" and bag >= 0 and bag <= 4 and slot > 0 then
                buttons[#buttons + 1] = button
            end
        end
    end
    return buttons
end

-- The lock texture itself stays unchanged; render it deliberately taller than
-- wide so its silhouette reads as a lock rather than a squat square badge at
-- bag-slot scale. Marker Size continues to mean the visible height.
local FROZEN_MARKER_WIDTH_RATIO = 0.70

local function ApplyMarkerAnchor(texture, button)
    local settings = GetSettings()
    local point = settings.bagSlotFreezeMarkerPosition or "TOPRIGHT"
    texture:ClearAllPoints()
    texture:SetPoint(point, button, point, settings.bagSlotFreezeMarkerX or 0, settings.bagSlotFreezeMarkerY or 0)
    local size = GetMarkerSize()
    texture:SetSize(math.max(1, math.floor(size * FROZEN_MARKER_WIDTH_RATIO + 0.5)), size)
end

local function ApplyFreezeHotspotAnchor(catcher, button)
    local settings = GetSettings()
    local point = settings.bagSlotFreezeMarkerPosition or "TOPRIGHT"
    catcher:ClearAllPoints()
    catcher:SetPoint(point, button, point, settings.bagSlotFreezeMarkerX or 0, settings.bagSlotFreezeMarkerY or 0)
    local size = math.max(14, GetMarkerSize())
    catcher:SetSize(size, size)
end

local function SetEdgeState(entry, state)
    local alpha = state == "frozen" and 0.95 or (state == "preview" and 0.48 or 0)
    for _, edge in ipairs(entry.edges) do edge:SetAlpha(alpha) end
end

local RefreshVisuals

local function GetOrCreateVisual(button)
    local entry = visuals[button]
    if entry then return entry end
    -- The host's inventory buttons are secure templates.  Do not add child
    -- regions while combat-locked; PLAYER_REGEN_ENABLED will create them and
    -- repaint safely once the restriction lifts.
    if InCombatLockdown and InCombatLockdown() then return nil end

    entry = { button = button, edges = {} }
    local marker = button:CreateTexture(nil, "OVERLAY", nil, 7)
    marker:SetTexture(FROZEN_TEXTURE)
    marker:SetTexCoord(0, 1, 0, 1)
    marker:Hide()
    entry.marker = marker

    local catcher = CreateFrame("Button", nil, button)
    -- Never cover the whole secure item button: even a nominal left-click
    -- pass-through can prevent Blizzard's Ctrl+click dress-up preview.
    ApplyFreezeHotspotAnchor(catcher, button)
    catcher:SetFrameLevel(button:GetFrameLevel() + 12)
    catcher:RegisterForClicks("RightButtonUp")
    catcher:Hide()
    entry.catcher = catcher

    local preview = catcher:CreateTexture(nil, "OVERLAY")
    preview:SetTexture(FROZEN_TEXTURE)
    preview:SetTexCoord(0, 1, 0, 1)
    preview:SetVertexColor(0.62, 0.90, 1, 0.72)
    preview:Hide()
    entry.preview = preview

    local function NewEdge()
        local edge = button:CreateTexture(nil, "OVERLAY", nil, 6)
        edge:SetColorTexture(0.20, 0.82, 1, 1)
        edge:Hide()
        entry.edges[#entry.edges + 1] = edge
        return edge
    end
    local top, bottom, left, right = NewEdge(), NewEdge(), NewEdge(), NewEdge()
    top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bottom:SetHeight(1); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    left:SetWidth(1); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetWidth(1); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")

    catcher:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "RightButton" or not IsFreezeModifierDown() then return end
        local bag, slot, info = GetSlotData(button)
        if not (bag and IsMainBagsButton(button)) then return end
        local frozen = GetFrozenSlots()
        local key = SlotKey(bag, slot)
        if IsSavedFrozen(bag, slot, info) then
            frozen[key] = nil
        else
            frozen[key] = { itemID = info.itemID, itemGUID = info.itemGUID }
        end
        if RefreshVisuals then RefreshVisuals() end
    end)
    catcher:SetScript("OnEnter", function() if RefreshVisuals then RefreshVisuals() end end)
    catcher:SetScript("OnLeave", function() if RefreshVisuals then RefreshVisuals() end end)
    visuals[button] = entry
    return entry
end

local function HideVisual(entry)
    entry.marker:Hide()
    entry.preview:Hide()
    entry.catcher:Hide()
    SetEdgeState(entry, nil)
end

RefreshVisuals = function()
    ReconcileFrozenSlots()
    local bags = _G.EUI_Bags
    if not (bags and (not bags.IsShown or bags:IsShown())) then
        for _, entry in pairs(visuals) do HideVisual(entry) end
        return
    end

    local touched = {}
    for _, button in ipairs(GetVisibleItemButtons()) do
        local entry = GetOrCreateVisual(button)
        if entry then
            touched[button] = true
            local bag, slot, info = GetSlotData(button)
            local eligible = GetSettings().bagSlotFreezeEnabled ~= false and bag and IsMainBagsButton(button)
            local frozen = eligible and IsSavedFrozen(bag, slot, info)
            local holdKey = eligible and IsFreezeModifierDown()
            ApplyMarkerAnchor(entry.marker, button)
            ApplyMarkerAnchor(entry.preview, button)
            -- Its parent is a secure item button; never reposition this child
            -- while combat lockdown is active.
            if not (InCombatLockdown and InCombatLockdown()) then
                ApplyFreezeHotspotAnchor(entry.catcher, button)
            end
            entry.marker:SetShown(frozen == true)
            entry.catcher:SetShown(holdKey == true)
            local preview = holdKey and not frozen and (button:IsMouseOver() or entry.catcher:IsMouseOver())
            entry.preview:SetShown(preview == true)
            SetEdgeState(entry, frozen and "frozen" or (preview and "preview" or nil))
        end
    end
    for button, entry in pairs(visuals) do
        if not touched[button] then HideVisual(entry) end
    end
end

local function QueueVisualRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = nil
        RefreshVisuals()
    end)
end

-- EllesmereUI Bags can rebuild/reuse item buttons one frame after Blizzard's
-- bag events. Repaint once immediately and once after that layout pass so a
-- frozen marker cannot vanish during an open, move, sort, or category refresh.
local function QueueVisualRefreshAfterLayout()
    QueueVisualRefresh()
    if refreshFollowupPending then return end
    refreshFollowupPending = true
    C_Timer.After(0.08, function()
        refreshFollowupPending = nil
        QueueVisualRefresh()
    end)
end

local function HasFrozenMainBagSlots()
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and IsSavedFrozen(bag, slot, info) then return true end
        end
    end
    return false
end
addon.HasFrozenBagSlots = function()
    return GetSettings().bagSlotFreezeEnabled ~= false and HasFrozenMainBagSlots()
end

local function ItemNameAndQuality(item)
    local name, _, quality = GetItemInfo(item.itemLink or item.itemID)
    return name or tostring(item.itemID or ""), quality or 0
end

local function BuildSectionOrder(manager)
    local sections, order, grouped = {}, 0, {}
    for index, category in ipairs(manager:GetCategories() or {}) do
        if category.groupName then
            if not grouped[category.groupName] then
                grouped[category.groupName] = true
                order = order + 1
                for _, member in ipairs(manager:GetGroupMembers(category.groupName) or {}) do
                    sections[member] = order
                end
            end
        else
            order = order + 1
            sections[index] = order
        end
    end
    return sections
end

-- This is the host's physical-sort shape applied only to non-frozen slots:
-- category order, then quality/name/item identity. Frozen positions never
-- become a source or destination. Actual bag moves are serialized and checked
-- because a single-frame burst of PickupContainerItem calls can race Retail's
-- temporary slot locks, leaving ordinary holes in an otherwise valid sort.
local function SortUnfrozenSlots(replan)
    if sortRunActive or (InCombatLockdown and InCombatLockdown()) then return end
    local bags = _G.EUI_Bags
    local manager = _G.EUI_CategoryManager
    if not (bags and manager and C_Container and C_Container.GetContainerNumSlots
        and C_Container.GetContainerItemInfo and C_Container.PickupContainerItem) then return end

    ReconcileFrozenSlots()
    replan = tonumber(replan) or 0
    local positions, items = {}, {}
    local waitingForUnlock = false
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.isLocked then
                -- A normal slot lock is transient. Do not misclassify it as
                -- frozen and leave a permanent gap; wait for the bag update,
                -- then build a clean physical plan from unlocked data.
                waitingForUnlock = true
            elseif not (info and IsSavedFrozen(bag, slot, info)) then
                local position = { bag = bag, slot = slot, key = SlotKey(bag, slot) }
                positions[#positions + 1] = position
                if info then
                    local item = {
                        bag = bag, slot = slot, key = position.key, info = info,
                        itemGUID = info.itemGUID, itemID = info.itemID,
                        itemLink = C_Container.GetContainerItemLink(bag, slot),
                    }
                    item.name, item.quality = ItemNameAndQuality(item)
                    items[#items + 1] = item
                end
            end
        end
    end
    if waitingForUnlock then
        if replan < MAX_SORT_REPLANS then
            C_Timer.After(0.12, function() SortUnfrozenSlots(replan + 1) end)
        end
        return
    end
    if #items == 0 or #positions == 0 then return end

    manager:ClassifyAll(items)
    local sections = BuildSectionOrder(manager)
    for _, item in ipairs(items) do item.section = sections[item.categoryIndex] or 9999 end
    table.sort(items, function(left, right)
        if left.section ~= right.section then return left.section < right.section end
        if left.quality ~= right.quality then return left.quality > right.quality end
        if left.name ~= right.name then return left.name < right.name end
        if left.itemID ~= right.itemID then return left.itemID < right.itemID end
        if left.bag ~= right.bag then return left.bag < right.bag end
        return left.slot < right.slot
    end)

    local profile = EllesmereUI and EllesmereUI._bagsDB and EllesmereUI._bagsDB.profile
    local first = profile and profile.bagSortToBottom and (#positions - #items + 1) or 1
    local targets = {}
    for index, item in ipairs(items) do
        targets[#targets + 1] = { position = positions[first + index - 1], wanted = item }
    end

    local sortButton = bags._sortBtn
    local oldRefresh = bags.refreshEnabled
    bags.refreshEnabled = false
    if sortButton then
        sortButton:EnableMouse(false)
        if sortButton.icon then sortButton.icon:SetAlpha(0.22) end
    end
    sortRunActive = true

    local state = { index = 1, retries = {}, targets = targets, unresolved = false }
    local AdvanceSort
    local function TargetHasWantedItem(target, wanted)
        local info = C_Container.GetContainerItemInfo(target.bag, target.slot)
        -- Identical item IDs have identical sort data. Treat either stack as
        -- satisfied so a stack merge cannot create a false failure/retry loop.
        return info and info.itemID == wanted.itemID
    end
    local function FindWantedItem(wanted)
        local fallback
        for bag = 0, 4 do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isLocked and not IsSavedFrozen(bag, slot, info)
                    and info.itemID == wanted.itemID then
                    local position = { bag = bag, slot = slot, key = SlotKey(bag, slot) }
                    if wanted.itemGUID and info.itemGUID == wanted.itemGUID then return position end
                    fallback = fallback or position
                end
            end
        end
        return fallback
    end

    local function HasUnfilledTarget()
        for _, target in ipairs(state.targets) do
            if not C_Container.GetContainerItemInfo(target.position.bag, target.position.slot) then return true end
        end
        return false
    end
    local function FinishSort(retry)
        if state.finished then return end
        state.finished = true
        bags.refreshEnabled = oldRefresh ~= false
        if bags.RefreshInventory then bags:RefreshInventory() end
        if sortButton then
            sortButton:EnableMouse(true)
            if sortButton.icon then sortButton.icon:SetAlpha(0.9) end
        end
        sortRunActive = nil
        QueueVisualRefreshAfterLayout()
        if retry and replan < MAX_SORT_REPLANS then
            C_Timer.After(0.14, function() SortUnfrozenSlots(replan + 1) end)
        end
    end
    local function RetryOrAdvance(target)
        local attempts = (state.retries[target.key] or 0) + 1
        state.retries[target.key] = attempts
        if attempts > MAX_SORT_MOVE_RETRIES then
            state.unresolved = true
            state.index = state.index + 1
        end
        C_Timer.After(SORT_MOVE_DELAY, AdvanceSort)
    end
    AdvanceSort = function()
        if InCombatLockdown and InCombatLockdown() then
            if ClearCursor then ClearCursor() end
            FinishSort(true)
            return
        end
        local step = state.targets[state.index]
        if not step then
            FinishSort(state.unresolved or HasUnfilledTarget())
            return
        end
        local target, wanted = step.position, step.wanted
        local targetInfo = C_Container.GetContainerItemInfo(target.bag, target.slot)
        if targetInfo and IsSavedFrozen(target.bag, target.slot, targetInfo) then
            -- It was never part of the plan, but preserve a freeze added while
            -- this sort was running rather than moving it under the user.
            state.unresolved = true
            state.index = state.index + 1
            C_Timer.After(0, AdvanceSort)
            return
        end
        if targetInfo and targetInfo.isLocked then
            RetryOrAdvance(target)
            return
        end
        if TargetHasWantedItem(target, wanted) then
            state.index = state.index + 1
            C_Timer.After(0, AdvanceSort)
            return
        end
        local source = FindWantedItem(wanted)
        if not source then
            state.unresolved = true
            state.index = state.index + 1
            C_Timer.After(0, AdvanceSort)
            return
        end
        C_Container.PickupContainerItem(source.bag, source.slot)
        C_Container.PickupContainerItem(target.bag, target.slot)
        if ClearCursor then ClearCursor() end
        C_Timer.After(SORT_MOVE_DELAY, function()
            if TargetHasWantedItem(target, wanted) then
                state.retries[target.key] = nil
                state.index = state.index + 1
                AdvanceSort()
            else
                RetryOrAdvance(target)
            end
        end)
    end
    AdvanceSort()
end

local function StartFrozenAwareSort()
    if EllesmereUIDB and EllesmereUIDB.bagSortWarningDismissed then
        SortUnfrozenSlots()
        return
    end
    if not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then
        SortUnfrozenSlots()
        return
    end
    EllesmereUI:ShowConfirmPopup({
        title = "Sort Unfrozen Items",
        message = "Frozen Main Bags items will remain in their exact bag slots. Other Main Bags items will be reorganized around them.",
        confirmText = "Sort",
        cancelText = "Cancel",
        checkbox = "Don't show me again",
        onConfirm = function(dontShowAgain)
            if dontShowAgain then
                EllesmereUIDB = EllesmereUIDB or {}
                EllesmereUIDB.bagSortWarningDismissed = true
            end
            SortUnfrozenSlots()
        end,
    })
end

-- Kept narrow for regression coverage and for Waffle House's own sort-button
-- hook below; this is not an EllesmereUI Bags modification or replacement API.
addon.SortUnfrozenBagSlots = SortUnfrozenSlots

local function InstallSortHook()
    local bags = _G.EUI_Bags
    local sortButton = bags and bags._sortBtn
    if not (sortButton and sortButton.GetScript and sortButton.SetScript) then return end
    local nativeClick = sortButton:GetScript("OnClick")
    if sortButton == sortHookButton and nativeClick == sortHookHandler then return end
    if type(nativeClick) ~= "function" then return end
    local handler = function(self, ...)
        -- Native OneBag and MultiBag physical sorts both touch Main Bags,
        -- regardless of which section is currently visible in the UI.
        if GetSettings().bagSlotFreezeEnabled ~= false and HasFrozenMainBagSlots() then
            StartFrozenAwareSort()
        else
            nativeClick(self, ...)
        end
    end
    sortButton:SetScript("OnClick", handler)
    sortHookButton, sortHookHandler = sortButton, handler
end

local function InstallVisualHooks()
    local bags = _G.EUI_Bags
    if visualHooksInstalled or not bags then return end
    if bags.HookScript then
        bags:HookScript("OnShow", QueueVisualRefreshAfterLayout)
    end
    if hooksecurefunc and type(bags.RefreshInventory) == "function" then
        hooksecurefunc(bags, "RefreshInventory", QueueVisualRefreshAfterLayout)
    end
    visualHooksInstalled = true
    QueueVisualRefreshAfterLayout()
end

local function StartFrozenSlotManagerDraft()
    ReconcileFrozenSlots()
    frozenSlotManagerDraft = {}
    for key, record in pairs(GetFrozenSlots()) do
        if type(record) == "table" and type(record.itemID) == "number" then
            frozenSlotManagerDraft[key] = CopyFrozenRecord(record)
        end
    end
    frozenSlotManagerOpen = true
end

local function GetFrozenSlotManagerEntries(frozen)
    local entries = {}
    if not (C_Container and C_Container.GetContainerItemInfo) then return entries end
    for key, record in pairs(frozen or {}) do
        local bag, slot = key:match("^(%-?%d+):(%d+)$")
        bag, slot = tonumber(bag), tonumber(slot)
        local info = bag and slot and C_Container.GetContainerItemInfo(bag, slot)
        if type(record) == "table" and info and info.itemID == record.itemID
            and (not record.itemGUID or record.itemGUID == info.itemGUID) then
            local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
            local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID))
                or (link and link:match("%[(.-)%]")) or ("Item " .. tostring(info.itemID))
            entries[#entries + 1] = {
                bag = bag,
                itemID = info.itemID,
                key = key,
                link = link,
                name = name,
                slot = slot,
            }
        end
    end
    table.sort(entries, function(left, right)
        if left.bag ~= right.bag then return left.bag < right.bag end
        return left.slot < right.slot
    end)
    return entries
end

function addon.BuildBagsPage(parent, yOffset)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return yOffset end
    local y, h = yOffset, 0
    local function Refresh()
        QueueVisualRefresh()
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end
    local function Rebuild()
        QueueVisualRefreshAfterLayout()
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    _, h = W:SectionHeader(parent, "FROZEN SLOTS", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Freeze Bag Slots",
            tooltip = "Hold the selected modifier and right-click the small lock marker on an item in OneBag's Main Bags section to freeze or unfreeze it. Ctrl+left-click on the item remains available for Blizzard's preview. Frozen items stay in their physical bag slots when using Sort Items.",
            getValue = function() return GetSettings().bagSlotFreezeEnabled ~= false end,
            setValue = function(value) GetSettings().bagSlotFreezeEnabled = value and true or false; Refresh() end,
        },
        {
            type = "dropdown",
            text = "Freeze Modifier",
            values = { ctrl = "Ctrl", shift = "Shift", alt = "Alt", disabled = "Disabled" },
            order = { "ctrl", "shift", "alt", "disabled" },
            tooltip = "Hold this key while hovering a Main Bags item to reveal its lock marker, then right-click that marker to freeze. Disabled turns the feature off without removing saved freezes.",
            getValue = function() return GetSettings().bagSlotFreezeModifier end,
            setValue = function(value) GetSettings().bagSlotFreezeModifier = value; Refresh() end,
        }
    ); y = y - h

    _, h = W:DropdownWithOffsets(parent, y,
        {
            type = "dropdown",
            text = "Frozen Marker",
            values = MARKER_POSITION_VALUES,
            order = MARKER_POSITION_ORDER,
            tooltip = "Choose any corner, edge, or the center used by the frozen-lock marker. X and Y let you nudge it precisely without crowding another bag label.",
            getValue = function() return GetSettings().bagSlotFreezeMarkerPosition end,
            setValue = function(value) GetSettings().bagSlotFreezeMarkerPosition = value; Refresh() end,
        },
        {
            text = "X", min = -12, max = 12, step = 1,
            tooltip = "Horizontal frosted-lock marker offset.",
            getValue = function() return GetSettings().bagSlotFreezeMarkerX or 0 end,
            setValue = function(value) GetSettings().bagSlotFreezeMarkerX = value; Refresh() end,
        },
        {
            text = "Y", min = -12, max = 12, step = 1,
            tooltip = "Vertical frosted-lock marker offset.",
            getValue = function() return GetSettings().bagSlotFreezeMarkerY or 0 end,
            setValue = function(value) GetSettings().bagSlotFreezeMarkerY = value; Refresh() end,
        }
    ); y = y - h

    _, h = W:Slider(parent, "Frozen Marker Size", y, FREEZE_MARKER_MIN_SIZE, FREEZE_MARKER_MAX_SIZE, 1,
        function() return GetMarkerSize() end,
        function(value)
            GetSettings().bagSlotFreezeMarkerSize = math.max(FREEZE_MARKER_MIN_SIZE,
                math.min(FREEZE_MARKER_MAX_SIZE, math.floor((tonumber(value) or FREEZE_MARKER_DEFAULT_SIZE) + 0.5)))
            Refresh()
        end,
        "Resize the frozen-lock marker. The smaller default matches EllesmereUI's compact icon language; increase it only if you need more visual weight."); y = y - h

    _, h = W:SectionHeader(parent, "MANAGEMENT", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Frozen Slots",
            buttonText = frozenSlotManagerOpen and "Hide Frozen Items" or "View Frozen Items",
            tooltip = "Review and manage frozen Main Bags items here. Click again to close the inline manager without saving; Save applies its changes and Cancel discards them.",
            onClick = function()
                if frozenSlotManagerOpen then
                    frozenSlotManagerDraft = nil
                    frozenSlotManagerOpen = false
                else
                    StartFrozenSlotManagerDraft()
                end
                Rebuild()
            end,
        }
    ); y = y - h

    if frozenSlotManagerOpen then
        _, h = W:SectionHeader(parent, "FROZEN SLOT MANAGER", y); y = y - h
        local entries = GetFrozenSlotManagerEntries(frozenSlotManagerDraft)
        if #entries == 0 then
            _, h = W:DualRow(parent, y, {
                type = "label",
                text = "No frozen items are currently available.",
                tooltip = "There are no saved frozen Main Bags items to manage. Frozen items that were used, sold, or otherwise removed are cleaned up automatically.",
            }); y = y - h
        else
            for _, entry in ipairs(entries) do
                local draftKey = entry.key
                _, h = W:DualRow(parent, y, {
                    type = "labeledButton",
                    text = entry.link or entry.name,
                    buttonText = "Unfreeze",
                    tooltip = "Main Bags — bag " .. tostring(entry.bag) .. ", slot " .. tostring(entry.slot)
                        .. ". Removes this item from the draft only; choose Save to apply it.",
                    onClick = function()
                        if frozenSlotManagerDraft then frozenSlotManagerDraft[draftKey] = nil end
                        Rebuild()
                    end,
                }); y = y - h
            end
            _, h = W:DualRow(parent, y, {
                type = "labeledButton",
                text = "Frozen Slots",
                buttonText = "Clear Draft",
                tooltip = "Remove every frozen item from this draft. Nothing changes in your bags until you choose Save.",
                onClick = function()
                    frozenSlotManagerDraft = {}
                    Rebuild()
                end,
            }); y = y - h
        end
        _, h = W:DualRow(parent, y,
            {
                type = "button",
                text = "Save",
                tooltip = "Apply this Frozen Slots draft and return to the compact management row.",
                onClick = function()
                    GetSettings().bagFrozenSlots = frozenSlotManagerDraft or {}
                    ReconcileFrozenSlots()
                    frozenSlotManagerDraft = nil
                    frozenSlotManagerOpen = false
                    Rebuild()
                end,
            },
            {
                type = "button",
                text = "Cancel",
                tooltip = "Discard this Frozen Slots draft and return to the compact management row.",
                onClick = function()
                    frozenSlotManagerDraft = nil
                    frozenSlotManagerOpen = false
                    Rebuild()
                end,
            }
        ); y = y - h
    end
    if addon.BuildRecentItemsBagsPage then y = addon.BuildRecentItemsBagsPage(parent, y) end

    _, h = W:SectionHeader(parent, "BAG ASSISTANT", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Show Bag Assistant",
            tooltip = "Show the assistant button beside the bag controls.",
            getValue = function() return GetSettings().bagAssistantEnabled ~= false end,
            setValue = function(value)
                GetSettings().bagAssistantEnabled = value and true or false
                if addon.RefreshBagAssistant then addon.RefreshBagAssistant() end
            end,
        },
        {
            type = "toggle",
            text = "Include Guild Bank",
            tooltip = "Opt in to Guild Bank organization when it is open and your guild permissions permit it. Guild moves still require a click.",
            getValue = function() return GetSettings().bagAssistantIncludeGuildBank == true end,
            setValue = function(value)
                GetSettings().bagAssistantIncludeGuildBank = value and true or false
                if addon.RefreshBagAssistant then addon.RefreshBagAssistant() end
            end,
        }
    ); y = y - h
    return math.abs(y)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "EllesmereUIBags" then return end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED"
        or event == "BAG_UPDATE_DELAYED" then
        C_Timer.After(0, InstallSortHook)
        C_Timer.After(0, InstallVisualHooks)
    end
    QueueVisualRefreshAfterLayout()
end)
