local addon = {}
local hooks = {}
local function Frame()
    local frame = { shown = true, scripts = {} }
    setmetatable(frame, { __index = function() return function() end end })
    function frame:CreateFontString() return Frame() end
    function frame:CreateTexture() return Frame() end
    function frame:GetHighlightTexture() return Frame() end
    function frame:GetFrameLevel() return 1 end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetShown(value) self.shown = value end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
    return frame
end
CreateFrame = function() return Frame() end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
EllesmereUI = { EXPRESSWAY = STANDARD_TEXT_FONT, SelectModule = function() end,
    _RegisterSearchEntry = function() end, _tabBar = Frame() }
hooksecurefunc = function(_, name, callback) hooks[name] = callback end

assert(loadfile(arg[1] or "WaffleHouse_TabSearch.lua"))("WaffleHouse_EllesmereUI", addon)
local search = addon.TabSearch
assert(search.Find("auto repair")[1].page == "Automation", "search should find automation features")
assert(search.Find("renown")[1].page == "Vendor", "search should find vendor features")
assert(search.Find("transmog")[1].page == "Adventure", "search should find adventure features")
assert(search.Find("guild bank")[1].page == "Bags", "search should find bag features")
assert(search.Find("item queue")[1].page == "Item Queue", "all six tabs should be searchable")
assert(search.Find("nameplate")[1].page == "General", "search should find general features")
assert(#search.Find("") == 0, "empty search should not show a result popup")

local navigated
search.Navigate(search.Find("renown")[1], {
    NavigateToElementSettings = function(_, module, page, section, _, label)
        navigated = { module, page, section, label }
    end,
})
assert(navigated[1] == "WaffleHouse_EllesmereUI" and navigated[2] == "Vendor"
    and navigated[3] == "CURRENCY LEGEND" and navigated[4] == "Hide Renown-Locked Items",
    "search results should deep-link to the matching setting")

addon.InstallTabSearch()
assert(hooks.SelectModule, "module selection should install the search field")
assert(hooks._RegisterSearchEntry, "newly built Waffle House options should join the search index")
hooks._RegisterSearchEntry("Future Setting", nil, "", "WaffleHouse_EllesmereUI", "General", "SKINNING", nil, nil, false)
assert(search.Find("future setting")[1].page == "General", "new settings should become searchable")
hooks.SelectModule(nil, "WaffleHouse_EllesmereUI")
assert(EllesmereUI._tabBar._waffleSearchFrame and EllesmereUI._tabBar._waffleSearchFrame:IsShown(),
    "Waffle House tab bar should show its search field")
hooks.SelectModule(nil, "EllesmereUIBags")
assert(not EllesmereUI._tabBar._waffleSearchFrame:IsShown(),
    "search field should not leak into another module")

print("waffle_tab_search_test: ok")
