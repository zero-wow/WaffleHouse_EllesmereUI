local _, addon = ...

local generation = 0
local RETRY_SECONDS = 30
local DEFAULT_MINUTES = 30

local function IsPlain(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IntervalSeconds(settings)
    local minutes = tonumber(settings.randomTransmogInterval) or DEFAULT_MINUTES
    if minutes ~= 5 and minutes ~= 15 and minutes ~= 30
        and minutes ~= 60 and minutes ~= 120 and minutes ~= 240 then
        minutes = DEFAULT_MINUTES
    end
    return minutes * 60
end

local function CanSwitch()
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return false end
    if UnitOnTaxi("player") or UnitInVehicle("player") or GetUnitSpeed("player") > 0 then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if TransmogFrame and TransmogFrame:IsShown() then return false end
    local transmog = C_Transmog
    if transmog and type(transmog.IsAtTransmogNPC) == "function"
        and transmog.IsAtTransmogNPC() then return false end
    local outfits = C_TransmogOutfitInfo
    if not (outfits and type(outfits.GetOutfitsInfo) == "function"
        and type(outfits.GetActiveOutfitID) == "function"
        and type(outfits.IsLockedOutfit) == "function"
        and type(outfits.ChangeDisplayedOutfit) == "function"
        and Enum and Enum.TransmogSituationTrigger and Enum.TransmogSituationTrigger.Manual) then
        return false
    end
    if type(outfits.IsTransmogEnabled) == "function" and not outfits.IsTransmogEnabled() then return false end
    if type(outfits.HasPendingOutfitTransmogs) == "function"
        and outfits.HasPendingOutfitTransmogs() then return false end
    if type(outfits.InTransmogEvent) == "function" and outfits.InTransmogEvent() then return false end
    return true
end

local function SwitchToRandomOutfit()
    local outfits = C_TransmogOutfitInfo
    local activeID = outfits.GetActiveOutfitID()
    if not IsPlain(activeID) then return end
    if type(activeID) == "number" and activeID > 0 then
        local activeLocked = outfits.IsLockedOutfit(activeID)
        if not IsPlain(activeLocked) or activeLocked ~= false then return end
    end

    local entries = outfits.GetOutfitsInfo()
    if not IsPlain(entries) or type(entries) ~= "table" then return end
    local candidates = {}
    for _, entry in pairs(entries) do
        if IsPlain(entry) and type(entry) == "table" then
            local id = entry.outfitID
            local name = entry.name
            local disabled = entry.isDisabled
            local eventOutfit = entry.isEventOutfit
            if IsPlain(id) and IsPlain(name) and IsPlain(disabled) and IsPlain(eventOutfit)
                and type(id) == "number" and id > 0 and id ~= activeID
                and type(name) == "string" and name ~= ""
                and disabled == false and eventOutfit == false then
                local locked = outfits.IsLockedOutfit(id)
                if IsPlain(locked) and locked == false then
                    candidates[#candidates + 1] = id
                end
            end
        end
    end
    if #candidates < 1 then return end
    local chosenID = candidates[math.random(#candidates)]
    -- A manual trigger avoids changing situation rules; false prevents the
    -- game's same-outfit toggle from clearing an outfit. No save/commit call.
    outfits.ChangeDisplayedOutfit(chosenID, Enum.TransmogSituationTrigger.Manual, false, false)
end

local Schedule
Schedule = function(delay)
    generation = generation + 1
    local current = generation
    C_Timer.After(delay, function()
        if generation ~= current then return end
        local settings = addon.GetSettings and addon.GetSettings()
        if not settings or settings.randomTransmogEnabled ~= true then return end
        local ok, safe = pcall(CanSwitch)
        if not ok or not safe then
            Schedule(RETRY_SECONDS)
            return
        end
        -- Schedule before applying: the displayed-outfit event can restart the
        -- interval synchronously and invalidate this callback's schedule.
        Schedule(IntervalSeconds(settings))
        pcall(SwitchToRandomOutfit)
    end)
end

function addon.RefreshRandomTransmog()
    generation = generation + 1
    local settings = addon.GetSettings and addon.GetSettings()
    if settings and settings.randomTransmogEnabled == true and C_Timer and C_Timer.After then
        Schedule(IntervalSeconds(settings))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
events:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED"
        or event == "TRANSMOG_OUTFITS_CHANGED" then
        addon.RefreshRandomTransmog()
    end
end)
