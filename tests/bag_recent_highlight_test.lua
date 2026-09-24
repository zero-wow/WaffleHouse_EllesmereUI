-- Exercise the opt-in visual layer without creating or clicking secure items.
local source = assert(io.open(arg[1] or "WaffleHouse_RecentItems.lua", "rb"))
local chunk = source:read("*a")
source:close()

local Object = {}
Object.__index = Object
local function newObject(parent)
    local object = setmetatable({ parent = parent, children = {}, scripts = {}, shown = true }, Object)
    if parent then parent.children[#parent.children + 1] = object end
    return object
end
function Object:GetChildren() return (table.unpack or unpack)(self.children) end
function Object:GetParent() return self.parent end
function Object:GetID() return self.id end
function Object:IsShown() return self.shown end
function Object:IsVisible() return self.shown end
function Object:Show() self.shown = true end
function Object:Hide() self.shown = false; self:Fire("OnHide") end
function Object:SetShown(value) self.shown = value end
function Object:CreateTexture(_, layer, _, subLevel)
    self.textures = (self.textures or 0) + 1
    local texture = newObject()
    texture.layer, texture.subLevel = layer, subLevel
    return texture
end
function Object:SetAtlas(atlas) self.atlas = atlas end
function Object:SetBlendMode(mode) self.blendMode = mode end
function Object:SetVertexColor(...) self.vertexColor = { ... } end
function Object:SetAlpha(alpha) self.alpha = alpha end
function Object:SetAllPoints(parent) self.allPoints = parent end
function Object:CreateAnimationGroup()
    local group = newObject()
    self.animationGroup = group
    return group
end
function Object:SetLooping(looping) self.looping = looping end
function Object:CreateAnimation(kind)
    local animation = newObject()
    animation.kind = kind
    self.animations = self.animations or {}
    self.animations[#self.animations + 1] = animation
    return animation
end
function Object:SetOrder(order) self.order = order end
function Object:SetDuration(duration) self.duration = duration end
function Object:SetFromAlpha(alpha) self.fromAlpha = alpha end
function Object:SetToAlpha(alpha) self.toAlpha = alpha end
function Object:IsPlaying() return self.playing == true end
function Object:Play() self.playing = true; self.playCount = (self.playCount or 0) + 1 end
function Object:Stop() self.playing = false; self.stopCount = (self.stopCount or 0) + 1 end
function Object:SetPoint() end
function Object:SetHeight() end
function Object:SetWidth() end
function Object:RegisterEvent() end
function Object:SetScript(name, callback) self.scripts[name] = callback end
function Object:HookScript(name, callback)
    local original = self.scripts[name]
    self.scripts[name] = function(...)
        if original then original(...) end
        callback(...)
    end
end
function Object:Fire(name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
end

local settings = { bagRecentHighlightEnabled = true, bagRecentHighlightClearMode = "hover" }
local addon = { GetSettings = function() return settings end }
local bags = newObject()
bags._scrollChild = newObject(bags)
bags._recentItems = { [101] = true }
function bags:RefreshInventory() end
local reagent = newObject()
function reagent:RefreshInventory() end
local parent = newObject(bags._scrollChild)
parent.id = 0
local button = newObject(parent)
button.id = 1
local contents = { [0] = { [1] = { itemID = 101 } } }
local timers = {}
local inCombat = false
local events
local env = setmetatable({
    _G = { EUI_Bags = bags, EUI_BagsReagent = reagent },
    C_Container = { GetContainerItemInfo = function(bag, slot)
        return contents[bag] and contents[bag][slot]
    end },
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end },
    CreateFrame = function() events = newObject(); return events end,
    GetTime = function() return 10 end,
    InCombatLockdown = function() return inCombat end,
    hooksecurefunc = function(frame, method, callback)
        local original = frame[method]
        frame[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
    end,
    wipe = function(value) for key in pairs(value) do value[key] = nil end end,
    EllesmereUI = { Widgets = {
        SectionHeader = function(_, _, _, y) return nil, 20 end,
        DualRow = function(_, _, _, left, right)
            addon._options = { left, right }
            return nil, 25
        end,
    } },
}, { __index = _G })
assert(load(chunk, "@WaffleHouse_RecentItems.lua", "t", env))("WaffleHouse_EllesmereUI", addon)

local function flush(delay)
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if not delay or timer.delay == delay then timer.callback()
        else timers[#timers + 1] = timer end
    end
end
local function glow() return button._testTextures and button._testTextures[1] end
local originalCreateTexture = button.CreateTexture
button.CreateTexture = function(self, ...)
    local texture = originalCreateTexture(self, ...)
    self._testTextures = self._testTextures or {}
    self._testTextures[#self._testTextures + 1] = texture
    return texture
end

events:Fire("OnEvent", "ADDON_LOADED", "EllesmereUIBags")
flush(0)
bags:RefreshInventory()
local recentGlow = glow()
assert(button.textures == 1 and recentGlow and recentGlow.shown
    and recentGlow.atlas == "bags-glow-white" and recentGlow.blendMode == "ADD"
    and recentGlow.layer == "OVERLAY" and recentGlow.subLevel == 3
    and recentGlow.allPoints == button and recentGlow.animationGroup:IsPlaying()
    and recentGlow.animationGroup.looping == "REPEAT"
    and #recentGlow.animationGroup.animations == 2,
    "recent item must receive Blizzard's pulsing glow over the full icon, not inset edges")
button:Fire("OnEnter")
assert(not recentGlow.shown and not recentGlow.animationGroup:IsPlaying()
    and bags._recentItems[101], "hover clears only Waffle's glow")

contents[0][1] = { itemID = 102 }
bags._recentItems[101] = nil
bags._recentItems[102] = true
bags:RefreshInventory()
assert(recentGlow.shown and recentGlow.animationGroup:IsPlaying()
    and recentGlow.animationGroup.playCount == 2,
    "reused item button must restart the glow for a newly acquired item")
settings.bagRecentHighlightEnabled = false
addon.RefreshRecentItemHighlights()
assert(not recentGlow.shown and not recentGlow.animationGroup:IsPlaying(),
    "disabling the feature must remove stale pooled glows")

settings.bagRecentHighlightEnabled = true
settings.bagRecentHighlightClearMode = "close"
addon.ResetRecentItemHighlights()
assert(recentGlow.shown, "close mode should show the glow while bags are open")
bags:Hide()
assert(not recentGlow.shown and not recentGlow.animationGroup:IsPlaying(),
    "closing bags must clear the glow in close mode")
bags:Show()
bags:RefreshInventory()
assert(not recentGlow.shown, "a cleared item must stay clear when bags reopen")

settings.bagRecentHighlightClearMode = "timer"
addon.ResetRecentItemHighlights()
assert(recentGlow.shown and recentGlow.animationGroup:IsPlaying(),
    "timer mode should initially pulse")
flush(30)
assert(not recentGlow.shown and not recentGlow.animationGroup:IsPlaying(),
    "timer expiry should stop the glow")

local newParent = newObject(bags._scrollChild)
newParent.id = 0
local newButton = newObject(newParent)
newButton.id = 2
contents[0][2] = { itemID = 103 }
bags._recentItems[103] = true
inCombat = true
bags:RefreshInventory()
assert(not newButton.textures, "secure item regions must not be created during combat")
inCombat = false
events:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
flush(0)
assert(newButton.textures == 1, "combat-end refresh should create the deferred glow")

local endY = addon.BuildRecentItemsBagsPage(newObject(), -100)
assert(endY == -145, "recent-items controls must reserve their settings-page height")
assert(addon._options[1].getValue() == true and addon._options[2].getValue() == "timer",
    "the Bags settings controls must expose highlight and clear mode")
assert(addon._options[1].tooltip:find("glow", 1, true),
    "the settings description must match the animated glow")
print("Recent bag-item highlight regressions passed")
