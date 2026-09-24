local addonName, addon = ...
if not addon then return end

-- EllesmereUI Bags owns recent-item detection. This module only paints a
-- separate, non-interactive Blizzard-style glow on existing inventory slots.
local HIGHLIGHT_SECONDS = 30
local visuals = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local seen, firstShown = {}, {}
local RefreshVisuals

local function GetSettings()
    return addon.GetSettings and addon.GetSettings() or {}
end

local function GetClearMode()
    local mode = GetSettings().bagRecentHighlightClearMode
    if mode == "timer" or mode == "close" then return mode end
    return "hover"
end

local function IsSafe(value)
    return not (issecretvalue and issecretvalue(value))
end

local function GetButtonItemID(button)
    if not (button and button.GetParent and button.GetID and C_Container
        and C_Container.GetContainerItemInfo) then return nil end
    local parent = button:GetParent()
    local bag, slot = parent and parent.GetID and parent:GetID(), button:GetID()
    if not (IsSafe(bag) and IsSafe(slot) and type(bag) == "number" and type(slot) == "number"
        and bag >= 0 and bag <= 5 and slot > 0) then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = info and IsSafe(info) and info.itemID
    return IsSafe(itemID) and type(itemID) == "number" and itemID or nil
end

local function GetOrCreateVisual(button)
    local visual = visuals[button]
    if visual then return visual end
    -- The item button uses a secure template; never create its regions or
    -- attach a script while combat-locked. Repaint after combat instead.
    if InCombatLockdown and InCombatLockdown() then return nil end
    -- EllesmereUI suppresses the template's NewItemTexture and animation.
    -- Own this visual instead of changing Blizzard template sub-objects, and
    -- keep it below the host's text and Waffle's frozen-item marker.
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 3)
    glow:SetAllPoints(button)
    glow:SetAtlas("bags-glow-white")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.05, 0.82, 0.62, 1)
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetOrder(1)
    fadeOut:SetDuration(0.5)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.2)
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetOrder(2)
    fadeIn:SetDuration(0.5)
    fadeIn:SetFromAlpha(0.2)
    fadeIn:SetToAlpha(1)
    visual = { glow = glow, pulse = pulse }
    button:HookScript("OnEnter", function(self)
        if GetClearMode() ~= "hover" then return end
        local itemID = GetButtonItemID(self)
        local bags = _G.EUI_Bags
        if itemID and bags and bags._recentItems and bags._recentItems[itemID] then
            seen[itemID] = true
            RefreshVisuals()
        end
    end)
    visuals[button] = visual
    return visual
end

local function SetVisual(visual, visible)
    if visible then
        visual.glow:Show()
        if not visual.pulse:IsPlaying() then
            visual.glow:SetAlpha(1)
            visual.pulse:Play()
        end
    else
        if visual.pulse:IsPlaying() then visual.pulse:Stop() end
        visual.glow:Hide()
    end
end

local function EnumerateButtons(container, touched, recent, mode)
    if not (container and container.GetChildren and container.IsVisible and container:IsVisible()) then return end
    for _, parent in ipairs({ container:GetChildren() }) do
        local button = parent and parent.GetChildren and parent:GetChildren()
        if button and button.GetID and parent.GetID and button.IsShown and button:IsShown()
            and parent.IsShown and parent:IsShown() then
            local itemID = GetButtonItemID(button)
            if itemID and recent[itemID] and not seen[itemID] then
                local visual = GetOrCreateVisual(button)
                if visual then
                    if mode == "timer" and not firstShown[itemID] then
                        local token = {}
                        firstShown[itemID] = token
                        if C_Timer and C_Timer.After then
                            C_Timer.After(HIGHLIGHT_SECONDS, function()
                                if firstShown[itemID] == token and GetClearMode() == "timer" then
                                    seen[itemID] = true
                                    RefreshVisuals()
                                end
                            end)
                        end
                    end
                    touched[button] = true
                    SetVisual(visual, true)
                end
            end
        end
    end
end

RefreshVisuals = function()
    local bags = _G.EUI_Bags
    local recent = bags and bags._recentItems or {}
    for itemID in pairs(seen) do if not recent[itemID] then seen[itemID] = nil end end
    for itemID in pairs(firstShown) do if not recent[itemID] then firstShown[itemID] = nil end end
    local touched = {}
    if GetSettings().bagRecentHighlightEnabled ~= false then
        local mode = GetClearMode()
        EnumerateButtons(bags and bags._scrollChild, touched, recent, mode)
        EnumerateButtons(_G.EUI_BagsReagent, touched, recent, mode)
    end
    for button, visual in pairs(visuals) do
        if not touched[button] then SetVisual(visual, false) end
    end
end
addon.RefreshRecentItemHighlights = RefreshVisuals

function addon.ResetRecentItemHighlights()
    wipe(seen)
    wipe(firstShown)
    RefreshVisuals()
end

function addon.BuildRecentItemsBagsPage(parent, y)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return y end
    local h
    _, h = W:SectionHeader(parent, "RECENT ITEMS", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Highlight Recent Items",
            tooltip = "Pulse Blizzard's new-item glow over items tracked by EllesmereUI Bags' Recent Items list. This visual effect never changes the bag item or its click behavior.",
            getValue = function() return GetSettings().bagRecentHighlightEnabled ~= false end,
            setValue = function(value)
                GetSettings().bagRecentHighlightEnabled = value and true or false
                RefreshVisuals()
            end,
        },
        {
            type = "dropdown",
            text = "Clear Highlight",
            values = { hover = "On Hover", timer = "After 30 Seconds", close = "When Bags Close" },
            order = { "hover", "timer", "close" },
            tooltip = "Choose when the glow disappears. This does not clear EllesmereUI Bags' Recent Items list. The timer starts when the item is first shown in your bags.",
            getValue = GetClearMode,
            setValue = function(value)
                GetSettings().bagRecentHighlightClearMode = value
                addon.ResetRecentItemHighlights()
            end,
        }
    ); y = y - h
    return y
end

local function InstallHooks()
    for _, frame in ipairs({ _G.EUI_Bags, _G.EUI_BagsReagent }) do
        if frame and frame.RefreshInventory and not hookedFrames[frame] then
            hooksecurefunc(frame, "RefreshInventory", RefreshVisuals)
            if frame == _G.EUI_Bags then
                frame:HookScript("OnHide", function()
                    if GetClearMode() == "close" then
                        for itemID in pairs(frame._recentItems or {}) do seen[itemID] = true end
                    end
                    RefreshVisuals()
                end)
            end
            hookedFrames[frame] = true
        end
    end
    RefreshVisuals()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "EllesmereUIBags" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, InstallHooks)
        if event == "PLAYER_LOGIN" then C_Timer.After(1, InstallHooks) end
    else
        InstallHooks()
    end
end)
