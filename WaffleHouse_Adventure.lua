local addonName, addon = ...

-- These are FileDataIDs for Valeera Sanguinar's Delve-companion voice assets,
-- checked against the current Retail client asset list.  MuteSoundFile operates
-- on these files only, so other NPC dialogue and normal combat sounds remain
-- untouched.
local VALEERA_VOICE_FILE_IDS = {
    7243762, 7243934, 7329273, 7430043, 7430047, 7430050, 7430053, 7430056, 7430059, 7430063,
    7430066, 7430069, 7430072, 7430075, 7430078, 7430082, 7430086, 7430089, 7430092, 7430095,
    7430098, 7430101, 7430104, 7430107, 7430110, 7430113, 7430116, 7430119, 7430122, 7430125,
    7430156, 7430159, 7430162, 7430165, 7430168, 7430171, 7430174, 7430177, 7430180, 7430183,
    7430186, 7430189, 7430192, 7430196, 7430199, 7430202, 7430205, 7430208, 7430211, 7430230,
    7430233, 7430237, 7430257, 7430268, 7430275, 7430283, 7430294, 7430314, 7430324, 7430333,
    7430336, 7430339, 7430342, 7430345, 7430348, 7430351, 7430354, 7430357, 7430360, 7430363,
    7430366, 7430369, 7430372, 7430375, 7430378, 7430381, 7430384, 7430388, 7430391, 7430394,
    7430397, 7430400, 7430405, 7430416, 7430423, 7430428, 7430431, 7430434, 7430437, 7430440,
    7430443, 7430446, 7430449, 7430452, 7430456, 7430459, 7430462, 7430465, 7430468, 7430471,
    7430474, 7430477, 7430480, 7430483, 7430486, 7430489, 7430492, 7430498, 7430506, 7430512,
    7430516, 7430519, 7430538, 7430547, 7430550, 7430555, 7430561, 7430565, 7430733, 7430740,
    7430751, 7430754, 7430778, 7430781, 7430784, 7430787, 7430790, 7430793, 7430796, 7430799,
    7430864, 7430867, 7430870, 7430881, 7430973, 7430985, 7430989, 7431077, 7431084, 7431087,
    7431093, 7431103, 7431106, 7431109, 7431112, 7431115, 7431119, 7431123, 7440991, 7461759,
    7825546, 8026028, 8026044, 8026045, 8026061, 8026646,
}

-- General-purpose Season 2 picks, shared across player specs and Valeera's
-- roles.  These are recommendations, not a talent-build calculation. Spell IDs
-- locate the live Trait entries regardless of client locale.
local RECOMMENDED_CURIO_SPELL_BY_TYPE = {
    Combat = 1248876, -- Corrosive Bilespear
    Utility = 1305684, -- Soul-Cracking Dreamcatcher
}
local CURIO_ORDER = { "Combat", "Utility" }
local CURIO_FALLBACK_NAMES = {
    Combat = "Corrosive Bilespear",
    Utility = "Soul-Cracking Dreamcatcher",
}
local ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62

local curioHookInstalled = false
local curioPanel
local RefreshCurioPanel
local muteAppliedByWaffleHouse = false

-- ZamestoTV Delves adds ValeeraMuterButton directly to the companion frame.
-- It is a separate addon, so skin its public button after it is constructed
-- instead of changing its source or competing with its mute logic.
local function SkinValeeraMuterButton()
    local button = _G.ValeeraMuterButton
    if not button then return end

    if not button._waffleValeeraMuteText then
        button._waffleValeeraMuteText = button:CreateFontString(nil, "OVERLAY")
        local path = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")
        button._waffleValeeraMuteText:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
        button._waffleValeeraMuteText:SetAllPoints()
        button._waffleValeeraMuteText:SetJustifyH("CENTER")
        button._waffleValeeraMuteText:SetJustifyV("MIDDLE")
        button:SetSize(62, 20)
        if button.Text then button.Text:Hide() end
        -- Remove the third-party UIPanelButton artwork completely. The action
        -- reads as an EUI-style text link rather than a mismatched Blizzard box.
        for _, region in ipairs({ button:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
        end
        button:HookScript("OnClick", function() C_Timer.After(0, SkinValeeraMuterButton) end)
        button:HookScript("OnEnter", function(self)
            local muted = ValeeraMuterDB and ValeeraMuterDB.isMuted == true
            self._waffleValeeraMuteText:SetTextColor(muted and 0.16 or 0.90, muted and 0.92 or 0.92, muted and 0.72 or 0.93, 1)
        end)
        button:HookScript("OnLeave", function() SkinValeeraMuterButton() end)
    end

    local muted = ValeeraMuterDB and ValeeraMuterDB.isMuted == true
    button._waffleValeeraMuteText:SetText(muted and "Mute: ON" or "Mute: OFF")
    -- Muted is the selected/healthy state, not an error. Keep audible neutral.
    button._waffleValeeraMuteText:SetTextColor(muted and 0.05 or 0.66, muted and 0.82 or 0.69, muted and 0.62 or 0.71, 1)
end

local function GetSettings()
    return addon.GetSettings and addon.GetSettings() or {}
end

local function SetValeeraVoiceMute(shouldMute)
    local soundAPI = shouldMute and MuteSoundFile or UnmuteSoundFile
    if type(soundAPI) ~= "function" then return end

    for _, fileID in ipairs(VALEERA_VOICE_FILE_IDS) do
        pcall(soundAPI, fileID)
    end
    muteAppliedByWaffleHouse = shouldMute == true
end

function addon.RefreshAdventureFeatures()
    local settings = GetSettings()
    local shouldMute = settings.muteValeeraVoiceLines == true
    if shouldMute ~= muteAppliedByWaffleHouse then
        SetValeeraVoiceMute(shouldMute)
    end
end

local function GetCurrentCompanionID()
    local frame = DelvesCompanionConfigurationFrame
    return frame and frame.playerCompanionID or nil
end

local function GetRecommendedEntryID(configID, selectionNodeID, recommendedSpellID)
    local nodeInfo = C_Traits.GetNodeInfo(configID, selectionNodeID)
    if not nodeInfo or type(nodeInfo.entryIDs) ~= "table" then return nil end

    for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        local definitionInfo = entryInfo and entryInfo.definitionID
            and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
        local spellID = definitionInfo and (definitionInfo.overriddenSpellID or definitionInfo.spellID)
        if spellID == recommendedSpellID then
            return entryID
        end
    end
    return nil
end

local function GetCurioConfiguration()
    if not (DelvesCompanionConfigurationFrame and DelvesCompanionConfigurationFrame:IsShown()) then return end

    local D, T = C_DelvesUI, C_Traits
    if not (D and T and Enum and Enum.CurioType
        and D.GetTraitTreeForCompanion and D.GetCurioNodeForCompanion
        and T.GetConfigIDByTreeID and T.GetNodeInfo and T.GetEntryInfo
        and T.GetDefinitionInfo) then
        return
    end

    local companionID = GetCurrentCompanionID()
    local traitTreeID = D.GetTraitTreeForCompanion(companionID)
    if not traitTreeID or traitTreeID == 0 then return end
    local configID = T.GetConfigIDByTreeID(traitTreeID)
    if not configID or configID == 0 then return end
    return D, T, companionID, configID
end

local function GetCurioSlot(D, T, companionID, configID, typeName)
    local curioType = Enum.CurioType[typeName]
    local nodeID = curioType and D.GetCurioNodeForCompanion(curioType, companionID)
    if not nodeID or nodeID == 0 then return end
    local nodeInfo = T.GetNodeInfo(configID, nodeID)
    local entryID = GetRecommendedEntryID(configID, nodeID, RECOMMENDED_CURIO_SPELL_BY_TYPE[typeName])
    local activeID = nodeInfo and nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
    return nodeID, entryID, activeID
end

local function ApplyRecommendedCurios(onlyType)
    if InCombatLockdown and InCombatLockdown() then return false, "Unavailable in combat" end
    local D, T, companionID, configID = GetCurioConfiguration()
    if not (D and T and T.SetSelection and T.IsReadyForCommit and T.CommitConfig) then
        return false, "Companion configuration unavailable"
    end

    local changed = false
    local unavailable = false
    for _, typeName in ipairs(CURIO_ORDER) do
        if not onlyType or onlyType == typeName then
            local nodeID, desiredID, activeID = GetCurioSlot(D, T, companionID, configID, typeName)
            if not nodeID or not desiredID then
                unavailable = true
            elseif desiredID ~= activeID then
                changed = T.SetSelection(configID, nodeID, desiredID) or changed
                if not changed then unavailable = true end
            end
        end
    end

    if changed then
        if not T.IsReadyForCommit() then return false, "Cannot commit this curio yet" end
        T.CommitConfig(configID)
        return true, "Recommendation applied"
    end
    if unavailable then return false, "Unlock this curio to apply it" end
    return true, "Already equipped"
end

local function EquipRecommendedCurios()
    if GetSettings().autoEquipBestDelveCurios ~= true then return end
    ApplyRecommendedCurios()
    if RefreshCurioPanel then C_Timer.After(0, RefreshCurioPanel) end
end

local function AddSolid(parent, point, relativeTo, relativePoint, x, y, width, height, r, g, b, a)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetPoint(point, relativeTo, relativePoint, x, y)
    texture:SetSize(width, height)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function SetPanelText(parent, size, r, g, b)
    local label = parent:CreateFontString(nil, "OVERLAY")
    local path = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")
    label:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    label:SetTextColor(r, g, b, 1)
    label:SetJustifyH("LEFT")
    return label
end

local function PositionCurioPanel()
    if not curioPanel then return end
    local host = DelvesCompanionConfigurationFrame
    if not host then return end
    local left, right = host:GetLeft(), host:GetRight()
    local screenWidth = UIParent:GetWidth()
    if not (left and right and screenWidth) then return end
    curioPanel:ClearAllPoints()
    local required = curioPanel:GetWidth() + 8
    if screenWidth - right >= required then
        curioPanel:SetPoint("TOPLEFT", host, "TOPRIGHT", 8, -12)
    elseif left >= required then
        curioPanel:SetPoint("TOPRIGHT", host, "TOPLEFT", -8, -12)
    else
        local bottom, top = host:GetBottom(), host:GetTop()
        local screenHeight = UIParent:GetHeight()
        if bottom and bottom >= curioPanel:GetHeight() + 8 then
            curioPanel:SetPoint("TOP", host, "BOTTOM", 0, -8)
        elseif top and screenHeight and screenHeight - top >= curioPanel:GetHeight() + 8 then
            curioPanel:SetPoint("BOTTOM", host, "TOP", 0, 8)
        else
            -- Very small displays cannot fit the panel beside the native UI.
            -- Keep it entirely on screen; the user can still close it.
            curioPanel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
        end
    end
end

local function CreateCurioPanel()
    if curioPanel then return curioPanel end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(322, 260)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        C_Timer.After(0, RefreshCurioPanel)
    end)
    frame:Hide()
    curioPanel = frame

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.025, 0.035, 0.045, 0.98)
    AddSolid(frame, "TOPLEFT", frame, "TOPLEFT", 0, 0, 322, 2, ACCENT_R, ACCENT_G, ACCENT_B, 1)
    AddSolid(frame, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, 322, 1, 0.26, 0.32, 0.34, 0.8)
    AddSolid(frame, "TOPLEFT", frame, "TOPLEFT", 0, -2, 1, 257, 0.26, 0.32, 0.34, 0.8)
    AddSolid(frame, "TOPRIGHT", frame, "TOPRIGHT", -1, -2, 1, 257, 0.26, 0.32, 0.34, 0.8)

    frame.title = SetPanelText(frame, 14, 0.92, 0.94, 0.93)
    frame.title:SetPoint("TOPLEFT", 16, -17)
    frame.title:SetText("CURIO HELPER")
    frame.context = SetPanelText(frame, 11, 0.62, 0.70, 0.72)
    frame.context:SetPoint("TOPLEFT", 16, -40)
    frame.context:SetWidth(286)
    frame.note = SetPanelText(frame, 10, 0.56, 0.67, 0.66)
    frame.note:SetPoint("TOPLEFT", 16, -59)
    frame.note:SetText("General-purpose picks shared across specs")

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -9, -10)
    close.label = SetPanelText(close, 17, 0.63, 0.68, 0.69)
    close.label:SetAllPoints()
    close.label:SetJustifyH("CENTER")
    close.label:SetText("×")
    close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self.label:SetTextColor(0.63, 0.68, 0.69, 1) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.rows = {}
    for index, typeName in ipairs(CURIO_ORDER) do
        local y = -84 - (index - 1) * 55
        AddSolid(frame, "TOPLEFT", frame, "TOPLEFT", 16, y, 290, 1, 1, 1, 1, 0.10)
        local row = CreateFrame("Frame", nil, frame)
        row:SetPoint("TOPLEFT", 16, y - 8)
        row:SetSize(290, 42)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(34, 34)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.type = SetPanelText(row, 9, ACCENT_R, ACCENT_G, ACCENT_B)
        row.type:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, 0)
        row.type:SetText(string.upper(typeName) .. " CURIO")
        row.name = SetPanelText(row, 11, 0.92, 0.94, 0.93)
        row.name:SetPoint("TOPLEFT", row.type, "BOTTOMLEFT", 0, -3)
        row.name:SetWidth(178)
        row.name:SetText(CURIO_FALLBACK_NAMES[typeName])
        row.button = CreateFrame("Button", nil, row)
        row.button:SetSize(61, 25)
        row.button:SetPoint("RIGHT", 0, 0)
        row.button.bg = row.button:CreateTexture(nil, "BACKGROUND")
        row.button.bg:SetAllPoints()
        row.button.label = SetPanelText(row.button, 10, 0.02, 0.06, 0.06)
        row.button.label:SetAllPoints()
        row.button.label:SetJustifyH("CENTER")
        row.button:SetScript("OnEnter", function(self)
            if self.enabled then self.bg:SetColorTexture(0.18, 0.95, 0.74, 1) end
        end)
        row.button:SetScript("OnLeave", function(self)
            if self.enabled then self.bg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1) end
        end)
        row.button:SetScript("OnClick", function()
            local ok, message = ApplyRecommendedCurios(typeName)
            frame.statusMessage = message
            frame.statusSuccess = ok
            if RefreshCurioPanel then C_Timer.After(0, RefreshCurioPanel) end
        end)
        frame.rows[typeName] = row
    end

    AddSolid(frame, "TOPLEFT", frame, "TOPLEFT", 16, -194, 290, 1, 1, 1, 1, 0.10)
    frame.auto = CreateFrame("Button", nil, frame)
    frame.auto:SetSize(290, 24)
    frame.auto:SetPoint("TOPLEFT", 16, -202)
    frame.auto.box = frame.auto:CreateTexture(nil, "ARTWORK")
    frame.auto.box:SetSize(14, 14)
    frame.auto.box:SetPoint("LEFT", 0, 0)
    frame.auto.check = SetPanelText(frame.auto, 11, 0.02, 0.06, 0.06)
    frame.auto.check:SetSize(14, 14)
    frame.auto.check:SetPoint("CENTER", frame.auto.box, "CENTER", 0, 0)
    frame.auto.check:SetJustifyH("CENTER")
    frame.auto.check:SetText("✓")
    frame.auto.label = SetPanelText(frame.auto, 11, 0.84, 0.88, 0.87)
    frame.auto.label:SetPoint("LEFT", frame.auto.box, "RIGHT", 9, 0)
    frame.auto.label:SetText("Auto apply when companion opens")
    frame.auto:SetScript("OnClick", function()
        local settings = GetSettings()
        settings.autoEquipBestDelveCurios = settings.autoEquipBestDelveCurios ~= true
        if settings.autoEquipBestDelveCurios then EquipRecommendedCurios() end
        RefreshCurioPanel()
    end)
    frame.status = SetPanelText(frame, 10, 0.56, 0.67, 0.66)
    frame.status:SetPoint("BOTTOMLEFT", 16, 12)
    frame.status:SetWidth(290)
    return frame
end

RefreshCurioPanel = function()
    if not curioPanel or not curioPanel:IsShown() then return end
    local frame = curioPanel
    local specIndex = GetSpecialization and GetSpecialization()
    local specName
    if specIndex and GetSpecializationInfo then specName = select(2, GetSpecializationInfo(specIndex)) end
    local className = UnitClass and UnitClass("player")
    frame.context:SetText((specName or className or "Current character") .. (specName and className and (" " .. className) or ""))
    local inCombat = InCombatLockdown and InCombatLockdown()
    local D, T, companionID, configID
    -- Do not inspect trait selections in combat; Retail can mark combat data
    -- secret, and the helper has no usable action until combat ends anyway.
    if not inCombat then D, T, companionID, configID = GetCurioConfiguration() end
    for _, typeName in ipairs(CURIO_ORDER) do
        local row = frame.rows[typeName]
        local spellID = RECOMMENDED_CURIO_SPELL_BY_TYPE[typeName]
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        row.name:SetText((spellInfo and spellInfo.name) or CURIO_FALLBACK_NAMES[typeName])
        row.icon:SetTexture((spellInfo and spellInfo.iconID) or 134400)
        local nodeID, desiredID, activeID
        if D and T then nodeID, desiredID, activeID = GetCurioSlot(D, T, companionID, configID, typeName) end
        local equipped = desiredID and activeID == desiredID
        local canApply = nodeID and desiredID and not equipped and not inCombat
        row.button.enabled = canApply == true
        row.button:SetEnabled(canApply == true)
        row.button.bg:SetColorTexture(canApply and ACCENT_R or 0.16, canApply and ACCENT_G or 0.20,
            canApply and ACCENT_B or 0.21, 1)
        row.button.label:SetText(equipped and "EQUIPPED" or (canApply and "APPLY" or "N/A"))
        row.button.label:SetTextColor(canApply and 0.02 or 0.61, canApply and 0.06 or 0.68,
            canApply and 0.06 or 0.68, 1)
    end
    local auto = GetSettings().autoEquipBestDelveCurios == true
    frame.auto.box:SetColorTexture(auto and ACCENT_R or 0.15, auto and ACCENT_G or 0.20,
        auto and ACCENT_B or 0.21, 1)
    if auto then frame.auto.check:Show() else frame.auto.check:Hide() end
    frame.auto.label:SetTextColor(auto and 0.93 or 0.72, auto and 0.96 or 0.78,
        auto and 0.95 or 0.78, 1)
    frame.status:SetText(inCombat and "Apply is available out of combat" or (frame.statusMessage or ""))
    local ok = frame.statusSuccess
    frame.status:SetTextColor(ok and ACCENT_R or 0.95, ok and ACCENT_G or 0.62,
        ok and ACCENT_B or 0.40, 1)
end

local function ShowCurioPanel()
    if GetSettings().showDelveCurioHelper == false then return end
    if not (DelvesCompanionConfigurationFrame and DelvesCompanionConfigurationFrame:IsShown()) then return end
    local frame = CreateCurioPanel()
    PositionCurioPanel()
    frame.statusMessage = nil
    frame.statusSuccess = nil
    frame:Show()
    RefreshCurioPanel()
end

local function HookDelvesCompanionFrame()
    if curioHookInstalled or not DelvesCompanionConfigurationFrame then return end
    curioHookInstalled = true

    DelvesCompanionConfigurationFrame:HookScript("OnShow", function()
        -- Blizzard's OnShow refreshes the trait configuration first.  Deferring
        -- one frame lets the same current configuration be read without touching
        -- the secure companion UI itself.
        C_Timer.After(0, function()
            EquipRecommendedCurios()
            ShowCurioPanel()
        end)
        -- The third-party OnShow creates its button too; defer one frame so
        -- this runs after that construction regardless of addon load order.
        C_Timer.After(0, SkinValeeraMuterButton)
    end)
    DelvesCompanionConfigurationFrame:HookScript("OnHide", function()
        if curioPanel then curioPanel:Hide() end
    end)
end

function addon.BuildAdventurePage(parent, yOffset)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return yOffset end

    local y = yOffset
    local _, h

    -- Build only populated feature sections, in activity order. Each feature
    -- owns its native EUI header and the height of its controls.
    if addon.BuildSoireeOptions then y = addon.BuildSoireeOptions(parent, y) end

    _, h = W:SectionHeader(parent, "MOUNTING", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Auto Mount Out of Combat",
            tooltip = "When unmounted and out of combat, try to mount after three seconds to leave time for looting. Wait until movement, looting, and spellcasts stop, then allow at least one quiet second. Dismounting within five seconds of mounting or interrupting a mount cast pauses auto-mounting until you mount again or finish another combat. This is off by default, and mounting can still fail where the game forbids it.",
            getValue = function()
                return GetSettings().autoMountAfterCombat == true
            end,
            setValue = function(value)
                GetSettings().autoMountAfterCombat = value == true
                if addon.RefreshAutoMount then addon.RefreshAutoMount() end
            end,
        },
        {
            type = "dropdown",
            text = "Mount Picker",
            values = {
                auto = "Auto: LiteMount Button 1 / WoW",
                litemount = "LiteMount Button 1 Rules",
                wow = "WoW Random Favorite",
            },
            order = { "auto", "litemount", "wow" },
            tooltip = "Auto evaluates LiteMount Button 1's active rules when LiteMount is loaded, otherwise it uses WoW's random favorite. LiteMount Button 1 Rules also falls back to WoW if LiteMount is absent. A plain journal-mount result can be summoned automatically; forms, items, macros, and actions needing a secure click are skipped rather than replaced with the wrong mount.",
            getValue = function()
                return GetSettings().autoMountProvider
            end,
            setValue = function(value)
                if value == "litemount" or value == "wow" then
                    GetSettings().autoMountProvider = value
                else
                    GetSettings().autoMountProvider = "auto"
                end
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "AUTO-MOUNT LOCATIONS", y); y = y - h
    local function MountLocationControl(info)
        return {
            type = "toggle",
            text = info.label,
            tooltip = info.tooltip,
            getValue = function()
                local locations = GetSettings().autoMountLocations
                return type(locations) ~= "table" or locations[info.key] ~= false
            end,
            setValue = function(value)
                local settings = GetSettings()
                if type(settings.autoMountLocations) ~= "table" then settings.autoMountLocations = {} end
                settings.autoMountLocations[info.key] = value == true
            end,
        }
    end
    local locationTypes = addon.AutoMountLocationTypes or {}
    for index = 1, #locationTypes, 2 do
        _, h = W:DualRow(parent, y,
            MountLocationControl(locationTypes[index]),
            locationTypes[index + 1] and MountLocationControl(locationTypes[index + 1]) or nil
        ); y = y - h
    end

    _, h = W:SectionHeader(parent, "FLIGHT STYLE INDICATOR", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Show Flight Style Indicator",
            tooltip = "Show the illustrated Skyriding or Steady Flight emblem. Choose its original size or a much smaller version with the same art and animation. Hold Shift and drag either layout to move it. An interrupted Switch Flight Style cast restores the original state. Off by default on public installs.",
            getValue = function()
                return GetSettings().flightIndicatorEnabled == true
            end,
            setValue = function(value)
                GetSettings().flightIndicatorEnabled = value == true
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        },
        {
            type = "dropdown",
            text = "Indicator Layout",
            values = { emblem = "Full Emblem", compact = "Rounded Compact" },
            order = { "emblem", "compact" },
            tooltip = "Rounded Compact uses two illustrated flight-state panels with integrated lettering and a raised creature medallion. Each layout has its own Shift-drag position. Your local install starts compact; public installs retain the full emblem when enabled.",
            getValue = function()
                return GetSettings().flightIndicatorLayout
            end,
            setValue = function(value)
                GetSettings().flightIndicatorLayout = value
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        {
            type = "dropdown",
            text = "Indicator Size",
            values = { small = "Small", medium = "Medium", large = "Large" },
            order = { "small", "medium", "large" },
            tooltip = "Size of the selected flight-indicator layout.",
            getValue = function()
                return GetSettings().flightIndicatorSize
            end,
            setValue = function(value)
                GetSettings().flightIndicatorSize = value
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        },
        {
            type = "toggle",
            text = "Skyriding Charges",
            tooltip = "Show shared Surge Forward / Skyward Ascent charges as jewels around the full emblem or below the compact panel lettering. The next empty jewel fills as its charge recovers. Charges hide in Steady Flight and whenever charge data is unavailable.",
            getValue = function()
                return GetSettings().flightIndicatorCharges ~= false
            end,
            setValue = function(value)
                GetSettings().flightIndicatorCharges = value == true
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Cast Progress",
            tooltip = "Show cast progress around the full emblem or beneath the compact panel lettering. It vanishes when the cast completes or is interrupted.",
            getValue = function()
                return GetSettings().flightIndicatorCastProgress ~= false
            end,
            setValue = function(value)
                GetSettings().flightIndicatorCastProgress = value == true
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        },
        {
            type = "dropdown",
            text = "Compact Panel Theme",
            values = { classic = "Steady / Skyride", alternate = "Cruise / Surge" },
            order = { "classic", "alternate" },
            tooltip = "Choose the illustrated wording on the short flight-state panels. This applies only to Rounded Compact and preserves the full emblem.",
            getValue = function()
                return GetSettings().flightIndicatorCompactTheme
            end,
            setValue = function(value)
                GetSettings().flightIndicatorCompactTheme = value
                if addon.RefreshFlightIndicator then addon.RefreshFlightIndicator() end
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "RANDOM TRANSMOG", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Random Saved Outfit",
            tooltip = "Periodically switch among your saved, unlocked outfits. Never creates or edits an outfit, spends gold, switches in combat, or overrides a locked outfit. Waits while moving, casting, or editing transmog. Manual outfit changes restart the timer. Off by default on public installs.",
            getValue = function()
                return GetSettings().randomTransmogEnabled == true
            end,
            setValue = function(value)
                GetSettings().randomTransmogEnabled = value == true
                if addon.RefreshRandomTransmog then addon.RefreshRandomTransmog() end
            end,
        },
        {
            type = "dropdown",
            text = "Change Outfit Every",
            values = { ["5"] = "5 Minutes", ["15"] = "15 Minutes", ["30"] = "30 Minutes",
                ["60"] = "1 Hour", ["120"] = "2 Hours", ["240"] = "4 Hours" },
            order = { "5", "15", "30", "60", "120", "240" },
            tooltip = "Time between attempts, beginning when enabled or after an outfit change. Unsafe conditions defer the attempt without rapid retries.",
            getValue = function()
                return GetSettings().randomTransmogInterval
            end,
            setValue = function(value)
                GetSettings().randomTransmogInterval = value
                if addon.RefreshRandomTransmog then addon.RefreshRandomTransmog() end
            end,
        }
    ); y = y - h

    _, h = W:SectionHeader(parent, "DELVE COMPANION", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Show Curio Helper",
            tooltip = "Show an EllesmereUI-style Curio recommendation panel when you open Trusty Delve Companion. Apply each recommended curio there, or enable Auto Apply in the panel.",
            getValue = function()
                return GetSettings().showDelveCurioHelper ~= false
            end,
            setValue = function(value)
                GetSettings().showDelveCurioHelper = value == true
                if value ~= true and curioPanel then curioPanel:Hide() end
                if value == true then ShowCurioPanel() end
            end,
        },
        {
            type = "toggle",
            text = "Mute Valeera Voice Lines",
            tooltip = "Mute Valeera Sanguinar's known Delve companion voice files. This leaves other NPC dialogue, game sounds, and speech bubbles alone.",
            getValue = function()
                return GetSettings().muteValeeraVoiceLines == true
            end,
            setValue = function(value)
                GetSettings().muteValeeraVoiceLines = value == true
                if addon.RefreshAdventureFeatures then addon.RefreshAdventureFeatures() end
            end,
        }
    ); y = y - h

    -- Buff Check belongs with group and instance preparation, not as another
    -- top-level configuration page.
    if addon.BuildBuffCheckPage then y = -addon.BuildBuffCheckPage(parent, y) end

    return math.abs(y)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_DelvesCompanionConfiguration" then
        HookDelvesCompanionFrame()
    elseif event == "ADDON_LOADED" and name == "ZamestoTV_Delves" then
        C_Timer.After(0, SkinValeeraMuterButton)
    elseif event == "PLAYER_LOGIN" then
        addon.RefreshAdventureFeatures()
        HookDelvesCompanionFrame()
    end
end)
