local _, addon = ...

local generation = 0
local RETRY_SECONDS = 30
local DEFAULT_MINUTES = 30
local BUTTON_ART = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\RandomTransmog\\random-outfit-button.png"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TICK_COUNT = 32
local button
local pendingButtonID
local timerStartedAt
local timerDuration

local function IsPlain(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IntervalSeconds(settings)
    local minutes = tonumber(settings.randomTransmogInterval) or DEFAULT_MINUTES
    if minutes ~= 5 and minutes ~= 15 and minutes ~= 30
        and minutes ~= 60 and minutes ~= 120 and minutes ~= 240 then
        minutes = DEFAULT_MINUTES
    end
    return minutes * 60
end

local function CanSwitch()
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return false end
    if UnitOnTaxi("player") or UnitInVehicle("player") or GetUnitSpeed("player") > 0 then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if TransmogFrame and TransmogFrame:IsShown() then return false end
    local transmog = C_Transmog
    if transmog and type(transmog.IsAtTransmogNPC) == "function"
        and transmog.IsAtTransmogNPC() then return false end
    local outfits = C_TransmogOutfitInfo
    if not (outfits and type(outfits.GetOutfitsInfo) == "function"
        and type(outfits.GetActiveOutfitID) == "function"
        and type(outfits.IsLockedOutfit) == "function"
        and type(outfits.ChangeDisplayedOutfit) == "function"
        and Enum and Enum.TransmogSituationTrigger and Enum.TransmogSituationTrigger.Manual) then
        return false
    end
    if type(outfits.IsTransmogEnabled) == "function" and not outfits.IsTransmogEnabled() then return false end
    if type(outfits.HasPendingOutfitTransmogs) == "function"
        and outfits.HasPendingOutfitTransmogs() then return false end
    if type(outfits.InTransmogEvent) == "function" and outfits.InTransmogEvent() then return false end
    return true
end

local function SwitchToRandomOutfit(beforeApply)
    local outfits = C_TransmogOutfitInfo
    local activeID = outfits.GetActiveOutfitID()
    if not IsPlain(activeID) then return false end
    if type(activeID) == "number" and activeID > 0 then
        local activeLocked = outfits.IsLockedOutfit(activeID)
        if not IsPlain(activeLocked) or activeLocked ~= false then return false end
    end

    local entries = outfits.GetOutfitsInfo()
    if not IsPlain(entries) or type(entries) ~= "table" then return false end
    local candidates = {}
    for _, entry in pairs(entries) do
        if IsPlain(entry) and type(entry) == "table" then
            local id = entry.outfitID
            local name = entry.name
            local disabled = entry.isDisabled
            local eventOutfit = entry.isEventOutfit
            if IsPlain(id) and IsPlain(name) and IsPlain(disabled) and IsPlain(eventOutfit)
                and type(id) == "number" and id > 0 and id ~= activeID
                and type(name) == "string" and name ~= ""
                and disabled == false and eventOutfit == false then
                local locked = outfits.IsLockedOutfit(id)
                if IsPlain(locked) and locked == false then
                    candidates[#candidates + 1] = id
                end
            end
        end
    end
    if #candidates < 1 then return false end
    local chosenID = candidates[math.random(#candidates)]
    if beforeApply then beforeApply(chosenID) end
    -- A manual trigger avoids changing situation rules; false prevents the
    -- game's same-outfit toggle from clearing an outfit. No save/commit call.
    outfits.ChangeDisplayedOutfit(chosenID, Enum.TransmogSituationTrigger.Manual, false, false)
    return true, chosenID
end

local function Report(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r " .. message)
    end
end

local function RenderButtonProgress(progress, alpha)
    if not button then return end
    local lit = math.floor(progress * TICK_COUNT + 0.5)
    if lit == button.lastLit and alpha == button.lastAlpha then return end
    button.lastLit, button.lastAlpha = lit, alpha
    for index, tick in ipairs(button.ticks) do
        tick:SetAlpha(index <= lit and alpha or 0)
    end
end

local function ResetButtonProgress()
    if not button then return end
    button.progress = 0
    button.elapsed = 0
    button.completed = false
    button.manualProgress = false
    button.lastLit, button.lastAlpha = nil, nil
end

local function AnimateButton(_, elapsed)
    if button.manualProgress then
        button.elapsed = button.elapsed + elapsed
        local target = button.completed and 1 or math.min(0.88, button.elapsed / 1.5 * 0.88)
        button.progress = math.min(target, button.progress + elapsed * (button.completed and 1.6 or 0.7))
        RenderButtonProgress(button.progress, 0.72 + 0.20 * math.sin(button.elapsed * 8))
        if button.completed and button.progress >= 1 then
            if button.elapsed >= 1.35 then ResetButtonProgress() end
        elseif button.elapsed >= 5 then
            pendingButtonID = nil
            ResetButtonProgress()
        end
        return
    end
    button.updateElapsed = (button.updateElapsed or 0) + elapsed
    if button.updateElapsed < 0.2 then return end
    button.updateElapsed = 0
    local settings = addon.GetSettings and addon.GetSettings()
    local progress = 0
    if settings and settings.randomTransmogEnabled == true and timerStartedAt and timerDuration then
        progress = math.max(0, math.min(1, (GetTime() - timerStartedAt) / timerDuration))
    end
    RenderButtonProgress(progress, 0.82)
end

local function PositionButton(settings)
    if not button then return end
    local x = tonumber(settings.randomTransmogButtonX) or 260
    local y = tonumber(settings.randomTransmogButtonY) or -160
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function CreateButton()
    if button or not UIParent then return end
    button = CreateFrame("Button", "WaffleHouseRandomTransmogButton", UIParent)
    button:SetSize(70, 70)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(BUTTON_ART)
    button.ticks = {}
    for index = 1, TICK_COUNT do
        local angle = (index - 1) * 2 * math.pi / TICK_COUNT
        local tick = button:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(WHITE)
        tick:SetBlendMode("ADD")
        tick:SetVertexColor(0.28, 0.86, 1)
        tick:SetSize(3, 6)
        tick:SetPoint("CENTER", button, "CENTER", math.sin(angle) * 27.4, math.cos(angle) * 27.4)
        tick:SetRotation(-angle)
        tick:SetAlpha(0)
        button.ticks[index] = tick
    end
    button:SetScript("OnClick", function()
        if IsShiftKeyDown() then return end
        if pendingButtonID then return end
        addon.RandomizeTransmogNow()
    end)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if not (x and y and parentX and parentY) then return end
        local settings = addon.GetSettings and addon.GetSettings()
        if not settings then return end
        settings.randomTransmogButtonX = math.floor(x - parentX + 0.5)
        settings.randomTransmogButtonY = math.floor(y - parentY + 0.5)
        PositionButton(settings)
    end)
    button:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        pendingButtonID = nil
        ResetButtonProgress()
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Random Saved Outfit")
        GameTooltip:AddLine("Click to switch now. Shift-drag to move.", 0.8, 0.85, 0.9)
        local settings = addon.GetSettings and addon.GetSettings()
        if settings and settings.randomTransmogEnabled == true and timerStartedAt and timerDuration then
            local remaining = math.max(0, math.ceil(timerDuration - (GetTime() - timerStartedAt)))
            if remaining == 0 then
                GameTooltip:AddLine("Automatic switch ready; waiting for a safe moment.", 0.4, 0.9, 1)
            else
                GameTooltip:AddLine("Next automatic attempt in " .. math.ceil(remaining / 60) .. " min.", 0.4, 0.9, 1)
            end
        else
            GameTooltip:AddLine("Timed outfit changes are off.", 0.6, 0.65, 0.7)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnUpdate", AnimateButton)
end

function addon.RefreshRandomTransmogButton()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.randomTransmogButtonEnabled ~= true then
        if button then button:Hide() end
        return
    end
    CreateButton()
    if not button then return end
    PositionButton(settings)
    button:Show()
end

function addon.RandomizeTransmogNow()
    local ok, safe = pcall(CanSwitch)
    if not ok or not safe then
        Report("Wait until you are out of combat, stationary, and away from the transmog editor.")
        return false
    end
    local applied, switched, chosenID = pcall(SwitchToRandomOutfit, function(id)
        pendingButtonID = id
        if button then
            ResetButtonProgress()
            button.manualProgress = true
        end
    end)
    if not applied or not switched then
        pendingButtonID = nil
        ResetButtonProgress()
        Report("No other unlocked saved outfit is available, or the switch was refused.")
        return false
    end
    local activeOK, activeID = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
    if activeOK and IsPlain(activeID) and activeID == chosenID then
        pendingButtonID = nil
        if button then button.completed = true end
    end
    return true
end

local Schedule
Schedule = function(delay, preserveProgress)
    generation = generation + 1
    local current = generation
    if not preserveProgress then
        timerStartedAt = GetTime()
        timerDuration = delay
    end
    C_Timer.After(delay, function()
        if generation ~= current then return end
        local settings = addon.GetSettings and addon.GetSettings()
        if not settings or settings.randomTransmogEnabled ~= true then return end
        local ok, safe = pcall(CanSwitch)
        if not ok or not safe then
            Schedule(RETRY_SECONDS, true)
            return
        end
        -- Schedule before applying: the displayed-outfit event can restart the
        -- interval synchronously and invalidate this callback's schedule.
        Schedule(IntervalSeconds(settings))
        pcall(SwitchToRandomOutfit)
    end)
end

function addon.RefreshRandomTransmog()
    generation = generation + 1
    local settings = addon.GetSettings and addon.GetSettings()
    if settings and settings.randomTransmogEnabled == true and C_Timer and C_Timer.After then
        Schedule(IntervalSeconds(settings))
    else
        timerStartedAt, timerDuration = nil, nil
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
events:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" and pendingButtonID then
        local ok, activeID = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
        if ok and IsPlain(activeID) and activeID == pendingButtonID then
            pendingButtonID = nil
            if button then button.completed = true end
        end
    end
    if event == "PLAYER_LOGIN" or event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED"
        or event == "TRANSMOG_OUTFITS_CHANGED" then
        addon.RefreshRandomTransmog()
        if event == "PLAYER_LOGIN" then addon.RefreshRandomTransmogButton() end
    end
end)
