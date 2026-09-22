local addonName, addon = ...
local ADDON_FOLDER = addonName

-- The source asset is 1024 x 256.  Keep these UVs together with the asset so
-- a transparent export margin can be trimmed without changing layout code.
addon.LogoTextureInfo = addon.LogoTextureInfo or {
    path = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\waffle-house-logo.tga",
    left = 0.0078125,
    right = 0.9921875,
    top = 0.1484375,
    bottom = 0.8515625,
}

local logo

local function GetHeader()
    local tabBar = EllesmereUI and EllesmereUI._tabBar
    if not (tabBar and tabBar.GetPoint) then return end
    local _, header = tabBar:GetPoint(1)
    if header and header._title and header._desc then return header end
end

local function GetVisibleAspect(info)
    local left = tonumber(info.left) or 0
    local right = tonumber(info.right) or 1
    local top = tonumber(info.top) or 0
    local bottom = tonumber(info.bottom) or 1
    local width, height = right - left, bottom - top
    if width <= 0 or height <= 0 then return 4 end
    return 4 * width / height
end

local function ShowTextTitle(header)
    if logo then logo:Hide() end
    if header and header._title then header._title:Show() end
end

local function ApplyLogo(showLogo)
    local header = GetHeader()
    if not header then return end
    if not showLogo then
        ShowTextTitle(header)
        return
    end

    local title = header._title
    local info = addon.LogoTextureInfo
    if not (info and type(info.path) == "string" and info.path ~= "") then
        ShowTextTitle(header)
        return
    end

    if not logo then
        logo = header:CreateTexture(nil, "OVERLAY", nil, 1)
        logo:SetDrawLayer("OVERLAY", 1)
    end

    -- Keep the logo inside the exact text-title footprint.  The subtitle stays
    -- anchored to the unchanged FontString, preserving its existing position.
    local titleWidth = title:GetStringWidth()
    local titleHeight = title:GetStringHeight()
    if titleWidth <= 0 then titleWidth = 180 end
    if titleHeight <= 0 then titleHeight = 36 end
    local logoHeight = math.min(titleHeight, titleWidth / GetVisibleAspect(info))
    local logoWidth = logoHeight * GetVisibleAspect(info)

    local ok, loaded = pcall(logo.SetTexture, logo, info.path)
    if not ok or loaded == false or not logo:GetTexture() then
        ShowTextTitle(header)
        return
    end

    logo:SetTexCoord(info.left or 0, info.right or 1, info.top or 0, info.bottom or 1)
    logo:ClearAllPoints()
    logo:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
    logo:SetSize(logoWidth, logoHeight)
    title:Hide()
    logo:Show()
end

local function RefreshLogo()
    local activeModule = EllesmereUI and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    ApplyLogo(activeModule == ADDON_FOLDER)
end

if EllesmereUI and EllesmereUI.RegisterOnShow then
    EllesmereUI:RegisterOnShow(function()
        local header = GetHeader()
        if not header then return end
        -- On reopen there is no SelectModule call for the cached active page.
        -- Query the core's state rather than title visibility, because a
        -- missing texture intentionally leaves that title visible as fallback.
        RefreshLogo()
    end)
end

if EllesmereUI and EllesmereUI.SelectModule and hooksecurefunc then
    hooksecurefunc(EllesmereUI, "SelectModule", function()
        RefreshLogo()
    end)
end
