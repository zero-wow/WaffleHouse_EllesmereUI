-- Currency icon-grid geometry and interaction-contract checks.
-- Run from the addon source directory:
--   lua tests/vendor_currency_grid_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file, err = io.open(SOURCE, "rb")
assert(file, "could not open " .. SOURCE .. ": " .. tostring(err))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()

local startAt = assert(source:find("function addon%.GetCurrencyIconGridLayout%("), "missing currency-grid layout helper")
local endAt = assert(source:find("\nend\n\nlocal function SetRowState", startAt), "unterminated currency-grid layout helper")
local functionSource = source:sub(startAt, endAt + #"\nend" - 1)
local chunk, loadErr = load([[local addon = { CurrencyGrid = { size = 38, gap = 4, gutter = 6 } }
]] .. functionSource .. [[

return addon.GetCurrencyIconGridLayout
]], "@extracted-currency-grid-layout")
assert(chunk, loadErr)
local GetCurrencyIconGridLayout = chunk()

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local columns, rows, height = GetCurrencyIconGridLayout(183, 9)
equal(columns, 4, "minimum Vendor Bags width must retain a four-tile grid")
equal(rows, 3, "nine currencies must wrap into three grid rows")
equal(height, 134, "grid height must include outer and inter-row gutters")

columns, rows, height = GetCurrencyIconGridLayout(900, 22)
equal(columns, 21, "wide currency legend must use available horizontal space")
equal(rows, 2, "the next currency after a full row must wrap")
equal(height, 92, "two grid rows must reserve their visible gutter")

columns, rows, height = GetCurrencyIconGridLayout(1, 2)
equal(columns, 1, "narrow layouts must never calculate zero columns")
equal(rows, 2, "narrow layouts must stack tiles safely")
equal(height, 92, "stacked tiles need the same bounded vertical geometry")

assert(source:find('row._label:Hide()', startAt, true), "Icon Grid must hide the text-row label")
assert(source:find('row._count:SetText(entry.owned ~= nil and tostring(entry.owned) or "?")', startAt, true),
    "Icon Grid must overlay the raw owned count on the currency tile")
local textBranch = assert(source:find('if IsTextMode() then', startAt, true), "missing Text Rows layout branch")
local textBranchEnd = assert(source:find('\n        else\n            local gridIndex', textBranch), "Text Rows branch must end before Icon Grid layout")
local textRows = source:sub(textBranch, textBranchEnd - 1)
assert(textRows:find('row._iconSlot:Show()', 1, true), "Text Rows must retain the leading currency icon")
assert(textRows:find('row._iconSlot:SetSize(addon.CurrencyGrid.size - 4, addon.CurrencyGrid.size - 4)', 1, true),
    "Text Rows icon must match the 34px vendor-item icon size")
assert(source:find('row._icon:SetAllPoints(row._iconSlot)', startAt, true),
    "currency artwork must fill the same physical 34px icon box as vendor items")
assert(textRows:find('row._iconSlot:SetPoint("LEFT", row, "LEFT", addon.CurrencyGrid.gutter, 0)', 1, true),
    "Text Rows icon must remain at the front of the currency row")
assert(source:find('row._costLink = entry.link', startAt, true), "currency tiles must retain their links for details")
assert(source:find('IsAltKeyDown and IsAltKeyDown()', startAt, true), "currency details must be Alt-gated")
assert(source:find('GameTooltip.SetCurrencyByID', startAt, true), "Alt currency detail must prefer the native currency tooltip")
assert(source:find('GameTooltip.SetHyperlink', startAt, true), "Alt currency detail needs a hyperlink fallback")

io.write("Currency icon-grid regressions passed\n")
