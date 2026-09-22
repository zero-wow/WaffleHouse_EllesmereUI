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

assert(toc:find("WaffleHouse_BagSlotFreeze.lua\nWaffleHouse_BagAssistant.lua", 1, true),
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
assert(source:find("sortButton:Click(\"LeftButton\")", 1, true),
    "assistant must route tidy actions through EllesmereUI Bags' existing sort button")
assert(source:find("if IsInCombat() or not IsBankOpen() then return end", 1, true),
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
    BagIndex = { CharacterBankTab_1 = 100, CharacterBankTab_2 = 101,
        CharacterBankTab_3 = 102, CharacterBankTab_4 = 103, AccountBankTab_1 = 104 } }
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
local frameMethods = {}
function frameMethods:RegisterEvent(event) events[event] = true end
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
assert(plan.cleanups[1].depositFlags == 4,
    "automatic tab organization must preserve existing deposit flags")

local updates = {}
C_Bank.UpdateBankTabSettings = function(...) updates[#updates + 1] = { ... } end
local changed = addon.ApplyBagAssistantTabCleanup()
assert(changed and #updates == 1 and updates[1][1] == Enum.BankType.Character
    and updates[1][2] == 102 and updates[1][3] == "Materials 3"
    and updates[1][4] == 457 and updates[1][5] == 4,
    "one cleanup click must apply only generic-tab name/icon updates")

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
EUI_Bags = { Header = CreateFrame("Frame"), _bagsBtn = CreateFrame("Button"),
    _sortBtn = { Click = function() end } }
addon.RefreshBagAssistant()
local assistantButton = EUI_Bags.Header.children[1]
assert(assistantButton and assistantButton.scripts.OnClick, "assistant header button must be created")
assistantButton:Click("LeftButton")
local menu = WaffleHouseBagAssistantMenu
assert(menu and menu:IsShown() and menu.width == 390 and menu.height == 480,
    "expanded bank planner must open in a bounded menu")
assert(#updates == 2 and menu.hint.text:find("Submitted 1 tab name/icon update", 1, true),
    "opening the assistant at a bank must auto-apply qualifying generic-tab edits from the user click")
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
    and updates[#updates][4] == 458 and updates[#updates][5] == 8,
    "portable warband access must update only account tabs and preserve deposit flags")

print("bag assistant static tests passed")
