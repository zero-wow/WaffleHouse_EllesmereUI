local addonName, addon = ...

local STEADY_FLIGHT_AURA = 404468
local ART_ROOT = "Interface\\AddOns\\" .. addonName .. "\\Media\\FlightStyle\\"
local FLIGHT_FRAMES = {}
for index = 1, 16 do
    FLIGHT_FRAMES[index] = ART_ROOT .. "flight-" .. string.format("%02d", index) .. ".png"
end
local ICONS = { skyriding = FLIGHT_FRAMES[1], steady = FLIGHT_FRAMES[16] }
local EMPTY_BACKGROUNDS = {
    skyriding = ART_ROOT .. "empty-skyriding.png",
    steady = ART_ROOT .. "empty-steady.png",
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

-- Read the same start/end timestamps used by Blizzard's cast bar. Only trust
-- them when the live cast is one of our flight-style spells and its cast GUID
-- matches the event that started this animation.
local function ReadStyleCastTimes(castGUID)
    if type(UnitCastingInfo) ~= "function" then return end
    local ok, castStart, castEnd = pcall(function()
        local _, _, _, startMS, endMS, _, currentGUID, _, spellID = UnitCastingInfo("player")
        if issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS)
            or issecretvalue(currentGUID) or issecretvalue(spellID)) then return end
        if type(startMS) ~= "number" or type(endMS) ~= "number"
            or type(spellID) ~= "number" or not SWITCH_SPELLS[spellID]
            or (castGUID and currentGUID and castGUID ~= currentGUID) then return end
        local duration = (endMS - startMS) / 1000
        if duration < 1 or duration > 20 then return end
        return startMS / 1000, endMS / 1000
    end)
    if ok and castStart and castEnd then return castStart, castEnd end
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
    badge.blend = badge:CreateTexture(nil, "ARTWORK", nil, 1)
    badge.blend:SetAllPoints()
    badge.blend:SetAlpha(0)

    badge.creature = badge:CreateTexture(nil, "OVERLAY", nil, 1)
    badge.creature:SetPoint("CENTER", badge, "CENTER")
    badge.creature:SetAlpha(0)
    -- These endpoint paintings contain an opaque sky. They must sit BELOW
    -- the transparent creature cutout, including during the final handoff.
    badge.original = badge:CreateTexture(nil, "ARTWORK", nil, 2)
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
    badge.preloadedFrames = {}
    for _, path in ipairs(FLIGHT_FRAMES) do
        local texture = badge:CreateTexture(nil, "BACKGROUND")
        texture:SetTexture(path)
        texture:SetAlpha(0)
        badge.preloadedFrames[#badge.preloadedFrames + 1] = texture
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
    badge.creature:SetAlpha(0)
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
    local castStart, castEnd = ReadStyleCastTimes(animation.guid)
    if castStart and math.abs(castStart - animation.startTime) < 10 then
        animation.startTime = castStart
        animation.duration = castEnd - castStart
    end
    local progress = Clamp01(
        (GetTime() - animation.startTime) / animation.duration)

    -- The original authored emblems read cleanly from dragon to bird. Do not
    -- use the reverse-direction cutout morph here: its intermediate images
    -- show two heads when played in this direction.
    if animation.from == "skyriding" then
        local framePosition = 1 + (#FLIGHT_FRAMES - 1) * progress
        local first = math.min(#FLIGHT_FRAMES - 1, math.floor(framePosition))
        if badge.iconPath ~= FLIGHT_FRAMES[first] then
            badge.icon:SetTexture(FLIGHT_FRAMES[first])
            badge.iconPath = FLIGHT_FRAMES[first]
        end
        if badge.blendPath ~= FLIGHT_FRAMES[first + 1] then
            badge.blend:SetTexture(FLIGHT_FRAMES[first + 1])
            badge.blendPath = FLIGHT_FRAMES[first + 1]
        end
        badge.blend:SetAlpha(framePosition - first)
        badge.creature:SetAlpha(0)
        badge.original:SetAlpha(0)
        return
    end

    -- Bird to dragon keeps the stronger 48-pose morph. Reserve its last
    -- second for the dragon's original five settling drawings, ending on the
    -- exact static artwork instead of popping to it at cast completion.
    if progress >= 0.82 then
        local tailPosition = 1 + 4 * (progress - 0.82) / 0.18
        local first = math.min(4, math.floor(tailPosition))
        local firstPath = FLIGHT_FRAMES[6 - first]
        local nextPath = FLIGHT_FRAMES[5 - first]
        if badge.iconPath ~= firstPath then
            badge.icon:SetTexture(firstPath)
            badge.iconPath = firstPath
        end
        if badge.blendPath ~= nextPath then
            badge.blend:SetTexture(nextPath)
            badge.blendPath = nextPath
        end
        badge.blend:SetAlpha(tailPosition - first)
        badge.creature:SetAlpha(0)
        badge.original:SetAlpha(0)
        return
    end

    -- Darken the sky behind the independently layered creature. The cutout
    -- stays on OVERLAY even while both background paintings crossfade.
    local fromBackground = EMPTY_BACKGROUNDS.steady
    local toBackground = EMPTY_BACKGROUNDS.skyriding
    if badge.iconPath ~= fromBackground then
        badge.icon:SetTexture(fromBackground)
        badge.iconPath = fromBackground
    end
    if badge.blendPath ~= toBackground then
        badge.blend:SetTexture(toBackground)
        badge.blendPath = toBackground
    end
    badge.blend:SetAlpha(SmoothStep((progress - 0.12) / 0.70))

    local position = #CREATURE - (#CREATURE - 5) * progress / 0.82
    local index = math.max(1, math.min(#CREATURE, math.floor(position + 0.5)))
    if badge.creaturePath ~= CREATURE[index] then
        badge.creature:SetTexture(CREATURE[index])
        badge.creaturePath = CREATURE[index]
    end
    -- The original endpoint paintings use a smaller bird than dragon. Match
    -- those silhouettes so the final handoff does not visibly pop in size.
    local morphProgress = (position - 1) / (#CREATURE - 1)
    local creatureSize = badge:GetWidth() * (0.90 - 0.12 * morphProgress)
    badge.creature:SetSize(creatureSize, creatureSize)

    local originalAlpha = progress < 0.06 and (1 - SmoothStep(progress / 0.06))
        or SmoothStep((progress - 0.76) / 0.06)
    local originalPath = progress < 0.76 and ICONS.steady or FLIGHT_FRAMES[5]
    if badge.originalPath ~= originalPath then
        badge.original:SetTexture(originalPath)
        badge.originalPath = originalPath
    end
    badge.original:SetAlpha(originalAlpha)
    badge.creature:SetAlpha(1 - originalAlpha)
end

local function StartStyleCast(castGUID)
    local settings = addon.GetSettings and addon.GetSettings()
    if not settings or settings.flightIndicatorEnabled ~= true then return end
    addon.RefreshFlightIndicator()
    if not (badge and badge.style) then return end
    local from = badge.style
    local duration, startTime = 5, GetTime()
    local castStart, castEnd = ReadStyleCastTimes(castGUID)
    if castStart and math.abs(castStart - startTime) < 10 then
        startTime, duration = castStart, castEnd - castStart
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
    badge.creature:SetSize(size * 0.90, size * 0.90)
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
