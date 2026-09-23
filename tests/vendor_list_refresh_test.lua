-- Exercise the actual refresh, planner, toolbar and list renderer together.
-- Only WoW APIs / frame objects are mocked. Run: lua tests/vendor_list_refresh_test.lua
-- Prove the old bug fails: lua tests/vendor_list_refresh_test.lua WaffleHouse_EllesmereUI.lua --pre-fix
local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(SOURCE, "rb"))
local source = file:read("*a")
file:close()
local unpack = table.unpack or unpack

-- Optional mutation proves the regression fails with the former identity
-- fallback. It changes only this in-memory test chunk, never the source file.
if arg[2] == "--pre-fix" then
    local start = assert(source:find("local function GetVendorPlannerKey(button)", 1, true))
    local finish = assert(source:find("local function SaveVendorPlannerItem", start, true))
    source = source:sub(1, start - 1) .. [[
local function GetVendorPlannerKey(button)
    local itemID = GetVendorItemID(button)
    if not itemID then return nil end
    local vendorKey = UnitGUID and UnitGUID("npc") or nil
    if not IsSafeText(vendorKey) then vendorKey = UnitName and UnitName("npc") or "merchant" end
    return tostring(vendorKey or "merchant") .. ":" .. itemID
end
]] .. source:sub(finish)
end

local function section(first, following)
    local start = assert(source:find(first, 1, true), "missing source boundary: " .. first)
    local finish = assert(source:find(following, start + #first, true), "missing source boundary: " .. following)
    return source:sub(start, finish - 1)
end
local production = source:sub(1, assert(source:find("local function GetNPCIDFromGUID", 1, true)) - 1)
    .. section("local function IsTextMode()", "-- EllesmereUI owns the confirmation popup")
    .. section("local function GetVendorPlanner()", "local function GetItemQueueSettings()")
    .. section("local function IsSafeValue", "local function NormalizeItemQueueTooltipText")
    .. section("local function TooltipShowsMaxedCount", "local function IsCompletedQueueItem")
    .. section("local function GetMerchantCosts", "local zygorPointerSkin")
    .. "\nreturn addon\n"

local function check(value, message) assert(value, message or "vendor list regression") end
local function equal(actual, expected, message)
    check(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.01, (message or "geometry differs") .. ": expected " .. expected .. ", got " .. actual)
end

-- Frame coordinates are expressed in each object's effective-scale units,
-- as GetLeft/GetRight and physical GetCursorPosition require in the client.
local Object = {}
Object.__index = Object
local function newObject(kind, parent, region)
    local obj = setmetatable({kind = kind, parent = parent, children = {}, regions = {}, points = {}, scripts = {}, shown = true}, Object)
    if parent then table.insert(region and parent.regions or parent.children, obj) end
    return obj
end
local function factors(point)
    return point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5,
        point:find("TOP") and 0 or point:find("BOTTOM") and 1 or 0.5
end
function Object:GetScale() return self.scale or 1 end
function Object:SetScale(value) self.scale = value end
function Object:GetEffectiveScale() return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Object:_Axis(vertical)
    local size = (vertical and self.height or self.width) or 0
    local start, fraction
    for _, p in ipairs(self.points) do
        local x, y = factors(p[1])
        local rx, ry = factors(p[3])
        local f, rf = vertical and y or x, vertical and ry or rx
        local relative = p[2]
        local base = vertical and relative:GetTop() or relative:GetLeft()
        local extent = vertical and relative:GetHeight() or relative:GetWidth()
        local sign = vertical and -1 or 1
        local coordinate = (base + sign * rf * extent) * relative:GetEffectiveScale() / self:GetEffectiveScale()
            + (vertical and p[5] or p[4])
        if start and f ~= fraction then
            size = (coordinate - start) / (sign * (f - fraction))
            return start - sign * fraction * size, size
        end
        start, fraction = coordinate, f
    end
    return start and start + (vertical and 1 or -1) * fraction * size
        or (vertical and (self.top or size) or (self.left or 0)), size
end
function Object:GetLeft() return (self:_Axis(false)) end
function Object:GetTop() return (self:_Axis(true)) end
function Object:GetWidth() local _, value = self:_Axis(false); return value end
function Object:GetHeight() local _, value = self:_Axis(true); return value end
function Object:GetRight() return self:GetLeft() + self:GetWidth() end
function Object:GetBottom() return self:GetTop() - self:GetHeight() end
function Object:SetSize(width, height)
    local changed = self.width ~= width or self.height ~= height
    self.width, self.height = width, height
    if changed then self:Fire("OnSizeChanged", width, height) end
end
function Object:SetWidth(value) self:SetSize(value, self.height or 0) end
function Object:SetHeight(value) self:SetSize(self.width or 0, value) end
function Object:ClearAllPoints() self.points = {} end
function Object:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point end
    relative, relativePoint = relative or self.parent, relativePoint or point
    check(relative, "anchor has no relative object")
    local entry = {point, relative, relativePoint, x or 0, y or 0}
    for index, old in ipairs(self.points) do
        if old[1] == point then self.points[index] = entry; return end
    end
    self.points[#self.points + 1] = entry
end
function Object:SetAllPoints(relative)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", relative or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relative or self.parent, "BOTTOMRIGHT", 0, 0)
end
function Object:GetNumPoints() return #self.points end
function Object:GetPoint(index) return unpack(self.points[index or 1] or {}) end
function Object:GetParent() return self.parent end
function Object:GetChildren() return unpack(self.children) end
function Object:GetRegions() return unpack(self.regions) end
function Object:CreateTexture() return newObject("Texture", self, true) end
function Object:CreateFontString() return newObject("FontString", self, true) end
function Object:SetScript(name, callback) self.scripts[name] = callback end
function Object:GetScript(name) return self.scripts[name] end
function Object:HookScript(name, callback)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; callback(...) end
end
function Object:Fire(name, ...) if self.scripts[name] then return self.scripts[name](self, ...) end end
function Object:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Object:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Object:IsShown() return self.shown end
function Object:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Object:SetShown(value) if value then self:Show() else self:Hide() end end
function Object:SetFrameLevel(value) self.level = value end
function Object:SetFrameStrata(value) self.strata = value end
function Object:SetClampedToScreen(value) self.clamped = value end
function Object:IsMouseOver() return self.mouseOver == true end
function Object:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel() + 1) or 1 end
function Object:SetFont(font, size, flags) self.font, self.fontSize, self.fontFlags = font, size, flags end
function Object:GetFont() return self.font or "mock-font", self.fontSize or 10, self.fontFlags or "OUTLINE" end
function Object:SetText(value) self.text = value end
function Object:GetText() return self.text end
function Object:GetStringWidth() return #(tostring(self.text or ""):gsub("|T.-|t", "xx"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * (self.fontSize or 10) * 0.5 end
function Object:SetJustifyH(value) self.justifyH = value end
function Object:GetJustifyH() return self.justifyH or "LEFT" end
function Object:SetTexture(value) self.texture = value end
function Object:SetColorTexture(...) self.color = {...} end
function Object:SetTextColor(...) self.color = {...} end
function Object:SetVertexColor(...) self.color = {...} end
function Object:SetAlpha(value) self.alpha = value end
function Object:GetAlpha() return self.alpha or 1 end
function Object:SetVerticalScroll(value) self.scroll = value end
function Object:GetVerticalScroll() return self.scroll or 0 end
function Object:GetVerticalScrollRange() return math.max(0, self.ScrollChild:GetHeight() - self:GetHeight()) end
for _, name in ipairs({"EnableMouse", "RegisterForDrag", "RegisterForClicks", "SetWordWrap", "SetMaxLines", "SetTexCoord"}) do
    Object[name] = function() end
end
function Object:SetPropagateMouseClicks()
    error("protected SetPropagateMouseClicks must not run during vendor refresh", 2)
end

local function secretOperation() error("attempt to transform a secret NPC identity", 2) end
local SECRET = setmetatable({}, {__concat = secretOperation, __tostring = secretOperation})
local SECRET_GUID, SECRET_NAME = "protected-NPC-GUID", "protected-NPC-name"
local function fixture(options)
    options = options or {}
    local state = {timers = {}, cursorX = 0, mouseDown = false, time = 0, entries = options.entries or {
        {id = 101, name = "Soulguard", price = 0},
        {id = 102, name = "Spirit Potion", price = 0},
    }}
    state.settings = {vendorItemView = options.view or "list"}
    local env = setmetatable({}, {__index = _G})
    env._G, env.unpack, env.WaffleHouseDB = env, unpack, state.settings
    env.UIParent = newObject("Frame")
    env.UIParent:SetSize(1920, 1080)
    env.UIParent:SetScale(options.uiScale or 1)
    env.UIParent.left, env.UIParent.top = 0, 1080
    env.STANDARD_TEXT_FONT = "mock-font"
    env.issecretvalue = function(value) return value == SECRET or value == SECRET_GUID or value == SECRET_NAME end
    env.UnitGUID = function() return options.guid == nil and SECRET or options.guid end
    env.UnitName = function() return options.name == nil and SECRET or options.name end
    env.CreateFrame = function(kind, _, parent) return newObject(kind, parent or env.UIParent) end
    env.hooksecurefunc = function(object, method, callback)
        local original = assert(object[method])
        object[method] = function(self, ...) local results = {original(self, ...)}; callback(self, ...); return unpack(results) end
    end
    env.C_Timer = {After = function(_, callback) table.insert(state.timers, callback) end}
    env.GetTime = function() return state.time end
    env.GetCursorPosition = function() return state.cursorX, 0 end
    env.IsMouseButtonDown = function() return state.mouseDown end
    env.IsModifierKeyDown = function() return state.modifier == "generic" end
    env.IsControlKeyDown = function() return state.modifier == "ctrl" end
    env.IsShiftKeyDown = function() return state.modifier == "shift" end
    env.IsAltKeyDown = function() return state.modifier == "alt" end
    env.HandleModifiedItemClick = function(link)
        state.modifiedClicks = (state.modifiedClicks or 0) + 1
        state.modifiedLink = link
        return state.modifiedHandled == true
    end
    env.GetMerchantNumItems = function() return #state.entries end
    env.GetMerchantItemCostInfo = function() return options.noCosts and 0 or 1 end
    env.GetMerchantItemCostItem = function(index) return 12345, index * 10, "currency:7", "Ethereal Credit" end
    env.GetMerchantItemInfo = function(index)
        local entry = state.entries[index]
        if entry then return entry.name, 12345, entry.price, 1, -1, true, false, not options.noCosts end
    end
    env.GetMerchantItemLink = function(index)
        local entry = state.entries[index]
        return entry and ("|cff0070dd|Hitem:" .. entry.id .. "|h[" .. entry.name .. "]|h|r")
    end
    env.GetMoney = function() return 10000 end
    env.PlayerHasToy = function(itemID) return options.knownToyIDs and options.knownToyIDs[itemID] == true or false end
    env.GetCoinTextureString = function(value) return tostring(value) .. " copper" end
    env.GetItemInfo = function() return "Item", nil, 3, nil, nil, "Armor", "Plate" end
    env.GetItemQualityColor = function() return 0, 0.44, 0.87 end
    env.C_CurrencyInfo = {GetCurrencyInfo = function() return {quantity = 50} end}
    if options.factions then
        env.C_MajorFactions = {
            GetMajorFactionIDs = function()
                local ids = {}
                for index = 1, #options.factions do ids[index] = index end
                return ids
            end,
            GetMajorFactionData = function(index) return options.factions[index] end,
        }
    end
    env.C_TooltipInfo = {GetMerchantItem = function(index)
        local entry = state.entries[index]
        if not entry or not entry.tooltip then return nil end
        return {lines = {{leftText = entry.name}, {leftText = entry.tooltip}}}
    end}
    env.C_Item = {GetItemInfo = env.GetItemInfo, GetItemInfoInstant = function() return 101, nil, nil, nil, nil, 4, 4 end}
    env.EllesmereUI = {MakeBorder = function() return {SetColor = function() end} end}
    local frame = newObject("Frame", env.UIParent)
    frame:SetScale(options.scale or 1)
    frame:SetSize(options.width or 640, 420)
    frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 100, -100)
    frame.Header = newObject("Frame", frame)
    frame.Header:SetSize(frame:GetWidth(), 35)
    frame.Header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.Sidebar = newObject("Frame", frame)
    frame.Sidebar:SetWidth(160)
    frame.Footer = newObject("Frame", frame)
    frame.Footer:SetHeight(24)
    frame.Footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.Footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.ScrollFrame = newObject("ScrollFrame", frame)
    frame.ScrollFrame:SetSize(frame:GetWidth() - 160, 320)
    frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -36)
    frame.ScrollChild = newObject("Frame", frame.ScrollFrame)
    frame.ScrollChild:SetSize(frame:GetWidth() - 162, 320)
    frame.ScrollChild:SetPoint("TOPLEFT", frame.ScrollFrame, "TOPLEFT", 0, 0)
    frame.ScrollFrame.ScrollChild = frame.ScrollChild
    frame.EmptyLabel = frame.ScrollChild:CreateFontString()
    frame.EmptyLabel:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 16, -8)
    frame.EmptyLabel:SetSize(180, 12)
    frame.EmptyLabel:SetText("No items match your filter.")
    frame.EmptyLabel:Hide()
    frame.UpdateThumb = function() state.thumbUpdates = (state.thumbUpdates or 0) + 1 end
    frame.SearchBox = newObject("EditBox", frame)
    env.EUI_VendorBagFrame = frame
    state.frame, state.env, state.buttons, state.headers = frame, env, {}, {}
    for index, entry in ipairs(state.entries) do
        local header = newObject("Frame", frame.ScrollChild)
        header:SetSize(200, 20)
        header:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8, -6 - (index - 1) * 70)
        header.label, header.line = header:CreateFontString(), header:CreateTexture()
        state.headers[index] = header
        local slot = newObject("Frame", frame.ScrollChild)
        slot:SetSize(34, 34)
        slot:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8, -30 - (index - 1) * 70)
        local button = newObject("Button", slot)
        button:SetAllPoints(slot)
        button.SlotParent, button._merchantIndex, button._link = slot, index, env.GetMerchantItemLink(index)
        button.icon = button:CreateTexture()
        button.icon:SetAllPoints(button)
        button.PriceText, button.StockText, button.Count = button:CreateFontString(), button:CreateFontString(), button:CreateFontString()
        button.PriceText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
        button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button:SetScript("OnClick", function() state.purchases = (state.purchases or 0) + 1 end)
        button.EUIVendorBagInsetBorder = {top = button:CreateTexture(), bottom = button:CreateTexture(), left = button:CreateTexture(), right = button:CreateTexture()}
        state.buttons[index] = button
    end
    local addon = {}
    local factory = assert(load(production, "@production-vendor-refresh", "t", env))
    state.addon = factory("WaffleHouse_EllesmereUI", addon)
    function state:flush()
        local turns = 0
        while #self.timers > 0 do
            turns = turns + 1
            check(turns < 20, "refresh recursively scheduled itself")
            local pending = self.timers
            self.timers = {}
            for _, callback in ipairs(pending) do callback() end
        end
    end
    function state:toolbar()
        for _, child in ipairs(frame.children) do if child.list and child.rows then return child end end
        error("real refresh did not create toolbar")
    end
    return state
end

local function assertList(state)
    local frame = state.frame
    local header = frame._waffleListHeader
    check(header and header:IsShown(), "refresh must reach the list renderer and show column headers")
    for index, button in ipairs(state.buttons) do
        if button:IsShown() then
            check(button._waffleListApplied and button._waffleListName:IsShown(), "visible merchant item must become a list row")
            near(button.SlotParent:GetWidth(), frame.ScrollChild:GetWidth() - 6, "row must stretch across scroll content")
            near(button.icon:GetWidth(), 26, "icon must stay square")
            near(button.icon:GetHeight(), 26, "icon height")
            check(button._waffleListCost:GetStringWidth() <= button._waffleListCost:GetWidth(), "cost must fit its column")
            check(button:GetTop() < header:GetBottom(), "row must remain below column titles")
            check(not state.headers[index]:IsShown(), "host category heading must hide in list view")
            check(not button.EUIVendorBagInsetBorder.top:IsShown(), "host quality border must not wrap full list row")
            check(button._wafflePlannerControl:IsShown(), "planner pin must remain interactive")
        end
    end
end

-- This models Vendor Bags' renderer order: it reanchors pooled grid slots,
-- writes the final content height, then clamps the current scroll position.
-- The height write is Waffle House's only post-render hook, so a list reflow
-- must complete before this function returns.
local function renderNativeVendorGrid(state, contentHeight)
    local frame = state.frame
    for index, button in ipairs(state.buttons) do
        button.SlotParent:ClearAllPoints()
        button.SlotParent:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8 + (index - 1) * 38, -30)
        button.SlotParent:SetSize(34, 34)
        button.icon:SetAllPoints(button)
        state.headers[index]:Show()
    end
    frame.ScrollChild:SetHeight(contentHeight)
    frame.ScrollFrame:SetVerticalScroll(math.min(frame.ScrollFrame:GetVerticalScroll(), frame.ScrollFrame:GetVerticalScrollRange()))
end

local passed, failures = 0, {}
local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; io.write("PASS: " .. name .. "\n")
    else failures[#failures + 1] = name .. ": " .. tostring(err); io.write("FAIL: " .. failures[#failures] .. "\n") end
end

test("secret GUID and secret name do not abort refresh before list rendering", function()
    local state = fixture()
    state.addon.Refresh()
    state:flush()
    assertList(state)
    local pin = state.buttons[1]._wafflePlannerControl
    pin:Fire("OnClick", "LeftButton")
    check(state.settings.vendorPlanner["merchant:101"], "secret identities must use readable fallback planner namespace")
    equal(state.settings.vendorPlanner["merchant:101"].vendor, "Merchant", "saved vendor name must not retain secret identity")
    assertList(state)
    pin:Fire("OnClick", "LeftButton")
    equal(state.settings.vendorPlanner["merchant:101"], nil, "second click must remove saved item")
    equal(state.purchases, nil, "planner click must not buy the item")
    state.buttons[1]:Fire("OnClick")
    equal(state.purchases, 1, "native item purchase callback must be preserved")
end)

test("secret string values are rejected despite retaining Lua string type", function()
    local state = fixture({guid = SECRET_GUID, name = SECRET_NAME})
    state.addon.Refresh()
    assertList(state)
    state.buttons[1]._wafflePlannerControl:Fire("OnClick", "LeftButton")
    check(state.settings.vendorPlanner["merchant:101"], "secret strings must use neutral readable key")
    equal(state.settings.vendorPlanner["merchant:101"].vendor, "Merchant", "secret string name must not persist")
end)

test("readable name and GUID retain existing planner namespaces", function()
    for _, identity in ipairs({{guid = SECRET, name = "Soul-Trader", key = "Soul-Trader:101"}, {guid = "Creature-0-1-2-3-27914-0", name = SECRET, key = "Creature-0-1-2-3-27914-0:101"}}) do
        local state = fixture(identity)
        state.addon.Refresh()
        state.buttons[1]._wafflePlannerControl:Fire("OnClick", "LeftButton")
        check(state.settings.vendorPlanner[identity.key], "safe identity must preserve saved planner key")
    end
end)

test("real list toggle restores pooled slots, all-points icons, borders and headers", function()
    local state = fixture({view = "grid"})
    state.addon.Refresh()
    local button = state.buttons[1]
    local nativeLeft, nativeTop = button:GetLeft(), button:GetTop()
    local toggle = state:toolbar().list
    toggle:Fire("OnClick")
    state:flush()
    equal(state.settings.vendorItemView, "list", "toggle must persist list setting")
    assertList(state)
    toggle:Fire("OnClick")
    state:flush()
    equal(state.settings.vendorItemView, "grid", "toggle must persist grid setting")
    near(button.SlotParent:GetWidth(), 34, "grid width must restore")
    near(button:GetLeft(), nativeLeft, "grid x must restore")
    near(button:GetTop(), nativeTop, "grid y must restore")
    equal(button.icon:GetNumPoints(), 2, "native icon all-points anchors must restore")
    near(button.icon:GetWidth() * button.icon:GetScale(), 34, "restored icon anchors must constrain its physical width")
    check(state.headers[1]:IsShown() and button.EUIVendorBagInsetBorder.top:IsShown(), "native header and border must restore")
    check(not state.frame._waffleListHeader:IsShown() and not button._waffleListName:IsShown(), "list-only regions must hide")
    near(button._wafflePlannerControl:GetWidth(), 24, "grid pin width must restore")
    near(button._wafflePlannerControl:GetHeight(), 28, "grid pin height must restore")
end)

test("header drag at non-default frame scale persists order and realigns row cells", function()
    local state = fixture({scale = 0.8, uiScale = 0.9})
    state.addon.Refresh()
    local header = state.frame._waffleListHeader
    local cost = header.columnControls.cost
    state.mouseDown = true
    state.cursorX = (header.columnControls.icon:GetLeft() + 1) * header:GetEffectiveScale()
    cost:Fire("OnMouseDown", "LeftButton")
    check(not header._waffleListDropGuide:IsShown(), "a normal press must not flash the drag divider")
    state.time = state.time + 0.26
    header:Fire("OnUpdate")
    check(header._waffleListDropGuide:IsShown(), "drag must show insertion guide")
    equal(header._waffleListDragDropIndex, 1, "physical cursor must be normalized by header effective scale")
    state.mouseDown = false
    header:Fire("OnUpdate")
    state:flush()
    equal(state.settings.vendorListColumnOrder[1], "cost", "drop must save cost-first ordering")
    check(not header._waffleListDropGuide:IsShown() and not header:GetScript("OnUpdate"), "finished drag must release guide and update handler")
    near(state.buttons[1]._waffleListCost:GetLeft(), header.columnControls.cost:GetLeft(), "row cells must follow reordered header")
    assertList(state)
end)

test("short header clicks sort whole rows and a second click reverses direction", function()
    local state = fixture()
    state.entries[1].name = "Zulu Relic"
    state.entries[2].name = "Apple Relic"
    state.addon.Refresh()
    local header = state.frame._waffleListHeader
    local item = header.columnControls.item

    state.mouseDown = true
    item:Fire("OnMouseDown", "LeftButton")
    check(not header._waffleListDropGuide:IsShown(), "a sort click must not display the reorder divider")
    state.time = state.time + 0.24
    header:Fire("OnUpdate")
    check(header._waffleListHeaderPress, "a press shorter than 0.25 seconds must remain a click")
    state.mouseDown = false
    item:Fire("OnMouseUp", "LeftButton")
    item:Fire("OnClick", "LeftButton")
    item:Fire("OnLeave")
    state:flush()
    equal(state.settings.vendorListSortColumn, "item", "first header click must select that sort column")
    equal(state.settings.vendorListSortAscending, true, "first header click must sort ascending")
    check(state.buttons[2]:GetTop() > state.buttons[1]:GetTop(), "every cell must move with its Apple item row")

    state.mouseDown = true
    item:Fire("OnMouseDown", "LeftButton")
    state.mouseDown = false
    item:Fire("OnMouseUp", "LeftButton")
    item:Fire("OnClick", "LeftButton")
    item:Fire("OnLeave")
    state:flush()
    equal(state.settings.vendorListSortAscending, false, "second click on the same column must sort descending")
    check(state.buttons[1]:GetTop() > state.buttons[2]:GetTop(), "descending sort must move the complete Zulu row back to the top")

    -- Some UI surfaces deliver the Button click even if an overlapping frame
    -- swallows MouseUp. Its callback must still finish the pending sort.
    state.mouseDown = true
    item:Fire("OnMouseDown", "LeftButton")
    state.mouseDown = false
    item:Fire("OnClick", "LeftButton")
    state:flush()
    equal(state.settings.vendorListSortAscending, true, "OnClick fallback must complete a missed MouseUp")
    check(state.buttons[2]:GetTop() > state.buttons[1]:GetTop(), "fallback must reorder complete rows")
    assertList(state)
end)

test("cost header orders entire rows by price and reverses on second click", function()
    local state = fixture({noCosts = true})
    state.entries[1].price = 500
    state.entries[2].price = 100
    state.addon.Refresh()
    local header = state.frame._waffleListHeader
    local cost = header.columnControls.cost
    cost:Fire("OnMouseDown", "LeftButton")
    cost:Fire("OnMouseUp", "LeftButton")
    cost:Fire("OnClick", "LeftButton")
    state:flush()
    equal(state.settings.vendorListSortColumn, "cost", "cost click must select cost sorting")
    equal(cost.sortMarker.font, "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Arial Narrow.ttf",
        "sort direction must use a font that contains the triangle glyph")
    equal(cost.sortMarker.text, "▲", "ascending cost header must show its sort glyph")
    check(cost.sortMarker:IsShown(), "sort glyph must be visible when the column is active")
    check(state.buttons[2]:GetTop() > state.buttons[1]:GetTop(), "cheaper item's whole row must move first")
    local tooltip = { shown = false }
    function tooltip:SetOwner() end
    function tooltip:SetText(text) self.text = text end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    state.env.GameTooltip = tooltip
    cost:Fire("OnEnter")
    check(tooltip.shown and tooltip.text:find("Click to sort", 1, true),
        "header hover must use a reliable tooltip even if EllesmereUI's helper is unavailable")
    cost:Fire("OnLeave")
    check(not tooltip.shown, "header hover tooltip must close on leave")
    cost:Fire("OnMouseDown", "LeftButton")
    cost:Fire("OnMouseUp", "LeftButton")
    cost:Fire("OnClick", "LeftButton")
    state:flush()
    equal(cost.sortMarker.text, "▼", "descending cost header must switch glyph")
    check(state.buttons[1]:GetTop() > state.buttons[2]:GetTop(), "higher price row must move first descending")
end)

test("modern merchant prices are used and missing prices never read as free", function()
    local entries = {
        { id = 101, name = "Gold item", price = 12345 },
        { id = 102, name = "Free item", price = 0 },
        { id = 103, name = "Pending item" },
        { id = 104, name = "Alternate item", price = 0, extended = true },
    }
    local state = fixture({ noCosts = true, entries = entries })
    state.env.GetMerchantItemInfo = function() return nil end
    state.env.C_MerchantFrame = { GetItemInfo = function(index)
        local entry = entries[index]
        if index == 3 then return nil end
        return { name = entry.name, texture = 12345, price = entry.price,
            hasExtendedCost = entry.extended == true }
    end }
    state.addon.Refresh()
    check(state.buttons[1]._waffleListCost.text:find("Gold", 1, true),
        "the list must use a readable modern gold price even without the legacy API")
    equal(state.buttons[2]._waffleListCost.text, "Free", "confirmed zero-price items may read Free")
    equal(state.buttons[3]._waffleListCost.text, "Price unavailable",
        "a missing merchant price must not be called Free")
    equal(state.buttons[4]._waffleListCost.text, "Alt cost unavailable",
        "an extended cost that has not loaded must not be called Free")
    equal(state.addon.GetVendorListCostSortValue(state.buttons[3], {}), "3",
        "unknown prices must sort separately from confirmed free items")
end)

test("seven-item ascending cost sort keeps every vendor item in its own row", function()
    local entries = {}
    for index, price in ipairs({ 10, 70, 30, 50, 20, 60, 40 }) do
        entries[index] = { id = 100 + index, name = "Decor " .. index, price = price }
    end
    local state = fixture({ noCosts = true, entries = entries })
    state.settings.vendorListSortColumn = "cost"
    state.settings.vendorListSortAscending = true
    state.addon.Refresh()
    local seen = {}
    for _, button in ipairs(state.buttons) do
        local top = button:GetTop()
        check(not seen[top], "sorted vendor buttons must not share a row")
        seen[top] = true
    end
    equal(state.buttons[1]._waffleListIndex, 1, "cheapest item must remain the first whole row")
    equal(state.buttons[2]._waffleListIndex, 7, "most expensive item must remain the last whole row")
end)

test("cost sort ignores rarity and secondary currency while Rarity remains its own choice", function()
    local entries, costs = {}, {}
    local amounts = { 200, 150, 150, 100, 100, 100, 200 }
    local qualities = { 2, 3, 2, 3, 2, 3, 3 }
    for index, amount in ipairs(amounts) do
        entries[index] = { id = 100 + index, name = "Decor " .. index, price = 0 }
        costs[index] = { { amount = amount, link = index == 7 and "currency:1" or "currency:9",
            name = index == 7 and "Artisan Moxie" or "Brimming Arcana" } }
    end
    costs[7][2] = { amount = 150, link = "currency:9", name = "Brimming Arcana" }
    local state = fixture({ entries = entries })
    state.env.GetMerchantItemCostInfo = function(index) return #costs[index] end
    state.env.GetMerchantItemCostItem = function(index, costIndex)
        local cost = costs[index][costIndex]
        return 12345, cost.amount, cost.link, cost.name
    end
    state.env.GetItemInfo = function(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        return "Item", nil, qualities[(id or 100) - 100], nil, nil, "Armor", "Plate"
    end
    state.settings.vendorListSortColumn = "cost"
    state.settings.vendorListSortAscending = false
    state.addon.Refresh()
    equal(state.buttons[1]._waffleListIndex, 1, "first 200-cost item must lead descending Cost")
    equal(state.buttons[7]._waffleListIndex, 2,
        "a second 200-cost item must stay with 200s despite its different currency and rarity")
    equal(state.buttons[2]._waffleListIndex, 3, "150-cost items must follow both 200-cost items")
    equal(state.buttons[4]._waffleListIndex, 5, "100-cost items must follow the 150-cost items")
    check(state.frame._waffleListHeader.columnControls.rarity:IsShown(),
        "Rarity must be a visible independent header by default")
    equal(state.buttons[1]._waffleListRarity.text, "Uncommon", "Rarity column must name item quality")
    equal(state.buttons[7]._waffleListRarity.text, "Rare", "Rarity column must name higher quality")

    state.settings.vendorListSortColumn = "rarity"
    state.settings.vendorListSortAscending = true
    state.addon.Refresh()
    equal(state.buttons[1]._waffleListIndex, 1, "ascending Rarity must put Uncommon first")
    equal(state.buttons[3]._waffleListIndex, 2, "Rarity sort must group equal qualities")
    equal(state.buttons[5]._waffleListIndex, 3, "Rarity sort must not defer to cost")

    state.settings.vendorListShowRarity = false
    state.addon.Refresh()
    check(not state.frame._waffleListHeader.columnControls.rarity:IsShown()
        and not state.buttons[1]._waffleListRarity:IsShown(),
        "hiding Rarity in Vendor options must hide both header and row cells")
end)

test("rarity and cost columns keep a gutter at the smallest vendor widths", function()
    local state = fixture()
    state.settings.vendorListColumnOrder = { "icon", "pin", "item", "type", "cost" }
    local migrated = state.addon.GetVendorListColumnOrder()
    equal(migrated[5], "rarity", "saved default layouts must add Rarity before Cost")
    equal(migrated[6], "cost", "saved default layouts must keep Cost on the far right")
    for _, width in ipairs({ 192, 270, 340, 545 }) do
        local layout = state.addon.GetVendorListColumnLayout(width)
        local previousRight = nil
        for _, key in ipairs(layout.order) do
            local column = layout.columns[key]
            check(column and column.width > 0, "each visible list column needs positive width")
            if previousRight then
                check(column.x - previousRight >= 5, "visible columns need a five-pixel gutter")
            end
            previousRight = column.x + column.width
        end
        check(previousRight <= width - 9, "last column must clear the right border")
        equal(layout.columns.rarity ~= nil, width >= 270,
            "Rarity must release its space when the vendor window is too narrow")
    end
end)

test("column resize divider appears only after the held-drag threshold", function()
    local state = fixture()
    state.addon.Refresh()
    local header = state.frame._waffleListHeader
    local divider = header.resizeControls.icon
    state.mouseDown = true
    divider:Fire("OnMouseDown", "LeftButton")
    check(not divider.line:IsShown(), "divider must stay hidden when the mouse first goes down")
    state.time = state.time + 0.24
    header:Fire("OnUpdate")
    check(not divider.line:IsShown(), "divider must stay hidden before 0.25 seconds")
    state.time = state.time + 0.02
    header:Fire("OnUpdate")
    check(divider.line:IsShown(), "divider must appear once the held resize starts")
    state.mouseDown = false
    header:Fire("OnUpdate")
    check(not divider.line:IsShown(), "divider must hide after the resize drag ends")
end)

test("pooled render and resize defer until final host pass then refresh list", function()
    local state = fixture()
    state.addon.Refresh()
    local frame = state.frame
    frame._liveWindowWidth = true
    frame:SetWidth(350)
    frame.ScrollChild:SetWidth(188)
    for index, button in ipairs(state.buttons) do
        button.SlotParent:ClearAllPoints()
        button.SlotParent:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8 + (index - 1) * 38, -30)
        button.SlotParent:SetSize(34, 34)
        button.icon:SetAllPoints(button)
        state.headers[index]:Show()
    end
    frame.ScrollChild:SetHeight(100)
    state.addon.Refresh()
    near(state.buttons[1].SlotParent:GetWidth(), 34, "active resize must leave host render alone")
    check(frame._waffleListRefreshAfterResize, "resize must record deferred refresh")
    frame._liveWindowWidth = nil
    frame.ScrollChild:SetHeight(100)
    assertList(state)
    equal(#state.timers, 0, "release render must not leave a deferred list reflow")
    check(not frame._waffleListHeader.columnControls.type:IsShown(), "narrow layout must collapse type column")
    check(not frame._waffleListRefreshAfterResize, "final render must clear deferred refresh")
    local top = state.buttons[1]:GetTop()
    state.addon.Refresh()
    near(state.buttons[1]:GetTop(), top, "repeated refresh must not accumulate row offsets")
    frame:SetWidth(640)
    frame.ScrollChild:SetWidth(478)
    frame.ScrollChild:SetHeight(320)
    state:flush()
    check(frame._waffleListHeader.columnControls.type:IsShown(), "widening must restore type column")
    assertList(state)
end)

test("purchase grid redraws restore list and preserve scroll before host clamp", function()
    local entries = {}
    for index = 1, 12 do
        entries[index] = {id = 100 + index, name = "Purchase row " .. index, price = 0}
    end
    local state = fixture({entries = entries})
    state.addon.Refresh()
    local frame = state.frame
    frame.ScrollFrame:SetVerticalScroll(31)

    -- A purchase produces BAG_UPDATE while Vendor Bags repeatedly redraws its
    -- pooled grid.  Each final height update must restore the list immediately,
    -- before the native renderer clamps the current scroll value.
    state.buttons[1]:Fire("OnClick", "LeftButton")
    equal(state.purchases, 1, "purchase must still reach the native click handler")
    for pass = 1, 3 do
        renderNativeVendorGrid(state, 720 - pass * 40)
        assertList(state)
        equal(frame.ScrollFrame:GetVerticalScroll(), 31,
            "host scroll clamp must preserve the current list position after redraw " .. pass)
        equal(#state.timers, 0, "host redraw " .. pass .. " must not leave a list refresh queued")
    end

    -- Switching to grid after a purchase must leave Vendor Bags' pooled layout
    -- untouched; the list renderer may only recover the list view.
    state.settings.vendorItemView = "grid"
    state.addon.Refresh()
    renderNativeVendorGrid(state, 600)
    for index, button in ipairs(state.buttons) do
        check(not button._waffleListApplied, "grid view must restore native pooled slot " .. index)
        near(button.SlotParent:GetWidth(), 34, "grid slot must retain native width " .. index)
        check(state.headers[index]:IsShown(), "grid category header must remain native " .. index)
    end
end)

test("vendor switch repairs a late host grid redraw and refreshes currency rows", function()
    local state = fixture()
    local frame = state.frame
    local host = {}
    host.RefreshEUILayout = function()
        -- The host can finish a fresh merchant render after Waffle House's
        -- event refresh. Its native layout reclaims the toolbar and grid.
        frame.ScrollFrame:ClearAllPoints()
        frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -36)
        for index, button in ipairs(state.buttons) do
            local slot = button.SlotParent
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8 + (index - 1) * 38, -30)
            slot:SetSize(34, 34)
            button.icon:SetAllPoints(button)
            state.headers[index]:Show()
        end
    end
    state.env.EllesmereUIVendorBag = host
    state.addon.Refresh()
    assertList(state)

    state.entries[1] = {id = 901, name = "Amani Hide Cutter", price = 0}
    state.entries[2] = {id = 902, name = "Amani Log Splitter", price = 0}
    state.env.GetMerchantItemCostItem = function()
        return 54321, 800, "currency:9", "Unalloyed Abundance"
    end
    for index, button in ipairs(state.buttons) do
        button._link = state.env.GetMerchantItemLink(index)
    end
    host.RefreshEUILayout()

    assertList(state)
    local toolbar = state:toolbar()
    equal(select(2, frame.ScrollFrame:GetPoint(1)), toolbar,
        "currency panel must own the scroll-frame top after merchant switch")
    check(frame._waffleListHeader:GetTop() < toolbar:GetBottom(),
        "column headers must sit below the currency panel")
    equal(toolbar.rows[1]._currencyName, "Unalloyed Abundance",
        "merchant switch must replace the previous currency")
    check(toolbar.rows[1]:IsShown(), "the new merchant currency must be visible")
    equal(state.buttons[1]._waffleListName:GetText(), "Amani Hide Cutter",
        "reused list rows must display the new merchant's items")
end)

test("shorter vendor never revives pooled items hidden by the previous filter", function()
    local state = fixture()
    local frame = state.frame
    local host = {}
    host.RefreshEUILayout = function()
        frame._slotOffset = #state.entries
        frame.ScrollFrame:ClearAllPoints()
        frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -36)
        for index, button in ipairs(state.buttons) do
            button:SetShown(index <= frame._slotOffset)
            button.SlotParent:SetShown(index <= frame._slotOffset)
            state.headers[index]:SetShown(index <= frame._slotOffset)
        end
    end
    state.env.EllesmereUIVendorBag = host
    state.addon.Refresh()
    state.settings.legendSavedOnly = true
    state.addon.Refresh()
    check(state.buttons[2]._waffleCurrencyFilterApplied,
        "previous merchant's filtered pooled button must exercise the stale-state path")

    state.entries = {{id = 903, name = "One New Item", price = 0}}
    state.buttons[1]._link = state.env.GetMerchantItemLink(1)
    host.RefreshEUILayout()
    check(not state.buttons[2]:IsShown() and not state.buttons[2].SlotParent:IsShown(),
        "unused pooled item must remain hidden after merchant change")
    check(not state.buttons[2]._waffleListApplied,
        "unused pooled item must release the previous merchant's list styling")
    state.settings.legendSavedOnly = false
    state.addon.Refresh()
    assertList(state)
    check(state.buttons[1]:IsShown() and not state.buttons[2]:IsShown(),
        "clearing the filter must restore only the current merchant's item")
    equal(state.buttons[1]._waffleListName:GetText(), "One New Item")
end)

test("saved-only empty state clears stale rows and remains below column header", function()
    local state = fixture()
    state.addon.Refresh()
    state:toolbar().saved:Fire("OnClick")
    check(state.settings.legendSavedOnly, "saved-only toggle must run actual filter path")
    for _, button in ipairs(state.buttons) do check(not button:IsVisible(), "unsaved row must hide") end
    for _, button in ipairs(state.buttons) do
        check(not button._waffleListApplied, "hidden pooled buttons must release old list decorations")
    end
    check(state.frame.EmptyLabel:IsShown(), "empty list must show native empty label")
    check(state.frame.EmptyLabel:GetTop() < state.frame._waffleListHeader:GetBottom() - 4, "empty copy must clear column header")
    state:toolbar().saved:Fire("OnClick")
    check(not state.frame.EmptyLabel:IsShown(), "restoring results must hide empty copy")
    assertList(state)
end)

test("RENOWN filters only confirmed unmet requirements in both vendor views", function()
    for _, view in ipairs({"grid", "list"}) do
        local state = fixture({view = view,
            factions = {{name = "Silvermoon Court", renownLevel = 10}},
            entries = {
                {id = 101, name = "Fiery Dragonhawk", price = 0, tooltip = "Requires Renown Rank 19 with the Silvermoon Court."},
                {id = 102, name = "Available Reward", price = 0, tooltip = "Requires Renown Rank 10 with the Silvermoon Court."},
                {id = 103, name = "Other Faction", price = 0, tooltip = "Requires Renown Rank 19 with the Unknown Court."},
                {id = 104, name = "Unrestricted Reward", price = 0, tooltip = "Some other requirement."},
                {id = 105, name = "Unreadable Reward", price = 0, tooltip = SECRET_NAME},
            },
        })
        state.addon.Refresh()
        state:toolbar().hide:Fire("OnClick")
        local menu = state:toolbar().hideMenu
        check(menu:IsShown(), "HIDE action must open its own option menu")
        menu.rows[2]:Fire("OnClick")
        check(state.settings.legendHideRenownLocked, "RENOWN control must persist its setting")
        check(not state.buttons[1]:IsVisible(), "unmet Silvermoon Court renown must hide the item")
        for index = 2, 5 do check(state.buttons[index]:IsVisible(), "known-satisfied or unknown rank must stay visible") end
        state.env.C_MajorFactions.GetMajorFactionData = function() return {name = "Silvermoon Court", renownLevel = 19} end
        state.addon.Refresh()
        check(state.buttons[1]:IsVisible(), "reaching the required rank must restore the reward")
        menu.rows[2]:Fire("OnClick")
        for _, button in ipairs(state.buttons) do check(button:IsVisible(), "turning RENOWN off must restore all items") end
    end
end)

test("renown filter leaves items visible when faction data is unavailable", function()
    local state = fixture({entries = {{id = 101, name = "Fiery Dragonhawk", tooltip = "Requires Renown Rank 19 with the Silvermoon Court."}}})
    state.addon.Refresh()
    state:toolbar().hide:Fire("OnClick")
    state:toolbar().hideMenu.rows[2]:Fire("OnClick")
    check(state.buttons[1]:IsVisible(), "missing faction API must fail open")
end)

test("HIDE menu combines Known and Renown without treating them as one filter", function()
    local state = fixture({
        factions = {{name = "Silvermoon Court", renownLevel = 10}},
        knownToyIDs = {[104] = true},
        entries = {
            {id = 101, name = "Learned Recipe", tooltip = "Already Known"},
            {id = 102, name = "Fiery Dragonhawk", tooltip = "Requires Renown Rank 19 with the Silvermoon Court."},
            {id = 103, name = "Other Reward", tooltip = "Requires Level 90"},
            {id = 104, name = "Collected Toy"},
            {id = 105, name = "Unreadable Reward", tooltip = SECRET_NAME},
        },
    })
    state.addon.Refresh()
    local toolbar = state:toolbar()
    check(toolbar.hide._waffleHideIcon.texture:find("eui%-visible%.png"), "open-eye icon must represent no active hide rules")
    near(toolbar.hide._waffleHideIcon:GetWidth(), 16, "eye asset padding needs a full-size visible mark")
    toolbar.hide:Fire("OnClick")
    local menu = toolbar.hideMenu
    check(menu:IsShown() and menu.clamped, "HIDE must open a screen-clamped anchored menu")
    for _, row in ipairs(menu.rows) do
        check(row:GetLeft() >= menu:GetLeft() + 10 and row:GetRight() <= menu:GetRight() - 10,
            "menu choice must keep its horizontal gutters")
        check(row:GetTop() <= menu:GetTop() - 34 and row:GetBottom() >= menu:GetBottom() + 11,
            "menu choice must stay inside its vertical padding")
    end
    menu.rows[1]:Fire("OnClick")
    check(state.settings.legendHideKnown and not state.settings.legendHideRenownLocked, "Known is independently configurable")
    check(not state.buttons[1]:IsVisible() and not state.buttons[4]:IsVisible(), "learned recipe and collected toy must hide")
    check(state.buttons[2]:IsVisible() and state.buttons[3]:IsVisible() and state.buttons[5]:IsVisible(),
        "renown lock, unrelated requirement, and secret tooltip stay visible")
    check(toolbar.hide._waffleHideIcon.texture:find("eui%-invisible%.png"), "closed-eye icon must represent active hiding")
    menu.rows[2]:Fire("OnClick")
    check(not state.buttons[2]:IsVisible(), "Renown choice must combine with Known")
    menu.rows[1]:Fire("OnClick")
    check(state.buttons[1]:IsVisible() and state.buttons[4]:IsVisible(), "disabling Known restores its own items")
    check(not state.buttons[2]:IsVisible(), "Renown choice must remain active")
    menu.rows[2]:Fire("OnClick")
    check(toolbar.hide._waffleHideIcon.texture:find("eui%-visible%.png"), "eye must reopen when no hide rule is active")
    toolbar.hide:Fire("OnClick")
    check(not menu:IsShown(), "clicking HIDE again must close its menu")
    toolbar.hide:Fire("OnClick")
    state.mouseDown = true
    menu:Fire("OnUpdate")
    check(not menu:IsShown(), "clicking outside must close the menu")
end)

test("currency-free vendors still reach list renderer and keep view toggle available", function()
    local state = fixture({noCosts = true})
    state.addon.Refresh()
    assertList(state)
    check(state:toolbar():IsShown() and state:toolbar().list:IsVisible(), "currency-free vendor must retain view controls")
end)

test("every modifier blocks purchases whether modified-item handling succeeds or fails", function()
    for _, view in ipairs({"grid", "list"}) do
        local state = fixture({view = view})
        state.addon.Refresh()
        local button = state.buttons[1]
        local guard = button:GetScript("OnClick")
        state.addon.Refresh()
        equal(button:GetScript("OnClick"), guard, "repeated refresh must not nest purchase wrappers")
        for _, modifier in ipairs({"ctrl", "shift", "alt", "generic"}) do
            for _, handled in ipairs({false, true}) do
                state.modifier, state.modifiedHandled = modifier, handled
                for _, mouseButton in ipairs({"LeftButton", "RightButton"}) do
                    button:Fire("OnMouseDown", mouseButton)
                    button:Fire("OnClick", mouseButton)
                    equal(state.purchases, nil, view .. " " .. modifier .. " must never buy")
                    equal(state.modifiedLink, button._link, "modified action must receive the safe item link")
                end
            end
        end
        equal(state.modifiedClicks, 16, "each modified click must offer its link action once")
        state.modifier = nil
        button:Fire("OnMouseDown", "RightButton")
        button:Fire("OnClick", "RightButton")
        equal(state.purchases, 1, "unmodified click must retain native purchase behavior")
    end
end)

test("modifier latch survives release before click and clears on hide", function()
    local state = fixture()
    state.frame._liveWindowWidth = true
    state.addon.Refresh()
    local button = state.buttons[1]
    check(button._wafflePurchaseGuard, "purchase safety must install even while list layout is deferred")
    state.modifier = "ctrl"
    button:Fire("OnMouseDown", "LeftButton")
    state.modifier = nil
    button:Fire("OnClick", "LeftButton")
    equal(state.purchases, nil, "releasing modifier before mouse-up must not buy")
    state.modifier = "shift"
    button:Fire("OnMouseDown", "LeftButton")
    button:Hide()
    button:Show()
    state.modifier = nil
    button:Fire("OnClick", "LeftButton")
    equal(state.purchases, 1, "pooled button hide must clear stale modifier latch")
end)

io.write(passed .. " vendor refresh tests passed; " .. #failures .. " failed\n")
if #failures > 0 then os.exit(1) end
