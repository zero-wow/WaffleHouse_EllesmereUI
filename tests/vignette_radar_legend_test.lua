local sourcePath = arg[1] or "WaffleHouse_VignetteRadarLegend.lua"

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetRight() return self.right or 100 end
function methods:SetPoint(...) self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:IsShown() return self.shown == true end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:CreateTexture()
    local texture = setmetatable({ kind = "Texture", parent = self, shown = true }, { __index = methods })
    objects[#objects + 1] = texture
    return texture
end
function methods:CreateFontString()
    local label = setmetatable({ kind = "FontString", parent = self, shown = true }, { __index = methods })
    objects[#objects + 1] = label
    return label
end

function CreateFrame(kind, name, parent)
    -- Native WoW frames begin shown, which catches lazy-panel initialization bugs.
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = true }, { __index = methods })
    objects[#objects + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
STANDARD_TEXT_FONT = "fallback.ttf"
EllesmereUI = { EXPRESSWAY = "native-eui-font.ttf" }
GameTooltip = {
    SetOwner = function() end, SetText = function() end, AddLine = function() end,
    Show = function() end, Hide = function() end,
}

local settings = {}
local refreshes = 0
local addon = {
    GetSettings = function() return settings end,
    RefreshVignetteRadar = function() refreshes = refreshes + 1 end,
}
assert(loadfile(sourcePath))("WaffleHouse_EllesmereUI", addon)

local legend = assert(addon.VignetteRadarLegend, "legend module must publish its integration API")
for _, category in ipairs({ "rare", "treasure", "event", "other" }) do
    assert(settings.vignetteRadarCategories[category] == true, "all categories must default on: " .. category)
    assert(legend.IsCategoryEnabled(category), "default category state must be readable: " .. category)
end
assert(legend.GetHighlight() == nil, "spotlight must default to all categories")
assert(legend.IsCategoryEnabled("unknown"), "unknown Blizzard categories must safely use the other filter")

local r, g, b = legend.ColorFor("treasure")
assert(r == 1 and g == 0.68 and b == 0.16, "treasure must use the legend's gold treatment")
local _, _, _, _, alpha, normalized = legend.DotStyle("unrecognized")
assert(normalized == "other" and alpha == 1, "dot style must normalize unknown categories without inventing data")

legend.SetHighlight("rare")
assert(settings.vignetteRadarHighlight == "rare", "spotlight selection must persist")
assert(legend.OpacityFor("rare") == 1 and legend.OpacityFor("event") == 0.18,
    "spotlight must preserve the chosen category and dim other enabled dots")
assert(refreshes == 1, "a spotlight change must refresh the radar")

legend.SetCategoryEnabled("treasure", false)
assert(not legend.IsCategoryEnabled("treasure") and legend.OpacityFor("treasure") == 0,
    "disabled categories must be completely filtered")
assert(refreshes == 2, "a category filter change must refresh the radar")
legend.SetCategoryEnabled("rare", false)
assert(legend.GetHighlight() == nil, "disabling the spotlighted category must clear the spotlight")

settings.vignetteRadarHighlight = "invented"
settings.vignetteRadarCategories.event = "bad"
legend.ApplyDefaults(settings)
assert(settings.vignetteRadarHighlight == nil and settings.vignetteRadarCategories.event == true,
    "defaults must repair invalid saved settings")

local anchor = CreateFrame("Frame", nil, UIParent)
anchor.right = 500
assert(legend.Toggle(anchor) == true and legend.IsShown(), "toggle must open the attached legend")
local panel = assert(_G.WaffleHouseVignetteRadarLegend, "legend panel must have a stable global frame name")
assert(panel.width == 206 and panel.height == 166 and panel.clamped == true,
    "legend must use its compact, screen-safe dimensions")
assert(panel.mouseEnabled == true and panel.divider.height == 1,
    "legend surface must capture input and preserve a visible header gutter")
assert(panel.point[1] == "TOPLEFT" and panel.point[3] == "TOPRIGHT" and panel.point[4] == 8,
    "legend must sit outside the radar with an explicit gutter")
assert(panel.title.font[1] == EllesmereUI.EXPRESSWAY and panel.title.text == "RADAR LEGEND",
    "legend must use native EllesmereUI typography")
assert(panel.rows.rare and panel.rows.treasure and panel.rows.event and panel.rows.other,
    "legend must render one independent row for every supported filter")
assert(panel.rows.event.scripts.OnMouseDown and panel.rows.event.scripts.OnMouseUp,
    "category controls must expose native pressed feedback")
assert(panel.rows.rare.toggle.label.text == "OFF", "the UI must reflect persisted filter state")

panel.rows.event.scripts.OnClick(panel.rows.event)
assert(settings.vignetteRadarHighlight == "event", "clicking a category row must spotlight it")
assert(panel.rows.event.selection:IsShown(), "the selected category needs a visible UI treatment")
assert(panel.rows.event.alpha == 1 and panel.rows.other.alpha == 0.58,
    "the selected row must remain strong while nonfocused enabled rows are dimmed")
panel.all.scripts.OnClick(panel.all)
assert(settings.vignetteRadarHighlight == nil, "the ALL action must clear highlighting")

local before = legend.IsCategoryEnabled("other")
panel.rows.other.toggle.scripts.OnClick(panel.rows.other.toggle)
assert(legend.IsCategoryEnabled("other") ~= before, "the row switch must toggle its category filter")
assert(legend.Toggle(anchor) == false and not legend.IsShown(), "toggle must close an open legend")

-- Validate fallback behavior without native EllesmereUI helpers or fonts.
EllesmereUI = nil
local fallbackSettings = {}
local fallbackAddon = { GetSettings = function() return fallbackSettings end }
assert(loadfile(sourcePath))("WaffleHouse_EllesmereUI", fallbackAddon)
assert(fallbackAddon.VignetteRadarLegend.Toggle(anchor), "legend must build without EllesmereUI helper functions")
assert(fallbackAddon.VignetteRadarLegend.Testing.GetPanel().title.font[1] == STANDARD_TEXT_FONT,
    "helper-free mode must use the standard client font")

io.write("vignette radar legend tests passed\n")
