local _, addon = ...
if type(addon) ~= "table" then return end

local owner, picker, active
local merchantSession = 0
local MAX_PURCHASE_CALLS = 20
local MAX_ITEMS = 10000

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
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

local function Limits(index, info)
    local perCall = GetMerchantItemMaxStack(index)
    if not Number(perCall) or perCall < info.stackCount then return 0, 0, false end
    perCall = math.floor(perCall / info.stackCount) * info.stackCount
    local refundable = C_MerchantFrame.IsMerchantItemRefundable(index)
    if not Public(refundable) then return 0, perCall, false end
    local highPrice = info.price >= (MERCHANT_HIGH_PRICE_COST or 1500000)
    local multi = not info.hasExtendedCost and refundable and not highPrice
    local limit = math.min(MAX_ITEMS, perCall * (multi and MAX_PURCHASE_CALLS or 1))
    if Number(info.numAvailable) and info.numAvailable >= 0 then
        limit = math.min(limit, info.numAvailable * info.stackCount)
    end
    if info.price > 0 then
        local money = GetMoney()
        if not Number(money) then return 0, perCall, multi end
        limit = math.min(limit, math.floor(money / info.price) * info.stackCount)
    end
    if info.hasExtendedCost then
        for costIndex = 1, (MAX_ITEM_COST or 3) do
            local _, amount, link, currencyName = GetMerchantItemCostItem(index, costIndex)
            if link and not currencyName then
                local count = C_Item.GetItemCount(link, false, false, true)
                if not Number(amount) or amount <= 0 or not Number(count) then return 0, perCall, multi end
                limit = math.min(limit, math.floor(count / amount) * info.stackCount)
            end
        end
    end
    return math.max(0, math.floor(limit / info.stackCount) * info.stackCount), perCall, multi
end

local function ConfigureOwner(info, link, index)
    owner:SetID(index)
    owner.price = info.price
    if info.hasExtendedCost and info.price == 0 then owner.price = nil end
    owner.extendedCost = info.hasExtendedCost and true or nil
    owner.name, owner.link, owner.texture, owner.count = info.name, link, info.texture, info.stackCount
    owner.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
end

local function Font(parent, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    label:SetJustifyH("LEFT")
    label:SetTextColor(color[1], color[2], color[3])
    return label
end

local function Button(parent, text, x, y, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button:SetBackdropColor(0.10, 0.13, 0.16, 0.96)
    button:SetBackdropBorderColor(0.26, 0.31, 0.34, 1)
    local label = Font(button, 12, { 0.90, 0.93, 0.94 })
    label:SetPoint("CENTER")
    label:SetText(text)
    button.label = label
    button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.06, 0.82, 0.62, 1) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.26, 0.31, 0.34, 1) end)
    button:SetScript("OnClick", onClick)
    return button
end

local function ItemStackSize(link, bundle)
    if link and C_Item.GetItemMaxStackSizeByID then
        local id = link:match("item:(%d+)")
        if id then
            local size = C_Item.GetItemMaxStackSizeByID(tonumber(id))
            if Number(size) and size >= bundle then return math.floor(size / bundle) * bundle end
        end
    end
    return bundle
end

local function ValidQuantity(quantity, context)
    return Number(quantity) and quantity >= context.bundle and quantity <= context.limit
        and quantity % 1 == 0 and quantity % context.bundle == 0
end

local function Render()
    if not picker or not active then return end
    local quantity = tonumber(picker.quantity:GetText())
    local valid = ValidQuantity(quantity, active)
    picker.buy:SetEnabled(valid)
    picker.buy:SetAlpha(valid and 1 or 0.45)
    if not valid then
        picker.summary:SetText(string.format("Enter a multiple of %d, up to %d items.", active.bundle, active.limit))
        picker.summary:SetTextColor(1, 0.55, 0.38)
    elseif active.price > 0 then
        local total = quantity / active.bundle * active.price
        local cost = GetCoinTextureString and GetCoinTextureString(total) or tostring(total) .. " copper"
        picker.summary:SetText(string.format("%d items  ·  %s", quantity, cost))
        picker.summary:SetTextColor(0.77, 0.84, 0.86)
    elseif active.extended then
        picker.summary:SetText(string.format("%d items  ·  Blizzard confirms token costs when needed", quantity))
        picker.summary:SetTextColor(0.77, 0.84, 0.86)
    else
        picker.summary:SetText(string.format("%d items  ·  No gold price reported; check the vendor tooltip", quantity))
        picker.summary:SetTextColor(0.77, 0.84, 0.86)
    end
end

local function SetQuantity(quantity)
    if not active or not picker or not Number(quantity) then return end
    local rounded = math.ceil(quantity / active.bundle) * active.bundle
    rounded = math.max(active.bundle, math.min(active.limit, rounded))
    picker.quantity:SetText(tostring(rounded))
    picker.quantity:HighlightText()
    Render()
end

function addon.CloseVendorStackPicker(button)
    if not active or (button and active.button ~= button) then return end
    active = nil
    if picker then picker:Hide() end
    if owner then owner:Hide() end
end

local function ConfirmPurchase()
    local context = active
    if not context then return end
    local quantity = tonumber(picker.quantity:GetText())
    if not ValidQuantity(quantity, context) then Notice("Enter a valid purchase amount."); return end
    addon.CloseVendorStackPicker()
    if context.session ~= merchantSession or context.button._isBuyback
        or context.button._merchantIndex ~= context.index
        or (context.button.IsShown and not context.button:IsShown()) then return end
    local current, currentLink = ReadOffer(context.index)
    if not current or currentLink ~= context.link or current.name ~= context.name
        or current.price ~= context.price or current.stackCount ~= context.bundle
        or current.hasExtendedCost ~= context.extended then
        Notice("The vendor item changed. Open the quantity picker again.")
        return
    end
    local limit, perCall, multi = Limits(context.index, current)
    if quantity > limit or (quantity > perCall and not multi) then
        Notice("That amount is no longer available or affordable. Open the quantity picker again.")
        return
    end
    ConfigureOwner(current, currentLink, context.index)
    if current.price >= (MERCHANT_HIGH_PRICE_COST or 1500000) and not current.hasExtendedCost then
        if MerchantFrame_ConfirmHighCostItem then
            MerchantFrame_ConfirmHighCostItem(owner, quantity)
        else
            Notice("Blizzard's high-price confirmation is unavailable. Nothing was bought.")
        end
        return
    end
    local remaining = quantity
    while remaining > 0 do
        local chunk = math.min(remaining, perCall)
        owner.SplitStack(owner, chunk)
        remaining = remaining - chunk
    end
end

local function CreatePicker()
    if picker then return end
    picker = CreateFrame("Frame", "WaffleHouseVendorQuantityPicker", UIParent, "BackdropTemplate")
    picker:SetSize(434, 310)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    picker:SetFrameStrata("DIALOG")
    picker:EnableMouse(true)
    picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    picker:SetBackdropColor(0.045, 0.055, 0.065, 0.98)
    picker:SetBackdropBorderColor(0.27, 0.32, 0.35, 1)
    local rule = picker:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.05, 0.82, 0.62, 1)
    rule:SetPoint("TOPLEFT", 1, -1)
    rule:SetPoint("TOPRIGHT", -1, -1)
    rule:SetHeight(2)
    picker.title = Font(picker, 13, { 0.05, 0.82, 0.62 })
    picker.title:SetPoint("TOPLEFT", 18, -18)
    picker.title:SetText("BUY MULTIPLE")
    Button(picker, "X", 392, -12, 26, 26, function() addon.CloseVendorStackPicker() end)
    picker.item = Font(picker, 15, { 1, 1, 1 })
    picker.item:SetPoint("TOPLEFT", 18, -48)
    picker.item:SetPoint("TOPRIGHT", -18, -48)
    picker.item:SetWordWrap(false)
    picker.info = Font(picker, 11, { 0.62, 0.68, 0.71 })
    picker.info:SetPoint("TOPLEFT", 18, -76)
    picker.info:SetPoint("TOPRIGHT", -18, -76)
    local amountLabel = Font(picker, 11, { 0.68, 0.74, 0.77 })
    amountLabel:SetPoint("TOPLEFT", 18, -103)
    amountLabel:SetText("QUANTITY")
    picker.quantity = CreateFrame("EditBox", nil, picker, "BackdropTemplate")
    picker.quantity:SetSize(180, 34)
    picker.quantity:SetPoint("TOPLEFT", 18, -120)
    picker.quantity:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    picker.quantity:SetBackdropColor(0.08, 0.10, 0.12, 1)
    picker.quantity:SetBackdropBorderColor(0.31, 0.38, 0.40, 1)
    picker.quantity:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 19, "")
    picker.quantity:SetTextInsets(10, 8, 0, 0)
    picker.quantity:SetNumeric(true)
    picker.quantity:SetMaxLetters(6)
    picker.quantity:SetAutoFocus(false)
    picker.quantity:SetScript("OnTextChanged", Render)
    picker.quantity:SetScript("OnEnterPressed", ConfirmPurchase)
    picker.quantity:SetScript("OnEscapePressed", function() addon.CloseVendorStackPicker() end)
    Button(picker, "-", 208, -120, 40, 34, function()
        SetQuantity((tonumber(picker.quantity:GetText()) or active.bundle) - active.bundle)
    end)
    Button(picker, "+", 256, -120, 40, 34, function()
        SetQuantity((tonumber(picker.quantity:GetText()) or 0) + active.bundle)
    end)
    Button(picker, "MAX", 304, -120, 112, 34, function() SetQuantity(active.limit) end)
    local stackLabel = Font(picker, 11, { 0.68, 0.74, 0.77 })
    stackLabel:SetPoint("TOPLEFT", 18, -166)
    stackLabel:SetText("QUICK SET")
    picker.oneStack = Button(picker, "1 STACK", 18, -182, 126, 30, function() SetQuantity(active.stackSize) end)
    picker.fiveStacks = Button(picker, "5 STACKS", 152, -182, 126, 30, function() SetQuantity(active.stackSize * 5) end)
    Button(picker, "1 BUNDLE", 286, -182, 130, 30, function() SetQuantity(active.bundle) end)
    local addLabel = Font(picker, 11, { 0.68, 0.74, 0.77 })
    addLabel:SetPoint("TOPLEFT", 18, -220)
    addLabel:SetText("ADD TO QUANTITY")
    for i, delta in ipairs({ 10, 20, 50, 100 }) do
        Button(picker, "+" .. delta, 18 + (i - 1) * 100, -236, 92, 30, function()
            SetQuantity((tonumber(picker.quantity:GetText()) or 0) + delta)
        end)
    end
    picker.summary = Font(picker, 11, { 0.77, 0.84, 0.86 })
    picker.summary:SetPoint("TOPLEFT", 18, -274)
    picker.summary:SetPoint("TOPRIGHT", -130, -274)
    picker.summary:SetWordWrap(false)
    picker.buy = Button(picker, "BUY", 324, -271, 92, 28, ConfirmPurchase)
    picker:Hide()
end

function addon.OpenVendorStackPicker(button)
    if not button or button._isBuyback or not Number(button._merchantIndex) then return false end
    addon.CloseVendorStackPicker()
    if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.IsMerchantItemRefundable
        and GetMerchantItemLink and GetMerchantItemMaxStack and GetMoney and GetMerchantItemCostItem
        and C_Item and C_Item.GetItemCount and MerchantItemButton_OnLoad and UIParent) then
        Notice("The merchant quantity picker is unavailable. Nothing was bought.")
        return false
    end
    local index = button._merchantIndex
    local info, link = ReadOffer(index)
    if not info then Notice("This vendor item is unavailable. Nothing was bought."); return false end
    local limit, perCall, multi = Limits(index, info)
    if limit < info.stackCount then Notice("You cannot afford a purchase of this item."); return false end
    if not owner then
        owner = CreateFrame("Button", nil, UIParent)
        owner:EnableMouse(false)
        MerchantItemButton_OnLoad(owner)
    end
    CreatePicker()
    ConfigureOwner(info, link, index)
    active = { button = button, index = index, link = link, name = info.name, price = info.price,
        bundle = info.stackCount, extended = info.hasExtendedCost, session = merchantSession,
        limit = limit, perCall = perCall, multi = multi, stackSize = ItemStackSize(link, info.stackCount) }
    picker.item:SetText(info.name)
    picker.info:SetText(string.format("Sold in %d-item bundles  ·  Up to %d items%s", info.stackCount,
        limit, multi and " (multiple purchases)" or ""))
    picker.oneStack.label:SetText("1 STACK: " .. active.stackSize)
    picker.fiveStacks.label:SetText("5 STACKS: " .. active.stackSize * 5)
    picker.quantity:SetText(tostring(info.stackCount))
    picker.quantity:ClearFocus()
    Render()
    if GameTooltip then GameTooltip:Hide() end
    picker:Show()
    return true
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function()
    merchantSession = merchantSession + 1
    addon.CloseVendorStackPicker()
end)
