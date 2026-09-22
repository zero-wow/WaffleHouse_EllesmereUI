local sourcePath = arg[1] or "WaffleHouse_VignetteRadar.lua"
unpack = table.unpack

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
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
function methods:RegisterForDrag(...) self.dragButtons = { ... } end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:SetHighlightTexture(texture) self.highlight = setmetatable({ texture = texture }, { __index = methods }) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetTexture(value) self.texture = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...) self.startPoint = { ... } end
function methods:SetEndPoint(...) self.endPoint = { ... } end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:IsShown() return self.shown == true end
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
assert(settings.vignetteRadarEnabled == false, "layout preview must not silently enable live tracking")
assert(panel:IsShown() and panel.width == 220 and panel.height == 252, "preview must show the intended compact panel")
assert(panel.field.width == 200 and panel.field.height == 200 and panel.field.point[1] == "BOTTOM"
    and panel.field.point[3] == 9, "radar field must fit below the header with a visible gutter")
assert(panel.drag.width == 182 and panel.close.point[1] == "TOPRIGHT",
    "drag target must stop before the close control")
assert(panel.title.font[1] == EllesmereUI.EXPRESSWAY, "radar must use native EllesmereUI typography")
assert(panel.summary.text == "PREVIEW" and #panel.blips == 2,
    "preview must be explicit and render exactly two sample markers")
local firstBlip, secondBlip = panel.blips[1], panel.blips[2]
for _, blip in ipairs(panel.blips) do
    assert(blip._seen and blip.target.sample == true, "preview marker must be labeled as sample data")
    assert(blip.dot.vertexColor[1] == 1 and blip.dot.vertexColor[2] == 0.18,
        "preview and live markers must share the requested red treatment")
    local x, y = blip.point[4], blip.point[5]
    assert(math.sqrt(x * x + y * y) < 91, "preview markers must remain inside the radar ring")
end
panel.scripts.OnUpdate(panel, 0.06)
assert(panel.blips[1] == firstBlip and panel.blips[2] == secondBlip and firstBlip:IsShown() and secondBlip:IsShown(),
    "render ticks must retain stable blip buttons so hover tooltips do not flicker")
assert(#panel.outerRing == 64 and #panel.middleRing == 64 and #panel.innerRing == 64,
    "all radar rings must be complete and bounded")
assert(panel.clamped == true and panel.movable == true, "panel must remain movable and clamped to screen")

io.write("vignette radar UI tests passed\n")
