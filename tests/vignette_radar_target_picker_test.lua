local sourcePath = arg[1] or "WaffleHouse_VignetteRadarTargetPicker.lua"

local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
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
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:IsShown() return self.shown == true end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:CreateTexture()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end
function methods:CreateFontString()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = true }, { __index = methods })
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

local addon = {}
assert(loadfile(sourcePath))("WaffleHouse_EllesmereUI", addon)
local picker = assert(addon.VignetteRadarTargetPicker, "target picker must publish its API")
local changes = 0
picker.SetChangeCallback(function() changes = changes + 1 end)
local targets = {
    { key = "a", name = "Alpha Rare", category = "rare", distance = 42, red = 1, green = 0.24, blue = 0.20 },
    { key = "b", name = "Buried Cache", category = "treasure", distance = 73, red = 1, green = 0.68, blue = 0.16 },
    { key = "c", name = "Event One", category = "event", distance = 90 },
    { key = "d", name = "Event Two", category = "event", distance = 105 },
    { key = "e", name = "Other One", category = "other", distance = 120 },
    { key = "f", name = "Other Two", category = "other", distance = 145 },
}
picker.SetProvider(function() return targets end)

local anchor = CreateFrame("Frame", nil, UIParent)
anchor.right = 500
assert(picker.Toggle(anchor) and picker.IsShown(), "focus button must open the attached target list")
local panel = assert(_G.WaffleHouseVignetteRadarTargetPicker, "target list needs a stable global frame name")
assert(panel.width == 250 and panel.height == 258 and panel.clamped == true,
    "specific target picker must stay compact and screen-safe")
assert(panel.point[1] == "TOPLEFT" and panel.point[3] == "TOPRIGHT" and panel.point[4] == 8,
    "specific target picker must open outside the radar with a gutter")
assert(panel.rows[1].target.key == "a" and panel.rows[5].target.key == "e" and panel.next:IsShown(),
    "first focus page must show five current detections with pagination")
assert(panel.rows[1].name.text == "Alpha Rare" and panel.rows[1].meta.text:find("42 YD", 1, true),
    "target rows must identify the vignette and show its distance")

panel.rows[1].scripts.OnClick(panel.rows[1])
assert(picker.GetFocus() == "a" and picker.GetFocusName() == "Alpha Rare" and changes == 1,
    "clicking a row must isolate that exact active vignette")
assert(panel.rows[1].selection:IsShown() and panel.rows[1].action.text == "ACTIVE",
    "focused vignette needs a clear selected state")
panel.clear.scripts.OnClick(panel.clear)
assert(picker.GetFocus() == nil and changes == 2, "SHOW ALL must clear the specific target filter")

panel.next.scripts.OnClick(panel.next)
assert(panel.rows[1].target.key == "f" and not panel.next:IsShown() and panel.previous:IsShown(),
    "paging must expose remaining detections without extending the panel")
panel.rows[1].scripts.OnClick(panel.rows[1])
assert(picker.GetFocus() == "f", "a target on a later page must be focusable")
targets = { targets[1], targets[2] }
assert(picker.ValidateTargets(targets), "a vanished focused target must be cleared")
assert(picker.GetFocus() == nil, "stale target focus must never leave the radar blank")
assert(picker.Toggle(anchor) == false and not picker.IsShown(), "focus button must close the target list")

io.write("vignette radar target picker tests passed\n")
