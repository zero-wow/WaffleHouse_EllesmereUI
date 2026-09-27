local _, addon = ...
local unpack = unpack or table.unpack

-- Mounts and pets are read from the full collections. Blizzard only exposes
-- toys by their filtered Toy Box index, so that collection follows its view.
local S = {}
addon.RandomSummoner = S

local CATEGORIES = { "mount", "pet", "toy" }
local LABELS = { mount = "Mounts", pet = "Pets", toy = "Toys" }
local ART = "Interface\\AddOns\\WaffleHouse_EllesmereUI\\Media\\RandomSummoner\\"
local CATEGORY_ART = { mount = ART .. "mount.tga", pet = ART .. "pet.tga", toy = ART .. "toy.tga" }
local TRAVEL_ART = { Ground = ART .. "ground.tga", Sky = ART .. "sky.tga", Aquatic = ART .. "aquatic.tga" }
local TRAVEL_TAGS = { "Ground", "Sky", "Aquatic" }
local GROUPS = {
    mount = { "Any", "Ground", "Sky", "Aquatic", "Auction House", "Vendor", "Repair", "Travel" },
    pet = { "Any", "Cooking", "Blacksmith", "Vendor", "Mailbox", "Bank", "Repair", "Portal", "Transport", "Other Utility", "Companion" },
    toy = { "Any", "Portal", "Morph", "Flag", "Crafting", "Music", "Visual", "Play", "Other" },
}
local PACKS = {
    mount = {
        { key = "all", label = "All Collected" },
        { key = "favorite", label = "Favorites" },
        { key = "store", label = "Store Mounts" },
        { key = "longsub", label = "Long Subscriptions (3/6/12)" },
        { key = "darkmoon", label = "Darkmoon Faire" },
        { key = "picked", label = "My Picks" },
    },
    pet = {
        { key = "all", label = "All Collected" },
        { key = "favorite", label = "Favorites" },
        { key = "store", label = "Store Pets" },
        { key = "darkmoon", label = "Darkmoon Faire" },
        { key = "picked", label = "My Picks" },
    },
    toy = {
        { key = "all", label = "All Collected" },
        { key = "favorite", label = "Favorites" },
        { key = "picked", label = "My Picks" },
    },
}

local function Settings()
    local db = addon.GetSettings and addon.GetSettings() or WaffleHouseDB
    if type(db) ~= "table" then
        WaffleHouseDB = {}
        db = WaffleHouseDB
    end
    if type(db.randomSummoner) ~= "table" then db.randomSummoner = {} end
    local settings = db.randomSummoner
    for _, category in ipairs(CATEGORIES) do
        if type(settings[category]) ~= "table" then settings[category] = {} end
        local pool = settings[category]
        if type(pool.packs) ~= "table" then pool.packs = { all = true } end
        if type(pool.picks) ~= "table" then pool.picks = {} end
        if type(pool.ratings) ~= "table" then pool.ratings = {} end
        if type(pool.groups) ~= "table" then pool.groups = {} end
        if type(pool.travelTags) ~= "table" then pool.travelTags = {} end
        if type(pool.customPools) ~= "table" then pool.customPools = {} end
        if pool.launcherMode ~= "favorites" then pool.launcherMode = "rated" end
    end
    if type(settings.shortcuts) ~= "table" then settings.shortcuts = {} end
    if settings.showLauncher == nil then settings.showLauncher = true end
    return settings
end
S.GetSettings = Settings

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeText(text)
    if type(text) ~= "string" or IsSecret(text) then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("<[^>]+>", ""):lower()
end

local function DetectGroup(category, name, description)
    local text = SafeText(name) .. " " .. SafeText(description)
    if category == "mount" then
        if text:find("auction house", 1, true) or text:find("brutosaur", 1, true) then return "Auction House" end
        if text:find("repair", 1, true) then return "Repair" end
        if text:find("vendor", 1, true) or text:find("merchant", 1, true)
            or text:find("expedition yak", 1, true) or text:find("tundra mammoth", 1, true) then return "Vendor" end
        return "Travel"
    elseif category == "pet" then
        if text:find("cook", 1, true) or text:find("campfire", 1, true) then return "Cooking" end
        if text:find("blacksmith", 1, true) or text:find("anvil", 1, true)
            or text:find("forge", 1, true) then return "Blacksmith" end
        if text:find("vendor", 1, true) or text:find("merchant", 1, true) then return "Vendor" end
        if text:find("mailbox", 1, true) or text:find("mail ", 1, true) then return "Mailbox" end
        if text:find("bank", 1, true) then return "Bank" end
        if text:find("repair", 1, true) then return "Repair" end
        if text:find("portal", 1, true) or text:find("teleport", 1, true) then return "Portal" end
        if text:find("transport", 1, true) or text:find("ride", 1, true) then return "Transport" end
        return "Companion"
    end
    if text:find("portal", 1, true) or text:find("teleport", 1, true)
        or text:find("hearth", 1, true) or text:find("waygate", 1, true) then return "Portal" end
    if text:find("transform", 1, true) or text:find("disguise", 1, true)
        or text:find("costume", 1, true) or text:find("appearance", 1, true)
        or text:find("illusion", 1, true) or text:find("morph", 1, true) then return "Morph" end
    if text:find("flag", 1, true) or text:find("banner", 1, true)
        or text:find("standard", 1, true) then return "Flag" end
    if text:find("cook", 1, true) or text:find("anvil", 1, true)
        or text:find("forge", 1, true) then return "Crafting" end
    if text:find("music", 1, true) or text:find("song", 1, true)
        or text:find("instrument", 1, true) then return "Music" end
    if text:find("firework", 1, true) or text:find("light", 1, true)
        or text:find("weather", 1, true) then return "Visual" end
    if text:find("game", 1, true) or text:find("ball", 1, true) then return "Play" end
    return "Other"
end
S.DetectGroup = DetectGroup

local function DetectTravelTags(name, description)
    local text = SafeText(name) .. " " .. SafeText(description)
    local aquatic = text:find("aquatic", 1, true) or text:find("seahorse", 1, true)
        or text:find("manta", 1, true) or text:find("jellyfish", 1, true)
        or text:find("water strider", 1, true) or text:find("underwater", 1, true)
    local sky = text:find("wing", 1, true) or text:find("dragon", 1, true)
        or text:find("drake", 1, true) or text:find("gryphon", 1, true)
        or text:find("griff", 1, true) or text:find("phoenix", 1, true)
        or text:find("stormrider", 1, true)
    return { Ground = not aquatic, Sky = not not sky, Aquatic = not not aquatic }
end
S.DetectTravelTags = DetectTravelTags

local tooltipCache = {}
local function ItemTooltipText(id)
    if tooltipCache[id] then return tooltipCache[id] end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return "" end
    local data = C_TooltipInfo.GetItemByID(id)
    if IsSecret(data) or type(data) ~= "table" or IsSecret(data.lines)
        or type(data.lines) ~= "table" then return "" end
    local lines = {}
    for i = 1, math.min(#data.lines, 12) do
        local line = data.lines[i]
        if not IsSecret(line) and type(line) == "table" then
            lines[#lines + 1] = SafeText(line.leftText)
        end
    end
    tooltipCache[id] = table.concat(lines, " ")
    return tooltipCache[id]
end

local function DetectSourcePacks(source)
    local text = SafeText(source)
    local packs = {}
    -- Subscription duration is not a structured collection field. Only
    -- explicit English journal source wording is counted, never a guess.
    if text:find("12[%s%-]+month") and text:find("subscription") then packs.sub12 = true end
    if text:find("6[%s%-]+month") and text:find("subscription") then packs.sub6 = true end
    if text:find("3[%s%-]+month") and text:find("subscription") then packs.sub3 = true end
    if packs.sub12 or packs.sub6 or packs.sub3 then packs.longsub = true end
    local fair = SafeText(_G.DARKMOON_FAIRE)
    if (fair ~= "" and text:find(fair, 1, true)) or text:find("darkmoon faire", 1, true) then
        packs.darkmoon = true
    end
    return packs
end
S.DetectSourcePacks = DetectSourcePacks

local function StoreSourceLabel()
    local label = _G.BATTLE_PET_SOURCE_10
    return SafeText(label)
end

local function IsStoreText(text)
    text = SafeText(text)
    local sourceLabel = StoreSourceLabel()
    return (sourceLabel ~= "" and text:find(sourceLabel, 1, true) ~= nil)
        or text:find("in-game shop", 1, true) ~= nil
        or text:find("battle.net shop", 1, true) ~= nil
        or text:find("warcraft shop", 1, true) ~= nil
end

local function Mounts()
    local rows = {}
    if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return rows end
    local ids = C_MountJournal.GetMountIDs() or {}
    local storeSource = Enum and Enum.BattlePetSources and Enum.BattlePetSources.PetStore
    for _, id in ipairs(ids) do
        if type(id) == "number" and not IsSecret(id) then
            local name, spellID, icon, _, usable, sourceType, favorite, _, _, hidden, collected = C_MountJournal.GetMountInfoByID(id)
            if collected and name and not IsSecret(name) then
                local description, source
                if C_MountJournal.GetMountInfoExtraByID then
                    _, description, source = C_MountJournal.GetMountInfoExtraByID(id)
                end
                local packs = DetectSourcePacks(source)
                if storeSource ~= nil and sourceType == storeSource then packs.store = true end
                rows[#rows + 1] = { id = id, spellID = spellID, name = name, icon = icon, usable = usable and not hidden,
                    packs = packs, favorite = favorite == true,
                    group = DetectGroup("mount", name, description),
                    travel = DetectTravelTags(name, description) }
            end
        end
    end
    return rows
end

local function PetInfo(guid)
    if C_PetJournal.GetPetInfoTableByPetID then
        local info = C_PetJournal.GetPetInfoTableByPetID(guid)
        if info then return info end
    end
    if C_PetJournal.GetPetInfoByPetID then
        local speciesID, customName, _, _, _, _, favorite, name, icon, _, _, sourceText = C_PetJournal.GetPetInfoByPetID(guid)
        return { speciesID = speciesID, customName = customName, isFavorite = favorite,
            name = name, icon = icon, sourceText = sourceText }
    end
end

local function Pets()
    local rows, bySpecies = {}, {}
    if not (C_PetJournal and C_PetJournal.GetOwnedPetIDs) then return rows end
    for _, guid in ipairs(C_PetJournal.GetOwnedPetIDs() or {}) do
        if type(guid) == "string" and not IsSecret(guid) then
            local info = PetInfo(guid)
            if info and type(info.speciesID) == "number" and not IsSecret(info.speciesID) then
                local id = info.speciesID
                local row = bySpecies[id]
                if not row then
                    local packs = DetectSourcePacks(info.sourceText)
                    if IsStoreText(info.sourceText) then packs.store = true end
                    local description = info.description
                    if not description and C_PetJournal.GetPetInfoBySpeciesID then
                        description = select(6, C_PetJournal.GetPetInfoBySpeciesID(id))
                    end
                    row = { id = id, guid = guid, name = info.name or info.customName or ("Pet " .. id),
                        icon = info.icon, favorite = info.isFavorite == true, packs = packs, usable = true,
                        group = DetectGroup("pet", info.name or info.customName, description) }
                    if C_PetJournal.GetPetStats then
                        local rarity = select(5, C_PetJournal.GetPetStats(guid))
                        if not IsSecret(rarity) and type(rarity) == "number" then
                            row.quality = math.max(0, rarity - 1)
                        end
                    end
                    bySpecies[id] = row
                    rows[#rows + 1] = row
                else
                    row.favorite = row.favorite or info.isFavorite == true
                end
                if C_PetJournal.GetPetSummonInfo then
                    local summonable = C_PetJournal.GetPetSummonInfo(guid)
                    if summonable then row.guid = guid; row.usable = true
                    elseif row.guid == guid then row.usable = false end
                elseif C_PetJournal.PetIsSummonable then
                    local summonable = C_PetJournal.PetIsSummonable(guid)
                    if summonable then row.guid = guid; row.usable = true
                    elseif row.guid == guid then row.usable = false end
                end
            end
        end
    end
    return rows
end

local function Toys()
    local rows = {}
    if not (C_ToyBox and C_ToyBox.GetToyFromIndex and C_ToyBox.GetToyInfo) then return rows end
    local count = C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys()
        or C_ToyBox.GetNumToys and C_ToyBox.GetNumToys() or 0
    for i = 1, count do
        local id = C_ToyBox.GetToyFromIndex(i)
        if type(id) == "number" and not IsSecret(id) and PlayerHasToy and PlayerHasToy(id) then
            local _, name, icon, favorite, _, quality = C_ToyBox.GetToyInfo(id)
            if name and not IsSecret(name) then
                rows[#rows + 1] = { id = id, name = name, icon = icon, favorite = favorite == true,
                    usable = not C_ToyBox.IsToyUsable or C_ToyBox.IsToyUsable(id), packs = {},
                    group = DetectGroup("toy", name, ItemTooltipText(id)),
                    quality = not IsSecret(quality) and type(quality) == "number" and quality or nil }
            end
        end
    end
    return rows
end

function S.Collect(category)
    local rows = category == "mount" and Mounts() or category == "pet" and Pets() or category == "toy" and Toys() or {}
    table.sort(rows, function(a, b)
        local an, bn = SafeText(a.name), SafeText(b.name)
        return an == bn and a.id < b.id or an < bn
    end)
    return rows
end

function S.IsSelected(category, row, settings)
    local pool = settings or Settings()[category]
    if not pool then return false end
    local packs = pool.packs or {}
    if packs.all or (packs.favorite and row.favorite) or (packs.picked and pool.picks[row.id]) then return true end
    for key in pairs(row.packs or {}) do if packs[key] then return true end end
    for _, custom in ipairs(pool.customPools or {}) do
        if custom.enabled and type(custom.members) == "table" and custom.members[row.id] then return true end
    end
    return false
end

function S.CreatePool(category, name)
    if category ~= "mount" and category ~= "pet" and category ~= "toy" then return end
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return end
    local pools = Settings()[category].customPools
    if #pools >= 12 then return end
    pools[#pools + 1] = { name = name:sub(1, 26), enabled = true, members = {} }
    return #pools
end

function S.SetPoolMember(category, index, id, selected)
    local pool = Settings()[category].customPools[index]
    if not pool or type(id) ~= "number" then return false end
    pool.members[id] = selected and true or nil
    return true
end

function S.DeletePool(category, index)
    local pools = Settings()[category].customPools
    if not pools[index] then return false end
    table.remove(pools, index)
    for _, shortcut in pairs(Settings().shortcuts) do
        if shortcut.category == category and type(shortcut.filter) == "string" then
            local old = tonumber(shortcut.filter:match("^pool:(%d+)$"))
            if old == index then shortcut.filter = nil
            elseif old and old > index then shortcut.filter = "pool:" .. (old - 1) end
        end
    end
    return true
end

function S.GetTravelTag(id, row, tag)
    if not (row and row.travel and row.travel[tag] ~= nil) then return false end
    local overrides = Settings().mount.travelTags[id]
    if type(overrides) == "table" and overrides[tag] ~= nil then return overrides[tag] end
    return row.travel[tag] == true
end

function S.ToggleTravelTag(id, row, tag)
    if not S.GetTravelTag(id, row, tag) and not (row and row.travel and row.travel[tag] ~= nil) then return end
    local tags = Settings().mount.travelTags
    if type(tags[id]) ~= "table" then tags[id] = {} end
    tags[id][tag] = not S.GetTravelTag(id, row, tag)
end

function S.GetRating(category, id)
    local value = Settings()[category].ratings[id]
    return type(value) == "number" and math.max(0, math.min(4, math.floor(value))) or 2
end

function S.SetRating(category, id, value)
    Settings()[category].ratings[id] = math.max(0, math.min(4, math.floor(tonumber(value) or 2)))
end

function S.GetGroup(category, row)
    return Settings()[category].groups[row.id] or row.group or GROUPS[category][#GROUPS[category]]
end

function S.SetGroup(category, id, group)
    for _, allowed in ipairs(GROUPS[category]) do
        if group == allowed then
            Settings()[category].groups[id] = allowed == "Any" and nil or allowed
            return true
        end
    end
    return false
end

S.Groups = GROUPS

function S.MatchesGroup(category, row, group)
    if group == "Any" then return true end
    if category == "mount" and (group == "Ground" or group == "Sky" or group == "Aquatic") then
        return S.GetTravelTag(row.id, row, group)
    end
    return S.GetGroup(category, row) == group
end

function S.Counts(category, rows)
    local counts = { picked = 0, favorite = 0, all = #rows, selected = 0, usable = 0 }
    local settings = Settings()[category]
    for _, row in ipairs(rows) do
        if row.favorite then counts.favorite = counts.favorite + 1 end
        if settings.picks[row.id] then counts.picked = counts.picked + 1 end
        for key in pairs(row.packs or {}) do counts[key] = (counts[key] or 0) + 1 end
        if S.IsSelected(category, row, settings) then
            counts.selected = counts.selected + 1
            if row.usable and S.GetRating(category, row.id) > 0 then counts.usable = counts.usable + 1 end
        end
    end
    return counts
end

local lastChoice = {}
function S.Pick(category, rows, filter)
    local eligible = {}
    local totalWeight = 0
    for _, row in ipairs(rows or S.Collect(category)) do
        local rating = S.GetRating(category, row.id)
        local pool = Settings()[category]
        local effectiveFilter = filter or (pool.launcherMode == "favorites" and "favorite" or nil)
        local matches = not effectiveFilter or effectiveFilter == "Any" or S.MatchesGroup(category, row, effectiveFilter)
            or filter == ("item:" .. tostring(row.id))
            or (effectiveFilter == "favorite" and row.favorite)
            or (effectiveFilter == "picked" and pool.picks[row.id])
            or (type(effectiveFilter) == "string" and effectiveFilter:sub(1, 5) == "pool:"
                and pool.customPools[tonumber(effectiveFilter:sub(6))]
                and pool.customPools[tonumber(effectiveFilter:sub(6))].members[row.id])
            or (row.packs and row.packs[effectiveFilter])
        if row.usable and rating > 0 and matches and (effectiveFilter or S.IsSelected(category, row)) then
            local weight = ({ 0, 1, 3, 7, 15 })[rating + 1]
            totalWeight = totalWeight + weight
            eligible[#eligible + 1] = { row = row, weight = weight }
        end
    end
    if #eligible == 0 then return nil end
    local previous = lastChoice[category .. ":" .. tostring(filter or "pool")]
    if #eligible > 1 then
        for i = #eligible, 1, -1 do
            if eligible[i].row.id == previous then
                totalWeight = totalWeight - eligible[i].weight
                table.remove(eligible, i)
                break
            end
        end
    end
    local draw = math.random(totalWeight)
    for _, entry in ipairs(eligible) do
        draw = draw - entry.weight
        if draw <= 0 then
            lastChoice[category .. ":" .. tostring(filter or "pool")] = entry.row.id
            return entry.row
        end
    end
end

local function Message(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r " .. message) end
end

function S.Summon(category, filter)
    if category == "toy" or category == "mount" then
        Message((category == "toy" and "Toys" or "Mounts")
            .. " need the Random button in /whrandom or its keybind on the Shortcuts tab.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        Message("Random " .. (LABELS[category] or "collection") .. " is unavailable in combat.")
        return false
    end
    local row = S.Pick(category, nil, filter)
    if not row then
        Message("No usable " .. (LABELS[category] or "items"):lower() .. " in this pool. Open /whrandom to choose a pool.")
        return false
    end
    if category == "pet" and C_PetJournal and C_PetJournal.SummonPetByGUID then
        C_PetJournal.SummonPetByGUID(row.guid)
    else
        Message("This collection action is unavailable on this client.")
        return false
    end
    return true
end

-- Named functions are used by Bindings.xml. A binding is a real player key
-- press, which toy use requires; no timer or automatic toy activation exists.
_G.WaffleHouseRandomSummonerToggle = function() S.Toggle() end
_G.WaffleHouseRandomSummonerMount = function() S.Toggle("mount", "collection") end
_G.WaffleHouseRandomSummonerPet = function() S.Summon("pet") end
_G.BINDING_NAME_WH_RANDOM_SUMMONER = "Open Random Summoner"
_G.BINDING_NAME_WH_RANDOM_MOUNT = "Open random mount pool (legacy key)"
_G.BINDING_NAME_WH_RANDOM_PET = "Random pet from my pool"
_G["BINDING_NAME_CLICK WaffleHouseRandomMountKeyButton:LeftButton"] = "Random mount from my pool"
_G["BINDING_NAME_CLICK WaffleHouseRandomToyKeyButton:LeftButton"] = "Random toy from my pool"
local SHORTCUT_COUNT = 12
local function ShortcutCommand(index)
    return ("CLICK WaffleHouseRandomShortcut%02d:LeftButton"):format(index)
end
for index = 1, SHORTCUT_COUNT do
    _G["BINDING_NAME_" .. ShortcutCommand(index)] = ("Random Summoner shortcut %d"):format(index)
end

local WIDTH, HEIGHT, GUTTER = 600, 660, 18
local GREEN = { 0.05, 0.82, 0.62 }
local QUALITY = { [0] = { 0.62, 0.64, 0.65 }, [1] = { 0.91, 0.94, 0.94 },
    [2] = { 0.12, 0.95, 0.22 }, [3] = { 0.12, 0.57, 1 },
    [4] = { 0.71, 0.29, 0.96 }, [5] = { 1, 0.49, 0 }, [6] = { 0.9, 0.7, 0.35 } }
local panel, launcher, selectedCategory, currentRows, currentCounts, page, search
local Refresh, RefreshLauncher
local activePool = { mount = 0, pet = 0, toy = 0 }
local rowsPerPage = 7
local bindCapture, bindCaptureSlot, replaceKey
local viewMode, shortcutPage = "collection", 1
local browseFilter = { mount = "Any", pet = "Any", toy = "Any" }
local bindingCommands = {
    mount = "CLICK WaffleHouseRandomMountKeyButton:LeftButton",
    pet = "WH_RANDOM_PET",
    toy = "CLICK WaffleHouseRandomToyKeyButton:LeftButton",
}

local function FilterOptions(category)
    local options = { { value = nil, label = "My Pool" }, { value = "Any", label = "All Collected" } }
    for _, group in ipairs(GROUPS[category]) do
        if group ~= "Any" then options[#options + 1] = { value = group, label = group } end
    end
    for _, pack in ipairs(PACKS[category]) do
        if pack.key ~= "all" then options[#options + 1] = { value = pack.key, label = pack.label } end
    end
    for index, pool in ipairs(Settings()[category].customPools) do
        options[#options + 1] = { value = "pool:" .. index, label = pool.name }
    end
    return options
end

local function FilterLabel(category, value, shortcut)
    if type(value) == "string" and value:sub(1, 5) == "item:" then
        return "Only: " .. (shortcut and shortcut.itemName or value:sub(6))
    end
    for _, option in ipairs(FilterOptions(category)) do
        if option.value == value then return option.label end
    end
    return "My Pool"
end

function S.CreateShortcut(category)
    if not LABELS[category] then return nil end
    local shortcuts = Settings().shortcuts
    for index = 1, SHORTCUT_COUNT do
        if not shortcuts[index] then
            shortcuts[index] = { category = category, name = "Random " .. LABELS[category], filter = nil }
            return index
        end
    end
end

function S.DeleteShortcut(index)
    local shortcuts = Settings().shortcuts
    if not shortcuts[index] then return end
    shortcuts[index] = nil
    local command = ShortcutCommand(index)
    if GetBindingKey and SetBinding then
        local first, second = GetBindingKey(command)
        if first then SetBinding(first) end
        if second then SetBinding(second) end
        if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
    end
end

-- UseToy is protected. A real secure click chooses one toy in PreClick,
-- performs the action through Blizzard's secure "toy" handler, then disarms
-- the button. The disarmed button is safe if combat begins before the next key.
function S.PrepareToyButton(button, filter)
    if InCombatLockdown and InCombatLockdown() then return false end
    local choice = S.Pick("toy", nil, filter)
    button:SetAttribute("type", choice and "toy" or nil)
    button:SetAttribute("toy", choice and choice.id or nil)
    if not choice then Message("No usable toys in this pool. Open /whrandom to choose a pool.") end
    return choice ~= nil
end

-- Mount journal summoning is protected. Arm the secure spell action with the
-- mount's cast name on the actual hardware click instead of calling the
-- journal's SummonByID from addon Lua.
function S.PrepareMountButton(button, filter)
    if InCombatLockdown and InCombatLockdown() then return false end
    local choice = S.Pick("mount", nil, filter)
    local info = choice and type(choice.spellID) == "number"
        and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(choice.spellID)
    local castName = (info and info.name) or (choice and choice.name)
    if IsSecret(castName) or type(castName) ~= "string" or castName == "" then castName = nil end
    button:SetAttribute("type", castName and "spell" or nil)
    button:SetAttribute("spell", castName)
    if not castName then Message("No usable mounts in this pool. Open /whrandom to choose a pool.") end
    return castName ~= nil
end

function S.ActivateShortcut(index, button)
    local shortcut = Settings().shortcuts[index]
    if not shortcut or not LABELS[shortcut.category] then return false end
    if shortcut.category == "toy" then
        return S.PrepareToyButton(button, shortcut.filter)
    elseif shortcut.category == "mount" then
        return S.PrepareMountButton(button, shortcut.filter)
    end
    return S.Summon(shortcut.category, shortcut.filter)
end

local function MakeShortcutButton(index)
    local button = CreateFrame("Button", ("WaffleHouseRandomShortcut%02d"):format(index),
        UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetSize(1, 1)
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    button:SetAlpha(0)
    button:SetScript("PreClick", function(self) S.ActivateShortcut(index, self) end)
    button:SetScript("PostClick", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then
            self:SetAttribute("type", nil)
            self:SetAttribute("toy", nil)
            self:SetAttribute("spell", nil)
        end
    end)
    return button
end

local function MakeMountButton(name, parent)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self) S.PrepareMountButton(self) end)
    button:SetScript("PostClick", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then
            self:SetAttribute("type", nil)
            self:SetAttribute("spell", nil)
        end
    end)
    return button
end

local function MakeToyButton(name, parent)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", nil)
    button:SetScript("PreClick", function(self) S.PrepareToyButton(self) end)
    button:SetScript("PostClick", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then
            self:SetAttribute("type", nil)
            self:SetAttribute("toy", nil)
        end
    end)
    return button
end

local function Font(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local path = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")
    fs:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    fs:SetTextColor(unpack(color or { 0.88, 0.9, 0.91 }))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Surface(frame, r, g, b)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(r or 0.055, g or 0.061, b or 0.068, 0.98)
    frame:SetBackdropBorderColor(1, 1, 1, 0.18)
end

-- Two-pixel corner cutouts on every corner; no large card-like radius.
local function SoftPanel(frame, width, height)
    frame:SetBackdrop(nil)
    local function Rect(layer, x, y, w, h, r, g, b, a)
        local texture = frame:CreateTexture(nil, layer)
        texture:SetColorTexture(r, g, b, a)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
        texture:SetSize(w, h)
    end
    Rect("BACKGROUND", 2, 0, width - 4, height, 0.055, 0.061, 0.068, 0.99)
    Rect("BACKGROUND", 0, 2, width, height - 4, 0.055, 0.061, 0.068, 0.99)
    Rect("BORDER", 2, 0, width - 4, 1, 0.3, 0.34, 0.36, 0.7)
    Rect("BORDER", 2, height - 1, width - 4, 1, 0.3, 0.34, 0.36, 0.7)
    Rect("BORDER", 0, 2, 1, height - 4, 0.3, 0.34, 0.36, 0.7)
    Rect("BORDER", width - 1, 2, 1, height - 4, 0.3, 0.34, 0.36, 0.7)
end

local function Button(parent, label, w, h, click)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(w, h)
    Surface(button, 0.09, 0.105, 0.115)
    button.text = Font(button, 11)
    button.text:SetPoint("LEFT", 8, 0)
    button.text:SetPoint("RIGHT", -8, 0)
    button.text:SetJustifyH("CENTER")
    button.text:SetText(label)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetVertexColor(0.05, 0.82, 0.62, 0.16) end
    button:SetScript("OnClick", click)
    return button
end

local function ArtButton(parent, texture, size, click)
    local button = Button(parent, "", size, size, click)
    button.text:Hide()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(texture)
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(size - 3, size - 3)
    button:SetScript("OnMouseDown", function(self)
        self.icon:ClearAllPoints(); self.icon:SetPoint("CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.icon:ClearAllPoints(); self.icon:SetPoint("CENTER", 0, 0)
    end)
    return button
end

local function ActionVisual(button, category)
    button:SetSize(126, 27)
    button:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.52)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(CATEGORY_ART[category])
    button.icon:SetPoint("LEFT", 4, 0)
    button.icon:SetSize(23, 23)
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 29, 0)
    button.text:SetPoint("RIGHT", -5, 0)
    button.text:SetJustifyH("CENTER")
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 0.18) end
end

local function ChevronButton(parent, direction, click)
    local button = Button(parent, "", 26, 24, click)
    button.text:Hide()
    local angle = math.pi / 4
    for index = 1, 2 do
        local arm = button:CreateTexture(nil, "ARTWORK")
        arm:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.95)
        arm:SetSize(10, 2)
        arm:SetPoint("CENTER", button, "CENTER", 0, index == 1 and 3 or -3)
        local rotation = direction == "right" and (index == 1 and -angle or angle)
            or (index == 1 and angle or -angle)
        arm:SetRotation(rotation)
    end
    return button
end

local function EditBox(parent, width, height)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetSize(width, height)
    Surface(edit, 0.055, 0.075, 0.083)
    edit:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.4)
    local path = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")
    edit:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(0.93, 0.96, 0.95)
    edit:SetTextInsets(8, 8, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

local function BindLabel(command, slot)
    local first, second = GetBindingKey and GetBindingKey(command)
    local key = slot == 2 and second or first
    return key and (GetBindingText and GetBindingText(key) or key) or "+ Set key"
end

local function EndCapture()
    bindCapture, bindCaptureSlot, replaceKey = nil, nil, nil
    if panel then panel:EnableKeyboard(false) end
    if Refresh then Refresh() end
end

local function SetKey(key)
    if not bindCapture or not SetBinding then return end
    local existing = GetBindingAction and GetBindingAction(key) or ""
    if existing ~= "" and existing ~= bindCapture and replaceKey ~= key then
        replaceKey = key
        panel.keyHint:SetText("Key in use. Press it again to replace, or Esc to cancel.")
        return
    end
    local first, second = GetBindingKey and GetBindingKey(bindCapture)
    local old = bindCaptureSlot == 2 and second or first
    if old then SetBinding(old) end
    if SetBinding(key, bindCapture) then
        if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
        EndCapture()
    else
        panel.keyHint:SetText("That key cannot be assigned. Try another.")
    end
end

local function StartKeyCapture(command, slot, label)
    if InCombatLockdown and InCombatLockdown() then
        panel.keyHint:SetText("Keys cannot be changed in combat.")
        return
    end
    bindCapture, bindCaptureSlot, replaceKey = command, slot, nil
    panel:EnableKeyboard(true)
    panel.keyHint:SetText("Press a key for " .. label .. ". Esc cancels. Right-click a key to remove it.")
    Refresh()
end

local function ClearKey(command, slot)
    if InCombatLockdown and InCombatLockdown() then return end
    local first, second = GetBindingKey and GetBindingKey(command)
    local key = slot == 2 and second or first
    if key and SetBinding then
        SetBinding(key)
        if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
    end
    Refresh()
end

local function EnsurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "WaffleHouseRandomSummoner", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) == "number" and type(screenHeight) == "number" then
        panel:SetScale(math.min(1, (screenWidth - 32) / WIDTH, (screenHeight - 32) / HEIGHT))
    end
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:EnableKeyboard(false)
    panel:SetScript("OnKeyDown", function(_, key)
        if not bindCapture then return end
        if key == "ESCAPE" then EndCapture(); return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
            or key == "LALT" or key == "RALT" or key == "UNKNOWN" then return end
        local prefix = (IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "")
            .. (IsAltKeyDown and IsAltKeyDown() and "ALT-" or "")
            .. (IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "")
        SetKey(prefix .. key)
    end)
    SoftPanel(panel, WIDTH, HEIGHT)
    panel:SetScript("OnHide", EndCapture)

    local title = Font(panel, 17, GREEN)
    title:SetPoint("TOPLEFT", GUTTER, -16)
    title:SetText("Random Summoner")
    local subtitle = Font(panel, 10, { 0.62, 0.67, 0.69 })
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Choose a pool, rate what you love, and set shortcuts for each collection.")
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetWidth(WIDTH - 70)
    drag:SetHeight(48)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local close = Button(panel, "x", 27, 25, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", -GUTTER, -14)
    close:SetFrameLevel((drag:GetFrameLevel() or 0) + 1)
    panel.close = close

    panel.tabs = {}
    for i, category in ipairs(CATEGORIES) do
        local tab = Button(panel, LABELS[category], 180, 30, function()
            selectedCategory, page, search, viewMode = category, 1, "", "collection"
            panel.search:SetText("")
            panel.filterMenu:Hide()
            Refresh()
        end)
        tab:SetPoint("TOPLEFT", GUTTER + (i - 1) * 192, -65)
        panel.tabs[category] = tab
    end

    panel.summary = Font(panel, 11, GREEN)
    panel.summary:SetPoint("TOPLEFT", GUTTER, -106)
    panel.summary:SetWidth(WIDTH - GUTTER * 2 - 145)
    panel.shortcutToggle = Button(panel, "Shortcuts & Keys", 139, 26, function()
        viewMode = "shortcuts"
        shortcutPage = 1
        panel.filterMenu:Hide()
        Refresh()
    end)
    panel.shortcutToggle:SetPoint("TOPRIGHT", -GUTTER, -101)
    panel.poolSelect = Button(panel, "My Picks", 145, 25, function(self)
        panel.OpenFilterMenu(self, "pool")
    end)
    panel.poolSelect:SetPoint("TOPLEFT", GUTTER, -125)
    panel.poolName = EditBox(panel, 192, 25)
    panel.poolName:SetPoint("TOPLEFT", GUTTER + 153, -125)
    panel.poolName:SetText("")
    panel.poolPlaceholder = Font(panel.poolName, 10, { 0.46, 0.55, 0.57 })
    panel.poolPlaceholder:SetPoint("LEFT", 8, 0)
    panel.poolPlaceholder:SetText("New Pool Name")
    panel.poolName:SetScript("OnTextChanged", function(self)
        panel.poolPlaceholder:SetShown(self:GetText() == "")
    end)
    panel.poolName:SetScript("OnEnterPressed", function(self)
        local index = S.CreatePool(selectedCategory, self:GetText())
        if index then activePool[selectedCategory] = index; self:SetText("") end
        self:ClearFocus(); Refresh()
    end)
    panel.poolAdd = Button(panel, "Create", 80, 25, function()
        local index = S.CreatePool(selectedCategory, panel.poolName:GetText())
        if index then activePool[selectedCategory] = index; panel.poolName:SetText("") end
        panel.poolName:ClearFocus(); Refresh()
    end)
    panel.poolAdd:SetPoint("TOPLEFT", GUTTER + 353, -125)
    panel.poolEnabled = Button(panel, "Active", 65, 25, function()
        local custom = Settings()[selectedCategory].customPools[activePool[selectedCategory]]
        if custom then custom.enabled = not custom.enabled; Refresh() end
    end)
    panel.poolEnabled:SetPoint("TOPLEFT", GUTTER + 441, -125)
    panel.poolDelete = Button(panel, "X", 35, 25, function()
        local index = activePool[selectedCategory]
        if index > 0 then
            S.DeletePool(selectedCategory, index)
            activePool[selectedCategory] = 0
            Refresh()
        end
    end)
    panel.poolDelete:SetPoint("TOPLEFT", GUTTER + 514, -125)

    panel.packs = {}
    for i = 1, 8 do
        local x = GUTTER + ((i - 1) % 2) * 288
        local y = -153 - math.floor((i - 1) / 2) * 29
        local button = Button(panel, "", 276, 24, function(self)
            local def = self.def
            if not def then return end
            local packs = Settings()[selectedCategory].packs
            packs[def.key] = not packs[def.key]
            Refresh()
        end)
        button:SetPoint("TOPLEFT", x, y)
        button:SetScript("OnEnter", function(self)
            if not (self.def and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.def.label)
            local count = currentCounts and currentCounts[self.def.key] or 0
            if count == 0 and self.def.key ~= "picked" and self.def.key ~= "favorite" then
                GameTooltip:AddLine("No collected item matched the available source data. Collection metadata can be incomplete or localized differently. Add items to a custom pool above.", 0.8, 0.73, 0.52, true)
            else
                GameTooltip:AddLine("Click to include or exclude this set from your rated pool.", 0.7, 0.75, 0.77, true)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.packs[i] = button
    end

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetPoint("TOPLEFT", GUTTER, -276)
    divider:SetSize(WIDTH - GUTTER * 2, 1)
    local pickTitle = Font(panel, 12, GREEN)
    pickTitle:SetPoint("TOPLEFT", GUTTER, -287)
    pickTitle:SetText("COLLECTION")
    panel.pickTitle = pickTitle
    local pickHelp = Font(panel, 10, { 0.66, 0.7, 0.72 })
    pickHelp:SetPoint("TOPLEFT", GUTTER + 104, -289)
    pickHelp:SetText("Click to include. Weight: 0 off, 4 frequent.")
    panel.pickHelp = pickHelp
    panel.weightHeader = Font(panel, 10, GREEN)
    panel.weightHeader:SetPoint("TOPRIGHT", -24, -288)
    panel.weightHeader:SetWidth(110)
    panel.weightHeader:SetJustifyH("CENTER")
    panel.weightHeader:SetText("WEIGHT")
    panel.filterButton = Button(panel, "Show: All", 150, 27, function(self)
        panel.OpenFilterMenu(self, "browse")
    end)
    panel.filterButton:SetPoint("TOPLEFT", GUTTER, -309)
    panel.search = EditBox(panel, WIDTH - GUTTER * 2 - 161, 27)
    panel.search:SetPoint("TOPLEFT", GUTTER + 161, -309)
    panel.search:SetText("")
    panel.searchPlaceholder = Font(panel.search, 10, { 0.46, 0.55, 0.57 })
    panel.searchPlaceholder:SetPoint("LEFT", 9, 0)
    panel.searchPlaceholder:SetText("Search collection...")
    panel.search:SetScript("OnTextChanged", function(self)
        search, page = self:GetText() or "", 1
        panel.searchPlaceholder:SetShown(search == "")
        Refresh()
    end)
    panel.listRows = {}
    for i = 1, rowsPerPage do
        local row = Button(panel, "", WIDTH - GUTTER * 2, 34, function(self)
            if not self.item then return end
            local index = activePool[selectedCategory]
            if index > 0 then
                local custom = Settings()[selectedCategory].customPools[index]
                if custom then S.SetPoolMember(selectedCategory, index, self.item.id, not custom.members[self.item.id]) end
            else
                local picks = Settings()[selectedCategory].picks
                picks[self.item.id] = not picks[self.item.id] or nil
            end
            Refresh()
        end)
        row:SetPoint("TOPLEFT", GUTTER, -344 - (i - 1) * 37)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetSize(25, 25)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")
        row.iconBorder:SetSize(27, 27)
        Surface(row.iconBorder, 0, 0, 0)
        row.iconBorder:SetBackdropColor(0, 0, 0, 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 37, 0)
        row.text:SetPoint("RIGHT", -250, 0)
        row.text:SetJustifyH("LEFT")
        row.groupButton = Button(row, "Group", 116, 26, function(self)
            if row.item then panel.OpenFilterMenu(self, "group", row.item.id) end
        end)
        row.groupButton:SetPoint("RIGHT", row, "RIGHT", -124, 0)
        row.travelButtons = {}
        for index, tag in ipairs(TRAVEL_TAGS) do
            local travel = ArtButton(row, TRAVEL_ART[tag], 26, function()
                if row.item then S.ToggleTravelTag(row.item.id, row.item, tag); Refresh() end
            end)
            travel:SetPoint("RIGHT", row, "RIGHT", -214 + (index - 1) * 29, 0)
            travel:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(tag .. " Travel")
                    GameTooltip:AddLine("Click to include or exclude this mount from " .. tag .. " shortcuts.", 0.7, 0.75, 0.77, true)
                    GameTooltip:Show()
                end
            end)
            travel:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row.travelButtons[index] = travel
        end
        row.utility = Button(row, "...", 27, 26, function(self)
            if row.item then panel.OpenFilterMenu(self, "group", row.item.id) end
        end)
        row.utility:SetPoint("RIGHT", row, "RIGHT", -124, 0)
        row.weight = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.weight:SetSize(110, 26)
        row.weight:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        Surface(row.weight, 0.048, 0.066, 0.072)
        row.weight:SetBackdropBorderColor(1, 1, 1, 0.2)
        row.weightRail = row.weight:CreateTexture(nil, "ARTWORK")
        row.weightRail:SetColorTexture(0.38, 0.48, 0.49, 0.48)
        row.weightRail:SetPoint("LEFT", row.weight, "LEFT", 11, 0)
        row.weightRail:SetSize(86, 2)
        row.weightTicks = {}
        for rating = 0, 4 do
            local tick = row.weight:CreateTexture(nil, "ARTWORK")
            tick:SetColorTexture(0.57, 0.69, 0.68, 0.48)
            tick:SetPoint("LEFT", row.weight, "LEFT", 12 + rating * 21, 0)
            tick:SetSize(1, 7)
            row.weightTicks[rating] = tick
        end
        row.weightFill = row.weight:CreateTexture(nil, "OVERLAY")
        row.weightFill:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.86)
        row.weightFill:SetPoint("LEFT", row.weight, "LEFT", 12, 0)
        row.weightFill:SetHeight(2)
        row.weightSelect = row.weight:CreateTexture(nil, "OVERLAY")
        row.weightSelect:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        row.weightSelect:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 1)
        row.weightSelect:SetSize(18, 18)
        row.weightValue = Font(row.weight, 10, { 0.02, 0.13, 0.12 })
        row.weightValue:SetPoint("CENTER", row.weightSelect, "CENTER", 0, 0)
        row.weightValue:SetJustifyH("CENTER")
        row.weightButtons = {}
        for rating = 0, 4 do
            local choice = CreateFrame("Button", nil, row.weight)
            choice:SetSize(21, 24)
            choice:SetPoint("LEFT", row.weight, "LEFT", 2 + rating * 21, 0)
            choice:SetScript("OnClick", function()
                if row.item then S.SetRating(selectedCategory, row.item.id, rating); Refresh() end
            end)
            choice:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local meaning = ({ "Off: never picked", "Low chance", "Normal chance",
                        "High chance", "Highest chance" })[rating + 1]
                    GameTooltip:SetText("Weight " .. rating .. " / 4")
                    GameTooltip:AddLine(meaning .. ". Click to set this weight directly.", 0.7, 0.75, 0.77, true)
                    GameTooltip:Show()
                end
            end)
            choice:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row.weightButtons[rating] = choice
        end
        panel.listRows[i] = row
    end
    panel.previous = ChevronButton(panel, "left", function() page = math.max(1, page - 1); Refresh() end)
    panel.previous:SetPoint("TOPLEFT", GUTTER, -606)
    panel.pageText = Font(panel, 10)
    panel.pageText:SetPoint("LEFT", panel.previous, "RIGHT", 7, 0)
    panel.next = ChevronButton(panel, "right", function() page = page + 1; Refresh() end)
    panel.next:SetPoint("LEFT", panel.pageText, "RIGHT", 8, 0)
    panel.action = Button(panel, "Random Pet", 110, 25, function() S.Summon("pet"); Refresh() end)
    ActionVisual(panel.action, "pet")
    panel.action:SetPoint("TOPRIGHT", -GUTTER, -606)
    panel.mountAction = MakeMountButton(nil, panel)
    panel.mountAction:SetSize(126, 27)
    panel.mountAction:SetPoint("TOPRIGHT", -GUTTER, -606)
    Surface(panel.mountAction, 0.09, 0.105, 0.115)
    panel.mountAction.text = Font(panel.mountAction, 11)
    panel.mountAction.text:SetAllPoints()
    panel.mountAction.text:SetJustifyH("CENTER")
    panel.mountAction.text:SetText("Random Mount")
    ActionVisual(panel.mountAction, "mount")
    panel.mountAction:Hide()
    panel.toyAction = MakeToyButton(nil, panel)
    panel.toyAction:SetSize(126, 27)
    panel.toyAction:SetPoint("TOPRIGHT", -GUTTER, -606)
    Surface(panel.toyAction, 0.09, 0.105, 0.115)
    panel.toyAction.text = Font(panel.toyAction, 11)
    panel.toyAction.text:SetAllPoints()
    panel.toyAction.text:SetJustifyH("CENTER")
    panel.toyAction.text:SetText("Random Toy")
    ActionVisual(panel.toyAction, "toy")
    panel.toyAction:Hide()

    local bindDivider = panel:CreateTexture(nil, "ARTWORK")
    bindDivider:SetColorTexture(1, 1, 1, 0.12)
    bindDivider:SetPoint("TOPLEFT", GUTTER, -638)
    bindDivider:SetSize(WIDTH - GUTTER * 2, 1)
    panel.hint = Font(panel, 10, { 0.67, 0.72, 0.74 })
    panel.hint:SetPoint("TOPLEFT", GUTTER, -644)
    panel.hint:SetWidth(WIDTH - GUTTER * 2)
    panel.hint:SetText("Groups are editable. Auto groups are suggestions from names and descriptions.")
    panel.collectionWidgets = { panel.summary, panel.shortcutToggle, panel.poolSelect,
        panel.poolName, panel.poolAdd, panel.poolEnabled, panel.poolDelete, divider, pickTitle, pickHelp,
        panel.weightHeader,
        panel.filterButton, panel.search, panel.previous, panel.pageText, panel.next, panel.action, panel.mountAction, panel.toyAction,
        bindDivider, panel.hint }
    for _, button in ipairs(panel.packs) do panel.collectionWidgets[#panel.collectionWidgets + 1] = button end
    for _, button in ipairs(panel.listRows) do panel.collectionWidgets[#panel.collectionWidgets + 1] = button end

    panel.keysPage = CreateFrame("Frame", nil, panel)
    panel.keysPage:SetPoint("TOPLEFT", GUTTER, -105)
    panel.keysPage:SetSize(WIDTH - GUTTER * 2, 535)
    local keysTitle = Font(panel.keysPage, 13, GREEN)
    keysTitle:SetPoint("TOPLEFT", 0, 0)
    panel.keysTitle = keysTitle
    local back = Button(panel.keysPage, "Back to collection", 148, 27, function()
        viewMode = "collection"
        panel.filterMenu:Hide()
        Refresh()
    end)
    back:SetPoint("TOPRIGHT", 0, 6)
    local keysHelp = Font(panel.keysPage, 10, { 0.68, 0.72, 0.74 })
    keysHelp:SetPoint("TOPLEFT", 0, -25)
    keysHelp:SetText("Click a key box, then press a key. Right-click a box to clear it. Esc cancels.")
    panel.bindingRows = {}
    for i = 1, 2 do
        local row = CreateFrame("Frame", nil, panel.keysPage)
        row:SetPoint("TOPLEFT", 0, -61 - (i - 1) * 44)
        row:SetSize(WIDTH - GUTTER * 2, 35)
        local label = Font(row, 11)
        label:SetPoint("LEFT", 3, 0)
        row.label = label
        row.keys = {}
        for slot = 1, 2 do
            local keyButton = Button(row, "+ Set key", 112, 29, function(_, mouseButton)
                local command = i == 1 and "WH_RANDOM_SUMMONER" or bindingCommands[selectedCategory]
                if mouseButton == "RightButton" then ClearKey(command, slot)
                else StartKeyCapture(command, slot, i == 1 and "open popup" or ("random " .. LABELS[selectedCategory])) end
            end)
            keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            keyButton:SetPoint("RIGHT", row, "RIGHT", slot == 1 and -126 or -4, 0)
            row.keys[slot] = keyButton
        end
        panel.bindingRows[i] = row
    end
    local customTitle = Font(panel.keysPage, 12, GREEN)
    customTitle:SetPoint("TOPLEFT", 2, -156)
    customTitle:SetText("CUSTOM SHORTCUTS")
    local addShortcut = Button(panel.keysPage, "+ Add shortcut", 136, 27, function()
        if InCombatLockdown and InCombatLockdown() then return end
        local index = S.CreateShortcut(selectedCategory)
        if index then
            local ordinal = 0
            for candidate = 1, index do
                local item = Settings().shortcuts[candidate]
                if item and item.category == selectedCategory then ordinal = ordinal + 1 end
            end
            shortcutPage = math.floor((ordinal - 1) / 4) + 1
            Refresh()
        else
            panel.keyHint:SetText("All 12 custom shortcut slots are in use.")
        end
    end)
    addShortcut:SetPoint("TOPRIGHT", 0, -148)
    panel.shortcutRows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, panel.keysPage)
        row:SetPoint("TOPLEFT", 0, -196 - (i - 1) * 54)
        row:SetSize(WIDTH - GUTTER * 2, 47)
        row.name = EditBox(row, 157, 28)
        row.name:SetPoint("LEFT", 0, 0)
        local function SaveShortcutName(self)
            local item = Settings().shortcuts[row.index]
            if item then
                local value = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
                item.name = value ~= "" and value:sub(1, 32) or ("Random " .. LABELS[item.category])
            end
            Refresh()
        end
        row.name:SetScript("OnEditFocusLost", SaveShortcutName)
        row.name:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        row.filter = Button(row, "My pool", 136, 28, function(self)
            if row.index then panel.OpenFilterMenu(self, "shortcut", row.index) end
        end)
        row.filter.menuAbove = i > 1
        row.filter:SetPoint("LEFT", row, "LEFT", 164, 0)
        row.keys = {}
        for slot = 1, 2 do
            local keyButton = Button(row, "+ Set key", 97, 28, function(_, mouseButton)
                if not row.index then return end
                local command = ShortcutCommand(row.index)
                if mouseButton == "RightButton" then ClearKey(command, slot)
                else StartKeyCapture(command, slot, Settings().shortcuts[row.index].name) end
            end)
            keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            keyButton:SetPoint("LEFT", row, "LEFT", slot == 1 and 307 or 411, 0)
            row.keys[slot] = keyButton
        end
        row.remove = Button(row, "x", 29, 28, function()
            if InCombatLockdown and InCombatLockdown() then return end
            S.DeleteShortcut(row.index)
            Refresh()
        end)
        row.remove:SetPoint("LEFT", row, "LEFT", 516, 0)
        panel.shortcutRows[i] = row
    end
    panel.shortcutPrevious = ChevronButton(panel.keysPage, "left", function()
        shortcutPage = math.max(1, shortcutPage - 1); Refresh()
    end)
    panel.shortcutPrevious:SetPoint("TOPLEFT", 0, -417)
    panel.shortcutPageText = Font(panel.keysPage, 10)
    panel.shortcutPageText:SetPoint("LEFT", panel.shortcutPrevious, "RIGHT", 8, 0)
    panel.shortcutNext = ChevronButton(panel.keysPage, "right", function()
        shortcutPage = shortcutPage + 1; Refresh()
    end)
    panel.shortcutNext:SetPoint("LEFT", panel.shortcutPageText, "RIGHT", 8, 0)
    local launchTitle = Font(panel.keysPage, 11)
    launchTitle:SetPoint("TOPLEFT", 3, -461)
    launchTitle:SetText("Floating launcher")
    panel.launchToggle = Button(panel.keysPage, "", 160, 30, function()
        Settings().showLauncher = not Settings().showLauncher
        RefreshLauncher()
        Refresh()
    end)
    panel.launchToggle:SetPoint("TOPRIGHT", 0, -453)
    panel.keyHint = Font(panel.keysPage, 10, { 0.68, 0.72, 0.74 })
    panel.keyHint:SetPoint("TOPLEFT", 3, -505)
    panel.keyHint:SetWidth(WIDTH - GUTTER * 2 - 6)
    panel.keyHint:SetText("Shortcuts draw from their chosen group; each supports two keys.")

    panel.filterMenu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    Surface(panel.filterMenu, 0.055, 0.073, 0.081)
    panel.filterMenu:SetFrameLevel((panel:GetFrameLevel() or 0) + 20)
    panel.filterMenu:EnableMouse(true)
    panel.filterMenu.entries = {}
    for i = 1, 32 do
        local entry = Button(panel.filterMenu, "", 174, 23, function(self)
            local option = self.option
            local mode, category, id = panel.filterMenu.mode, panel.filterMenu.category, panel.filterMenu.id
            if mode == "browse" then browseFilter[category] = option.value or "Any"; page = 1
            elseif mode == "pool" then activePool[category] = option.value or 0
            elseif mode == "group" and option.value == "__itemShortcut" then
                local index = S.CreateShortcut(category)
                if index then
                    for _, item in ipairs(currentRows or {}) do
                        if item.id == id then
                            Settings().shortcuts[index].name = item.name:sub(1, 32)
                            Settings().shortcuts[index].itemName = item.name
                            break
                        end
                    end
                    Settings().shortcuts[index].filter = "item:" .. tostring(id)
                    viewMode = "shortcuts"
                    local ordinal = 0
                    for candidate = 1, index do
                        local item = Settings().shortcuts[candidate]
                        if item and item.category == category then ordinal = ordinal + 1 end
                    end
                    shortcutPage = math.floor((ordinal - 1) / #panel.shortcutRows) + 1
                end
            elseif mode == "group" then S.SetGroup(category, id, option.value)
            elseif mode == "shortcut" and Settings().shortcuts[id] then
                Settings().shortcuts[id].filter = option.value
            end
            panel.filterMenu:Hide()
            Refresh()
        end)
        panel.filterMenu.entries[i] = entry
    end
    panel.OpenFilterMenu = function(anchor, mode, id)
        local category = selectedCategory
        local options = mode == "shortcut" and FilterOptions(category) or {}
        if mode == "pool" then
            options = { { value = 0, label = "My Picks" } }
            for index, custom in ipairs(Settings()[category].customPools) do
                options[#options + 1] = { value = index, label = custom.name }
            end
        elseif mode ~= "shortcut" then
            for _, group in ipairs(GROUPS[category]) do
                if not (mode == "group" and category == "mount"
                    and (group == "Ground" or group == "Sky" or group == "Aquatic")) then
                    options[#options + 1] = { value = group, label = mode == "group" and group == "Any" and "Auto-Detect" or group }
                end
            end
            if mode == "group" then
                options[#options + 1] = { value = "__itemShortcut", label = "+ Shortcut for this item" }
            end
        end
        local menu = panel.filterMenu
        menu.mode, menu.category, menu.id = mode, category, id
        local columns = #options > 16 and 3 or #options > 8 and 2 or 1
        local rows = math.ceil(#options / columns)
        menu:SetSize(columns * 184, rows * 25 + 10)
        menu:ClearAllPoints()
        if mode == "group" then
            menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
        elseif mode == "shortcut" and anchor.menuAbove then
            menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -164, 4)
        elseif mode == "shortcut" then
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -164, -4)
        else menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4) end
        for i, entry in ipairs(menu.entries) do
            entry.option = options[i]
            entry:SetShown(options[i] ~= nil)
            if options[i] then
                local column = math.floor((i - 1) / rows)
                local row = (i - 1) % rows
                entry:ClearAllPoints()
                entry:SetPoint("TOPLEFT", 5 + column * 184, -5 - row * 25)
                entry.text:SetText(options[i].label)
            end
        end
        menu:Show()
    end
    panel.filterMenu:Hide()
    panel.keysPage:Hide()
    panel:Hide()
end

Refresh = function()
    if not panel or not panel:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local onKeys = viewMode == "shortcuts"
    for _, widget in ipairs(panel.collectionWidgets) do widget:SetShown(not onKeys) end
    panel.keysPage:SetShown(onKeys)
    for category, tab in pairs(panel.tabs) do
        local active = category == selectedCategory
        tab:SetBackdropBorderColor(active and GREEN[1] or 1, active and GREEN[2] or 1,
            active and GREEN[3] or 1, active and 0.8 or 0.18)
    end
    if onKeys then
        panel.keysTitle:SetText(LABELS[selectedCategory] .. " shortcuts")
        for i, row in ipairs(panel.bindingRows) do
            row.label:SetText(i == 1 and "Open Random Summoner" or ("Random " .. LABELS[selectedCategory]))
            local command = i == 1 and "WH_RANDOM_SUMMONER" or bindingCommands[selectedCategory]
            for slot, keyButton in ipairs(row.keys) do
                keyButton.text:SetText(bindCapture == command and bindCaptureSlot == slot
                    and "Press a key..." or BindLabel(command, slot))
            end
        end
        local indices = {}
        for index = 1, SHORTCUT_COUNT do
            local item = Settings().shortcuts[index]
            if item and item.category == selectedCategory then indices[#indices + 1] = index end
        end
        local pages = math.max(1, math.ceil(#indices / #panel.shortcutRows))
        shortcutPage = math.min(shortcutPage, pages)
        for i, row in ipairs(panel.shortcutRows) do
            local index = indices[(shortcutPage - 1) * #panel.shortcutRows + i]
            row.index = index
            row:SetShown(index ~= nil)
            if index then
                local item = Settings().shortcuts[index]
                if not row.name:HasFocus() then row.name:SetText(item.name or "") end
                row.filter.text:SetText(FilterLabel(selectedCategory, item.filter, item))
                for slot, keyButton in ipairs(row.keys) do
                    local command = ShortcutCommand(index)
                    keyButton.text:SetText(bindCapture == command and bindCaptureSlot == slot
                        and "Press a key..." or BindLabel(command, slot))
                end
            end
        end
        panel.shortcutPrevious:SetEnabled(shortcutPage > 1)
        panel.shortcutNext:SetEnabled(shortcutPage < pages)
        panel.shortcutPageText:SetText(shortcutPage .. "/" .. pages)
        panel.launchToggle.text:SetText(Settings().showLauncher and "Shown (click to hide)" or "Hidden (click to show)")
        return
    end
    panel.action:SetShown(selectedCategory == "pet")
    panel.mountAction:SetShown(selectedCategory == "mount")
    panel.toyAction:SetShown(selectedCategory == "toy")
    currentRows = S.Collect(selectedCategory)
    currentCounts = S.Counts(selectedCategory, currentRows)
    local settings = Settings()[selectedCategory]
    local custom = settings.customPools[activePool[selectedCategory]]
    panel.poolSelect.text:SetText(custom and custom.name or "My Picks")
    panel.poolEnabled:SetShown(custom ~= nil)
    panel.poolDelete:SetShown(custom ~= nil)
    if custom then
        panel.poolEnabled.text:SetText(custom.enabled and "Active" or "Off")
        panel.poolEnabled:SetBackdropBorderColor(custom.enabled and GREEN[1] or 1,
            custom.enabled and GREEN[2] or 1, custom.enabled and GREEN[3] or 1, custom.enabled and 0.7 or 0.15)
    end
    panel.pickTitle:SetText(custom and "CUSTOM POOL" or "COLLECTION")
    panel.pickHelp:SetText(custom and "Click to add to this pool. Weight: 0 off, 4 frequent."
        or "Click to add to My Picks. Weight: 0 off, 4 frequent.")
    local modeName = settings.launcherMode == "favorites" and "Favorites" or "Rated Pool"
    panel.summary:SetText(modeName .. "  |  " .. currentCounts.selected .. " in pool  |  "
        .. #currentRows .. (selectedCategory == "toy" and " visible toys" or " collected"))
    panel.filterButton.text:SetText("Show: " .. browseFilter[selectedCategory])
    panel.searchPlaceholder:SetText("Search " .. LABELS[selectedCategory]:lower() .. "...")
    for i, button in ipairs(panel.packs) do
        local def = PACKS[selectedCategory][i]
        button.def = def
        button:SetShown(def ~= nil)
        if def then
            local count = currentCounts[def.key] or 0
            button.text:SetText((settings.packs[def.key] and "|cff0dd19e[x]|r " or "[ ] ") .. def.label .. " (" .. count .. ")")
            button:SetBackdropBorderColor(settings.packs[def.key] and GREEN[1] or 1,
                settings.packs[def.key] and GREEN[2] or 1,
                settings.packs[def.key] and GREEN[3] or 1,
                settings.packs[def.key] and 0.55 or 0.12)
        end
    end
    local filtered = {}
    local query = SafeText(search)
    for _, row in ipairs(currentRows) do
        if S.MatchesGroup(selectedCategory, row, browseFilter[selectedCategory])
            and (query == "" or SafeText(row.name):find(query, 1, true)) then
            filtered[#filtered + 1] = row
        end
    end
    local pages = math.max(1, math.ceil(#filtered / rowsPerPage))
    page = math.min(page, pages)
    for i, button in ipairs(panel.listRows) do
        local row = filtered[(page - 1) * rowsPerPage + i]
        button.item = row
        button:SetShown(row ~= nil)
        if row then
            button.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local quality = QUALITY[row.quality] or QUALITY[0]
            button.iconBorder:SetBackdropBorderColor(quality[1], quality[2], quality[3], 0.92)
            local picked = custom and custom.members[row.id] or settings.picks[row.id]
            button.text:SetText((picked and "|cff0dd19e[x]|r " or "[ ] ") .. row.name)
            button.groupButton.text:SetText(S.GetGroup(selectedCategory, row))
            button.groupButton:SetShown(selectedCategory ~= "mount")
            button.utility:SetShown(selectedCategory == "mount")
            for index, tag in ipairs(TRAVEL_TAGS) do
                local travel = button.travelButtons[index]
                travel:SetShown(selectedCategory == "mount")
                if selectedCategory == "mount" then
                    local on = S.GetTravelTag(row.id, row, tag)
                    travel.icon:SetDesaturated(not on)
                    travel.icon:SetAlpha(on and 1 or 0.36)
                    travel:SetBackdropBorderColor(on and GREEN[1] or 1, on and GREEN[2] or 1,
                        on and GREEN[3] or 1, on and 0.7 or 0.14)
                end
            end
            local chosenRating = S.GetRating(selectedCategory, row.id)
            button.weightSelect:ClearAllPoints()
            button.weightSelect:SetPoint("CENTER", button.weight, "LEFT", 12 + chosenRating * 21, 0)
            button.weightValue:SetText(tostring(chosenRating))
            button.weightFill:SetShown(chosenRating > 0)
            button.weightFill:SetWidth(chosenRating * 21)
            button.weight:SetBackdropBorderColor(chosenRating > 0 and GREEN[1] or 1,
                chosenRating > 0 and GREEN[2] or 1, chosenRating > 0 and GREEN[3] or 1,
                chosenRating > 0 and 0.42 or 0.16)
        end
    end
    panel.previous:SetEnabled(page > 1)
    panel.next:SetEnabled(page < pages)
    panel.pageText:SetText(page .. "/" .. pages)
    panel.action.text:SetText("Random Pet")
    local empty = {}
    for _, def in ipairs(PACKS[selectedCategory]) do
        if def.key ~= "all" and def.key ~= "picked" and def.key ~= "favorite"
            and (currentCounts[def.key] or 0) == 0 then empty[#empty + 1] = def.label end
    end
    panel.hint:SetText(#empty > 0 and "Empty Auto Packs May Lack Source Tags. Use A Custom Pool Above."
        or "Auto Packs Use Source Tags. Add Missing Items To A Custom Pool Above.")
end

function S.Toggle(category, mode)
    if InCombatLockdown and InCombatLockdown() then
        Message("Open Random Summoner after combat.")
        return
    end
    EnsurePanel()
    if panel:IsShown() and not category and not mode then panel:Hide(); return end
    selectedCategory = LABELS[category] and category or selectedCategory or "mount"
    viewMode = mode or viewMode or "collection"
    panel.filterMenu:Hide()
    page = page or 1
    search = search or ""
    panel:Show()
    Refresh()
    RefreshLauncher()
end

RefreshLauncher = function()
    if not launcher then return end
    launcher:SetShown(Settings().showLauncher)
    for category, button in pairs(launcher.categoryButtons or {}) do
        local mode = Settings()[category].launcherMode
        local active = panel and panel:IsShown() and selectedCategory == category
        button:SetBackdropBorderColor(active and GREEN[1] or 0.48, active and GREEN[2] or 0.5,
            active and GREEN[3] or 0.52, active and 0.85 or 0.35)
        if button.modeLine then
            if mode == "favorites" then button.modeLine:SetColorTexture(1, 0.7, 0.2, 1)
            else button.modeLine:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1) end
        end
    end
end

function S.SetLauncherShown(value)
    Settings().showLauncher = value == true
    RefreshLauncher()
end

local function EnsureLauncher()
    if launcher then return end
    launcher = CreateFrame("Frame", "WaffleHouseRandomLauncher", UIParent, "BackdropTemplate")
    launcher:SetSize(130, 44)
    Surface(launcher, 0.047, 0.055, 0.064)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    local position = Settings().position
    launcher:SetPoint("CENTER", UIParent, "CENTER", position and position.x or 240, position and position.y or -150)
    local function StopDrag(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        Settings().position = { x = x - ux, y = y - uy }
    end
    launcher.categoryButtons = {}
    for i, category in ipairs(CATEGORIES) do
        local tile = ArtButton(launcher, CATEGORY_ART[category], 36, function(_, mouseButton)
            if mouseButton == "RightButton" then
                if IsShiftKeyDown and IsShiftKeyDown() then S.Toggle(category, "shortcuts")
                else
                    local pool = Settings()[category]
                    pool.launcherMode = pool.launcherMode == "rated" and "favorites" or "rated"
                    RefreshLauncher()
                    if panel and panel:IsShown() then Refresh() end
                end
            else
                S.Toggle(category, "collection")
                RefreshLauncher()
            end
        end)
        tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tile:SetPoint("TOPLEFT", 13 + (i - 1) * 38, -4)
        tile.modeLine = tile:CreateTexture(nil, "OVERLAY")
        tile.modeLine:SetPoint("BOTTOMLEFT", 5, 2)
        tile.modeLine:SetPoint("BOTTOMRIGHT", -5, 2)
        tile.modeLine:SetHeight(2)
        tile:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(LABELS[category])
                GameTooltip:AddLine("Left: Open " .. LABELS[category] .. "  |  Right: Toggle Rated/Favorites", 0.7, 0.75, 0.77)
                GameTooltip:AddLine("Shift-Right: Shortcuts  |  Shift-Drag: Move", 0.7, 0.75, 0.77)
                GameTooltip:AddLine("Current: " .. (Settings()[category].launcherMode == "favorites" and "Favorites" or "Rated Pool"), 0.9, 0.8, 0.3)
                GameTooltip:Show()
            end
        end)
        tile:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        tile:RegisterForDrag("LeftButton")
        tile:SetScript("OnDragStart", function()
            if IsShiftKeyDown and IsShiftKeyDown() then launcher:StartMoving() end
        end)
        tile:SetScript("OnDragStop", function() StopDrag(launcher) end)
        launcher.categoryButtons[category] = tile
    end
    local grip = Button(launcher, "", 8, 36, function() end)
    grip.text:Hide()
    grip:SetPoint("TOPLEFT", 2, -4)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() launcher:StartMoving() end)
    grip:SetScript("OnDragStop", function() StopDrag(launcher) end)
    local gripMark = grip:CreateTexture(nil, "ARTWORK")
    gripMark:SetColorTexture(0.42, 0.47, 0.49, 0.6)
    gripMark:SetPoint("CENTER")
    gripMark:SetSize(2, 18)
    launcher:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Random Summoner")
        GameTooltip:AddLine("Choose Mounts, Pets, or Toys. Drag the left grip to move.", 0.7, 0.75, 0.77, true)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    RefreshLauncher()
end

local function EnsureToyKeyButton()
    if S.toyKeyButton then return end
    local button = MakeToyButton("WaffleHouseRandomToyKeyButton", UIParent)
    button:SetSize(1, 1)
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    button:SetAlpha(0)
    S.toyKeyButton = button
    local mountButton = MakeMountButton("WaffleHouseRandomMountKeyButton", UIParent)
    mountButton:SetSize(1, 1)
    mountButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    mountButton:SetAlpha(0)
    S.mountKeyButton = mountButton
    S.shortcutButtons = {}
    for index = 1, SHORTCUT_COUNT do
        S.shortcutButtons[index] = MakeShortcutButton(index)
    end
end

local function MigrateMountBinding()
    if not (GetBindingKey and SetBinding) then return end
    local first, second = GetBindingKey("WH_RANDOM_MOUNT")
    if not first and not second then return end
    local target = bindingCommands.mount
    local changed = false
    if first and SetBinding(first, target) then changed = true end
    if second and SetBinding(second, target) then changed = true end
    if changed and SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
end

SLASH_WAFFLEHOUSERANDOM1 = "/whrandom"
SlashCmdList.WAFFLEHOUSERANDOM = function(input)
    local command = SafeText(input):gsub("^%s+", ""):gsub("%s+$", "")
    if command == "mount" or command == "pet" then
        S.Summon(command)
    elseif command == "toy" then
        selectedCategory = "toy"
        if not panel or not panel:IsShown() then S.Toggle() else Refresh() end
    elseif command == "button" then
        Settings().showLauncher = not Settings().showLauncher
        EnsureLauncher()
        RefreshLauncher()
    else
        S.Toggle()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
events:RegisterEvent("TOYS_UPDATED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        EnsureLauncher()
        EnsureToyKeyButton()
        MigrateMountBinding()
    elseif panel and panel:IsShown() then Refresh() end
end)
