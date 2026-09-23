local _, addon = ...

local ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62
local nativeViewActive = false
local nativeReturnButton
local bridgedHost

local function ShowTooltip(button, message)
    if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
        EllesmereUI.ShowWidgetTooltip(button, message)
    end
end

local function HideTooltip()
    if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
end

local function EnsureNativeReturnButton(merchantFrame)
    if nativeReturnButton then return nativeReturnButton end
    local button = CreateFrame("Button", nil, merchantFrame)
    button:SetSize(18, 18)
    -- The Blizzard close button occupies the top-right 32 pixels.  Leave a
    -- visible gutter so neither click target sits on the other's edge.
    button:SetPoint("TOPRIGHT", merchantFrame, "TOPRIGHT", -42, -10)
    button:SetFrameLevel(merchantFrame:GetFrameLevel() + 10)
    button.dot = button:CreateTexture(nil, "ARTWORK")
    button.dot:SetSize(6, 6)
    button.dot:SetPoint("CENTER")
    button.dot:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    button:SetScript("OnEnter", function(self)
        self.dot:SetColorTexture(1, 1, 1, 1)
        ShowTooltip(self, "Return to the EllesmereUI vendor view.")
    end)
    button:SetScript("OnLeave", function(self)
        self.dot:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        HideTooltip()
    end)
    button:SetScript("OnClick", function() addon.SetVendorNativeView(false) end)
    button:Hide()
    nativeReturnButton = button
    return button
end

local function GetVendorHost()
    local host = _G.EllesmereUIVendorBag
    if not (host and type(host.IsEUILayoutActive) == "function"
        and type(host.RefreshMerchantLayout) == "function") then
        return nil
    end
    if host ~= bridgedHost then
        local originalIsEUILayoutActive = host.IsEUILayoutActive
        host.IsEUILayoutActive = function(...)
            if nativeViewActive then return false end
            return originalIsEUILayoutActive(...)
        end
        bridgedHost = host
    end
    return host
end

function addon.SetVendorNativeView(enabled)
    -- Changing the merchant presentation can move protected Blizzard frames.
    if InCombatLockdown and InCombatLockdown() then return false end
    local merchantFrame = _G.MerchantFrame
    if not (merchantFrame and merchantFrame:IsShown()) then return false end
    local host = GetVendorHost()
    if not host then return false end

    local button = EnsureNativeReturnButton(merchantFrame)
    nativeViewActive = enabled == true
    host.RefreshMerchantLayout()
    button:SetShown(nativeViewActive)
    if not nativeViewActive and addon.Refresh then addon.Refresh() end
    return true
end

function addon.ResetVendorNativeView()
    -- A per-merchant comparison must not silently change the saved EUI layout
    -- or carry across to the next NPC.
    nativeViewActive = false
    if nativeReturnButton then nativeReturnButton:Hide() end
end

function addon.IsVendorNativeViewActive()
    return nativeViewActive
end
