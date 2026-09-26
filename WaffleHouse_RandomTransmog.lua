local _, addon = ...

local ART_BASE = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\RandomTransmog\\"
local DEFAULT_MINUTES = 30
local MIN_SIZE, MAX_SIZE, SIZE_STEP = 16, 160, 4
local button
local timerStartedAt
local timerDuration
local lastSelectionReason

local function IsPlain(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Settings()
    return addon.GetSettings and addon.GetSettings()
end

local function Report(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r " .. message)
    end
end

local function IntervalSeconds(settings)
    local minutes = tonumber(settings.randomTransmogInterval) or DEFAULT_MINUTES
    if minutes ~= 5 and minutes ~= 15 and minutes ~= 30
        and minutes ~= 60 and minutes ~= 120 and minutes ~= 240 then
        minutes = DEFAULT_MINUTES
    end
    return minutes * 60
end

-- The outfit C API is protected. Never call ChangeDisplayedOutfit from addon
-- Lua (not even from OnClick or pcall). Only a hardware click on the secure
-- outfit action below may make the change. Its index is prepared beforehand.
local function ChooseOutfit()
    local outfits = C_TransmogOutfitInfo
    if not (outfits and type(outfits.GetOutfitsInfo) == "function"
        and type(outfits.GetActiveOutfitID) == "function"
        and type(outfits.IsLockedOutfit) == "function") then return nil, "Outfit API is unavailable." end
    if type(outfits.IsTransmogEnabled) == "function" and not outfits.IsTransmogEnabled() then
        return nil, "Transmog is disabled for this character."
    end
    local activeID = outfits.GetActiveOutfitID()
    if not IsPlain(activeID) then return nil, "Active outfit is unavailable." end
    if type(activeID) == "number" and activeID > 0 then
        local locked = outfits.IsLockedOutfit(activeID)
        if not IsPlain(locked) then return nil, "Active outfit lock is unavailable." end
        if locked == true then return nil, "Current outfit is locked; unlock it in Transmog to switch." end
    end
    local entries = outfits.GetOutfitsInfo()
    if not IsPlain(entries) or type(entries) ~= "table" then return nil, "Saved outfit list is unavailable." end
    local candidates = {}
    local total, noIndex, lockedCount, disabledCount = 0, 0, 0, 0
    for position, entry in ipairs(entries) do
        if IsPlain(entry) and type(entry) == "table" then
            total = total + 1
            local id = entry.outfitID
            local index = entry.playerFacingOutfitIndex
            local name = entry.name
            local disabled = entry.isDisabled
            local eventOutfit = entry.isEventOutfit
            if IsPlain(id) and type(id) == "number" and id > 0
                and not (IsPlain(index) and type(index) == "number" and index > 0)
                and type(outfits.GetOutfitInfoByPlayerFacingIndex) == "function" then
                -- Never assume the array position is a player-facing index: event
                -- outfits can occupy entries without a selectable /outfit slot.
                local lookupOK, indexed = pcall(outfits.GetOutfitInfoByPlayerFacingIndex, position)
                if lookupOK and IsPlain(indexed) and type(indexed) == "table"
                    and IsPlain(indexed.outfitID) and indexed.outfitID == id then
                    index = position
                end
            end
            if IsPlain(id) and IsPlain(index) and IsPlain(name)
                and IsPlain(disabled) and IsPlain(eventOutfit)
                and type(id) == "number" and id > 0 and id ~= activeID
                and type(index) == "number" and index > 0
                and type(name) == "string" and name ~= ""
                and disabled ~= true and eventOutfit ~= true then
                local locked = outfits.IsLockedOutfit(id)
                if IsPlain(locked) and locked ~= true then
                    candidates[#candidates + 1] = { id = id, index = index, name = name }
                else
                    lockedCount = lockedCount + 1
                end
            elseif IsPlain(id) and type(id) == "number" and id ~= activeID then
                if not (IsPlain(index) and type(index) == "number" and index > 0) then
                    noIndex = noIndex + 1
                else
                    disabledCount = disabledCount + 1
                end
            end
        end
    end
    if #candidates > 0 then return candidates[math.random(#candidates)], nil, #candidates end
    return nil, ("No selectable saved outfit (listed %d, missing index %d, locked %d, unavailable %d).")
        :format(total, noIndex, lockedCount, disabledCount), 0
end

local function PrepareButton()
    if not button or InCombatLockdown() then return false end
    local ok, chosen, reason, count = pcall(ChooseOutfit)
    if not ok then chosen, reason, count = nil, "Outfit selection failed; use /wh transmog status.", 0 end
    -- Set both attributes outside combat. A protected click reads them without
    -- running any addon code in its secure dispatch path.
    button:SetAttribute("type", chosen and "outfit" or nil)
    button:SetAttribute("outfit-index", chosen and chosen.index or nil)
    button.queuedOutfitID = chosen and chosen.id or nil
    button.queuedOutfitName = chosen and chosen.name or nil
    button.queuedOutfitIndex = chosen and chosen.index or nil
    button.selectionReason = reason
    button.candidateCount = count or 0
    lastSelectionReason = reason
    return chosen ~= nil
end

local function RenderProgress(progress)
    if not button then return end
    local frame = math.max(0, math.min(63, math.floor(progress * 63 + 0.5)))
    if frame == button.lastFrame then return end
    button.lastFrame = frame
    local col, row = frame % 8, math.floor(frame / 8)
    button.fill:SetTexCoord(col / 8, (col + 1) / 8, row / 8, (row + 1) / 8)
    button.fill:SetAlpha(frame > 0 and 1 or 0)
    local stages = { 0.01, 0.25, 0.5, 0.75 }
    for index, gem in ipairs(button.gems) do
        gem:SetAlpha(progress >= stages[index] and 1 or 0)
    end
end

local function UpdateButton(_, elapsed)
    if button.manualProgress then
        button.manualElapsed = button.manualElapsed + elapsed
        if button.manualConfirmed then
            button.manualFill = math.min(1, button.manualFill + elapsed * 1.8)
        else
            button.manualFill = math.min(0.86, button.manualFill + elapsed * 0.65)
        end
        RenderProgress(button.manualFill)
        if (button.manualConfirmed and button.manualElapsed >= 1.2 and button.manualFill >= 1)
            or button.manualElapsed >= 5 then
            button.manualProgress = false
            button.lastFrame = nil
        end
        return
    end
    button.updateElapsed = (button.updateElapsed or 0) + elapsed
    if button.updateElapsed < 0.2 then return end
    button.updateElapsed = 0
    local settings = Settings()
    local progress = 0
    if settings and settings.randomTransmogEnabled == true and timerStartedAt and timerDuration then
        progress = math.max(0, math.min(1, (GetTime() - timerStartedAt) / timerDuration))
    end
    RenderProgress(progress)
end

local function ButtonSize(settings)
    local size = tonumber(settings.randomTransmogButtonSize) or 64
    return math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(size + 0.5)))
end

local function PositionButton(settings)
    if not button then return end
    local size = ButtonSize(settings)
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(settings.randomTransmogButtonX) or 260,
        tonumber(settings.randomTransmogButtonY) or -160)
end

local function CreateButton()
    if button or not UIParent then return end
    button = CreateFrame("Button", "WaffleHouseRandomTransmogButton", UIParent, "SecureActionButtonTemplate")
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    -- Use mouse-up regardless of the global action-button CVar.
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:EnableMouseWheel(true)
    button:SetAttribute("action", "change")
    button:SetAttribute("shift-type1", "") -- Shift-drag must never apply an outfit.

    button.back = button:CreateTexture(nil, "ARTWORK", nil, 0)
    button.back:SetAllPoints()
    button.back:SetTexture(ART_BASE .. "button-back.png")
    button.fill = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.fill:SetAllPoints()
    button.fill:SetTexture(ART_BASE .. "button-fill-atlas.png")
    button.fill:SetAlpha(0)
    button.front = button:CreateTexture(nil, "ARTWORK", nil, 2)
    button.front:SetAllPoints()
    button.front:SetTexture(ART_BASE .. "button-front.png")
    button.gems = {}
    for index = 1, 4 do
        local gem = button:CreateTexture(nil, "OVERLAY")
        gem:SetAllPoints()
        gem:SetTexture(ART_BASE .. "button-gem.png")
        gem:SetRotation((index - 1) * math.pi / 2)
        gem:SetAlpha(0)
        button.gems[index] = gem
    end

    button:HookScript("PostClick", function(self, mouseButton, down)
        if mouseButton ~= "LeftButton" or down or IsShiftKeyDown() then return end
        self.clickCount = (self.clickCount or 0) + 1
        self.lastClickAt = GetTime()
        if not self.queuedOutfitID then
            Report(self.selectionReason or "No saved outfit is ready. Use /wh transmog status.")
            return
        end
        local requestedID, requestedIndex = self.queuedOutfitID, self.queuedOutfitIndex
        self.manualProgress = true
        self.manualElapsed = 0
        self.manualFill = 0
        self.manualConfirmed = self.lastConfirmedAt
            and GetTime() - self.lastConfirmedAt < 0.5
            and self.lastConfirmedOutfitID == self.queuedOutfitID or false
        self.lastFrame = nil
        C_Timer.After(3, function()
            if not self.manualConfirmed and not InCombatLockdown() then
                local ok, activeID = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
                if not ok or not IsPlain(activeID) or activeID ~= requestedID then
                    Report(("Outfit did not change (queued slot %s). Use /wh transmog status.")
                        :format(tostring(requestedIndex)))
                end
            end
            if not InCombatLockdown() then PrepareButton() end
        end)
    end)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if not (x and y and parentX and parentY) then return end
        local settings = Settings()
        if not settings then return end
        settings.randomTransmogButtonX = math.floor(x - parentX + 0.5)
        settings.randomTransmogButtonY = math.floor(y - parentY + 0.5)
        PositionButton(settings)
    end)
    button:SetScript("OnMouseWheel", function(self, direction)
        if not IsControlKeyDown() or direction == 0 or InCombatLockdown() then return end
        local settings = Settings()
        if not settings then return end
        settings.randomTransmogButtonSize = math.max(MIN_SIZE, math.min(MAX_SIZE,
            ButtonSize(settings) + (direction > 0 and SIZE_STEP or -SIZE_STEP)))
        PositionButton(settings)
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Random Saved Outfit")
        GameTooltip:AddLine(self.queuedOutfitName
            and ("Click to switch to " .. self.queuedOutfitName .. ".")
            or (self.selectionReason or "No other unlocked outfit is ready."), 0.8, 0.85, 0.9)
        GameTooltip:AddLine("Shift-drag to move. Ctrl+wheel to resize (16–160).", 0.6, 0.85, 1)
        local settings = Settings()
        if settings and settings.randomTransmogEnabled == true and timerStartedAt and timerDuration then
            local remaining = math.max(0, math.ceil(timerDuration - (GetTime() - timerStartedAt)))
            GameTooltip:AddLine(remaining == 0 and "Outfit change reminder ready—click to switch."
                or ("Reminder in " .. math.ceil(remaining / 60) .. " min."), 0.4, 0.9, 1)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnUpdate", UpdateButton)
end

function addon.RefreshRandomTransmogButton()
    local settings = Settings()
    if not settings or settings.randomTransmogButtonEnabled ~= true then
        if button and not InCombatLockdown() then
            if UnregisterStateDriver and button.visibilityDriverRegistered then
                UnregisterStateDriver(button, "visibility")
                button.visibilityDriverRegistered = false
            end
            button:Hide()
        end
        return
    end
    if InCombatLockdown() then return end
    CreateButton()
    if not button then return end
    PositionButton(settings)
    if RegisterStateDriver and not button.visibilityDriverRegistered then
        RegisterStateDriver(button, "visibility", "[combat] hide; show")
        button.visibilityDriverRegistered = true
    end
    button:Show()
    PrepareButton()
end

-- Chat cannot provide the protected hardware click. It can expose and arm
-- the real secure button so the next physical click changes the outfit.
function addon.RandomizeTransmogNow()
    local settings = Settings()
    if not settings then return false end
    if InCombatLockdown() then
        Report("Wait until combat ends, then click the wardrobe button.")
        return false
    end
    if settings.randomTransmogButtonEnabled ~= true then
        settings.randomTransmogButtonEnabled = true
        addon.RefreshRandomTransmogButton()
    end
    if not PrepareButton() then
        Report(lastSelectionReason or "No other unlocked saved outfit is available.")
        return false
    end
    Report("Random outfit is ready. Click the wardrobe button to switch.")
    return true
end

function addon.ReportRandomTransmogStatus()
    local settings = Settings()
    if not settings then Report("Settings are not ready."); return end
    if not button then
        Report("Outfit button is not created. Enable Show Instant Outfit Button in /wh transmog.")
        return
    end
    if not InCombatLockdown() then PrepareButton() end
    Report(("Button %s; combat %s; action %s; candidates %d; queued %s (slot %s).")
        :format(button:IsShown() and "shown" or "hidden", InCombatLockdown() and "yes" or "no",
            tostring(button:GetAttribute("type")), button.candidateCount or 0,
            tostring(button.queuedOutfitName), tostring(button:GetAttribute("outfit-index"))))
    Report(("Button clicks seen: %d; last outfit-change event: %s.")
        :format(button.clickCount or 0, button.lastConfirmedOutfitID and tostring(button.lastConfirmedOutfitID) or "none"))
    if button.selectionReason then Report(button.selectionReason) end
end

function addon.RefreshRandomTransmog()
    local settings = Settings()
    if settings and settings.randomTransmogEnabled == true then
        timerStartedAt = GetTime()
        timerDuration = IntervalSeconds(settings)
    else
        timerStartedAt, timerDuration = nil, nil
    end
    if button then button.lastFrame = nil end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
events:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        addon.RefreshRandomTransmog()
        addon.RefreshRandomTransmogButton()
    elseif event == "PLAYER_REGEN_ENABLED" then
        addon.RefreshRandomTransmogButton()
    elseif event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" then
        if button then
            button.lastConfirmedAt = GetTime()
            local ok, activeID = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
            button.lastConfirmedOutfitID = ok and IsPlain(activeID) and activeID or nil
            if button.manualProgress and button.lastConfirmedOutfitID == button.queuedOutfitID then
                button.manualConfirmed = true
            end
        end
        addon.RefreshRandomTransmog()
        C_Timer.After(0, PrepareButton)
    elseif event == "TRANSMOG_OUTFITS_CHANGED" then
        C_Timer.After(0, PrepareButton)
    end
end)
