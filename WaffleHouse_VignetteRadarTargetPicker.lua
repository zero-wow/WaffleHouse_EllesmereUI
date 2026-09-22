local _, addon = ...
if type(addon) ~= "table" then return end

local PANEL_W, PANEL_H = 250, 258
local ROWS_PER_PAGE = 5
local ACCENT = { 0.05, 0.82, 0.62 }
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

local panel
local provider
local changeCallback
local focusKey, focusName
local page = 1

local API = {}
addon.VignetteRadarTargetPicker = API

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

local function Targets()
    if type(provider) ~= "function" then return {} end
    local ok, targets = pcall(provider)
    if not ok or type(targets) ~= "table" then return {} end
    return targets
end

local function Tooltip(owner, target)
    if not (GameTooltip and target) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(target.name or "Detected vignette", 1, 1, 1)
    if type(target.distance) == "number" then
        GameTooltip:AddLine(math.floor(target.distance + 0.5) .. " yd away", 0.72, 0.76, 0.78)
    end
    GameTooltip:AddLine("Click to show only this vignette on both radar views.", 0.55, 0.86, 0.76, true)
    GameTooltip:Show()
end

local function NotifyChanged()
    API.Refresh()
    if type(changeCallback) == "function" then pcall(changeCallback) end
end

function API.SetProvider(callback)
    provider = type(callback) == "function" and callback or nil
    API.Refresh()
end

function API.SetChangeCallback(callback)
    changeCallback = type(callback) == "function" and callback or nil
end

function API.GetFocus()
    return focusKey
end

function API.GetFocusName()
    return focusName
end

function API.SetFocus(key, name)
    key = type(key) == "string" and key ~= "" and key or nil
    name = key and type(name) == "string" and name or nil
    if focusKey == key and focusName == name then return false end
    focusKey, focusName = key, name
    NotifyChanged()
    return true
end

function API.ClearFocus()
    return API.SetFocus(nil)
end

function API.ValidateTargets(targets)
    if not focusKey then return false end
    targets = type(targets) == "table" and targets or Targets()
    for _, target in ipairs(targets) do
        if target.key == focusKey then return false end
    end
    focusKey, focusName = nil, nil
    API.Refresh()
    return true
end

local function AddPressState(button)
    button.press = button:CreateTexture(nil, "OVERLAY")
    button.press:SetAllPoints()
    button.press:SetColorTexture(1, 1, 1, 0.05)
    button.press:Hide()
    button:SetScript("OnMouseDown", function(self) self.press:Show() end)
    button:SetScript("OnMouseUp", function(self) self.press:Hide() end)
    button:SetScript("OnHide", function(self) self.press:Hide() end)
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(PANEL_W - 18, 34)
    row:SetPoint("TOPLEFT", 9, -45 - ((index - 1) * 37))
    Surface(row, 0.06, 0.069, 0.078, 0.98, 0.09)

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetPoint("TOPLEFT", 1, -1)
    row.selection:SetPoint("BOTTOMRIGHT", -1, 1)
    row.selection:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.10)
    row.selection:Hide()
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", 1, 1)
    row.accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    row.accent:Hide()

    row.reticle = row:CreateTexture(nil, "ARTWORK")
    row.reticle:SetSize(19, 19)
    row.reticle:SetPoint("LEFT", 8, 0)
    row.reticle:SetTexture(CIRCLE_TEXTURE)
    row.reticle:SetVertexColor(0.22, 0.26, 0.28, 0.9)
    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("CENTER", row.reticle, "CENTER")
    row.dot:SetTexture(CIRCLE_TEXTURE)

    row.name = Text(row, 10, "")
    row.name:SetPoint("TOPLEFT", 35, -6)
    row.name:SetWidth(133)
    row.meta = Text(row, 8, "")
    row.meta:SetPoint("BOTTOMLEFT", 35, 5)
    row.meta:SetTextColor(0.49, 0.58, 0.59, 1)
    row.action = Text(row, 8, "FOCUS")
    row.action:SetPoint("RIGHT", -8, 0)
    row.action:SetJustifyH("RIGHT")
    row.action:SetTextColor(0.56, 0.64, 0.65, 1)
    AddPressState(row)

    row:SetScript("OnClick", function(self)
        local target = self.target
        if not target then return end
        if focusKey == target.key then API.ClearFocus() else API.SetFocus(target.key, target.name) end
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.36)
        Tooltip(self, self.target)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.09)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return row
end

local function Attach(anchor)
    if not panel then return end
    panel:ClearAllPoints()
    if anchor and anchor.GetRight and UIParent and UIParent.GetWidth then
        local right, width = anchor:GetRight(), UIParent:GetWidth()
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
end

local function EnsurePanel()
    if panel then return panel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end

    panel = CreateFrame("Frame", "WaffleHouseVignetteRadarTargetPicker", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    if panel.SetFrameStrata then panel:SetFrameStrata("DIALOG") end
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    Surface(panel)

    panel.accent = panel:CreateTexture(nil, "OVERLAY")
    panel.accent:SetPoint("TOPLEFT", 1, -1)
    panel.accent:SetPoint("BOTTOMLEFT", 1, 1)
    panel.accent:SetWidth(2)
    panel.accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    panel.title = Text(panel, 11, "VIGNETTE FOCUS")
    panel.title:SetPoint("TOPLEFT", 10, -9)
    panel.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    panel.subtitle = Text(panel, 8, "Choose one current detection")
    panel.subtitle:SetPoint("TOPLEFT", 10, -25)
    panel.subtitle:SetTextColor(0.48, 0.56, 0.57, 1)

    panel.clear = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.clear:SetSize(58, 20)
    panel.clear:SetPoint("TOPRIGHT", -9, -8)
    Surface(panel.clear, 0.03, 0.038, 0.043, 0.96, 0.16)
    panel.clear.label = Text(panel.clear, 8, "SHOW ALL")
    panel.clear.label:SetAllPoints()
    panel.clear.label:SetJustifyH("CENTER")
    AddPressState(panel.clear)
    panel.clear:SetScript("OnClick", function() API.ClearFocus() end)
    panel.clear:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show all vignettes", 1, 1, 1)
        GameTooltip:AddLine("Clear the specific target filter while keeping category filters active.", 0.55, 0.86, 0.76, true)
        GameTooltip:Show()
    end)
    panel.clear:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel.rows = {}
    for index = 1, ROWS_PER_PAGE do panel.rows[index] = CreateRow(panel, index) end
    panel.empty = Text(panel, 10, "NO CURRENT DETECTIONS")
    panel.empty:SetPoint("CENTER", 0, -5)
    panel.empty:SetJustifyH("CENTER")
    panel.empty:SetTextColor(0.50, 0.56, 0.57, 1)

    panel.previous = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.previous:SetSize(24, 18)
    panel.previous:SetPoint("BOTTOMLEFT", 9, 7)
    Surface(panel.previous, 0.03, 0.038, 0.043, 0.96, 0.14)
    panel.previous.label = Text(panel.previous, 10, "‹")
    panel.previous.label:SetAllPoints()
    panel.previous.label:SetJustifyH("CENTER")
    panel.previous:SetScript("OnClick", function() page = math.max(1, page - 1); API.Refresh() end)
    panel.next = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.next:SetSize(24, 18)
    panel.next:SetPoint("BOTTOMRIGHT", -9, 7)
    Surface(panel.next, 0.03, 0.038, 0.043, 0.96, 0.14)
    panel.next.label = Text(panel.next, 10, "›")
    panel.next.label:SetAllPoints()
    panel.next.label:SetJustifyH("CENTER")
    panel.next:SetScript("OnClick", function() page = page + 1; API.Refresh() end)
    panel.page = Text(panel, 8, "1 / 1")
    panel.page:SetPoint("BOTTOM", 0, 11)
    panel.page:SetJustifyH("CENTER")
    panel.page:SetTextColor(0.49, 0.57, 0.58, 1)
    panel:Hide()
    return panel
end

function API.Refresh()
    if not panel then return end
    local targets = Targets()
    local pageCount = math.max(1, math.ceil(#targets / ROWS_PER_PAGE))
    page = math.max(1, math.min(page, pageCount))
    local first = ((page - 1) * ROWS_PER_PAGE) + 1
    for rowIndex, row in ipairs(panel.rows) do
        local target = targets[first + rowIndex - 1]
        row.target = target
        if target then
            local red, green, blue = target.red or 1, target.green or 0.24, target.blue or 0.20
            row.name:SetText(target.name or "Detected vignette")
            local category = type(target.category) == "string" and target.category:upper() or "OTHER"
            local distance = type(target.distance) == "number" and (math.floor(target.distance + 0.5) .. " YD") or "DISTANCE N/A"
            row.meta:SetText(category .. "  •  " .. distance)
            row.dot:SetVertexColor(red, green, blue, 1)
            local selected = focusKey == target.key
            row.action:SetText(selected and "ACTIVE" or "FOCUS")
            row.action:SetTextColor(selected and ACCENT[1] or 0.56, selected and ACCENT[2] or 0.64,
                selected and ACCENT[3] or 0.65, 1)
            if selected then row.selection:Show(); row.accent:Show() else row.selection:Hide(); row.accent:Hide() end
            row:Show()
        else
            row:Hide()
        end
    end
    panel.empty:SetShown(#targets == 0)
    panel.page:SetText(page .. " / " .. pageCount)
    panel.previous:SetShown(pageCount > 1 and page > 1)
    panel.next:SetShown(pageCount > 1 and page < pageCount)
    panel.clear:SetAlpha(focusKey and 1 or 0.48)
    panel.subtitle:SetText(focusKey and ("Focused: " .. (focusName or "current vignette")) or "Choose one current detection")
end

function API.Toggle(anchor)
    local picker = EnsurePanel()
    if not picker then return false end
    if picker:IsShown() then picker:Hide(); return false end
    Attach(anchor)
    API.Refresh()
    picker:Show()
    return true
end

function API.Hide()
    if panel then panel:Hide() end
end

function API.IsShown()
    return panel ~= nil and panel:IsShown() or false
end

API.Testing = {
    GetPanel = function() return panel end,
    GetTargets = Targets,
    RowsPerPage = ROWS_PER_PAGE,
}
