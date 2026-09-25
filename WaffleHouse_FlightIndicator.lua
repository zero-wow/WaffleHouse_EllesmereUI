local addonName, addon = ...

local STEADY_FLIGHT_AURA = 404468
local TRANSITION = {}
for index = 1, 16 do
    TRANSITION[index] = "Interface\\AddOns\\" .. addonName
        .. "\\Media\\FlightStyle\\flight-" .. string.format("%02d", index) .. ".png"
end
local ICONS = { skyriding = TRANSITION[1], steady = TRANSITION[16] }
local WIND_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\FlightStyle\\wind.png"
local VEIL_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\FlightStyle\\veil.png"
local SWITCH_SPELLS = { [436854] = true, [460002] = true, [460003] = true }
local SIZES = { small = 76, medium = 104, large = 132 }
local DEFAULT_X, DEFAULT_Y = 0, 180

local badge
local animation

-- LiteMount uses this same Steady Flight aura to distinguish the two styles.
-- In Midnight, aura data can become secret during combat; keep the last
-- trustworthy display instead of testing a secret value or guessing.
local function ReadFlightStyle()
    if not (C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function") then return end
    local ok, style = pcall(function()
        if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function"
            and C_Secrets.ShouldAurasBeSecret() then return end
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(STEADY_FLIGHT_AURA)
        if issecretvalue and issecretvalue(aura) then return end
        return aura and "steady" or "skyriding"
    end)
    if ok and (not issecretvalue or not issecretvalue(style)) then return style end
end

addon.GetFlightIndicatorState = ReadFlightStyle

local function PositionBadge(settings)
    if not badge then return end
    local width = UIParent:GetWidth() or 0
    local height = UIParent:GetHeight() or 0
    local xLimit = math.max(0, (width - badge:GetWidth()) / 2)
    local yLimit = math.max(0, (height - badge:GetHeight()) / 2)
    local x = tonumber(settings.flightIndicatorX) or DEFAULT_X
    local y = tonumber(settings.flightIndicatorY) or DEFAULT_Y
    x = math.max(-xLimit, math.min(xLimit, x))
    y = math.max(-yLimit, math.min(yLimit, y))
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function CreateBadge()
    badge = CreateFrame("Frame", "WaffleHouseFlightIndicator", UIParent)
    badge:SetSize(SIZES.medium, SIZES.medium)
    badge:SetFrameStrata("MEDIUM")
    badge:SetMovable(true)
    badge:SetClampedToScreen(true)
    badge:RegisterForDrag("LeftButton")
    badge:EnableMouse(false)

    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints()
    badge.blend = badge:CreateTexture(nil, "OVERLAY")
    badge.blend:SetAllPoints()
    badge.blend:SetAlpha(0)

    badge.wind = badge:CreateTexture(nil, "OVERLAY")
    badge.wind:SetPoint("CENTER", badge, "CENTER")
    badge.wind:SetTexture(WIND_TEXTURE)
    badge.wind:SetBlendMode("ADD")
    badge.wind:SetAlpha(0)

    badge.veil = badge:CreateTexture(nil, "OVERLAY")
    badge.veil:SetPoint("CENTER", badge, "CENTER")
    badge.veil:SetTexture(VEIL_TEXTURE)
    badge.veil:SetAlpha(0)

    badge:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    badge:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if not (x and y and parentX and parentY) then return end
        local settings = addon.GetSettings()
        settings.flightIndicatorX = math.floor(x - parentX + 0.5)
        settings.flightIndicatorY = math.floor(y - parentY + 0.5)
        PositionBadge(settings)
    end)
    badge:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
end

local function ShowStaticStyle(style)
    if not badge or not style then return end
    animation = nil
    badge:SetScript("OnUpdate", nil)
    badge.icon:SetTexture(ICONS[style])
    badge.iconPath = ICONS[style]
    badge.blend:SetAlpha(0)
    badge.icon:SetRotation(0)
    badge.blend:SetRotation(0)
    badge.wind:SetAlpha(0)
    badge.veil:SetAlpha(0)
    badge.style = style
    badge:Show()
end

local function UpdateState()
    if not badge then return end
    local style = ReadFlightStyle()
    if not style then return end
    if animation then
        if style == animation.to and animation.completed then
            ShowStaticStyle(style)
        end
        return
    end
    if badge.style ~= style then ShowStaticStyle(style) end
end

local function RenderTransition()
    if not (badge and animation) then return end
    local progress = math.max(0, math.min(1,
        (GetTime() - animation.startTime) / animation.duration))
    -- Hold the recognisable starting form while wind builds, then sweep
    -- through the pose change under the bright vortex near the cast's end.
    -- The same authored art is played backwards for the opposite switch.
    local framePos
    if progress < 0.68 then
        framePos = 4 * progress / 0.68
    elseif progress < 0.95 then
        framePos = 4 + 10 * (progress - 0.68) / 0.27
    else
        framePos = 14 + (progress - 0.95) / 0.05
    end
    local index = math.min(#TRANSITION - 1, math.floor(framePos) + 1)
    local fraction = framePos - (index - 1)
    local startIndex = animation.from == "skyriding" and index or (#TRANSITION + 1 - index)
    local endIndex = animation.from == "skyriding" and (index + 1) or (#TRANSITION - index)
    if badge.iconPath ~= TRANSITION[startIndex] then
        badge.icon:SetTexture(TRANSITION[startIndex])
        badge.iconPath = TRANSITION[startIndex]
    end
    if badge.blendPath ~= TRANSITION[endIndex] then
        badge.blend:SetTexture(TRANSITION[endIndex])
        badge.blendPath = TRANSITION[endIndex]
    end
    badge.blend:SetAlpha(fraction)

    local direction = animation.from == "skyriding" and 1 or -1
    local spin = math.max(0, math.min(1, (progress - 0.58) / 0.28))
    spin = spin * spin * (3 - 2 * spin)
    local angle = direction * 2 * math.pi * spin
    badge.icon:SetRotation(angle)
    badge.blend:SetRotation(angle)

    badge.wind:SetRotation(direction * 10 * math.pi * progress)
    badge.wind:SetAlpha(math.max(0, math.sin(math.pi * progress)) * 0.78)
    local veilAlpha = 0
    if progress >= 0.52 and progress < 0.70 then
        veilAlpha = 0.96 * (progress - 0.52) / 0.18
    elseif progress >= 0.70 and progress < 0.86 then
        veilAlpha = 0.96 * (0.86 - progress) / 0.16
    end
    badge.veil:SetRotation(-direction * 4 * math.pi * progress)
    badge.veil:SetAlpha(veilAlpha)
end

local function StartStyleCast(castGUID)
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.flightIndicatorEnabled ~= true then return end
    addon.RefreshFlightIndicator()
    if not (badge and badge.style) then return end
    local from = badge.style
    local duration, startTime = 5, GetTime()
    if type(UnitCastingInfo) == "function" then
        local ok, castStart, castEnd = pcall(function()
            local _, _, _, startMS, endMS = UnitCastingInfo("player")
            if type(startMS) ~= "number" or type(endMS) ~= "number"
                or (issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS))) then return end
            return startMS / 1000, endMS / 1000
        end)
        if ok and castStart and castEnd and castEnd > castStart
            and math.abs(castStart - startTime) < 10 then
            startTime, duration = castStart, castEnd - castStart
        end
    end
    animation = {
        from = from,
        to = from == "steady" and "skyriding" or "steady",
        guid = castGUID,
        startTime = startTime,
        duration = duration,
    }
    badge:SetScript("OnUpdate", RenderTransition)
    RenderTransition()
end

local function FinishStyleCast(castGUID)
    if not animation or animation.guid ~= castGUID then return end
    animation.completed = true
    UpdateState()
    -- The success event can precede the Steady Flight aura update.
    C_Timer.After(0.25, UpdateState)
    C_Timer.After(1, function()
        if animation and animation.guid == castGUID and animation.completed then
            ShowStaticStyle(ReadFlightStyle() or animation.from)
        end
    end)
end

local function CancelStyleCast(castGUID)
    if animation and animation.guid == castGUID then
        ShowStaticStyle(animation.from)
    end
end

local function StopStyleCast(castGUID)
    if not animation or animation.guid ~= castGUID then return end
    -- STOP also fires for a successful cast, normally before SUCCEEDED.
    -- Check next frame so the success event has a chance to arrive first.
    C_Timer.After(0.1, function()
        if animation and animation.guid == castGUID and not animation.completed then
            CancelStyleCast(castGUID)
        end
    end)
end

function addon.RefreshFlightIndicator()
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.flightIndicatorEnabled ~= true then
        animation = nil
        if badge then
            badge:SetScript("OnUpdate", nil)
            badge:Hide()
        end
        return
    end

    if not badge then CreateBadge() end
    local size = SIZES[settings.flightIndicatorSize] or SIZES.medium
    badge:SetSize(size, size)
    badge.wind:SetSize(size * 0.77, size * 0.77)
    badge.veil:SetSize(size * 0.72, size * 0.72)
    PositionBadge(settings)
    badge:EnableMouse(IsShiftKeyDown())

    UpdateState()
    if badge.style then
        badge:Show()
    else
        -- No reliable aura read yet (for example login during combat).
        badge:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
events:RegisterEvent("UNIT_SPELLCAST_STOP")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if event == "UNIT_AURA" then
        if unit == "player" then UpdateState() end
        return
    end
    if event == "UNIT_SPELLCAST_START" then
        if unit == "player" and SWITCH_SPELLS[spellID] then StartStyleCast(castGUID) end
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        if unit == "player" then CancelStyleCast(castGUID) end
        return
    end
    if event == "UNIT_SPELLCAST_STOP" then
        if unit == "player" then StopStyleCast(castGUID) end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and SWITCH_SPELLS[spellID] then FinishStyleCast(castGUID) end
        return
    end
    if event == "MODIFIER_STATE_CHANGED" then
        if badge and badge:IsShown() then badge:EnableMouse(IsShiftKeyDown()) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" and animation then
        ShowStaticStyle(ReadFlightStyle() or animation.from)
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        addon.RefreshFlightIndicator()
    else
        UpdateState()
    end
end)
