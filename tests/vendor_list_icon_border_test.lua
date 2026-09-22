-- Easy Access list-view quality-border regression checks.
-- Run from the addon source directory:
--   lua tests/vendor_list_icon_border_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file, err = io.open(SOURCE, "rb")
assert(file, "could not open " .. SOURCE .. ": " .. tostring(err))
local source = file:read("*a")
file:close()

local function assertContains(pattern, message)
    assert(source:find(pattern) ~= nil, message)
end

assertContains("local function SetVendorListNativeBorderVisible%(button, visible%)",
    "list view must explicitly suppress the host's full-row inset border")
assertContains("local iconBorderHost = CreateFrame%(\"Frame\", nil, button%)",
    "list view must create a dedicated icon-sized quality border host")
assertContains("iconBorderHost:SetSize%(28, 28%)",
    "quality border host must remain icon-sized")
assertContains("SetVendorListNativeBorderVisible%(button, false%)",
    "stretched list rows must hide the host quality border")
assertContains("SetVendorListIconBorderColor%(button, r, g, b%)",
    "item quality color must be applied to the icon border")
assertContains("SetVendorListNativeBorderVisible%(button, true%)",
    "grid restore must bring the host quality border back")

io.write("Vendor list icon-border regression checks passed\n")
