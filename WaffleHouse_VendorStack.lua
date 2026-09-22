local _, addon = ...
if type(addon) ~= "table" then return end

local owner, active, merchantSession
merchantSession = 0

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function Notice(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(message, 1, 0.75, 0.2)
    else print("Waffle House: " .. message) end
end

local function ReadOffer(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    local link = GetMerchantItemLink(index)
    if not Public(info) or type(info) ~= "table" or not Number(info.stackCount) or info.stackCount < 1
        or not Number(info.price) or info.price < 0 or not Public(link) or (link ~= nil and type(link) ~= "string")
        or not Public(info.name) or type(info.name) ~= "string" or not Public(info.hasExtendedCost)
        or not Public(info.isPurchasable) or info.isPurchasable == false then return end
    return info, link
end

local function Maximum(index, info)
    -- Follow Blizzard's merchant split calculation. Price/costs are per
    -- merchant bundle; the native picker and BuyMerchantItem use item units.
    local maximum = GetMerchantItemMaxStack(index)
    if not Number(maximum) or maximum < 1 then return 0 end
    if info.price > 0 then
        local money = GetMoney()
        if not Number(money) then return 0 end
        maximum = math.min(maximum, math.floor(money / (info.price / info.stackCount)))
    end
    if info.hasExtendedCost then
        for costIndex = 1, (MAX_ITEM_COST or 3) do
            local _, amount, link, currencyName = GetMerchantItemCostItem(index, costIndex)
            if link and not currencyName then
                local count = C_Item.GetItemCount(link, false, false, true)
                if not Number(amount) or amount <= 0 or not Number(count) then return 0 end
                maximum = math.min(maximum, math.floor(count / (amount / info.stackCount)))
            end
        end
    end
    -- A fractional bundle cannot be bought; also avoids the native right
    -- arrow stepping past a cap which is not divisible by its increment.
    return math.max(0, math.floor(maximum / info.stackCount) * info.stackCount)
end

local function ConfigureOwner(info, link, index)
    owner:SetID(index)
    owner.price = info.price
    if info.hasExtendedCost and info.price == 0 then owner.price = nil end
    owner.extendedCost = info.hasExtendedCost and true or nil
    owner.name, owner.link, owner.texture, owner.count = info.name, link, info.texture, info.stackCount
    owner.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
end

function addon.CloseVendorStackPicker(button)
    if not active or (button and active.button ~= button) then return end
    active = nil
    if StackSplitFrame and StackSplitFrame.owner == owner then StackSplitFrame:Hide() end
    if owner then owner:Hide() end
end

function addon.OpenVendorStackPicker(button)
    if not button or button._isBuyback or not Number(button._merchantIndex) then return false end
    addon.CloseVendorStackPicker()
    if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.IsMerchantItemRefundable
        and GetMerchantItemLink and GetMerchantItemMaxStack and GetMoney and GetMerchantItemCostItem
        and C_Item and C_Item.GetItemCount and MerchantItemButton_OnLoad
        and StackSplitFrame and StackSplitFrame.OpenStackSplitFrame) then
        Notice("The merchant quantity picker is unavailable. Nothing was bought.")
        return false
    end
    local index = button._merchantIndex
    local info, link = ReadOffer(index)
    if not info then Notice("This vendor item is unavailable. Nothing was bought."); return false end
    local maximum = Maximum(index, info)
    if maximum < info.stackCount then Notice("You cannot afford a purchase of this item."); return false end
    if not owner then
        owner = CreateFrame("Button", nil, UIParent)
        owner:EnableMouse(false)
        MerchantItemButton_OnLoad(owner)
        StackSplitFrame:HookScript("OnHide", function(self)
            if self.owner ~= owner or not active then return end
            local closing = active
            owner:Hide()
            -- Native OK hides the frame BEFORE invoking owner.SplitStack.
            -- Let that synchronous callback consume the context; cancel and
            -- Escape clear it next tick without disturbing a newly opened picker.
            C_Timer.After(0, function()
                if active == closing then active = nil end
            end)
        end)
        local nativeSplit = owner.SplitStack
        owner.SplitStack = function(self, quantity)
            local context = active
            addon.CloseVendorStackPicker()
            if not context or context.session ~= merchantSession or context.button._isBuyback
                or context.button._merchantIndex ~= context.index or not Number(quantity) or quantity <= 0 then return end
            local current, currentLink = ReadOffer(context.index)
            if not current or currentLink ~= context.link or current.name ~= context.name or current.price ~= context.price
                or current.stackCount ~= context.bundle or current.hasExtendedCost ~= context.extended then
                Notice("The vendor item changed. Open the quantity picker again.")
                return
            end
            if quantity % current.stackCount ~= 0 or quantity > Maximum(context.index, current) then
                Notice("That amount is no longer available or affordable. Open the quantity picker again.")
                return
            end
            ConfigureOwner(current, currentLink, context.index)
            -- Keep Blizzard's extended-cost/nonrefundable confirmation flow.
            -- No purchase occurs while opening or adjusting the picker.
            nativeSplit(self, quantity)
        end
    end
    ConfigureOwner(info, link, index)
    owner:ClearAllPoints()
    owner:SetAllPoints(button)
    owner:Show()
    active = { button = button, index = index, link = link, name = info.name, price = info.price,
        bundle = info.stackCount, extended = info.hasExtendedCost, session = merchantSession }
    if GameTooltip then GameTooltip:Hide() end
    StackSplitFrame:OpenStackSplitFrame(maximum, owner, "BOTTOMLEFT", "TOPLEFT", info.stackCount)
    return true
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function()
    merchantSession = merchantSession + 1
    addon.CloseVendorStackPicker()
end)
