-- Vendor list cost-label abbreviation regressions.
-- Run from the addon source directory:
--   lua tests/vendor_list_cost_text_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file, err = io.open(SOURCE, "rb")
assert(file, "could not open " .. SOURCE .. ": " .. tostring(err))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()

local startAt = assert(source:find("local function CompactVendorListCurrencyName%("), "missing cost-name compactor")
local endAt = assert(source:find("\nend\n\nlocal function", startAt), "unterminated cost-name compactor")
local functionSource = source:sub(startAt, endAt + #"\nend" - 1)
local chunk, loadErr = load([[local function IsSafeText(value) return type(value) == "string" and value ~= "" end
]] .. functionSource .. [[

return CompactVendorListCurrencyName
]], "@extracted-vendor-list-cost-text")
assert(chunk, loadErr)
local CompactVendorListCurrencyName = chunk()

local function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. expected .. ", got " .. tostring(actual))
end

assertEqual(CompactVendorListCurrencyName("Artisan Blacksmith's Moxie", false), "Blacksmith's Moxie",
    "normal list width should preserve the profession name")
assertEqual(CompactVendorListCurrencyName("Artisan Scribe's Moxie", false), "Scribe's Moxie",
    "all profession Moxie names should lose only the redundant Artisan prefix")
assertEqual(CompactVendorListCurrencyName("Artisan Blacksmith's Moxie", true), "AB Moxie",
    "narrow list width should use clear Artisan-plus-profession initials")
assertEqual(CompactVendorListCurrencyName("Voidlight Marl", true), "Voidlight Marl",
    "unrelated currency names must stay unchanged")
assert(source:find("GetVendorListCostText%(button, itemCosts, true%)") ~= nil,
    "initials must be used as a fallback before visual truncation")

io.write("Vendor list cost-text regressions passed\n")
