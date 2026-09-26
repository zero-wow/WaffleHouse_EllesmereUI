local _, addon = ...
if type(addon) ~= "table" then return end

local toast
local queue = {}
local queuedKeys = {}
local activeKey
local SHOW_SECONDS = 8
local FADE_SECONDS = 0.25

local function CreateToast()
    if toast or not UIParent then return end
    toast = CreateFrame("Frame", "WaffleHouseWarningToast", UIParent, "BackdropTemplate")
    toast:SetSize(380, 90)
    toast:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -28, -76)
    toast:SetFrameStrata("DIALOG")
    toast:EnableMouse(false)
    toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    toast:SetBackdropColor(0.045, 0.055, 0.07, 0.97)
    toast:SetBackdropBorderColor(0.31, 0.34, 0.38, 1)

    local accent = toast:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", 1, 1)
    accent:SetWidth(3)
    accent:SetColorTexture(1, 0.64, 0.2, 1)

    local icon = toast:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 15, -18)

    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    toast.title = toast:CreateFontString(nil, "OVERLAY")
    toast.title:SetFont(font, 11, "OUTLINE")
    toast.title:SetPoint("TOPLEFT", 53, -12)
    toast.title:SetPoint("TOPRIGHT", -14, -12)
    toast.title:SetJustifyH("LEFT")
    toast.title:SetTextColor(1, 0.69, 0.28)

    toast.message = toast:CreateFontString(nil, "OVERLAY")
    toast.message:SetFont(font, 14, "")
    toast.message:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -8)
    toast.message:SetPoint("RIGHT", -14, 0)
    toast.message:SetJustifyH("LEFT")
    toast.message:SetTextColor(1, 1, 1)

    toast.detail = toast:CreateFontString(nil, "OVERLAY")
    toast.detail:SetFont(font, 10, "")
    toast.detail:SetPoint("TOPLEFT", toast.message, "BOTTOMLEFT", 0, -7)
    toast.detail:SetPoint("RIGHT", -14, 0)
    toast.detail:SetJustifyH("LEFT")
    toast.detail:SetTextColor(0.65, 0.69, 0.73)
    toast:Hide()
end

local function ShowNext()
    if not toast or toast:IsShown() or #queue == 0 then return end
    local entry = table.remove(queue, 1)
    activeKey = entry.key
    toast.title:SetText(entry.title)
    toast.message:SetText(entry.message)
    toast.detail:SetText(entry.detail)
    toast.elapsed = 0
    toast:SetAlpha(0)
    toast:SetScript("OnUpdate", function(self, delta)
        self.elapsed = self.elapsed + delta
        if self.elapsed < FADE_SECONDS then
            self:SetAlpha(self.elapsed / FADE_SECONDS)
        elseif self.elapsed < SHOW_SECONDS - FADE_SECONDS then
            self:SetAlpha(1)
        elseif self.elapsed < SHOW_SECONDS then
            self:SetAlpha((SHOW_SECONDS - self.elapsed) / FADE_SECONDS)
        else
            self:SetScript("OnUpdate", nil)
            self:Hide()
            queuedKeys[activeKey] = nil
            activeKey = nil
            ShowNext()
        end
    end)
    toast:Show()
end

function addon.ShowWarningToast(key, title, message, detail)
    if type(key) ~= "string" or key == "" or queuedKeys[key]
        or type(title) ~= "string" or type(message) ~= "string" then return false end
    CreateToast()
    if not toast then return false end
    queuedKeys[key] = true
    queue[#queue + 1] = { key = key, title = title, message = message, detail = detail or "" }
    ShowNext()
    return true
end
