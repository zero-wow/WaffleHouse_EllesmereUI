-- Frozen-marker placement must expose every standard frame anchor and keep
-- the SavedVariables migration in sync with the Bags-page dropdown.

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local main = read(arg[1] or "WaffleHouse_EllesmereUI.lua")
local bags = read(arg[2] or "WaffleHouse_BagSlotFreeze.lua")
for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
    assert(main:find(point .. " = true", 1, true), "settings migration is missing " .. point)
    assert(bags:find(point .. ' = "', 1, true), "marker dropdown is missing " .. point)
end
assert(bags:find("MARKER_POSITION_ORDER", 1, true), "marker dropdown must use its complete anchor order")
assert(bags:find("corner, edge, or the center", 1, true), "marker tooltip must explain full placement support")
assert(main:find("bagSlotFreezeMarkerSize = 11", 1, true), "the frozen-marker default height must be 11px")
assert(main:find("bagSlotFreezeMarkerDefaultVersion = 3", 1, true), "the frozen-marker default migration must be versioned")
assert(bags:find("FREEZE_MARKER_DEFAULT_SIZE = 11", 1, true), "the Bags page must use the 11px frozen-marker default")

io.write("bag marker anchor tests passed\n")
