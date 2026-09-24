-- General-page layout regressions. The compact integrations page must use
-- standard EllesmereUI section ownership and make meaningful use of its width.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(SOURCE, "rb"))
local source = file:read("*a")
file:close()

assert(source:find('pages = { "General", "Adventure", "Automation", "Bags", "Item Queue", "Vendor" },', 1, true),
    "General must remain first and the remaining Waffle House tabs must be alphabetical")

local generalStart = assert(source:find('if pageName == "General" then', 1, true), "missing General page block")
local generalEnd = assert(source:find('\n            if pageName == "Vendor" then', generalStart, true),
    "General page block must end before Vendor options")
local general = source:sub(generalStart, generalEnd - 1)

assert(general:find('W:SectionHeader(parent, "DATABARS & COMPANIONS"', 1, true),
    "Wonderbar and companion controls need one owning EUI section")
assert(general:find('W:SectionHeader(parent, "SKINNING"', 1, true),
    "Zygor pointer styling needs its own Skinning section")
local resourceHeader = assert(general:find('W:SectionHeader(parent, "RESOURCE WATCH"', 1, true))
local protectorOptions = assert(general:find('addon.BuildNameplateCVarOptions(parent, y)', 1, true),
    "nameplate CVar controls must be included on General")
local skinningHeader = assert(general:find('W:SectionHeader(parent, "SKINNING"', 1, true))
assert(resourceHeader < protectorOptions and protectorOptions < skinningHeader,
    "nameplate CVar controls must sit between Resource Watch and Skinning")
assert(general:find('OptionsSectionIntro', 1, true) == nil,
    "General must not use floating centered context labels above its section headers")

local firstRowStart = assert(general:find('W:DualRow(parent, y,', 1, true), "missing integrations two-column row")
local skinHeader = assert(general:find('W:SectionHeader(parent, "SKINNING"', 1, true), "missing Skinning header")
local firstRow = general:sub(firstRowStart, skinHeader - 1)
assert(firstRow:find('text = "Reorder Wonderbar Entries"', 1, true)
        and firstRow:find('text = "Keep Soul-Trader Summoned"', 1, true),
    "Wonderbar and Soul-Trader controls must share the two-column integrations row")
assert(general:find('text = "Skin Zygor Guide Pointer"', skinHeader, true),
    "the existing Zygor setting must remain available under Skinning")

io.write("general options layout tests passed\n")
