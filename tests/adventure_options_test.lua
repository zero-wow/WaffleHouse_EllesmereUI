-- Buff Check must remain an Adventure option, never another top-level page.
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local main = read(arg[1] or "WaffleHouse_EllesmereUI.lua")
local adventure = read(arg[2] or "WaffleHouse_Adventure.lua")

local pages = assert(main:match('pages%s*=%s*{(.-)}'), "main options must declare their pages")
assert(pages:find('"Adventure"', 1, true), "Adventure must remain a main options page")
assert(not main:find('"Item Queue", "Buff Check"', 1, true), "Buff Check must not be a top-level page")
assert(adventure:find('if addon.BuildBuffCheckPage then y = -addon.BuildBuffCheckPage(parent, y) end', 1, true),
    "Adventure must build the Buff Check section")
assert(not adventure:find('OptionsSectionIntro', 1, true), "Adventure must not display empty activity headings")
assert(adventure:find('if addon.BuildSoireeOptions then y = addon.BuildSoireeOptions(parent, y) end', 1, true),
    "Soiree must build its own populated section when available")
assert(adventure:find('local function SkinValeeraMuterButton()', 1, true), "Valeera muter needs a remote EUI skin")
assert(adventure:find('button._waffleValeeraMuteText:SetText(muted and "Mute: ON" or "Mute: OFF")', 1, true),
    "muter button needs an owned text-only label")
assert(adventure:find('muted and 0.05 or 0.66', 1, true), "muted status must use teal rather than red")

io.write("Adventure options tests passed\n")
