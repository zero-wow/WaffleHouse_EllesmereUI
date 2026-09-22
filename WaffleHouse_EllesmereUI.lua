local addonName, addon = ...
local ADDON_FOLDER = addonName

local ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62
local TITLE_H = 26
addon.CurrencyGrid = { size = 38, gap = 4, gutter = 6 }
local ICON_SCALE = 1.1 -- 34px slots with 4px gutters safely fit a 37px icon.
local LIST_ROW_H = 34
local LIST_HEADER_H = 20
-- The regular UI font lacks the triangle sort glyphs on some installs.
local VENDOR_SORT_GLYPH_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Arial Narrow.ttf"
-- A header click sorts.  Holding it intentionally turns that same header into
-- a column-reorder handle, so a normal sort click never flashes a drag guide.
addon.VendorListDragHoldSeconds = 0.25
local SOUL_TRADER_SPECIES_ID = 183
local BAG_FREEZE_MARKER_POSITIONS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
addon.VendorListColumnDefault = { "icon", "pin", "item", "type", "rarity", "cost" }
addon.VendorListColumnText = {
    icon = "ICON",
    pin = "",
    item = "ITEM",
    type = "TYPE",
    rarity = "RARITY",
    cost = "COST",
}
local VENDOR_LIST_COLUMN_MIN_WIDTH = {
    icon = 26,
    pin = 24,
    item = 60,
    type = 56,
    rarity = 56,
    cost = 60,
}

local panel
local selectedCostKey
local refreshPending
local hookedFunctions = {}
local QueueRefresh
local optionsRegistered
local optionsRegistrationTicker
local itemQueueButton
local itemQueueCombatGate
local itemQueueCandidates = {}
local itemQueueLastDecisions = {}
local itemQueueCache = { tooltipInstances = {}, items = {}, followupItems = {}, dirtyBags = {} }
local sessionBannedItems = {}
local incompleteCombinationItems = {}
local itemQueueTooltipRetryPending = { items = {} }
local itemQueueRefreshPending
local itemQueueFollowupRefreshPending
local itemQueueRefreshAfterCombat
local itemQueueAuditRunning
local RefreshItemQueue
local UpdateItemQueueCombatVisibility
local BuildItemQueuePage
local ShowItemQueuePinnedItemsPopup
local ShowItemQueueBannedItemsPopup
local ShowItemQueueDiagnostics
local ShowVendorPlan
local ShowVendorNotePopup
local SetFont
local QueueZygorPointerSkin
local UpdateIgnoredInteractBinding
local InstallConfirmPopupPixelBorderHook
local ignoredInteractBindingOwner
local ignoredInteractBlocker
local UpdateSoulTraderCompanion
local InstallWonderbarReorderHooks
local RefreshWonderbarReorderMode
local soulTraderLastSummonAttempt

BINDING_HEADER_WAFFLEHOUSE = "Waffle House"
_G["BINDING_NAME_CLICK WaffleHouseItemQueueButton:LeftButton"] = "Use queued item"

local ITEM_QUEUE_ORDER = { "knowledge", "recipes", "appearances", "tabards", "mounts", "heirlooms", "toys", "pets", "housing", "account", "combination", "darkmoon", "containers", "currency", "custom" }
local ITEM_QUEUE_TYPES = {
    knowledge = { label = "Profession Knowledge", color = { r = 0.08, g = 0.82, b = 0.67 } },
    recipes = { label = "Recipes", color = { r = 0.63, g = 0.43, b = 0.94 } },
    appearances = { label = "Appearance Unlocks", color = { r = 0.36, g = 0.73, b = 0.94 } },
    tabards = { label = "Tabard Unlocks", color = { r = 0.80, g = 0.52, b = 0.93 } },
    mounts = { label = "Mount Unlocks", color = { r = 0.32, g = 0.84, b = 0.55 } },
    heirlooms = { label = "Heirloom Unlocks", color = { r = 0.88, g = 0.72, b = 0.30 } },
    toys = { label = "Toy Unlocks", color = { r = 0.94, g = 0.58, b = 0.30 } },
    pets = { label = "Battle Pets", color = { r = 0.30, g = 0.66, b = 0.96 } },
    housing = { label = "Housing Decor", color = { r = 0.90, g = 0.56, b = 0.30 } },
    account = { label = "Account Unlocks", color = { r = 0.74, g = 0.56, b = 0.92 } },
    combination = { label = "Combination Items", color = { r = 0.91, g = 0.36, b = 0.26 } },
    darkmoon = { label = "Darkmoon Faire Cards", color = { r = 0.46, g = 0.58, b = 0.94 } },
    containers = { label = "Boxes & Caches", color = { r = 0.96, g = 0.70, b = 0.20 } },
    currency = { label = "Currency", color = { r = 0.28, g = 0.78, b = 0.84 } },
    custom = { label = "Pinned Items", color = { r = 0.96, g = 0.40, b = 0.20 } },
}

local function GetSettings()
    if type(WaffleHouseDB) ~= "table" then
        WaffleHouseDB = type(EllesmereUI_WaffleHouseDB) == "table" and EllesmereUI_WaffleHouseDB
            or (type(EllesmereUI_QoLDB) == "table" and EllesmereUI_QoLDB
            or (type(EllesmereUIVendorExtrasDB) == "table" and EllesmereUIVendorExtrasDB or {})
            )
    end
    if WaffleHouseDB.legendMode ~= "text" then
        WaffleHouseDB.legendMode = "icon"
    end
    if WaffleHouseDB.legendAlternatingRows == nil then
        WaffleHouseDB.legendAlternatingRows = true
    end
    if WaffleHouseDB.legendFilterItems == nil then
        WaffleHouseDB.legendFilterItems = false
    end
    if WaffleHouseDB.legendAffordableOnly == nil then
        WaffleHouseDB.legendAffordableOnly = false
    end
    if WaffleHouseDB.legendSavedOnly == nil then
        WaffleHouseDB.legendSavedOnly = false
    end
    if WaffleHouseDB.currencyLegendVisible == nil then
        WaffleHouseDB.currencyLegendVisible = true
    end
    if WaffleHouseDB.vendorTooltipDetails == nil then
        WaffleHouseDB.vendorTooltipDetails = true
    end
    if WaffleHouseDB.vendorItemView ~= "list" then
        WaffleHouseDB.vendorItemView = "grid"
    end
    if WaffleHouseDB.vendorListAlternatingRows == nil then
        WaffleHouseDB.vendorListAlternatingRows = true
    end
    if WaffleHouseDB.vendorListShowRarity == nil then
        WaffleHouseDB.vendorListShowRarity = true
    end
    -- Preserve the old single-toggle choice on upgrade.  After migration the
    -- two combat phases are independent; the legacy value is never read again.
    if WaffleHouseDB.ignoreInteractVendorsOutOfCombat == nil then
        WaffleHouseDB.ignoreInteractVendorsOutOfCombat = WaffleHouseDB.ignoreInteractVendors == true
    end
    if WaffleHouseDB.ignoreInteractVendorsInCombat == nil then
        WaffleHouseDB.ignoreInteractVendorsInCombat = WaffleHouseDB.ignoreInteractVendors == true
    end
    if type(WaffleHouseDB.ignoredInteractVendorNPCs) ~= "table" then
        -- Ethereal Soul-Trader is the most common companion vendor players
        -- want their soft-interact key to pass over.  The feature is opt-in.
        WaffleHouseDB.ignoredInteractVendorNPCs = { [27914] = true }
    end
    if WaffleHouseDB.keepSoulTraderSummoned == nil then
        WaffleHouseDB.keepSoulTraderSummoned = false
    end
    if WaffleHouseDB.autoEquipBestDelveCurios == nil then
        WaffleHouseDB.autoEquipBestDelveCurios = false
    end
    if WaffleHouseDB.showDelveCurioHelper == nil then
        WaffleHouseDB.showDelveCurioHelper = true
    end
    if WaffleHouseDB.muteValeeraVoiceLines == nil then
        WaffleHouseDB.muteValeeraVoiceLines = false
    end
    if WaffleHouseDB.wonderbarReorderMode == nil then
        WaffleHouseDB.wonderbarReorderMode = false
    end
    if WaffleHouseDB.bagSlotFreezeEnabled == nil then
        WaffleHouseDB.bagSlotFreezeEnabled = true
    end
    if WaffleHouseDB.bagAssistantEnabled == nil then
        WaffleHouseDB.bagAssistantEnabled = true
    end
    if WaffleHouseDB.bagSlotFreezeModifier ~= "shift" and WaffleHouseDB.bagSlotFreezeModifier ~= "alt"
        and WaffleHouseDB.bagSlotFreezeModifier ~= "disabled" then
        WaffleHouseDB.bagSlotFreezeModifier = "ctrl"
    end
    if not BAG_FREEZE_MARKER_POSITIONS[WaffleHouseDB.bagSlotFreezeMarkerPosition] then
        WaffleHouseDB.bagSlotFreezeMarkerPosition = "TOPRIGHT"
    end
    if type(WaffleHouseDB.bagSlotFreezeMarkerX) ~= "number" then WaffleHouseDB.bagSlotFreezeMarkerX = 0 end
    if type(WaffleHouseDB.bagSlotFreezeMarkerY) ~= "number" then WaffleHouseDB.bagSlotFreezeMarkerY = 0 end
    if type(WaffleHouseDB.bagSlotFreezeMarkerSize) ~= "number"
        or WaffleHouseDB.bagSlotFreezeMarkerSize < 10 or WaffleHouseDB.bagSlotFreezeMarkerSize > 22 then
        WaffleHouseDB.bagSlotFreezeMarkerSize = 11
    end
    -- Version 1 introduced the marker at 15px, and Version 2 used 13px.
    -- Migrate only either exact former default; later choices are left alone.
    local markerDefaultVersion = tonumber(WaffleHouseDB.bagSlotFreezeMarkerDefaultVersion) or 1
    if markerDefaultVersion < 2 and WaffleHouseDB.bagSlotFreezeMarkerSize == 15 then
        WaffleHouseDB.bagSlotFreezeMarkerSize = 13
    end
    if markerDefaultVersion < 3 then
        if WaffleHouseDB.bagSlotFreezeMarkerSize == 13 then
            WaffleHouseDB.bagSlotFreezeMarkerSize = 11
        end
        WaffleHouseDB.bagSlotFreezeMarkerDefaultVersion = 3
    end
    if type(WaffleHouseDB.bagFrozenSlots) ~= "table" then WaffleHouseDB.bagFrozenSlots = {} end
    return WaffleHouseDB
end

-- Feature modules share this narrow settings accessor instead of reaching for
-- the SavedVariables directly.  It keeps migrations and reset behavior owned
-- by the main addon.
addon.GetSettings = GetSettings

-- Vendor tracking is loaded as a separate Waffle House module.  Give it a
-- small, read-only view of this setting so it can leave the alternate list
-- layout alone without reaching into EllesmereUIVendorBag.
addon.IsVendorListView = function()
    return GetSettings().vendorItemView == "list"
end

local function GetNPCIDFromGUID(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    -- Summoned service companions use Pet GUIDs, whose sixth component is the
    -- same stable creature ID used by Creature and Vehicle GUIDs.
    if unitType ~= "Creature" and unitType ~= "Vehicle" and unitType ~= "Pet" then return nil end
    npcID = tonumber(npcID)
    return type(npcID) == "number" and npcID > 0 and npcID or nil
end

local function GetSoftInteractVendorNPCID()
    if not UnitGUID then return nil end
    return GetNPCIDFromGUID(UnitGUID("softinteract"))
end

function addon.GetInteractVendorNPCID(unit)
    if InCombatLockdown and InCombatLockdown() then return nil end
    if not UnitGUID then return nil end
    return GetNPCIDFromGUID(UnitGUID(unit or "softinteract"))
end

addon.IsIgnoredInteractVendor = function(unit)
    local settings = GetSettings()
    if not UnitGUID then return false end
    local npcID = GetNPCIDFromGUID(UnitGUID(unit or "npc"))
    return npcID ~= nil and settings.ignoredInteractVendorNPCs[npcID] == true
end

-- The secure binding state driver handles a known soft target across combat
-- transitions.  If the target changes while combat locks binding updates,
-- dismiss an ignored vendor's gossip on the same event that opens it.
addon.CloseIgnoredVendorGossip = function()
    if not (InCombatLockdown and InCombatLockdown()) then return false end
    if GetSettings().ignoreInteractVendorsInCombat ~= true then return false end
    if not (addon.IsIgnoredInteractVendor("npc") or addon.IsIgnoredInteractVendor("softinteract")) then return false end
    local closed = false
    if C_GossipInfo and C_GossipInfo.CloseGossip then
        -- A protected/UI compatibility edge must not leave the dialog open;
        -- use the visible-frame fallback if Blizzard declines this close call.
        closed = pcall(C_GossipInfo.CloseGossip)
    end
    if not closed and GossipFrame and GossipFrame.Hide then
        GossipFrame:Hide()
    end
    return true
end

local function EnsureIgnoredInteractBindingFrames()
    if ignoredInteractBindingOwner then return end
    ignoredInteractBindingOwner = CreateFrame("Frame", "WaffleHouseIgnoredInteractBindingOwner", UIParent, "SecureHandlerStateTemplate")
    ignoredInteractBlocker = CreateFrame("Button", "WaffleHouseIgnoredInteractBlocker", UIParent, "SecureActionButtonTemplate")
    ignoredInteractBlocker:SetSize(1, 1)
    ignoredInteractBlocker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    ignoredInteractBlocker:SetAlpha(0)
    ignoredInteractBlocker:RegisterForClicks("AnyDown", "AnyUp")
    -- The click intentionally has no action.  A temporary override to this
    -- button consumes only the Interact With Target press for an ignored NPC.
    ignoredInteractBindingOwner:SetAttribute("_onstate-combat", [[
        self:ClearBindings()
        local enabled = (newstate == "combat" and self:GetAttribute("waffleIgnoreInCombat"))
            or (newstate == "peace" and self:GetAttribute("waffleIgnoreOutOfCombat"))
        if enabled then
            local key1 = self:GetAttribute("waffleInteractKey1")
            local key2 = self:GetAttribute("waffleInteractKey2")
            if key1 and key1 ~= "" then
                self:SetBindingClick(false, key1, "WaffleHouseIgnoredInteractBlocker", "LeftButton")
            end
            if key2 and key2 ~= "" and key2 ~= key1 then
                self:SetBindingClick(false, key2, "WaffleHouseIgnoredInteractBlocker", "LeftButton")
            end
        end
    ]])
    RegisterStateDriver(ignoredInteractBindingOwner, "combat", "[combat] combat; peace")
end

UpdateIgnoredInteractBinding = function()
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    EnsureIgnoredInteractBindingFrames()
    if ClearOverrideBindings then
        ClearOverrideBindings(ignoredInteractBindingOwner)
    end

    local settings = GetSettings()
    local npcID = GetSoftInteractVendorNPCID()
    local ignored = npcID and settings.ignoredInteractVendorNPCs[npcID] == true
    local key1, key2
    if ignored and GetBindingKey then
        key1, key2 = GetBindingKey("INTERACTTARGET")
    end
    ignoredInteractBindingOwner:SetAttribute("waffleIgnoreOutOfCombat", ignored and settings.ignoreInteractVendorsOutOfCombat == true)
    ignoredInteractBindingOwner:SetAttribute("waffleIgnoreInCombat", ignored and settings.ignoreInteractVendorsInCombat == true)
    ignoredInteractBindingOwner:SetAttribute("waffleInteractKey1", type(key1) == "string" and key1 or nil)
    ignoredInteractBindingOwner:SetAttribute("waffleInteractKey2", type(key2) == "string" and key2 or nil)
    if not (ignored and settings.ignoreInteractVendorsOutOfCombat == true and SetOverrideBindingClick) then return end

    for _, key in pairs({ key1, key2 }) do
        if type(key) == "string" and key ~= "" then
            SetOverrideBindingClick(ignoredInteractBindingOwner, false, key,
                "WaffleHouseIgnoredInteractBlocker", "LeftButton")
        end
    end
end

addon.RefreshIgnoredInteractBinding = UpdateIgnoredInteractBinding

local function IsSoulTraderCurrentlySummoned()
    if not (C_PetJournal and C_PetJournal.GetSummonedPetGUID) then return false end
    local summonedPetGUID = C_PetJournal.GetSummonedPetGUID()
    if type(summonedPetGUID) ~= "string" then return false end
    if C_PetJournal.GetPetInfoByPetID then
        local speciesID = C_PetJournal.GetPetInfoByPetID(summonedPetGUID)
        return speciesID == SOUL_TRADER_SPECIES_ID
    end
    return false
end

local function GetSoulTraderPetGUID()
    if not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then return nil end
    local collected = C_PetJournal.GetNumCollectedInfo(SOUL_TRADER_SPECIES_ID)
    if type(collected) ~= "number" or collected <= 0 then return nil end

    -- Use the localized species name supplied by the journal so a custom pet
    -- name or non-English client never changes which companion is selected.
    if C_PetJournal.GetPetInfoBySpeciesID and C_PetJournal.FindPetIDByName then
        local speciesName = C_PetJournal.GetPetInfoBySpeciesID(SOUL_TRADER_SPECIES_ID)
        if type(speciesName) == "string" then
            local speciesID, petGUID = C_PetJournal.FindPetIDByName(speciesName)
            if speciesID == SOUL_TRADER_SPECIES_ID and type(petGUID) == "string" then
                return petGUID
            end
        end
    end

    -- The name lookup is normally sufficient.  This fallback helps clients
    -- whose journal cache has not populated that lookup yet.
    if C_PetJournal.GetNumPets and C_PetJournal.GetPetInfoByIndex then
        local total = C_PetJournal.GetNumPets()
        for index = 1, type(total) == "number" and total or 0 do
            local petGUID, speciesID, owned = C_PetJournal.GetPetInfoByIndex(index)
            if speciesID == SOUL_TRADER_SPECIES_ID and owned and type(petGUID) == "string" then
                return petGUID
            end
        end
    end
end

local function CanSummonSoulTraderHere()
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return false end
    if IsInInstance then
        local _, instanceType = IsInInstance()
        if instanceType == "arena" or instanceType == "pvp" then return false end
    end
    return true
end

UpdateSoulTraderCompanion = function()
    if GetSettings().keepSoulTraderSummoned ~= true then return end
    if not CanSummonSoulTraderHere() or IsSoulTraderCurrentlySummoned() then return end
    if not (C_PetJournal and C_PetJournal.SummonPetByGUID) then return end

    local petGUID = GetSoulTraderPetGUID()
    if not petGUID then return end
    local now = GetTime and GetTime() or 0
    if soulTraderLastSummonAttempt and now - soulTraderLastSummonAttempt < 1.5 then return end
    soulTraderLastSummonAttempt = now
    C_PetJournal.SummonPetByGUID(petGUID)
end

-------------------------------------------------------------------------------
-- Wonderbar entry reordering
--
-- EllesmereUI DataBars (the current Wonderbar module) owns the entry runtime
-- and its saved order.  Waffle House intentionally does not alter that addon:
-- it layers an invisible, opt-in drag surface over each live entry and commits
-- drops through DataBars' exported MoveBlockTo API.  The surface is state
-- driven out of combat and while Shift is held, so normal Wonderbar controls
-- remain clickable until the player deliberately begins a reorder drag.
-------------------------------------------------------------------------------
local wonderbarReorderHooked
local wonderbarReorderRefreshPending
local wonderbarDragController
local activeWonderbarDrag

local function GetWonderbarNamespace()
    local registry = EllesmereUI and EllesmereUI._ModuleNS
    local ns = type(registry) == "table" and registry.EllesmereUIDataBars
    if type(ns) ~= "table" or type(ns.GetProfile) ~= "function"
        or type(ns.MoveBlockTo) ~= "function" or type(ns.ApplyBar) ~= "function"
        or type(ns._live) ~= "table" then
        return nil
    end
    return ns
end

local function GetWonderbarBlockIndex(blocks, blockId)
    for index, block in ipairs(blocks or {}) do
        if block and block.id == blockId then return index end
    end
end

local function CopyWonderbarBlockOrder(blocks)
    local order = {}
    for index, block in ipairs(blocks or {}) do
        if block and block.id ~= nil then order[index] = block.id end
    end
    return order
end

-- Return DataBars' pre-removal boundary index.  Its horizontal layout runs
-- left-to-right; vertical bars run top-to-bottom, hence the inverted Y test.
-- Using the actual live slot centers keeps the drop target correct for auto,
-- even, fill, and centered bar layouts alike.
local function GetWonderbarDropBoundary(barCfg, rec, cursorX, cursorY)
    if not (barCfg and rec and type(rec.slots) == "table") then return nil end
    local vertical = barCfg.orientation == "V"
    local cursor = vertical and cursorY or cursorX
    if type(cursor) ~= "number" then return nil end

    local boundary = 1
    for index, block in ipairs(barCfg.blocks or {}) do
        local slot = rec.slots[block.id]
        local centerX, centerY
        if slot and slot.GetCenter then
            centerX, centerY = slot:GetCenter()
        end
        local center = vertical and centerY or centerX
        if type(center) == "number" then
            if (not vertical and cursor < center) or (vertical and cursor > center) then
                return index
            end
            boundary = index + 1
        end
    end
    return boundary
end

local function RestoreWonderbarBlockOrder(ns, barId, desiredOrder)
    local barCfg = ns and ns.GetBar and ns.GetBar(barId)
    if not (barCfg and type(desiredOrder) == "table") then return end
    -- Place each desired block from left to right.  All earlier positions are
    -- already fixed, so the public pre-removal boundary index is also the
    -- final index we want.  This avoids direct writes into DataBars' profile.
    for desiredIndex, blockId in ipairs(desiredOrder) do
        local currentIndex = GetWonderbarBlockIndex(barCfg.blocks, blockId)
        if currentIndex and currentIndex ~= desiredIndex then
            ns.MoveBlockTo(barId, blockId, desiredIndex)
        end
    end
end

local function EndWonderbarDrag(commit)
    local drag = activeWonderbarDrag
    if not drag then return end

    if not commit then
        RestoreWonderbarBlockOrder(drag.ns, drag.barId, drag.originalOrder)
    end
    if drag.slot and drag.slot.SetAlpha then drag.slot:SetAlpha(1) end
    activeWonderbarDrag = nil
    if wonderbarDragController then wonderbarDragController:SetScript("OnUpdate", nil) end
end

local function UpdateWonderbarDrag()
    local drag = activeWonderbarDrag
    if not drag then return end
    if not (GetSettings().wonderbarReorderMode == true)
        or (InCombatLockdown and InCombatLockdown()) then
        EndWonderbarDrag(false)
        return
    end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then
        EndWonderbarDrag(false)
        return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        EndWonderbarDrag(true)
        return
    end

    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local barCfg = drag.ns.GetBar and drag.ns.GetBar(drag.barId)
    local rec = drag.ns._live and drag.ns._live[drag.barId]
    local boundary = GetWonderbarDropBoundary(barCfg, rec, cursorX, cursorY)
    if not boundary or boundary == drag.lastBoundary then return end
    drag.lastBoundary = boundary

    local currentIndex = barCfg and GetWonderbarBlockIndex(barCfg.blocks, drag.blockId)
    if not currentIndex then return end
    -- MoveBlockTo consumes a boundary before removal.  A forward move needs
    -- the boundary after its intended final slot; a backwards move does not.
    local targetIndex = boundary
    if targetIndex > currentIndex then targetIndex = targetIndex - 1 end
    if targetIndex == currentIndex then return end

    drag.ns.MoveBlockTo(drag.barId, drag.blockId, boundary)
    drag.changed = true
end

local function BeginWonderbarDrag(overlay)
    if activeWonderbarDrag or not (overlay and overlay._waffleWonderbarNS) then return end
    if GetSettings().wonderbarReorderMode ~= true
        or (InCombatLockdown and InCombatLockdown()) then return end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return end

    local ns, barId, blockId = overlay._waffleWonderbarNS, overlay._waffleWonderbarBarId, overlay._waffleWonderbarBlockId
    local barCfg = ns.GetBar and ns.GetBar(barId)
    local rec = ns._live and ns._live[barId]
    local slot = rec and rec.slots and rec.slots[blockId]
    if not (barCfg and rec and slot and GetWonderbarBlockIndex(barCfg.blocks, blockId)) then return end

    activeWonderbarDrag = {
        ns = ns,
        barId = barId,
        blockId = blockId,
        slot = slot,
        originalOrder = CopyWonderbarBlockOrder(barCfg.blocks),
    }
    slot:SetAlpha(0.45)
    if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    if not wonderbarDragController then
        wonderbarDragController = CreateFrame("Frame")
    end
    wonderbarDragController:SetScript("OnUpdate", UpdateWonderbarDrag)
    UpdateWonderbarDrag()
end

local function SetWonderbarOverlayState(overlay, enabled)
    if not overlay or (InCombatLockdown and InCombatLockdown()) then return end
    if enabled then
        overlay:EnableMouse(true)
        if RegisterStateDriver and not overlay._waffleWonderbarStateDriver then
            local ok = pcall(RegisterStateDriver, overlay, "visibility", "[combat] hide; [mod:shift] show; hide")
            overlay._waffleWonderbarStateDriver = ok and true or nil
        end
        overlay:Show()
    else
        if overlay._waffleWonderbarStateDriver and UnregisterStateDriver then
            UnregisterStateDriver(overlay, "visibility")
            overlay._waffleWonderbarStateDriver = nil
        end
        overlay:EnableMouse(false)
        overlay:Hide()
    end
end

local function EnsureWonderbarReorderOverlay(ns, barCfg, rec, block)
    local slot = rec.slots and rec.slots[block.id]
    if not slot then return end
    local overlay = slot._waffleWonderbarReorderOverlay
    if not overlay then
        overlay = CreateFrame("Button", nil, slot)
        overlay:SetAllPoints(slot)
        overlay:SetFrameLevel((slot:GetFrameLevel() or 0) + 30)
        overlay:RegisterForDrag("LeftButton")
        overlay:EnableMouse(true)
        local hover = overlay:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.08)
        overlay._waffleWonderbarHover = hover
        overlay:SetScript("OnEnter", function(self)
            if activeWonderbarDrag then return end
            if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
            if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, "Hold Shift and drag this Wonderbar entry to a new position.")
            end
        end)
        overlay:SetScript("OnLeave", function()
            if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        overlay:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then EndWonderbarDrag(true) end
        end)
        overlay:SetScript("OnDragStart", BeginWonderbarDrag)
        overlay:SetScript("OnDragStop", function() EndWonderbarDrag(true) end)
        slot._waffleWonderbarReorderOverlay = overlay
    end
    overlay._waffleWonderbarNS = ns
    overlay._waffleWonderbarBarId = barCfg.id
    overlay._waffleWonderbarBlockId = block.id
    SetWonderbarOverlayState(overlay, true)
end

RefreshWonderbarReorderMode = function()
    if InCombatLockdown and InCombatLockdown() then return false end
    local ns = GetWonderbarNamespace()
    if not ns then return false end

    local enabled = GetSettings().wonderbarReorderMode == true
    if not enabled then EndWonderbarDrag(false) end
    local profile = ns.GetProfile()
    for _, barCfg in ipairs(profile and profile.bars or {}) do
        local rec = ns._live[barCfg.id]
        if rec and rec.slots then
            local wanted = {}
            for _, block in ipairs(barCfg.blocks or {}) do
                wanted[block.id] = true
                if enabled then
                    EnsureWonderbarReorderOverlay(ns, barCfg, rec, block)
                end
            end
            for blockId, slot in pairs(rec.slots) do
                local overlay = slot and slot._waffleWonderbarReorderOverlay
                if overlay and (not enabled or not wanted[blockId]) then
                    SetWonderbarOverlayState(overlay, false)
                end
            end
        end
    end
    return true
end

local function QueueWonderbarReorderRefresh()
    if wonderbarReorderRefreshPending then return end
    wonderbarReorderRefreshPending = true
    C_Timer.After(0, function()
        wonderbarReorderRefreshPending = nil
        if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
    end)
end

InstallWonderbarReorderHooks = function()
    if wonderbarReorderHooked then return true end
    local ns = GetWonderbarNamespace()
    if not (ns and hooksecurefunc) then return false end
    hooksecurefunc(ns, "ApplyBar", QueueWonderbarReorderRefresh)
    wonderbarReorderHooked = true
    QueueWonderbarReorderRefresh()
    return true
end

local function IsTextMode()
    return GetSettings().legendMode == "text"
end

-- EllesmereUI owns the confirmation popup's logic.  Waffle House only adds a
-- presentation overlay after it opens, so Disable/Enable module behavior,
-- callbacks, and reload flow stay entirely EllesmereUI-owned.
local confirmPopupPixelBorderHooked
local function ApplyConfirmPopupPixelBorder(target, key, r, g, b, a)
    local pp = EllesmereUI and EllesmereUI.PP
    if not (target and pp and pp.CreateBorder) then return end

    local host = target[key]
    if not host then
        host = CreateFrame("Frame", nil, target)
        host:SetAllPoints(target)
        host:EnableMouse(false)
        target[key] = host
        pp.CreateBorder(host, r, g, b, a, 1, "OVERLAY", 7)
    elseif pp.UpdateBorder then
        pp.UpdateBorder(host, 1, r, g, b, a)
    end
    host:SetFrameLevel(target:GetFrameLevel() + 10)
end

local function SkinConfirmPopupPixelBorders()
    local popup = _G.EUIConfirmPopup
    if not (popup and EllesmereUI and EllesmereUI.PP) then return end

    local accentR, accentG, accentB = ACCENT_R, ACCENT_G, ACCENT_B
    if type(EllesmereUI.GetAccentColor) == "function" then
        local r, g, b = EllesmereUI.GetAccentColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            accentR, accentG, accentB = r, g, b
        end
    end
    ApplyConfirmPopupPixelBorder(popup, "_waffleConfirmPopupPixelBorder", 1, 1, 1, 0.15)
    ApplyConfirmPopupPixelBorder(popup._cancelBtn, "_waffleConfirmCancelPixelBorder", 1, 1, 1, 0.50)
    ApplyConfirmPopupPixelBorder(popup._confirmBtn, "_waffleConfirmAcceptPixelBorder", accentR, accentG, accentB, 0.90)
end

InstallConfirmPopupPixelBorderHook = function()
    if confirmPopupPixelBorderHooked or not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then return end
    if not hooksecurefunc then return end
    hooksecurefunc(EllesmereUI, "ShowConfirmPopup", SkinConfirmPopupPixelBorders)
    confirmPopupPixelBorderHooked = true
    SkinConfirmPopupPixelBorders()
end

local function GetVendorPlanner()
    local settings = GetSettings()
    if type(settings.vendorPlanner) ~= "table" then settings.vendorPlanner = {} end
    if type(settings.vendorNotes) ~= "table" then settings.vendorNotes = {} end
    return settings.vendorPlanner, settings.vendorNotes
end

local function GetItemQueueSettings()
    local settings = GetSettings()
    if type(settings.itemQueue) ~= "table" then settings.itemQueue = {} end
    local queue = settings.itemQueue
    if queue.enabled == nil then queue.enabled = true end
    if type(queue.categories) ~= "table" then queue.categories = {} end
    if type(queue.order) ~= "table" then queue.order = {} end
    if type(queue.colors) ~= "table" then queue.colors = {} end
    if type(queue.pinnedItems) ~= "table" then queue.pinnedItems = {} end
    if type(queue.bannedItems) ~= "table" then queue.bannedItems = {} end
    if queue.hideCompletedItems == nil then queue.hideCompletedItems = true end
    if queue.hideInCombat == nil then queue.hideInCombat = false end
    if queue.showOwnedHousingDecor == nil then queue.showOwnedHousingDecor = false end

    local seen, normalizedOrder = {}, {}
    for _, key in ipairs(queue.order) do
        if ITEM_QUEUE_TYPES[key] and not seen[key] then
            seen[key] = true
            normalizedOrder[#normalizedOrder + 1] = key
        end
    end
    -- Preserve an established custom order, inserting this new subcategory
    -- beside generic combination items instead of appending it arbitrarily.
    if not seen.darkmoon and seen.combination then
        for index, key in ipairs(normalizedOrder) do
            if key == "combination" then
                table.insert(normalizedOrder, index + 1, "darkmoon")
                seen.darkmoon = true
                break
            end
        end
    end
    -- Keep new currency grants in the utility part of an established custom
    -- order, immediately after boxes/caches, rather than silently appending
    -- them after the user's pinned-item fallback.
    if not seen.currency and seen.containers then
        for index, key in ipairs(normalizedOrder) do
            if key == "containers" then
                table.insert(normalizedOrder, index + 1, "currency")
                seen.currency = true
                break
            end
        end
    end
    for _, key in ipairs(ITEM_QUEUE_ORDER) do
        if not seen[key] then
            normalizedOrder[#normalizedOrder + 1] = key
            seen[key] = true
        end
        if queue.categories[key] == nil then queue.categories[key] = true end
    end
    queue.order = normalizedOrder
    return queue
end

local function IsItemQueueCategoryEnabled(key)
    return GetItemQueueSettings().categories[key] ~= false
end

local function GetItemQueueColor(key)
    local saved = GetItemQueueSettings().colors[key]
    local fallback = ITEM_QUEUE_TYPES[key] and ITEM_QUEUE_TYPES[key].color or { r = 1, g = 1, b = 1 }
    return (saved and saved.r) or fallback.r, (saved and saved.g) or fallback.g,
        (saved and saved.b) or fallback.b, (saved and saved.a) or 1
end

local function InstallSidebarEntry()
    if not (EllesmereUI and type(EllesmereUI.ADDON_GROUPS) == "table"
        and type(EllesmereUI._addonInfoByFolder) == "table") then
        return false
    end

    EllesmereUI._addonInfoByFolder[ADDON_FOLDER] = {
        folder = ADDON_FOLDER,
        display = "Waffle House",
        search_name = "EllesmereUI Waffle House Vendor Bags Frozen Slots",
    }

    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        if group.key == "qol" then
            for _, folder in ipairs(group.members) do
                if folder == ADDON_FOLDER then return true end
            end
            table.insert(group.members, 2, ADDON_FOLDER)
            return true
        end
    end

    return false
end

local function BuildOptionsConfig()
    return {
        title = "Waffle House",
        description = "|cff7f7f7fEnhancing your |r|cff18d19eEllesmereUI|r|cff7f7f7f with |r|cff6fe4cbQuality of Life|r|cff7f7f7f Goodness...|r",
        searchTerms = "vendor bag merchant currency cost legend shopping list easy access item view list rows frozen slot freeze modifier lock sort main bags frosted marker interact key ignored vendor npc ethereal soul trader tool rack chooser choice celestial carver energy splinter arcanic precision empyrean zapper primary stat haste mastery critical strike companion pet summon wonderbar databar data bar drag reorder entries item queue zygor automation auto skip quest gossip dialogue campaign cinematic repair sell junk modifier reverse mode buff check raid party missing assignment beacon earth shield fortitude intellect skyfury bronze buff frame anchor collapse expand own cast timer rules adventure ritual ritual sites delve delves dungeon dungeons raid raids trusty delve companion valeera sanguinar curio curios combat utility bilespear dreamcatcher mute voice dialogue sound",
        pages = { "General", "Adventure", "Automation", "Bags", "Item Queue", "Vendor" },
        buildPage = function(pageName, parent, yOffset)
            if pageName == "Adventure" then
                return addon.BuildAdventurePage and addon.BuildAdventurePage(parent, yOffset) or yOffset
            end
            if pageName == "Item Queue" then
                return BuildItemQueuePage(pageName, parent, yOffset)
            end
            if pageName == "Automation" then
                if addon.BuildAutomationPage then
                    return addon.BuildAutomationPage(parent, yOffset)
                end
                return yOffset
            end
            if pageName == "Bags" then
                if addon.BuildBagsPage then
                    return addon.BuildBagsPage(parent, yOffset)
                end
                return yOffset
            end
            if pageName ~= "General" and pageName ~= "Vendor" then return end

            local W = EllesmereUI.Widgets
            local y = yOffset
            local _, h
            local legendModes = { icon = "Icon Grid", text = "Text Rows" }

            if pageName == "Vendor" then
            _, h = W:SectionHeader(parent, "CURRENCY LEGEND", y); y = y - h
            _, h = W:DualRow(parent, y,
                {
                    type = "dropdown",
                    text = "Legend Display",
                    values = legendModes,
                    order = { "icon", "text" },
                    tooltip = "Icon Grid shows currency tiles with the owned count over each icon; hold Alt over a tile for the full currency tooltip. Text Rows keeps a 34px currency icon at the left of each name and count.",
                    getValue = function()
                        return GetSettings().legendMode
                    end,
                    setValue = function(value)
                        GetSettings().legendMode = value == "text" and "text" or "icon"
                        if addon.Refresh then addon.Refresh() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Alternating Currency Rows",
                    tooltip = "Use subtle transparent alternating backgrounds to make Text Rows easier to scan.",
                    disabled = function()
                        return GetSettings().legendMode ~= "text"
                    end,
                    disabledTooltip = "Alternating backgrounds apply only to Text Rows; Icon Grid uses individual currency tiles.",
                    getValue = function()
                        return GetSettings().legendAlternatingRows ~= false
                    end,
                    setValue = function(value)
                        GetSettings().legendAlternatingRows = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                }
            ); y = y - h

            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Filter Selected Currency",
                    tooltip = "When a currency row is selected at a merchant, hide items that do not use that currency.",
                    getValue = function()
                        return GetSettings().legendFilterItems == true
                    end,
                    setValue = function(value)
                        GetSettings().legendFilterItems = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Only Affordable Items",
                    tooltip = "At a merchant, hide items you cannot currently afford with gold and listed currencies.",
                    getValue = function()
                        return GetSettings().legendAffordableOnly == true
                    end,
                    setValue = function(value)
                        GetSettings().legendAffordableOnly = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                }
            ); y = y - h

            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Only Saved Vendor Items",
                    tooltip = "At a merchant, show only items saved to the Waffle House shopping list. Use the pin beside a vendor item to save it.",
                    getValue = function()
                        return GetSettings().legendSavedOnly == true
                    end,
                    setValue = function(value)
                        GetSettings().legendSavedOnly = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Vendor Tooltip Details",
                    tooltip = "Show owned-item counts, appearance collection state, and saved vendor notes on vendor-item tooltips.",
                    getValue = function()
                        return GetSettings().vendorTooltipDetails ~= false
                    end,
                    setValue = function(value)
                        GetSettings().vendorTooltipDetails = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                }
            ); y = y - h

            _, h = W:SectionHeader(parent, "ITEM VIEW", y); y = y - h
            _, h = W:DualRow(parent, y,
                {
                    type = "dropdown",
                    text = "Vendor Item View",
                    values = { grid = "Grid", list = "List" },
                    order = { "grid", "list" },
                    tooltip = "Grid keeps EllesmereUI Vendor Bags' normal icon layout. List adds icon, shopping-list pin, item name, type, optional rarity, and text-cost columns. Click Cost to sort by displayed amount across the whole list, or Rarity to group by quality. Hold a header for 0.25 seconds to move it.",
                    getValue = function()
                        return GetSettings().vendorItemView
                    end,
                    setValue = function(value)
                        GetSettings().vendorItemView = value == "list" and "list" or "grid"
                        if addon.Refresh then addon.Refresh() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Alternating Item Rows",
                    tooltip = "Add subtle alternating backgrounds behind Easy Access list rows, matching the currency legend's scan-friendly treatment.",
                    getValue = function()
                        return GetSettings().vendorListAlternatingRows ~= false
                    end,
                    setValue = function(value)
                        GetSettings().vendorListAlternatingRows = value and true or false
                        if addon.Refresh then addon.Refresh() end
                    end,
                }
            ); y = y - h

            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Show Rarity Column",
                    tooltip = "Show a clickable Rarity column in the vendor list when the window is wide enough. Select it to sort by item quality; selecting Cost instead sorts by cost without rarity taking precedence.",
                    getValue = function()
                        return GetSettings().vendorListShowRarity ~= false
                    end,
                    setValue = function(value)
                        local settings = GetSettings()
                        settings.vendorListShowRarity = value and true or false
                        if not value and settings.vendorListSortColumn == "rarity" then
                            settings.vendorListSortColumn = nil
                        end
                        if addon.Refresh then addon.Refresh() end
                    end,
                }
            ); y = y - h

            _, h = W:SectionHeader(parent, "INTERACT KEY", y); y = y - h
            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Ignore In Combat",
                    tooltip = "Block Interact With Target for saved vendor NPCs during combat. If a new soft target appears after combat has started, close that vendor's dialogue as it opens.",
                    disabled = function() return InCombatLockdown and InCombatLockdown() end,
                    disabledTooltip = "Interact Key overrides can only be changed outside combat.",
                    getValue = function()
                        return GetSettings().ignoreInteractVendorsInCombat == true
                    end,
                    setValue = function(value)
                        GetSettings().ignoreInteractVendorsInCombat = value and true or false
                        if UpdateIgnoredInteractBinding then UpdateIgnoredInteractBinding() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Ignore Out of Combat",
                    tooltip = "Block Interact With Target while a saved vendor NPC is your soft-interact target outside combat. Clicking the NPC directly still works.",
                    disabled = function() return InCombatLockdown and InCombatLockdown() end,
                    disabledTooltip = "Interact Key overrides can only be changed outside combat.",
                    getValue = function()
                        return GetSettings().ignoreInteractVendorsOutOfCombat == true
                    end,
                    setValue = function(value)
                        GetSettings().ignoreInteractVendorsOutOfCombat = value and true or false
                        if UpdateIgnoredInteractBinding then UpdateIgnoredInteractBinding() end
                    end,
                }
            ); y = y - h

            if addon.BuildIgnoredVendorOptions then y = addon.BuildIgnoredVendorOptions(parent, y) end
            end

            if pageName == "General" then
            -- The General page only has a few integrations. Keep related
            -- controls on one native two-column row instead of making every
            -- option a tiny one-item section with a floating context label.
            -- SectionHeader already owns the normal EUI label, divider, and
            -- breathing room above its attached row.
            _, h = W:SectionHeader(parent, "DATABARS & COMPANIONS", y); y = y - h
            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Reorder Wonderbar Entries",
                    tooltip = "Enable a temporary out-of-combat reorder mode. Drag any Wonderbar entry itself to a new position; its normal click action is paused only while this mode is enabled. Waffle House uses EllesmereUI DataBars' own saved-order API and does not modify its files.",
                    disabled = function() return InCombatLockdown and InCombatLockdown() end,
                    disabledTooltip = "Wonderbar reordering is available only outside combat.",
                    getValue = function()
                        return GetSettings().wonderbarReorderMode == true
                    end,
                    setValue = function(value)
                        GetSettings().wonderbarReorderMode = value and true or false
                        if InstallWonderbarReorderHooks then InstallWonderbarReorderHooks() end
                        if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
                    end,
                },
                {
                    type = "toggle",
                    text = "Keep Soul-Trader Summoned",
                    tooltip = "When you are safely outside combat, keep Ethereal Soul-Trader as your active companion pet if you own it. This replaces another summoned companion, or summons Soul-Trader when none is active. It pauses during pet battles, Arenas, and Battlegrounds, then checks again when safe.",
                    getValue = function()
                        return GetSettings().keepSoulTraderSummoned == true
                    end,
                    setValue = function(value)
                        GetSettings().keepSoulTraderSummoned = value and true or false
                        if value and UpdateSoulTraderCompanion then UpdateSoulTraderCompanion() end
                    end,
                }
            ); y = y - h

            _, h = W:SectionHeader(parent, "SKINNING", y); y = y - h
            _, h = W:DualRow(parent, y,
                {
                    type = "toggle",
                    text = "Skin Zygor Guide Pointer",
                    tooltip = "Give Zygor's clickable guide-step icon the EllesmereUI button treatment. This only changes the icon's presentation, not Zygor's click or waypoint behavior. Turning it off requires a reload to remove an already-applied skin.",
                    getValue = function()
                        return GetSettings().skinZygorGuidePointer ~= false
                    end,
                    setValue = function(value)
                        GetSettings().skinZygorGuidePointer = value and nil or false
                        if value and QueueZygorPointerSkin then QueueZygorPointerSkin() end
                    end,
                }
            ); y = y - h
            if addon.BuildBuffFrameOptions then y = addon.BuildBuffFrameOptions(parent, y) end
            end

            if pageName == "Vendor" then
            _, h = W:SectionHeader(parent, "SHOPPING LIST & NOTES", y); y = y - h
            local plannerRow
            plannerRow, h = W:DualRow(parent, y,
                {
                    type = "labeledButton",
                    text = "Saved Vendor Items",
                    buttonText = "Open List",
                    tooltip = "Review saved vendor items and combined costs. Use the pin beside a vendor item to save it; right-click the pin to edit its note.",
                }
            ); y = y - h
            local plannerButton = plannerRow and plannerRow._leftRegion and plannerRow._leftRegion._control
            if plannerButton then
                plannerButton:SetScript("OnClick", function(self) ShowVendorPlan(self) end)
            end
            end

            return math.abs(y)
        end,
        onReset = function()
            WaffleHouseDB = {}
            if addon.Refresh then addon.Refresh() end
            if addon.RefreshBuffCheck then addon.RefreshBuffCheck() end
            if addon.RefreshBuffFrameControls then addon.RefreshBuffFrameControls() end
            if addon.RefreshAdventureFeatures then addon.RefreshAdventureFeatures() end
        end,
    }
end

local function RegisterOptionsPage()
    if optionsRegistered then return true end
    if not InstallSidebarEntry() then return false end
    if not (EllesmereUI and EllesmereUI.RegisterModule and EllesmereUI.Widgets) then return false end

    _G.WaffleHouse_PendingOptionsConfig = BuildOptionsConfig()
    local bridge = loadstring(
        "local c = _G.WaffleHouse_PendingOptionsConfig; "
        .. "if c and EllesmereUI then EllesmereUI:RegisterModule(" .. string.format("%q", ADDON_FOLDER) .. ", c) end",
        "@Interface/AddOns/EllesmereUI/EllesmereUI_WaffleHouseBridge.lua"
    )
    if not bridge then
        _G.WaffleHouse_PendingOptionsConfig = nil
        return false
    end

    local ok = pcall(bridge)
    _G.WaffleHouse_PendingOptionsConfig = nil
    if not ok then return false end

    optionsRegistered = true
    if optionsRegistrationTicker then
        optionsRegistrationTicker:Cancel()
        optionsRegistrationTicker = nil
    end
    return true
end

local function StartOptionsRegistration()
    InstallSidebarEntry()
    C_Timer.After(0, RegisterOptionsPage)
    C_Timer.After(0.5, RegisterOptionsPage)
    if not optionsRegistrationTicker then
        optionsRegistrationTicker = C_Timer.NewTicker(0.5, RegisterOptionsPage)
    end
end

local function BuildItemQueuePriorityList(parent, yOffset, onOrderChanged, onAutoSortReady)
    -- One continuous priority list: down the left column, then down the right.
    local ROW_H, ROW_GAP, COLUMNS, COLUMN_GAP = 32, 4, 2, 12
    local order = GetItemQueueSettings().order
    local gridRows = math.ceil(#order / COLUMNS)
    local listHeight = gridRows * ROW_H
    local padding = EllesmereUI.CONTENT_PAD or 45
    local fontPath = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or STANDARD_TEXT_FONT
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(parent:GetWidth() - padding * 2, listHeight)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", padding, yOffset)
    holder._labelText = "Item Use Order Priority Drag Reorder"

    local rows, dragging, originalIndex = {}, nil, nil
    local ghost, grabX, grabY

    local function GetRowIndex(row)
        for index, candidate in ipairs(rows) do
            if candidate == row then return index end
        end
    end

    local function GetScaledCursor()
        local cursorX, cursorY = GetCursorPosition()
        local scale = holder:GetEffectiveScale()
        return cursorX / scale, cursorY / scale
    end

    local function CreateGhost()
        -- Inherit the options panel's scale and scroll clipping.
        local frame = CreateFrame("Frame", nil, holder)
        frame:SetSize(1, ROW_H - ROW_GAP)
        frame:SetFrameLevel(holder:GetFrameLevel() + 10)
        frame:EnableMouse(false)
        frame:Hide()

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.025, 0.035, 0.045, 0.94)
        local top = frame:CreateTexture(nil, "ARTWORK")
        top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
        top:SetColorTexture(1, 1, 1, 0.42)
        local bottom = frame:CreateTexture(nil, "ARTWORK")
        bottom:SetHeight(1); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetColorTexture(1, 1, 1, 0.42)

        local grip = frame:CreateFontString(nil, "OVERLAY")
        grip:SetFont(fontPath, 12, "")
        grip:SetPoint("LEFT", frame, "LEFT", 9, 0)
        grip:SetText("=")
        grip:SetTextColor(1, 1, 1, 0.50)
        local rank = frame:CreateFontString(nil, "OVERLAY")
        rank:SetFont(fontPath, 12, "")
        rank:SetPoint("LEFT", grip, "RIGHT", 9, 0)
        rank:SetWidth(24)
        rank:SetJustifyH("RIGHT")
        rank:SetTextColor(0.78, 0.78, 0.78, 1)
        local swatch = frame:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(8, 8)
        swatch:SetPoint("LEFT", rank, "RIGHT", 10, 0)
        local label = frame:CreateFontString(nil, "OVERLAY")
        label:SetFont(fontPath, 14, "")
        label:SetPoint("LEFT", swatch, "RIGHT", 9, 0)
        label:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(1, 1, 1, 1)

        frame._rank, frame._swatch, frame._label = rank, swatch, label
        return frame
    end

    local function PositionGhost()
        if not ghost then return end
        local cursorX, cursorY = GetScaledCursor()
        local left, top = holder:GetLeft(), holder:GetTop()
        if not left or not top then return end
        local x = cursorX - left - grabX
        local y = cursorY - top + grabY
        x = math.max(0, math.min(x, holder:GetWidth() - ghost:GetWidth()))
        y = math.max(ghost:GetHeight() - holder:GetHeight(), math.min(y, 0))
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
    end

    local function GetDropIndex()
        local cursorX, cursorY = GetScaledCursor()
        local left, top = holder:GetLeft(), holder:GetTop()
        if not left or not top then return GetRowIndex(dragging) end

        local column = cursorX >= left + holder:GetWidth() / COLUMNS and 1 or 0
        local gridRow = math.floor((top - cursorY) / ROW_H)
        gridRow = math.max(0, math.min(gridRows - 1, gridRow))
        -- The hovered slot is the final rank in either direction.  A forward
        -- move must not subtract one and silently land back at the source.
        return math.min(#rows, column * gridRows + gridRow + 1)
    end

    local function SaveOrder()
        local savedOrder = {}
        for index, row in ipairs(rows) do
            savedOrder[index] = row._queueKey
        end
        GetItemQueueSettings().order = savedOrder
        if onOrderChanged then onOrderChanged(savedOrder) end
        if RefreshItemQueue then RefreshItemQueue() end
    end

    local function LayoutRows()
        local columnWidth = (holder:GetWidth() - COLUMN_GAP) / COLUMNS
        for index, row in ipairs(rows) do
            local gridIndex = index - 1
            local column = math.floor(gridIndex / gridRows)
            local gridRow = gridIndex % gridRows
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", column * (columnWidth + COLUMN_GAP), -(gridRow * ROW_H))
            row:SetSize(columnWidth, ROW_H - ROW_GAP)
            row._baseBg:SetColorTexture(0, 0, 0, gridRow % 2 == 0 and 0.10 or 0.20)
            row._rank:SetText(index .. ".")
        end
    end

    local function ApplyOrder(order)
        local byKey, sorted = {}, {}
        for _, row in ipairs(rows) do byKey[row._queueKey] = row end
        for _, key in ipairs(order) do
            local row = byKey[key]
            if row then
                sorted[#sorted + 1] = row
                byKey[key] = nil
            end
        end
        -- Keep any unexpected future category visible instead of losing it
        -- when a recommended order from an older client is applied.
        for _, row in ipairs(rows) do
            if byKey[row._queueKey] then sorted[#sorted + 1] = row end
        end
        rows = sorted
        LayoutRows()
    end

    local function PreviewOrder()
        local sourceIndex, targetIndex = GetRowIndex(dragging), GetDropIndex()
        if sourceIndex and targetIndex and sourceIndex ~= targetIndex then
            table.remove(rows, sourceIndex)
            table.insert(rows, targetIndex, dragging)
            LayoutRows()
        end
        ghost._rank:SetText(dragging._rank:GetText())
        PositionGhost()
    end

    local function EndDrag(save)
        if not dragging then return end

        local source, sourceIndex = dragging, GetRowIndex(dragging)
        if not save and sourceIndex ~= originalIndex then
            table.remove(rows, sourceIndex)
            table.insert(rows, originalIndex, source)
        end
        local changed = sourceIndex ~= originalIndex
        source:SetAlpha(1)
        source._sourceFill:SetAlpha(0)
        source._dragGrabX, source._dragGrabY = nil, nil
        if ghost then ghost:Hide() end
        dragging, originalIndex = nil, nil
        holder:SetScript("OnUpdate", nil)
        LayoutRows()

        if save and changed then
            SaveOrder()

            -- A brief settle flash confirms the drop without adding visual noise.
            source._settleFlash:SetAlpha(0.34)
            C_Timer.After(0.06, function() if source._settleFlash then source._settleFlash:SetAlpha(0.16) end end)
            C_Timer.After(0.16, function() if source._settleFlash then source._settleFlash:SetAlpha(0) end end)
        end
    end

    local function FinishDrag()
        if not dragging then return end
        -- Read the release position even if there was no final OnUpdate.
        PreviewOrder()
        EndDrag(true)
    end

    local function AutoSort()
        if dragging then EndDrag(false) end
        local recommended = {}
        for _, key in ipairs(ITEM_QUEUE_ORDER) do
            if ITEM_QUEUE_TYPES[key] then recommended[#recommended + 1] = key end
        end
        ApplyOrder(recommended)
        SaveOrder()
    end

    local function RememberGrab(row)
        local cursorX, cursorY = GetScaledCursor()
        row._dragGrabX = cursorX - row:GetLeft()
        row._dragGrabY = row:GetTop() - cursorY
    end

    local function BeginDrag(row)
        if dragging then return end
        if not row._dragGrabX then RememberGrab(row) end
        dragging = row
        originalIndex = GetRowIndex(row)
        grabX, grabY = row._dragGrabX, row._dragGrabY
        for _, candidate in ipairs(rows) do candidate._queueHover:SetAlpha(0) end
        row:SetAlpha(0.35)
        row._sourceFill:SetAlpha(1)
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        if not ghost then ghost = CreateGhost() end
        local r, g, b = GetItemQueueColor(row._queueKey)
        ghost:SetWidth(row:GetWidth())
        ghost._rank:SetText(row._rank:GetText())
        ghost._swatch:SetColorTexture(r, g, b, 1)
        ghost._label:SetText(ITEM_QUEUE_TYPES[row._queueKey].label)
        ghost:Show()
        PositionGhost()
    end

    local function UpdateDrag()
        if dragging then
            if not IsMouseButtonDown("LeftButton") then
                FinishDrag()
                return
            end
            PreviewOrder()
        end
    end

    holder:SetScript("OnHide", function() EndDrag(false) end)

    for _, key in ipairs(order) do
        local entry = ITEM_QUEUE_TYPES[key]
        if entry then
            local row = CreateFrame("Button", nil, holder)
            row._queueKey = key
            row:EnableMouse(true)
            row:RegisterForDrag("LeftButton")

            local r, g, b = GetItemQueueColor(key)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            row._baseBg = bg

            local hover = row:CreateTexture(nil, "BORDER")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0)
            row._queueHover = hover
            local sourceFill = row:CreateTexture(nil, "BORDER")
            sourceFill:SetAllPoints()
            sourceFill:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.30)
            sourceFill:SetAlpha(0)
            row._sourceFill = sourceFill
            local settleFlash = row:CreateTexture(nil, "HIGHLIGHT")
            settleFlash:SetAllPoints()
            settleFlash:SetColorTexture(1, 1, 1, 0.25)
            settleFlash:SetAlpha(0)
            row._settleFlash = settleFlash

            local grip = row:CreateFontString(nil, "OVERLAY")
            grip:SetFont(fontPath, 12, "")
            grip:SetPoint("LEFT", row, "LEFT", 9, 0)
            grip:SetText("=")
            grip:SetTextColor(1, 1, 1, 0.32)

            local rank = row:CreateFontString(nil, "OVERLAY")
            rank:SetFont(fontPath, 12, "")
            rank:SetPoint("LEFT", grip, "RIGHT", 9, 0)
            rank:SetWidth(24)
            rank:SetJustifyH("RIGHT")
            rank:SetTextColor(0.62, 0.62, 0.62, 1)
            row._rank = rank

            local swatch = row:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(8, 8)
            swatch:SetPoint("LEFT", rank, "RIGHT", 10, 0)
            swatch:SetColorTexture(r, g, b, 1)

            local label = row:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 14, "")
            label:SetPoint("LEFT", swatch, "RIGHT", 9, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(entry.label)
            label:SetTextColor(1, 1, 1, 1)

            row:SetScript("OnEnter", function(self)
                if dragging then return end
                self._queueHover:SetAlpha(1); self._queueHover:SetColorTexture(1, 1, 1, 0.07)
                if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Drag up or down, or across columns, to change priority. Order runs down the left column, then down the right.")
                end
            end)
            row:SetScript("OnLeave", function(self)
                if not dragging then self._queueHover:SetAlpha(0) end
                if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            row:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then RememberGrab(self) end
            end)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    FinishDrag()
                    self._dragGrabX, self._dragGrabY = nil, nil
                end
            end)
            row:SetScript("OnDragStart", function(self)
                BeginDrag(self)
                holder:SetScript("OnUpdate", UpdateDrag)
            end)
            row:SetScript("OnDragStop", FinishDrag)

            rows[#rows + 1] = row
        end
    end
    LayoutRows()
    if onAutoSortReady then onAutoSortReady(AutoSort) end
    return holder, listHeight
end

local function GetPinnedItemIDsText()
    local itemIDs = {}
    for itemID, enabled in pairs(GetItemQueueSettings().pinnedItems) do
        if enabled and tonumber(itemID) then itemIDs[#itemIDs + 1] = tonumber(itemID) end
    end
    table.sort(itemIDs)
    return table.concat(itemIDs, ", ")
end

local function GetBannedItemIDsText()
    local itemIDs = {}
    for itemID, enabled in pairs(GetItemQueueSettings().bannedItems) do
        if enabled and tonumber(itemID) then itemIDs[#itemIDs + 1] = tonumber(itemID) end
    end
    table.sort(itemIDs)
    return table.concat(itemIDs, ", ")
end

ShowItemQueuePinnedItemsPopup = function(anchor)
    if not (EllesmereUI and EllesmereUI.BuildCogPopup) then return end

    local _, show = EllesmereUI.BuildCogPopup({
        title = "Pinned Queue Items",
        minWidth = 390,
        rows = {
            {
                type = "input",
                label = "Item IDs",
                inputWidth = 220,
                get = GetPinnedItemIDsText,
                set = function(value)
                    local pinned = {}
                    for itemID in tostring(value or ""):gmatch("%d+") do
                        pinned[tonumber(itemID)] = true
                    end
                    GetItemQueueSettings().pinnedItems = pinned
                    if RefreshItemQueue then RefreshItemQueue() end
                end,
            },
        },
    })
    show(anchor or EllesmereUI._mainFrame or UIParent)
end

ShowItemQueueBannedItemsPopup = function(anchor)
    if not (EllesmereUI and EllesmereUI.BuildCogPopup) then return end

    local _, show = EllesmereUI.BuildCogPopup({
        title = "Banned Queue Items",
        minWidth = 390,
        rows = {
            {
                type = "input",
                label = "Item IDs",
                inputWidth = 220,
                get = GetBannedItemIDsText,
                set = function(value)
                    local banned = {}
                    for itemID in tostring(value or ""):gmatch("%d+") do
                        banned[tonumber(itemID)] = true
                    end
                    GetItemQueueSettings().bannedItems = banned
                    if RefreshItemQueue then RefreshItemQueue() end
                end,
            },
        },
    })
    show(anchor or EllesmereUI._mainFrame or UIParent)
end

BuildItemQueuePage = function(pageName, parent, yOffset)
    if pageName ~= "Item Queue" then return end

    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local categoryLabels = {}
    local function UpdateCategoryRanks(order)
        for priority, key in ipairs(order) do
            local label = categoryLabels[key]
            if label then label:SetText("#" .. priority .. "  " .. ITEM_QUEUE_TYPES[key].label) end
        end
    end

    _, h = W:SectionHeader(parent, "QUEUE BEHAVIOR", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Enable Item Queue",
            tooltip = "Shows a button only when a configured usable item is available in your bags. The button never uses an item automatically.",
            getValue = function() return GetItemQueueSettings().enabled ~= false end,
            setValue = function(value)
                GetItemQueueSettings().enabled = value and true or false
                if RefreshItemQueue then RefreshItemQueue() end
            end,
        },
        {
            type = "toggle",
            text = "Hide Completed Items",
            tooltip = "Hide items that are already learned or collected, including maxed battle pets. Owned housing decor has its own separate option below. Items the game marks unusable are always hidden.",
            getValue = function() return GetItemQueueSettings().hideCompletedItems ~= false end,
            setValue = function(value)
                GetItemQueueSettings().hideCompletedItems = value and true or false
                if RefreshItemQueue then RefreshItemQueue() end
            end,
        }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Hide Queue in Combat",
            tooltip = "Hide the Item Queue popup automatically while you are in combat. It returns after combat if a queueable item is still available.",
            disabled = function() return InCombatLockdown and InCombatLockdown() end,
            disabledTooltip = "Combat visibility is a secure setting and can only be changed outside combat.",
            getValue = function() return GetItemQueueSettings().hideInCombat == true end,
            setValue = function(value)
                GetItemQueueSettings().hideInCombat = value and true or false
                if UpdateItemQueueCombatVisibility then UpdateItemQueueCombatVisibility() end
                if RefreshItemQueue then RefreshItemQueue() end
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "ITEM USE ORDER", y); y = y - h
    local autoSort
    local orderTools
    orderTools, h = W:DualRow(parent, y, {
        type = "labeledButton",
        text = "Drag to reorder: down the left, then the right",
        buttonText = "Auto Sort",
        width = 104,
        tooltip = "Drag any item category to change its priority. Auto Sort restores the recommended order: profession knowledge, recipes, collection unlocks, then utility items.",
        onClick = function() if autoSort then autoSort() end end,
    }); y = y - h - 8
    local autoSortButton = orderTools and orderTools._leftRegion and orderTools._leftRegion._control
    if autoSortButton then autoSortButton._waffleAutoSort = true end
    _, h = BuildItemQueuePriorityList(parent, y, UpdateCategoryRanks, function(action) autoSort = action end); y = y - h

    _, h = W:SectionHeader(parent, "CATEGORIES", y); y = y - h
    for _, key in ipairs(ITEM_QUEUE_ORDER) do
        local entry = ITEM_QUEUE_TYPES[key]
        local categoryTooltip = key == "darkmoon"
            and "Include Darkmoon Faire cards only when every required Ace-through-Eight card shown in the tooltip is complete. Only one card per completed deck type is queued."
            or key == "appearances" and "Include usable appearance unlocks, including Pepe costume unlock items, in the item queue."
            or "Include usable " .. entry.label:lower() .. " in the item queue."
        local categoryRow
        categoryRow, h = W:DualRow(parent, y,
            {
                type = "toggle",
                text = entry.label,
                tooltip = categoryTooltip,
                getValue = function() return IsItemQueueCategoryEnabled(key) end,
                setValue = function(value)
                    GetItemQueueSettings().categories[key] = value and true or false
                    if RefreshItemQueue then RefreshItemQueue() end
                end,
            },
            {
                type = "colorpicker",
                text = entry.label .. " Color",
                getValue = function() return GetItemQueueColor(key) end,
                setValue = function(r, g, b, a)
                    GetItemQueueSettings().colors[key] = { r = r, g = g, b = b, a = a or 1 }
                    if RefreshItemQueue then RefreshItemQueue() end
                end,
            }
        ); y = y - h
        local region = categoryRow and categoryRow._leftRegion
        if region and region._label then
            categoryLabels[key] = region._label
            if region._control then
                region._label:SetPoint("RIGHT", region._control, "LEFT", -12, 0)
            end
        end
    end
    UpdateCategoryRanks(GetItemQueueSettings().order)

    _, h = W:SectionHeader(parent, "HOUSING DECOR", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Show Already Owned Decor",
            tooltip = "Include usable housing decor even when you already own a copy. Turn this on when you want to use several owned or duplicate decor items in one pass.",
            getValue = function() return GetItemQueueSettings().showOwnedHousingDecor == true end,
            setValue = function(value)
                -- Keep this as a strict boolean.  A migrated value can be nil,
                -- but the options control must always receive a stable on/off
                -- state on its next visual refresh.
                GetItemQueueSettings().showOwnedHousingDecor = value == true
                if RefreshItemQueue then RefreshItemQueue() end
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "ITEM EXCEPTIONS", y); y = y - h
    local pinnedRow
    pinnedRow, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Pinned Item IDs",
            buttonText = "Manage Items",
            tooltip = "Add item IDs here to include any usable item that the automatic categories do not recognize.",
        },
        {
            type = "labeledButton",
            text = "Banned Item IDs",
            buttonText = "Manage Items",
            tooltip = "Shift-right-click an item on the Item Queue button to ban it permanently. Right-click alone only hides it until reload. Manage permanent bans here with comma- or space-separated item IDs.",
        }
    ); y = y - h
    local pinnedButton = pinnedRow and pinnedRow._leftRegion and pinnedRow._leftRegion._control
    if pinnedButton then
        pinnedButton:SetScript("OnClick", function(self) ShowItemQueuePinnedItemsPopup(self) end)
    end
    local bannedButton = pinnedRow and pinnedRow._rightRegion and pinnedRow._rightRegion._control
    if bannedButton then
        bannedButton:SetScript("OnClick", function(self) ShowItemQueueBannedItemsPopup(self) end)
    end

    _, h = W:SectionHeader(parent, "QUEUE TOOLS", y); y = y - h
    local auditRow
    auditRow, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Bag Queue Audit",
            buttonText = "Inspect Bags",
            tooltip = "Creates a read-only report of collection and usable-item candidates in your bags. Use /whqueue for the current queue item, /whqueue <bag> <slot> for one exact bag item, or /whqueue <item name or ID> to find a copy.",
        }
    ); y = y - h
    local auditButton = auditRow and auditRow._leftRegion and auditRow._leftRegion._control
    if auditButton then
        auditButton:SetScript("OnClick", function(self) ShowItemQueueDiagnostics(self) end)
    end

    return math.abs(y)
end

local function IsSafeValue(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IsSafeText(value)
    return type(value) == "string" and IsSafeValue(value) and value ~= ""
end

local function IsSafeNumber(value)
    return type(value) == "number" and IsSafeValue(value)
end

SetFont = function(fontString, size, flags)
    fontString:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE")
end

local function GetCostKey(texture, link)
    if IsSafeText(link) then
        return "link:" .. link
    end
    if IsSafeValue(texture) and (type(texture) == "number" or type(texture) == "string") then
        return "texture:" .. tostring(texture)
    end
end

local function GetCostName(link, currencyName)
    if IsSafeText(currencyName) then
        return currencyName
    end
    if IsSafeText(link) and GetItemInfo then
        local itemName = GetItemInfo(link)
        if IsSafeText(itemName) then
            return itemName
        end
    end
    return "Currency"
end

-- Currency links normally arrive as plain white text, which made every
-- currency inherit the same teal fallback.  Give every currency ID a stable
-- hue instead.  The golden-angle step separates neighbouring IDs well while
-- the tiny lightness variation keeps IDs that share a hue residue distinct.
function addon.GetCurrencyAccentColor(link)
    if not IsSafeText(link) then return nil end
    local currencyID = tonumber(link:match("|Hcurrency:(%d+)") or link:match("currency:(%d+)"))
    if not currencyID then return nil end

    local hue = ((currencyID * 137) % 360) / 360
    local lightness = 0.60 + (((math.floor(currencyID / 360) % 3) - 1) * 0.035)
    local saturation = 0.62
    local q = lightness < 0.5 and lightness * (1 + saturation) or lightness + saturation - (lightness * saturation)
    local p = (2 * lightness) - q
    local function Channel(offset)
        local t = (hue + offset) % 1
        if t < (1 / 6) then return p + ((q - p) * 6 * t) end
        if t < 0.5 then return q end
        if t < (2 / 3) then return p + ((q - p) * ((2 / 3) - t) * 6) end
        return p
    end
    return string.format("ff%02x%02x%02x", math.floor(Channel(1 / 3) * 255 + 0.5),
        math.floor(Channel(0) * 255 + 0.5), math.floor(Channel(-1 / 3) * 255 + 0.5))
end

local function GetCostColor(link)
    local currencyColor = addon.GetCurrencyAccentColor(link)
    if currencyColor then return currencyColor end
    if IsSafeText(link) then
        local color = link:match("|c(%x%x%x%x%x%x%x%x)")
        if color and color ~= "ffffffff" then return color end
    end
    return "ff40d8c6"
end

local function ColorName(name, color)
    return "|c" .. (color or "ff40d8c6") .. name .. "|r"
end

local function ColorComponents(color)
    color = color or "ff40d8c6"
    return (tonumber(color:sub(3, 4), 16) or 64) / 255,
        (tonumber(color:sub(5, 6), 16) or 216) / 255,
        (tonumber(color:sub(7, 8), 16) or 198) / 255
end

local function NormalizeItemQueueTooltipText(value)
    if not IsSafeText(value) then return "" end
    -- C_TooltipInfo supplies the same color and texture markup that GameTooltip
    -- draws.  Remove it before matching so visual markup cannot split a Use
    -- action or an x/y requirement into different search tokens.
    local text = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("%s+", " ")
    return text:match("^%s*(.-)%s*$") or ""
end

local function GetBagItemTooltipSnapshot(bag, slot)
    local snapshot = {
        available = false,
        bag = bag,
        lineCount = 0,
        lines = {},
        normalized = "",
        reason = "C_TooltipInfo.GetBagItem is unavailable.",
        slot = slot,
    }
    if not (C_TooltipInfo and type(C_TooltipInfo.GetBagItem) == "function") then return snapshot end

    local ok, tooltip = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok then
        snapshot.reason = "C_TooltipInfo.GetBagItem raised an error."
        return snapshot
    end
    if type(tooltip) ~= "table" then
        snapshot.reason = "C_TooltipInfo.GetBagItem returned no tooltip table."
        return snapshot
    end
    if type(tooltip.lines) ~= "table" then
        snapshot.reason = "C_TooltipInfo.GetBagItem returned a tooltip without lines."
        return snapshot
    end

    snapshot.available = true
    snapshot.dataInstanceID = IsSafeNumber(tooltip.dataInstanceID) and tooltip.dataInstanceID or nil
    local parts = {}
    for index, line in ipairs(tooltip.lines) do
        local left = NormalizeItemQueueTooltipText(line.leftText)
        local right = NormalizeItemQueueTooltipText(line.rightText)
        if left ~= "" or right ~= "" then
            snapshot.lineCount = snapshot.lineCount + 1
            snapshot.lines[#snapshot.lines + 1] = {
                index = index,
                left = left,
                right = right,
            }
            if left ~= "" then parts[#parts + 1] = left end
            if right ~= "" then parts[#parts + 1] = right end
        end
    end
    snapshot.normalized = table.concat(parts, " "):lower()
    if snapshot.lineCount == 0 then
        snapshot.reason = "Tooltip contains no readable left or right text."
    elseif snapshot.lineCount == 1 then
        snapshot.reason = "Tooltip has only one readable line; waiting for its detail lines."
    else
        snapshot.reason = "Tooltip has readable detail lines."
    end
    return snapshot
end

local function IsItemQueueTooltipReady(itemID, snapshot)
    local itemDataCached = true
    if C_Item and type(C_Item.IsItemDataCachedByID) == "function" then
        itemDataCached = C_Item.IsItemDataCachedByID(itemID) == true
    end
    snapshot.itemDataCached = itemDataCached
    snapshot.ready = snapshot.available and snapshot.lineCount > 1 and snapshot.normalized ~= "" and itemDataCached
    if not snapshot.ready then
        if not itemDataCached then
            snapshot.reason = "Item data is not cached yet."
        elseif snapshot.available and snapshot.lineCount <= 1 then
            snapshot.reason = "Tooltip detail lines are not ready yet."
        end
    end
    return snapshot.ready
end

local function RequestItemQueueTooltipRetry(itemID, bag, slot)
    itemQueueTooltipRetryPending.items[itemID] = true
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function"
        and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    if itemQueueTooltipRetryPending.timer or (itemQueueTooltipRetryPending.attempt or 0) >= 6
        or not (C_Timer and type(C_Timer.After) == "function") then return end
    itemQueueTooltipRetryPending.timer = true
    itemQueueTooltipRetryPending.attempt = (itemQueueTooltipRetryPending.attempt or 0) + 1
    -- Share one bounded timer, but retry only items still waiting for data.
    C_Timer.After(0.25 * 2 ^ (itemQueueTooltipRetryPending.attempt - 1), function()
        itemQueueTooltipRetryPending.timer = nil
        local items = itemQueueTooltipRetryPending.items
        itemQueueTooltipRetryPending.items = {}
        if next(items) and RefreshItemQueue then RefreshItemQueue(items) end
    end)
end

local function IsDarkmoonFaireCardTooltip(tooltip)
    return tooltip:find("use: combine the ace through eight of", 1, true) ~= nil
end

local function IsCombinationTooltip(tooltip)
    return tooltip:find("use: combine", 1, true) ~= nil
        or tooltip:find("use: reform", 1, true) ~= nil
end

local function IsCurrencyGrantTooltip(tooltip)
    -- Items such as Nahuut's Second-Favorite Chew Toy read "Use: Gain a
    -- large amount of Voidlight Marl."  They are consumable currency grants,
    -- not boxes or generic gear.  Retain a narrow Use/Gain/amount-of shape so
    -- stat, health, mana, and experience effects do not enter this category.
    if not tooltip:find("use: gain", 1, true) then return false end
    local granted = tooltip:match("use:%s*gain%s+.-%s+of%s+([%a][%a%s'%-]*)")
    if not IsSafeText(granted) then return false end
    granted = granted:lower()
    return not granted:find("experience", 1, true)
        and not granted:find("health", 1, true)
        and not granted:find("mana", 1, true)
end

local function HasCompleteCombinationRequirements(tooltip)
    -- A regular combination item can have no explicit x/y list.  In that
    -- case its own Use action decides whether it can proceed.  When it does
    -- list components, though, every requirement has to be met before this
    -- particular item may occupy the queue.
    for current, required in tooltip:gmatch("(%d+)%s*/%s*(%d+)") do
        current, required = tonumber(current), tonumber(required)
        if current and required and required > 0 and current < required then
            return false
        end
    end
    return true
end

local function IsIncompleteCombinationTooltip(tooltip)
    return IsCombinationTooltip(tooltip) and not HasCompleteCombinationRequirements(tooltip)
end

local function GetItemQueueCombinationRequirements(itemID, snapshot)
    if not IsCombinationTooltip(snapshot.normalized) and not incompleteCombinationItems[itemID] then return nil end
    local result = { ready = false, rows = {}, incomplete = false, reason = "Waiting for item Use spell/recipe data." }
    if not snapshot.ready then return result end
    -- Preserve the existing raw-tooltip Darkmoon path when all eight card
    -- counts are explicitly present. No missing or abbreviated list qualifies.
    if IsDarkmoonFaireCardTooltip(snapshot.normalized) then
        for current, required in snapshot.normalized:gmatch("(%d+)%s*/%s*(%d+)") do
            current, required = tonumber(current), tonumber(required)
            if required > 0 then
                result.rows[#result.rows + 1] = { owned = current, required = required, alternatives = {}, ready = true }
                if current < required then result.incomplete = true end
            end
        end
        if #result.rows >= 8 then
            result.ready, result.source = true, "raw Darkmoon tooltip"
            result.reason = result.incomplete and "Darkmoon card counts are incomplete." or "All eight Darkmoon card counts are complete."
            return result
        end
        result.rows, result.incomplete = {}, false
    end
    if not (C_Item and C_Item.GetItemSpell and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return result end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    if not ok or not IsSafeNumber(spellID) or spellID <= 0 then return result end
    result.spellID = spellID
    local schematicOK, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
    if not schematicOK or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return result end
    result.recipeID = schematic.recipeID
    result.source = "item Use recipe"
    result.ready = true
    -- Plumber's visible x/y rows are appended to GameTooltip from this same
    -- recipe API; they are NOT part of C_TooltipInfo.GetBagItem(). Read the
    -- required slots directly and count carried items, excluding every bank.
    for index, reagentSlot in ipairs(schematic.reagentSlotSchematics) do
        if reagentSlot.required then
            local row = { slot = index, required = reagentSlot.quantityRequired, owned = 0, alternatives = {} }
            local valid = IsSafeNumber(row.required) and row.required > 0
                and type(reagentSlot.reagents) == "table" and #reagentSlot.reagents > 0
            for _, reagent in ipairs(reagentSlot.reagents or {}) do
                local count, name, countOK
                if IsSafeNumber(reagent.itemID) and reagent.itemID > 0 then
                    if C_Item.GetItemCount then
                        countOK, count = pcall(C_Item.GetItemCount, reagent.itemID, false, false, false, false)
                    end
                    name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(reagent.itemID)
                elseif IsSafeNumber(reagent.currencyID) and reagent.currencyID > 0 then
                    local info
                    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                        countOK, info = pcall(C_CurrencyInfo.GetCurrencyInfo, reagent.currencyID)
                    end
                    if type(info) == "table" then count, name = info.quantity, info.name end
                end
                if not countOK or not IsSafeNumber(count) or count < 0 then
                    valid = false
                else
                    row.owned = row.owned + count
                end
                row.alternatives[#row.alternatives + 1] = {
                    itemID = reagent.itemID, currencyID = reagent.currencyID,
                    name = IsSafeText(name) and name or nil, count = IsSafeNumber(count) and count or nil,
                }
            end
            row.ready = valid
            if not valid then result.ready = false
            elseif row.owned < row.required then result.incomplete = true end
            result.rows[#result.rows + 1] = row
        end
    end
    result.reason = not result.ready and "Required reagent data is incomplete."
        or (result.incomplete and "Required components are missing from carried bags."
        or (#result.rows > 0 and "Every required component is in carried bags." or "Recipe exposes no required components."))
    return result
end

local function UpdateIncompleteCombinationItem(itemID, tooltipSnapshot, readOnly)
    local requirements = tooltipSnapshot.combinationRequirements
    local incomplete = incompleteCombinationItems[itemID] == true
    if IsIncompleteCombinationTooltip(tooltipSnapshot.normalized) or (requirements and requirements.incomplete) then
        incomplete = true
    elseif tooltipSnapshot.ready and requirements and requirements.ready then
        -- An absent count list is not evidence of completion. Only a resolved
        -- recipe, with every required slot supplied, clears automatic blocks.
        incomplete = false
    end
    if not readOnly then incompleteCombinationItems[itemID] = incomplete or nil end
    return incomplete
end

local function HasCompleteDarkmoonFaireCardSet(tooltip)
    local requirementCount = 0
    for current, required in tooltip:gmatch("(%d+)%s*/%s*(%d+)") do
        current, required = tonumber(current), tonumber(required)
        if current and required and required > 0 then
            requirementCount = requirementCount + 1
            if current < required then return false end
        end
    end
    return requirementCount >= 8
end

local function GetDarkmoonFaireCardSetKey(tooltip)
    local deck = tooltip:match("use:%s*combine%s+the%s+ace%s+through%s+eight%s+of%s+(.+)%s+to%s+complete%s+the%s+set")
    if IsSafeText(deck) then
        return deck:gsub("%s+", " ")
    end
    return "darkmoon-fair-card-set"
end

local function GetBattlePetSpeciesID(itemID)
    if not (C_PetJournal and C_PetJournal.GetPetInfoByItemID) then return nil end
    -- Retail's species ID is the thirteenth return value for an un-caged pet item.
    return select(13, C_PetJournal.GetPetInfoByItemID(itemID))
end

local function IsToyItem(itemID)
    return C_ToyBox and type(C_ToyBox.GetToyInfo) == "function"
        and C_ToyBox.GetToyInfo(itemID) ~= nil
end

local function GetMountIDFromItem(itemID)
    if not (C_MountJournal and type(C_MountJournal.GetMountFromItem) == "function") then return nil end
    return C_MountJournal.GetMountFromItem(itemID)
end

local function IsMountCollected(itemID)
    local mountID = GetMountIDFromItem(itemID)
    if not (mountID and C_MountJournal and type(C_MountJournal.GetMountInfoByID) == "function") then return false end
    local collected = select(11, C_MountJournal.GetMountInfoByID(mountID))
    return collected == true
end

local function IsHeirloomItem(itemID)
    return C_Heirloom and type(C_Heirloom.GetHeirloomInfo) == "function"
        and C_Heirloom.GetHeirloomInfo(itemID) ~= nil
end

local function HasHeirloom(itemID)
    return C_Heirloom and type(C_Heirloom.PlayerHasHeirloom) == "function"
        and C_Heirloom.PlayerHasHeirloom(itemID) == true
end

local function IsItemAppearanceCollected(itemID)
    if not (C_TransmogCollection and type(C_TransmogCollection.PlayerHasTransmogByItemInfo) == "function") then return false end
    local ok, collected = pcall(C_TransmogCollection.PlayerHasTransmogByItemInfo, itemID)
    return ok and collected == true
end

local function GetHousingCatalogItemInfo(itemID)
    local api = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
    if type(api) ~= "function" then return nil end
    local ok, info = pcall(api, itemID, true)
    if ok and type(info) == "table" then return info end
    ok, info = pcall(api, itemID)
    return ok and type(info) == "table" and info or nil
end

local function IsOwnedHousingDecor(info)
    if type(info) ~= "table" then return false end
    for _, field in ipairs({ "quantity", "remainingRedeemable", "numPlaced", "totalNumStored", "totalNumPlaced" }) do
        if IsSafeNumber(info[field]) and info[field] > 0 then return true end
    end
    return false
end

local function TooltipShowsMaxedCount(tooltip, pattern)
    local current, maximum = tooltip:match(pattern)
    current, maximum = tonumber(current), tonumber(maximum)
    return current and maximum and maximum > 0 and current >= maximum
end

local function IsCompletedQueueItem(itemID, tooltip, housingInfo)
    local queue = GetItemQueueSettings()
    if queue.hideCompletedItems == false then return false end

    if IsOwnedHousingDecor(housingInfo) and not queue.showOwnedHousingDecor then return true end

    if C_PetJournal and C_PetJournal.GetNumCollectedInfo then
        local speciesID = GetBattlePetSpeciesID(itemID)
        if type(speciesID) == "number" then
            local collected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
            if type(collected) == "number" and type(limit) == "number" and limit > 0 and collected >= limit then
                return true
            end
        end
    end

    if PlayerHasToy and PlayerHasToy(itemID) then return true end
    if IsMountCollected(itemID) or HasHeirloom(itemID) then return true end
    if tooltip:find("tabard", 1, true) and IsItemAppearanceCollected(itemID) then return true end

    if TooltipShowsMaxedCount(tooltip, "pet%s+max%s*:?%s*(%d+)%s*/%s*(%d+)")
        or TooltipShowsMaxedCount(tooltip, "learned%s*:?%s*(%d+)%s*/%s*(%d+)")
        or TooltipShowsMaxedCount(tooltip, "collected%s+appearances%s*:?%s*(%d+)%s*/%s*(%d+)") then
        return true
    end

    for _, phrase in ipairs({
        "already learned",
        "already known",
        "already collected",
        "you have collected this appearance",
        "you have collected the maximum",
        "you already have the maximum",
        "cannot be learned",
    }) do
        if tooltip:find(phrase, 1, true) then return true end
    end
    return false
end

local function CanLearnQueueRecipe(tooltip)
    if not (GetProfessions and GetProfessionInfo) then return true end

    local known = {}
    for _, professionIndex in pairs({ GetProfessions() }) do
        if professionIndex then
            local name, _, skillLevel, _, _, _, _, _, _, _, skillLineName = GetProfessionInfo(professionIndex)
            for _, professionName in ipairs({ name, skillLineName }) do
                if IsSafeText(professionName) then
                    local key = professionName:lower()
                    known[key] = math.max(known[key] or 0, tonumber(skillLevel) or 0)
                end
            end
        end
    end

    for professionName, skillLevel in pairs(known) do
        local prefix = "requires " .. professionName
        local startIndex = tooltip:find(prefix, 1, true)
        if not startIndex then
            prefix = "requires: " .. professionName
            startIndex = tooltip:find(prefix, 1, true)
        end
        if startIndex then
            local remaining = tooltip:sub(startIndex + #prefix)
            local requiredSkill = tonumber(remaining:match("^%s*%((%d+)%)"))
            return not requiredSkill or skillLevel >= requiredSkill
        end
    end

    -- Profession recipe tooltips that have a requirement we could not match
    -- belong to a profession the character does not have.
    return not (tooltip:find("requires ", 1, true) or tooltip:find("requires:", 1, true))
end

local function IsAppearanceUnlockTooltip(tooltip)
    if not tooltip:find("use:", 1, true) then return false end
    return tooltip:find("collect the appearance", 1, true) ~= nil
        or tooltip:find("collect the appearances", 1, true) ~= nil
        or tooltip:find("collected appearances", 1, true) ~= nil
        -- Pepe costumes describe the appearance of future summons. Require
        -- that specific Use clause, not a Pepe name or a summoning action.
        or tooltip:find("use: when summoned, pepe will sometimes ", 1, true) ~= nil
        -- Warband cosmetics such as Barbed Riftwalker Dirk word this as
        -- "Use: Add this appearance to your Warband collection."  Do not
        -- depend on the line staying on one tooltip line.
        or (tooltip:find("add this appearance", 1, true) ~= nil
            and (tooltip:find("warband", 1, true) ~= nil or tooltip:find("collection", 1, true) ~= nil))
end

local function GetItemQueueMatchData(itemID, bag, slot, tooltipSnapshot)
    local queue = GetItemQueueSettings()
    if not tooltipSnapshot then
        tooltipSnapshot = GetBagItemTooltipSnapshot(bag, slot)
        IsItemQueueTooltipReady(itemID, tooltipSnapshot)
        tooltipSnapshot.combinationRequirements = GetItemQueueCombinationRequirements(itemID, tooltipSnapshot)
    end
    local tooltip = tooltipSnapshot.normalized
    local housingInfo = GetHousingCatalogItemInfo(itemID)
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, itemClassID = C_Item.GetItemInfoInstant(itemID)
        classID = itemClassID
    end
    local petSpeciesID = GetBattlePetSpeciesID(itemID)
    local isRecipe = not petSpeciesID and (classID == 9 or tooltip:find("teaches you", 1, true) ~= nil)
    local isDarkmoonCard = IsDarkmoonFaireCardTooltip(tooltip)
    local isCombination = IsCombinationTooltip(tooltip)
    local matches = {
        custom = queue.pinnedItems[itemID] == true,
        knowledge = tooltip:find("knowledge", 1, true) ~= nil,
        appearances = IsAppearanceUnlockTooltip(tooltip),
        tabards = tooltip:find("tabard", 1, true) ~= nil
            and tooltip:find("use:", 1, true) ~= nil,
        mounts = GetMountIDFromItem(itemID) ~= nil,
        heirlooms = IsHeirloomItem(itemID),
        toys = IsToyItem(itemID),
        pets = petSpeciesID ~= nil
            or tooltip:find("summon and dismiss this companion", 1, true) ~= nil
            or tooltip:find("learn this companion", 1, true) ~= nil,
        housing = housingInfo ~= nil,
        account = tooltip:find("use: add", 1, true) ~= nil
            and (tooltip:find("warband", 1, true) ~= nil or tooltip:find("collection", 1, true) ~= nil),
        recipes = isRecipe and CanLearnQueueRecipe(tooltip),
        -- These cards are never offered early.  Each item's own tooltip
        -- lists the complete Ace-through-Eight set and its x/y counts.
        darkmoon = isDarkmoonCard and HasCompleteDarkmoonFaireCardSet(tooltip),
        -- Things like Tempered Amani Spearhead have a direct "Use: Combine"
        -- action but are neither a container nor a learned collectible.
        combination = not isDarkmoonCard and isCombination and HasCompleteCombinationRequirements(tooltip),
        containers = classID == 1
            or tooltip:find("open to receive", 1, true) ~= nil
            or tooltip:find("contains", 1, true) ~= nil
            or tooltip:find("cache", 1, true) ~= nil
            or tooltip:find("crate", 1, true) ~= nil
            or tooltip:find("box", 1, true) ~= nil
            or tooltip:find("satchel", 1, true) ~= nil,
        currency = IsCurrencyGrantTooltip(tooltip),
    }
    return tooltip, tooltipSnapshot, housingInfo, matches
end

local function CanUseQueueItem(itemID, tooltip, matches)
    if C_Item and C_Item.IsUsableItem and C_Item.IsUsableItem(itemID) then
        return true
    end

    -- Some account-wide cosmetics advertise a real "Use" action but Retail's
    -- generic usable-item flag reports false for them.  The secure item
    -- button can still activate these, so accept an explicit collection-use
    -- tooltip only for categories we positively recognized—not ordinary gear.
    if not tooltip:find("use:", 1, true) then return false end
    return matches.appearances or matches.tabards or matches.pets or matches.housing
        or matches.account or matches.combination or matches.containers
        or matches.knowledge or matches.recipes or matches.toys or matches.mounts
        or matches.heirlooms or matches.darkmoon or matches.currency
end

local function EvaluateItemQueueCandidate(itemID, bag, slot, snapshot, readOnly)
    local queue = GetItemQueueSettings()
    local tooltip, tooltipSnapshot, housingInfo, matches = GetItemQueueMatchData(itemID, bag, slot, snapshot)
    local decision = {
        bag = bag,
        categoryMatches = {},
        checks = {},
        itemID = itemID,
        matches = matches,
        slot = slot,
        tooltip = tooltip,
        tooltipSnapshot = tooltipSnapshot,
    }

    local tooltipReady = itemID and IsItemQueueTooltipReady(itemID, tooltipSnapshot) or false
    local isDarkmoonCard = IsDarkmoonFaireCardTooltip(tooltip)
    local requirements = tooltipSnapshot.combinationRequirements
    local incompleteDarkmoon = isDarkmoonCard and not HasCompleteDarkmoonFaireCardSet(tooltip)
        and not (requirements and requirements.ready and #requirements.rows > 0 and not requirements.incomplete)
    local incompleteCombination = IsIncompleteCombinationTooltip(tooltip)
    local automaticCombinationBan = itemID and UpdateIncompleteCombinationItem(itemID, tooltipSnapshot, readOnly) or false
    local requirementsPending = requirements and not requirements.ready or false
    if isDarkmoonCard then matches.darkmoon = not incompleteDarkmoon end
    local completed = itemID and IsCompletedQueueItem(itemID, tooltip, housingInfo) or false
    local usable = itemID and CanUseQueueItem(itemID, tooltip, matches) or false
    decision.checks = {
        completed = completed,
        automaticCombinationBan = automaticCombinationBan,
        requirementsPending = requirementsPending,
        incompleteCombination = incompleteCombination,
        incompleteDarkmoon = incompleteDarkmoon,
        itemPresent = itemID ~= nil,
        permanentlyBanned = itemID and queue.bannedItems[itemID] == true or false,
        sessionBanned = itemID and sessionBannedItems[itemID] == true or false,
        tooltipReady = tooltipReady,
        usable = usable,
    }

    for priority, key in ipairs(queue.order) do
        decision.categoryMatches[#decision.categoryMatches + 1] = {
            enabled = queue.categories[key] ~= false,
            key = key,
            matched = matches[key] == true,
            priority = priority,
        }
    end

    -- This is deliberately before every category decision.  A cold or partial
    -- C_TooltipInfo snapshot must not let an otherwise known pinned, box, or
    -- API-detected item become a cached queue candidate without its Use action
    -- and component requirements being observed.
    if not itemID then
        decision.reason = "No item ID was supplied."
        return decision
    end
    if decision.checks.permanentlyBanned then
        decision.reason = "Permanently banned."
        return decision
    end
    if decision.checks.sessionBanned then
        decision.reason = "Hidden until reload."
        return decision
    end
    if automaticCombinationBan then
        if requirementsPending and not readOnly then RequestItemQueueTooltipRetry(itemID, bag, slot) end
        decision.reason = "Temporarily blocked: Combine/Reform component requirements are incomplete."
        return decision
    end
    if not tooltipReady then
        if not readOnly then RequestItemQueueTooltipRetry(itemID, bag, slot) end
        decision.reason = "Tooltip data is not ready; deferred until a complete scanner snapshot is available."
        return decision
    end
    if requirementsPending then
        if not readOnly then RequestItemQueueTooltipRetry(itemID, bag, slot) end
        decision.reason = "Combine/Reform recipe requirements are not ready; deferred."
        return decision
    end
    -- Both gates apply across all categories.  In particular, a pinned item
    -- or an item with the broad container class cannot bypass an incomplete
    -- Combine/Reform list, and a pinned Darkmoon card cannot bypass its deck.
    if incompleteDarkmoon then
        decision.reason = "Darkmoon Faire Card requirements are incomplete."
        return decision
    end
    if incompleteCombination then
        decision.reason = "Combine/Reform component requirements are incomplete."
        return decision
    end
    if completed then
        decision.reason = "Already learned, collected, or intentionally hidden by the completed-item setting."
        return decision
    end
    if not usable then
        decision.reason = "Not currently usable."
        return decision
    end

    for _, category in ipairs(decision.categoryMatches) do
        if category.enabled and category.matched then
            decision.category = category.key
            decision.darkmoonSetKey = isDarkmoonCard and GetDarkmoonFaireCardSetKey(tooltip) or nil
            decision.priority = category.priority
            decision.reason = "Queued as " .. ITEM_QUEUE_TYPES[category.key].label .. "."
            return decision
        end
    end
    decision.reason = "No enabled queue category matched."
    return decision
end

local function GetItemQueueCategory(itemID, bag, slot)
    local decision = EvaluateItemQueueCandidate(itemID, bag, slot)
    return decision.category, decision.priority, decision.darkmoonSetKey
end

function itemQueueCache.SameSlot(previous, current)
    return previous and current and not current.isLocked
        and previous.itemID == current.itemID and previous.itemGUID == current.itemGUID
        and previous.stackCount == current.stackCount and previous.hyperlink == current.hyperlink
end

-- nil rebuilds everything; "bags" diffs the inventory; an item-ID set refreshes
-- only those cached slots. Keep rejected items too: new data can admit them.
local function ScanItemQueue(itemIDs, invalidatedItems)
    local candidates = {}
    local queuedDarkmoonSets = {}
    local samples = {}
    local dirty = {}
    itemQueueCache.followupItems = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return candidates
    end
    if not itemQueueCache.samples then itemIDs = nil end
    if type(itemIDs) == "table" then
        if next(itemQueueCache.dirtyBags) then return ScanItemQueue("bags", itemIDs) end
        samples = itemQueueCache.samples
        for _, sample in ipairs(samples) do
            if itemIDs[sample.item.itemID] then
                local item = C_Container.GetContainerItemInfo(sample.bag, sample.slot)
                if not itemQueueCache.SameSlot(sample.item, item) then
                    -- A late data notification can race a move, removal or
                    -- stack change. Reconcile inventory before using the slot.
                    itemQueueCache.dirtyBags = {}
                    return ScanItemQueue("bags", itemIDs)
                end
                dirty[sample] = true
            end
        end
    else
        local previous = {}
        local previousBags = {}
        local dirtyBags = itemIDs == "bags" and next(itemQueueCache.dirtyBags) and itemQueueCache.dirtyBags or nil
        itemQueueCache.dirtyBags = {}
        if itemIDs == "bags" then
            for _, sample in ipairs(itemQueueCache.samples) do
                previous[tostring(sample.bag) .. ":" .. tostring(sample.slot)] = sample
                previousBags[sample.bag] = previousBags[sample.bag] or {}
                table.insert(previousBags[sample.bag], sample)
            end
        end
        local changedItems = {}
        local bags = {}
        for bag = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
        local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
        if reagentBag and reagentBag > (NUM_BAG_SLOTS or 4) then bags[#bags + 1] = reagentBag end
        for _, bag in ipairs(bags) do
            if dirtyBags and not dirtyBags[bag] then
                for _, sample in ipairs(previousBags[bag] or {}) do samples[#samples + 1] = sample end
            else
                for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                    local item = C_Container.GetContainerItemInfo(bag, slot)
                    if item and item.itemID and not item.isLocked then
                        local old = previous[tostring(bag) .. ":" .. tostring(slot)]
                        local sample = old
                        if not old or not itemQueueCache.SameSlot(old.item, item) then
                            sample = { item = { itemID = item.itemID, itemGUID = item.itemGUID,
                                stackCount = item.stackCount, hyperlink = item.hyperlink, iconFileID = item.iconFileID }, bag = bag, slot = slot }
                            dirty[sample] = true
                            changedItems[item.itemID] = true
                            if itemIDs == "bags" then itemQueueCache.followupItems[item.itemID] = true end
                        end
                        samples[#samples + 1] = sample
                    end
                end
            end
        end
        -- The temporary combination ban is shared by item ID. Refresh sibling
        -- stacks together before evaluating any of their category decisions.
        for _, sample in ipairs(samples) do
            local snapshot = sample.snapshot
            if changedItems[sample.item.itemID] or (invalidatedItems and invalidatedItems[sample.item.itemID])
                or (snapshot and (snapshot.combinationRequirements or IsDarkmoonFaireCardTooltip(snapshot.normalized)
                    or not snapshot.ready)) then
                -- Component counts can change even in an untouched bag.
                dirty[sample] = true
            end
        end
        itemQueueCache.samples = samples
    end

    -- Finish the affected Combine/Reform prepass before category matching.
    for _, sample in ipairs(samples) do
        if dirty[sample] then
            local itemID = sample.item.itemID
            local snapshot = GetBagItemTooltipSnapshot(sample.bag, sample.slot)
            IsItemQueueTooltipReady(itemID, snapshot)
            snapshot.combinationRequirements = GetItemQueueCombinationRequirements(itemID, snapshot)
            UpdateIncompleteCombinationItem(itemID, snapshot)
            sample.snapshot = snapshot
            sample.candidate = nil
            if not snapshot.ready or snapshot.combinationRequirements then
                itemQueueCache.followupItems[itemID] = true
            end
        end
    end

    itemQueueLastDecisions = {}
    itemQueueCache.tooltipInstances = {}
    itemQueueCache.items = {}
    local unresolved = {}
    for _, sample in ipairs(samples) do
        local item, bag, slot = sample.item, sample.bag, sample.slot
        if dirty[sample] then
            sample.decision = EvaluateItemQueueCandidate(item.itemID, bag, slot, sample.snapshot)
        end
        local decision = sample.decision
        itemQueueCache.items[item.itemID] = true
        if sample.snapshot.dataInstanceID then
            itemQueueCache.tooltipInstances[sample.snapshot.dataInstanceID] = item.itemID
        end
        if not decision.checks.tooltipReady or decision.checks.requirementsPending then unresolved[item.itemID] = true end
        local category, priority, darkmoonSetKey = decision.category, decision.priority, decision.darkmoonSetKey
        itemQueueLastDecisions[tostring(bag) .. ":" .. tostring(slot)] = decision
        local isNewDarkmoonSet = not darkmoonSetKey or not queuedDarkmoonSets[darkmoonSetKey]
        if category and isNewDarkmoonSet then
            if darkmoonSetKey then queuedDarkmoonSets[darkmoonSetKey] = true end
            if not sample.candidate then
                local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.itemID)
                sample.candidate = {
                    bag = bag,
                    category = category,
                    count = item.stackCount or 1,
                    icon = item.iconFileID or icon,
                    itemID = item.itemID,
                    link = item.hyperlink,
                    name = name or (item.hyperlink and item.hyperlink:match("%[(.-)%]")) or "Usable Item",
                    priority = priority,
                    quality = quality,
                    slot = slot,
                    decision = decision,
                    slotInfo = item,
                }
            end
            candidates[#candidates + 1] = sample.candidate
            decision.scanResult = "Candidate accepted."
        elseif category then
            decision.scanResult = "Duplicate complete Darkmoon deck suppressed."
        else
            decision.scanResult = "Excluded: " .. decision.reason
        end
    end
    for itemID in pairs(itemQueueTooltipRetryPending.items) do
        if not unresolved[itemID] then itemQueueTooltipRetryPending.items[itemID] = nil end
    end

    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.itemID < b.itemID
    end)
    return candidates
end

local function GetQueueItemName(item)
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.itemID)
    return name or (item.hyperlink and item.hyperlink:match("%[(.-)%]")) or ("Item " .. tostring(item.itemID))
end

local function IsPotentialQueueItem(itemID, tooltip, matches)
    if matches then
        for _, matched in pairs(matches) do
            if matched then return true end
        end
    end
    return GetBattlePetSpeciesID(itemID) ~= nil or IsToyItem(itemID) or GetMountIDFromItem(itemID) ~= nil
        or IsHeirloomItem(itemID) or tooltip:find("use:", 1, true) ~= nil
end

local function GetQueueItemDiagnostic(item, bag, slot)
    local decision = EvaluateItemQueueCandidate(item.itemID, bag, slot, nil, true)
    if not IsPotentialQueueItem(item.itemID, decision.tooltip, decision.matches) then return nil end
    if decision.category then return decision.reason .. " (priority " .. tostring(decision.priority) .. ")." end
    return decision.reason
end

local function QueueDiagnosticYesNo(value)
    return value and "YES" or "no"
end

local function BuildItemQueueDiagnosticDetails(item, bag, slot)
    local decision = EvaluateItemQueueCandidate(item.itemID, bag, slot, nil, true)
    local snapshot = decision.tooltipSnapshot
    local lines = {
        "ITEM QUEUE ITEM DIAGNOSTICS (recipe-requirements-v2)",
        "Bag / slot: " .. tostring(bag) .. " / " .. tostring(slot),
        "Item ID: " .. tostring(item.itemID),
        "Link: " .. tostring(item.hyperlink or item.link or "<unavailable>"),
        "Scanner snapshot: available=" .. QueueDiagnosticYesNo(snapshot.available)
            .. ", readable lines=" .. tostring(snapshot.lineCount)
            .. ", item data cached=" .. QueueDiagnosticYesNo(snapshot.itemDataCached)
            .. ", ready=" .. QueueDiagnosticYesNo(snapshot.ready),
        "Scanner state: " .. tostring(snapshot.reason),
        "Normalized scanner data: " .. (decision.tooltip ~= "" and decision.tooltip or "<empty>"),
        "Normalized scanner lines:",
    }
    if #snapshot.lines == 0 then
        lines[#lines + 1] = "  <none>"
    else
        for _, line in ipairs(snapshot.lines) do
            local rendered = "  " .. tostring(line.index) .. ": " .. (line.left ~= "" and line.left or "<empty>")
            if line.right ~= "" then rendered = rendered .. "  ||  " .. line.right end
            lines[#lines + 1] = rendered
        end
    end
    local requirements = snapshot.combinationRequirements
    lines[#lines + 1] = "Recipe requirements (C_Item.GetItemSpell -> C_TradeSkillUI.GetRecipeSchematic):"
    if requirements then
        lines[#lines + 1] = "  Use spell: " .. tostring(requirements.spellID or "<pending>")
            .. "; ready=" .. QueueDiagnosticYesNo(requirements.ready) .. "; " .. requirements.reason
        for _, row in ipairs(requirements.rows) do
            local names = {}
            for _, reagent in ipairs(row.alternatives) do
                names[#names + 1] = (reagent.name or "<uncached name>")
                    .. " [" .. (reagent.itemID and "item " .. tostring(reagent.itemID) or "currency " .. tostring(reagent.currencyID))
                    .. "]=" .. tostring(reagent.count or "<pending>")
            end
            lines[#lines + 1] = "  " .. table.concat(names, " + ")
                .. "; carried/required=" .. tostring(row.owned) .. "/" .. tostring(row.required)
        end
    else
        lines[#lines + 1] = "  Not a recognized Combine/Reform item."
    end
    lines[#lines + 1] = "Early checks:"
    lines[#lines + 1] = "  Bag slot locked (excluded by scan): " .. QueueDiagnosticYesNo(item.isLocked)
    lines[#lines + 1] = "  Item present: " .. QueueDiagnosticYesNo(decision.checks.itemPresent)
    lines[#lines + 1] = "  Permanently banned: " .. QueueDiagnosticYesNo(decision.checks.permanentlyBanned)
    lines[#lines + 1] = "  Hidden until reload: " .. QueueDiagnosticYesNo(decision.checks.sessionBanned)
    lines[#lines + 1] = "  Temporary incomplete-combination block: " .. QueueDiagnosticYesNo(decision.checks.automaticCombinationBan)
    lines[#lines + 1] = "  Tooltip ready: " .. QueueDiagnosticYesNo(decision.checks.tooltipReady)
    lines[#lines + 1] = "  Recipe requirements pending: " .. QueueDiagnosticYesNo(decision.checks.requirementsPending)
    lines[#lines + 1] = "  Darkmoon requirements incomplete: " .. QueueDiagnosticYesNo(decision.checks.incompleteDarkmoon)
    lines[#lines + 1] = "  Combine/Reform requirements incomplete: " .. QueueDiagnosticYesNo(decision.checks.incompleteCombination)
    lines[#lines + 1] = "  Already complete or hidden: " .. QueueDiagnosticYesNo(decision.checks.completed)
    lines[#lines + 1] = "  Usable: " .. QueueDiagnosticYesNo(decision.checks.usable)
    lines[#lines + 1] = "Category matches:"
    for _, category in ipairs(decision.categoryMatches) do
        lines[#lines + 1] = "  " .. tostring(category.priority) .. ". " .. ITEM_QUEUE_TYPES[category.key].label
            .. " — match=" .. QueueDiagnosticYesNo(category.matched)
            .. ", enabled=" .. QueueDiagnosticYesNo(category.enabled)
    end
    lines[#lines + 1] = "Final decision: " .. decision.reason
    if decision.category then
        lines[#lines + 1] = "Final category / priority: " .. ITEM_QUEUE_TYPES[decision.category].label .. " / " .. tostring(decision.priority)
    else
        lines[#lines + 1] = "Final category / priority: <not queued>"
    end
    local last = itemQueueLastDecisions[tostring(bag) .. ":" .. tostring(slot)]
    if last and last.itemID == item.itemID then
        lines[#lines + 1] = "LAST ACTUAL SCAN: " .. tostring(last.scanResult or last.reason)
        lines[#lines + 1] = "  Scanner text: " .. last.tooltip
        lines[#lines + 1] = "  Category: " .. tostring(last.category or "<none>")
    else
        lines[#lines + 1] = "LAST ACTUAL SCAN: no retained decision for this item/slot."
    end
    local displayed = itemQueueButton and itemQueueButton._queueItem
    lines[#lines + 1] = "Displayed item: " .. (displayed and tostring(displayed.itemID) .. " at "
        .. tostring(displayed.bag) .. ":" .. tostring(displayed.slot) .. " as " .. displayed.category or "<none>")
    if displayed and displayed.decision then
        lines[#lines + 1] = "  Admission text: " .. displayed.decision.tooltip
    end
    lines[#lines + 1] = "Combat refresh deferred: " .. QueueDiagnosticYesNo(itemQueueRefreshAfterCombat)
    return table.concat(lines, "\n")
end

local function SetItemQueueAuditButtonText(button, text)
    if not button then return end
    local label = button._waffleHouseLabel
    if not label and button.GetRegions then
        for index = 1, select("#", button:GetRegions()) do
            local region = select(index, button:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                label = region
                button._waffleHouseLabel = label
                break
            end
        end
    end
    if label then label:SetText(text) end
end

local function ShowItemQueueDiagnosticsReport(anchor, summary)
    if EllesmereUI and EllesmereUI.ShowCopyPopup then
        EllesmereUI:ShowCopyPopup("Item Queue Diagnostics", "Recognized bag items and their queue result.", summary)
    elseif EllesmereUI and EllesmereUI.BuildCogPopup then
        local _, show = EllesmereUI.BuildCogPopup({ title = "Item Queue Diagnostics", minWidth = 500, rows = {{ type = "input", label = "Audit", inputWidth = 350, get = function() return summary end, set = function() end }} })
        show(anchor or EllesmereUI._mainFrame or UIParent)
    end
end

local function GetItemQueueDiagnosticTarget(input)
    input = tostring(input or "")
    local bag, slot = input:match("^%s*(-?%d+)%s+(-?%d+)%s*$")
    if bag and slot then
        bag, slot = tonumber(bag), tonumber(slot)
        local item = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        if item and item.itemID then return item, bag, slot end
        return nil, nil, nil, "No item was found in bag " .. tostring(bag) .. ", slot " .. tostring(slot) .. "."
    end

    local itemID = tonumber(input:match("^%s*(%d+)%s*$"))
    if itemID and C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        local bags = {}
        for index = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = index end
        if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
        for _, candidateBag in ipairs(bags) do
            for candidateSlot = 1, (C_Container.GetContainerNumSlots(candidateBag) or 0) do
                local item = C_Container.GetContainerItemInfo(candidateBag, candidateSlot)
                if item and item.itemID == itemID then return item, candidateBag, candidateSlot end
            end
        end
        return nil, nil, nil, "Item ID " .. tostring(itemID) .. " is not in an unlocked bag slot."
    end

    local nameNeedle = input:match("^%s*(.-)%s*$"):lower()
    if nameNeedle ~= "" and C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        local bags = {}
        for index = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = index end
        if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
        for _, candidateBag in ipairs(bags) do
            for candidateSlot = 1, (C_Container.GetContainerNumSlots(candidateBag) or 0) do
                local item = C_Container.GetContainerItemInfo(candidateBag, candidateSlot)
                if item and item.itemID then
                    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.itemID)
                    name = name or (item.hyperlink and item.hyperlink:match("%[(.-)%]"))
                    if IsSafeText(name) and name:lower():find(nameNeedle, 1, true) then
                        return item, candidateBag, candidateSlot
                    end
                end
            end
        end
        return nil, nil, nil, "No bag item name contains '" .. input .. "'."
    end

    if input:match("^%s*$") and itemQueueButton and itemQueueButton._queueItem then
        local item = itemQueueButton._queueItem
        return item, item.bag, item.slot
    end
    return nil, nil, nil, "No displayed queue item is available. Use /whqueue <bag> <slot>, /whqueue <itemID>, or /whqueue <item name>."
end

local function ShowCurrentItemQueueDiagnostics(input)
    local item, bag, slot, failure = GetItemQueueDiagnosticTarget(input)
    if not item then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff8040Waffle House:|r " .. failure) end
        return
    end
    local report = BuildItemQueueDiagnosticDetails(item, bag, slot)
    ShowItemQueueDiagnosticsReport(itemQueueButton or UIParent, report)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r Item Queue diagnostics opened for bag " .. tostring(bag) .. ", slot " .. tostring(slot) .. ".")
    end
end

SLASH_WAFFLEHOUSEQUEUE1 = "/whqueue"
SlashCmdList.WAFFLEHOUSEQUEUE = function(input)
    ShowCurrentItemQueueDiagnostics(input)
end

ShowItemQueueDiagnostics = function(anchor)
    if itemQueueAuditRunning then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        SetItemQueueAuditButtonText(anchor, "Unavailable")
        C_Timer.After(1, function() SetItemQueueAuditButtonText(anchor, "Inspect Bags") end)
        return
    end

    itemQueueAuditRunning = true
    if anchor and anchor.Disable then anchor:Disable() end
    SetItemQueueAuditButtonText(anchor, "Inspecting")

    local lines, found = { "BAG QUEUE AUDIT" }, 0
    local bags = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end

    -- Work through a few slots per tick so the button has time to communicate
    -- real progress instead of looking like a dead control during a full audit.
    local bagIndex, slot, ticks, scanComplete = 1, 1, 0, false
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        ticks = ticks + 1
        local dots = math.floor(ticks / 4) % 4
        SetItemQueueAuditButtonText(anchor, "Inspecting" .. string.rep(".", dots))

        local inspected = 0
        while inspected < 12 and bagIndex <= #bags do
            local bag = bags[bagIndex]
            local slotCount = C_Container.GetContainerNumSlots(bag) or 0
            if slot > slotCount then
                bagIndex, slot = bagIndex + 1, 1
            else
                local item = C_Container.GetContainerItemInfo(bag, slot)
                if item and item.itemID and not item.isLocked then
                    local ok, status = pcall(GetQueueItemDiagnostic, item, bag, slot)
                    if ok and status then
                        found = found + 1
                        lines[#lines + 1] = GetQueueItemName(item) .. " [" .. tostring(item.itemID) .. "] — " .. status
                    elseif not ok then
                        lines[#lines + 1] = "Item " .. tostring(item.itemID) .. " could not be inspected."
                    end
                end
                slot = slot + 1
                inspected = inspected + 1
            end
        end
        scanComplete = bagIndex > #bags

        -- Let the user see the three-dot state even when their bags are tiny.
        if scanComplete and ticks >= 12 then
            ticker:Cancel()
            itemQueueAuditRunning = nil
            if found == 0 then
                lines[#lines + 1] = "No collection, recipe, knowledge, housing, combination, box, or pinned candidates were found in your bags."
            end
            if anchor and anchor.Enable then anchor:Enable() end
            SetItemQueueAuditButtonText(anchor, "Inspect Bags")
            ShowItemQueueDiagnosticsReport(anchor, table.concat(lines, "\n"))
        end
    end)
end

local function ShowItemQueueTooltip(button)
    local item = button and button._queueItem
    if not (item and GameTooltip) then return end

    -- Rebuild rather than append to the existing tooltip.  The queue can
    -- advance while the pointer remains on the button after a left-click.
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:SetBagItem(item.bag, item.slot)
    GameTooltip:AddLine("Right-Click: hide until reload", 1, 0.82, 0.48)
    GameTooltip:AddLine("Shift-Right-Click: permanently ban", 1, 0.45, 0.45)
    GameTooltip:Show()
end

local function SetItemQueueActionState(button, state)
    if not button then return end
    local r, g, b
    if state == "hover" then
        r, g, b = ACCENT_R, ACCENT_G, ACCENT_B
        if button._queueBg then button._queueBg:SetColorTexture(0.035, 0.105, 0.09, 0.94) end
    elseif state == "pressed" then
        r, g, b = 0.30, 0.66, 1.00
        if button._queueBg then button._queueBg:SetColorTexture(0.045, 0.085, 0.14, 0.98) end
    else
        r, g, b = 1, 1, 1
        if button._queueBg then button._queueBg:SetColorTexture(0.025, 0.035, 0.045, 0.84) end
    end

    -- Idle is deliberately neutral: only an actual hover or click colorizes
    -- the top/bottom rules and icon border.  The main popup has no side rail.
    if button._queueIconBorder then
        local base = button._queueItemColor
        if state == "idle" and base then
            button._queueIconBorder:SetColor(base.r, base.g, base.b, 0.90)
        else
            button._queueIconBorder:SetColor(r, g, b, 1)
        end
    end
    if button._queueTopRule then button._queueTopRule:SetColorTexture(r, g, b, state == "idle" and 0.10 or 0.92) end
    if button._queueBottomRule then button._queueBottomRule:SetColorTexture(r, g, b, state == "idle" and 0.10 or 0.92) end
    if state == "idle" then
        local base = button._queueItemColor
        if button._queueTitle then button._queueTitle:SetTextColor(1, 1, 1, 0.92) end
        if button._queueSub then button._queueSub:SetTextColor(base and base.r or 1, base and base.g or 1, base and base.b or 1, 0.68) end
    else
        if button._queueTitle then button._queueTitle:SetTextColor(r, g, b, 1) end
        -- The category is an item-quality cue, not a button-state cue.  Keep
        -- it stable while the item name and borders communicate interaction.
        local base = button._queueItemColor
        if button._queueSub then button._queueSub:SetTextColor(base and base.r or 1, base and base.g or 1, base and base.b or 1, 0.68) end
    end

    local stateLine = button._queueActionStateLine
    if stateLine then
        stateLine:SetColorTexture(r, g, b, state == "idle" and 0.16 or 1)
    end
end

local function HideItemQueueTooltip(button)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then
        GameTooltip:Hide()
    end
end

UpdateItemQueueCombatVisibility = function()
    if not itemQueueCombatGate or (InCombatLockdown and InCombatLockdown()) then return end

    local current = itemQueueButton and itemQueueButton._queueItem
    local combination = current and current.decision and current.decision.tooltipSnapshot.combinationRequirements
    local hideInCombat = GetItemQueueSettings().hideInCombat == true or combination ~= nil
    if itemQueueCombatGate._waffleHideInCombat == hideInCombat then return end
    if UnregisterStateDriver then
        UnregisterStateDriver(itemQueueCombatGate, "visibility")
    end
    if hideInCombat and RegisterStateDriver then
        -- The gate is state-driven by Blizzard's secure visibility handler;
        -- Waffle House never attempts an unsafe Show/Hide on the action
        -- button while combat is active.
        RegisterStateDriver(itemQueueCombatGate, "visibility", "[combat] hide; show")
    else
        itemQueueCombatGate:Show()
    end
    itemQueueCombatGate._waffleHideInCombat = hideInCombat
end

local function EnsureItemQueueButton()
    if itemQueueButton then return itemQueueButton end

    -- Let the client perform the actual item action.  This uses a secure
    -- /use bag-slot macro rather than SecureActionButton's `item` action:
    -- Blizzard's `item` action silently equips any equippable item before it
    -- considers Use, which breaks cosmetic shield and weapon unlock tokens.
    local combatGate = CreateFrame("Frame", "WaffleHouseItemQueueCombatGate", UIParent, "SecureHandlerStateTemplate")
    combatGate:SetAllPoints(UIParent)
    itemQueueCombatGate = combatGate
    local button = CreateFrame("Button", "WaffleHouseItemQueueButton", combatGate, "SecureActionButtonTemplate")
    button:SetSize(220, 36)
    button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 168)
    -- Keep it in the normal HUD layer so vendor, character, map, and dialog
    -- windows naturally render over it instead of being obscured by it.
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(5)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    -- Do not inherit the player's action-bar key-down preference here: this
    -- button is deliberately registered for the mouse-up click that opens it.
    button:SetAttribute("useOnKeyDown", false)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.025, 0.035, 0.045, 0.84)
    button._queueBg = bg

    local topRule = button:CreateTexture(nil, "ARTWORK")
    topRule:SetHeight(1)
    topRule:SetPoint("TOPLEFT")
    topRule:SetPoint("TOPRIGHT")
    topRule:SetColorTexture(1, 1, 1, 0.10)
    button._queueTopRule = topRule
    local bottomRule = button:CreateTexture(nil, "ARTWORK")
    bottomRule:SetHeight(1)
    bottomRule:SetPoint("BOTTOMLEFT")
    bottomRule:SetPoint("BOTTOMRIGHT")
    bottomRule:SetColorTexture(1, 1, 1, 0.10)
    button._queueBottomRule = bottomRule

    local iconSlot = CreateFrame("Frame", nil, button)
    iconSlot:SetSize(28, 28)
    iconSlot:SetPoint("LEFT", button, "LEFT", 4, 0)
    iconSlot:SetFrameLevel(button:GetFrameLevel() + 1)
    local iconSlotBackground = iconSlot:CreateTexture(nil, "BACKGROUND")
    iconSlotBackground:SetAllPoints()
    iconSlotBackground:SetColorTexture(0.02, 0.025, 0.03, 0.78)
    -- EUI's pixel-snapped HUD border keeps all four sides precisely one
    -- physical pixel wide, including when the UI scale is fractional.
    button._queueIconBorder = EllesmereUI.MakeBorder(iconSlot, 0.30, 0.30, 0.30, 0.95)
    local icon = iconSlot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconSlot, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", iconSlot, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button._queueIconSlot = iconSlot
    button._queueIcon = icon

    local title = button:CreateFontString(nil, "OVERLAY")
    SetFont(title, 11)
    title:SetPoint("TOPLEFT", iconSlot, "TOPRIGHT", 8, -5)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    button._queueTitle = title

    local sub = button:CreateFontString(nil, "OVERLAY")
    SetFont(sub, 9)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(1, 1, 1, 0.48)
    button._queueSub = sub

    -- The action cue intentionally stays quiet beside the item name.  A
    -- single state line carries hover/press feedback without turning USE into
    -- a second decorative logo.
    local action = button:CreateFontString(nil, "OVERLAY", nil, 4)
    SetFont(action, 11)
    action:SetPoint("RIGHT", button, "RIGHT", -9, 0)
    action:SetText("USE")
    action:SetTextColor(1, 1, 1, 0.80)
    button._queueAction = action
    local actionStateLine = button:CreateTexture(nil, "OVERLAY", nil, 3)
    actionStateLine:SetSize(math.max(17, math.ceil(action:GetStringWidth())), 1)
    -- Leave one physical pixel of padding below the FontString.  The cue must
    -- not cross the letter glyphs at fractional UI scale.
    actionStateLine:SetPoint("TOP", action, "BOTTOM", 0, -1)
    actionStateLine:SetColorTexture(1, 1, 1, 0.16)
    button._queueActionStateLine = actionStateLine

    local actionDivider = button:CreateTexture(nil, "ARTWORK")
    actionDivider:SetWidth(1)
    actionDivider:SetHeight(16)
    actionDivider:SetPoint("RIGHT", action, "LEFT", -9, 0)
    actionDivider:SetColorTexture(1, 1, 1, 0.08)
    title:SetPoint("RIGHT", actionDivider, "LEFT", -9, 0)
    sub:SetPoint("RIGHT", actionDivider, "LEFT", -9, 0)

    button:SetScript("OnEnter", function(self)
        self._queueHovered = true
        SetItemQueueActionState(self, "hover")
        ShowItemQueueTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self._queueHovered = nil
        SetItemQueueActionState(self, "idle")
        HideItemQueueTooltip(self)
    end)
    button:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            SetItemQueueActionState(self, "pressed")
        end
    end)
    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            if self:IsMouseOver() then
                SetItemQueueActionState(self, "hover")
            else
                SetItemQueueActionState(self, "idle")
            end
        end
    end)
    -- Hook rather than replace the template's click script: its inherited
    -- handler is what performs the secure left-click item action.
    button:HookScript("OnClick", function(self, mouseButton, down)
        if down then return end
        local item = self._queueItem
        if not item then return end
        if mouseButton == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
            GetItemQueueSettings().bannedItems[item.itemID] = true
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(item.name .. " banned from Item Queue.", 1, 0.35, 0.35, 1)
            end
            RefreshItemQueue({ [item.itemID] = true })
            return
        end
        if mouseButton == "RightButton" then
            sessionBannedItems[item.itemID] = true
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(item.name .. " hidden until reload.", 1, 0.82, 0.48, 1)
            end
            RefreshItemQueue({ [item.itemID] = true })
            return
        end
        if mouseButton == "LeftButton" and C_Timer then
            -- The secure action has already run.  Scan after it so consumed,
            -- learned, and opened items naturally disappear or advance.
            C_Timer.After(0, function() RefreshItemQueue("bags", { [item.itemID] = true }) end)
        end
    end)
    button:Hide()
    itemQueueButton = button
    UpdateItemQueueCombatVisibility()
    return button
end

local function GetQueueItemColor(item)
    if type(item.quality) == "number" then
        if C_Item and type(C_Item.GetItemQualityColor) == "function" then
            local r, g, b = C_Item.GetItemQualityColor(item.quality)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
        local qualityColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if qualityColor then return qualityColor.r, qualityColor.g, qualityColor.b end
    end
    return GetItemQueueColor(item.category)
end

RefreshItemQueue = function(itemIDs, invalidatedItems)
    itemQueueCache.followupItems = {}
    -- Creating, showing, hiding, resizing or rearming this protected action
    -- button is forbidden in combat. Its pre-registered secure visibility
    -- driver hides combination items; rebuild them when combat ends.
    if InCombatLockdown and InCombatLockdown() then
        itemQueueRefreshAfterCombat = true
        if itemQueueButton then
            itemQueueButton._queueHovered = nil
            HideItemQueueTooltip(itemQueueButton)
        end
        return
    end
    local button = EnsureItemQueueButton()
    local queue = GetItemQueueSettings()
    if not queue.enabled then
        itemQueueCandidates = {}
        itemQueueCache.samples = nil
        itemQueueCache.items = {}
        itemQueueCache.tooltipInstances = {}
        itemQueueTooltipRetryPending.items = {}
        button._queueItem = nil
        button._secureItemID, button._secureBag, button._secureSlot = nil, nil, nil
        button:SetAttribute("type1", nil)
        button:SetAttribute("macrotext1", nil)
        button._queueHovered = nil
        HideItemQueueTooltip(button)
        button:Hide()
        return
    end

    itemQueueCandidates = ScanItemQueue(itemIDs, invalidatedItems)
    local item = itemQueueCandidates[1]
    if item and not itemQueueCache.SameSlot(item.slotInfo, C_Container.GetContainerItemInfo(item.bag, item.slot)) then
        -- A different cached candidate may have moved before BAG_UPDATE_DELAYED.
        -- Never arm a secure /use action from an unverified cached slot.
        itemQueueCache.dirtyBags = {}
        itemQueueCandidates = ScanItemQueue("bags", type(itemIDs) == "table" and itemIDs or invalidatedItems)
        item = itemQueueCandidates[1]
    end
    if not item then
        button._queueItem = nil
        button._secureItemID, button._secureBag, button._secureSlot = nil, nil, nil
        button:SetAttribute("type1", nil)
        button:SetAttribute("macrotext1", nil)
        button._queueHovered = nil
        HideItemQueueTooltip(button)
        button:Hide()
        return
    end

    local r, g, b = GetQueueItemColor(item)
    if not (InCombatLockdown and InCombatLockdown()) then
        button:SetAttribute("type1", "macro")
        -- Address the exact occupied bag slot.  `/use` deliberately skips
        -- the secure-button item's auto-equip branch and executes the item's
        -- own Use action, including Warband appearance unlocks.
        local combination = item.decision and item.decision.tooltipSnapshot.combinationRequirements
        button:SetAttribute("macrotext1", "/use " .. (combination and "[nocombat] " or "") .. tostring(item.bag) .. " " .. tostring(item.slot))
        button:SetAttribute("item1", nil)
        button:SetAttribute("type2", nil)
        button:SetAttribute("item2", nil)
        button:SetAttribute("macrotext2", nil)
        button._secureItemID = item.itemID
        button._secureBag = item.bag
        button._secureSlot = item.slot
    end
    button._queueItem = item
    UpdateItemQueueCombatVisibility()
    button._queueItemColor = { r = r, g = g, b = b }
    button._queueIcon:SetTexture(item.icon)
    button._queueTitle:SetText(item.name)
    button._queueSub:SetText(ITEM_QUEUE_TYPES[item.category].label)
    if not (InCombatLockdown and InCombatLockdown()) then
        local textWidth = math.max(button._queueTitle:GetStringWidth(), button._queueSub:GetStringWidth())
        local fixedWidth = 70 + button._queueAction:GetStringWidth()
        local availableWidth = math.max(220, (UIParent:GetWidth() or 220) - 40)
        button:SetWidth(math.min(availableWidth, math.max(220, math.ceil(textWidth + fixedWidth))))
    end
    SetItemQueueActionState(button, button._queueHovered and "hover" or "idle")
    button:Show()
    if button._queueHovered then ShowItemQueueTooltip(button) end
end

function itemQueueCache.BagChanged(bag)
    if not IsSafeNumber(bag) or not (bag >= 0 and bag <= (NUM_BAG_SLOTS or 4)
        or (Enum and Enum.BagIndex and bag == Enum.BagIndex.ReagentBag)) then return end
    itemQueueCache.dirtyBags[bag] = true
    local button = itemQueueButton
    local item = button and button._queueItem
    if not item or item.bag ~= bag then return end
    if InCombatLockdown and InCombatLockdown() then
        itemQueueRefreshAfterCombat = true
        return
    end
    if itemQueueCache.SameSlot(item.slotInfo, C_Container.GetContainerItemInfo(item.bag, item.slot)) then return end
    -- Disarm a changed/locked slot immediately; the debounced scan can safely
    -- choose the next item once the bag update batch has finished.
    button:SetAttribute("type1", nil)
    button:SetAttribute("macrotext1", nil)
    button._queueItem = nil
    button._secureItemID, button._secureBag, button._secureSlot = nil, nil, nil
    button._queueHovered = nil
    HideItemQueueTooltip(button)
    button:Hide()
end

local function ScheduleItemQueueRefresh(itemIDs)
    if type(itemIDs) == "table" then
        local tracked = {}
        for itemID in pairs(itemIDs) do
            if itemQueueCache.items[itemID] then tracked[itemID] = true end
        end
        if not next(tracked) then return end
        itemIDs = tracked
    end
    if not GetItemQueueSettings().enabled then return end
    if InCombatLockdown and InCombatLockdown() then
        itemQueueRefreshAfterCombat = true
        return
    end
    itemQueueTooltipRetryPending.attempt = 0
    local pending = itemQueueRefreshPending or { items = {} }
    if not itemIDs then pending.full = true
    elseif itemIDs == "bags" then pending.bags = true
    else
        for itemID in pairs(itemIDs) do pending.items[itemID] = true end
    end
    if itemQueueRefreshPending then return end
    itemQueueRefreshPending = pending
    -- Batch notifications across frames as item data arrives in bursts.
    C_Timer.After(0.1, function()
        itemQueueRefreshPending = nil
        if pending.full then RefreshItemQueue()
        elseif pending.bags then
            -- Bag reconciliation must also honor item data invalidations that
            -- arrived in the same batch, even if their slots did not move.
            RefreshItemQueue("bags", pending.items)
        else RefreshItemQueue(pending.items) end

        if not next(itemQueueCache.followupItems) then return end
        local followup = itemQueueFollowupRefreshPending or {}
        for itemID in pairs(itemQueueCache.followupItems) do followup[itemID] = true end
        if itemQueueFollowupRefreshPending then return end
        itemQueueFollowupRefreshPending = followup
        -- Only changed inventory slots, incomplete data, and combination
        -- requirements need the delayed hydration check. Never rescan all bags.
        C_Timer.After(0.4, function()
            itemQueueFollowupRefreshPending = nil
            RefreshItemQueue(followup)
        end)
    end)
end

local function GetMerchantCosts(merchantIndex)
    if not (IsSafeNumber(merchantIndex) and GetMerchantItemCostInfo and GetMerchantItemCostItem) then
        return {}
    end

    local count = GetMerchantItemCostInfo(merchantIndex)
    if not IsSafeNumber(count) or count <= 0 then
        return {}
    end

    local costs = {}
    for costIndex = 1, count do
        local texture, amount, link, currencyName = GetMerchantItemCostItem(merchantIndex, costIndex)
        local key = GetCostKey(texture, link)
        if key and IsSafeValue(texture) and IsSafeNumber(amount) then
            costs[#costs + 1] = {
                amount = amount,
                key = key,
                link = IsSafeText(link) and link or nil,
                name = GetCostName(link, currencyName),
                color = GetCostColor(link),
                texture = texture,
            }
        end
    end
    return costs
end

local function GetOwnedCostAmount(cost)
    if not (cost and IsSafeText(cost.link)) then return nil end

    local currencyID = cost.link:match("|Hcurrency:(%d+)") or cost.link:match("currency:(%d+)")
    if currencyID then
        currencyID = tonumber(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
            local info = C_CurrencyInfo.GetCurrencyInfoFromLink(cost.link)
            if info and IsSafeNumber(info.quantity) then
                return info.quantity
            end
        end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info and IsSafeNumber(info.quantity) then
                return info.quantity
            end
        elseif GetCurrencyInfo then
            local _, quantity = GetCurrencyInfo(currencyID)
            if IsSafeNumber(quantity) then
                return quantity
            end
        end
    elseif GetItemCount then
        local quantity = GetItemCount(cost.link)
        if IsSafeNumber(quantity) then
            return quantity
        end
    end
end

local function CollectVendorCosts()
    local entries, entriesByKey, costsByMerchant = {}, {}, {}
    local itemCount = GetMerchantNumItems and GetMerchantNumItems()
    if not IsSafeNumber(itemCount) then
        return entries, costsByMerchant
    end

    for merchantIndex = 1, itemCount do
        local costs = GetMerchantCosts(merchantIndex)
        if #costs > 0 then
            costsByMerchant[merchantIndex] = costs
            local keysSeen = {}
            for _, cost in ipairs(costs) do
                local entry = entriesByKey[cost.key]
                if not entry then
                    entry = {
                        count = 0,
                        key = cost.key,
                        link = cost.link,
                        name = cost.name,
                        color = cost.color,
                        owned = GetOwnedCostAmount(cost),
                        texture = cost.texture,
                    }
                    entriesByKey[cost.key] = entry
                    entries[#entries + 1] = entry
                end
                if not keysSeen[cost.key] then
                    entry.count = entry.count + 1
                    keysSeen[cost.key] = true
                end
            end
        end
    end

    return entries, costsByMerchant
end

local function TextureMarkup(texture, size)
    if not (IsSafeValue(texture) and (type(texture) == "number" or type(texture) == "string")) then
        return ""
    end
    return "|T" .. tostring(texture) .. ":" .. size .. ":" .. size .. ":0:0|t"
end

function addon.GetCurrencyIconGridLayout(panelWidth, entryCount)
    local usableWidth = math.max(addon.CurrencyGrid.size,
        math.floor(tonumber(panelWidth) or addon.CurrencyGrid.size) - (addon.CurrencyGrid.gutter * 2))
    local columns = math.max(1, math.floor((usableWidth + addon.CurrencyGrid.gap) / (addon.CurrencyGrid.size + addon.CurrencyGrid.gap)))
    local rows = entryCount > 0 and math.ceil(entryCount / columns) or 0
    local height = rows > 0 and ((addon.CurrencyGrid.gutter * 2) + (rows * addon.CurrencyGrid.size)
        + ((rows - 1) * addon.CurrencyGrid.gap)) or 0
    return columns, rows, height
end

local function SetRowState(row)
    local active = selectedCostKey and row._costKey == selectedCostKey
    local textMode = IsTextMode()
    row._active = active
    row._indicator:SetShown(active and textMode)
    local textR, textG, textB = 1, 1, 1
    if textMode then
        textR, textG, textB = ColorComponents(row._color)
    end
    if active then
        -- A currency selection is a filter state, so make it clearly distinct
        -- from the quiet alternating scan rows without bringing back a heavy
        -- full-row outline.
        row._background:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, textMode and 0.32 or 0.22)
        row._indicator:SetWidth(3)
        row._label:SetTextColor(textR, textG, textB, 1)
        row._count:SetTextColor(textR, textG, textB, 0.96)
        for _, edge in ipairs(row._iconBorders) do edge:SetColorTexture(textR, textG, textB, 0.98) end
    else
        row._indicator:SetWidth(2)
        if textMode and GetSettings().legendAlternatingRows ~= false then
            local alpha = (row._legendIndex or 0) % 2 == 0 and 0.30 or 0.13
            row._background:SetColorTexture(0.03, 0.045, 0.055, alpha)
        elseif textMode then
            row._background:SetColorTexture(1, 1, 1, 0)
        else
            row._background:SetColorTexture(0.03, 0.045, 0.055, 0.86)
        end
        row._label:SetTextColor(textR, textG, textB, 0.82)
        row._count:SetTextColor(textR, textG, textB, textMode and 0.84 or 0.96)
        for _, edge in ipairs(row._iconBorders) do edge:SetColorTexture(textR, textG, textB, 0.82) end
    end
end

function addon.HideLegendCurrencyTooltip(row)
    if not row or not row._currencyTooltipShown then return end
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == row then GameTooltip:Hide() end
    row._currencyTooltipShown = nil
end

function addon.ShowLegendCurrencyTooltip(row)
    if not (row and GameTooltip and GameTooltip.SetOwner) then return end
    local link = row._costLink
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local shown = false
    local currencyID = IsSafeText(link) and tonumber(link:match("currency:(%d+)")) or nil
    if currencyID and GameTooltip.SetCurrencyByID then
        local ok = pcall(GameTooltip.SetCurrencyByID, GameTooltip, currencyID)
        shown = ok
    end
    if not shown and IsSafeText(link) and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        shown = ok
    end
    if not shown then
        GameTooltip:AddLine(row._currencyName or "Currency", 1, 1, 1)
        GameTooltip:AddDoubleLine("Owned", row._owned ~= nil and tostring(row._owned) or "?", 0.75, 0.75, 0.75, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: select this currency", ACCENT_R, ACCENT_G, ACCENT_B)
    GameTooltip:Show()
    row._currencyTooltipShown = true
end

function addon.UpdateLegendCurrencyTooltip(row)
    local wantsTooltip = row and row._legendHovering and not IsTextMode()
        and IsAltKeyDown and IsAltKeyDown()
    if wantsTooltip and not row._currencyTooltipShown then
        addon.ShowLegendCurrencyTooltip(row)
    elseif not wantsTooltip then
        addon.HideLegendCurrencyTooltip(row)
    end
end

local function CreateLegendRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")

    row._background = row:CreateTexture(nil, "BACKGROUND")
    row._background:SetAllPoints()
    row._indicator = row:CreateTexture(nil, "OVERLAY")
    row._indicator:SetWidth(2)
    row._indicator:SetPoint("TOPLEFT")
    row._indicator:SetPoint("BOTTOMLEFT")
    row._indicator:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    row._iconSlot = CreateFrame("Frame", nil, row)
    row._iconSlot:SetSize(22, 22)
    row._iconSlot:SetFrameLevel(row:GetFrameLevel() + 1)
    local slotBackground = row._iconSlot:CreateTexture(nil, "BACKGROUND")
    slotBackground:SetAllPoints()
    slotBackground:SetColorTexture(0.035, 0.045, 0.055, 0.96)
    row._iconBorders = {}
    local top = row._iconSlot:CreateTexture(nil, "OVERLAY", nil, 2)
    top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    local bottom = row._iconSlot:CreateTexture(nil, "OVERLAY", nil, 2)
    bottom:SetHeight(1); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    local left = row._iconSlot:CreateTexture(nil, "OVERLAY", nil, 2)
    left:SetWidth(1); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    local right = row._iconSlot:CreateTexture(nil, "OVERLAY", nil, 2)
    right:SetWidth(1); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    for _, edge in ipairs({ top, bottom, left, right }) do
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        edge:SetColorTexture(0.30, 0.30, 0.30, 0.95)
        row._iconBorders[#row._iconBorders + 1] = edge
    end
    row._icon = row._iconSlot:CreateTexture(nil, "ARTWORK")
    -- Vendor Bags renders each item icon into a physical 34px box.  The
    -- currency icon used to lose two pixels on every edge inside an otherwise
    -- matching slot, making it visibly smaller despite the matching border.
    -- Let the shared border draw over the icon instead, exactly as the item
    -- tiles do.
    row._icon:SetAllPoints(row._iconSlot)
    row._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._label = row:CreateFontString(nil, "OVERLAY")
    SetFont(row._label, 10)
    row._label:SetPoint("LEFT", row._iconSlot, "RIGHT", 7, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -25, 0)
    row._label:SetJustifyH("LEFT")
    row._label:SetWordWrap(false)
    row._count = row:CreateFontString(nil, "OVERLAY")
    SetFont(row._count, 9)
    row._count:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row._count:SetJustifyH("RIGHT")
    row._count:SetTextColor(0.65, 0.65, 0.65, 1)

    row:SetScript("OnEnter", function(self)
        self._legendHovering = true
        if not self._active then
            self._background:SetColorTexture(1, 1, 1, 0.06)
            for _, edge in ipairs(self._iconBorders) do edge:SetColorTexture(0.62, 0.62, 0.62, 1) end
        end
        addon.UpdateLegendCurrencyTooltip(self)
        self:SetScript("OnUpdate", addon.UpdateLegendCurrencyTooltip)
    end)
    row:SetScript("OnLeave", function(self)
        self._legendHovering = nil
        self:SetScript("OnUpdate", nil)
        addon.HideLegendCurrencyTooltip(self)
        SetRowState(self)
    end)
    row:SetScript("OnClick", function(self)
        -- _active is updated from the live legend state immediately before
        -- display.  Prefer it over raw key equality so the same row always
        -- behaves as a reliable second-click deselect after a refresh.
        if self._active or selectedCostKey == self._costKey then
            selectedCostKey = nil
        else
            selectedCostKey = self._costKey
        end
        if panel then
            for _, entry in ipairs(panel.rows) do
                if entry:IsShown() then
                    SetRowState(entry)
                end
            end
        end
        if addon.Refresh then
            addon.Refresh()
        end
    end)
    return row
end

-- The compact currency header uses square checks only for persistent on/off
-- states.  One-shot actions get a small, recognizable mark in that same
-- leading position so their labels do not look as though a checkbox failed to
-- render beside them.
function addon.CreatePanelActionIcon(button, kind)
    local anchor = CreateFrame("Frame", nil, button)
    anchor:SetSize(12, 12)
    anchor:SetPoint("LEFT", button, "LEFT", 1, 0)
    button._waffleActionIconAnchor = anchor
    button._waffleActionIconParts = {}

    if kind == "plan" then
        local pin = anchor:CreateTexture(nil, "ARTWORK")
        pin:SetAllPoints()
        pin:SetTexture("Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\vendor-pin-off.tga")
        button._waffleActionIconParts[#button._waffleActionIconParts + 1] = pin
    elseif kind == "mode" then
        -- Three short strokes read as a text/list-mode mark even at the
        -- deliberately small vendor-header scale.
        for index, width in ipairs({ 10, 8, 11 }) do
            local line = anchor:CreateTexture(nil, "ARTWORK")
            line:SetSize(width, 1)
            line:SetPoint("LEFT", anchor, "LEFT", 1, 0)
            line:SetPoint("TOP", anchor, "TOP", 0, -((index - 1) * 4 + 1))
            line._waffleActionColorFill = true
            button._waffleActionIconParts[#button._waffleActionIconParts + 1] = line
        end
    elseif kind == "clear" then
        local close = anchor:CreateFontString(nil, "ARTWORK")
        SetFont(close, 11)
        close:SetAllPoints()
        close:SetJustifyH("CENTER")
        close:SetText("×")
        button._waffleActionIconParts[#button._waffleActionIconParts + 1] = close
    end

    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -3, 0)
    button.label:SetJustifyH("LEFT")
end

function addon.SetPanelActionColor(button, r, g, b)
    if button.label then button.label:SetTextColor(r, g, b, 1) end
    for _, part in ipairs(button._waffleActionIconParts or {}) do
        if part._waffleActionColorFill then
            part:SetColorTexture(r, g, b, 1)
        elseif part.SetVertexColor then
            part:SetVertexColor(r, g, b, 1)
        elseif part.SetTextColor then
            part:SetTextColor(r, g, b, 1)
        end
    end
end

local function EnsurePanel(frame)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, frame)
    panel:SetFrameLevel(frame:GetFrameLevel() + 6)
    panel.rows = {}

    panel.background = panel:CreateTexture(nil, "BACKGROUND")
    panel.background:SetAllPoints()
    -- Let the Vendor Bags frame's own skin show through instead of layering an
    -- unrelated black rectangle over it.
    panel.background:SetColorTexture(0, 0, 0, 0)
    panel.topBorder = panel:CreateTexture(nil, "ARTWORK")
    panel.topBorder:SetHeight(1)
    panel.topBorder:SetPoint("TOPLEFT")
    panel.topBorder:SetPoint("TOPRIGHT")
    panel.topBorder:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.55)
    panel.bottomBorder = panel:CreateTexture(nil, "ARTWORK")
    panel.bottomBorder:SetHeight(1)
    panel.bottomBorder:SetPoint("BOTTOMLEFT")
    panel.bottomBorder:SetPoint("BOTTOMRIGHT")
    panel.bottomBorder:SetColorTexture(1, 1, 1, 0.11)

    panel.title = panel:CreateFontString(nil, "OVERLAY")
    SetFont(panel.title, 10)
    panel._waffleTitleLeft = 28
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", panel._waffleTitleLeft, -6)
    panel.title:SetText("CURRENCIES")
    panel.title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    -- Keep the collapsible section control with its heading rather than in the
    -- right-side action strip.  The heading remains visible as the restore
    -- affordance after its currency rows are collapsed.
    panel.currencyCollapse = CreateFrame("Button", nil, panel)
    panel.currencyCollapse:SetSize(16, 16)
    panel.currencyCollapse:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -5)
    panel.currencyCollapse.label = panel.currencyCollapse:CreateFontString(nil, "OVERLAY")
    SetFont(panel.currencyCollapse.label, 12, "OUTLINE")
    panel.currencyCollapse.label:SetAllPoints()
    panel.currencyCollapse.label:SetJustifyH("CENTER")
    if panel.currencyCollapse.label.SetJustifyV then panel.currencyCollapse.label:SetJustifyV("MIDDLE") end
    panel.currencyCollapse:SetScript("OnEnter", function(self)
        self._hovering = true
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Collapse or expand the currency list. Vendor items and their costs stay visible.")
        end
        if addon.UpdateCurrencyLegendVisibilityControl then addon.UpdateCurrencyLegendVisibilityControl(panel) end
    end)
    panel.currencyCollapse:SetScript("OnLeave", function(self)
        self._hovering = nil
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        if addon.UpdateCurrencyLegendVisibilityControl then addon.UpdateCurrencyLegendVisibilityControl(panel) end
    end)
    panel.currencyCollapse:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.currencyLegendVisible = settings.currencyLegendVisible == false
        if addon.Refresh then addon.Refresh() end
    end)

    panel.mode = CreateFrame("Button", nil, panel)
    panel.mode:SetSize(43, TITLE_H)
    panel.mode:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, 0)
    panel.mode.label = panel.mode:CreateFontString(nil, "OVERLAY")
    SetFont(panel.mode.label, 9)
    addon.CreatePanelActionIcon(panel.mode, "mode")
    panel.mode:SetScript("OnEnter", function(self)
        addon.SetPanelActionColor(self, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Switch the currency legend between an icon grid and text rows.")
        end
    end)
    panel.mode:SetScript("OnLeave", function(self)
        addon.SetPanelActionColor(self, 0.75, 0.75, 0.75)
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    panel.mode:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.legendMode = settings.legendMode == "icon" and "text" or "icon"
        if addon.Refresh then
            addon.Refresh()
        end
    end)

    panel.filter = CreateFrame("Button", nil, panel)
    panel.filter:SetSize(62, TITLE_H)
    panel.filter:SetPoint("RIGHT", panel.mode, "LEFT", -3, 0)
    panel.filter._box = panel.filter:CreateTexture(nil, "ARTWORK")
    panel.filter._box:SetSize(12, 12)
    panel.filter._box:SetPoint("LEFT", panel.filter, "LEFT", 2, 0)
    panel.filter._check = panel.filter:CreateTexture(nil, "OVERLAY")
    panel.filter._check:SetSize(16, 16)
    panel.filter._check:SetPoint("CENTER", panel.filter._box, "CENTER")
    panel.filter._check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    panel.filter._edges = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", 12, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 12, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 12 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 12 },
    }) do
        local line = panel.filter:CreateTexture(nil, "OVERLAY")
        if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
        line:SetPoint(edge[1], panel.filter._box, edge[1])
        line:SetPoint(edge[2], panel.filter._box, edge[2])
        panel.filter._edges[#panel.filter._edges + 1] = line
    end
    panel.filter.label = panel.filter:CreateFontString(nil, "OVERLAY")
    SetFont(panel.filter.label, 8)
    panel.filter.label:SetPoint("LEFT", panel.filter._box, "RIGHT", 5, 0)
    panel.filter.label:SetText("FILTER")
    panel.filter:SetScript("OnEnter", function(self)
        self._hovering = true
        self.label:SetTextColor(1, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "With a currency selected, hide vendor items that do not use that currency. Click that currency again to restore the full list.")
        end
    end)
    panel.filter:SetScript("OnLeave", function(self)
        self._hovering = nil
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        local enabled = GetSettings().legendFilterItems == true
        self.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end)
    panel.filter:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.legendFilterItems = not settings.legendFilterItems
        if addon.Refresh then addon.Refresh() end
    end)

    panel.afford = CreateFrame("Button", nil, panel)
    panel.afford:SetSize(68, TITLE_H)
    panel.afford:SetPoint("RIGHT", panel.filter, "LEFT", -3, 0)
    panel.afford._box = panel.afford:CreateTexture(nil, "ARTWORK")
    panel.afford._box:SetSize(12, 12)
    panel.afford._box:SetPoint("LEFT", panel.afford, "LEFT", 2, 0)
    panel.afford._check = panel.afford:CreateTexture(nil, "OVERLAY")
    panel.afford._check:SetSize(16, 16)
    panel.afford._check:SetPoint("CENTER", panel.afford._box, "CENTER")
    panel.afford._check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    panel.afford._edges = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", 12, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 12, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 12 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 12 },
    }) do
        local line = panel.afford:CreateTexture(nil, "OVERLAY")
        if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
        line:SetPoint(edge[1], panel.afford._box, edge[1])
        line:SetPoint(edge[2], panel.afford._box, edge[2])
        panel.afford._edges[#panel.afford._edges + 1] = line
    end
    panel.afford.label = panel.afford:CreateFontString(nil, "OVERLAY")
    SetFont(panel.afford.label, 8)
    panel.afford.label:SetPoint("LEFT", panel.afford._box, "RIGHT", 5, 0)
    panel.afford.label:SetText("AFFORD")
    panel.afford:SetScript("OnEnter", function(self)
        self._hovering = true
        self.label:SetTextColor(1, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Hide vendor items you cannot currently afford. This checks gold and every listed currency cost.")
        end
    end)
    panel.afford:SetScript("OnLeave", function(self)
        self._hovering = nil
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        local enabled = GetSettings().legendAffordableOnly == true
        self.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end)
    panel.afford:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.legendAffordableOnly = not settings.legendAffordableOnly
        if addon.Refresh then addon.Refresh() end
    end)

    panel.plan = CreateFrame("Button", nil, panel)
    panel.plan:SetSize(43, TITLE_H)
    panel.plan:SetPoint("RIGHT", panel.afford, "LEFT", -3, 0)
    panel.plan.label = panel.plan:CreateFontString(nil, "OVERLAY")
    SetFont(panel.plan.label, 8)
    panel.plan.label:SetText("PLAN")
    addon.CreatePanelActionIcon(panel.plan, "plan")
    addon.SetPanelActionColor(panel.plan, 0.75, 0.75, 0.75)
    panel.plan:SetScript("OnEnter", function(self)
        addon.SetPanelActionColor(self, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Open the saved vendor shopping list and combined costs.")
        end
    end)
    panel.plan:SetScript("OnLeave", function(self)
        addon.SetPanelActionColor(self, 0.75, 0.75, 0.75)
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    panel.plan:SetScript("OnClick", function(self) ShowVendorPlan(self) end)

    panel.saved = CreateFrame("Button", nil, panel)
    panel.saved:SetSize(55, TITLE_H)
    panel.saved:SetPoint("RIGHT", panel.plan, "LEFT", -3, 0)
    panel.saved._box = panel.saved:CreateTexture(nil, "ARTWORK")
    panel.saved._box:SetSize(12, 12)
    panel.saved._box:SetPoint("LEFT", panel.saved, "LEFT", 2, 0)
    panel.saved._check = panel.saved:CreateTexture(nil, "OVERLAY")
    panel.saved._check:SetSize(16, 16)
    panel.saved._check:SetPoint("CENTER", panel.saved._box, "CENTER")
    panel.saved._check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    panel.saved._edges = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", 12, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 12, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 12 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 12 },
    }) do
        local line = panel.saved:CreateTexture(nil, "OVERLAY")
        if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
        line:SetPoint(edge[1], panel.saved._box, edge[1])
        line:SetPoint(edge[2], panel.saved._box, edge[2])
        panel.saved._edges[#panel.saved._edges + 1] = line
    end
    panel.saved.label = panel.saved:CreateFontString(nil, "OVERLAY")
    SetFont(panel.saved.label, 8)
    panel.saved.label:SetPoint("LEFT", panel.saved._box, "RIGHT", 5, 0)
    panel.saved.label:SetText("SAVED")
    panel.saved:SetScript("OnEnter", function(self)
        self._hovering = true
        self.label:SetTextColor(1, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Show only items saved to the vendor shopping list. Use the pin beside an item to save it.")
        end
    end)
    panel.saved:SetScript("OnLeave", function(self)
        self._hovering = nil
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        local enabled = GetSettings().legendSavedOnly == true
        self.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end)
    panel.saved:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.legendSavedOnly = not settings.legendSavedOnly
        if addon.Refresh then addon.Refresh() end
    end)

    panel.list = CreateFrame("Button", nil, panel)
    panel.list:SetSize(41, TITLE_H)
    panel.list:SetPoint("RIGHT", panel.saved, "LEFT", -3, 0)
    panel.list._box = panel.list:CreateTexture(nil, "ARTWORK")
    panel.list._box:SetSize(12, 12)
    panel.list._box:SetPoint("LEFT", panel.list, "LEFT", 2, 0)
    panel.list._check = panel.list:CreateTexture(nil, "OVERLAY")
    panel.list._check:SetSize(16, 16)
    panel.list._check:SetPoint("CENTER", panel.list._box, "CENTER")
    panel.list._check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    panel.list._edges = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", 12, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 12, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 12 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 12 },
    }) do
        local line = panel.list:CreateTexture(nil, "OVERLAY")
        if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
        line:SetPoint(edge[1], panel.list._box, edge[1])
        line:SetPoint(edge[2], panel.list._box, edge[2])
        panel.list._edges[#panel.list._edges + 1] = line
    end
    panel.list.label = panel.list:CreateFontString(nil, "OVERLAY")
    SetFont(panel.list.label, 8)
    panel.list.label:SetPoint("LEFT", panel.list._box, "RIGHT", 5, 0)
    panel.list.label:SetText("LIST")
    panel.list:SetScript("OnEnter", function(self)
        self._hovering = true
        self.label:SetTextColor(1, 1, 1, 1)
        if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Show vendor items as a sortable list with icon, pin, item, type, and cost columns. Clear the checkbox to return to the normal icon grid.")
        end
    end)
    panel.list:SetScript("OnLeave", function(self)
        self._hovering = nil
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        local enabled = GetSettings().vendorItemView == "list"
        self.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end)
    panel.list:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.vendorItemView = settings.vendorItemView == "list" and "grid" or "list"
        if QueueRefresh then QueueRefresh() elseif addon.Refresh then addon.Refresh() end
    end)

    return panel
end

local function UpdateCurrencyFilterControl(legend)
    if not (legend and legend.filter) then return end
    local enabled = GetSettings().legendFilterItems == true
    legend.filter._box:SetColorTexture(enabled and ACCENT_R or 0.025, enabled and ACCENT_G or 0.035, enabled and ACCENT_B or 0.045, enabled and 0.62 or 0.88)
    legend.filter._check:SetShown(enabled)
    for _, edge in ipairs(legend.filter._edges) do
        edge:SetColorTexture(enabled and ACCENT_R or 0.38, enabled and ACCENT_G or 0.38, enabled and ACCENT_B or 0.38, enabled and 0.95 or 0.85)
    end
    if not legend.filter._hovering then
        legend.filter.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end
end

local function UpdateAffordableFilterControl(legend)
    if not (legend and legend.afford) then return end
    local enabled = GetSettings().legendAffordableOnly == true
    legend.afford._box:SetColorTexture(enabled and ACCENT_R or 0.025, enabled and ACCENT_G or 0.035, enabled and ACCENT_B or 0.045, enabled and 0.62 or 0.88)
    legend.afford._check:SetShown(enabled)
    for _, edge in ipairs(legend.afford._edges) do
        edge:SetColorTexture(enabled and ACCENT_R or 0.38, enabled and ACCENT_G or 0.38, enabled and ACCENT_B or 0.38, enabled and 0.95 or 0.85)
    end
    if not legend.afford._hovering then
        legend.afford.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end
end

local function UpdateSavedFilterControl(legend)
    if not (legend and legend.saved) then return end
    local enabled = GetSettings().legendSavedOnly == true
    legend.saved._box:SetColorTexture(enabled and ACCENT_R or 0.025, enabled and ACCENT_G or 0.035, enabled and ACCENT_B or 0.045, enabled and 0.62 or 0.88)
    legend.saved._check:SetShown(enabled)
    for _, edge in ipairs(legend.saved._edges) do
        edge:SetColorTexture(enabled and ACCENT_R or 0.38, enabled and ACCENT_G or 0.38, enabled and ACCENT_B or 0.38, enabled and 0.95 or 0.85)
    end
    if not legend.saved._hovering then
        legend.saved.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end
end

function addon.UpdateVendorListViewControl(legend)
    if not (legend and legend.list) then return end
    local enabled = GetSettings().vendorItemView == "list"
    legend.list._box:SetColorTexture(enabled and ACCENT_R or 0.025, enabled and ACCENT_G or 0.035, enabled and ACCENT_B or 0.045, enabled and 0.62 or 0.88)
    legend.list._check:SetShown(enabled)
    for _, edge in ipairs(legend.list._edges) do
        edge:SetColorTexture(enabled and ACCENT_R or 0.38, enabled and ACCENT_G or 0.38, enabled and ACCENT_B or 0.38, enabled and 0.95 or 0.85)
    end
    if not legend.list._hovering then
        legend.list.label:SetTextColor(enabled and ACCENT_R or 0.75, enabled and ACCENT_G or 0.75, enabled and ACCENT_B or 0.75, 1)
    end
end

function addon.UpdateCurrencyLegendVisibilityControl(legend)
    local control = legend and legend.currencyCollapse
    if not control then return end
    local enabled = GetSettings().currencyLegendVisible ~= false
    local r, g, b = enabled and ACCENT_R or 0.38, enabled and ACCENT_G or 0.38, enabled and ACCENT_B or 0.38
    control.label:SetText(enabled and "-" or ">")
    control.label:SetTextColor(control._hovering and 1 or r, control._hovering and 1 or g, control._hovering and 1 or b, 1)
    if legend.title then legend.title:SetTextColor(r, g, b, enabled and 1 or 0.78) end
end

-- The Vendor Bags host can be narrowed to four columns, leaving this panel
-- little wider than 170 pixels.  Keep every command available at that size by
-- measuring each label.  Wide panels share the title row; narrower panels
-- flow the complete toolbar beneath it so currency rows never collide with a
-- wrapped control.
function addon.LayoutVendorToolbar(legend, panelWidth)
    if not legend then return TITLE_H end

    local outerGutter = 6
    local controlGap = 3
    local controlHeight = TITLE_H - 4
    local available = math.max(1, math.floor((panelWidth or legend:GetWidth() or 1) - (outerGutter * 2)))
    local controls = { legend.list, legend.saved, legend.plan, legend.afford, legend.filter, legend.mode }
    local widths = {}
    local controlsWidth = 0
    for index, control in ipairs(controls) do
        if control and control.label then
            local label = control.label
            local labelWidth = math.ceil((label.GetUnboundedStringWidth and label:GetUnboundedStringWidth()) or label:GetStringWidth() or 0)
            -- Both control styles reserve 22 pixels: a 12px leading mark,
            -- a 4-5px text gap, and visible gutters at each edge.
            widths[index] = math.max(41, labelWidth + 22)
            controlsWidth = controlsWidth + widths[index]
            if index > 1 then controlsWidth = controlsWidth + controlGap end
        end
    end

    local showTitle = legend._waffleHasCurrencies == true
    if legend.title and legend.title.SetShown then legend.title:SetShown(showTitle) end
    local titleWidth = 0
    if legend.title then
        titleWidth = math.ceil((legend.title.GetUnboundedStringWidth and legend.title:GetUnboundedStringWidth()) or legend.title:GetStringWidth() or 0)
    end
    local sharedTitleGap = 10
    local sharedToolbarX = (legend._waffleTitleLeft or 8) + titleWidth + sharedTitleGap
    local sharesTitleRow = showTitle
        and ((sharedToolbarX + controlsWidth) <= (outerGutter + available))
        or (not showTitle and controlsWidth <= available)
    local rows, row = { {} }, 1
    local rowWidths = { 0 }
    for index, control in ipairs(controls) do
        if control and control.label then
            local width = widths[index]
            if not sharesTitleRow and rowWidths[row] > 0 and (rowWidths[row] + controlGap + width) > available then
                row = row + 1
                rows[row] = {}
                rowWidths[row] = 0
            end
            rows[row][#rows[row] + 1] = { control = control, width = width }
            rowWidths[row] = rowWidths[row] + width + (rowWidths[row] > 0 and controlGap or 0)
        end
    end

    for rowIndex, controlsInRow in ipairs(rows) do
        -- Keep this compact toolbar at the far right, where EUI places its
        -- header actions.  On narrow windows each wrapped row is right-aligned
        -- too, rather than beginning underneath the CURRENCIES label.
        local x = outerGutter + available - (rowWidths[rowIndex] or 0)
        for _, entry in ipairs(controlsInRow) do
            local control, width = entry.control, entry.width
            control:SetSize(width, controlHeight)
            control:ClearAllPoints()
            local topOffset = sharesTitleRow and 2 or (TITLE_H + controlGap + ((rowIndex - 1) * (controlHeight + controlGap)))
            control:SetPoint("TOPLEFT", legend, "TOPLEFT", x, -topOffset)

            control.label:ClearAllPoints()
            if control._waffleActionIconAnchor then
                control.label:SetPoint("LEFT", control._waffleActionIconAnchor, "RIGHT", 4, 0)
            elseif control._box then
                control.label:SetPoint("LEFT", control._box, "RIGHT", 5, 0)
            else
                control.label:SetPoint("LEFT", control, "LEFT", 3, 0)
            end
            control.label:SetPoint("RIGHT", control, "RIGHT", -3, 0)
            control.label:SetJustifyH("LEFT")
            x = x + width + controlGap
        end
    end

    if sharesTitleRow then return TITLE_H end
    return TITLE_H + controlGap + (#rows * (controlHeight + controlGap))
end

local function RestoreScrollLayout(frame)
    if not (frame and frame.ScrollFrame and frame.Footer and frame.Header) then return end

    local sidebarWidth = frame.Sidebar and frame.Sidebar:GetWidth() or 160
    local headerHeight = frame.Header:GetHeight()
    frame.ScrollFrame:ClearAllPoints()
    frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", sidebarWidth, -(headerHeight + 1))
    frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", -1, 0)
    if frame.ScrollTrack then
        frame.ScrollTrack:ClearAllPoints()
        frame.ScrollTrack:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(headerHeight + 1))
        frame.ScrollTrack:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", -1, 0)
    end
end

local function LayoutPanel(frame, entries)
    local legend = EnsurePanel(frame)
    -- A currency-free merchant still needs all toolbar controls (List, Saved,
    -- Plan, and so on), but a "CURRENCIES" heading above no currency rows is
    -- misleading and wastes the left side of the header.
    legend._waffleHasCurrencies = #entries > 0
    local showCurrencyRows = legend._waffleHasCurrencies and GetSettings().currencyLegendVisible ~= false

    local hasSelectedEntry = false
    for _, entry in ipairs(entries) do
        if entry.key == selectedCostKey then
            hasSelectedEntry = true
            break
        end
    end
    if not hasSelectedEntry then
        selectedCostKey = nil
    end

    local sidebarWidth = frame.Sidebar and frame.Sidebar:GetWidth() or 160
    local headerHeight = frame.Header and frame.Header:GetHeight() or 35
    legend:ClearAllPoints()
    legend:SetPoint("TOPLEFT", frame, "TOPLEFT", sidebarWidth, -(headerHeight + 1))
    legend:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(headerHeight + 1))
    legend.mode.label:SetText(IsTextMode() and "TEXT" or "GRID")
    addon.SetPanelActionColor(legend.mode, 0.75, 0.75, 0.75)
    local panelWidth = (frame:GetWidth() or 0) - sidebarWidth - 1
    if panelWidth <= 1 then panelWidth = legend:GetWidth() or 1 end
    local toolbarHeight = addon.LayoutVendorToolbar(legend, panelWidth)
    local gridColumns, _, gridHeight = addon.GetCurrencyIconGridLayout(panelWidth, showCurrencyRows and #entries or 0)
    local currencyHeight = showCurrencyRows and (IsTextMode() and ((#entries * addon.CurrencyGrid.size) + 3) or gridHeight) or 0
    local height = toolbarHeight + currencyHeight
    legend:SetHeight(height)

    for index, entry in ipairs(entries) do
        local row = legend.rows[index]
        if not row then
            row = CreateLegendRow(legend)
            legend.rows[index] = row
        end
        row._costKey = entry.key
        row._costLink = entry.link
        row._currencyName = entry.name
        row._color = entry.color
        row._legendIndex = index
        row._owned = entry.owned
        row:ClearAllPoints()
        row._label:ClearAllPoints()
        row._count:ClearAllPoints()
        row._iconSlot:ClearAllPoints()
        if IsTextMode() then
            row:SetPoint("TOPLEFT", legend, "TOPLEFT", 0, -toolbarHeight - ((index - 1) * addon.CurrencyGrid.size))
            row:SetPoint("TOPRIGHT", legend, "TOPRIGHT", 0, -toolbarHeight - ((index - 1) * addon.CurrencyGrid.size))
            row:SetHeight(addon.CurrencyGrid.size)
            row._iconSlot:Show()
            row._iconSlot:SetSize(addon.CurrencyGrid.size - 4, addon.CurrencyGrid.size - 4)
            row._iconSlot:SetPoint("LEFT", row, "LEFT", addon.CurrencyGrid.gutter, 0)
            row._icon:SetTexture(entry.texture)
            row._label:Show()
            row._label:SetPoint("LEFT", row._iconSlot, "RIGHT", 8, 0)
            row._label:SetPoint("RIGHT", row, "RIGHT", -58, 0)
            row._label:SetText(entry.name)
            SetFont(row._count, 9)
            row._count:SetPoint("RIGHT", row, "RIGHT", -7, 0)
            row._count:SetJustifyH("RIGHT")
            row._count:SetText(entry.owned ~= nil and "[" .. tostring(entry.owned) .. "]" or "[?]")
            row._indicator:ClearAllPoints()
            row._indicator:SetPoint("TOPLEFT")
            row._indicator:SetPoint("BOTTOMLEFT")
        else
            local gridIndex = index - 1
            local column = gridIndex % gridColumns
            local gridRow = math.floor(gridIndex / gridColumns)
            row:SetSize(addon.CurrencyGrid.size, addon.CurrencyGrid.size)
            row:SetPoint("TOPLEFT", legend, "TOPLEFT", addon.CurrencyGrid.gutter + (column * (addon.CurrencyGrid.size + addon.CurrencyGrid.gap)),
                -toolbarHeight - addon.CurrencyGrid.gutter - (gridRow * (addon.CurrencyGrid.size + addon.CurrencyGrid.gap)))
            row._iconSlot:Show()
            row._iconSlot:SetSize(addon.CurrencyGrid.size - 4, addon.CurrencyGrid.size - 4)
            row._iconSlot:SetPoint("CENTER", row, "CENTER")
            row._icon:SetTexture(entry.texture)
            row._label:Hide()
            SetFont(row._count, 10)
            row._count:SetPoint("BOTTOMRIGHT", row._iconSlot, "BOTTOMRIGHT", 1, 1)
            row._count:SetJustifyH("RIGHT")
            row._count:SetText(entry.owned ~= nil and tostring(entry.owned) or "?")
        end
        SetRowState(row)
        row:Show()
    end
    for index = #entries + 1, #legend.rows do
        legend.rows[index]:Hide()
    end

    legend.mode.label:SetText(IsTextMode() and "TEXT" or "GRID")
    addon.SetPanelActionColor(legend.mode, 0.75, 0.75, 0.75)
    UpdateCurrencyFilterControl(legend)
    UpdateAffordableFilterControl(legend)
    UpdateSavedFilterControl(legend)
    addon.UpdateVendorListViewControl(legend)
    if legend.currencyCollapse then legend.currencyCollapse:SetShown(legend._waffleHasCurrencies) end
    addon.UpdateCurrencyLegendVisibilityControl(legend)
    if not showCurrencyRows then
        for _, row in ipairs(legend.rows) do row:Hide() end
    end
    legend:Show()
    frame.ScrollFrame:ClearAllPoints()
    frame.ScrollFrame:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -1)
    frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", -1, 0)
    if frame.ScrollTrack then
        frame.ScrollTrack:ClearAllPoints()
        frame.ScrollTrack:SetPoint("TOPRIGHT", legend, "BOTTOMRIGHT", 0, -1)
        frame.ScrollTrack:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", -1, 0)
    end
end

local function EnsureHighlight(button)
    if button._euvxHighlight then return button._euvxHighlight end

    local highlight = CreateFrame("Frame", nil, button)
    highlight:SetAllPoints()
    highlight:SetFrameLevel(button:GetFrameLevel() + 5)
    local lines = {}
    for index = 1, 4 do
        lines[index] = highlight:CreateTexture(nil, "OVERLAY")
        lines[index]:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end
    lines[1]:SetHeight(2)
    lines[1]:SetPoint("TOPLEFT")
    lines[1]:SetPoint("TOPRIGHT")
    lines[2]:SetHeight(2)
    lines[2]:SetPoint("BOTTOMLEFT")
    lines[2]:SetPoint("BOTTOMRIGHT")
    lines[3]:SetWidth(2)
    lines[3]:SetPoint("TOPLEFT")
    lines[3]:SetPoint("BOTTOMLEFT")
    lines[4]:SetWidth(2)
    lines[4]:SetPoint("TOPRIGHT")
    lines[4]:SetPoint("BOTTOMRIGHT")
    highlight:Hide()
    button._euvxHighlight = highlight
    return highlight
end

local function ButtonUsesCost(costs, key)
    if not key then return false end
    for _, cost in ipairs(costs or {}) do
        if cost.key == key then
            return true
        end
    end
    return false
end

local function CanAffordMerchantItem(merchantIndex, costs)
    local price = 0
    if GetMerchantItemInfo then
        local _, _, itemPrice = GetMerchantItemInfo(merchantIndex)
        price = IsSafeNumber(itemPrice) and itemPrice or 0
    end
    if price > 0 and GetMoney and GetMoney() < price then return false end
    for _, cost in ipairs(costs or {}) do
        local owned = GetOwnedCostAmount(cost)
        if not IsSafeNumber(owned) or owned < cost.amount then return false end
    end
    return true
end

local function GetVendorItemID(button)
    if not button then return nil end
    local link = button._link
    if not IsSafeText(link) and GetMerchantItemLink and IsSafeNumber(button._merchantIndex) then
        link = GetMerchantItemLink(button._merchantIndex)
    end
    return IsSafeText(link) and tonumber(link:match("item:(%d+)")) or nil
end

local function GetVendorPlannerKey(button)
    local itemID = GetVendorItemID(button)
    if not itemID then return nil end
    local vendorKey = UnitGUID and UnitGUID("npc") or nil
    if not IsSafeText(vendorKey) then
        vendorKey = UnitName and UnitName("npc") or nil
    end
    -- Retail can protect BOTH identity APIs for companion vendors such as
    -- Soul-Trader. Concatenating the fallback name propagates its secrecy;
    -- indexing the planner with that key then aborts the entire list refresh.
    -- Only concatenate readable values; use our neutral namespace otherwise.
    if not IsSafeText(vendorKey) then vendorKey = "merchant" end
    return vendorKey .. ":" .. itemID
end

local function SaveVendorPlannerItem(button, costs)
    local key = GetVendorPlannerKey(button)
    if not key then return end
    local planner = GetVendorPlanner()
    if planner[key] then
        planner[key] = nil
        return
    end

    local name, texture, price
    if GetMerchantItemInfo then
        name, texture, price = GetMerchantItemInfo(button._merchantIndex)
    end
    local copiedCosts = {}
    for _, cost in ipairs(costs or {}) do
        copiedCosts[#copiedCosts + 1] = {
            amount = cost.amount,
            color = cost.color,
            key = cost.key,
            name = cost.name,
            texture = cost.texture,
        }
    end
    local vendorName = UnitName and UnitName("npc")
    planner[key] = {
        costs = copiedCosts,
        itemID = GetVendorItemID(button),
        link = button._link,
        name = name or (button._link and button._link:match("%[(.-)%]")) or "Vendor Item",
        price = IsSafeNumber(price) and price or 0,
        vendor = IsSafeText(vendorName) and vendorName or "Merchant",
    }
end

ShowVendorNotePopup = function(button)
    local key = GetVendorPlannerKey(button)
    if not (key and EllesmereUI and EllesmereUI.BuildCogPopup) then return end
    local _, notes = GetVendorPlanner()
    local _, show = EllesmereUI.BuildCogPopup({
        title = "Vendor Note",
        minWidth = 390,
        rows = {
            {
                type = "input",
                label = "Note",
                inputWidth = 230,
                get = function() return notes[key] or "" end,
                set = function(value)
                    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    notes[key] = value ~= "" and value or nil
                    if addon.Refresh then addon.Refresh() end
                end,
            },
        },
    })
    show(button)
end

local function VendorPlanText(value, maximum)
    value = tostring(value or "")
    if #value <= maximum then return value end
    return value:sub(1, math.max(1, maximum - 3)) .. "..."
end

ShowVendorPlan = function(anchor)
    local planner = GetVendorPlanner()
    local entries, currencyTotals, goldTotal = {}, {}, 0
    for _, entry in pairs(planner) do
        entries[#entries + 1] = entry
        goldTotal = goldTotal + (entry.price or 0)
        for _, cost in ipairs(entry.costs or {}) do
            local total = currencyTotals[cost.key]
            if not total then
                total = { amount = 0, name = cost.name, texture = cost.texture }
                currencyTotals[cost.key] = total
            end
            total.amount = total.amount + (cost.amount or 0)
        end
    end
    table.sort(entries, function(a, b)
        if a.vendor ~= b.vendor then return tostring(a.vendor) < tostring(b.vendor) end
        return tostring(a.name) < tostring(b.name)
    end)

    local lines = { "SHOPPING LIST" }
    if #entries == 0 then
        lines[#lines + 1] = "No saved items. Click the pin beside a vendor item to add it."
    else
        for _, entry in ipairs(entries) do
            local vendor = VendorPlanText(entry.vendor or "Merchant", 24)
            local item = VendorPlanText(entry.name or "Vendor Item", 42)
            lines[#lines + 1] = VendorPlanText(vendor .. " — " .. item, 70)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "TOTALS"
        if goldTotal > 0 then lines[#lines + 1] = GetCoinTextureString and GetCoinTextureString(goldTotal) or tostring(goldTotal) .. " copper" end
        for _, total in pairs(currencyTotals) do
            lines[#lines + 1] = VendorPlanText(total.name or "Currency", 56) .. ": " .. tostring(total.amount)
        end
    end
    local summary = table.concat(lines, "\n")
    if EllesmereUI and EllesmereUI.ShowCopyPopup then
        EllesmereUI:ShowCopyPopup("Vendor Shopping List", "Click a pin to save or remove. Right-click a pin to add a note.", summary)
    elseif EllesmereUI and EllesmereUI.BuildCogPopup then
        local _, show = EllesmereUI.BuildCogPopup({ title = "Vendor Shopping List", minWidth = 420, rows = {{ type = "input", label = "Summary", inputWidth = 270, get = function() return summary end, set = function() end }} })
        show(anchor)
    end
end

local function EnsureVendorPlannerControl(button, costs)
    if not button._wafflePlannerControl then
        local control = CreateFrame("Button", nil, button)
        control:SetSize(24, 28)
        control:SetPoint("LEFT", button, "RIGHT", 6, 0)
        control:SetFrameLevel(button:GetFrameLevel() + 10)
        control:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if control.SetPropagateMouseClicks then
            control:SetPropagateMouseClicks(false)
        end
        control.icon = control:CreateTexture(nil, "ARTWORK")
        control.icon:SetSize(24, 24)
        control.icon:SetPoint("CENTER")
        control.icon:SetTexCoord(0, 1, 0, 1)
        control:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            local key = GetVendorPlannerKey(parent)
            local planner = GetVendorPlanner()
            local tracked = key and planner[key] ~= nil
            if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self,
                    "Shopping List: " .. (tracked and "Tracked" or "Not tracked")
                    .. "\nLeft-click: " .. (tracked and "remove from the shopping list." or "add to the shopping list.")
                    .. "\nRight-click: edit note.")
            end
        end)
        control:SetScript("OnLeave", function(self)
            if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        control:SetScript("OnClick", function(self, mouseButton)
            local parent = self:GetParent()
            if parent._isBuyback or not IsSafeNumber(parent._merchantIndex) or not GetVendorPlannerKey(parent) then return end
            if mouseButton == "RightButton" then
                ShowVendorNotePopup(parent)
            elseif mouseButton == "LeftButton" then
                SaveVendorPlannerItem(parent, parent._waffleCosts or {})
                if addon.Refresh then addon.Refresh() end
                if self.IsMouseOver and self:IsMouseOver() and self:IsShown() then
                    self:GetScript("OnEnter")(self)
                end
            end
        end)
        button._wafflePlannerControl = control
    end
    button._waffleCosts = costs
    local key = GetVendorPlannerKey(button)
    local planner = GetVendorPlanner()
    local control = button._wafflePlannerControl
    local canTrack = not button._isBuyback and IsSafeNumber(button._merchantIndex) and key ~= nil
    if not canTrack then
        control:Hide()
        return
    end
    control.icon:SetTexture(planner[key]
        and "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\vendor-pin-on.tga"
        or "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\vendor-pin-off.tga")
    control:Show()
end

local function ApplyVendorFilters(button, costs)
    local settings = GetSettings()
    local currencyFiltering = settings.legendFilterItems == true and selectedCostKey ~= nil
    local affordableFiltering = settings.legendAffordableOnly == true
    local savedFiltering = settings.legendSavedOnly == true
    local filtering = currencyFiltering or affordableFiltering or savedFiltering
    local slotParent = button.SlotParent or button:GetParent()
    if not slotParent then return end

    if not filtering then
        if button._waffleCurrencyFilterApplied then
            button._waffleCurrencyFilterApplied = nil
            if button._waffleCurrencyFilterWasVisible then
                button:Show()
                slotParent:Show()
            end
            button._waffleCurrencyFilterWasVisible = nil
        end
        return
    end

    if not button._waffleCurrencyFilterApplied then
        button._waffleCurrencyFilterWasVisible = button:IsShown() and slotParent:IsShown()
        button._waffleCurrencyFilterApplied = true
    end

    local matchesCurrency = not currencyFiltering or ButtonUsesCost(costs, selectedCostKey)
    local affordable = not affordableFiltering or CanAffordMerchantItem(button._merchantIndex, costs)
    local planner = GetVendorPlanner()
    local saved = not savedFiltering or planner[GetVendorPlannerKey(button)] ~= nil
    if button._waffleCurrencyFilterWasVisible and matchesCurrency and affordable and saved then
        button:Show()
        slotParent:Show()
    else
        button:Hide()
        slotParent:Hide()
    end
end

local function AppendCostTooltip(button)
    if not (button and not button._isBuyback and IsSafeNumber(button._merchantIndex)) then return end

    if addon.OpenVendorStackPicker then
        GameTooltip:AddLine("Shift-Right-Click: buy a stack or choose quantity", ACCENT_R, ACCENT_G, ACCENT_B)
        GameTooltip:Show()
    end
    local costs = GetMerchantCosts(button._merchantIndex)
    if #costs == 0 then return end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Currency Cost", ACCENT_R, ACCENT_G, ACCENT_B)
    for _, cost in ipairs(costs) do
        local label
        if IsTextMode() then
            label = ColorName(cost.name, cost.color)
        else
            label = TextureMarkup(cost.texture, 14) .. " " .. cost.name
        end
        GameTooltip:AddDoubleLine(label, tostring(cost.amount), 1, 1, 1, 1, 1, 1)
    end
    if GetSettings().vendorTooltipDetails ~= false then
        local itemID = GetVendorItemID(button)
        if itemID and C_Item and C_Item.GetItemCount then
            GameTooltip:AddDoubleLine("Owned", tostring(C_Item.GetItemCount(itemID) or 0), 0.75, 0.75, 0.75, 1, 1, 1)
        end
        if button._link and C_TransmogCollection and C_TransmogCollection.GetItemInfo then
            local appearanceID = C_TransmogCollection.GetItemInfo(button._link)
            if appearanceID then
                local collected = C_TransmogCollection.PlayerHasTransmogByItemInfo
                    and C_TransmogCollection.PlayerHasTransmogByItemInfo(button._link)
                GameTooltip:AddLine(collected and "Appearance: collected" or "Appearance: new", collected and 0.55 or 0.20, collected and 0.55 or 0.90, collected and 0.55 or 0.75)
            end
        end
        local key = GetVendorPlannerKey(button)
        local _, notes = GetVendorPlanner()
        if key and IsSafeText(notes[key]) then
            GameTooltip:AddLine("Note: " .. notes[key], ACCENT_R, ACCENT_G, ACCENT_B, true)
        end
    end
    GameTooltip:Show()
end

local function GetWaffleCostText(button)
    if button._waffleCostText then return button._waffleCostText end

    local text = button:CreateFontString(nil, "OVERLAY", nil, 7)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button._waffleCostText = text
    return text
end

local function CopyPriceTextLayout(source, target)
    target:ClearAllPoints()
    local point, relativeTo, relativePoint, x, y = source:GetPoint(1)
    if point then
        target:SetPoint(point, relativeTo, relativePoint, x, y)
    else
        target:SetPoint("BOTTOMLEFT", target:GetParent(), "BOTTOMLEFT", 2, 2)
    end

    local font, size, flags = source:GetFont()
    if font and size then target:SetFont(font, size, flags) end
    target:SetJustifyH(source:GetJustifyH() or "LEFT")
end

local function UpdatePriceLabel(button, costs)
    if not button.PriceText then return end

    local waffleText = button._waffleCostText
    if not (#costs > 0 and GetMerchantItemInfo) then
        if waffleText then waffleText:Hide() end
        button.PriceText:Show()
        return
    end

    local _, _, price, _, _, _, _, hasExtendedCost = GetMerchantItemInfo(button._merchantIndex)
    if hasExtendedCost and IsSafeNumber(price) and price <= 0 then
        local firstCost = costs[1]
        waffleText = GetWaffleCostText(button)
        CopyPriceTextLayout(button.PriceText, waffleText)
        waffleText:SetText(tostring(firstCost.amount) .. TextureMarkup(firstCost.texture, 10)
            .. (#costs > 1 and "+" or ""))
        waffleText:SetTextColor(ColorComponents(firstCost.color))
        waffleText:Show()
        -- Vendor Bags uses this field for its "Alt" placeholder. Hide that
        -- placeholder and draw our currency amount in a separate owned layer.
        button.PriceText:Hide()
    else
        if waffleText then waffleText:Hide() end
        button.PriceText:Show()
    end
end

local function CaptureAnchors(region)
    local anchors = {}
    if not (region and region.GetNumPoints and region.GetPoint) then return anchors end
    for index = 1, region:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
        if point then
            anchors[#anchors + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end
    return anchors
end

local function RestoreAnchors(region, anchors)
    if not region then return end
    region:ClearAllPoints()
    for _, anchor in ipairs(anchors or {}) do
        region:SetPoint(unpack(anchor))
    end
end

local function GetVendorListItemName(button)
    local name
    if GetMerchantItemInfo and IsSafeNumber(button._merchantIndex) then
        name = GetMerchantItemInfo(button._merchantIndex)
    end
    if not IsSafeText(name) and IsSafeText(button._link) then
        name = button._link:match("%[(.-)%]")
    end
    return IsSafeText(name) and name or "Vendor Item"
end

function addon.GetVendorListItemQuality(button)
    local link = button._link
    if not IsSafeText(link) and GetMerchantItemLink and IsSafeNumber(button._merchantIndex) then
        link = GetMerchantItemLink(button._merchantIndex)
    end
    if IsSafeText(link) and GetItemInfo then
        local _, _, quality = GetItemInfo(link)
        if IsSafeNumber(quality) then return quality end
    end
    return nil
end

local function GetVendorListItemColor(button)
    local quality = addon.GetVendorListItemQuality(button)
    if quality and GetItemQualityColor then
        local r, g, b = GetItemQualityColor(quality)
        if IsSafeNumber(r) and IsSafeNumber(g) and IsSafeNumber(b) then return r, g, b end
    end
    return 0.93, 0.93, 0.93
end

addon.VendorListRarityNames = {
    [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Artifact", "Heirloom", "Token",
}

function addon.GetVendorListRarityText(button)
    local quality = addon.GetVendorListItemQuality(button)
    return quality and (addon.VendorListRarityNames[quality] or ("Quality " .. quality)) or "Unknown"
end

-- Keep the type column practical rather than exposing Blizzard's very long
-- weapon and armour subclasses.  Consumables retain their useful subtype,
-- so Food and Potion can be spotted at a glance.
function addon.GetVendorListItemType(button)
    local link = button and button._link
    if not IsSafeText(link) and GetMerchantItemLink and button and IsSafeNumber(button._merchantIndex) then
        link = GetMerchantItemLink(button._merchantIndex)
    end
    local itemID = IsSafeText(link) and tonumber(link:match("item:(%d+)")) or nil
    local item = itemID or link
    if not item then return "Item" end

    local itemType, itemSubType
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, foundType, foundSubType = C_Item.GetItemInfo(item)
        itemType, itemSubType = foundType, foundSubType
    elseif GetItemInfo then
        local _, _, _, _, _, foundType, foundSubType = GetItemInfo(item)
        itemType, itemSubType = foundType, foundSubType
    end

    local classID, subclassID
    if itemID and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, foundClassID, foundSubclassID = C_Item.GetItemInfoInstant(itemID)
        classID, subclassID = foundClassID, foundSubclassID
    end
    if classID == 2 then return itemType or "Weapon" end
    if classID == 4 then return itemType or "Armor" end
    if classID == 0 then
        -- Item-subclass IDs are API values, unlike the localized type text.
        if subclassID == 1 then return "Potion" end
        if subclassID == 5 then return "Food" end
        if IsSafeText(itemSubType) then return itemSubType end
    end
    return IsSafeText(itemType) and itemType or "Item"
end

function addon.GetVendorListColumnOrder()
    local settings = GetSettings()
    local saved = settings.vendorListColumnOrder
    local order, seen = {}, {}
    if type(saved) == "table" then
        for _, key in ipairs(saved) do
            if addon.VendorListColumnText[key] and not seen[key] then
                order[#order + 1] = key
                seen[key] = true
            end
        end
    end
    -- Existing default layouts were saved without Rarity. Insert the new
    -- field before Cost so the familiar Cost column stays on the right;
    -- custom user-reordered layouts keep their own relative order.
    if not seen.rarity and #order == 5 and order[1] == "icon" and order[2] == "pin"
        and order[3] == "item" and order[4] == "type" and order[5] == "cost" then
        table.insert(order, 5, "rarity")
        seen.rarity = true
    end
    for _, key in ipairs(addon.VendorListColumnDefault) do
        if not seen[key] then order[#order + 1] = key end
    end
    settings.vendorListColumnOrder = order
    return order
end

function addon.MoveVendorListColumn(columnKey, dropIndex)
    local order = addon.GetVendorListColumnOrder()
    local sourceIndex
    for index, key in ipairs(order) do
        if key == columnKey then sourceIndex = index; break end
    end
    if not sourceIndex then return false end

    dropIndex = math.max(1, math.min(#order + 1, math.floor(dropIndex or sourceIndex)))
    table.remove(order, sourceIndex)
    if sourceIndex < dropIndex then dropIndex = dropIndex - 1 end
    dropIndex = math.max(1, math.min(#order + 1, dropIndex))
    table.insert(order, dropIndex, columnKey)
    GetSettings().vendorListColumnOrder = order
    return sourceIndex ~= dropIndex
end

function addon.GetVendorListSort()
    local settings = GetSettings()
    local columnKey = settings.vendorListSortColumn
    if not addon.VendorListColumnText[columnKey] then return nil, true end
    if columnKey == "rarity" and settings.vendorListShowRarity == false then return nil, true end
    return columnKey, settings.vendorListSortAscending ~= false
end

function addon.ToggleVendorListSort(columnKey)
    if not addon.VendorListColumnText[columnKey] then return false end
    local settings = GetSettings()
    if settings.vendorListSortColumn == columnKey then
        settings.vendorListSortAscending = settings.vendorListSortAscending == false
    else
        settings.vendorListSortColumn = columnKey
        settings.vendorListSortAscending = true
    end
    return true
end

function addon.NormalizeVendorListSortText(value)
    if not IsSafeText(value) then return "" end
    return string.lower(value)
end

function addon.GetVendorListCostSortValue(button, costs)
    local price = 0
    if GetMerchantItemInfo and IsSafeNumber(button and button._merchantIndex) then
        local _, _, merchantPrice = GetMerchantItemInfo(button._merchantIndex)
        price = IsSafeNumber(merchantPrice) and math.max(0, merchantPrice) or 0
    end

    if price > 0 then
        return "1", string.format("%012d", price)
    end
    if #(costs or {}) == 0 then
        return "0", ""
    end

    -- Different currencies have no conversion rate, but the first displayed
    -- amount is still the most useful Cost sort. Compare that number before
    -- currency names or secondary costs; otherwise a 200-cost item can end
    -- up after 100-cost items merely because its currency name differs.
    local parts = {}
    for index, cost in ipairs(costs or {}) do
        local key = addon.NormalizeVendorListSortText(cost and (cost.key or cost.name))
        local amount = IsSafeNumber(cost and cost.amount) and math.max(0, cost.amount) or 0
        parts[index] = { amount = string.format("%012d", amount), key = key }
    end
    local rest = {}
    for index = 2, #parts do
        rest[#rest + 1] = parts[index].amount .. "\31" .. parts[index].key
    end
    return "2", parts[1].amount, parts[1].key, table.concat(rest, "\30")
end

function addon.GetVendorListSortValue(columnKey, button, costs)
    if columnKey == "item" then
        return addon.NormalizeVendorListSortText(GetVendorListItemName(button))
    elseif columnKey == "type" then
        return addon.NormalizeVendorListSortText(addon.GetVendorListItemType(button))
    elseif columnKey == "rarity" then
        return string.format("%03d", addon.GetVendorListItemQuality(button) or -1)
    elseif columnKey == "pin" then
        local planner = GetVendorPlanner()
        local key = GetVendorPlannerKey(button)
        return planner[key] and "1" or "0"
    elseif columnKey == "cost" then
        return addon.GetVendorListCostSortValue(button, costs)
    elseif columnKey == "icon" then
        return string.format("%012d", GetVendorItemID(button) or 0)
    end
    return ""
end

function addon.SortVendorListRows(rows, costsByMerchant)
    local columnKey, ascending = addon.GetVendorListSort()
    if not columnKey then
        table.sort(rows, function(left, right)
            return (left._merchantIndex or 0) < (right._merchantIndex or 0)
        end)
        return
    end

    local values = {}
    for _, button in ipairs(rows) do
        values[button] = { addon.GetVendorListSortValue(columnKey, button, costsByMerchant[button._merchantIndex] or {}) }
    end
    table.sort(rows, function(left, right)
        local leftValues, rightValues = values[left], values[right]
        for index = 1, math.max(#leftValues, #rightValues) do
            local a, b = leftValues[index] or "", rightValues[index] or ""
            if a ~= b then
                if ascending then return a < b end
                return a > b
            end
        end
        -- Merchant index is a stable final tie-breaker, so rows never shuffle
        -- between refreshes when two items share the visible column value.
        return (left._merchantIndex or 0) < (right._merchantIndex or 0)
    end)
end

-- The host lets the vendor window become quite narrow.  At the smallest
-- useful width we temporarily collapse Type rather than letting labels cross
-- each other; it returns automatically as the window grows.
function addon.GetVendorListColumnLayout(scrollWidth)
    local order = addon.GetVendorListColumnOrder()
    local showType = scrollWidth >= 340
    local showRarity = GetSettings().vendorListShowRarity ~= false and scrollWidth >= 270
    local defaults = {
        icon = 30,
        pin = 27,
        type = showType and math.max(56, math.min(90, math.floor(scrollWidth * 0.14))) or 0,
        rarity = showRarity and 62 or 0,
        cost = math.max(showType and 100 or 40, math.min(showType and 245 or 170, math.floor(scrollWidth * (showType and 0.30 or 0.38)))),
    }
    local visible = {}
    for _, key in ipairs(order) do
        if (key ~= "type" or showType) and (key ~= "rarity" or showRarity) then
            visible[#visible + 1] = key
        end
    end
    local minimums = {
        icon = VENDOR_LIST_COLUMN_MIN_WIDTH.icon,
        pin = VENDOR_LIST_COLUMN_MIN_WIDTH.pin,
        item = VENDOR_LIST_COLUMN_MIN_WIDTH.item,
        type = showType and VENDOR_LIST_COLUMN_MIN_WIDTH.type or 0,
        rarity = showRarity and VENDOR_LIST_COLUMN_MIN_WIDTH.rarity or 0,
        cost = showType and VENDOR_LIST_COLUMN_MIN_WIDTH.cost or 40,
    }
    local gaps = math.max(0, #visible - 1) * 5
    -- The 5px left and 9px right gutters are outside the columns themselves.
    local available = math.max(1, scrollWidth - 20 - gaps)
    local fixedDefault = 0
    for _, key in ipairs(visible) do
        if key ~= "item" then fixedDefault = fixedDefault + (defaults[key] or 0) end
    end
    -- Item is the flexible remainder, not the entire available width.  Starting
    -- it as the whole row made every new layout shrink Cost to its minimum.
    defaults.item = math.max(1, available - fixedDefault)
    local saved = GetSettings().vendorListColumnWidths
    local widths, total = {}, 0
    for _, key in ipairs(visible) do
        local value = type(saved) == "table" and tonumber(saved[key]) or nil
        if not IsSafeNumber(value) then value = defaults[key] end
        if key == "item" and not value then value = defaults.item end
        widths[key] = math.max(minimums[key] or 1, math.floor(value))
        total = total + widths[key]
    end

    -- The flexible Item column takes all spare space by default.  Once the
    -- user has resized columns, preserve that intent as far as the live vendor
    -- window permits, shrinking back toward useful minimums on a narrow frame.
    if total < available then
        widths.item = widths.item + (available - total)
        total = available
    elseif total > available then
        local excess = total - available
        for _, key in ipairs({ "item", "cost", "type", "rarity", "pin", "icon" }) do
            if widths[key] then
                local floor = minimums[key] or 1
                local reducible = math.max(0, widths[key] - floor)
                local reduction = math.min(excess, reducible)
                widths[key] = widths[key] - reduction
                excess = excess - reduction
                if excess <= 0 then break end
            end
        end
        -- At extreme minimum window widths, let Item absorb the remainder;
        -- labels already ellipsize and Type is hidden below the useful break.
        if excess > 0 and widths.item then widths.item = math.max(1, widths.item - excess) end
    end

    local columns, x = {}, 5
    for _, key in ipairs(visible) do
        columns[key] = { x = x, width = widths[key] }
        x = x + widths[key] + 5
    end
    return { order = visible, columns = columns, minimums = minimums,
        showType = showType, showRarity = showRarity, scrollWidth = scrollWidth }
end

local function FormatVendorGoldCost(copper)
    if not IsSafeNumber(copper) or copper <= 0 then return nil end
    local parts = {}
    local gold = math.floor(copper / 10000)
    copper = copper % 10000
    local silver = math.floor(copper / 100)
    copper = copper % 100
    if gold > 0 then parts[#parts + 1] = tostring(gold) .. " Gold" end
    if silver > 0 then parts[#parts + 1] = tostring(silver) .. " Silver" end
    if copper > 0 then parts[#parts + 1] = tostring(copper) .. " Copper" end
    return #parts > 0 and table.concat(parts, " ") or nil
end

local function CompactVendorListCurrencyName(name, useInitials)
    -- "Artisan" adds no distinguishing information in the narrow vendor
    -- list column.  Keep the profession readable first, then use familiar
    -- initials only when the whole cost still cannot fit.
    local profession = IsSafeText(name) and name:match("^Artisan%s+(.+)'s%s+Moxie$")
    if not profession then return name end
    if not useInitials then return profession .. "'s Moxie" end

    local initials = {}
    for word in ("Artisan " .. profession):gmatch("[%a]+") do
        initials[#initials + 1] = word:sub(1, 1):upper()
    end
    return #initials > 1 and table.concat(initials) .. " Moxie" or profession .. " Moxie"
end

local function GetVendorListCostText(button, costs, useMoxieInitials)
    local parts = {}
    if GetMerchantItemInfo and IsSafeNumber(button._merchantIndex) then
        local _, _, price = GetMerchantItemInfo(button._merchantIndex)
        local goldText = FormatVendorGoldCost(price)
        if goldText then parts[#parts + 1] = goldText end
    end
    for _, cost in ipairs(costs or {}) do
        local name = IsSafeText(cost.name) and cost.name or "Currency"
        name = CompactVendorListCurrencyName(name, useMoxieInitials == true)
        parts[#parts + 1] = tostring(cost.amount or 0) .. " " .. name
    end
    return #parts > 0 and table.concat(parts, " + ") or "Free"
end

function addon.ColorVendorListCurrencyCosts(text, costs, useMoxieInitials)
    for _, cost in ipairs(costs or {}) do
        local name = IsSafeText(cost.name) and cost.name or "Currency"
        name = CompactVendorListCurrencyName(name, useMoxieInitials == true)
        local segment = tostring(cost.amount or 0) .. " " .. name
        text = text:gsub(segment:gsub("(%W)", "%%%1"), ColorName(segment, cost.color), 1)
    end
    return text
end

local function FitVendorListText(fontString, value, maximum)
    fontString:SetText(value)
    if not (maximum and maximum > 0) or fontString:GetStringWidth() <= maximum then return value end

    local low, high, best = 1, #value, ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = value:sub(1, middle) .. "..."
        fontString:SetText(candidate)
        if fontString:GetStringWidth() <= maximum then
            best = candidate
            low = middle + 1
        else
            high = middle - 1
        end
    end
    fontString:SetText(best ~= "" and best or "...")
    return best ~= "" and best or "..."
end

local function SetVendorListRowBackground(button)
    local background = button._waffleListBackground
    if not (background and button._waffleListApplied) then return end
    local selected = button._waffleListMatchesSelectedCost == true
    local alternate = (button._waffleListIndex or 0) % 2 == 0
    if selected then
        -- A selected currency is a quiet change of the alternating-row tint,
        -- not a full neon outline around every adjacent row.  That preserves
        -- the visual rhythm of a compact list while still making matches
        -- immediately scannable.
        local alpha = alternate and 0.50 or 0.38
        if button._waffleListHovering then alpha = alpha + 0.10 end
        background:SetColorTexture(0.025, 0.19, 0.145, alpha)
    elseif GetSettings().vendorListAlternatingRows ~= false then
        local alpha = alternate and 0.30 or 0.13
        if button._waffleListHovering then alpha = alpha + 0.07 end
        background:SetColorTexture(0.03, 0.045, 0.055, alpha)
    elseif button._waffleListHovering then
        background:SetColorTexture(1, 1, 1, 0.055)
    else
        background:SetColorTexture(1, 1, 1, 0)
    end

    local divider = button._waffleListDivider
    if divider then
        -- Rows touch by design, so only the lower row boundary is drawn.  A
        -- single physical pixel prevents adjacent borders from becoming a
        -- visually heavy two-pixel rail.
        divider:SetColorTexture(1, 1, 1, selected and 0.12 or 0.065)
    end
end

local function SetVendorListNativeBorderVisible(button, visible)
    -- EllesmereUI Vendor Bags owns this existing full-button inset border.
    -- In grid view the button is an icon tile, but in our list view it spans
    -- the entire row, so leaving its rarity color visible paints around the
    -- item name and cost as well.
    local border = button and button.EUIVendorBagInsetBorder
    if type(border) ~= "table" then return end
    local method = visible and "Show" or "Hide"
    for _, side in ipairs({ border.top, border.bottom, border.left, border.right }) do
        if side and side[method] then side[method](side) end
    end
end

local function SetVendorListIconBorderColor(button, r, g, b)
    local border = button and button._waffleListIconBorder
    if border and border.SetColor then
        border:SetColor(r or 0.30, g or 0.30, b or 0.30, 0.95)
    end
end

local function EnsureVendorListRegions(button)
    if button._waffleListBackground then return end

    local background = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    background:SetAllPoints()
    button._waffleListBackground = background
    local divider = button:CreateTexture(nil, "ARTWORK", nil, 1)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")
    button._waffleListDivider = divider

    -- The host's quality border follows the stretched list-row button.
    -- This separate 28px host keeps the quality cue squarely on the icon
    -- while preserving the row's neutral divider and background treatment.
    local iconBorderHost = CreateFrame("Frame", nil, button)
    iconBorderHost:SetSize(28, 28)
    iconBorderHost:SetPoint("LEFT", button, "LEFT", 4, 0)
    iconBorderHost:SetFrameLevel(button:GetFrameLevel() + 4)
    iconBorderHost:EnableMouse(false)
    button._waffleListIconBorderHost = iconBorderHost
    if EllesmereUI and EllesmereUI.MakeBorder then
        button._waffleListIconBorder = EllesmereUI.MakeBorder(iconBorderHost, 0.30, 0.30, 0.30, 0.95)
    end

    local name = button:CreateFontString(nil, "OVERLAY", nil, 8)
    SetFont(name, 11)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    if name.SetMaxLines then name:SetMaxLines(1) end
    button._waffleListName = name

    local itemType = button:CreateFontString(nil, "OVERLAY", nil, 8)
    SetFont(itemType, 9)
    itemType:SetJustifyH("LEFT")
    itemType:SetWordWrap(false)
    if itemType.SetMaxLines then itemType:SetMaxLines(1) end
    button._waffleListType = itemType

    local rarity = button:CreateFontString(nil, "OVERLAY", nil, 8)
    SetFont(rarity, 9)
    rarity:SetJustifyH("LEFT")
    rarity:SetWordWrap(false)
    if rarity.SetMaxLines then rarity:SetMaxLines(1) end
    button._waffleListRarity = rarity

    local cost = button:CreateFontString(nil, "OVERLAY", nil, 8)
    SetFont(cost, 9)
    cost:SetJustifyH("RIGHT")
    cost:SetWordWrap(false)
    if cost.SetMaxLines then cost:SetMaxLines(1) end
    button._waffleListCost = cost

    button:HookScript("OnEnter", function(self)
        if self._waffleListApplied then
            self._waffleListHovering = true
            SetVendorListRowBackground(self)
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self._waffleListApplied then
            self._waffleListHovering = nil
            SetVendorListRowBackground(self)
        end
    end)
end

local function CaptureVendorListSnapshot(button)
    if button._waffleListSnapshot then return button._waffleListSnapshot end
    local slot = button.SlotParent or button:GetParent()
    if not slot then return nil end
    local snapshot = {
        slot = slot,
        slotAnchors = CaptureAnchors(slot),
        slotWidth = slot:GetWidth(),
        slotHeight = slot:GetHeight(),
        iconAnchors = button.icon and CaptureAnchors(button.icon) or nil,
        countAnchors = button.Count and CaptureAnchors(button.Count) or nil,
    }
    local control = button._wafflePlannerControl
    if control then
        snapshot.control = control
        snapshot.controlAnchors = CaptureAnchors(control)
        snapshot.controlWidth = control:GetWidth()
        snapshot.controlHeight = control:GetHeight()
        if control.icon then
            snapshot.controlIconAnchors = CaptureAnchors(control.icon)
            snapshot.controlIconWidth = control.icon:GetWidth()
            snapshot.controlIconHeight = control.icon:GetHeight()
        end
    end
    button._waffleListSnapshot = snapshot
    return snapshot
end

local function RestoreVendorListButton(button, costs)
    local snapshot = button._waffleListSnapshot
    if not snapshot then return end

    RestoreAnchors(snapshot.slot, snapshot.slotAnchors)
    snapshot.slot:SetSize(snapshot.slotWidth, snapshot.slotHeight)
    if button.icon then
        RestoreAnchors(button.icon, snapshot.iconAnchors)
        button.icon:SetScale(ICON_SCALE)
    end
    if button.Count then RestoreAnchors(button.Count, snapshot.countAnchors) end
    if snapshot.control then
        RestoreAnchors(snapshot.control, snapshot.controlAnchors)
        snapshot.control:SetSize(snapshot.controlWidth, snapshot.controlHeight)
        if snapshot.control.icon then
            RestoreAnchors(snapshot.control.icon, snapshot.controlIconAnchors)
            snapshot.control.icon:SetSize(snapshot.controlIconWidth, snapshot.controlIconHeight)
        end
    end

    if button.StockText then button.StockText:Show() end
    if button.PriceText then button.PriceText:Show() end
    if button._waffleListBackground then button._waffleListBackground:Hide() end
    if button._waffleListDivider then button._waffleListDivider:Hide() end
    if button._waffleListIconBorderHost then button._waffleListIconBorderHost:Hide() end
    SetVendorListNativeBorderVisible(button, true)
    if button._waffleListName then button._waffleListName:Hide() end
    if button._waffleListType then button._waffleListType:Hide() end
    if button._waffleListRarity then button._waffleListRarity:Hide() end
    if button._waffleListCost then button._waffleListCost:Hide() end
    button._waffleListHovering = nil
    button._waffleListMatchesSelectedCost = nil
    button._waffleListApplied = nil
    button._waffleListSnapshot = nil
    UpdatePriceLabel(button, costs)
end

function addon.GetVendorListHeaderDropIndex(header, cursorX)
    if not (header and type(cursorX) == "number") then return nil end
    local visible = header._waffleListVisibleColumns or {}
    local dropIndex = #visible + 1
    for index, key in ipairs(visible) do
        local candidate = header.columnControls and header.columnControls[key]
        local left = candidate and candidate.GetLeft and candidate:GetLeft()
        local right = candidate and candidate.GetRight and candidate:GetRight()
        if left and right and cursorX < (left + right) / 2 then
            dropIndex = index
            break
        end
    end
    return dropIndex
end

function addon.SetVendorListHeaderDropGuide(header, dropIndex)
    local guide = header and header._waffleListDropGuide
    local visible = header and header._waffleListVisibleColumns or {}
    if not (guide and dropIndex and #visible > 0) then
        if guide then guide:Hide() end
        return
    end

    local referenceKey = visible[dropIndex] or visible[#visible]
    local reference = header.columnControls and header.columnControls[referenceKey]
    local x
    if reference and reference.GetLeft and reference.GetRight and header.GetLeft then
        if visible[dropIndex] then
            x = reference:GetLeft() - header:GetLeft()
        else
            x = reference:GetRight() - header:GetLeft()
        end
    end
    if not x then guide:Hide(); return end

    guide:ClearAllPoints()
    guide:SetPoint("TOP", header, "TOPLEFT", x - 1, 2)
    guide:SetPoint("BOTTOM", header, "BOTTOMLEFT", x - 1, -2)
    guide:Show()
end

function addon.HasVendorListHeaderHoldElapsed(press)
    if not (press and press.startedAt) then return false end
    if not GetTime then return true end
    return GetTime() - press.startedAt >= addon.VendorListDragHoldSeconds
end

function addon.UpdateVendorListHeaderDrag(header)
    local resizePress = header and header._waffleListResizePress
    if resizePress then
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            addon.FinishVendorListHeaderResizePress(header, resizePress.divider)
            return
        end
        if addon.HasVendorListHeaderHoldElapsed(resizePress) then
            header._waffleListResizePress = nil
            addon.BeginVendorListHeaderResize(header, resizePress.divider)
        end
        return
    end

    local headerPress = header and header._waffleListHeaderPress
    if headerPress then
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            addon.FinishVendorListHeaderPress(header, headerPress.control)
            return
        end
        if addon.HasVendorListHeaderHoldElapsed(headerPress) then
            header._waffleListHeaderPress = nil
            addon.BeginVendorListHeaderDrag(header, headerPress.control)
        end
        return
    end

    if header and header._waffleListResizeDivider then
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            addon.FinishVendorListHeaderResize(header)
            return
        end
        addon.UpdateVendorListHeaderResize(header)
        return
    end
    local columnKey = header and header._waffleListDragColumn
    if not columnKey then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        addon.FinishVendorListHeaderDrag(header, columnKey)
        return
    end
    if not (GetCursorPosition and UIParent) then return end
    local cursorX = GetCursorPosition()
    local scale = header.GetEffectiveScale and header:GetEffectiveScale() or 1
    if type(cursorX) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
    local dropIndex = addon.GetVendorListHeaderDropIndex(header, cursorX / scale)
    header._waffleListDragDropIndex = dropIndex
    addon.SetVendorListHeaderDropGuide(header, dropIndex)
end

function addon.BeginVendorListHeaderPress(header, control)
    local columnKey = control and control._waffleListColumnKey
    if not (header and columnKey) or header._waffleListDragColumn or header._waffleListResizeDivider
        or header._waffleListHeaderPress or header._waffleListResizePress then return end
    header._waffleListHeaderPress = {
        control = control,
        startedAt = GetTime and GetTime() or 0,
    }
    header:SetScript("OnUpdate", addon.UpdateVendorListHeaderDrag)
end

function addon.FinishVendorListHeaderPress(header, control)
    local press = header and header._waffleListHeaderPress
    if press and press.control == control then
        header._waffleListHeaderPress = nil
        header:SetScript("OnUpdate", nil)
        if addon.ToggleVendorListSort(control._waffleListColumnKey) then
            control._waffleListSortHandled = true
            if QueueRefresh then QueueRefresh() end
        end
        return
    end
    local columnKey = control and control._waffleListColumnKey
    if header and columnKey then addon.FinishVendorListHeaderDrag(header, columnKey) end
end

function addon.BeginVendorListHeaderDrag(header, control)
    local columnKey = control and control._waffleListColumnKey
    if not (header and columnKey) or header._waffleListDragColumn or header._waffleListResizeDivider then return end
    header._waffleListDragColumn = columnKey
    if control.label then control.label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end
    header:SetScript("OnUpdate", addon.UpdateVendorListHeaderDrag)
    addon.UpdateVendorListHeaderDrag(header)
end

function addon.FinishVendorListHeaderDrag(header, columnKey)
    if not (header and header._waffleListDragColumn == columnKey) then return end
    header._waffleListDragColumn = nil
    header:SetScript("OnUpdate", nil)
    addon.SetVendorListHeaderDropGuide(header, nil)
    local control = header.columnControls and header.columnControls[columnKey]
    if control and control.label then control.label:SetTextColor(0.58, 0.58, 0.58, 1) end
    if not (GetCursorPosition and UIParent) then return end

    local cursorX = GetCursorPosition()
    local scale = header.GetEffectiveScale and header:GetEffectiveScale() or 1
    if type(cursorX) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
    local dropIndex = header._waffleListDragDropIndex
        or addon.GetVendorListHeaderDropIndex(header, cursorX / scale)
    header._waffleListDragDropIndex = nil
    if not dropIndex then return end

    local visible = header._waffleListVisibleColumns or {}

    -- Convert a visible-column drop position to the persistent full order.
    -- Type is the only column that can be hidden on a very narrow window.
    local fullOrder = addon.GetVendorListColumnOrder()
    local targetKey = visible[dropIndex]
    local fullDrop = #fullOrder + 1
    if targetKey then
        for index, key in ipairs(fullOrder) do
            if key == targetKey then fullDrop = index; break end
        end
    elseif #visible > 0 then
        local lastKey = visible[#visible]
        for index, key in ipairs(fullOrder) do
            if key == lastKey then fullDrop = index + 1; break end
        end
    end
    if addon.MoveVendorListColumn(columnKey, fullDrop) and QueueRefresh then QueueRefresh() end
end

function addon.UpdateVendorListHeaderSortLabels(header)
    if not header then return end
    local columnKey, ascending = addon.GetVendorListSort()
    for key, control in pairs(header.columnControls or {}) do
        local active = key == columnKey
        local marker = active and (ascending and "▲" or "▼") or nil
        if control.label then
            control.label:ClearAllPoints()
            control.label:SetPoint("TOPLEFT")
            control.label:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", marker and -11 or 0, 0)
            control.label:SetText(marker and (key == "icon" or key == "pin")
                and "" or (addon.VendorListColumnText[key] or ""))
            local r, g, b = active and ACCENT_R or 0.58, active and ACCENT_G or 0.58, active and ACCENT_B or 0.58
            control.label:SetTextColor(r, g, b, 1)
            if control.sortMarker then
                control.sortMarker:SetText(marker or "")
                control.sortMarker:SetTextColor(r, g, b, 1)
                control.sortMarker:ClearAllPoints()
                if key == "icon" or key == "pin" then
                    control.sortMarker:SetPoint("CENTER")
                else
                    control.sortMarker:SetPoint("RIGHT", control, "RIGHT", -1, 0)
                end
                control.sortMarker:SetShown(marker ~= nil)
            end
        end
        for _, part in ipairs(control.shoppingListIconParts or {}) do
            part:SetShown(not active)
        end
    end
end

local function EnsureVendorListHeader(frame)
    if frame._waffleListHeader then return frame._waffleListHeader end
    local header = CreateFrame("Frame", nil, frame.ScrollChild)
    header:SetHeight(LIST_HEADER_H)
    -- Vendor Bags reuses item rows and can leave their transparent click
    -- frames above newly-created children.  Give the list header an explicit
    -- interaction level so every column title remains directly draggable.
    header:SetFrameLevel((frame.ScrollChild:GetFrameLevel() or 0) + 20)
    header:EnableMouse(true)
    header._waffleListHeader = true
    header.background = header:CreateTexture(nil, "BACKGROUND")
    header.background:SetAllPoints()
    header.background:SetColorTexture(0.025, 0.035, 0.045, 0.78)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    header.line:SetColorTexture(1, 1, 1, 0.12)
    header._waffleListDropGuide = header:CreateTexture(nil, "OVERLAY")
    header._waffleListDropGuide:SetWidth(2)
    header._waffleListDropGuide:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.95)
    header._waffleListDropGuide:Hide()
    header._waffleListOwner = frame

    header.columnControls = {}
    for _, key in ipairs(addon.VendorListColumnDefault) do
        local control = CreateFrame("Button", nil, header)
        control:EnableMouse(true)
        control:RegisterForClicks("LeftButtonUp")
        control:SetFrameLevel(header:GetFrameLevel() + 1)
        control._waffleListColumnKey = key
        local label = control:CreateFontString(nil, "OVERLAY")
        label:SetAllPoints()
        SetFont(label, 8)
        label:SetText(addon.VendorListColumnText[key])
        label:SetTextColor(0.58, 0.58, 0.58, 1)
        control.label = label
        control.sortMarker = control:CreateFontString(nil, "OVERLAY")
        control.sortMarker:SetFont(VENDOR_SORT_GLYPH_FONT, 9, "OUTLINE")
        control.sortMarker:SetJustifyH("CENTER")
        control.sortMarker:Hide()
        if key == "pin" then
            -- A compact checklist says what this column does at a glance. A
            -- literal PIN header was too ambiguous beside an already-visible
            -- pin control in every row.
            control.shoppingListIconParts = {}
            for line = 1, 3 do
                local check = control:CreateTexture(nil, "OVERLAY")
                check:SetSize(2, 2)
                check:SetPoint("LEFT", control, "CENTER", -6, 4 - ((line - 1) * 4))
                check:SetColorTexture(0.58, 0.58, 0.58, 1)
                control.shoppingListIconParts[#control.shoppingListIconParts + 1] = check
                local stroke = control:CreateTexture(nil, "OVERLAY")
                stroke:SetSize(7, 1)
                stroke:SetPoint("LEFT", check, "RIGHT", 2, 0)
                stroke:SetColorTexture(0.58, 0.58, 0.58, 1)
                control.shoppingListIconParts[#control.shoppingListIconParts + 1] = stroke
            end
        end
        control:SetScript("OnEnter", function(self)
            if header._waffleListDragColumn ~= self._waffleListColumnKey then
                self.label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            end
            for _, part in ipairs(self.shoppingListIconParts or {}) do part:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1) end
            if GameTooltip then
                local description = self._waffleListColumnKey == "pin"
                    and "Shopping List — pin or unpin this vendor item. Click to sort; hold for 0.25 seconds to move the column."
                    or "Click to sort ascending or descending. Hold for 0.25 seconds to move this column."
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(description, 0.82, 0.82, 0.82, 1, true)
                GameTooltip:Show()
                self._waffleHeaderTooltipShown = true
            end
        end)
        control:SetScript("OnLeave", function(self)
            if header._waffleListDragColumn ~= self._waffleListColumnKey then
                local active = addon.GetVendorListSort()
                self.label:SetTextColor(active == self._waffleListColumnKey and ACCENT_R or 0.58,
                    active == self._waffleListColumnKey and ACCENT_G or 0.58,
                    active == self._waffleListColumnKey and ACCENT_B or 0.58, 1)
            end
            local active = addon.GetVendorListSort()
            for _, part in ipairs(self.shoppingListIconParts or {}) do
                part:SetColorTexture(active == self._waffleListColumnKey and ACCENT_R or 0.58,
                    active == self._waffleListColumnKey and ACCENT_G or 0.58,
                    active == self._waffleListColumnKey and ACCENT_B or 0.58, 1)
            end
            if self._waffleHeaderTooltipShown and GameTooltip then GameTooltip:Hide() end
            self._waffleHeaderTooltipShown = nil
        end)
        control:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "LeftButton" then
                self._waffleListSortHandled = nil
                addon.BeginVendorListHeaderPress(header, self)
            end
        end)
        control:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "LeftButton" then
                addon.FinishVendorListHeaderPress(header, self)
            end
        end)
        -- Retail may deliver OnClick after OnMouseUp. The guard prevents that
        -- second callback from reversing a sort that MouseUp already handled.
        -- If MouseUp is swallowed by another overlay, OnClick still completes
        -- the pending short press.
        control:SetScript("OnClick", function(self, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            if self._waffleListSortHandled then
                self._waffleListSortHandled = nil
            elseif header._waffleListHeaderPress and header._waffleListHeaderPress.control == self then
                addon.FinishVendorListHeaderPress(header, self)
            end
        end)
        header.columnControls[key] = control
    end

    header.resizeControls = {}
    for _, key in ipairs(addon.VendorListColumnDefault) do
        local divider = CreateFrame("Button", nil, header)
        divider:EnableMouse(true)
        divider:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        divider:SetFrameLevel(header:GetFrameLevel() + 3)
        if divider.SetPropagateMouseClicks then divider:SetPropagateMouseClicks(false) end
        divider.line = divider:CreateTexture(nil, "OVERLAY")
        divider.line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.95)
        divider.line:Hide()
        divider:SetScript("OnEnter", function(self)
            self._waffleListResizeHovering = true
            if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, "Hold for 0.25 seconds, then drag to resize the columns on either side.")
            end
        end)
        divider:SetScript("OnLeave", function(self)
            self._waffleListResizeHovering = nil
            if self.line and header._waffleListResizeDivider ~= self then self.line:Hide() end
            if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        divider:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "LeftButton" then addon.BeginVendorListHeaderResizePress(header, self) end
        end)
        divider:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "LeftButton" then addon.FinishVendorListHeaderResizePress(header, divider) end
        end)
        header.resizeControls[key] = divider
    end
    frame._waffleListHeader = header
    return header
end

function addon.LayoutVendorListHeader(header, layout)
    header._waffleListVisibleColumns = layout.order
    header._waffleListColumnLayout = layout
    header._waffleListScrollWidth = layout.scrollWidth
    for key, control in pairs(header.columnControls or {}) do
        local column = layout.columns[key]
        if column then
            control:ClearAllPoints()
            control:SetPoint("LEFT", header, "LEFT", column.x, 0)
            control:SetSize(column.width, LIST_HEADER_H)
            control.label:SetJustifyH((key == "cost" and "RIGHT") or ((key == "icon" or key == "pin") and "CENTER") or "LEFT")
            control:Show()
        else
            control:Hide()
        end
    end
    addon.UpdateVendorListHeaderSortLabels(header)
    if addon.LayoutVendorListHeaderResizeControls then
        addon.LayoutVendorListHeaderResizeControls(header, layout)
    end
end

function addon.GetVendorListHeaderCursorX(header)
    if not (header and GetCursorPosition and header.GetEffectiveScale and header.GetLeft) then return nil end
    local cursorX, scale, left = GetCursorPosition(), header:GetEffectiveScale(), header:GetLeft()
    if type(cursorX) ~= "number" or type(scale) ~= "number" or scale <= 0 or type(left) ~= "number" then return nil end
    return cursorX / scale - left
end

function addon.LayoutVendorListHeaderResizeControls(header, layout)
    if not (header and layout and header.resizeControls) then return end
    local order, columns = layout.order or {}, layout.columns or {}
    for _, divider in pairs(header.resizeControls) do
        divider:Hide()
        if divider.line then divider.line:Hide() end
    end
    for index = 1, #order - 1 do
        local leftKey, rightKey = order[index], order[index + 1]
        local leftColumn = columns[leftKey]
        local divider = header.resizeControls[leftKey]
        if divider and leftColumn then
            divider._waffleListResizeLeftKey = leftKey
            divider._waffleListResizeRightKey = rightKey
            divider:ClearAllPoints()
            -- A forgiving eight-pixel hit area, while the visible one-pixel
            -- divider remains confined to this header and stays hidden until
            -- an intentional held drag begins.
            divider:SetPoint("LEFT", header, "LEFT", leftColumn.x + leftColumn.width - 4, 0)
            divider:SetSize(8, LIST_HEADER_H)
            if divider.line then
                divider.line:ClearAllPoints()
                divider.line:SetPoint("TOP", divider, "TOP", 0, 3)
                divider.line:SetPoint("BOTTOM", divider, "BOTTOM", 0, -3)
                divider.line:SetWidth(1)
                divider.line:SetShown(header._waffleListResizeDivider == divider)
            end
            divider:Show()
        end
    end
end

function addon.BeginVendorListHeaderResizePress(header, divider)
    if not (header and divider and divider._waffleListResizeLeftKey and divider._waffleListResizeRightKey)
        or header._waffleListDragColumn or header._waffleListResizeDivider
        or header._waffleListHeaderPress or header._waffleListResizePress then return end
    header._waffleListResizePress = {
        divider = divider,
        startedAt = GetTime and GetTime() or 0,
    }
    header:SetScript("OnUpdate", addon.UpdateVendorListHeaderDrag)
end

function addon.FinishVendorListHeaderResizePress(header, divider)
    local press = header and header._waffleListResizePress
    if press and press.divider == divider then
        header._waffleListResizePress = nil
        header:SetScript("OnUpdate", nil)
        if divider.line then divider.line:Hide() end
        return
    end
    if header and header._waffleListResizeDivider == divider then
        addon.FinishVendorListHeaderResize(header)
    end
end

function addon.BeginVendorListHeaderResize(header, divider)
    if not (header and divider and divider._waffleListResizeLeftKey and divider._waffleListResizeRightKey)
        or header._waffleListDragColumn or header._waffleListResizeDivider then return end
    local layout = header._waffleListColumnLayout
    local left = layout and layout.columns and layout.columns[divider._waffleListResizeLeftKey]
    local right = layout and layout.columns and layout.columns[divider._waffleListResizeRightKey]
    local cursorX = addon.GetVendorListHeaderCursorX(header)
    if not (left and right and cursorX) then return end
    header._waffleListResizeDivider = divider
    header._waffleListResize = {
        leftKey = divider._waffleListResizeLeftKey,
        rightKey = divider._waffleListResizeRightKey,
        cursorX = cursorX,
        leftWidth = left.width,
        rightWidth = right.width,
    }
    if divider.line then divider.line:Show() end
    header:SetScript("OnUpdate", addon.UpdateVendorListHeaderDrag)
end

function addon.UpdateVendorListHeaderResize(header)
    local resize = header and header._waffleListResize
    if not resize then return end
    local cursorX = addon.GetVendorListHeaderCursorX(header)
    local layout = header._waffleListColumnLayout
    if not (cursorX and layout and layout.minimums) then return end
    local minimums = layout.minimums
    local minimumDelta = (minimums[resize.leftKey] or 1) - resize.leftWidth
    local maximumDelta = resize.rightWidth - (minimums[resize.rightKey] or 1)
    local delta = math.max(minimumDelta, math.min(maximumDelta, math.floor(cursorX - resize.cursorX + 0.5)))
    local leftWidth, rightWidth = resize.leftWidth + delta, resize.rightWidth - delta
    if resize.lastLeft == leftWidth and resize.lastRight == rightWidth then return end
    resize.lastLeft, resize.lastRight = leftWidth, rightWidth
    local settings = GetSettings()
    settings.vendorListColumnWidths = type(settings.vendorListColumnWidths) == "table" and settings.vendorListColumnWidths or {}
    settings.vendorListColumnWidths[resize.leftKey] = leftWidth
    settings.vendorListColumnWidths[resize.rightKey] = rightWidth
    -- Reflow header immediately so the drag follows the pointer; the coalesced
    -- refresh below applies the same layout to all pooled item rows next frame.
    addon.LayoutVendorListHeader(header, addon.GetVendorListColumnLayout(header._waffleListScrollWidth))
    if QueueRefresh then QueueRefresh() end
end

function addon.FinishVendorListHeaderResize(header)
    local divider = header and header._waffleListResizeDivider
    if not divider then return end
    header._waffleListResizeDivider, header._waffleListResize = nil, nil
    header:SetScript("OnUpdate", nil)
    if divider.line and not divider._waffleListResizeHovering then divider.line:Hide() end
    if QueueRefresh then QueueRefresh() end
end

local function SetGridHeadersForList(frame, enabled)
    if not frame.ScrollChild then return end
    for _, child in ipairs({ frame.ScrollChild:GetChildren() }) do
        if child.label and child.line and child ~= frame._waffleListHeader then
            if enabled then
                if child._waffleListWasShown == nil then
                    child._waffleListWasShown = child:IsShown()
                end
                child:Hide()
            elseif child._waffleListWasShown ~= nil then
                if child._waffleListWasShown then child:Show() end
                child._waffleListWasShown = nil
            end
        end
    end
end

function addon.ApplyVendorListEmptyState(frame, isEmpty)
    local label = frame and frame.EmptyLabel
    if not label then return end
    if not frame._waffleListEmptyState then
        frame._waffleListEmptyState = {
            anchors = CaptureAnchors(label),
            wasShown = label:IsShown(),
        }
    end

    -- Vendor Bags normally anchors this at the top of the grid.  In list
    -- view that is the reserved column-header space, so always place its
    -- native empty copy just below our header instead.
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 16, -(LIST_HEADER_H + 12))
    label:SetShown(isEmpty == true)
end

local function RestoreEasyAccessItemList(frame, buttons, costsByMerchant)
    if frame._waffleListHeader then frame._waffleListHeader:Hide() end
    SetGridHeadersForList(frame, false)
    local emptyState = frame._waffleListEmptyState
    if emptyState and frame.EmptyLabel then
        RestoreAnchors(frame.EmptyLabel, emptyState.anchors)
        frame.EmptyLabel:SetShown(emptyState.wasShown)
        frame._waffleListEmptyState = nil
    end
    for _, button in ipairs(buttons) do
        RestoreVendorListButton(button, costsByMerchant[button._merchantIndex] or {})
    end
    if frame._waffleListScrollHeight then
        frame.ScrollChild:SetHeight(frame._waffleListScrollHeight)
        frame._waffleListScrollHeight = nil
    end
end

local function ApplyEasyAccessItemList(frame, buttons, costsByMerchant)
    if GetSettings().vendorItemView ~= "list" then
        RestoreEasyAccessItemList(frame, buttons, costsByMerchant)
        return
    end

    if not frame._waffleListScrollHeight then
        frame._waffleListScrollHeight = frame.ScrollChild:GetHeight()
    end
    SetGridHeadersForList(frame, true)
    local header = EnsureVendorListHeader(frame)
    local scrollWidth = math.max(150, math.floor(frame.ScrollChild:GetWidth() or frame.ScrollFrame:GetWidth() or 150))
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 3, -2)
    header:SetWidth(math.max(1, scrollWidth - 6))
    local columnLayout = addon.GetVendorListColumnLayout(scrollWidth)
    addon.LayoutVendorListHeader(header, columnLayout)
    header:Show()

    local visible = {}
    for _, button in ipairs(buttons) do
        if button:IsShown() and (button.SlotParent or button:GetParent()):IsShown() then
            visible[#visible + 1] = button
        end
    end
    addon.SortVendorListRows(visible, costsByMerchant)
    addon.ApplyVendorListEmptyState(frame, #visible == 0)

    for index, button in ipairs(visible) do
        EnsureVendorListRegions(button)
        local snapshot = CaptureVendorListSnapshot(button)
        if snapshot then
            local slot = snapshot.slot
            local y = -(LIST_HEADER_H + 3 + (index - 1) * LIST_ROW_H)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 3, y)
            slot:SetSize(math.max(1, scrollWidth - 6), LIST_ROW_H)
            local iconColumn = columnLayout.columns.icon
            local pinColumn = columnLayout.columns.pin
            local itemColumn = columnLayout.columns.item
            local typeColumn = columnLayout.columns.type
            local rarityColumn = columnLayout.columns.rarity
            local costColumn = columnLayout.columns.cost
            if button.icon then
                button.icon:ClearAllPoints()
                button.icon:SetPoint("LEFT", button, "LEFT", iconColumn.x + 1, 0)
                button.icon:SetSize(26, 26)
                button.icon:SetScale(1)
            end
            if button._waffleListIconBorderHost then
                button._waffleListIconBorderHost:ClearAllPoints()
                button._waffleListIconBorderHost:SetPoint("LEFT", button, "LEFT", iconColumn.x, 0)
            end
            if button.Count then
                button.Count:ClearAllPoints()
                button.Count:SetPoint("BOTTOMRIGHT", button.icon or button, "BOTTOMRIGHT", -3, 3)
            end
            if snapshot.control then
                local control = snapshot.control
                control:ClearAllPoints()
                control:SetPoint("LEFT", button, "LEFT", pinColumn.x, 0)
                control:SetSize(24, LIST_ROW_H)
                if control.icon then
                    control.icon:ClearAllPoints()
                    control.icon:SetPoint("CENTER")
                    control.icon:SetSize(18, 18)
                end
            end

            if button.StockText then button.StockText:Hide() end
            if button.PriceText then button.PriceText:Hide() end
            if button._waffleCostText then button._waffleCostText:Hide() end

            local name = GetVendorListItemName(button)
            local r, g, b = GetVendorListItemColor(button)
            local nameLabel = button._waffleListName
            local typeLabel = button._waffleListType
            local rarityLabel = button._waffleListRarity
            local costLabel = button._waffleListCost
            local affordable = CanAffordMerchantItem(button._merchantIndex, costsByMerchant[button._merchantIndex] or {})
            costLabel:ClearAllPoints()
            costLabel:SetPoint("LEFT", button, "LEFT", costColumn.x, 0)
            costLabel:SetWidth(costColumn.width)
            local itemCosts = costsByMerchant[button._merchantIndex] or {}
            local costText = GetVendorListCostText(button, itemCosts)
            local useMoxieInitials = false
            -- Prefer "Blacksmith's Moxie" over an opaque abbreviation.  If
            -- an unusually narrow frame or multi-cost item still cannot fit,
            -- fall back to "AB Moxie" before the final visual ellipsis.
            costLabel:SetText(costText)
            if costLabel:GetStringWidth() > costColumn.width then
                costText = GetVendorListCostText(button, itemCosts, true)
                useMoxieInitials = true
            end
            costText = FitVendorListText(costLabel, costText, costColumn.width)
            if affordable then
                costText = addon.ColorVendorListCurrencyCosts(costText, itemCosts, useMoxieInitials)
                costLabel:SetText(costText)
            end
            costLabel:SetTextColor(affordable and 0.73 or 1, affordable and 0.73 or 0.25, affordable and 0.73 or 0.25, 1)
            nameLabel:ClearAllPoints()
            nameLabel:SetPoint("LEFT", button, "LEFT", itemColumn.x, 0)
            nameLabel:SetWidth(itemColumn.width)
            FitVendorListText(nameLabel, name, itemColumn.width)
            nameLabel:SetTextColor(r, g, b, 1)
            if typeColumn then
                typeLabel:ClearAllPoints()
                typeLabel:SetPoint("LEFT", button, "LEFT", typeColumn.x, 0)
                typeLabel:SetWidth(typeColumn.width)
                FitVendorListText(typeLabel, addon.GetVendorListItemType(button), typeColumn.width)
                typeLabel:SetTextColor(0.62, 0.70, 0.72, 1)
            end
            if rarityColumn then
                rarityLabel:ClearAllPoints()
                rarityLabel:SetPoint("LEFT", button, "LEFT", rarityColumn.x, 0)
                rarityLabel:SetWidth(rarityColumn.width)
                FitVendorListText(rarityLabel, addon.GetVendorListRarityText(button), rarityColumn.width)
                rarityLabel:SetTextColor(r, g, b, 1)
            end
            SetVendorListNativeBorderVisible(button, false)
            SetVendorListIconBorderColor(button, r, g, b)

            button._waffleListIndex = index
            button._waffleListMatchesSelectedCost = ButtonUsesCost(costsByMerchant[button._merchantIndex] or {}, selectedCostKey)
            button._waffleListApplied = true
            button._waffleListBackground:Show()
            button._waffleListDivider:Show()
            button._waffleListIconBorderHost:Show()
            nameLabel:Show()
            typeLabel:SetShown(typeColumn ~= nil)
            rarityLabel:SetShown(rarityColumn ~= nil)
            costLabel:Show()
            SetVendorListRowBackground(button)
        end
    end

    for _, button in ipairs(buttons) do
        if not button._waffleListApplied then
            RestoreVendorListButton(button, costsByMerchant[button._merchantIndex] or {})
        end
    end

    local contentHeight = math.max(LIST_HEADER_H + 6 + #visible * LIST_ROW_H, frame.ScrollFrame:GetHeight())
    frame.ScrollChild:SetHeight(contentHeight)
    if frame.ScrollFrame.SetVerticalScroll and frame.ScrollFrame.GetVerticalScroll and frame.ScrollFrame.GetVerticalScrollRange then
        frame.ScrollFrame:SetVerticalScroll(math.min(frame.ScrollFrame:GetVerticalScroll(), frame.ScrollFrame:GetVerticalScrollRange()))
    end
end

function addon.IsVendorPurchaseModifierDown()
    return (IsModifierKeyDown and IsModifierKeyDown())
        or (IsControlKeyDown and IsControlKeyDown())
        or (IsShiftKeyDown and IsShiftKeyDown())
        or (IsAltKeyDown and IsAltKeyDown()) or false
end

function addon.IsVendorStackPurchaseClick(mouseButton)
    return mouseButton == "RightButton" and IsShiftKeyDown and IsShiftKeyDown()
        and not (IsControlKeyDown and IsControlKeyDown())
        and not (IsAltKeyDown and IsAltKeyDown())
end

function addon.GuardVendorPurchase(button)
    local nativeClick = button:GetScript("OnClick")
    if not nativeClick or nativeClick == button._wafflePurchaseGuard then return end

    if not button._wafflePurchaseMouseHooked then
        button:HookScript("OnMouseDown", function(self, mouseButton)
            self._wafflePurchaseModifiedDown = addon.IsVendorPurchaseModifierDown()
            self._wafflePurchaseStackDown = addon.IsVendorStackPurchaseClick(mouseButton)
        end)
        button:HookScript("OnHide", function(self)
            self._wafflePurchaseModifiedDown = nil
            self._wafflePurchaseStackDown = nil
            if addon.CloseVendorStackPicker then addon.CloseVendorStackPicker(self) end
        end)
        button._wafflePurchaseMouseHooked = true
    end

    local guardedClick = function(self, mouseButton, ...)
        local modified = self._wafflePurchaseModifiedDown or addon.IsVendorPurchaseModifierDown()
        local stackClick = mouseButton == "RightButton" and (self._wafflePurchaseStackDown or addon.IsVendorStackPurchaseClick(mouseButton))
        self._wafflePurchaseModifiedDown = nil
        self._wafflePurchaseStackDown = nil
        if stackClick and not self._isBuyback and type(addon.OpenVendorStackPicker) == "function" then
            addon.OpenVendorStackPicker(self)
            return
        end
        if modified then
            -- The native handler buys when HandleModifiedItemClick returns
            -- false (for example Ctrl-clicking an item with no preview).
            -- Preserve preview/link actions, but never run its purchase path.
            if IsSafeText(self._link) and HandleModifiedItemClick then
                HandleModifiedItemClick(self._link)
            end
            return
        end
        return nativeClick(self, mouseButton, ...)
    end
    button._wafflePurchaseGuard = guardedClick
    button:SetScript("OnClick", guardedClick)
end

local function FindVendorButtons(frame)
    local buttons = {}
    if not (frame and frame.ScrollChild) then return buttons end

    for _, slotParent in ipairs({ frame.ScrollChild:GetChildren() }) do
        local button = slotParent:GetChildren()
        if button and IsSafeNumber(button._merchantIndex) then
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

local function WireRefreshTriggers(frame)
    if not frame._euvxSizeHooked then
        frame:HookScript("OnSizeChanged", QueueRefresh)
        frame._euvxSizeHooked = true
    end
    if frame.ScrollChild and not frame._euvxListRenderHooked then
        -- Vendor Bags redraws its pooled grid while its corner resize is in
        -- progress, then performs one final redraw when the mouse releases.
        -- Its ScrollChild height is written at the end of every renderer
        -- pass, which gives us a stable, post-render signal without changing
        -- any Vendor Bags source code.
        hooksecurefunc(frame.ScrollChild, "SetHeight", function()
            if frame._waffleListApplying or GetSettings().vendorItemView ~= "list" then return end
            -- Sorting bags can make Vendor Bags rebuild its pooled scroll
            -- child even though no merchant data changed.  Do not mistake
            -- that temporary host redraw for a vendor-list reflow; doing so
            -- repeatedly forces items back to the top during the sort.
            if frame._waffleListIgnoreHostRenderUntilBagSettles then return end
            if frame._liveWindowWidth or frame._liveWindowHeight then
                frame._waffleListRefreshAfterResize = true
                return
            end
            QueueRefresh()
        end)
        frame._euvxListRenderHooked = true
    end
    if frame.SearchBox and not frame.SearchBox._euvxRefreshHooked then
        frame.SearchBox:HookScript("OnTextChanged", QueueRefresh)
        frame.SearchBox._euvxRefreshHooked = true
    end
    if frame.SidebarCollapseButton and not frame.SidebarCollapseButton._euvxRefreshHooked then
        frame.SidebarCollapseButton:HookScript("OnClick", QueueRefresh)
        frame.SidebarCollapseButton._euvxRefreshHooked = true
    end
    if frame.SidebarChild then
        for _, button in ipairs({ frame.SidebarChild:GetChildren() }) do
            if button._categoryIndex ~= nil and not button._euvxRefreshHooked then
                button:HookScript("OnClick", QueueRefresh)
                button._euvxRefreshHooked = true
            end
        end
    end
end

function addon.Refresh()
    local frame = _G.EUI_VendorBagFrame
    if not (frame and frame:IsShown() and frame.ScrollChild and frame.ScrollFrame and frame.Footer) then return end

    local buttons = FindVendorButtons(frame)
    -- Install purchase protection before layout or optional item decorations
    -- can fail, and before the live-resize path defers presentation updates.
    for _, button in ipairs(buttons) do addon.GuardVendorPurchase(button) end
    WireRefreshTriggers(frame)
    -- Do not compete with the host renderer while a corner is held.  Its
    -- release path redraws the dataset and the ScrollChild hook above queues
    -- one clean list layout after that final native pass completes.
    if GetSettings().vendorItemView == "list" and (frame._liveWindowWidth or frame._liveWindowHeight) then
        frame._waffleListRefreshAfterResize = true
        return
    end
    local entries, costsByMerchant = CollectVendorCosts()
    LayoutPanel(frame, entries)

    local listView = GetSettings().vendorItemView == "list"
    -- Restore the host's normal item anchors before the grid tracker resumes.
    -- This also means switching views never leaves a pooled Vendor Bags slot
    -- stretched into a row.
    if not listView then
        RestoreEasyAccessItemList(frame, buttons, costsByMerchant)
    end
    for _, button in ipairs(buttons) do
        if not button._euvxTooltipHooked then
            button:HookScript("OnEnter", AppendCostTooltip)
            button._euvxTooltipHooked = true
        end
        if button.icon then
            button.icon:SetScale(ICON_SCALE)
        end

        local costs = costsByMerchant[button._merchantIndex] or {}
        UpdatePriceLabel(button, costs)
        EnsureVendorPlannerControl(button, costs)
        -- Grid tiles use EUI's existing outline.  Compact list rows instead
        -- receive a subtle alternating-row tint so adjacent matches never
        -- stack their borders into a thick, neon divider.
        EnsureHighlight(button):SetShown(not listView and ButtonUsesCost(costs, selectedCostKey))
        local affordable = CanAffordMerchantItem(button._merchantIndex, costs)
        if button._waffleCostText and button._waffleCostText:IsShown() and not affordable then
            button._waffleCostText:SetTextColor(1, 0.25, 0.25, 1)
        end
        ApplyVendorFilters(button, costs)
    end

    if addon.LayoutVendorTracking then
        addon.LayoutVendorTracking(frame, buttons)
    end
    if listView then
        frame._waffleListApplying = true
        ApplyEasyAccessItemList(frame, buttons, costsByMerchant)
        frame._waffleListApplying = nil
        frame._waffleListRefreshAfterResize = nil
    else
        ApplyEasyAccessItemList(frame, buttons, costsByMerchant)
    end

    if frame.UpdateThumb then
        frame.UpdateThumb()
    end
end

QueueRefresh = function()
    local frame = _G.EUI_VendorBagFrame
    if frame and GetSettings().vendorItemView == "list" and (frame._liveWindowWidth or frame._liveWindowHeight) then
        frame._waffleListRefreshAfterResize = true
        return
    end
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = nil
        addon.Refresh()
    end)
end

local zygorPointerSkin
local zygorPointerHooked
local zygorPointerSkinPending

local function ApplyZygorPointerSkin()
    if GetSettings().skinZygorGuidePointer == false or not zygorPointerSkin then return false end
    if InCombatLockdown and InCombatLockdown() then return false end

    local icon = _G.ZygorGuidesViewerPointerArrow_Icon
    if not (icon and icon.texture) then return false end

    -- Preserve Zygor's dynamic quest icon while giving its secure button the
    -- house background, border, hover, and icon crop.  The actual click,
    -- drag, cooldown, and combat-hide handlers remain entirely Zygor-owned.
    icon.WaffleHouseGuideIcon = icon.texture
    -- The skin facade exposes plain functions rather than object methods.
    -- Calling these with ':' shifts every argument over and leaves the guide
    -- icon unskinned, so deliberately use '.' here.
    zygorPointerSkin.Button(icon, { "WaffleHouseGuideIcon" })
    zygorPointerSkin.SquareIcon(icon.texture, icon)
    return true
end

local function HookZygorPointerSetup()
    if zygorPointerHooked then return end
    local zygor = _G.ZygorGuidesViewer
    local pointer = zygor and zygor.Pointer
    if not (pointer and type(pointer.SetupArrow) == "function") then return end
    hooksecurefunc(pointer, "SetupArrow", function()
        if QueueZygorPointerSkin then QueueZygorPointerSkin() end
    end)
    zygorPointerHooked = true
end

QueueZygorPointerSkin = function()
    HookZygorPointerSetup()
    if zygorPointerSkinPending then return end
    zygorPointerSkinPending = true
    C_Timer.After(0, function()
        zygorPointerSkinPending = nil
        ApplyZygorPointerSkin()
    end)
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("Waffle House — Zygor Guide Pointer", function(skin)
        zygorPointerSkin = skin
        HookZygorPointerSetup()
        QueueZygorPointerSkin()
    end)
end

local function InstallHooks()
    for _, functionName in ipairs({
        "MerchantFrame_UpdateMerchantInfo",
        "MerchantFrame_UpdateBuybackInfo",
        "MerchantFrame_UpdateRepairButtons",
        "MerchantFrame_UpdateCurrencies",
    }) do
        if not hookedFunctions[functionName] and type(_G[functionName]) == "function" then
            hooksecurefunc(functionName, QueueRefresh)
            hookedFunctions[functionName] = true
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:RegisterEvent("TOOLTIP_DATA_UPDATE")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("NEW_TOY_ADDED")
events:RegisterEvent("TOYS_UPDATED")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:RegisterEvent("COMPANION_UPDATE")
events:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
events:RegisterEvent("UPDATE_SUMMONPETS_ACTION")
events:RegisterEvent("HEIRLOOMS_UPDATED")
events:RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST")
events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addonName, success)
    if event == "BAG_UPDATE" then
        local vendorFrame = _G.EUI_VendorBagFrame
        if vendorFrame then vendorFrame._waffleListIgnoreHostRenderUntilBagSettles = true end
        itemQueueCache.BagChanged(addonName)
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if IsSafeNumber(addonName) and success ~= false then
            ScheduleItemQueueRefresh({ [addonName] = true })
        end
        -- Merchant item data can matter independently of carried queue items.
        local frame = _G.EUI_VendorBagFrame
        if frame and frame:IsShown() then QueueRefresh() end
        return
    end
    if event == "TOOLTIP_DATA_UPDATE" then
        if not addonName then
            ScheduleItemQueueRefresh()
        elseif IsSafeNumber(addonName) then
            local itemID = itemQueueCache.tooltipInstances[addonName]
            if itemID then ScheduleItemQueueRefresh({ [itemID] = true }) end
        end
        return
    end
    if event == "GOSSIP_SHOW" and addon.CloseIgnoredVendorGossip and addon.CloseIgnoredVendorGossip() then
        return
    elseif event == "ADDON_LOADED" then
        if addonName == "ZygorGuidesViewer" and QueueZygorPointerSkin then
            QueueZygorPointerSkin()
        end
        if addonName == "EllesmereUIDataBars" then
            if InstallWonderbarReorderHooks then InstallWonderbarReorderHooks() end
            if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
        end
        if addonName == "Blizzard_MerchantUI" or addonName == "EllesmereUIVendorBag" then
            InstallHooks()
            QueueRefresh()
        end
    elseif event == "MERCHANT_CLOSED" then
        selectedCostKey = nil
        if panel then panel:Hide() end
    else
        InstallHooks()
        if event == "PLAYER_LOGIN" then
            StartOptionsRegistration()
            if QueueZygorPointerSkin then QueueZygorPointerSkin() end
            if UpdateIgnoredInteractBinding then UpdateIgnoredInteractBinding() end
            if InstallConfirmPopupPixelBorderHook then InstallConfirmPopupPixelBorderHook() end
            if InstallWonderbarReorderHooks then InstallWonderbarReorderHooks() end
            if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if QueueZygorPointerSkin then QueueZygorPointerSkin() end
            if UpdateIgnoredInteractBinding then UpdateIgnoredInteractBinding() end
            if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
            if itemQueueRefreshAfterCombat then
                itemQueueRefreshAfterCombat = nil
                ScheduleItemQueueRefresh()
            end
        elseif event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            if UpdateIgnoredInteractBinding then UpdateIgnoredInteractBinding() end
            if InstallWonderbarReorderHooks then InstallWonderbarReorderHooks() end
            if RefreshWonderbarReorderMode then RefreshWonderbarReorderMode() end
        end
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_ENABLED" or event == "COMPANION_UPDATE"
            or event == "PET_JOURNAL_LIST_UPDATE" or event == "UPDATE_SUMMONPETS_ACTION" then
            if UpdateSoulTraderCompanion then UpdateSoulTraderCompanion() end
        end
        if event == "BAG_UPDATE_DELAYED" then
            ScheduleItemQueueRefresh("bags")
            local vendorFrame = _G.EUI_VendorBagFrame
            if vendorFrame then
                C_Timer.After(0, function()
                    vendorFrame._waffleListIgnoreHostRenderUntilBagSettles = nil
                end)
            end
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            local items = {}
            for _, sample in ipairs(itemQueueCache.samples or {}) do
                if sample.snapshot.combinationRequirements then items[sample.item.itemID] = true end
            end
            ScheduleItemQueueRefresh(items)
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
            or event == "SKILL_LINES_CHANGED" or event == "NEW_TOY_ADDED" or event == "TOYS_UPDATED"
            or event == "NEW_MOUNT_ADDED" or event == "COMPANION_UPDATE"
            or event == "HEIRLOOMS_UPDATED"
            or event == "HOUSE_DECOR_ADDED_TO_CHEST" then
            ScheduleItemQueueRefresh()
        end
        -- The remaining events mostly serve Item Queue, companion, or skin
        -- features.  Never redraw Vendor Bags for those (notably bag sorting).
        if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "PLAYER_MONEY"
            or event == "CURRENCY_DISPLAY_UPDATE" then
            QueueRefresh()
        end
    end
end)
