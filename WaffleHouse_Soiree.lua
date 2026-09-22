local _, addon = ...
local Rules = addon.SoireeRules
local ACCENT = { 0.05, 0.82, 0.62 }
local CHOOSER_W, CHOOSER_H = 548, 532
local STYLE_PREVIEW_REVISION = 1
local overlays, buttonBorders = {}, {}
local chooser, currentModel, hookedHost, promptSeen
local Refresh, QueueRefresh, ShowChooser
local tooltipOwner, pinnedTooltip

local FOCUS_COPY = {
    favor = { "More Favor, more ways to help the court.",
        "A flexible pick when you are not chasing one faction. Favor unlocks additional faction tasks. We recommend it only when the live invitation rewards show one clear bonus winner." },
    [2711] = { "Back Silvermoon's arcane establishment.",
        "Make allies among Silvermoon's arcanists and political powerbrokers. Choose the Magisters to follow their weekly Fortify the Runestones route and work toward their reputation rewards." },
    [2712] = { "Stand with Silvermoon's Blood Knights.",
        "Support the blood elves' champions of the Light. Choose the Blood Knights to follow their weekly Fortify the Runestones route and work toward their reputation rewards." },
    [2713] = { "Help the rangers who defend Eversong.",
        "Side with the Farstriders, the defenders of Eversong's wilds. Choose them to follow their weekly Fortify the Runestones route and work toward their reputation rewards." },
    [2714] = { "Get to know the other side of Silvermoon.",
        "Build connections with the city's traders, rogues, and discreet operators. Choose the Shades of the Row to follow their weekly Fortify the Runestones route and work toward their reputation rewards." },
}

local function Settings()
    local root = addon.GetSettings()
    if type(root.soireeHelper) ~= "table" then root.soireeHelper = {} end
    local settings = root.soireeHelper
    if settings.enabled == nil then settings.enabled = true end
    if settings.askEachVisit == nil then settings.askEachVisit = false end
    -- One-time reset requested for this styling pass. The setting stays editable;
    -- do not rewrite a subsequent user choice on every refresh or login.
    if settings.stylePreviewRevision ~= STYLE_PREVIEW_REVISION then
        settings.enabled, settings.askEachVisit = true, true
        settings.stylePreviewRevision = STYLE_PREVIEW_REVISION
    end
    if not Rules.IsFocus(settings.focus) then settings.focus = nil end
    return settings
end

local function Text(parent, size, text, accent)
    local label = parent:CreateFontString(nil, "OVERLAY")
    local font = EllesmereUI and (EllesmereUI.EXPRESSWAY or EllesmereUI._font)
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    label:SetFont(font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    label:SetJustifyH("LEFT")
    label:SetTextColor(accent and ACCENT[1] or 0.9, accent and ACCENT[2] or 0.92, accent and ACCENT[3] or 0.93)
    label:SetText(text or "")
    return label
end

local function Fill(parent, r, g, b, a)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Border(parent, subtle)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local texture = parent:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(subtle and 1 or ACCENT[1], subtle and 1 or ACCENT[2], subtle and 1 or ACCENT[3], subtle and 0.15 or 0.9)
        if side == "TOP" or side == "BOTTOM" then
            texture:SetPoint(side .. "LEFT")
            texture:SetPoint(side .. "RIGHT")
            texture:SetHeight(1)
        else
            texture:SetPoint("TOP" .. side, 0, -1)
            texture:SetPoint("BOTTOM" .. side, 0, 1)
            texture:SetWidth(1)
        end
    end
end

local function HideTooltip(owner)
    if tooltipOwner == owner and pinnedTooltip ~= owner then
        if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        tooltipOwner = nil
    end
    if GameTooltip and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

local function ClearTooltip()
    pinnedTooltip = nil
    if tooltipOwner then HideTooltip(tooltipOwner) end
end

local function ShowTooltip(owner, text)
    if pinnedTooltip and pinnedTooltip ~= owner then pinnedTooltip = nil end
    if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
        tooltipOwner = owner
        EllesmereUI.ShowWidgetTooltip(owner, text, { width = 350, justify = "LEFT", anchor = "right" })
    elseif GameTooltip then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(text, 0.9, 0.92, 0.93, true)
        GameTooltip:Show()
    end
end

local function Explain(owner, entry)
    if not currentModel then return end
    local recommended = entry and currentModel.recommendedID == entry.optionID
    local lines = { recommended and "|cff0dd1a0Recommended for your focus|r" or "|cff0dd1a0Saltheril's Soiree|r",
        "Focus: " .. Rules.FocusName(currentModel.focus) }
    if recommended or not entry then
        lines[#lines + 1] = currentModel.reason
    elseif entry then
        lines[#lines + 1] = "This invitation supports " .. Rules.FactionName(entry.factionID) .. "."
    end
    if entry then
        local copy = FOCUS_COPY[entry.factionID]
        if copy then lines[#lines + 1] = "\n" .. copy[2] end
        lines[#lines + 1] = "\n|cffffffffInvitation reputation changes|r"
        local found
        for _, faction in ipairs(Rules.factions) do
            local value = entry.rep[faction.id]
            if value and value ~= 0 then
                found = true
                lines[#lines + 1] = (value < 0 and "|cffff8888" or "|cff6fe4cb")
                    .. string.format("%+d", value) .. "|r  " .. Rules.FactionName(faction.id)
            end
        end
        if not found then lines[#lines + 1] = "See this invitation's listed reputation changes." end
        if entry.favor > 0 then
            lines[#lines + 1] = "|cff0dd1a0+" .. entry.favor .. " Saltheril's Favor|r"
        end
        if not entry.enabled then lines[#lines + 1] = "This invitation is currently unavailable." end
    end
    lines[#lines + 1] = "\nCompare both reputation gains and losses. Your guest determines this week's Runestone faction; the highlight follows your chosen goal."
    lines[#lines + 1] = "\nClick this badge to change focus. You still send the invitation yourself."
    ShowTooltip(owner, table.concat(lines, "\n"))
end

local function HideIndicators()
    for _, overlay in pairs(overlays) do
        HideTooltip(overlay.badge)
        overlay:Hide()
    end
    for _, border in pairs(buttonBorders) do border:Hide() end
    currentModel = nil
end

local function Close()
    ClearTooltip()
    HideIndicators()
    if chooser then chooser:Hide() end
    promptSeen = nil
end

local function MakeButton(parent, label, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(104, 32)
    if EllesmereUI and EllesmereUI.MakeStyledButton and EllesmereUI.RB_COLOURS then
        local _, _, text = EllesmereUI.MakeStyledButton(button, label, 12, EllesmereUI.RB_COLOURS, callback)
        button.label = text
    else
        Fill(button, 0.061, 0.095, 0.12, 0.8)
        Border(button, true)
        button.label = Text(button, 12, label)
        button.label:SetPoint("CENTER")
        button:SetScript("OnClick", callback)
    end
    return button
end

local function FitChooser()
    if not chooser then return end
    local base = EllesmereUI and EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
    local scale = math.min(base, (UIParent:GetWidth() - 32) / CHOOSER_W, (UIParent:GetHeight() - 32) / CHOOSER_H)
    chooser:SetScale(math.max(0.1, scale))
end

local function SetFocus(focus)
    if not Rules.IsFocus(focus) or (InCombatLockdown and InCombatLockdown()) then return end
    Settings().focus = focus
    promptSeen = true
    if chooser then chooser:Hide() end
    QueueRefresh()
end

local function ChoiceModel(focus)
    local info = C_PlayerChoice and C_PlayerChoice.GetCurrentPlayerChoiceInfo
        and C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    return Rules.Evaluate(info, focus)
end

local function FocusDetails(key)
    local copy = FOCUS_COPY[key]
    local lines = { "|cff0dd1a0" .. Rules.FocusName(key) .. "|r", copy[2] }
    local model = ChoiceModel(key)
    local entry = model and model.byID[model.recommendedID]
    if entry then
        lines[#lines + 1] = "\n|cffffffffThis invitation|r"
        lines[#lines + 1] = (entry.name ~= "" and entry.name or Rules.FactionName(entry.factionID))
            .. " — " .. Rules.FactionName(entry.factionID)
        if entry.favor > 0 then lines[#lines + 1] = "+" .. entry.favor .. " Saltheril's Favor" end
        for _, faction in ipairs(Rules.factions) do
            local value = entry.rep[faction.id]
            if value and value ~= 0 then
                lines[#lines + 1] = (value < 0 and "|cffff8888" or "|cff6fe4cb")
                    .. string.format("%+d", value) .. "|r  " .. Rules.FactionName(faction.id)
            end
        end
    elseif model then
        lines[#lines + 1] = "\n" .. model.reason
    else
        lines[#lines + 1] = "\nOpen the invitation window to compare this week's rewards."
    end
    if key ~= "favor" then
        lines[#lines + 1] = "\nPick this for its faction route. Invitations can lower other reputations, so compare the current gains and losses."
    end
    lines[#lines + 1] = "\nClick the row to set your focus. Sending the invitation is still your choice."
    return table.concat(lines, "\n")
end

local function PaintChoice(button)
    local r, g, b = unpack(ACCENT)
    button.bg:SetColorTexture(button.recommended and r or 1, button.recommended and g or 1,
        button.recommended and b or 1, button.hovered and 0.12 or (button.recommended and 0.08 or 0.025))
    button.accent:SetColorTexture(r, g, b, 1)
    button.accent:SetShown(button.recommended == true)
    button.status:SetTextColor(r, g, b, 1)
end

local function RefreshChooser()
    local settings = Settings()
    if EllesmereUI and EllesmereUI.GetAccentColor then ACCENT = { EllesmereUI.GetAccentColor() } end
    local favorModel = ChoiceModel("favor")
    local favorEntry = favorModel and favorModel.byID[favorModel.recommendedID]
    for _, button in ipairs(chooser.choices) do
        button.recommended = button.focusKey == "favor" and favorEntry ~= nil
        button.status:SetText(button.recommended and "RECOMMENDED"
            or (button.focusKey == settings.focus and "SAVED FOCUS" or ""))
        button.detail:SetText(FOCUS_COPY[button.focusKey][1])
        if button.recommended then
            button.detail:SetText("+" .. favorEntry.favor .. " Favor from " .. Rules.FactionName(favorEntry.factionID)
                .. " in the current invitations.")
        end
        PaintChoice(button)
    end
end

ShowChooser = function()
    if Settings().enabled == false or (InCombatLockdown and InCombatLockdown()) then return end
    if not chooser then
        chooser = CreateFrame("Frame", "WaffleHouseSoireeFocus", UIParent)
        chooser:SetSize(CHOOSER_W, CHOOSER_H)
        chooser:SetPoint("CENTER")
        chooser:SetFrameStrata("DIALOG")
        chooser:SetClampedToScreen(true)
        chooser:EnableMouse(true)
        chooser:SetScript("OnHide", ClearTooltip)
        Fill(chooser, 0.06, 0.08, 0.10, 1)
        Border(chooser, true)
        local brand = Text(chooser, 11, "WAFFLE HOUSE  /  ADVENTURE", true)
        brand:SetPoint("TOPLEFT", 24, -18)
        local title = Text(chooser, 22, "Saltheril's Soiree")
        title:SetPoint("TOPLEFT", 24, -38)
        title:SetSize(CHOOSER_W - 100, 28)
        local intro = Text(chooser, 13, "Choose a goal for this week's invitation. Hover an info icon to see why it might suit you.")
        intro:SetPoint("TOPLEFT", 24, -74)
        intro:SetSize(CHOOSER_W - 48, 34)
        local close = MakeButton(chooser, "X", function() chooser:Hide() end)
        close:SetSize(28, 28)
        close:SetPoint("TOPRIGHT", -16, -16)
        chooser.choices = {}
        local choices = { { key = "favor", label = "Extra Favor" } }
        for _, faction in ipairs(Rules.factions) do
            choices[#choices + 1] = { key = faction.id, label = Rules.FactionName(faction.id) }
        end
        for index, choice in ipairs(choices) do
            local button = CreateFrame("Button", nil, chooser)
            button.focusKey = choice.key
            button:SetSize(CHOOSER_W - 48, 58)
            button:SetPoint("TOPLEFT", 24, -116 - (index - 1) * 64)
            button.bg = Fill(button, 1, 1, 1, 0.025)
            button.accent = button:CreateTexture(nil, "ARTWORK")
            button.accent:SetPoint("TOPLEFT", 0, -8)
            button.accent:SetPoint("BOTTOMLEFT", 0, 8)
            button.accent:SetWidth(2)
            button.label = Text(button, 15, choice.label)
            button.label:SetPoint("TOPLEFT", 16, -9)
            button.label:SetSize(CHOOSER_W - 230, 19)
            button.status = Text(button, 10, "", true)
            button.status:SetPoint("TOPRIGHT", -16, -10)
            button.status:SetSize(114, 12)
            button.status:SetJustifyH("RIGHT")
            button.detail = Text(button, 12, "")
            button.detail:SetPoint("TOPLEFT", 16, -32)
            button.detail:SetSize(CHOOSER_W - 126, 18)
            button.detail:SetTextColor(0.7, 0.75, 0.77, 1)
            button:SetScript("OnClick", function() SetFocus(choice.key) end)
            button:SetScript("OnEnter", function(self) self.hovered = true; PaintChoice(self) end)
            button:SetScript("OnLeave", function(self) self.hovered = nil; PaintChoice(self) end)
            local info = MakeButton(button, "i", function()
                if pinnedTooltip == button.info then ClearTooltip()
                else
                    pinnedTooltip = button.info
                    ShowTooltip(button.info, FocusDetails(choice.key))
                end
            end)
            button.info = info
            info:SetSize(26, 26)
            info:SetPoint("BOTTOMRIGHT", -12, 6)
            info:HookScript("OnEnter", function(self) ShowTooltip(self, FocusDetails(choice.key)) end)
            info:HookScript("OnLeave", HideTooltip)
            info:HookScript("OnHide", function() ClearTooltip() end)
            chooser.choices[#chooser.choices + 1] = button
        end
        local divider = chooser:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.10)
        divider:SetPoint("TOPLEFT", 24, -450)
        divider:SetPoint("TOPRIGHT", -24, -450)
        divider:SetHeight(1)
        local note = Text(chooser, 11, "Click an info icon to keep its details open. Your focus is shared across characters; change it with /whsoiree.")
        note:SetPoint("TOPLEFT", 24, -469)
        note:SetSize(CHOOSER_W - 192, 42)
        note:SetTextColor(0.6, 0.66, 0.69, 1)
        local later = MakeButton(chooser, "Later", function() chooser:Hide() end)
        later:SetPoint("BOTTOMRIGHT", -24, 24)
        table.insert(UISpecialFrames, "WaffleHouseSoireeFocus")
    end
    promptSeen = true
    RefreshChooser()
    FitChooser()
    chooser:Show()
end
addon.ShowSoireeFocus = ShowChooser

local function MaybePrompt()
    local settings = Settings()
    if not promptSeen and (not settings.focus or settings.askEachVisit) then ShowChooser() end
end

local function MakeOverlay(option)
    local overlay = CreateFrame("Frame", nil, option)
    overlay.ignoreInLayout = true
    overlay:EnableMouse(false)
    overlay:SetAllPoints(option)
    overlay:SetFrameLevel(option:GetFrameLevel() + 20)
    overlay.edge = CreateFrame("Frame", nil, overlay)
    overlay.edge:EnableMouse(false)
    -- The native option bounds include its title and invitation button.
    overlay.edge:SetPoint("TOPLEFT", option, "TOPLEFT", -4, 4)
    overlay.edge:SetPoint("BOTTOMRIGHT", option, "BOTTOMRIGHT", 4, -4)
    Border(overlay.edge)
    Fill(overlay.edge, ACCENT[1], ACCENT[2], ACCENT[3], 0.045)
    local badge = CreateFrame("Button", nil, overlay)
    overlay.badge = badge
    badge:EnableMouse(true)
    badge:SetHeight(36)
    badge:SetPoint("BOTTOMLEFT", option.Artwork, "BOTTOMLEFT", 8, 8)
    badge:SetPoint("BOTTOMRIGHT", option.Artwork, "BOTTOMRIGHT", -8, 8)
    Fill(badge, 0.035, 0.04, 0.045, 0.95)
    Border(badge, true)
    local icon = Text(badge, 20, "i", true)
    icon:SetSize(20, 26)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetJustifyH("CENTER")
    badge.label = Text(badge, 10, "", true)
    badge.label:SetPoint("TOPLEFT", 34, -6)
    badge.label:SetPoint("TOPRIGHT", -8, -6)
    local hint = Text(badge, 9, "Hover for details")
    hint:SetPoint("BOTTOMLEFT", 34, 6)
    hint:SetPoint("BOTTOMRIGHT", -8, 6)
    badge:SetScript("OnEnter", function(self) Explain(self, overlay.entry) end)
    badge:SetScript("OnClick", ShowChooser)
    badge:SetScript("OnLeave", HideTooltip)
    badge:SetScript("OnHide", HideTooltip)
    overlays[option] = overlay
    return overlay
end

local function HighlightButtons(option)
    local container = option.OptionButtonsContainer
    local pool = container and container.buttonFramePool
    if not (pool and pool.EnumerateActive) then return end
    for wrapper in pool:EnumerateActive() do
        local button = wrapper.Button
        if button and button:IsShown() and button:IsEnabled() then
            local border = buttonBorders[button]
            if not border then
                border = CreateFrame("Frame", nil, button)
                border.ignoreInLayout = true
                border:EnableMouse(false)
                border:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
                border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
                border:SetFrameLevel(button:GetFrameLevel() + 10)
                Border(border)
                Fill(border, ACCENT[1], ACCENT[2], ACCENT[3], 0.08)
                buttonBorders[button] = border
            end
            border:Show()
        end
    end
end

Refresh = function()
    HideIndicators()
    if Settings().enabled == false then
        if chooser then chooser:Hide() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    local host = _G.PlayerChoiceFrame
    if not (host and host:IsShown() and C_PlayerChoice and C_PlayerChoice.GetCurrentPlayerChoiceInfo) then return end
    local info = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    currentModel = Rules.Evaluate(info, Settings().focus)
    if not currentModel then
        if chooser then chooser:Hide() end
        return
    end
    local pool = host.optionPools
    if pool and pool.EnumerateActive then
        for option in pool:EnumerateActive() do
            local entry = option.optionInfo and currentModel.byID[option.optionInfo.id]
            if entry and option.Artwork and option.Artwork:IsShown()
                and option.Artwork:GetWidth() >= 140 and option.Artwork:GetHeight() >= 52 then
                local overlay = overlays[option] or MakeOverlay(option)
                overlay.entry = entry
                overlay:SetFrameLevel(option:GetFrameLevel() + 20)
                local recommended = entry.optionID == currentModel.recommendedID
                overlay.edge:SetShown(recommended)
                overlay.badge.label:SetText(recommended and "RECOMMENDED" or "INVITATION INFO")
                overlay:Show()
                if recommended then HighlightButtons(option) end
            end
        end
    end
    if chooser and chooser:IsShown() then RefreshChooser() end
    MaybePrompt()
end

local refreshPending
QueueRefresh = function()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function() refreshPending = nil; Refresh() end)
end

local function HookHost()
    local host = _G.PlayerChoiceFrame
    if not host or host == hookedHost then return end
    hookedHost = host
    host:HookScript("OnShow", QueueRefresh)
    host:HookScript("OnHide", Close)
    for _, method in ipairs({ "SetupOptions", "SetupOptionsAsGrid", "SetupFrame" }) do
        if type(host[method]) == "function" then hooksecurefunc(host, method, QueueRefresh) end
    end
end

function addon.BuildSoireeOptions(parent, y)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return y end
    local _, h = W:SectionHeader(parent, "SALTHERIL'S SOIREE", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Soiree Helper",
            tooltip = "Explain invitations and highlight the entry and button recommended for your focus. Invitations always require your own selection.",
            getValue = function() return Settings().enabled end,
            setValue = function(value) Settings().enabled = value == true; QueueRefresh() end },
        { type = "toggle", text = "Ask for Focus Each Visit",
            tooltip = "Show the focus chooser when the invitation window opens or you accept its quest. Otherwise remember your choice across characters.",
            getValue = function() return Settings().askEachVisit end,
            setValue = function(value) Settings().askEachVisit = value == true end }
    ); y = y - h
    local values, order = { favor = "Extra Favor" }, { "favor" }
    for _, faction in ipairs(Rules.factions) do
        local key = tostring(faction.id)
        values[key], order[#order + 1] = Rules.FactionName(faction.id), key
    end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Soiree Focus", values = values, order = order,
            tooltip = "Extra Favor follows this week's bonus token. A faction focus recommends its guest and weekly Runestone quest. Also available from /whsoiree.",
            getValue = function() return tostring(Settings().focus or "favor") end,
            setValue = function(value) SetFocus(value == "favor" and value or tonumber(value)) end }
    ); y = y - h
    return y
end

SLASH_WAFFLEHOUSESOIREE1 = "/whsoiree"
SlashCmdList.WAFFLEHOUSESOIREE = ShowChooser

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_CHOICE_UPDATE", "PLAYER_CHOICE_CLOSE",
    "QUEST_ACCEPTED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, value)
    if event == "PLAYER_CHOICE_CLOSE" then Close()
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideIndicators()
        if chooser then chooser:Hide() end
    elseif event == "QUEST_ACCEPTED" then
        if value == 89289 or value == 91629 then MaybePrompt() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        FitChooser()
        QueueRefresh()
    elseif event ~= "ADDON_LOADED" or value == "Blizzard_PlayerChoice" then
        HookHost()
        QueueRefresh()
    end
end)
