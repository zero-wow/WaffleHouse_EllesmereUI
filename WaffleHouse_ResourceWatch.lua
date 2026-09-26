local _, addon = ...

local SAMPLE_SECONDS = 5
local REQUIRED_SAMPLES = 4
local TOP_ADDONS = 8

local ticker
local streaks = {}
local warned = {}
local pending

local function GetSettings()
    return addon.GetSettings and addon.GetSettings()
end

local function IsProfilerAvailable()
    local profiler = C_AddOnProfiler
    local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
    return profiler and profiler.IsEnabled and profiler.GetTopKAddOnsForMetric
        and metric and profiler.IsEnabled(), metric
end

function addon.ResetResourceWatchSamples()
    streaks = {}
    pending = nil
end

local function ShowWarning(candidate)
    if not candidate or warned[candidate.name] then return end
    local settings = GetSettings()
    if not settings or settings.resourceWatchEnabled ~= true or InCombatLockdown() then return end

    local message = string.format("%s  ·  %.1f ms/frame for %d checks",
        candidate.name, candidate.value, REQUIRED_SAMPLES)
    if addon.ShowWarningToast and addon.ShowWarningToast("resource:" .. candidate.name,
        "RESOURCE WATCH", message, "Warning only · no addon disabled; shared libraries can affect attribution") then
        warned[candidate.name] = true
        pending = nil
    end
end

local function Sample()
    local settings = GetSettings()
    if not settings or settings.resourceWatchEnabled ~= true then return end
    local available, metric = IsProfilerAvailable()
    if not available then return end

    local ok, results = pcall(C_AddOnProfiler.GetTopKAddOnsForMetric, metric, TOP_ADDONS)
    if not ok or type(results) ~= "table" then return end

    local threshold = tonumber(settings.resourceWatchThreshold) or 8
    local above = {}
    local candidate
    for _, result in ipairs(results) do
        local name, value = result.addOnName, result.metricValue
        if type(name) == "string" and name ~= ""
            and type(value) == "number" and value >= threshold then
            above[name] = true
            streaks[name] = (streaks[name] or 0) + 1
            if streaks[name] >= REQUIRED_SAMPLES and not warned[name]
                and (not candidate or value > candidate.value) then
                candidate = { name = name, value = value }
            end
        end
    end
    for name in pairs(streaks) do
        if not above[name] then streaks[name] = nil end
    end

    if candidate and (not pending or candidate.value > pending.value) then
        pending = candidate
    end
    if not InCombatLockdown() then ShowWarning(pending) end
end

function addon.RefreshResourceWatch()
    local settings = GetSettings()
    local available = IsProfilerAvailable()
    if settings and settings.resourceWatchEnabled == true and available then
        if not ticker then ticker = C_Timer.NewTicker(SAMPLE_SECONDS, Sample) end
    else
        if ticker then ticker:Cancel() end
        ticker = nil
        addon.ResetResourceWatchSamples()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        addon.RefreshResourceWatch()
    elseif pending then
        ShowWarning(pending)
    end
end)
