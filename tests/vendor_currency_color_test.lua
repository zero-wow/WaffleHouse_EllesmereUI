local sourcePath = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = assert(file:read("*a"))
file:close()

local startAt = assert(source:find("function addon%.GetCurrencyAccentColor%(") , "missing stable currency accent helper")
local endAt = assert(source:find("\nend\n\nlocal function GetCostColor", startAt), "unterminated currency accent helper")
local helperSource = source:sub(startAt, endAt + #"\nend" - 1)
local chunk = assert(load([[local addon = {}
local function IsSafeText(value) return type(value) == "string" and value ~= "" end
]] .. helperSource .. "\n" .. [[
return addon.GetCurrencyAccentColor
]], "@vendor-currency-color-test"))
local accent = chunk()

local first = accent("currency:101")
assert(first == accent("|Hcurrency:101|h[Currency]|h"), "a currency must retain its color across link forms")
assert(first ~= accent("currency:102"), "neighbouring currencies must receive distinct accents")
assert(first:match("^ff%x%x%x%x%x%x$") ~= nil, "currency accent must be a valid opaque color")
assert(source:find("local currencyColor = addon%.GetCurrencyAccentColor%(link%)") ~= nil,
    "currency accents must feed every vendor cost")
assert(source:find("addon%.ColorVendorListCurrencyCosts%(costText, itemCosts, useMoxieInitials%)") ~= nil,
    "list-mode cost segments must retain their matching currency colors")
assert(source:find("row%._count:SetTextColor%(textR, textG, textB") ~= nil,
    "currency counts must use the same accent as their text and border")

io.write("vendor_currency_color_test: ok\n")
