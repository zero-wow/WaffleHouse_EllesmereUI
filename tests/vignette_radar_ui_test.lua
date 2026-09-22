local sourcePath = arg[1] or "WaffleHouse_VignetteRadar.lua"
local legendSourcePath = arg[2] or "WaffleHouse_VignetteRadarLegend.lua"
local targetPickerSourcePath = arg[3] or "WaffleHouse_VignetteRadarTargetPicker.lua"
unpack = table.unpack

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetRight() return self.right or ((self:GetLeft() or 0) + self:GetWidth()) end
function methods:SetPoint(...) self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetMovable(value) self.movable = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:RegisterForClicks(...) self.clickButtons = { ... } end
function methods:RegisterForDrag(...) self.dragButtons = { ... } end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:SetHighlightTexture(texture) self.highlight = setmetatable({ texture = texture }, { __index = methods }) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetTexture(value) self.texture = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha == nil and 1 or self.alpha end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...) self.startPoint = { ... } end
function methods:SetEndPoint(...) self.endPoint = { ... } end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:IsShown() return self.shown == true end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetLeft() return 30 end
function methods:GetTop() return 380 end
function methods:CreateTexture()
    local texture = setmetatable({ kind = "Texture", parent = self }, { __index = methods })
    objects[#objects + 1] = texture
    return texture
end
function methods:CreateFontString()
    local label = setmetatable({ kind = "FontString", parent = self }, { __index = methods })
    objects[#objects + 1] = label
    return label
end
function methods:CreateLine()
    local line = setmetatable({ kind = "Line", parent = self }, { __index = methods })
    objects[#objects + 1] = line
    return line
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = false }, { __index = methods })
    objects[#objects + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
UIParent:Show()
STANDARD_TEXT_FONT = "default.ttf"
SlashCmdList = {}
GameTooltip = {
    SetOwner = function() end, SetText = function() end, AddLine = function() end,
    Show = function() end, Hide = function() end,
}
C_Timer = { After = function(_, callback) callback() end }
C_Map = {
    GetBestMapForUnit = function() return 777 end,
    GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
    GetWorldPosFromMapPos = function(_, position) return 42, { x = position.x * 1000, y = position.y * 1000 } end,
}
C_VignetteInfo = {
    GetVignettes = function() return {} end,
    GetVignetteInfo = function() end,
    GetVignettePosition = function() end,
}
GetPlayerFacing = function() return 0 end
issecretvalue = function() return false end

local function control(config)
    local button = CreateFrame("Button", nil, UIParent)
    button.config = config
    return button
end
local Widgets = {}
function Widgets:SectionHeader(parent, text, y)
    local frame = CreateFrame("Frame", nil, parent); frame.sectionText, frame.y = text, y
    return frame, 40
end
function Widgets:DualRow(parent, y, leftConfig, rightConfig)
    local frame = CreateFrame("Frame", nil, parent); frame.y = y
    frame._leftRegion = { _control = control(leftConfig) }
    frame._rightRegion = { _control = control(rightConfig) }
    return frame, 50
end
EllesmereUI = { EXPRESSWAY = "native-eui-font.ttf", Widgets = Widgets }

local settings = { vignetteRadarEnabled = true, vignetteRadarHideWhenEmpty = true, vignetteRadarRange = 450 }
local addon = { GetSettings = function() return settings end }
assert(loadfile(legendSourcePath))("WaffleHouse_EllesmereUI", addon)
assert(loadfile(targetPickerSourcePath))("WaffleHouse_EllesmereUI", addon)
assert(loadfile(sourcePath))("WaffleHouse_EllesmereUI", addon)

local optionsParent = CreateFrame("Frame", nil, UIParent)
local contentHeight = addon.BuildVignetteRadarOptions(optionsParent, 0)
assert(contentHeight == -190, "radar options must reserve one header and three native rows without changing the signed layout cursor")
local sectionFound, nativeControls = false, 0
for _, object in ipairs(objects) do
    if object.sectionText == "VIGNETTE RADAR" then sectionFound = true end
    if object.config and object.config.text then nativeControls = nativeControls + 1 end
end
assert(sectionFound and nativeControls >= 6, "Adventure options need a populated native radar section")

settings.vignetteRadarEnabled = false
SlashCmdList.WAFFLEHOUSEVIGNETTERADAR("preview")
local panel = assert(_G.WaffleHouseVignetteRadar, "preview must construct the radar panel")
local launcher = assert(_G.WaffleHouseVignetteRadarLauncher, "preview must construct the draggable launcher")
assert(settings.vignetteRadarEnabled == false, "layout preview must not silently enable live tracking")
assert(panel:IsShown() and panel.width == 220 and panel.height == 252, "preview must show the intended compact panel")
assert(panel.field.width == 200 and panel.field.height == 200 and panel.field.point[1] == "BOTTOM"
    and panel.field.point[3] == 9, "radar field must fit below the header with a visible gutter")
assert(panel.drag.width == 128 and panel.target.point[1] == "TOPRIGHT"
    and panel.legend.point[1] == "TOPRIGHT" and panel.close.point[1] == "TOPRIGHT",
    "drag target must stop before the focus, legend, and close controls")
assert(panel.title.font[1] == EllesmereUI.EXPRESSWAY, "radar must use native EllesmereUI typography")
assert(panel.summary.text == "PREVIEW" and #panel.blips == 3,
    "preview must be explicit and render one sample marker for each themed category")
local firstBlip, secondBlip = panel.blips[1], panel.blips[2]
for _, blip in ipairs(panel.blips) do
    assert(blip._seen and blip.target.sample == true, "preview marker must be labeled as sample data")
    assert(blip.target.category and blip.dot.vertexColor[4] == 1,
        "preview and live markers must use an opaque category treatment")
    local x, y = blip.point[4], blip.point[5]
    assert(math.sqrt(x * x + y * y) < 91, "preview markers must remain inside the radar ring")
end
panel.scripts.OnUpdate(panel, 0.06)
assert(panel.blips[1] == firstBlip and panel.blips[2] == secondBlip and firstBlip:IsShown() and secondBlip:IsShown(),
    "render ticks must retain stable blip buttons so hover tooltips do not flicker")
assert(#panel.outerRing == 64 and #panel.middleRing == 64 and #panel.innerRing == 64,
    "all radar rings must be complete and bounded")
assert(panel.clamped == true and panel.movable == true, "panel must remain movable and clamped to screen")
assert(launcher.width == 44 and launcher.height == 44 and launcher.clamped == true and launcher.movable == true,
    "launcher must be a compact draggable instrument that stays on screen")
assert(launcher.clickButtons[1] == "LeftButtonUp" and launcher.clickButtons[2] == "RightButtonUp"
    and launcher.dragButtons[1] == "LeftButton", "launcher must expose distinct click and drag gestures")
assert(#launcher.ring == 24 and #launcher.sweepLines == 2
    and launcher.bezel.texture:find("vignette%-radar%-bezel%.tga$")
    and launcher.closed.texture:find("vignette%-radar%-closed%.tga$"),
    "launcher needs matching jeweled closed and hollow live states")
assert(launcher.rangeLabel.text == "150" and #launcher.miniBlips == 5 and launcher.miniBlips[1]:IsShown(),
    "launcher preview must mirror category dots inside its compact field")
launcher.scripts.OnUpdate(launcher, 0.05)
assert(launcher.halo.alpha >= 0.065 and launcher.halo.alpha <= 0.10 and launcher.alert == nil,
    "live detections may use only a soft low-amplitude glow, never a flashing full-face alert")

panel.legend.scripts.OnClick(panel.legend)
local legendPanel = assert(_G.WaffleHouseVignetteRadarLegend, "radar header must open its attached legend")
assert(legendPanel:IsShown() and legendPanel.point[1] == "TOPLEFT" and legendPanel.point[3] == "TOPRIGHT",
    "legend must open outside the radar with a visible gutter")
legendPanel.rows.rare.scripts.OnClick(legendPanel.rows.rare)
assert(settings.vignetteRadarHighlight == "rare" and firstBlip:GetAlpha() == 1 and secondBlip:GetAlpha() == 0.18,
    "spotlighting a category must keep its dots strong and dim the remaining context")
legendPanel.rows.treasure.toggle.scripts.OnClick(legendPanel.rows.treasure.toggle)
assert(settings.vignetteRadarCategories.treasure == false and not secondBlip:IsShown(),
    "legend category switches must remove disabled dots from the radar immediately")

-- Restore treasure so the specific-vignette picker can exercise more than one row.
addon.VignetteRadarLegend.SetCategoryEnabled("treasure", true)
panel.target.scripts.OnClick(panel.target, "LeftButton")
local targetPanel = assert(_G.WaffleHouseVignetteRadarTargetPicker, "reticle button must open its target picker")
assert(targetPanel:IsShown() and targetPanel.rows[1].target.key == "preview-rare",
    "specific-vignette picker must list current detections nearest first")
targetPanel.rows[1].scripts.OnClick(targetPanel.rows[1])
assert(addon.VignetteRadarTargetPicker.GetFocus() == "preview-rare" and firstBlip:IsShown()
    and not secondBlip:IsShown(), "specific focus must isolate one vignette across the full radar")
panel.target.scripts.OnClick(panel.target, "RightButton")
assert(addon.VignetteRadarTargetPicker.GetFocus() == nil,
    "right-clicking the reticle must restore all category-filtered vignettes")
SlashCmdList.WAFFLEHOUSEVIGNETTERADAR("off")
assert(launcher.closed:IsShown() and not launcher.bezel:IsShown() and not launcher.miniBlips[1]:IsShown(),
    "disabled tracking must close the live center into its filled jeweled state")

io.write("vignette radar UI tests passed\n")
