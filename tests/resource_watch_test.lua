local source = arg[1] or "WaffleHouse_ResourceWatch.lua"
local settings = { resourceWatchEnabled = false, resourceWatchThreshold = "8" }
local addon = { GetSettings = function() return settings end }
local combat = false
local readings = {}
local popups = {}
local ticker
local frame

StaticPopupDialogs = {}
CLOSE = "Close"
StaticPopup_Show = function(key, message)
    popups[#popups + 1] = { key = key, message = message }
    return {}
end
InCombatLockdown = function() return combat end
Enum = { AddOnProfilerMetric = { RecentAverageTime = 1 } }
C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetTopKAddOnsForMetric = function(metric, count)
        assert(metric == 1 and count == 8)
        return readings
    end,
}
C_Timer = { NewTicker = function(interval, callback)
    assert(interval == 5)
    ticker = { callback = callback, cancelled = false,
        Cancel = function(self) self.cancelled = true end }
    return ticker
end }
CreateFrame = function()
    frame = {
        RegisterEvent = function() end,
        SetScript = function(self, _, callback) self.OnEvent = callback end,
    }
    return frame
end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
assert(StaticPopupDialogs.WAFFLEHOUSE_RESOURCE_WATCH,
    "warning must have a dismissible popup")
frame:OnEvent("PLAYER_LOGIN")
assert(not ticker, "disabled watch must have no polling ticker")

settings.resourceWatchEnabled = true
addon.RefreshResourceWatch()
assert(ticker and not ticker.cancelled, "enabling must start one low-frequency ticker")
local firstTicker = ticker
addon.RefreshResourceWatch()
assert(ticker == firstTicker, "refresh must not create duplicate tickers")

readings = { { addOnName = "HeavyAddon", metricValue = 9 } }
for _ = 1, 3 do ticker.callback() end
assert(#popups == 0, "three high readings are not sustained enough")
ticker.callback()
assert(#popups == 1 and popups[1].message:find("HeavyAddon", 1, true),
    "four high readings must name the responsible addon")
for _ = 1, 5 do ticker.callback() end
assert(#popups == 1, "warn at most once per addon per session")

readings = { { addOnName = "AnotherAddon", metricValue = 9 } }
ticker.callback()
readings[1].metricValue = 3
ticker.callback()
readings[1].metricValue = 9
for _ = 1, 3 do ticker.callback() end
assert(#popups == 1, "a below-threshold reading must reset the streak")

combat = true
ticker.callback()
assert(#popups == 1, "no popup may appear in combat")
combat = false
frame:OnEvent("PLAYER_REGEN_ENABLED")
assert(#popups == 2 and popups[2].message:find("AnotherAddon", 1, true),
    "sustained combat warning must appear after combat")

settings.resourceWatchThreshold = "12"
addon.ResetResourceWatchSamples()
readings = { { addOnName = "ThresholdAddon", metricValue = 10 } }
for _ = 1, 4 do ticker.callback() end
assert(#popups == 2, "threshold setting must be honored")

readings = { { addOnName = "WaffleHouse_EllesmereUI", metricValue = 13 } }
for _ = 1, 4 do ticker.callback() end
assert(#popups == 3, "the monitor must be willing to report its own addon")

settings.resourceWatchEnabled = false
addon.RefreshResourceWatch()
assert(firstTicker.cancelled, "disabling must cancel the ticker")

io.write("resource watch tests passed\n")
