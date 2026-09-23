local sourcePath = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = assert(file:read("*a"))
file:close()
source = source:gsub("\r\n", "\n")

local hookStart = assert(source:find('hooksecurefunc(frame.ScrollChild, "SetHeight", function()', 1, true))
local hookEnd = assert(source:find('    if frame.SearchBox', hookStart, true))
local hook = source:sub(hookStart, hookEnd - 1)

assert(hook:find("addon.Refresh()", 1, true),
    "the final host ScrollChild height write must restore list layout synchronously")
assert(not hook:find("QueueRefresh()", 1, true),
    "the final host render hook must not defer list recovery to a later frame")
assert(not source:find("_waffleListIgnoreHostRenderUntilBagSettles", 1, true),
    "bag updates must not suppress post-render list recovery after a purchase")
assert(source:find('if event == "BAG_UPDATE" then\n        itemQueueCache.BagChanged(addonName)\n        return', 1, true),
    "BAG_UPDATE must remain an Item Queue cache invalidation only")
assert(source:find('if event == "BAG_UPDATE_DELAYED" then\n            ScheduleItemQueueRefresh("bags")', 1, true),
    "BAG_UPDATE_DELAYED must continue scheduling the deferred Item Queue scan")
assert(source:find('if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "PLAYER_MONEY"', 1, true),
    "vendor refreshes must be limited to merchant-relevant events")
assert(not source:find("        QueueRefresh()\n    end\nend)", source:find('if event == "MERCHANT_SHOW"', 1, true), true),
    "event handler must not retain an unconditional vendor refresh")

io.write("vendor_bag_sort_refresh_test: ok\n")
