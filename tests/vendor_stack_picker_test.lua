local PICKER = arg[1] or "WaffleHouse_VendorStack.lua"
local MAIN = arg[2] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(MAIN, "rb")); local main = file:read("*a"); file:close()
local first = assert(main:find("function addon.IsVendorPurchaseModifierDown()", 1, true))
local last = assert(main:find("local function FindVendorButtons", first, true))
local guardSource = main:sub(first, last - 1)

local function fixture()
    local s = { frames = {}, bought = {}, confirmed = {}, notices = {}, money = 100000000,
        maximum = 200, stackSize = 20, link = "item:123", itemTokens = 13, costs = {},
        modifiers = {}, modifiedClicks = 0, nativeClicks = 0,
        info = { name = "Vendor item", texture = 123, price = 100, stackCount = 1,
            hasExtendedCost = false, isPurchasable = true } }
    local function object()
        local f = { scripts = {}, hooks = {}, events = {}, shown = true, text = "" }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:GetScript(k) return self.scripts[k] end
        function f:HookScript(k, fn)
            self.hooks[k] = self.hooks[k] or {}
            table.insert(self.hooks[k], fn)
        end
        function f:Fire(k, ...)
            if self.scripts[k] then self.scripts[k](self, ...) end
            for _, fn in ipairs(self.hooks[k] or {}) do fn(self, ...) end
        end
        function f:Hide() self.shown = false; self:Fire("OnHide") end
        function f:Show() self.shown = true end
        function f:IsShown() return self.shown end
        function f:SetID(id) self.id = id end
        function f:GetID() return self.id end
        function f:SetText(value) self.text = value; self:Fire("OnTextChanged") end
        function f:GetText() return self.text end
        function f:SetEnabled(value) self.enabled = value end
        function f:SetPoint() end
        function f:SetSize() end
        function f:SetHeight() end
        function f:SetWidth() end
        function f:SetBackdrop() end
        function f:SetBackdropColor() end
        function f:SetBackdropBorderColor() end
        function f:SetFrameStrata() end
        function f:EnableMouse() end
        function f:SetColorTexture() end
        function f:SetFont() end
        function f:SetJustifyH() end
        function f:SetTextColor() end
        function f:SetWordWrap() end
        function f:SetTextInsets() end
        function f:SetNumeric() end
        function f:SetMaxLetters() end
        function f:SetAutoFocus() end
        function f:HighlightText() end
        function f:ClearFocus() end
        function f:SetAlpha() end
        function f:RegisterForClicks() end
        function f:RegisterForDrag() end
        function f:CreateFontString() return object() end
        function f:CreateTexture() return object() end
        s.frames[#s.frames + 1] = f
        return f
    end
    local env = setmetatable({
        CreateFrame = function(_, name)
            local f = object()
            if name == "WaffleHouseVendorQuantityPicker" then s.picker = f end
            return f
        end,
        UIParent = {}, MAX_ITEM_COST = 3, MERCHANT_HIGH_PRICE_COST = 1500000,
        C_MerchantFrame = {
            GetItemInfo = function() return s.info end,
            IsMerchantItemRefundable = function() return not s.nonrefundable end,
        },
        GetMerchantItemLink = function() return s.link end,
        GetMerchantItemMaxStack = function() return s.maximum end,
        GetMoney = function() return s.money end,
        GetMerchantItemCostItem = function(_, index)
            local cost = s.costs[index]
            if cost then return 1, cost.amount, cost.link, cost.currency end
        end,
        C_Item = {
            GetItemCount = function() return s.itemTokens end,
            GetItemMaxStackSizeByID = function() return s.stackSize end,
        },
        IsShiftKeyDown = function() return s.modifiers.shift == true end,
        IsControlKeyDown = function() return s.modifiers.ctrl == true end,
        IsAltKeyDown = function() return s.modifiers.alt == true end,
        IsSafeText = function(v) return type(v) == "string" and v ~= "" end,
        HandleModifiedItemClick = function() s.modifiedClicks = s.modifiedClicks + 1; return s.handled end,
        UIErrorsFrame = { AddMessage = function(_, message) s.notices[#s.notices + 1] = message end },
        GameTooltip = { Hide = function() end },
        BuyMerchantItem = function(index, quantity) s.bought[#s.bought + 1] = { index, quantity } end,
        MerchantFrame_ConfirmExtendedItemCost = function(owner, quantity)
            s.confirmed[#s.confirmed + 1] = { index = owner:GetID(), quantity = quantity,
                count = owner.count, price = owner.price, extended = owner.extendedCost,
                nonrefundable = owner.showNonrefundablePrompt }
        end,
        MerchantFrame_ConfirmHighCostItem = function(owner, quantity)
            s.confirmed[#s.confirmed + 1] = { index = owner:GetID(), quantity = quantity, highPrice = true }
        end,
    }, { __index = _G })
    env.MerchantItemButton_OnLoad = function(owner)
        owner.SplitStack = function(button, quantity)
            if button.extendedCost or button.showNonrefundablePrompt then
                env.MerchantFrame_ConfirmExtendedItemCost(button, quantity)
            else env.BuyMerchantItem(button:GetID(), quantity) end
        end
    end
    s.addon = {}
    env.addon = s.addon
    assert(loadfile(PICKER, "t", env))("WaffleHouse_EllesmereUI", s.addon)
    assert(load(guardSource, "@actual-purchase-guard", "t", env))()
    s.button = object(); s.button._merchantIndex = 7; s.button._link = s.link
    s.button:SetScript("OnClick", function() s.nativeClicks = s.nativeClicks + 1 end)
    s.addon.GuardVendorPurchase(s.button)
    function s:open()
        self.modifiers.shift = true
        self.button:Fire("OnMouseDown", "RightButton")
        self.button:Fire("OnClick", "RightButton")
    end
    function s:choose(label)
        for _, f in ipairs(self.frames) do
            if f.label and f.label:GetText() == label then f:Fire("OnClick"); return end
        end
        error("missing picker action: " .. label)
    end
    function s:confirm(quantity)
        if quantity ~= nil then self.picker.quantity:SetText(tostring(quantity)) end
        self.picker.buy:Fire("OnClick")
    end
    function s:event(event)
        for _, f in ipairs(self.frames) do if f.events[event] then f:Fire("OnEvent", event) end end
    end
    return s
end

local s = fixture(); s:open()
assert(s.picker and s.picker:IsShown() and s.nativeClicks == 0 and #s.bought == 0,
    "Shift-right-click must open the custom picker without purchasing")
assert(s.picker.item:GetText() == "Vendor item" and s.picker.info:GetText():find("Up to 4000", 1, true),
    "picker must identify the offer and safe cap")
s:choose("+10"); assert(s.picker.quantity:GetText() == "11", "+10 must add to quantity")
s:choose("+20"); assert(s.picker.quantity:GetText() == "31", "+20 must add to quantity")
s:choose("+50"); assert(s.picker.quantity:GetText() == "81", "+50 must add to quantity")
s:choose("+100"); assert(s.picker.quantity:GetText() == "181", "+100 must add to quantity")
s:choose("1 STACK: 20"); assert(s.picker.quantity:GetText() == "20", "stack preset must use actual stack size")
s:choose("5 STACKS: 100"); assert(s.picker.quantity:GetText() == "100", "five-stack preset must be available")
s:choose("MAX"); assert(s.picker.quantity:GetText() == "4000", "max preset must honor purchase cap")
s:confirm(450)
assert(#s.bought == 3 and s.bought[1][2] == 200 and s.bought[2][2] == 200 and s.bought[3][2] == 50,
    "gold-only multiple stacks must be purchased in bounded chunks after explicit Buy")
s:confirm(5); assert(#s.bought == 3, "closed picker must never buy twice")

s = fixture(); s.info.stackCount = 5; s.info.price = 100; s.money = 760; s:open()
assert(s.picker.info:GetText():find("Up to 35", 1, true), "bundle affordability must round down")
s:choose("+10"); assert(s.picker.quantity:GetText() == "15", "add buttons use item units")
s:confirm(16); assert(#s.bought == 0 and not s.picker.buy.enabled, "manual values must respect bundle multiples")
s:confirm(30); assert(#s.bought == 1 and s.bought[1][2] == 30, "valid bundle quantity must purchase")
s = fixture(); s.info.stackCount = 5; s.info.hasExtendedCost = true; s.info.price = 0
s.costs = { { amount = 3, link = "item:token" } }; s:open()
assert(s.picker.info:GetText():find("Up to 20", 1, true), "item tokens must cap quantity")
s:confirm(20)
assert(#s.bought == 0 and #s.confirmed == 1 and s.confirmed[1].count == 5 and s.confirmed[1].price == nil,
    "extended costs must retain Blizzard confirmation")
s = fixture(); s.nonrefundable = true; s:open(); s:confirm(5)
assert(#s.bought == 0 and s.confirmed[1].nonrefundable, "nonrefundable items must retain confirmation")
s = fixture(); s.info.price = 1500000; s:open(); s:confirm(5)
assert(#s.bought == 0 and s.confirmed[1].highPrice, "high-price offers must retain confirmation")
s = fixture(); s.link = nil; s.info.name = "Currency exchange"; s:open()
assert(s.picker:IsShown(), "non-item merchant offers must remain supported")
s = fixture(); s.info.numAvailable = 7; s:open()
assert(s.picker.info:GetText():find("Up to 7", 1, true), "finite vendor stock must cap the picker")
s:choose("+100"); assert(s.picker.quantity:GetText() == "7", "quick add must clamp to remaining stock")
s = fixture(); s.money = 0; s:open()
assert(not s.picker and #s.bought == 0, "unaffordable offer must not open")
s = fixture(); s:open(); s.money = 100; s:confirm(200)
assert(#s.bought == 0, "affordability must be rechecked on Buy")
for _, mutate in ipairs({
    function(x) x.button._merchantIndex = 8 end,
    function(x) x.link = "item:456" end,
    function(x) x.info.price = 200 end,
    function(x) x:event("MERCHANT_CLOSED") end,
    function(x) x:event("MERCHANT_UPDATE") end,
    function(x) x.button:Hide() end,
}) do
    s = fixture(); s:open(); mutate(s); s:confirm(5)
    assert(#s.bought == 0 and #s.confirmed == 0, "stale or closed offers must not purchase")
end
s = fixture(); s:open(); s:choose("X")
assert(#s.bought == 0 and not s.picker:IsShown(), "close must cancel without purchasing")
s = fixture(); s:open(); s:event("MERCHANT_SHOW"); s:confirm(5)
assert(#s.bought == 0, "new merchant session must invalidate old picker")

s = fixture(); s.modifiers.shift = true; s.button:Fire("OnMouseDown", "RightButton")
s.modifiers.shift = false; s.button:Fire("OnClick", "RightButton")
assert(s.picker and s.picker:IsShown(), "Shift latch must survive release before mouse-up")
for _, case in ipairs({ { "shift", "LeftButton" }, { "ctrl", "RightButton" }, { "alt", "RightButton" } }) do
    s = fixture(); s.modifiers[case[1]] = true
    s.button:Fire("OnMouseDown", case[2]); s.button:Fire("OnClick", case[2])
    assert(not s.picker and s.modifiedClicks == 1 and s.nativeClicks == 0,
        "other modifiers must preserve preview and link safety")
end
s = fixture(); s.modifiers.shift = true; s.modifiers.ctrl = true
s.button:Fire("OnMouseDown", "RightButton"); s.button:Fire("OnClick", "RightButton")
assert(not s.picker and s.modifiedClicks == 1, "Ctrl+Shift must preserve modified actions")
s = fixture(); s.button._isBuyback = true; s:open()
assert(not s.picker and s.modifiedClicks == 1, "buyback entries must not open quantity picker")
s = fixture(); s.button:Fire("OnClick", "RightButton")
assert(s.nativeClicks == 1 and not s.picker, "ordinary right click retains original handler")
print("vendor_stack_picker_test: ok")
