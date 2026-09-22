local sourcePath = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = assert(file:read("*a"))
file:close()

assert(source:find("if frame._waffleListIgnoreHostRenderUntilBagSettles then return end", 1, true),
    "vendor resize hook must ignore host redraws caused by bag sorting")
assert(source:find("vendorFrame._waffleListIgnoreHostRenderUntilBagSettles = true", 1, true),
    "BAG_UPDATE must suppress transient Vendor Bags redraws")
assert(source:find("vendorFrame._waffleListIgnoreHostRenderUntilBagSettles = nil", 1, true),
    "BAG_UPDATE_DELAYED must release the redraw suppression after sorting settles")
assert(source:find('if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "PLAYER_MONEY"', 1, true),
    "vendor refreshes must be limited to merchant-relevant events")
assert(not source:find("        QueueRefresh()\n    end\nend)", source:find('if event == "MERCHANT_SHOW"', 1, true), true),
    "event handler must not retain an unconditional vendor refresh")

io.write("vendor_bag_sort_refresh_test: ok\n")
