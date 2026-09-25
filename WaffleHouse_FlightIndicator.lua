local addonName, addon = ...

local STEADY_FLIGHT_AURA = 404468
local ART_ROOT = "Interface\\AddOns\\" .. addonName .. "\\Media\\FlightStyle\\"
local ICONS = { skyriding = ART_ROOT .. "flight-01.png", steady = ART_ROOT .. "flight-16.png" }
local BACKGROUNDS = {
    skyriding = { ART_ROOT .. "empty-skyriding.png", ART_ROOT .. "swirl-skyriding.png",
        ART_ROOT .. "swirl-steady.png", ART_ROOT .. "empty-steady.png" },
    steady = { ART_ROOT .. "empty-steady.png", ART_ROOT .. "swirl-steady.png",
        ART_ROOT .. "swirl-skyriding.png", ART_ROOT .. "empty-skyriding.png" },
}
local BASE_CREATURE = {}
for index = 1, 6 do
    BASE_CREATURE[#BASE_CREATURE + 1] = "creature-" .. string.format("%02d", index) .. ".png"
end
for index = 1, 4 do
    BASE_CREATURE[#BASE_CREATURE + 1] = "turn-" .. string.format("%02d", index) .. ".png"
end
for index = 7, 20 do
    BASE_CREATURE[#BASE_CREATURE + 1] = "creature-" .. string.format("%02d", index) .. ".png"
end
-- Put the additional drawings where the silhouette changes most. The reverse
-- flight-style cast walks this same 48-stage sequence backwards.
local BETWEEN_CREATURE = {
    [1] = { "morph-g01-50.png" }, [2] = { "morph-g02-50.png" },
    [3] = { "morph-g03-50.png" }, [4] = { "morph-g04-50.png" },
    [5] = { "morph-g05-50.png" },
    [6] = { "morph-g06-33.png", "morph-g06-67.png" },
    [7] = { "morph-g07-33.png", "morph-g07-67.png" },
    [8] = { "morph-g08-33.png", "morph-g08-67.png" },
    [9] = { "morph-g09-50.png", "morph-g09-67.png" },
    [10] = { "morph-g10-33.png", "morph-g10-67.png" },
    [11] = { "morph-g11-50.png" }, [12] = { "morph-g12-50.png" },
    [13] = { "morph-g13-50.png" }, [14] = { "morph-g14-50.png" },
    [15] = { "morph-g15-50.png" }, [16] = { "morph-g16-50.png" },
    [17] = { "morph-g17-50.png" }, [18] = { "morph-g18-50.png" },
    [19] = { "morph-g19-50.png" },
}
local CREATURE = {}
for index, name in ipairs(BASE_CREATURE) do
    CREATURE[#CREATURE + 1] = ART_ROOT .. name
    for _, inbetween in ipairs(BETWEEN_CREATURE[index] or {}) do
        CREATURE[#CREATURE + 1] = ART_ROOT .. inbetween
    end
end
local RIM_TEXTURE = ART_ROOT .. "rim.png"
local WIND_TEXTURE = ART_ROOT .. "wind.png"
local VEIL_TEXTURE = ART_ROOT .. "veil.png"
local SWITCH_SPELLS = { [436854] = true, [460002] = true, [460003] = true }
local SIZES = { small = 76, medium = 104, large = 132 }
local DEFAULT_X, DEFAULT_Y = 0, 180

local badge
local animation

local function Clamp01(value)
    return math.max(0, math.min(1, value))
end

local function SmoothStep(value)
    value = Clamp01(value)
    return value * value * (3 - 2 * value)
end

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

    badge.creatureA = badge:CreateTexture(nil, "OVERLAY")
    badge.creatureA:SetPoint("CENTER", badge, "CENTER")
    badge.creatureA:SetAlpha(0)
    badge.creatureB = badge:CreateTexture(nil, "OVERLAY")
    badge.creatureB:SetPoint("CENTER", badge, "CENTER")
    badge.creatureB:SetAlpha(0)

    badge.rim = badge:CreateTexture(nil, "OVERLAY")
    badge.rim:SetAllPoints()
    badge.rim:SetTexture(RIM_TEXTURE)
    badge.rim:SetAlpha(0)
    badge.original = badge:CreateTexture(nil, "OVERLAY")
    badge.original:SetAllPoints()
    badge.original:SetAlpha(0)

    -- Load the small sprite set before the first cast so its first reveal does
    -- not hitch while the game opens individual image files.
    badge.preloadedArt = {}
    for _, path in ipairs(CREATURE) do
        local texture = badge:CreateTexture(nil, "BACKGROUND")
        texture:SetTexture(path)
        texture:SetAlpha(0)
        badge.preloadedArt[#badge.preloadedArt + 1] = texture
    end

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
    badge.wind:SetAlpha(0)
    badge.veil:SetAlpha(0)
    badge.creatureA:SetAlpha(0)
    badge.creatureB:SetAlpha(0)
    badge.rim:SetAlpha(0)
    badge.original:SetAlpha(0)
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
    local progress = Clamp01(
        (GetTime() - animation.startTime) / animation.duration)
    local backgrounds = BACKGROUNDS[animation.from]
    local backgroundPosition
    if progress < 0.18 then
        backgroundPosition = progress / 0.18
    elseif progress < 0.50 then
        backgroundPosition = 1
    elseif progress < 0.72 then
        backgroundPosition = 1 + (progress - 0.50) / 0.22
    elseif progress < 0.84 then
        backgroundPosition = 2
    else
        backgroundPosition = 2 + (progress - 0.84) / 0.16
    end
    local backgroundIndex = math.min(3, math.floor(backgroundPosition) + 1)
    local backgroundMix = backgroundPosition - (backgroundIndex - 1)
    if badge.iconPath ~= backgrounds[backgroundIndex] then
        badge.icon:SetTexture(backgrounds[backgroundIndex])
        badge.iconPath = backgrounds[backgroundIndex]
    end
    if badge.blendPath ~= backgrounds[backgroundIndex + 1] then
        badge.blend:SetTexture(backgrounds[backgroundIndex + 1])
        badge.blendPath = backgrounds[backgroundIndex + 1]
    end
    badge.blend:SetAlpha(backgroundMix)

    local direction = animation.from == "skyriding" and 1 or -1
    local energy = SmoothStep((progress - 0.08) / 0.18)
        * SmoothStep((0.98 - progress) / 0.17)
    badge.wind:SetRotation(direction * 3 * math.pi * progress)
    badge.wind:SetAlpha(energy * (0.37 + 0.09 * math.sin(18 * math.pi * progress)))
    badge.veil:SetRotation(-direction * 2 * math.pi * progress)
    badge.veil:SetAlpha(energy * (0.19 + 0.08 * math.sin(27 * math.pi * progress) ^ 2))

    -- The subject is separate from the gem: it flies out, leaves the center
    -- empty during the clockwork vortex, then returns as a 48-pose morph.
    local creaturePosition, creatureAlpha, creatureScale, offsetX, offsetY
    if progress < 0.20 then
        local leaving = SmoothStep(progress / 0.20)
        creaturePosition = animation.from == "skyriding" and (1 + 4 * leaving)
            or (#CREATURE - 4 * leaving)
        creatureAlpha = 1 - SmoothStep((progress - 0.13) / 0.07)
        creatureScale = 1 - 0.52 * leaving
        offsetX = (animation.from == "skyriding" and 0.68 or 0.05) * leaving
        offsetY = (animation.from == "skyriding" and -0.36 or 0.55) * leaving
    elseif progress >= 0.66 then
        -- A linear walk gives all 48 poses roughly equal screen time during
        -- the final 1.7 seconds; only the flight path and scale ease in.
        local arriving = Clamp01((progress - 0.66) / 0.34)
        local arrivalEase = SmoothStep(arriving)
        creaturePosition = animation.from == "skyriding"
            and (5 + (#CREATURE - 5) * arriving)
            or (#CREATURE - 4 - (#CREATURE - 5) * arriving)
        creatureAlpha = SmoothStep((progress - 0.66) / 0.08)
        creatureScale = 0.32 + 0.68 * arrivalEase
        offsetX = (animation.from == "steady" and -0.24 or 0) * (1 - arrivalEase)
        offsetY = (animation.from == "steady" and 0.22 or -0.12) * (1 - arrivalEase)
    else
        creatureAlpha = 0
    end

    local originalAlpha = 0
    if progress < 0.06 then
        originalAlpha = 1 - SmoothStep(progress / 0.06)
    elseif progress > 0.92 then
        originalAlpha = SmoothStep((progress - 0.92) / 0.08)
        creatureAlpha = creatureAlpha * (1 - originalAlpha)
    end
    local originalPath = progress < 0.5 and ICONS[animation.from] or ICONS[animation.to]
    if badge.originalPath ~= originalPath then
        badge.original:SetTexture(originalPath)
        badge.originalPath = originalPath
    end
    badge.original:SetAlpha(originalAlpha)
    badge.rim:SetAlpha(1 - originalAlpha)

    if creatureAlpha > 0 then
        local first = math.min(#CREATURE - 1, math.floor(creaturePosition))
        local mix = creaturePosition - first
        if badge.creatureAPath ~= CREATURE[first] then
            badge.creatureA:SetTexture(CREATURE[first])
            badge.creatureAPath = CREATURE[first]
        end
        if badge.creatureBPath ~= CREATURE[first + 1] then
            badge.creatureB:SetTexture(CREATURE[first + 1])
            badge.creatureBPath = CREATURE[first + 1]
        end
        local size = badge:GetWidth()
            * (0.90 - 0.12 * (creaturePosition - 1) / (#CREATURE - 1)) * creatureScale
        for _, texture in ipairs({ badge.creatureA, badge.creatureB }) do
            texture:SetSize(size, size)
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", badge, "CENTER", offsetX * badge:GetWidth(),
                offsetY * badge:GetHeight())
        end
        badge.creatureA:SetAlpha(creatureAlpha * (1 - mix))
        badge.creatureB:SetAlpha(creatureAlpha * mix)
    else
        badge.creatureA:SetAlpha(0)
        badge.creatureB:SetAlpha(0)
    end
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
