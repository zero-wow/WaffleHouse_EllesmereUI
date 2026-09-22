local _, addon = ...
if type(addon) ~= "table" then return end

-- Repair saved layout data through the C API, never the live BuffFrame or
-- Edit Mode manager's layout tables. Native frame methods can taint aura code.
local pending = false
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Report(message)
    print("|cff0dd1a0Waffle House:|r " .. message)
end

local function DefaultAnchor()
    -- Blizzard's 12.0.5 BuffFrame preset: clear of the upper-right minimap.
    return { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = -255, offsetY = -10 }
end

local function SameAnchor(anchor, expected)
    if type(anchor) ~= "table" then return false end
    for _, key in ipairs({ "point", "relativeTo", "relativePoint", "offsetX", "offsetY" }) do
        if anchor[key] ~= expected[key] then return false end
    end
    return true
end

function addon.RepairBuffFrameAnchor(verbose)
    local function Stop(message)
        if verbose then Report(message) end
        return false
    end
    if pending then return Stop("A buff anchor repair is already pending.") end
    if InCombatLockdown and InCombatLockdown() then return Stop("Leave combat, then use /whbuffrepair.") end
    local manager = EditModeManagerFrame
    if manager and ((manager.IsEditModeActive and manager:IsEditModeActive())
        or (manager.HasActiveChanges and manager:HasActiveChanges())) then
        return Stop("Save or discard your Edit Mode changes and close Edit Mode, then use /whbuffrepair.")
    end
    if not (C_EditMode and type(C_EditMode.GetLayouts) == "function" and type(C_EditMode.SaveLayouts) == "function"
        and EditModePresetLayoutManager and type(EditModePresetLayoutManager.GetCopyOfPresetLayouts) == "function"
        and Enum and Enum.EditModeSystem and Enum.EditModeAuraFrameSystemIndices and Enum.EditModeLayoutType
        and type(addon.GetSettings) == "function") then
        return Stop("Blizzard's layout repair API is not available. No layouts were changed.")
    end
    local auraSystem, buffIndex = Enum.EditModeSystem.AuraFrame, Enum.EditModeAuraFrameSystemIndices.BuffFrame
    if auraSystem == nil or buffIndex == nil then return Stop("Unsupported buff layout format. No layouts were changed.") end
    local ok, original = pcall(C_EditMode.GetLayouts)
    if not ok or type(original) ~= "table" or type(original.layouts) ~= "table" then
        return Stop("Could not read saved layouts. No layouts were changed.")
    end
    local updated, changes, skipped = Copy(original), {}, 0
    for layoutIndex, layout in ipairs(updated.layouts) do
        if layout.layoutType ~= Enum.EditModeLayoutType.Preset then
            for systemIndex, system in ipairs(layout.systems or {}) do
                if system.system == auraSystem and system.systemIndex == buffIndex
                    and system.anchorInfo and system.anchorInfo.relativeTo == "PlayerBuffsMover" then
                    -- A valid second anchor could constrain a stretched frame;
                    -- do not silently discard it or guess at that layout.
                    if system.anchorInfo2 ~= nil then
                        skipped = skipped + 1
                    else
                        system.anchorInfo = DefaultAnchor()
                        changes[#changes + 1] = { layoutIndex = layoutIndex, systemIndex = systemIndex,
                            layoutName = layout.layoutName, layoutType = layout.layoutType }
                    end
                end
            end
        end
    end
    if #changes == 0 then
        return Stop(skipped > 0 and "The buff layout has a second anchor; it was preserved and needs a separate repair."
            or "No saved Buff Frame anchor points to PlayerBuffsMover. No layouts were changed.")
    end

    -- GetLayouts returns saved layouts without the built-in presets. Mirror
    -- Blizzard's UpdateLayoutInfo augmentation before passing data to SaveLayouts.
    local presetsOK, presets = pcall(EditModePresetLayoutManager.GetCopyOfPresetLayouts, EditModePresetLayoutManager)
    if not presetsOK or type(presets) ~= "table" or #presets == 0 then
        return Stop("Could not read Blizzard's preset layouts. No layouts were changed.")
    end
    local saveInfo = Copy(updated)
    saveInfo.layouts = Copy(presets)
    for _, layout in ipairs(updated.layouts) do saveInfo.layouts[#saveInfo.layouts + 1] = layout end
    local root = addon.GetSettings()
    if type(root) ~= "table" then return Stop("Could not back up the layouts. No layouts were changed.") end
    -- Retain the first pre-repair snapshot even if a save fails or is retried.
    if root.buffFrameAnchorRepairBackup == nil then root.buffFrameAnchorRepairBackup = Copy(original) end
    pending = true
    local saved = pcall(C_EditMode.SaveLayouts, saveInfo)
    if not saved then
        pending = false
        Report("Blizzard rejected the buff anchor repair. The original layout backup is retained; no retry loop was started.")
        return false
    end
    C_Timer.After(0.5, function()
        pending = false
        local readOK, current = pcall(C_EditMode.GetLayouts)
        local confirmed = readOK and type(current) == "table" and type(current.layouts) == "table"
        if confirmed then
            for _, change in ipairs(changes) do
                local found = false
                for _, layout in ipairs(current.layouts) do
                    if layout.layoutName == change.layoutName and layout.layoutType == change.layoutType then
                        for _, system in ipairs(layout.systems or {}) do
                            if system.system == auraSystem and system.systemIndex == buffIndex
                                and SameAnchor(system.anchorInfo, DefaultAnchor()) then found = true end
                        end
                    end
                end
                if not found then
                    confirmed = false
                    break
                end
            end
        end
        if not confirmed then
            Report("Buff anchor repair was submitted, but Blizzard has not confirmed it. Use /reload, then /whbuffrepair to check again.")
            return
        end
        -- Saving confirms persisted layout data, not the live frame position.
        -- A same-index SetActiveLayout request is not a verified frame refresh.
        Report("Repaired " .. #changes .. " saved buff anchor(s). Use /reload to apply the upper-right position."
            .. (skipped > 0 and " Layouts with a second anchor were left unchanged." or ""))
    end)
    return true
end

SLASH_WAFFLEHOUSEBUFFREPAIR1 = "/whbuffrepair"
SlashCmdList.WAFFLEHOUSEBUFFREPAIR = function() addon.RepairBuffFrameAnchor(true) end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- One startup check, no polling or recurring layout ownership.
    C_Timer.After(1, function() addon.RepairBuffFrameAnchor(false) end)
end)
