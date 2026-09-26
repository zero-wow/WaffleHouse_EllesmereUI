local source = arg[1] or "WaffleHouse_RandomSummoner.lua"
local db = {}
local addon = { GetSettings = function() return db end }
local state = { combat = false, mount = nil, pet = nil, toy = nil }

local newFrame
newFrame = function(name)
    local frame = { name = name, shown = true, scripts = {}, attributes = {} }
    local quiet = function() end
    setmetatable(frame, { __index = function(_, key) return quiet end })
    function frame:SetScript(event, handler) self.scripts[event] = handler end
    function frame:SetShown(value) self.shown = value end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function frame:CreateFontString() return newFrame() end
    function frame:CreateTexture() return newFrame() end
    function frame:GetHighlightTexture() return newFrame() end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetCenter() return 500, 400 end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    return frame
end
UIParent = newFrame("UIParent")
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
InCombatLockdown = function() return state.combat end
local namedFrames = {}
local eventFrame
CreateFrame = function(_, name)
    local frame = newFrame(name)
    if name then namedFrames[name] = frame end
    if not name and not eventFrame then eventFrame = frame end
    return frame
end
Enum = { BattlePetSources = { PetStore = 9 } }
BATTLE_PET_SOURCE_10 = "In-Game Shop"
DARKMOON_FAIRE = "Darkmoon Faire"

C_MountJournal = {
    GetMountIDs = function() return { 1, 2, 3, 4, 5 } end,
    GetMountInfoByID = function(id)
        local info = {
            [1] = { "Store Steed", true, 9, false, true },
            [2] = { "Yearly Steed", true, 7, false, true },
            [3] = { "Faire Pony", true, 6, false, true },
            [4] = { "Other Steed", true, 2, true, true },
            [5] = { "Unowned Steed", true, 9, false, false },
        }
        local row = info[id]
        return row[1], id + 100, id + 200, false, row[2], row[3], row[4], false, nil, false, row[5]
    end,
    GetMountInfoExtraByID = function(id)
        local sources = { [1] = "In-Game Shop", [2] = "12-month subscription reward",
            [3] = "Darkmoon Faire", [4] = "Vendor" }
        return nil, nil, sources[id]
    end,
    SummonByID = function(id) state.mount = id end,
}

local petInfo = {
    ["p1"] = { speciesID = 10, name = "Store Kitten", icon = 1, isFavorite = false,
        sourceText = "In-Game Shop" },
    ["p2"] = { speciesID = 11, name = "Faire Bunny", icon = 2, isFavorite = false,
        sourceText = "Darkmoon Faire" },
    ["p3"] = { speciesID = 12, name = "Wild Cub", icon = 3, isFavorite = true,
        sourceText = "Wild Pet" },
    ["p4"] = { speciesID = 12, name = "Wild Cub", icon = 3, isFavorite = false,
        sourceText = "Wild Pet" },
}
C_PetJournal = {
    GetOwnedPetIDs = function() return { "p1", "p2", "p3", "p4" } end,
    GetPetInfoTableByPetID = function(guid) return petInfo[guid] end,
    GetPetSummonInfo = function(guid) return guid ~= "p3" end,
    SummonPetByGUID = function(guid) state.pet = guid end,
}

C_ToyBox = {
    GetNumToys = function() return 3 end,
    GetToyFromIndex = function(index) return index + 1000 end,
    GetToyInfo = function(id) return id, "Toy " .. id, id, id == 1002 end,
    IsToyUsable = function(id) return id ~= 1003 end,
}
PlayerHasToy = function(id) return id ~= 1001 end
UseToy = function(id) state.toy = id end
math.random = function(count) assert(count >= 1); return 1 end

assert(loadfile(source))("WaffleHouse_EllesmereUI", addon)
local S = addon.RandomSummoner
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(S and S.GetSettings().mount.packs.all and S.GetSettings().showLauncher)
assert(S.GetSettings().pet.packs.all and S.GetSettings().toy.packs.all)

local mounts = S.Collect("mount")
assert(#mounts == 4, "uncollected mounts must not enter a pool")
local counts = S.Counts("mount", mounts)
assert(counts.store == 1 and counts.sub12 == 1 and counts.longsub == 1 and counts.darkmoon == 1)
assert(counts.selected == 4 and counts.usable == 4)

local m = S.GetSettings().mount
m.packs.all = false
m.packs.store = true
assert(S.Pick("mount", mounts).id == 1, "store source type must identify only store mounts")
m.packs.store = false
m.packs.longsub = true
assert(S.Pick("mount", mounts).id == 2, "subscription source text must identify its duration")
m.packs.longsub = false
m.packs.picked = true
m.picks[4] = true
assert(S.Pick("mount", mounts).id == 4, "personal mount picks must work")

local pets = S.Collect("pet")
assert(#pets == 3, "multiple copies of one species must show as one choice")
local p = S.GetSettings().pet
p.packs.all = false
p.packs.favorite = true
local pickedPet = S.Pick("pet", pets)
assert(pickedPet.id == 12 and pickedPet.guid == "p4", "choose a summonable copy of the favorite species")
p.packs.favorite = false
p.packs.store = true
assert(S.Pick("pet", pets).id == 10, "store pets use the localized source label")

local toys = S.Collect("toy")
assert(#toys == 2, "uncollected toys must be excluded")
assert(S.Counts("toy", toys).usable == 1, "unusable toys must not be random choices")
local secureToy = { attributes = {}, SetAttribute = function(self, key, value) self.attributes[key] = value end }
assert(S.PrepareToyButton(secureToy) and secureToy.attributes.type == "toy"
    and secureToy.attributes.toy == 1002, "toy use must be armed as a secure toy action")
assert(state.toy == nil, "addon Lua must not call the protected UseToy function")
assert(S.Summon("mount") and state.mount == 4)
assert(S.Summon("pet") and state.pet == "p1")

state.combat = true
assert(S.PrepareToyButton(secureToy) == false, "secure toy attributes must not change in combat")
state.combat = false
assert(S.DetectSourcePacks("Promotion") .sub12 == nil,
    "generic promotions must never be mislabeled as subscription rewards")

S.Toggle()
local popup = namedFrames.WaffleHouseRandomSummoner
assert(popup and popup:IsShown() and popup:GetWidth() == 522 and popup:GetHeight() == 562,
    "popup must open through its public action")
assert(S.toyKeyButton and S.toyKeyButton.name == "WaffleHouseRandomToyKeyButton",
    "login should create a named secure toy key button")
assert(loadfile("WaffleHouse_Slash.lua"))("WaffleHouse_EllesmereUI", addon)
SlashCmdList.WAFFLEHOUSEOPTIONS("random summoner")
assert(not popup:IsShown(), "/wh random summoner must toggle the popup")

print("random_summoner_test: ok")
