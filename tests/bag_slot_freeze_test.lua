-- Validates Waffle House's frozen-slot sorter without loading EllesmereUI Bags.
-- The feature must sort unfrozen slots while the clicked item's physical slot
-- remains untouched.

local SOURCE = arg[1] or "WaffleHouse_BagSlotFreeze.lua"

local events = {}
local eventHandler
function CreateFrame()
    local frame = {}
    function frame:RegisterEvent(event) events[event] = true end
    function frame:SetScript(name, callback)
        if name == "OnEvent" then eventHandler = callback end
    end
    return frame
end

local slots = {
    [0] = {
        [1] = { itemID = 101, quality = 1 },
        [2] = { itemID = 202, quality = 4 },
        [3] = { itemID = 303, quality = 2 },
        [4] = nil,
    },
}
local pendingSource
local failedDrops = 0
local unlockOnNextTimer
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local item = slots[bag] and slots[bag][slot]
        if not item then return nil end
        return { itemID = item.itemID, quality = item.quality, isLocked = item.isLocked == true }
    end,
    GetContainerItemLink = function(bag, slot)
        local item = slots[bag] and slots[bag][slot]
        return item and ("item:" .. item.itemID) or nil
    end,
    PickupContainerItem = function(bag, slot)
        if not pendingSource then
            pendingSource = { bag = bag, slot = slot }
            return
        end
        local source = pendingSource
        if failedDrops > 0 then
            failedDrops = failedDrops - 1
            pendingSource = nil
            return
        end
        slots[source.bag][source.slot], slots[bag][slot] = slots[bag][slot], slots[source.bag][source.slot]
        pendingSource = nil
    end,
}
C_Timer = { After = function(_, callback)
    if unlockOnNextTimer then
        unlockOnNextTimer = nil
        for _, bag in pairs(slots) do
            for _, item in pairs(bag) do
                if item then item.isLocked = false end
            end
        end
    end
    callback()
end }
ClearCursor = function() pendingSource = nil end
GetItemInfo = function(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    local names = { [101] = "Amber", [202] = "Brilliant", [303] = "Cold Lock" }
    local quality = { [101] = 1, [202] = 4, [303] = 2 }
    return names[id], nil, quality[id]
end
InCombatLockdown = function() return false end

EllesmereUI = { _bagsDB = { profile = { bagSortToBottom = false } } }
EUI_Bags = {
    refreshEnabled = true,
    RefreshInventory = function(self) self.refreshed = true end,
    _sortBtn = {
        EnableMouse = function(_, enabled) EUI_Bags.sortEnabled = enabled end,
        icon = { SetAlpha = function(_, alpha) EUI_Bags.sortAlpha = alpha end },
        GetScript = function(self) return self.onClick end,
        SetScript = function(self, _, callback) self.onClick = callback end,
        Click = function(self) self.onClick(self, "LeftButton") end,
    },
}
local nativeSortCalls = 0
EUI_Bags._sortBtn.onClick = function()
    nativeSortCalls = nativeSortCalls + 1
    slots[0][3], slots[0][4] = slots[0][4], slots[0][3]
end
EUI_CategoryManager = {
    ClassifyAll = function(_, items)
        for _, item in ipairs(items) do item.categoryIndex = 1 end
    end,
    GetCategories = function() return { { name = "Items" } } end,
    GetGroupMembers = function() return nil end,
}

local settings = {
    bagSlotFreezeEnabled = true,
    bagFrozenSlots = { ["0:3"] = { itemID = 303 } },
}
local addon = { GetSettings = function() return settings end }
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
assert(type(addon.SortUnfrozenBagSlots) == "function", "frozen-slot sorter must be exposed to its hook")

addon.SortUnfrozenBagSlots()
assert(slots[0][1].itemID == 202, "highest-quality unfrozen item should sort into the first movable slot")
assert(slots[0][2].itemID == 101, "remaining unfrozen item should follow the sorted order")
assert(slots[0][3].itemID == 303, "frozen item must remain in its original physical bag slot")
assert(EUI_Bags.refreshed == true, "sort must refresh the host bag view after moving items")
assert(EUI_Bags.sortEnabled == true, "sort control must be restored after the Waffle House sort")
assert(events.MODIFIER_STATE_CHANGED, "modifier changes must refresh the click-to-freeze preview")
assert(events.BAG_UPDATE and events.BAG_UPDATE_DELAYED,
    "bag updates must reapply frozen-slot visuals after item buttons are refreshed or recycled")

-- The host's OneBag/MultiBag sort button can be pressed when Main Bags is
-- collapsed or another category is selected. The frozen guard must not depend
-- on the currently rendered section, or native SortBags moves locked items.
eventHandler(nil, "PLAYER_LOGIN")
EUI_Bags._sortBtn:Click()
assert(nativeSortCalls == 0 and slots[0][3].itemID == 303,
    "host sort must preserve frozen slots even when Main Bags is not visible")
EUI_Bags._sortBtn:SetScript("OnClick", function() nativeSortCalls = nativeSortCalls + 1 end)
eventHandler(nil, "BAG_UPDATE_DELAYED")
EUI_Bags._sortBtn:Click()
assert(nativeSortCalls == 0 and slots[0][3].itemID == 303,
    "a replaced host sort handler must be rewrapped before another sort")

-- Real container moves can be rejected while a prior move is briefly locked.
-- A failed first drop must be retried rather than leaving an ordinary gap.
slots[0][1] = { itemID = 101, quality = 1 }
slots[0][2] = nil
slots[0][3] = { itemID = 303, quality = 2 }
slots[0][4] = { itemID = 202, quality = 4 }
failedDrops = 1
addon.SortUnfrozenBagSlots()
assert(slots[0][1].itemID == 202 and slots[0][2].itemID == 101,
    "a transient failed move must retry and fill each non-frozen target")
assert(slots[0][3].itemID == 303, "retrying a move must never use the frozen slot")

-- A slot locked at plan time is transient, not a fixed empty position. Once
-- the timer sees it unlock, the sorter needs to rebuild and complete the plan.
slots[0][1] = { itemID = 101, quality = 1, isLocked = true }
slots[0][2] = nil
slots[0][3] = { itemID = 303, quality = 2 }
slots[0][4] = { itemID = 202, quality = 4 }
unlockOnNextTimer = true
addon.SortUnfrozenBagSlots()
assert(slots[0][1].itemID == 202 and slots[0][2].itemID == 101,
    "a transiently locked non-frozen slot must be replanned instead of leaving a hole")
assert(slots[0][3].itemID == 303, "locked-slot replans must preserve frozen coordinates")

local file = assert(io.open(SOURCE, "r"))
local source = file:read("*a")
file:close()
for _, fragment in ipairs({
    'FROZEN_TEXTURE = "Interface\\\\AddOns\\\\WaffleHouse_EllesmereUI\\\\Media\\\\bag_slot_frozen_eui.tga"',
    'FREEZE_MARKER_DEFAULT_SIZE = 11',
    'text = "Freeze Modifier"',
    'text = "Frozen Marker"',
    '"Frozen Marker Size"',
    'GetMarkerSize()',
    'ReconcileFrozenSlots()',
    'itemGUID = info.itemGUID',
    'QueueVisualRefreshAfterLayout()',
    'MAX_SORT_MOVE_RETRIES',
    'TargetHasWantedItem',
    'HasUnfilledTarget',
    'buttonText = frozenSlotManagerOpen and "Hide Frozen Items" or "View Frozen Items"',
    '"FROZEN SLOT MANAGER"',
    'W:DropdownWithOffsets',
    'IsMainBagsButton(button)',
    'catcher:RegisterForClicks("RightButtonUp")',
    'catcher:SetPassThroughButtons("LeftButton", "MiddleButton")',
    'mouseButton ~= "RightButton" or not IsFreezeModifierDown()',
    'and right-click an item in OneBag',
}) do
    assert(source:find(fragment, 1, true), "missing frozen-slot feature fragment: " .. fragment)
end

io.write("bag slot freeze tests passed\n")
