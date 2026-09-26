local source = arg[1] or "WaffleHouse_Toast.lua"
local addon = {}
local frames = {}
local function object()
    local o = { shown = true }
    function o:SetSize() end
    function o:SetPoint() end
    function o:SetFrameStrata() end
    function o:EnableMouse(value) self.mouse = value end
    function o:SetBackdrop() end
    function o:SetBackdropColor() end
    function o:SetBackdropBorderColor() end
    function o:SetWidth() end
    function o:SetColorTexture() end
    function o:SetTexture() end
    function o:SetFont() end
    function o:SetJustifyH() end
    function o:SetTextColor() end
    function o:SetText(value) self.text = value end
    function o:SetAlpha(value) self.alpha = value end
    function o:Hide() self.shown = false end
    function o:Show() self.shown = true end
    function o:IsShown() return self.shown end
    function o:SetScript(name, fn) self[name] = fn end
    function o:CreateTexture() return object() end
    function o:CreateFontString() return object() end
    return o
end
UIParent = {}
CreateFrame = function(_, name)
    local frame = object()
    frames[name] = frame
    return frame
end
assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
assert(addon.ShowWarningToast("tomtom", "RESOURCE WATCH", "TomTom is using CPU", "Warning only"))
local toast = frames.WaffleHouseWarningToast
assert(toast and toast:IsShown() and toast.mouse == false, "warning must show without a click target")
assert(toast.title.text == "RESOURCE WATCH" and toast.message.text == "TomTom is using CPU")
assert(not addon.ShowWarningToast("tomtom", "RESOURCE WATCH", "duplicate"), "active toast must deduplicate")
assert(addon.ShowWarningToast("another", "RESOURCE WATCH", "Another addon", "Warning only"))
toast:OnUpdate(8.1)
assert(toast:IsShown() and toast.message.text == "Another addon", "queued warning must display after first fades")
assert(addon.ShowWarningToast("tomtom", "RESOURCE WATCH", "new episode", "Warning only"),
    "finished warning may be shown again")
toast:OnUpdate(8.1)
assert(toast:IsShown() and toast.message.text == "new episode")
toast:OnUpdate(8.1)
assert(not toast:IsShown(), "warning must auto-dismiss without a Close button")
print("warning_toast_test: ok")
