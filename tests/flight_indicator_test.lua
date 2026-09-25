local source = arg[1] or "WaffleHouse_FlightIndicator.lua"
local settings = { flightIndicatorEnabled = true, flightIndicatorSize = "medium",
    flightIndicatorCharges = true, flightIndicatorCastProgress = true }
local addon = { GetSettings = function() return settings end }
local aura, secret, shift, now = true, false, false, 0
local chargeCount, chargeMaximum, chargeStart, chargeDuration = 4, 6, 0, 10
local chargeAvailable, primaryChargeAvailable, chargeSecret = true, true, false
local mounted, flying = false, false
local activeCastGUID, activeSpellID, castStart, castDuration = nil, nil, 0, 5
local eventFrame, badge, chargeTicker
local timers = {}

GetTime = function() return now end
IsShiftKeyDown = function() return shift end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
C_Secrets = { ShouldAurasBeSecret = function() return secret end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(spellID)
    assert(spellID == 404468)
    return aura and { spellId = spellID } or nil
end }
C_Spell = { GetSpellCharges = function(spellID)
    assert(spellID == 372608 or spellID == 372610)
    if not chargeAvailable or (spellID == 372608 and not primaryChargeAvailable) then return end
    return { currentCharges = chargeSecret and { secret = true } or chargeCount,
        maxCharges = chargeMaximum, cooldownStartTime = chargeStart,
        cooldownDuration = chargeDuration, chargeModRate = 1 }
end }
IsMounted = function() return mounted end
IsFlying = function() return flying end
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { due = now + delay, fn = fn } end }
UnitCastingInfo = function()
    if not activeCastGUID then return end
    return "Switch Flight Style", nil, nil, castStart * 1000,
        (castStart + castDuration) * 1000, false, activeCastGUID, false, activeSpellID
end

UIParent = {
    GetWidth = function() return 1920 end,
    GetHeight = function() return 1080 end,
    GetCenter = function() return 960, 540 end,
}

local function NewFrame(name)
    local f = { scripts = {}, name = name, shown = false }
    function f:RegisterEvent() end
    function f:RegisterForDrag() end
    function f:SetScript(key, fn) self.scripts[key] = fn end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetFrameStrata() end
    function f:SetMovable() end
    function f:SetClampedToScreen() end
    function f:EnableMouse(value) self.mouse = value end
    function f:SetAllPoints() end
    function f:ClearAllPoints() end
    function f:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function f:GetCenter() return 960 + (self.x or 0), 540 + (self.y or 0) end
    function f:StartMoving() self.moving = true end
    function f:StopMovingOrSizing() self.moving = false end
    function f:Show() self.shown = true end
    function f:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:IsShown() return self.shown end
    function f:CreateTexture(_, layer, _, sublevel)
        local texture = { layer = layer, sublevel = sublevel or 0 }
        function texture:SetAllPoints() end
        function texture:SetPoint(_, _, _, x, y) self.x, self.y = x or 0, y or 0 end
        function texture:ClearAllPoints() end
        function texture:SetSize(w, h) self.width, self.height = w, h end
        function texture:SetTexture(path) self.path = path end
        function texture:SetTexCoord(...) self.texCoord = { ... } end
        function texture:SetBlendMode(mode) self.blendMode = mode end
        function texture:SetRotation(angle) self.angle = angle end
        function texture:SetAlpha(alpha) self.alpha = alpha end
        function texture:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
        return texture
    end
    function f:CreateFontString()
        local label = { shown = true }
        function label:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
        function label:ClearAllPoints() end
        function label:SetWidth(width) self.width = width end
        function label:SetFont(path, size) self.font, self.fontSize = path, size end
        function label:SetTextColor() end
        function label:SetJustifyH() end
        function label:SetText(value) self.text = value end
        function label:Show() self.shown = true end
        function label:Hide() self.shown = false end
        return label
    end
    return f
end

CreateFrame = function(_, name, parent)
    local frame = NewFrame(name)
    if name == "WaffleHouseFlightIndicator" then badge = frame
    elseif parent and parent == badge then chargeTicker = frame
    else eventFrame = frame end
    return frame
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
local function event(name, ...)
    if name == "UNIT_SPELLCAST_START" then
        activeCastGUID, activeSpellID = select(2, ...), select(3, ...)
        castStart = now
    end
    eventFrame.scripts.OnEvent(eventFrame, name, ...)
end
local function advance(seconds)
    now = now + seconds
    if badge and badge.scripts.OnUpdate then badge.scripts.OnUpdate(badge, seconds) end
    if chargeTicker and chargeTicker.shown and chargeTicker.scripts.OnUpdate then
        chargeTicker.scripts.OnUpdate(chargeTicker, seconds)
    end
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then timer.fn() else timers[#timers + 1] = timer end
    end
end

for i = 1, 16 do
    local name = ("Media/FlightStyle/flight-%02d.png"):format(i)
    local file = assert(io.open(name, "rb"), "missing animation art " .. name)
    file:close()
end
for i = 1, 20 do
    local name = ("Media/FlightStyle/creature-%02d.png"):format(i)
    local file = assert(io.open(name, "rb"), "missing creature art " .. name)
    file:close()
end
for i = 1, 4 do
    local name = ("Media/FlightStyle/turn-%02d.png"):format(i)
    local file = assert(io.open(name, "rb"), "missing creature turn art " .. name)
    file:close()
end
for gap = 1, 19 do
    local suffixes = gap >= 6 and gap <= 10 and
        (gap == 9 and { "50", "67" } or { "33", "67" }) or { "50" }
    for _, suffix in ipairs(suffixes) do
        local name = ("Media/FlightStyle/morph-g%02d-%s.png"):format(gap, suffix)
        local file = assert(io.open(name, "rb"), "missing in-between art " .. name)
        file:close()
    end
end
for _, name in ipairs({ "empty-skyriding.png", "empty-steady.png", "compact-housing.png" }) do
    local path = "Media/FlightStyle/" .. name
    local file = assert(io.open(path, "rb"), "missing animation effect " .. path)
    file:close()
end

event("PLAYER_LOGIN")
assert(badge and badge.shown and badge.style == "steady", "steady aura should show the steady badge")
assert(#badge.preloadedArt == 48, "all 48 creature stages should be loaded before the first cast")
assert(#badge.preloadedFrames == 16, "the original emblem sequence must be ready before the cast")
assert(not badge.wind and not badge.veil and not badge.rim,
    "the rejected swirling overlays must not appear in the flight indicator")
assert(badge.icon.layer == "ARTWORK" and badge.blend.layer == "ARTWORK"
    and badge.blend.sublevel > badge.icon.sublevel
    and badge.original.layer == "ARTWORK"
    and badge.original.sublevel > badge.blend.sublevel
    and badge.creature.layer == "OVERLAY",
    "the transparent creature must draw above every sky and opaque emblem")
assert(badge.icon.path:find("flight%-16%.png"), "steady badge should use last art frame")
assert(badge.mouse == false, "badge must not block ordinary HUD clicks")
assert(chargeTicker and not chargeTicker.shown,
    "charge jewels must stay hidden in Steady Flight")
for _, gem in ipairs(badge.chargeGems) do
    assert(gem.core.alpha == 0 and gem.bezel.alpha == 0,
        "Steady Flight must not leave charge jewels over the bird")
end

shift = true
event("MODIFIER_STATE_CHANGED")
assert(badge.mouse == true, "holding Shift must enable badge dragging")
badge.scripts.OnDragStart(badge)
assert(badge.moving, "Shift-drag must start moving")
badge.x, badge.y = 110, -80
badge.scripts.OnDragStop(badge)
assert(settings.flightIndicatorX == 110 and settings.flightIndicatorY == -80,
    "dragged position must be saved")
shift = false
event("MODIFIER_STATE_CHANGED")
assert(badge.mouse == false, "releasing Shift must stop intercepting clicks")

event("UNIT_SPELLCAST_START", "player", "cast-one", 460003)
assert(badge.scripts.OnUpdate, "Switch Flight Style cast must begin the animation")
assert(badge.castTicks[1].alpha > 0 and not chargeTicker.shown,
    "the cast arc should appear while charge jewels step aside")
assert(badge.original.alpha == 1 and badge.creature.alpha == 0,
    "the starting emblem should be visible before the creature appears")
local function creatureStage()
    for index, texture in ipairs(badge.preloadedArt) do
        if texture.path == badge.creature.path then return index end
    end
    error("creature texture is outside the authored sequence")
end
local previous = 49
for second = 1, 3 do
    advance(1)
    local stage = creatureStage()
    assert(stage < previous and math.abs(stage - (48 - 43 * second / 5 / 0.82)) <= 1,
        "bird-to-dragon poses must progress evenly until the settling tail")
    previous = stage
end
advance(0.9)
assert(badge.icon.path:find("empty%-steady%.png")
    and badge.blend.path:find("empty%-skyriding%.png")
    and badge.blend.alpha > 0.95
    and badge.original.path:find("flight%-05%.png")
    and badge.original.alpha > 0 and badge.creature.alpha > 0,
    "the dragon must remain in front of the darkening sky during the handoff")
advance(0.1)
assert(badge.icon.path:find("empty%-steady%.png")
    and badge.original.alpha > 0 and badge.original.alpha < 1,
    "the authored dragon tail should begin only in the final second")
event("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-one", 460003)
assert(not badge.scripts.OnUpdate and badge.style == "steady", "interrupted cast must restore prior state")
assert(badge.blend.alpha == 0 and badge.creature.alpha == 0,
    "interruption must clear all animated layers")

castDuration = 7
event("UNIT_SPELLCAST_START", "player", "cast-two", 460002)
advance(5)
assert(creatureStage() < 48 and badge.creature.alpha > 0 and badge.scripts.OnUpdate,
    "a longer live cast must not finish its animation two seconds early")
advance(2)
assert(badge.icon.path:find("flight%-02%.png")
    and badge.blend.path:find("flight%-01%.png")
    and math.abs(badge.blend.alpha - 1) < 0.001 and badge.creature.alpha == 0,
    "the dragon's final settle must end exactly with the live cast")
aura = nil
event("UNIT_SPELLCAST_STOP", "player", "cast-two", 460002)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-two", 460002)
advance(0)
assert(badge.style == "skyriding" and not badge.scripts.OnUpdate,
    "successful cast must settle on the actual new style")
assert(badge.icon.path:find("flight%-01%.png"), "Skyriding must use first art frame")
assert(chargeTicker.shown and badge.castTicks[1].alpha == 0,
    "Skyriding charges should return after the cast arc vanishes")

chargeStart = now
event("SPELL_UPDATE_CHARGES")
advance(0.3)
assert(#badge.chargeGems == 6 and #badge.castTicks == 12,
    "the instrument needs six jewels and a restrained cast arc")
assert(badge.chargeGems[4].core.g > badge.chargeGems[5].core.g
    and badge.chargeGems[5].core.alpha > 0
    and badge.chargeGems[6].core.alpha > 0,
    "four ready charges should light four jewels and leave two dim")
local initialRefill = badge.chargeGems[5].core.g
advance(4.7)
assert(badge.chargeGems[5].core.g > initialRefill,
    "the next jewel should brighten smoothly as its charge recovers")
chargeCount = 5
chargeStart = now
event("SPELL_UPDATE_CHARGES")
advance(0.1)
assert(badge.chargeGems[5].core.g > badge.chargeGems[6].core.g
    and badge.chargeGems[5].glow.alpha > 0.2,
    "a recovered charge should light and briefly glint")
mounted, flying = true, false
advance(0.1)
local beforeTakeoff = badge.chargeGems[1].glow.alpha
flying = true
advance(0.1)
assert(badge.chargeGems[1].glow.alpha > beforeTakeoff,
    "takeoff should add one restrained pulse to the jewel ring")

chargeSecret = true
event("SPELL_UPDATE_CHARGES")
assert(badge.chargeGems[1].core.alpha == 0,
    "secret charge values must hide the jewels rather than guess")
chargeSecret = false
event("SPELL_UPDATE_CHARGES")
assert(badge.chargeGems[1].core.alpha > 0,
    "jewels should recover when safe data returns")
primaryChargeAvailable = false
event("SPELL_UPDATE_CHARGES")
assert(badge.chargeGems[1].core.alpha > 0,
    "Skyward Ascent should provide the shared pool when Surge Forward is unavailable")
primaryChargeAvailable = true
chargeAvailable = false
event("SPELL_UPDATE_CHARGES")
assert(badge.chargeGems[1].core.alpha == 0,
    "missing spell data must hide the jewels rather than invent six charges")
chargeAvailable = true
event("SPELL_UPDATE_CHARGES")
chargeStart = 0
event("SPELL_UPDATE_CHARGES")
advance(0.1)
assert(badge.chargeGems[6].core.g < 0.3,
    "an inactive charge cooldown must not fabricate a full refill")
chargeStart = now
event("SPELL_UPDATE_CHARGES")
settings.flightIndicatorCharges = false
addon.RefreshFlightIndicator()
assert(not chargeTicker.shown and badge.chargeGems[1].core.alpha == 0,
    "the charge-jewels option must actually disable them")
settings.flightIndicatorCharges = true
addon.RefreshFlightIndicator()
advance(0.3)
assert(chargeTicker.shown and badge.chargeGems[1].core.alpha > 0,
    "the charge-jewels option must restore them")

castDuration = 5
event("UNIT_SPELLCAST_START", "player", "cast-forward", 436854)
advance(2.5)
assert(not chargeTicker.shown and badge.chargeGems[1].core.alpha == 0
    and badge.castTicks[6].alpha > badge.castTicks[7].alpha,
    "the cast arc should advance while charge jewels are hidden")
assert(badge.icon.path:find("flight%-05%.png")
    and badge.blend.path:find("flight%-06%.png")
    and badge.blend.alpha == 0
    and badge.creature.alpha == 0,
    "the dragon should remain legible halfway through the live cast")
advance(1.5)
assert(badge.icon.path:find("flight%-10%.png")
    and badge.blend.path:find("flight%-11%.png")
    and badge.blend.alpha == 1,
    "the dragon-to-bird morph should still be advancing near the cast end")
event("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-forward", 436854)
assert(badge.style == "skyriding" and badge.creature.alpha == 0,
    "cancelling the forward transition must restore its static dragon art")
assert(chargeTicker.shown and badge.castTicks[1].alpha == 0,
    "an interrupted cast must restore jewels and clear progress")

event("UNIT_SPELLCAST_START", "player", "cast-early", 436854)
advance(4)
aura = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-early", 436854)
assert(badge.scripts.OnUpdate and badge.style == "skyriding",
    "an early success event must not cut the forward morph short")
advance(0.9)
assert(badge.scripts.OnUpdate and badge.blend.alpha > 0,
    "the bird transition should continue until the measured cast ends")
advance(0.1)
assert(badge.style == "steady" and not badge.scripts.OnUpdate
    and badge.icon.path:find("flight%-16%.png"),
    "the forward cast must settle on the exact steady art at its end")
aura = nil
event("UNIT_AURA", "player")
assert(badge.style == "skyriding", "the next aura change should still update the badge")

secret = true
aura = true
event("UNIT_AURA", "player")
assert(badge.style == "skyriding", "secret aura state must not trigger a wrong-state switch")
secret = false
event("UNIT_AURA", "player")
assert(badge.style == "steady", "ordinary aura change must update the static indicator")
assert(not chargeTicker.shown and badge.chargeGems[1].core.alpha == 0,
    "switching to Steady Flight must hide the charge system")

settings.flightIndicatorCastProgress = false
event("UNIT_SPELLCAST_START", "player", "cast-three", 460002)
advance(0.5)
assert(badge.castTicks[1].alpha == 0,
    "the cast-progress option must remove the progress arc")
event("UNIT_SPELLCAST_STOP", "player", "cast-three", 460002)
advance(0.1)
assert(badge.style == "steady" and not badge.scripts.OnUpdate,
    "a cast stopped without success must restore the old badge")
settings.flightIndicatorCastProgress = true

event("UNIT_SPELLCAST_START", "player", "cast-four", 460003)
event("PLAYER_ENTERING_WORLD")
assert(not badge.scripts.OnUpdate, "zoning must not strand an active animation")

settings.flightIndicatorSize = "large"
addon.RefreshFlightIndicator()
assert(badge.width == 132 and badge.height == 132, "size setting must resize the badge")

local function ornamentsFit(size)
    settings.flightIndicatorSize = size
    addon.RefreshFlightIndicator()
    local half = badge.width / 2
    for _, gem in ipairs(badge.chargeGems) do
        local diamondHalf = gem.glow.width * math.sqrt(2) / 2
        assert(math.abs(gem.glow.x) + diamondHalf <= half + 0.001
            and math.abs(gem.glow.y) + diamondHalf <= half + 0.001,
            "charge jewel glow must fit inside the " .. size .. " emblem")
    end
end
ornamentsFit("small")
ornamentsFit("medium")
ornamentsFit("large")

settings.flightIndicatorLayout = "compact"
settings.flightIndicatorSize = "medium"
addon.RefreshFlightIndicator()
assert(badge.width == 158 and badge.height == 56
    and badge.x == -703 and badge.y == 338,
    "rounded compact view should sit beside the default radar launcher")
assert(badge.housing.path:find("compact%-housing%.png")
    and badge.housing.alpha == 1 and badge.icon.path:find("flight%-16%.png")
    and badge.label.shown and badge.label.text == "STEADY FLIGHT",
    "compact view must have a separate rounded housing, live art, and state text")
assert(badge.icon.x < 0 and badge.icon.width < badge.height
    and badge.housing.sublevel > badge.icon.sublevel,
    "the creature medallion must project from the left side of the capsule")
for size, dimensions in pairs({ small = { 132, 48 }, medium = { 158, 56 }, large = { 184, 66 } }) do
    settings.flightIndicatorSize = size
    addon.RefreshFlightIndicator()
    assert(badge.width == dimensions[1] and badge.height == dimensions[2],
        "rounded compact size must scale the authored housing at " .. size)
    assert(badge.label.x + badge.label.width <= badge.width - 5
        and badge.label.fontSize <= badge.height * 0.2 + 1,
        "compact state text must keep a readable inner gutter at " .. size)
    if size == "small" then
        assert(badge.label.text == "STEADY", "small size needs a short, unclipped state label")
    end
    for _, gem in ipairs(badge.chargeGems) do
        local diamondHalf = gem.glow.width * math.sqrt(2) / 2
        assert(math.abs(gem.glow.x) + diamondHalf <= badge.width / 2 + 0.001
            and math.abs(gem.glow.y) + diamondHalf <= badge.height / 2 + 0.001,
            "compact charge jewels must fit inside the " .. size .. " housing")
    end
end
settings.flightIndicatorSize = "medium"
addon.RefreshFlightIndicator()
local originalWidth, originalHeight, originalCenter =
    UIParent.GetWidth, UIParent.GetHeight, UIParent.GetCenter
UIParent.GetWidth = function() return 640 end
UIParent.GetHeight = function() return 480 end
UIParent.GetCenter = function() return 320, 240 end
addon.RefreshFlightIndicator()
assert(badge.x == -63 and badge.y == 38,
    "compact default must stay beside the launcher on a small screen")
settings.flightIndicatorCompactX, settings.flightIndicatorCompactY = -1000, 1000
addon.RefreshFlightIndicator()
assert(math.abs(badge.x) <= (640 - badge.width) / 2
    and math.abs(badge.y) <= (480 - badge.height) / 2,
    "a dragged compact view must remain on a small screen")
UIParent.GetWidth, UIParent.GetHeight, UIParent.GetCenter =
    originalWidth, originalHeight, originalCenter
settings.flightIndicatorCompactX, settings.flightIndicatorCompactY = nil, nil
addon.RefreshFlightIndicator()
shift = true
event("MODIFIER_STATE_CHANGED")
badge.x, badge.y = -400, 300
badge.scripts.OnDragStop(badge)
assert(settings.flightIndicatorCompactX == -400 and settings.flightIndicatorCompactY == 300,
    "compact Shift-drag must save an independent position")
settings.flightIndicatorLayout = "emblem"
addon.RefreshFlightIndicator()
assert(badge.x == 110 and badge.y == -80 and badge.width == 104
    and badge.icon.path:find("flight%-16%.png") and badge.housing.alpha == 0
    and not badge.label.shown,
    "switching back must restore the full emblem and its own position")
settings.flightIndicatorLayout = "compact"
addon.RefreshFlightIndicator()
assert(badge.x == -400 and badge.y == 300 and badge.width == 158,
    "returning to rounded compact must restore its saved position")
shift = false
event("MODIFIER_STATE_CHANGED")

aura = nil
chargeStart = now
event("UNIT_AURA", "player")
advance(0.3)
assert(badge.icon.path:find("flight%-01%.png")
    and badge.chargeGems[1].core.alpha > 0,
    "rounded compact Skyriding must retain the dragon art and charge jewels")
assert(badge.label.text == "SKYRIDING", "compact text must track the flight style")
settings.flightIndicatorCharges = false
addon.RefreshFlightIndicator()
assert(badge.chargeGems[1].core.alpha == 0,
    "the charge setting must also control miniature jewels")
settings.flightIndicatorCharges = true
addon.RefreshFlightIndicator()
advance(0.3)
assert(badge.chargeGems[1].core.alpha > 0,
    "restoring charges must relight miniature jewels")
event("UNIT_SPELLCAST_START", "player", "compact-forward", 436854)
advance(2.5)
assert(badge.castTicks[6].alpha > badge.castTicks[7].alpha
    and badge.icon.path:find("flight%-05%.png")
    and badge.blend.path:find("flight%-06%.png")
    and badge.chargeGems[1].core.alpha == 0,
    "rounded compact must retain the full morph and cast progress")
advance(1.5)
aura = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "compact-forward", 436854)
assert(badge.scripts.OnUpdate and badge.style == "skyriding",
    "an early success must not shorten the compact morph")
advance(1)
assert(badge.style == "steady" and badge.icon.path:find("flight%-16%.png")
    and badge.castTicks[1].alpha == 0,
    "rounded compact must settle on the steady art at cast completion")
event("UNIT_SPELLCAST_START", "player", "compact-reverse", 460003)
advance(2.5)
assert(badge.creature.alpha > 0 and badge.castTicks[6].alpha > 0,
    "the compact reverse cast must show the same creature morph and progress")
advance(2.5)
aura = nil
event("UNIT_SPELLCAST_SUCCEEDED", "player", "compact-reverse", 460003)
assert(badge.style == "skyriding" and badge.icon.path:find("flight%-01%.png"),
    "the compact reverse cast must settle on the original dragon art")

settings.flightIndicatorCastProgress = false
event("UNIT_SPELLCAST_START", "player", "compact-no-bar", 460002)
advance(0.5)
assert(badge.castTicks[1].alpha == 0,
    "the cast-progress option must also control rounded compact")
event("UNIT_SPELLCAST_INTERRUPTED", "player", "compact-no-bar", 460002)
settings.flightIndicatorCastProgress = true

settings.flightIndicatorEnabled = false
addon.RefreshFlightIndicator()
assert(not badge.shown and not badge.scripts.OnUpdate, "disabling indicator must hide and stop it")

print("flight indicator tests passed")
