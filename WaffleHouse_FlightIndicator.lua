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
-- Surge Forward and Skyward Ascent use the same six-charge pool in Midnight.
-- Try both because one may not be available until the player mounts.
local CHARGE_SPELLS = { 372608, 372610 }
local SIZES = { small = 76, medium = 104, large = 132 }
local COMPACT_SIZES = {
    small = { 90, 36 }, medium = { 104, 40 }, large = { 118, 44 },
}
local DEFAULT_X, DEFAULT_Y = 0, 180
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RADAR_R, RADAR_G, RADAR_B = 0.05, 0.82, 0.62
local RADAR_DEFAULT_RIGHT, RADAR_DEFAULT_CENTER_FROM_TOP, RADAR_GAP = 170, 202, 8
local GEM_ANGLES = { 30, 90, 150, 210, 270, 330 }
local CAST_TICKS = 12

local badge
local animation

local function Clamp01(value)
    return math.max(0, math.min(1, value))
end

local function SmoothStep(value)
    value = Clamp01(value)
    return value * value * (3 - 2 * value)
end

local function SafeNumber(value)
    return (not issecretvalue or not issecretvalue(value))
        and type(value) == "number" and value == value
end

local function ReadSkyridingCharges()
    if not (C_Spell and type(C_Spell.GetSpellCharges) == "function") then return end
    for _, spellID in ipairs(CHARGE_SPELLS) do
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and info and (not issecretvalue or not issecretvalue(info)) then
            local okFields, state = pcall(function()
                local count, maximum = info.currentCharges, info.maxCharges
                if not (SafeNumber(count) and SafeNumber(maximum))
                    or maximum < 1 or maximum > 6 or count < 0 or count > maximum
                    or count ~= math.floor(count) or maximum ~= math.floor(maximum) then return end
                local start, duration, rate = info.cooldownStartTime,
                    info.cooldownDuration, info.chargeModRate
                if not (SafeNumber(start) and SafeNumber(duration))
                    or start <= 0 or duration <= 0 then
                    start, duration = nil, nil
                end
                if not SafeNumber(rate) or rate <= 0 then rate = 1 end
                return { count = count, maximum = maximum,
                    start = start, duration = duration, rate = rate }
            end)
            if okFields and state then return state end
        end
    end
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
    local compact = badge.layout == "compact"
    -- Sit just to the right of Vignette Radar's default top-left launcher.
    -- The independent saved position takes over as soon as this is dragged.
    local defaultX = compact and (-width / 2 + RADAR_DEFAULT_RIGHT
        + RADAR_GAP + badge:GetWidth() / 2) or DEFAULT_X
    local defaultY = compact and (height / 2 - RADAR_DEFAULT_CENTER_FROM_TOP) or DEFAULT_Y
    local x = tonumber(settings[compact and "flightIndicatorCompactX" or "flightIndicatorX"])
        or defaultX
    local y = tonumber(settings[compact and "flightIndicatorCompactY" or "flightIndicatorY"])
        or defaultY
    x = math.max(-xLimit, math.min(xLimit, x))
    y = math.max(-yLimit, math.min(yLimit, y))
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function PositionOrnaments()
    local size = badge:GetWidth()
    for index, gem in ipairs(badge.chargeGems) do
        local angle = math.rad(GEM_ANGLES[index])
        local x, y = size * 0.43 * math.cos(angle), size * 0.43 * math.sin(angle)
        for _, part in ipairs({ gem.glow, gem.bezel, gem.core }) do
            part:ClearAllPoints()
            part:SetPoint("CENTER", badge, "CENTER", x, y)
        end
        gem.glow:SetSize(size * 0.09, size * 0.09)
        gem.bezel:SetSize(size * 0.075, size * 0.075)
        gem.core:SetSize(size * 0.048, size * 0.048)
    end
    for index, tick in ipairs(badge.castTicks) do
        local angle = math.rad(90 - (index - 1) * 360 / CAST_TICKS)
        tick:ClearAllPoints()
        tick:SetPoint("CENTER", badge, "CENTER",
            size * 0.32 * math.cos(angle), size * 0.32 * math.sin(angle))
        tick:SetSize(math.max(1, size * 0.017), size * 0.052)
    end
end

local function PositionCompact()
    if badge.layout ~= "compact" then return end
    local compact = badge.compact
    local width, height = badge:GetWidth(), badge:GetHeight()
    compact.dial:SetSize(height - 4, height - 4)
    compact.face:SetSize(height - 8, height - 8)
    compact.icon:SetSize(height - 9, height - 9)
    compact.label:ClearAllPoints()
    compact.label:SetPoint("TOPLEFT", badge, "TOPLEFT", height + 3, -6)
    compact.label:SetWidth(width - height - 7)
    for index, pip in ipairs(compact.pips) do
        pip:ClearAllPoints()
        pip:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT",
            height + 5 + (index - 1) * 8, 8)
    end
    compact.track:SetSize(width - 6, 2)
    compact.fill:SetSize(width - 6, 2)
    compact.edges.top:SetSize(width, 1)
    compact.edges.bottom:SetSize(width, 1)
    compact.edges.left:SetSize(1, height)
    compact.edges.right:SetSize(1, height)
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

    -- Radar Compact is an independent, low-profile readout. It reuses the
    -- authored creature endpoints without carrying over the ornate frame.
    local compact = {}
    badge.compact = compact
    compact.surface = badge:CreateTexture(nil, "BACKGROUND")
    compact.surface:SetAllPoints()
    compact.surface:SetTexture(WHITE)
    compact.surface:SetVertexColor(0.015, 0.022, 0.028)
    compact.surface:SetAlpha(0)
    compact.edges = {}
    for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
        local texture = badge:CreateTexture(nil, "BORDER")
        texture:SetTexture(WHITE)
        texture:SetVertexColor(RADAR_R, RADAR_G, RADAR_B)
        texture:SetAlpha(0)
        compact.edges[edge] = texture
    end
    compact.edges.top:SetPoint("TOPLEFT", badge, "TOPLEFT")
    compact.edges.bottom:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT")
    compact.edges.left:SetPoint("TOPLEFT", badge, "TOPLEFT")
    compact.edges.right:SetPoint("TOPRIGHT", badge, "TOPRIGHT")
    compact.dial = badge:CreateTexture(nil, "ARTWORK")
    compact.dial:SetTexture(CIRCLE)
    compact.dial:SetVertexColor(RADAR_R, RADAR_G, RADAR_B)
    compact.dial:SetPoint("LEFT", badge, "LEFT", 2, 0)
    compact.dial:SetAlpha(0)
    compact.face = badge:CreateTexture(nil, "ARTWORK", nil, 1)
    compact.face:SetTexture(CIRCLE)
    compact.face:SetVertexColor(0.018, 0.055, 0.061)
    compact.face:SetPoint("CENTER", compact.dial, "CENTER")
    compact.face:SetAlpha(0)
    compact.icon = badge:CreateTexture(nil, "ARTWORK", nil, 2)
    compact.icon:SetPoint("CENTER", compact.dial, "CENTER")
    compact.icon:SetAlpha(0)
    compact.label = badge:CreateFontString(nil, "OVERLAY")
    compact.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    compact.label:SetJustifyH("LEFT")
    compact.label:SetTextColor(0.78, 0.90, 0.88)
    compact.label:SetAlpha(0)
    compact.pips = {}
    for index = 1, #GEM_ANGLES do
        local pip = badge:CreateTexture(nil, "OVERLAY")
        pip:SetTexture(CIRCLE)
        pip:SetSize(5, 5)
        pip:SetVertexColor(RADAR_R, RADAR_G, RADAR_B)
        pip:SetAlpha(0)
        compact.pips[index] = pip
    end
    compact.track = badge:CreateTexture(nil, "OVERLAY")
    compact.track:SetTexture(WHITE)
    compact.track:SetVertexColor(RADAR_R, RADAR_G, RADAR_B)
    compact.track:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 3, 3)
    compact.track:SetAlpha(0)
    compact.fill = badge:CreateTexture(nil, "OVERLAY", nil, 1)
    compact.fill:SetTexture(WHITE)
    compact.fill:SetVertexColor(RADAR_R, RADAR_G, RADAR_B)
    compact.fill:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 3, 3)
    compact.fill:SetAlpha(0)

    -- In the full emblem, inlaid jewels show the shared charge pool; the
    -- smaller readout uses its separate six-dot row instead.
    badge.chargeGems = {}
    for index = 1, #GEM_ANGLES do
        local gem = {}
        for _, part in ipairs({ "glow", "bezel", "core" }) do
            local sublevel = part == "glow" and 2 or (part == "bezel" and 3 or 4)
            local texture = badge:CreateTexture(nil, "OVERLAY", nil, sublevel)
            texture:SetTexture(WHITE)
            texture:SetRotation(math.pi / 4)
            texture:SetAlpha(0)
            gem[part] = texture
        end
        gem.glow:SetVertexColor(0.10, 0.85, 1)
        gem.glow:SetBlendMode("ADD")
        gem.bezel:SetVertexColor(0.82, 0.59, 0.28)
        badge.chargeGems[index] = gem
    end
    badge.castTicks = {}
    for index = 1, CAST_TICKS do
        local tick = badge:CreateTexture(nil, "OVERLAY", nil, 2)
        tick:SetTexture(WHITE)
        tick:SetVertexColor(1, 0.72, 0.34)
        tick:SetRotation(math.rad(90 - (index - 1) * 360 / CAST_TICKS) - math.pi / 2)
        tick:SetAlpha(0)
        badge.castTicks[index] = tick
    end
    PositionOrnaments()

    badge.chargeTicker = CreateFrame("Frame", nil, badge)
    badge.chargeTicker:SetAllPoints(badge)
    badge.chargeTicker:EnableMouse(false)
    badge.chargeTicker:Hide()

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
        local key = self.layout == "compact" and "flightIndicatorCompact" or "flightIndicator"
        settings[key .. "X"] = math.floor(x - parentX + 0.5)
        settings[key .. "Y"] = math.floor(y - parentY + 0.5)
        PositionBadge(settings)
    end)
    badge:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
end

local function ShowCompactStyle(style)
    local compact = badge.compact
    local path = style == "steady" and CREATURE[#CREATURE] or CREATURE[1]
    if compact.iconPath ~= path then
        compact.icon:SetTexture(path)
        compact.iconPath = path
    end
    compact.icon:SetAlpha(badge.layout == "compact" and 1 or 0)
    compact.label:SetText(style == "steady" and "STEADY" or "SKYRIDE")
end

local function SetCompactVisibility(enabled)
    local compact = badge.compact
    compact.surface:SetAlpha(enabled and 0.90 or 0)
    for _, edge in pairs(compact.edges) do edge:SetAlpha(enabled and 0.38 or 0) end
    compact.dial:SetAlpha(enabled and 0.55 or 0)
    compact.face:SetAlpha(enabled and 1 or 0)
    compact.icon:SetAlpha(enabled and 1 or 0)
    compact.label:SetAlpha(enabled and 1 or 0)
    if not enabled then
        for _, pip in ipairs(compact.pips) do pip:SetAlpha(0) end
        compact.track:SetAlpha(0)
        compact.fill:SetAlpha(0)
    end
    badge.icon:SetAlpha(enabled and 0 or 1)
    if enabled then
        badge.blend:SetAlpha(0)
        badge.creature:SetAlpha(0)
        badge.original:SetAlpha(0)
        for _, tick in ipairs(badge.castTicks) do tick:SetAlpha(0) end
        for _, gem in ipairs(badge.chargeGems) do
            gem.glow:SetAlpha(0)
            gem.bezel:SetAlpha(0)
            gem.core:SetAlpha(0)
        end
    end
end

local function HideChargeGems()
    for _, gem in ipairs(badge.chargeGems) do
        gem.glow:SetAlpha(0)
        gem.bezel:SetAlpha(0)
        gem.core:SetAlpha(0)
    end
    for _, pip in ipairs(badge.compact.pips) do pip:SetAlpha(0) end
end

local function RenderCastProgress(progress)
    local settings = addon.GetSettings and addon.GetSettings()
    local enabled = not settings or settings.flightIndicatorCastProgress ~= false
    if badge.layout == "compact" then
        local compact = badge.compact
        compact.track:SetAlpha(enabled and 0.24 or 0)
        compact.fill:SetSize(math.max(1, (badge:GetWidth() - 6) * progress), 2)
        compact.fill:SetAlpha(enabled and 0.95 or 0)
        for _, tick in ipairs(badge.castTicks) do tick:SetAlpha(0) end
        return
    end
    for index, tick in ipairs(badge.castTicks) do
        local filled = Clamp01(progress * CAST_TICKS - index + 1)
        tick:SetAlpha(enabled and (0.10 + 0.72 * filled) or 0)
    end
end

local function HideCastProgress()
    for _, tick in ipairs(badge.castTicks) do tick:SetAlpha(0) end
    badge.compact.track:SetAlpha(0)
    badge.compact.fill:SetAlpha(0)
end

local function RenderChargeGems()
    local state = badge.chargeState
    if not state or badge.style ~= "skyriding" or animation then
        HideChargeGems()
        return
    end
    local now = GetTime()
    local reveal = Clamp01((now - (badge.chargeRevealAt or now)) / 0.25)
    local refill = 0
    if state.count < state.maximum and state.start and state.duration then
        refill = Clamp01((now - state.start) * state.rate / state.duration)
    end
    local pulse = Clamp01(1 - (now - (badge.chargePulseAt or -100)) / 0.35)
    local takeoff = Clamp01(1 - (now - (badge.takeoffAt or -100)) / 0.45)
    if badge.layout == "compact" then
        for index, pip in ipairs(badge.compact.pips) do
            if index <= state.maximum then
                local fill = index <= state.count and 1
                    or (index == state.count + 1 and refill or 0)
                local flash = index == badge.chargePulseIndex and pulse or 0
                pip:SetAlpha((0.18 + 0.64 * fill + 0.18 * flash
                    + 0.12 * takeoff) * reveal)
            else
                pip:SetAlpha(0)
            end
        end
        return
    end
    for index, gem in ipairs(badge.chargeGems) do
        if index <= state.maximum then
            local fill = index <= state.count and 1
                or (index == state.count + 1 and refill or 0)
            local flash = index == badge.chargePulseIndex and pulse or 0
            gem.bezel:SetAlpha(0.88 * reveal)
            gem.core:SetVertexColor(0.08 + 0.20 * fill,
                0.22 + 0.68 * fill, 0.31 + 0.69 * fill)
            gem.core:SetAlpha((0.64 + 0.36 * fill) * reveal)
            gem.glow:SetAlpha((0.12 * fill + 0.42 * flash
                + 0.24 * takeoff) * reveal)
        else
            gem.glow:SetAlpha(0)
            gem.bezel:SetAlpha(0)
            gem.core:SetAlpha(0)
        end
    end
end

local function RefreshChargeData()
    if not badge or badge.style ~= "skyriding" or animation
        or not badge.chargeTicker:IsShown() then return end
    local state = ReadSkyridingCharges()
    local old = badge.chargeState
    badge.chargeState = state
    if state and old and state.count ~= old.count then
        badge.chargePulseAt = GetTime()
        badge.chargePulseIndex = state.count > old.count and state.count or old.count
    end
    RenderChargeGems()
end

local function ReadFlyingMount()
    if type(IsMounted) ~= "function" or type(IsFlying) ~= "function" then return end
    local ok, flying = pcall(function()
        local mounted, airborne = IsMounted(), IsFlying()
        if issecretvalue and (issecretvalue(mounted) or issecretvalue(airborne)) then return end
        return mounted == true and airborne == true
    end)
    if ok then return flying end
end

local function ChargeTickerOnUpdate(_, elapsed)
    if not badge or badge.style ~= "skyriding" or animation then return end
    badge.chargeTickElapsed = (badge.chargeTickElapsed or 0) + elapsed
    if badge.chargeTickElapsed < 0.05 then return end
    badge.chargePollElapsed = (badge.chargePollElapsed or 0) + badge.chargeTickElapsed
    badge.chargeTickElapsed = 0
    if badge.chargePollElapsed >= 0.30 then
        badge.chargePollElapsed = 0
        RefreshChargeData()
    end
    local flying = ReadFlyingMount()
    if flying ~= nil then
        if badge.wasFlying == false and flying then badge.takeoffAt = GetTime() end
        badge.wasFlying = flying
    end
    RenderChargeGems()
end

local function SyncChargeMode()
    local settings = addon.GetSettings and addon.GetSettings()
    if badge.style == "skyriding" and settings
        and settings.flightIndicatorCharges ~= false and not animation then
        if not badge.chargeTicker:IsShown() then
            badge.chargeRevealAt = GetTime()
            badge.chargePollElapsed = 0
            badge.chargeTickElapsed = 0
            badge.wasFlying = ReadFlyingMount()
        end
        badge.chargeTicker:SetScript("OnUpdate", ChargeTickerOnUpdate)
        badge.chargeTicker:Show()
        RefreshChargeData()
    else
        badge.chargeTicker:Hide()
        badge.chargeState = nil
        HideChargeGems()
    end
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
    HideCastProgress()
    badge.style = style
    ShowCompactStyle(style)
    badge:Show()
    SyncChargeMode()
end

local function UpdateState()
    if not badge then return end
    local style = ReadFlightStyle()
    if not style then return end
    if animation then
        -- A success/aura event can arrive before the visual cast clock ends.
        -- Keep the dragon-to-bird morph running for the whole measured cast.
        if style == animation.to and animation.completed
            and ((animation.from ~= "skyriding" and badge.layout ~= "compact")
                or GetTime() >= animation.startTime + animation.duration) then
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
    RenderCastProgress(progress)

    if badge.layout == "compact" then
        -- The tiny readout favors an unmistakable state over a crowded
        -- two-headed miniature morph. Its bar carries the full cast while
        -- the silhouette fades to the new state at the end.
        if progress < 0.90 then
            ShowCompactStyle(animation.from)
            badge.compact.icon:SetAlpha(1 - SmoothStep((progress - 0.82) / 0.08))
        else
            ShowCompactStyle(animation.to)
            badge.compact.icon:SetAlpha(SmoothStep((progress - 0.90) / 0.10))
        end
        if progress >= 1 and animation.completed then UpdateState() end
        return
    end

    -- Keep the authored full emblems in this direction. Do not use the
    -- reverse-direction cutout morph here: its intermediate images
    -- show two heads when played in this direction. The bird is mostly formed
    -- by frame 11, so pace this direction later into the actual cast rather
    -- than leaving a static-looking bird for the final two seconds. Blend
    -- only near each frame boundary to avoid prolonged double silhouettes.
    if animation.from == "skyriding" then
        local framePosition = 1 + (#FLIGHT_FRAMES - 1) * progress ^ 1.85
        local first = math.min(#FLIGHT_FRAMES - 1, math.floor(framePosition))
        if badge.iconPath ~= FLIGHT_FRAMES[first] then
            badge.icon:SetTexture(FLIGHT_FRAMES[first])
            badge.iconPath = FLIGHT_FRAMES[first]
        end
        if badge.blendPath ~= FLIGHT_FRAMES[first + 1] then
            badge.blend:SetTexture(FLIGHT_FRAMES[first + 1])
            badge.blendPath = FLIGHT_FRAMES[first + 1]
        end
        badge.blend:SetAlpha(SmoothStep((framePosition - first - 0.2) / 0.6))
        badge.creature:SetAlpha(0)
        badge.original:SetAlpha(0)
        if progress >= 1 and animation.completed then UpdateState() end
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
    badge.chargeTicker:Hide()
    HideChargeGems()
    badge:SetScript("OnUpdate", RenderTransition)
    RenderTransition()
end

local function FinishStyleCast(castGUID)
    if not animation or animation.guid ~= castGUID then return end
    animation.completed = true
    UpdateState()
    -- The success event can precede the Steady Flight aura update.
    C_Timer.After(0.25, UpdateState)
    local remaining = animation
        and math.max(0, animation.startTime + animation.duration - GetTime()) or 0
    C_Timer.After(math.max(1, remaining + 0.25), function()
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
            badge.chargeTicker:Hide()
            HideChargeGems()
            HideCastProgress()
            badge:Hide()
        end
        return
    end

    if not badge then CreateBadge() end
    badge.layout = settings.flightIndicatorLayout == "compact" and "compact" or "emblem"
    local size = SIZES[settings.flightIndicatorSize] or SIZES.medium
    local compactSize = COMPACT_SIZES[settings.flightIndicatorSize] or COMPACT_SIZES.medium
    badge:SetSize(badge.layout == "compact" and compactSize[1] or size,
        badge.layout == "compact" and compactSize[2] or size)
    badge.creature:SetSize(size * 0.90, size * 0.90)
    PositionOrnaments()
    PositionCompact()
    PositionBadge(settings)
    badge:EnableMouse(IsShiftKeyDown())
    SetCompactVisibility(badge.layout == "compact")

    if animation then RenderTransition() else UpdateState() end
    if badge.style then
        if not animation then ShowCompactStyle(badge.style) end
        badge:Show()
        SyncChargeMode()
    else
        -- No reliable aura read yet (for example login during combat).
        badge:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("SPELL_UPDATE_CHARGES")
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
    if event == "SPELL_UPDATE_CHARGES" then
        RefreshChargeData()
        return
    end
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
