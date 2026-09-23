-- Easy Access list-view resize/re-render regression checks.
-- Run from the addon source directory:
--   lua tests/vendor_list_resize_reflow_test.lua

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file, err = io.open(SOURCE, "rb")
assert(file, "could not open " .. SOURCE .. ": " .. tostring(err))
local source = file:read("*a")
file:close()

local function assertContains(pattern, message)
    assert(source:find(pattern) ~= nil, message)
end

assertContains('hooksecurefunc%(frame%.ScrollChild, "SetHeight", function%(%)',
    "list view must observe the host renderer's final ScrollChild update")
assertContains('if frame%._liveWindowWidth or frame%._liveWindowHeight then',
    "live corner-resize redraws must defer Waffle House list layout")
assertContains('frame%._waffleListApplying = listView or nil',
    "the whole list refresh must guard its own callbacks against recursive reflows")
assertContains('frame%._waffleListRefreshAfterResize = nil',
    "final post-resize list layout must clear its deferred state")

local hookStart = assert(source:find('hooksecurefunc(frame.ScrollChild, "SetHeight", function()', 1, true),
    "missing final host render hook")
local hookEnd = assert(source:find('    if frame.SearchBox', hookStart, true),
    "could not bound final host render hook")
local hook = source:sub(hookStart, hookEnd - 1)
assert(hook:find('addon.Refresh()', 1, true),
    "final host pass must restore list layout before its native scroll clamp")
assert(not hook:find('QueueRefresh()', 1, true),
    "final host pass must not defer list layout to a later frame")

io.write("Vendor list resize-reflow regression checks passed\n")
