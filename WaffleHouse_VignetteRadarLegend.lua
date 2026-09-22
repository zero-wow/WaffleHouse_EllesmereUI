local _, addon = ...
if type(addon) ~= "table" then return end

local PANEL_W, PANEL_H = 206, 166
local ACCENT = { 0.05, 0.82, 0.62 }
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

local CATEGORY_ORDER = { "rare", "treasure", "event", "other" }
local CATEGORIES = {
    rare = { label = "RARES", color = { 1.00, 0.24, 0.20 } },
    treasure = { label = "TREASURE", color = { 1.00, 0.68, 0.16 } },
    event = { label = "EVENTS", color = { 0.67, 0.42, 1.00 } },
    other = { label = "OTHER", color = { 0.66, 0.72, 0.76 } },
}

local fallbackSettings = {}
local panel
local attachedTo
local changeCallback

local API = {}
addon.VignetteRadarLegend = API

local function Settings()
    if type(addon.GetSettings) == "function" then
        local ok, settings = pcall(addon.GetSettings)
        if ok and type(settings) == "table" then return settings end
    end
    return fallbackSettings
end

local function CategoryKey(category)
    if type(category) == "string" then
        category = category:lower()
        if CATEGORIES[category] then return category end
    end
    return "other"
end

function API.ApplyDefaults(settings)
    settings = type(settings) == "table" and settings or Settings()
    if type(settings.vignetteRadarCategories) ~= "table" then
        settings.vignetteRadarCategories = {}
    end
    local enabled = settings.vignetteRadarCategories
    for _, category in ipairs(CATEGORY_ORDER) do
        if type(enabled[category]) ~= "boolean" then enabled[category] = true end
    end
    local highlight = settings.vignetteRadarHighlight
    if type(highlight) ~= "string" then
        settings.vignetteRadarHighlight = nil
    else
        highlight = highlight:lower()
        if not CATEGORIES[highlight] or enabled[highlight] ~= true then
            settings.vignetteRadarHighlight = nil
        else
            settings.vignetteRadarHighlight = highlight
        end
    end
    return settings
end

function API.IsCategoryEnabled(category)
    local settings = API.ApplyDefaults()
    return settings.vignetteRadarCategories[CategoryKey(category)] == true
end

function API.GetHighlight()
    return API.ApplyDefaults().vignetteRadarHighlight
end

function API.ColorFor(category)
    local color = CATEGORIES[CategoryKey(category)].color
    return color[1], color[2], color[3]
end

-- A disabled category is hidden. Enabled categories outside the spotlight remain
-- visible enough to preserve spatial context without competing with the focus.
function API.OpacityFor(category)
    category = CategoryKey(category)
    if not API.IsCategoryEnabled(category) then return 0 end
    local highlight = API.GetHighlight()
    if highlight and highlight ~= category then return 0.18 end
    return 1
end

function API.DotStyle(category)
    category = CategoryKey(category)
    local red, green, blue = API.ColorFor(category)
    return API.IsCategoryEnabled(category), red, green, blue, API.OpacityFor(category), category
end

local function FontPath()
    return EllesmereUI and (EllesmereUI.EXPRESSWAY or EllesmereUI._font)
        or STANDARD_TEXT_FONT or FONT_FALLBACK
end

local function Text(parent, size, value)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FontPath(), size, "")
    label:SetText(value or "")
    label:SetTextColor(0.88, 0.90, 0.92, 1)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    return label
end

local function Surface(frame, red, green, blue, alpha, borderAlpha)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(red or 0.045, green or 0.052, blue or 0.06, alpha or 0.98)
    frame:SetBackdropBorderColor(1, 1, 1, borderAlpha or 0.13)
end

local function Tooltip(owner, title, body)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.65, 0.76, 0.74, true)
    GameTooltip:Show()
end

local function AddPressState(button)
    button.press = button:CreateTexture(nil, "OVERLAY")
    button.press:SetAllPoints()
    button.press:SetColorTexture(1, 1, 1, 0.055)
    button.press:Hide()
    button:SetScript("OnMouseDown", function(self) self.press:Show() end)
    button:SetScript("OnMouseUp", function(self) self.press:Hide() end)
    button:SetScript("OnHide", function(self) self.press:Hide() end)
end

local function NotifyChanged()
    API.Refresh()
    if type(changeCallback) == "function" then
        pcall(changeCallback)
    elseif type(addon.RefreshVignetteRadar) == "function" then
        addon.RefreshVignetteRadar()
    end
end

function API.SetChangeCallback(callback)
    changeCallback = type(callback) == "function" and callback or nil
end

function API.SetCategoryEnabled(category, enabled)
    category = CategoryKey(category)
    local settings = API.ApplyDefaults()
    enabled = enabled == true
    if settings.vignetteRadarCategories[category] == enabled then return false end
    settings.vignetteRadarCategories[category] = enabled
    if not enabled and settings.vignetteRadarHighlight == category then
        settings.vignetteRadarHighlight = nil
    end
    NotifyChanged()
    return true
end

function API.SetHighlight(category)
    local settings = API.ApplyDefaults()
    if category == nil or category == "all" then
        category = nil
    else
        category = CategoryKey(category)
        settings.vignetteRadarCategories[category] = true
    end
    if settings.vignetteRadarHighlight == category then return false end
    settings.vignetteRadarHighlight = category
    NotifyChanged()
    return true
end

local function CreateCategoryRow(parent, category, index)
    local definition = CATEGORIES[category]
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(PANEL_W - 18, 23)
    row:SetPoint("TOPLEFT", 9, -39 - ((index - 1) * 27))
    Surface(row, 0.065, 0.073, 0.082, 0.98, 0.10)
    row.category = category

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetPoint("TOPLEFT", 1, -1)
    row.selection:SetPoint("BOTTOMRIGHT", -1, 1)
    row.selection:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.09)
    row.selection:Hide()

    row.hover = row:CreateTexture(nil, "ARTWORK")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.035)
    row.hover:Hide()

    row.swatchGlow = row:CreateTexture(nil, "ARTWORK")
    row.swatchGlow:SetSize(13, 13)
    row.swatchGlow:SetPoint("LEFT", 8, 0)
    row.swatchGlow:SetColorTexture(definition.color[1], definition.color[2], definition.color[3], 0.14)
    row.swatch = row:CreateTexture(nil, "OVERLAY")
    row.swatch:SetSize(7, 7)
    row.swatch:SetPoint("CENTER", row.swatchGlow, "CENTER")
    row.swatch:SetColorTexture(definition.color[1], definition.color[2], definition.color[3], 1)

    row.label = Text(row, 10, definition.label)
    row.label:SetPoint("LEFT", 29, 0)

    row.toggle = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.toggle:SetSize(42, 17)
    row.toggle:SetPoint("RIGHT", -4, 0)
    Surface(row.toggle, 0.025, 0.03, 0.035, 0.95, 0.14)
    row.toggle.label = Text(row.toggle, 8, "ON")
    row.toggle.label:SetAllPoints()
    row.toggle.label:SetJustifyH("CENTER")
    AddPressState(row)
    AddPressState(row.toggle)

    row:SetScript("OnClick", function()
        if API.GetHighlight() == category then API.SetHighlight(nil) else API.SetHighlight(category) end
    end)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        Tooltip(self, definition.label:sub(1, 1) .. definition.label:sub(2):lower(),
            "Click the row to spotlight this type. Other enabled dots stay visible but dim.")
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.toggle:SetScript("OnClick", function()
        API.SetCategoryEnabled(category, not API.IsCategoryEnabled(category))
    end)
    row.toggle:SetScript("OnEnter", function(self)
        Tooltip(self, "Filter " .. definition.label:sub(1, 1) .. definition.label:sub(2):lower(),
            "Turn this category on or off on the radar.")
    end)
    row.toggle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function Attach(anchor)
    if not panel then return end
    panel:ClearAllPoints()
    if anchor and anchor.GetRight and UIParent and UIParent.GetWidth then
        local right = anchor:GetRight()
        local width = UIParent:GetWidth()
        if type(right) == "number" and type(width) == "number" and right + PANEL_W + 12 > width then
            panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        else
            panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        end
    elseif anchor then
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    attachedTo = anchor
end

local function EnsurePanel()
    if panel then return panel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end

    panel = CreateFrame("Frame", "WaffleHouseVignetteRadarLegend", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    if panel.SetFrameStrata then panel:SetFrameStrata("DIALOG") end
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    if panel.EnableMouse then panel:EnableMouse(true) end
    Surface(panel)

    panel.accent = panel:CreateTexture(nil, "OVERLAY")
    panel.accent:SetPoint("TOPLEFT", 1, -1)
    panel.accent:SetPoint("BOTTOMLEFT", 1, 1)
    panel.accent:SetWidth(2)
    panel.accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)

    panel.title = Text(panel, 11, "RADAR LEGEND")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetPoint("TOPLEFT", 9, -31)
    panel.divider:SetPoint("TOPRIGHT", -9, -31)
    panel.divider:SetHeight(1)
    panel.divider:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)

    panel.all = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.all:SetSize(38, 18)
    panel.all:SetPoint("TOPRIGHT", -9, -7)
    Surface(panel.all, 0.03, 0.038, 0.043, 0.96, 0.16)
    panel.all.label = Text(panel.all, 8, "ALL")
    panel.all.label:SetAllPoints()
    panel.all.label:SetJustifyH("CENTER")
    AddPressState(panel.all)
    panel.all:SetScript("OnClick", function() API.SetHighlight(nil) end)
    panel.all:SetScript("OnEnter", function(self)
        Tooltip(self, "Show all enabled", "Clear the spotlight and return enabled categories to equal strength.")
    end)
    panel.all:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel.rows = {}
    for index, category in ipairs(CATEGORY_ORDER) do
        panel.rows[category] = CreateCategoryRow(panel, category, index)
    end

    panel.status = Text(panel, 8, "NO SPOTLIGHT")
    panel.status:SetPoint("BOTTOMLEFT", 10, 7)
    panel.status:SetTextColor(0.48, 0.55, 0.56, 1)
    -- WoW creates frames shown by default. Keep the lazy panel closed until the
    -- radar's legend button explicitly opens it.
    panel:Hide()
    return panel
end

function API.Refresh()
    API.ApplyDefaults()
    if not panel then return end
    local highlight = API.GetHighlight()
    for _, category in ipairs(CATEGORY_ORDER) do
        local row = panel.rows[category]
        local enabled = API.IsCategoryEnabled(category)
        local selected = highlight == category
        if enabled then
            row:SetAlpha((selected or not highlight) and 1 or 0.58)
            row.toggle.label:SetText("ON")
            row.toggle.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            row.swatch:SetAlpha(1)
        else
            row:SetAlpha(0.46)
            row.toggle.label:SetText("OFF")
            row.toggle.label:SetTextColor(0.58, 0.60, 0.62, 1)
            row.swatch:SetAlpha(0.38)
        end
        if selected then row.selection:Show() else row.selection:Hide() end
    end
    if highlight then
        panel.status:SetText("SPOTLIGHT: " .. CATEGORIES[highlight].label)
        panel.all.label:SetTextColor(0.62, 0.66, 0.68, 1)
    else
        panel.status:SetText("NO SPOTLIGHT")
        panel.all.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    end
end

function API.Toggle(anchor)
    local legend = EnsurePanel()
    if not legend then return false end
    if legend:IsShown() then
        legend:Hide()
        return false
    end
    Attach(anchor or attachedTo)
    API.Refresh()
    legend:Show()
    return true
end

function API.Hide()
    if panel then panel:Hide() end
end

function API.IsShown()
    return panel ~= nil and panel:IsShown() or false
end

API.ApplyDefaults()

API.Testing = {
    CategoryKey = CategoryKey,
    CategoryOrder = CATEGORY_ORDER,
    Categories = CATEGORIES,
    GetPanel = function() return panel end,
}
