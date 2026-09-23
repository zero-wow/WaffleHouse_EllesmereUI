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
function Object:CreateTexture()
    self.textures = (self.textures or 0) + 1
    return newObject()
end
function Object:SetColorTexture() end
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
local function outlined()
    local visual = button.textures
    return visual and visual >= 4
end
local function visibleEdges()
    local count = 0
    -- The four highlight textures were created before any pooled reuse.
    for _, visual in ipairs(button._testTextures or {}) do
        if visual.shown then count = count + 1 end
    end
    return count
end
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
assert(outlined() and visibleEdges() == 4, "recent item must receive four visible inset edges")
button:Fire("OnEnter")
assert(visibleEdges() == 0 and bags._recentItems[101], "hover clears only Waffle's outline")

contents[0][1] = { itemID = 102 }
bags._recentItems[101] = nil
bags._recentItems[102] = true
bags:RefreshInventory()
assert(visibleEdges() == 4, "reused item button must highlight the newly acquired item")
settings.bagRecentHighlightEnabled = false
addon.RefreshRecentItemHighlights()
assert(visibleEdges() == 0, "disabling the feature must remove stale pooled outlines")

settings.bagRecentHighlightEnabled = true
settings.bagRecentHighlightClearMode = "close"
addon.ResetRecentItemHighlights()
assert(visibleEdges() == 4, "close mode should show the outline while bags are open")
bags:Hide()
assert(visibleEdges() == 0, "closing bags must clear outlines in close mode")
bags:Show()
bags:RefreshInventory()
assert(visibleEdges() == 0, "a cleared item must stay clear when bags reopen")

settings.bagRecentHighlightClearMode = "timer"
addon.ResetRecentItemHighlights()
assert(visibleEdges() == 4, "timer mode should initially highlight")
flush(30)
assert(visibleEdges() == 0, "timer expiry should clear the outline")

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
assert(newButton.textures == 4, "combat-end refresh should create the deferred outline")

local endY = addon.BuildRecentItemsBagsPage(newObject(), -100)
assert(endY == -145, "recent-items controls must reserve their settings-page height")
assert(addon._options[1].getValue() == true and addon._options[2].getValue() == "timer",
    "the Bags settings controls must expose highlight and clear mode")
print("Recent bag-item highlight regressions passed")
