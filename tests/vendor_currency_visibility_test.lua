local sourcePath = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = assert(file:read("*a"))
file:close()

assert(source:find("WaffleHouseDB.currencyLegendVisible == nil", 1, true),
    "currency list visibility must default to enabled for existing profiles")
assert(source:find("panel.title:SetPoint(\"TOPLEFT\", panel, \"TOPLEFT\", panel._waffleTitleLeft, -6)", 1, true),
    "heading must move right to make room for its checkbox")
assert(source:find("panel.currencyCollapse:SetPoint(\"TOPLEFT\", panel, \"TOPLEFT\", 8, -5)", 1, true),
    "collapse icon must sit directly left of the currency heading")
assert(source:find('control.label:SetText(enabled and "-" or ">")', 1, true),
    "collapse control must show minus while open and chevron while collapsed")
assert(source:find("settings.currencyLegendVisible = settings.currencyLegendVisible == false", 1, true),
    "checkbox must persistently toggle the currency list")
assert(source:find("local showCurrencyRows = legend._waffleHasCurrencies and GetSettings().currencyLegendVisible ~= false", 1, true),
    "hidden state must remove currency rows from layout")
assert(source:find("for _, row in ipairs(legend.rows) do row:Hide() end", 1, true),
    "hidden state must hide existing pooled currency rows")

io.write("vendor_currency_visibility_test: ok\n")
