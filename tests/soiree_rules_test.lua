-- Run with: lua tests/soiree_rules_test.lua WaffleHouse_SoireeRules.lua
local SOURCE = arg[1] or "WaffleHouse_SoireeRules.lua"

local localizedNames = {
    [2711] = "Magisters",
    [2712] = "Blood Knights",
    [2713] = "Farstriders",
    [2714] = "Shades of the Row",
}

C_Reputation = {
    GetFactionDataByID = function(id)
        return localizedNames[id] and { name = localizedNames[id] } or nil
    end,
}

local addon = {}
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
local R = assert(addon.SoireeRules)

local function option(id, factionID, extra)
    return {
        id = id,
        header = "Guest " .. id,
        subHeader = localizedNames[factionID],
        description = "Court invitation",
        buttons = { { id = id + 1000 } },
        rewardInfo = {
            itemRewards = extra and { { itemId = R.favorItemID, quantity = extra } } or {},
            repRewards = { { factionId = factionID, quantity = 50 } },
        },
    }
end

local function invitation(options)
    return { options = options }
end

local standard = invitation({
    option(101, 2711),
    option(102, 2712),
    option(103, 2713, 1),
    option(104, 2714),
})

assert(R.IsFocus("favor") and R.IsFocus(2711) and not R.IsFocus("Magisters"))
assert(R.favorItemID == 238987)

-- Extra Favor is identified from item reward data, independent of guest order or names.
local favor = assert(R.Evaluate(standard, "favor"))
assert(favor.recommendedID == 103 and favor.byID[103].favor == 1)
assert(favor.entries[3].factionID == 2713)

local rotated = invitation({ standard.options[4], standard.options[2], standard.options[1], standard.options[3] })
assert(R.Evaluate(rotated, "favor").recommendedID == 103,
    "the recommendation must survive a weekly rotation/reorder")

-- A faction focus picks that faction's route even if another option gives Favor.
rotated.options[1].rewardInfo.repRewards = { { factionId = 2711, quantity = 999 } }
for factionID, optionID in pairs({ [2711] = 101, [2712] = 102, [2713] = 103, [2714] = 104 }) do
    local model = assert(R.Evaluate(rotated, factionID))
    assert(model.recommendedID == optionID and model.byID[optionID].factionID == factionID)
end

-- Native reputation names are localized; the supplied subheader remains the stable visual mapping.
localizedNames[2711] = "Magisteri"
localizedNames[2712] = "Cavalieri del Sangue"
localizedNames[2713] = "Raminghi"
localizedNames[2714] = "Ombre del Viale"
local localized = invitation({ option(201, 2711), option(202, 2712), option(203, 2713), option(204, 2714) })
assert(R.Evaluate(localized, 2714).recommendedID == 204)
assert(R.Evaluate(localized, 2711).byID[201].factionID == 2711)

-- Restore the names used by text-only fallback assertions below.
localizedNames[2711] = "Magisters"
localizedNames[2712] = "Blood Knights"
localizedNames[2713] = "Farstriders"
localizedNames[2714] = "Shades of the Row"

local textFallback = invitation({
    option(301, 2711), option(302, 2712), option(303, 2713), option(304, 2714),
})
textFallback.options[1].rewardInfo.repRewards = {}
textFallback.options[1].description = "|cff00ff00+75 Magisters|r\n|cffff0000-25 Farstriders|r"
local textModel = assert(R.Evaluate(textFallback, 2711))
assert(textModel.byID[301].rep[2711] == 75 and textModel.byID[301].rep[2713] == -25,
    "signed, color-marked reputation text must remain available to the hover explanation")

-- Structural safety: Player Choice content must contain every court faction once and unique option IDs.
local unknown = invitation({ option(401, 2711), option(402, 2712), option(403, 2713), option(404, 2714) })
unknown.options[4].subHeader = "Unrelated faction"
assert(R.Evaluate(unknown, "favor") == nil)

local duplicateFaction = invitation({ option(411, 2711), option(412, 2712), option(413, 2713), option(414, 2713) })
assert(R.Evaluate(duplicateFaction, "favor") == nil)

local duplicateID = invitation({ option(421, 2711), option(421, 2712), option(423, 2713), option(424, 2714) })
assert(R.Evaluate(duplicateID, "favor") == nil)

local wrongCount = invitation({ option(431, 2711), option(432, 2712), option(433, 2713) })
assert(R.Evaluate(wrongCount, "favor") == nil)

-- Disabled or hidden responses may be displayed for context but never recommended.
local disabled = invitation({ option(501, 2711), option(502, 2712), option(503, 2713, 2), option(504, 2714) })
disabled.options[3].disabledOption = true
assert(R.Evaluate(disabled, "favor").recommendedID == nil)
assert(R.Evaluate(disabled, 2713).recommendedID == nil)

local hidden = invitation({ option(511, 2711), option(512, 2712, 2), option(513, 2713), option(514, 2714) })
hidden.options[2].buttons[1].hideButtonShowText = true
assert(R.Evaluate(hidden, "favor").recommendedID == nil)
assert(R.Evaluate(hidden, 2712).recommendedID == nil)

-- Ambiguous/missing Favor data must leave the selection to the player.
local tie = invitation({ option(601, 2711, 1), option(602, 2712, 1), option(603, 2713), option(604, 2714) })
assert(R.Evaluate(tie, "favor").recommendedID == nil)
local noFavor = invitation({ option(611, 2711), option(612, 2712), option(613, 2713), option(614, 2714) })
assert(R.Evaluate(noFavor, "favor").recommendedID == nil)

-- Bad option payloads should be rejected, not throw while an unrelated PlayerChoice is opening.
local malformed = invitation({ option(701, 2711), option(702, 2712), option(703, 2713), "not an option" })
local ok, result = pcall(R.Evaluate, malformed, "favor")
assert(ok and result == nil, "malformed PlayerChoice option must fail closed")

print("soiree_rules_test: ok")
