local PICKER = arg[1] or "WaffleHouse_VendorStack.lua"
local MAIN = arg[2] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(MAIN, "rb")); local main = file:read("*a"); file:close()
local first = assert(main:find("function addon.IsVendorPurchaseModifierDown()", 1, true))
local last = assert(main:find("local function FindVendorButtons", first, true))
local guardSource = main:sub(first, last - 1)
local function fixture()
    local s = { frames = {}, timers = {}, bought = {}, confirmed = {}, notices = {}, money = 100000, maximum = 200,
        link = "item:123", itemTokens = 13, costs = {}, modifiers = {}, modifiedClicks = 0, nativeClicks = 0,
        info = { name = "Vendor item", texture = 123, price = 100, stackCount = 1, hasExtendedCost = false, isPurchasable = true } }
    local function frame()
        local f = { scripts = {}, hooks = {}, events = {}, shown = true }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:GetScript(k) return self.scripts[k] end
        function f:HookScript(k, fn) self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn) end
        function f:Fire(k, ...)
            if self.scripts[k] then self.scripts[k](self, ...) end
            for _, fn in ipairs(self.hooks[k] or {}) do fn(self, ...) end
        end
        function f:Hide() self.shown = false; self:Fire("OnHide") end
        function f:Show() self.shown = true end
        function f:SetID(id) self.id = id end
        function f:GetID() return self.id end
        function f:ClearAllPoints() self.target = nil end
        function f:SetAllPoints(target) self.target = target end
        function f:EnableMouse(value) self.mouse = value end
        function f:RegisterForClicks() end
        function f:RegisterForDrag() end
        s.frames[#s.frames + 1] = f
        return f
    end
    local env = setmetatable({
        CreateFrame = frame, UIParent = {}, MAX_ITEM_COST = 3,
        C_Timer = { After = function(_, fn) s.timers[#s.timers + 1] = fn end },
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
        C_Item = { GetItemCount = function() return s.itemTokens end },
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
                count = owner.count, price = owner.price, extended = owner.extendedCost, nonrefundable = owner.showNonrefundablePrompt }
        end,
    }, { __index = _G })
    -- Exact native SplitStack dispatch installed by MerchantItemButton_OnLoad.
    env.MerchantItemButton_OnLoad = function(owner)
        owner.SplitStack = function(button, quantity)
            if button.extendedCost or button.showNonrefundablePrompt then
                env.MerchantFrame_ConfirmExtendedItemCost(button, quantity)
            elseif quantity > 0 then env.BuyMerchantItem(button:GetID(), quantity) end
        end
    end
    local popup = frame()
    function popup:OpenStackSplitFrame(maximum, owner, a, b, step)
        assert(a == "BOTTOMLEFT" and b == "TOPLEFT", "native positioning contract")
        self.owner, self.maximum, self.step, self.shown = owner, maximum, step, true
        s.opens = (s.opens or 0) + 1
    end
    env.StackSplitFrame = popup
    s.addon = {}; env.addon = s.addon
    assert(loadfile(PICKER, "t", env))("WaffleHouse_EllesmereUI", s.addon)
    assert(load(guardSource, "@actual-purchase-guard", "t", env))()
    s.button = frame(); s.button._merchantIndex = 7; s.button._link = s.link
    s.button:SetScript("OnClick", function() s.nativeClicks = s.nativeClicks + 1 end)
    s.addon.GuardVendorPurchase(s.button)
    s.env, s.popup = env, popup
    function s:open()
        self.modifiers.shift = true
        self.button:Fire("OnMouseDown", "RightButton")
        self.button:Fire("OnClick", "RightButton")
    end
    function s:confirm(quantity)
        self.popup:Hide() -- Native OK hides first, then invokes owner.SplitStack.
        self.popup.owner:SplitStack(quantity)
    end
    function s:event(event)
        for _, f in ipairs(self.frames) do if f.events[event] then f:Fire("OnEvent", event) end end
    end
    function s:flush()
        local ready = self.timers; self.timers = {}
        for _, fn in ipairs(ready) do fn() end
    end
    return s
end

local s = fixture(); s:open()
assert(s.opens == 1 and s.nativeClicks == 0 and s.modifiedClicks == 0 and #s.bought == 0,
    "Shift-right-click must open the quantity picker without buying or linking")
assert(s.popup.maximum == 200 and s.popup.step == 1 and s.popup.owner.target == s.button, "picker must use the native cap and clicked row")
s:confirm(200)
assert(#s.bought == 1 and s.bought[1][1] == 7 and s.bought[1][2] == 200, "explicit confirmation may buy one full stack")
s.popup.owner:SplitStack(200)
assert(#s.bought == 1, "a consumed context must not buy twice")

s = fixture(); s:open(); s:confirm(12)
assert(s.bought[1][2] == 12, "smaller selected amounts must be preserved")
s = fixture(); s.info.stackCount = 5; s.money = 760; s:open()
assert(s.popup.maximum == 35 and s.popup.step == 5, "bundle pricing and affordability must round to purchasable bundles")
s:confirm(30); assert(s.bought[1][2] == 30, "the purchase API must receive item units, not bundle count")
s = fixture(); s.info.stackCount = 5; s.info.hasExtendedCost = true; s.info.price = 0
s.costs = { { amount = 3, link = "item:token" } }; s:open()
assert(s.popup.maximum == 20, "item token costs must cap the picker")
s:confirm(20)
assert(#s.bought == 0 and #s.confirmed == 1 and s.confirmed[1].count == 5 and s.confirmed[1].price == nil,
    "extended costs must retain Blizzard's confirmation path and bundle fields")
s = fixture(); s.nonrefundable = true; s:open(); s:confirm(5)
assert(#s.bought == 0 and s.confirmed[1].nonrefundable, "nonrefundable confirmations must be preserved")
s = fixture(); s.link = nil; s.info.name = "Currency exchange"; s:open()
assert(s.opens == 1, "native non-item offers must remain supported")

for _, quantity in ipairs({ 0, -1, 2.5, 201, math.huge }) do
    s = fixture(); s:open(); s:confirm(quantity)
    assert(#s.bought == 0 and #s.confirmed == 0, "invalid quantities must not purchase")
end
s = fixture(); s.money = 0; s:open()
assert(not s.opens and #s.bought == 0, "unaffordable opening must never purchase")
s = fixture(); s:open(); s.money = 100; s:confirm(200)
assert(#s.bought == 0, "affordability must be rechecked on confirmation")
for _, mutate in ipairs({
    function(x) x.button._merchantIndex = 8 end,
    function(x) x.link = "item:456" end,
    function(x) x.info.price = 200 end,
    function(x) x:event("MERCHANT_CLOSED") end,
    function(x) x:event("MERCHANT_UPDATE") end,
    function(x) x.button:Hide() end,
}) do
    s = fixture(); s:open(); mutate(s); s:confirm(5)
    assert(#s.bought == 0 and #s.confirmed == 0, "stale/recycled/closed merchant offers must not purchase")
end
s = fixture(); s:open(); s.popup:Hide()
assert(#s.bought == 0 and not s.popup.owner.shown, "cancel must never buy or leave a visible proxy")
s:flush(); s.popup.owner:SplitStack(5)
assert(#s.bought == 0, "cancel must discard the stale purchase context")
s = fixture(); s:open(); s.popup:Hide(); s:open(); s:flush(); s:confirm(10)
assert(#s.bought == 1 and s.bought[1][2] == 10, "deferred cancel cleanup must not erase a new picker")
s = fixture(); s:open(); s.popup:Hide()
s:event("MERCHANT_SHOW"); s.popup.owner:SplitStack(5)
assert(#s.bought == 0, "new merchant sessions must invalidate old confirmation callbacks")

s = fixture(); s.modifiers.shift = true; s.button:Fire("OnMouseDown", "RightButton")
s.modifiers.shift = false; s.button:Fire("OnClick", "RightButton")
assert(s.opens == 1 and s.nativeClicks == 0, "Shift latch must survive release before mouse-up")
for _, case in ipairs({ { "shift", "LeftButton" }, { "ctrl", "RightButton" }, { "alt", "RightButton" } }) do
    s = fixture(); s.modifiers[case[1]] = true
    s.button:Fire("OnMouseDown", case[2]); s.button:Fire("OnClick", case[2])
    assert(not s.opens and s.modifiedClicks == 1 and s.nativeClicks == 0, "other modifiers must preserve preview/link safety")
end
s = fixture(); s.modifiers.shift = true; s.modifiers.ctrl = true
s.button:Fire("OnMouseDown", "RightButton"); s.button:Fire("OnClick", "RightButton")
assert(not s.opens and s.modifiedClicks == 1, "Ctrl+Shift must preserve modified item actions")
s = fixture(); s.button._isBuyback = true; s:open()
assert(not s.opens and s.modifiedClicks == 1 and s.nativeClicks == 0, "buyback entries must not become stack purchases")
s = fixture(); s.button:Fire("OnClick", "RightButton")
assert(s.nativeClicks == 1 and not s.opens, "ordinary right click must retain the original handler")
print("vendor_stack_picker_test: ok")
