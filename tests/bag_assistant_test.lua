local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = assert(file:read("*a"))
    file:close()
    return content
end

local root = arg[1] or "."
local function join(name)
    return root .. "/" .. name
end

local toc = read(join("WaffleHouse_EllesmereUI.toc"))
local source = read(join("WaffleHouse_BagAssistant.lua"))
local main = read(join("WaffleHouse_EllesmereUI.lua"))

local freezeAt = toc:find("WaffleHouse_BagSlotFreeze.lua", 1, true)
local assistantAt = toc:find("WaffleHouse_BagAssistant.lua", 1, true)
assert(freezeAt and assistantAt and freezeAt < assistantAt,
    "bag assistant must load after the bags integration")
assert(main:find("WaffleHouseDB.bagAssistantEnabled == nil", 1, true),
    "bag assistant needs a stable enabled-by-default setting")
assert(source:find("button:SetPoint(\"RIGHT\", bagsButton, \"LEFT\", -6, 0)", 1, true),
    "assistant must mirror the Show Bags-to-Sort header gap")
assert(source:find("button:SetSize(24, 24)", 1, true),
    "assistant must match the compact 24px header icon footprint")
assert(source:find("local tabs = bank and bank._allTabs", 1, true),
    "assistant must inspect published bank-tab metadata for recommendations")
assert(source:find("return _G.EUI_BankFrame", 1, true),
    "assistant must use EllesmereUI's globally named bank frame, not its local variable")
assert(source:find("C_Container.GetContainerItemInfo", 1, true),
    "assistant must inspect tab contents rather than guessing a destination")
assert(source:find("C_Bank.AutoDepositItemsIntoBank", 1, true),
    "assistant needs direct-click deposit support")
assert(source:find("C_Container.SortBags()", 1, true)
    and source:find("addon.SortUnfrozenBagSlots()", 1, true),
    "assistant must physically sort bags and use the frozen-aware path when needed")
assert(source:find("if IsInCombat() or not IsBankOpen() then return false", 1, true),
    "deposit actions must be gated behind an open bank and out-of-combat state")
assert(not source:find("_selectedView%s*="),
    "assistant must not mutate EllesmereUI Bank's private selected view")
assert(not source:find("OpenBank", 1, true),
    "assistant must not attempt to open protected bank UI remotely")

-- Advice is an ordinary read-only scan.  A full tab with existing materials
-- must not cause a false "bank full" result when another published tab has
-- room for a future material destination.
Enum = { ItemClass = { Reagent = 5, Tradegoods = 7, Weapon = 2, Armor = 4, Consumable = 0 },
    BankType = { Character = 1, Account = 2 },
    BagSlotFlags = { ClassEquipment = 1, ClassConsumables = 2,
        ClassProfessionGoods = 4, ClassReagents = 8, ClassJunk = 16 },
    BagIndex = { CharacterBankTab_1 = 100, CharacterBankTab_2 = 101,
        CharacterBankTab_3 = 102, CharacterBankTab_4 = 103, AccountBankTab_1 = 104 } }
bit = { bor = function(a, b) return a + b end }
local containers = {
    [0] = { { itemID = 9001 }, false },
    [100] = { { itemID = 9001 }, { itemID = 9001 } },
    [101] = { { itemID = 8001 }, false, false },
    [102] = { { itemID = 9001, iconFileID = 457 }, { itemID = 9001, iconFileID = 457 },
        { itemID = 9001, iconFileID = 457 }, { itemID = 9001, iconFileID = 457 },
        { itemID = 9001, iconFileID = 457 }, false },
    [103] = { { itemID = 7001, hyperlink = "item:7001", iconFileID = 999 } },
}
C_Container = {
    GetContainerNumSlots = function(bag) return #(containers[bag] or {}) end,
    GetContainerItemInfo = function(bag, slot)
        local item = (containers[bag] or {})[slot]
        return item or nil
    end,
    GetContainerItemLink = function(bag, slot)
        local item = (containers[bag] or {})[slot]
        return item and item.hyperlink or nil
    end,
}
C_Item = {
    GetItemInfoInstant = function(itemID)
        if type(itemID) == "string" then itemID = tonumber(itemID:match("item:(%d+)")) end
        return itemID, nil, nil, nil, nil, itemID == 9001 and 7 or (itemID == 7001 and 4 or 1)
    end,
    GetDetailedItemLevelInfo = function(item) return tostring(item):find("7001") and 160 or 0 end,
    GetItemInfo = function(item) return tostring(item):find("7001") and "Outdated Helm" or "Material" end,
}
GetAverageItemLevel = function() return 250, 240 end
InCombatLockdown = function() return false end
C_Bank = {
    FetchPurchasedBankTabData = function(bankType)
        if bankType == Enum.BankType.Account then
            return { { name = "Tab 1", icon = 125, depositFlags = 8 } }
        end
        return { { name = "Materials" }, { name = "Overflow" },
            { name = "Tab 3", icon = 123, depositFlags = 4 },
            { name = "Transmog Vault", icon = 124 } }
    end,
}
-- EllesmereUI's bank file declares `local EUI_Bank` and names the actual frame
-- `EUI_BankFrame`; only the latter exists in the global namespace.
EUI_Bank = nil
EUI_BankFrame = {
    IsVisible = function() return true end,
    _allTabs = {
        { bagID = 100, name = "Materials", numSlots = 2 },
        { bagID = 101, name = "Overflow", numSlots = 3 },
    },
}
local events = {}
local bankEventFrame
local frameMethods = {}
function frameMethods:RegisterEvent(event)
    events[event] = true
    if event == "BANKFRAME_OPENED" then bankEventFrame = self end
end
function frameMethods:SetScript(name, callback) self.scripts[name] = callback end
function frameMethods:SetSize(width, height) self.width, self.height = width, height end
function frameMethods:SetHeight(height) self.height = height end
function frameMethods:SetWidth(width) self.width = width end
function frameMethods:SetPoint(...) self.point = { ... } end
function frameMethods:ClearAllPoints() self.point = nil end
function frameMethods:SetAllPoints() end
function frameMethods:SetFrameStrata() end
function frameMethods:SetClampedToScreen() end
function frameMethods:EnableMouse(value) self.mouseEnabled = value end
function frameMethods:SetBackdrop() end
function frameMethods:SetBackdropColor() end
function frameMethods:SetBackdropBorderColor() end
function frameMethods:SetText(text) self.text = text end
function frameMethods:SetTextColor() end
function frameMethods:SetJustifyH() end
function frameMethods:SetJustifyV() end
function frameMethods:SetWordWrap() end
function frameMethods:SetTexture(texture) self.texture = texture end
function frameMethods:SetTexCoord(...) self.texCoord = { ... } end
function frameMethods:SetAlpha() end
function frameMethods:SetVertexColor() end
function frameMethods:SetColorTexture() end
function frameMethods:SetDesaturated() end
function frameMethods:IsShown() return self.shown == true end
function frameMethods:Show()
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function frameMethods:Hide() self.shown = false end
function frameMethods:SetShown(value) if value then self:Show() else self:Hide() end end
function frameMethods:CreateTexture() return setmetatable({ scripts = {}, shown = true }, { __index = frameMethods }) end
function frameMethods:CreateFontString() return setmetatable({ scripts = {}, shown = true }, { __index = frameMethods }) end
function frameMethods:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button) end end
function frameMethods:GetChildren() return table.unpack(self.children or {}) end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true },
        { __index = frameMethods })
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, frame)
    end
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
C_Timer = { After = function(_, callback) callback() end }
local addon = {}
local chunk = assert(load(source, "@WaffleHouse_BagAssistant.lua"))
chunk("WaffleHouse_EllesmereUI", addon)
local advice = addon.GetBagAssistantAdvice()
assert(advice.state == "ready" and advice.tab and advice.tab.name == "Overflow" and advice.tab.freeSlots == 2,
    "assistant must prefer an available destination over an already-full material tab")
assert(events.BANKFRAME_OPENED and events.PLAYERBANKSLOTS_CHANGED,
    "assistant must refresh advice as bank data changes")

EUI_BankFrame._allTabs[#EUI_BankFrame._allTabs + 1] =
    { bagID = 102, name = "Tab 3", numSlots = 6, icon = 123, depositFlags = 4 }
EUI_BankFrame._allTabs[#EUI_BankFrame._allTabs + 1] =
    { bagID = 103, name = "Transmog Vault", numSlots = 1, icon = 124 }
local fetchTabData = C_Bank.FetchPurchasedBankTabData
C_Bank.FetchPurchasedBankTabData = function() return nil end
assert(#addon.GetBagAssistantPlan().cleanups == 0,
    "fallback tab names before live bank settings load must not trigger automatic renames")
C_Bank.FetchPurchasedBankTabData = fetchTabData
local plan = addon.GetBagAssistantPlan()
assert(plan.tabCount == 4 and #plan.cleanups == 1 and plan.cleanups[1].name == "Materials 3"
    and plan.cleanups[1].icon == 457,
    "generic high-confidence material tab must receive a name and icon suggestion")
assert(#plan.outdated == 1 and plan.outdated[1].name == "Outdated Helm"
    and plan.outdated[1].level == 160 and plan.threshold == 190,
    "only gear at least 50 item levels below equipped average should be flagged")
assert(plan.cleanups[1].depositFlags == 12,
    "automatic tab organization must assign matching profession-goods and reagent filters")

local updates = {}
C_Bank.UpdateBankTabSettings = function(...) updates[#updates + 1] = { ... } end
local changed = addon.ApplyBagAssistantTabCleanup()
assert(changed and #updates == 1 and updates[1][1] == Enum.BankType.Character
    and updates[1][2] == 102 and updates[1][3] == "Materials 3"
    and updates[1][4] == 457 and updates[1][5] == 12,
    "one cleanup click must apply generic-tab name, icon, and deposit settings")

local clicked
local view = { _viewIdx = -3, IsVisible = function() return true end,
    Click = function(_, mouseButton) clicked = mouseButton end }
EUI_BankFrame.GetChildren = function()
    return { GetChildren = function() return view end }
end
assert(addon.SelectBagAssistantBankView(-3) and clicked == "LeftButton",
    "view navigation must click the bank's own sidebar button")
assert(not addon.SelectBagAssistantBankView(99), "missing bank view must not be invented")

local cursor
CursorHasItem = function() return cursor ~= nil end
C_Container.PickupContainerItem = function(bag, slot)
    local held = (containers[bag] or {})[slot]
    if cursor then
        containers[bag][slot], cursor = cursor, held or nil
    elseif held then
        cursor, containers[bag][slot] = held, nil
    end
end
local delayedLoginCallbacks = {}
local immediateTimer = C_Timer.After
C_Timer.After = function(delay, callback)
    if delay > 0 then delayedLoginCallbacks[#delayedLoginCallbacks + 1] = callback
    else callback() end
end
bankEventFrame.scripts.OnEvent(nil, "PLAYER_LOGIN")
assert(#delayedLoginCallbacks >= 1,
    "assistant must retry after EllesmereUI Bags builds its header post-login")
EUI_Bags = { Header = CreateFrame("Frame"), _bagsBtn = CreateFrame("Button"),
    _sortBtn = { Click = function() end } }
for _, callback in ipairs(delayedLoginCallbacks) do callback() end
C_Timer.After = immediateTimer
local assistantButton = EUI_Bags.Header.children[1]
assert(assistantButton and assistantButton.scripts.OnClick, "assistant header button must be created")
assert(assistantButton.icon.texture:find("bag_assistant_emblem.tga", 1, true)
    and assistantButton.actionTile.width == 14 and assistantButton.actionTile.height == 14
    and assistantButton.stateBorder.width == 9,
    "action and status badges must fit the skinned 24px assistant icon")
assistantButton:Click("LeftButton")
local menu = WaffleHouseBagAssistantMenu
assert(not menu and #updates == 2,
    "left-click must do the next action without opening the full planner")
assert(assistantButton.pauseLeft:IsShown() and not assistantButton.playGlyph:IsShown(),
    "active sequence must display pause bars without replacing the bronze icon")
assistantButton:Click("RightButton")
assert(not WaffleHouseBagAssistantMenu and #updates == 2,
    "right-click during an active run must pause without opening the planner")
assert(not assistantButton.pauseLeft:IsShown() and assistantButton.playGlyph:IsShown(),
    "paused sequence must display a play/resume mark")
local shiftDown = true
IsShiftKeyDown = function() return shiftDown end
assistantButton:Click("RightButton")
menu = WaffleHouseBagAssistantMenu
assert(menu and menu:IsShown() and menu.width == 390 and menu.height == 480,
    "shift-right-click must open the bounded planner while paused")
shiftDown = false
assistantButton:Click("LeftButton")
assert(#updates == 2, "left-click while paused must not queue another action")
assistantButton:Click("RightButton")
assert(#updates == 2, "resuming must not immediately queue another action")
assert(#updates == 2,
    "first assistant click must auto-apply qualifying bank-tab settings")
assert(menu.viewButtons[-3]._enabled and menu.organize._enabled and menu.withdrawGear._enabled,
    "bank views, eligible generic-tab cleanup, and exact gear review must be actionable")
assert(not menu.openTab._enabled and not menu.editTab._enabled,
    "hidden physical tabs must not expose dead navigation or edit controls")
menu.organize:Click("LeftButton")
assert(#updates == 3, "the manual organize fallback must submit the eligible tab edit")
assistantButton:Click("LeftButton")
assistantButton:Click("LeftButton")
assert(#updates == 3, "a repeated assistant click must not resubmit automatic edits in the same bank visit")

local moved = addon.WithdrawBagAssistantOutdatedGear(plan.outdated[1])
assert(moved and not cursor and not containers[103][1] and containers[0][2]
    and containers[0][2].itemID == 7001,
    "explicit withdrawal must move only the selected outdated bank item to a free bag slot")
assert(not addon.WithdrawBagAssistantOutdatedGear(plan.outdated[1]),
    "an already-moved bank item must never be withdrawn a second time")

containers[104] = { { itemID = 9001, iconFileID = 458 }, { itemID = 9001, iconFileID = 458 },
    { itemID = 9001, iconFileID = 458 }, { itemID = 9001, iconFileID = 458 }, false }
EUI_BankFrame._allTabs[#EUI_BankFrame._allTabs + 1] =
    { bagID = 104, name = "Warbank Tab 1", isWarband = true, numSlots = 5, icon = 125, depositFlags = 8 }
local warbandPlan = addon.GetBagAssistantPlan()
assert(#warbandPlan.cleanups == 2 and warbandPlan.cleanups[2].name == "Materials 5",
    "generic warband tabs must be recognized independently of aggregate OneWarbank views")
Enum.PlayerInteractionType = { AccountBanker = 9 }
C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return true end }
local beforePortable = #updates
assert(addon.ApplyBagAssistantTabCleanup() and #updates == beforePortable + 1
    and updates[#updates][1] == Enum.BankType.Account and updates[#updates][2] == 104
    and updates[#updates][4] == 458 and updates[#updates][5] == 12,
    "portable warband access must update only account tabs and set matching deposit flags")

-- Cross-storage categorization must be one exact, click-triggered move into
-- a named category tab, and only when the account bank accepts that item.
C_PlayerInteractionManager.IsInteractingWithNpcOfType = function() return false end
C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Account then
        return { { name = "Materials 5", icon = 458, depositFlags = 12 } }
    end
    return { { name = "Materials" }, { name = "Overflow" },
        { name = "Materials 3", icon = 457, depositFlags = 12 },
        { name = "Transmog Vault", icon = 124 } }
end
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
C_Bank.IsItemAllowedInBankType = function(_, location) return location.bag == 100 end
local categoryMove = addon.GetBagAssistantPlan().move
assert(categoryMove and categoryMove.source.bagID == 100 and categoryMove.target.bagID == 104,
    "categorization must target a matching named Warband tab for an eligible bank item")
assert(addon.MoveBagAssistantCategoryItem(), "approved category move must run from one click")
assert(not containers[100][1] and containers[104][5] and containers[104][5].itemID == 9001,
    "one category click must move exactly the proposed item and preserve other slots")
local deposits = 0
C_Bank.AutoDepositItemsIntoBank = function() deposits = deposits + 1 end
addon.HasFrozenBagSlots = function() return true end
addon.RefreshBagAssistant()
assert(not menu.reagents._enabled and not menu.warbound._enabled
    and addon.GetBagAssistantNextTask() ~= "deposit"
    and addon.GetBagAssistantNextTask() ~= "warband" and deposits == 0,
    "bulk deposits must never include frozen bag items")

containers[100] = { { itemID = 9001 }, { itemID = 9001 },
    { itemID = 9001 }, { itemID = 9001 } }
C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Account then
        return { { name = "Materials 5", icon = 458, depositFlags = 12 } }
    end
    return { { name = "My Special Mats", icon = 777, depositFlags = 0 },
        { name = "Overflow" }, { name = "Materials 3", icon = 457, depositFlags = 12 },
        { name = "Transmog Vault", icon = 124 } }
end
local customPlan = addon.GetBagAssistantPlan()
assert(#customPlan.cleanups == 1 and customPlan.cleanups[1].bagID == 100
    and customPlan.cleanups[1].name == "My Special Mats"
    and customPlan.cleanups[1].icon == 777 and customPlan.cleanups[1].depositFlags == 12,
    "custom tab names and icons must survive an automatic high-confidence deposit-filter update")

addon.HasFrozenBagSlots = function() return false end
C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Account then
        return { { name = "Materials 5", icon = 458, depositFlags = 12 } }
    end
    return { { name = "My Special Mats", icon = 777, depositFlags = 12 },
        { name = "Overflow" }, { name = "Materials 3", icon = 457, depositFlags = 12 },
        { name = "Transmog Vault", icon = 124 } }
end
containers[102][6] = { itemID = 9001 }
containers[104][5] = false
C_Bank.IsItemAllowedInBankType = function() return false end
local bagSorts, bankSorts = 0, {}
C_Container.SortBags = function() bagSorts = bagSorts + 1 end
C_Container.SortBank = function(bankType) bankSorts[#bankSorts + 1] = bankType end
bankEventFrame.scripts.OnEvent(nil, "BANKFRAME_OPENED")
assert(addon.GetBagAssistantNextTask() == "deposit", "sequence must start with reagent deposit")
assistantButton:Click("LeftButton")
assert(deposits == 1 and addon.GetBagAssistantNextTask() == "warband",
    "after reagents, the next click must offer a Warbound deposit")
assistantButton:Click("LeftButton")
assert(deposits == 2 and addon.GetBagAssistantNextTask() == "sort_bags",
    "after both deposit types, the next click must advance to physical bag sorting")
assistantButton:Click("LeftButton")
assert(bagSorts == 1 and addon.GetBagAssistantNextTask() == "sort_character",
    "bag sort must run once before character-bank sorting")
assistantButton:Click("LeftButton")
assert(bankSorts[1] == Enum.BankType.Character and addon.GetBagAssistantNextTask() == "sort_warband",
    "character bank must sort before Warband bank")
assistantButton:Click("LeftButton")
assert(bankSorts[2] == Enum.BankType.Account and addon.GetBagAssistantNextTask() == "menu",
    "assistant must finish the click sequence after sorting the Warband bank")

-- A carried item can be categorized on demand, but both the initial scan and
-- the final pickup must honor a newly frozen slot.
containers[100] = {}
containers[102][6] = false
containers[104][5] = { itemID = 9001 }
C_Bank.IsItemAllowedInBankType = function(_, location) return location.bag == 0 end
addon.IsFrozenBagSlot = function(bag, slot) return bag == 0 and slot == 1 end
assert(not addon.GetBagAssistantPlan().move,
    "a frozen carried item must not enter the category transfer plan")
local freezeChecks = 0
addon.IsFrozenBagSlot = function(bag, slot)
    if bag == 0 and slot == 1 then
        freezeChecks = freezeChecks + 1
        return freezeChecks > 1
    end
    return false
end
assert(not addon.MoveBagAssistantCategoryItem() and containers[0][1]
    and containers[0][1].itemID == 9001,
    "a newly frozen carried item must not be picked up after planning")
addon.IsFrozenBagSlot = nil

-- Guild Bank support is opt-in and moves one visible, permitted item per
-- click, from the selected tab to a populated named category tab.
EUI_BankFrame.IsVisible = function() return false end
addon.GetSettings = function() return { bagAssistantIncludeGuildBank = true } end
GuildBankFrame = { IsVisible = function() return true end }
local guildItems = {
    [1] = { { link = "item:9001", texture = 457 } },
    [2] = { { link = "item:9001", texture = 457 } },
}
GetNumGuildBankTabs = function() return 2 end
GetCurrentGuildBankTab = function() return 1 end
GetGuildBankTabInfo = function(tab)
    return tab == 1 and "Misc" or "Materials 2", 457, true, true, -1, -1
end
GetGuildBankItemInfo = function(tab, slot)
    local item = guildItems[tab] and guildItems[tab][slot]
    return item and item.texture or nil, 1, false
end
GetGuildBankItemLink = function(tab, slot)
    local item = guildItems[tab] and guildItems[tab][slot]
    return item and item.link or nil
end
PickupGuildBankItem = function(tab, slot)
    local held = guildItems[tab][slot]
    if cursor then guildItems[tab][slot], cursor = cursor, held
    elseif held then cursor, guildItems[tab][slot] = held, nil end
end
assert(addon.GetBagAssistantNextTask() == "guild_move",
    "an opted-in Guild Bank should offer a permitted category move")
assistantButton:Click("LeftButton")
assert(not guildItems[1][1] and guildItems[2][2] and not cursor,
    "one guild action click must move one item between guild tabs")

print("bag assistant static tests passed")
