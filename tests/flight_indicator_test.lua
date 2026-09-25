local source = arg[1] or "WaffleHouse_FlightIndicator.lua"
local settings = { flightIndicatorEnabled = true, flightIndicatorSize = "medium" }
local addon = { GetSettings = function() return settings end }
local aura, secret, shift, now = true, false, false, 0
local eventFrame, badge
local timers = {}

GetTime = function() return now end
IsShiftKeyDown = function() return shift end
issecretvalue = function() return false end
C_Secrets = { ShouldAurasBeSecret = function() return secret end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(spellID)
    assert(spellID == 404468)
    return aura and { spellId = spellID } or nil
end }
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { due = now + delay, fn = fn } end }
UnitCastingInfo = function() return "Switch Flight Style", nil, nil, now * 1000, (now + 5) * 1000 end

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
    function f:CreateTexture()
        local texture = {}
        function texture:SetAllPoints() end
        function texture:SetTexture(path) self.path = path end
        function texture:SetAlpha(alpha) self.alpha = alpha end
        return texture
    end
    return f
end

CreateFrame = function(_, name)
    local frame = NewFrame(name)
    if name == "WaffleHouseFlightIndicator" then badge = frame else eventFrame = frame end
    return frame
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
local function event(name, ...)
    eventFrame.scripts.OnEvent(eventFrame, name, ...)
end
local function advance(seconds)
    now = now + seconds
    if badge and badge.scripts.OnUpdate then badge.scripts.OnUpdate(badge, seconds) end
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

event("PLAYER_LOGIN")
assert(badge and badge.shown and badge.style == "steady", "steady aura should show the steady badge")
assert(badge.icon.path:find("flight%-16%.png"), "steady badge should use last art frame")
assert(badge.mouse == false, "badge must not block ordinary HUD clicks")

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
advance(2.5)
assert(badge.icon.path:find("flight%-09%.png") or badge.icon.path:find("flight%-08%.png"),
    "steady-to-skyriding must run the flipbook in reverse")
event("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-one", 460003)
assert(not badge.scripts.OnUpdate and badge.style == "steady", "interrupted cast must restore prior state")

event("UNIT_SPELLCAST_START", "player", "cast-two", 460002)
advance(5)
aura = nil
event("UNIT_SPELLCAST_STOP", "player", "cast-two", 460002)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-two", 460002)
advance(0)
assert(badge.style == "skyriding" and not badge.scripts.OnUpdate,
    "successful cast must settle on the actual new style")
assert(badge.icon.path:find("flight%-01%.png"), "Skyriding must use first art frame")

secret = true
aura = true
event("UNIT_AURA", "player")
assert(badge.style == "skyriding", "secret aura state must not trigger a wrong-state switch")
secret = false
event("UNIT_AURA", "player")
assert(badge.style == "steady", "ordinary aura change must update the static indicator")

event("UNIT_SPELLCAST_START", "player", "cast-three", 460002)
event("UNIT_SPELLCAST_STOP", "player", "cast-three", 460002)
advance(0.1)
assert(badge.style == "steady" and not badge.scripts.OnUpdate,
    "a cast stopped without success must restore the old badge")

event("UNIT_SPELLCAST_START", "player", "cast-four", 460003)
event("PLAYER_ENTERING_WORLD")
assert(not badge.scripts.OnUpdate, "zoning must not strand an active animation")

settings.flightIndicatorSize = "large"
addon.RefreshFlightIndicator()
assert(badge.width == 132 and badge.height == 132, "size setting must resize the badge")

settings.flightIndicatorEnabled = false
addon.RefreshFlightIndicator()
assert(not badge.shown and not badge.scripts.OnUpdate, "disabling indicator must hide and stop it")

print("flight indicator tests passed")
