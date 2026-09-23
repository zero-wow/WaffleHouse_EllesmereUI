-- The dot uses the host's own native MerchantFrame path without changing its
-- saved layout preset.  Run from the Waffle House source directory.
local addon = { refreshes = 0 }
function addon.Refresh() addon.refreshes = addon.refreshes + 1 end

local function MakeButton(parent)
    local button = { parent = parent, scripts = {}, shown = true }
    function button:SetSize(width, height) self.width, self.height = width, height end
    function button:SetPoint(...) self.point = { ... } end
    function button:SetFrameLevel(level) self.level = level end
    function button:CreateTexture()
        local texture = {}
        function texture:SetSize(width, height) self.width, self.height = width, height end
        function texture:SetPoint(...) self.point = { ... } end
        function texture:SetColorTexture(...) self.color = { ... } end
        return texture
    end
    function button:SetScript(script, callback) self.scripts[script] = callback end
    function button:Hide() self.shown = false end
    function button:SetShown(shown) self.shown = shown end
    function button:IsShown() return self.shown end
    return button
end

local created
CreateFrame = function(_, _, parent)
    created = MakeButton(parent)
    return created
end
MerchantFrame = { shown = true, level = 5 }
function MerchantFrame:IsShown() return self.shown end
function MerchantFrame:GetFrameLevel() return self.level end
local combat = false
InCombatLockdown = function() return combat end

local originalMode = function() return true end
local host = { IsEUILayoutActive = originalMode, savedLayout = "custom", refreshes = {} }
function host.RefreshMerchantLayout()
    host.refreshes[#host.refreshes + 1] = host.IsEUILayoutActive()
end
EllesmereUIVendorBag = host

local module, err = loadfile("WaffleHouse_VendorNativeView.lua")
assert(module, err)
module("WaffleHouse_EllesmereUI", addon)

assert(addon.SetVendorNativeView(true), "native view should open from a live merchant")
assert(addon.IsVendorNativeViewActive(), "native flag must be active")
assert(host.refreshes[1] == false, "host must render Blizzard's merchant frame")
assert(host.savedLayout == "custom", "comparison must not mutate the saved layout")
assert(created and created.parent == MerchantFrame and created:IsShown(), "native frame needs its own return dot")
assert(created.width == 18 and created.point[4] == -42, "return dot must clear the close button")

created.scripts.OnClick()
assert(not addon.IsVendorNativeViewActive(), "return dot must restore the custom view")
assert(host.refreshes[2] == true and not created:IsShown(), "host custom layout and return-dot visibility must restore")
assert(addon.refreshes == 1, "returning must repaint Waffle's custom vendor controls")

assert(addon.SetVendorNativeView(true), "second comparison should remain available")
addon.ResetVendorNativeView()
assert(not addon.IsVendorNativeViewActive() and not created:IsShown(), "merchant close clears the session override")
assert(host.IsEUILayoutActive(), "next merchant must use the saved EUI layout")

local priorRefreshes = #host.refreshes
combat = true
assert(not addon.SetVendorNativeView(true), "combat must block presentation changes")
assert(#host.refreshes == priorRefreshes, "combat must not touch merchant layout")
combat = false
MerchantFrame.shown = false
assert(not addon.SetVendorNativeView(true), "closed merchants cannot be switched")

io.write("Vendor native-view tests passed\n")
