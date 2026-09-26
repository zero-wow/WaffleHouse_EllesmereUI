local _, addon = ...
local unpack = unpack or table.unpack

-- Mounts and pets are read from the full collections. Blizzard only exposes
-- toys by their filtered Toy Box index, so that collection follows its view.
local S = {}
addon.RandomSummoner = S

local CATEGORIES = { "mount", "pet", "toy" }
local LABELS = { mount = "Mounts", pet = "Pets", toy = "Toys" }
local PACKS = {
    mount = {
        { key = "all", label = "All collected" },
        { key = "favorite", label = "Favorites" },
        { key = "store", label = "Store Mounts" },
        { key = "longsub", label = "Long Subscriptions (3/6/12)" },
        { key = "darkmoon", label = "Darkmoon Faire" },
        { key = "picked", label = "My Picks" },
    },
    pet = {
        { key = "all", label = "All collected" },
        { key = "favorite", label = "Favorites" },
        { key = "store", label = "Store Pets" },
        { key = "darkmoon", label = "Darkmoon Faire" },
        { key = "picked", label = "My Picks" },
    },
    toy = {
        { key = "all", label = "All collected" },
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
    end
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
            local name, _, icon, _, usable, sourceType, favorite, _, _, hidden, collected = C_MountJournal.GetMountInfoByID(id)
            if collected and name and not IsSecret(name) then
                local source = C_MountJournal.GetMountInfoExtraByID and select(3, C_MountJournal.GetMountInfoExtraByID(id))
                local packs = DetectSourcePacks(source)
                if storeSource ~= nil and sourceType == storeSource then packs.store = true end
                rows[#rows + 1] = { id = id, name = name, icon = icon, usable = usable and not hidden,
                    packs = packs, favorite = favorite == true }
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
                    row = { id = id, guid = guid, name = info.name or info.customName or ("Pet " .. id),
                        icon = info.icon, favorite = info.isFavorite == true, packs = packs, usable = true }
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
            local _, name, icon, favorite = C_ToyBox.GetToyInfo(id)
            if name and not IsSecret(name) then
                rows[#rows + 1] = { id = id, name = name, icon = icon, favorite = favorite == true,
                    usable = not C_ToyBox.IsToyUsable or C_ToyBox.IsToyUsable(id), packs = {} }
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
    return false
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
            if row.usable then counts.usable = counts.usable + 1 end
        end
    end
    return counts
end

local lastChoice = {}
function S.Pick(category, rows)
    local eligible = {}
    for _, row in ipairs(rows or S.Collect(category)) do
        if row.usable and S.IsSelected(category, row) then eligible[#eligible + 1] = row end
    end
    if #eligible == 0 then return nil end
    local chosen = eligible[math.random(#eligible)]
    if #eligible > 1 and chosen.id == lastChoice[category] then
        chosen = eligible[(math.random(#eligible - 1) % #eligible) + 1]
        if chosen.id == lastChoice[category] then
            for _, row in ipairs(eligible) do if row.id ~= chosen.id then chosen = row; break end end
        end
    end
    lastChoice[category] = chosen.id
    return chosen
end

local function Message(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r " .. message) end
end

function S.Summon(category)
    if category == "toy" then
        Message("Toys need the Random Toy button in /whrandom or its keybind on the Keys tab.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        Message("Random " .. (LABELS[category] or "collection") .. " is unavailable in combat.")
        return false
    end
    local row = S.Pick(category)
    if not row then
        Message("No usable " .. (LABELS[category] or "items"):lower() .. " in this pool. Open /whrandom to choose a pool.")
        return false
    end
    if category == "mount" and C_MountJournal and C_MountJournal.SummonByID then
        C_MountJournal.SummonByID(row.id)
    elseif category == "pet" and C_PetJournal and C_PetJournal.SummonPetByGUID then
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
_G.WaffleHouseRandomSummonerMount = function() S.Summon("mount") end
_G.WaffleHouseRandomSummonerPet = function() S.Summon("pet") end
_G.BINDING_NAME_WH_RANDOM_SUMMONER = "Open Random Summoner"
_G.BINDING_NAME_WH_RANDOM_MOUNT = "Random mount from my pool"
_G.BINDING_NAME_WH_RANDOM_PET = "Random pet from my pool"
_G["BINDING_NAME_CLICK WaffleHouseRandomToyKeyButton:LeftButton"] = "Random toy from my pool"

local WIDTH, HEIGHT, GUTTER = 522, 562, 18
local GREEN = { 0.05, 0.82, 0.62 }
local panel, launcher, selectedCategory, currentRows, currentCounts, page, search
local Refresh, RefreshLauncher
local rowsPerPage = 7
local bindCapture, replaceKey
local bindingCommands = {
    { command = "WH_RANDOM_SUMMONER", label = "Open popup" },
    { command = "WH_RANDOM_MOUNT", label = "Random mount" },
    { command = "WH_RANDOM_PET", label = "Random pet" },
    { command = "CLICK WaffleHouseRandomToyKeyButton:LeftButton", label = "Random toy" },
}

-- UseToy is protected. A real secure click chooses one toy in PreClick,
-- performs the action through Blizzard's secure "toy" handler, then disarms
-- the button. The disarmed button is safe if combat begins before the next key.
function S.PrepareToyButton(button)
    if InCombatLockdown and InCombatLockdown() then return false end
    local choice = S.Pick("toy")
    button:SetAttribute("type", choice and "toy" or nil)
    button:SetAttribute("toy", choice and choice.id or nil)
    if not choice then Message("No usable toys in this pool. Open /whrandom to choose a pool.") end
    return choice ~= nil
end

local function MakeToyButton(name, parent)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
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
    button:SetScript("OnClick", click)
    return button
end

local function BindLabel(command)
    local key = GetBindingKey and GetBindingKey(command)
    return key and (GetBindingText and GetBindingText(key) or key) or "Click to set"
end

local function EndCapture()
    bindCapture, replaceKey = nil, nil
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
    local old = GetBindingKey and GetBindingKey(bindCapture)
    if old then SetBinding(old) end
    if SetBinding(key, bindCapture) then
        if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
        EndCapture()
    else
        panel.keyHint:SetText("That key cannot be assigned. Try another.")
    end
end

local function EnsurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "WaffleHouseRandomSummoner", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
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
    Surface(panel)
    panel:SetScript("OnHide", EndCapture)

    local title = Font(panel, 17, GREEN)
    title:SetPoint("TOPLEFT", GUTTER, -16)
    title:SetText("Random Summoner")
    local subtitle = Font(panel, 10, { 0.62, 0.67, 0.69 })
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Pick pools below, then press a random button or your keybind.")
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", 0, 0)
    drag:SetHeight(48)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local close = Button(panel, "x", 27, 25, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", -GUTTER, -14)

    panel.tabs = {}
    for i, category in ipairs({ "mount", "pet", "toy", "keys" }) do
        local tab = Button(panel, LABELS[category] or "Keys", 113, 29, function()
            selectedCategory, page, search = category, 1, ""
            panel.search:SetText("")
            Refresh()
        end)
        tab:SetPoint("TOPLEFT", GUTTER + (i - 1) * 123, -59)
        panel.tabs[category] = tab
    end

    panel.summary = Font(panel, 11, GREEN)
    panel.summary:SetPoint("TOPLEFT", GUTTER, -99)
    panel.summary:SetWidth(WIDTH - GUTTER * 2)
    local help = Font(panel, 10, { 0.66, 0.7, 0.72 })
    help:SetPoint("TOPLEFT", GUTTER, -117)
    help:SetText("Checked groups are combined. Turn off All collected to narrow the pool.")

    panel.packs = {}
    for i = 1, 8 do
        local x = GUTTER + ((i - 1) % 2) * 244
        local y = -145 - math.floor((i - 1) / 2) * 29
        local button = Button(panel, "", 234, 24, function(self)
            local def = self.def
            if not def then return end
            local packs = Settings()[selectedCategory].packs
            packs[def.key] = not packs[def.key]
            Refresh()
        end)
        button:SetPoint("TOPLEFT", x, y)
        panel.packs[i] = button
    end

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetPoint("TOPLEFT", GUTTER, -264)
    divider:SetSize(WIDTH - GUTTER * 2, 1)
    local pickTitle = Font(panel, 12, GREEN)
    pickTitle:SetPoint("TOPLEFT", GUTTER, -275)
    pickTitle:SetText("MY PICKS")
    local pickHelp = Font(panel, 10, { 0.66, 0.7, 0.72 })
    pickHelp:SetPoint("TOPLEFT", GUTTER + 82, -277)
    pickHelp:SetText("Check items here, then enable My Picks above.")
    panel.search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.search:SetSize(WIDTH - GUTTER * 2 - 16, 24)
    panel.search:SetPoint("TOPLEFT", GUTTER + 8, -297)
    panel.search:SetAutoFocus(false)
    panel.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.search:SetScript("OnTextChanged", function(self)
        search, page = self:GetText() or "", 1
        Refresh()
    end)
    panel.listRows = {}
    for i = 1, rowsPerPage do
        local row = Button(panel, "", WIDTH - GUTTER * 2, 22, function(self)
            if not self.item then return end
            local picks = Settings()[selectedCategory].picks
            picks[self.item.id] = not picks[self.item.id] or nil
            Refresh()
        end)
        row:SetPoint("TOPLEFT", GUTTER, -328 - (i - 1) * 24)
        row.text:SetJustifyH("LEFT")
        panel.listRows[i] = row
    end
    panel.previous = Button(panel, "<", 26, 22, function() page = math.max(1, page - 1); Refresh() end)
    panel.previous:SetPoint("TOPLEFT", GUTTER, -501)
    panel.pageText = Font(panel, 10)
    panel.pageText:SetPoint("LEFT", panel.previous, "RIGHT", 7, 0)
    panel.next = Button(panel, ">", 26, 22, function() page = page + 1; Refresh() end)
    panel.next:SetPoint("LEFT", panel.pageText, "RIGHT", 8, 0)
    panel.action = Button(panel, "Random", 110, 25, function() S.Summon(selectedCategory); Refresh() end)
    panel.action:SetPoint("TOPRIGHT", -GUTTER, -499)
    panel.toyAction = MakeToyButton(nil, panel)
    panel.toyAction:SetSize(110, 25)
    panel.toyAction:SetPoint("TOPRIGHT", -GUTTER, -499)
    Surface(panel.toyAction, 0.09, 0.105, 0.115)
    panel.toyAction.text = Font(panel.toyAction, 11)
    panel.toyAction.text:SetAllPoints()
    panel.toyAction.text:SetJustifyH("CENTER")
    panel.toyAction.text:SetText("Random Toy")
    panel.toyAction:Hide()

    local bindDivider = panel:CreateTexture(nil, "ARTWORK")
    bindDivider:SetColorTexture(1, 1, 1, 0.12)
    bindDivider:SetPoint("TOPLEFT", GUTTER, -529)
    bindDivider:SetSize(WIDTH - GUTTER * 2, 1)
    panel.hint = Font(panel, 10, { 0.67, 0.72, 0.74 })
    panel.hint:SetPoint("TOPLEFT", GUTTER, -535)
    panel.hint:SetWidth(WIDTH - GUTTER * 2)
    panel.hint:SetText("Packs use journal sources. Toys follow your Toy Box filters.")
    panel.collectionWidgets = { panel.summary, help, divider, pickTitle, pickHelp,
        panel.search, panel.previous, panel.pageText, panel.next, panel.action, panel.toyAction,
        bindDivider, panel.hint }
    for _, button in ipairs(panel.packs) do panel.collectionWidgets[#panel.collectionWidgets + 1] = button end
    for _, button in ipairs(panel.listRows) do panel.collectionWidgets[#panel.collectionWidgets + 1] = button end

    panel.keysPage = CreateFrame("Frame", nil, panel)
    panel.keysPage:SetPoint("TOPLEFT", GUTTER, -100)
    panel.keysPage:SetSize(WIDTH - GUTTER * 2, 420)
    local keysTitle = Font(panel.keysPage, 13, GREEN)
    keysTitle:SetPoint("TOPLEFT", 0, 0)
    keysTitle:SetText("YOUR SHORTCUT KEYS")
    local keysHelp = Font(panel.keysPage, 10, { 0.68, 0.72, 0.74 })
    keysHelp:SetPoint("TOPLEFT", 0, -25)
    keysHelp:SetText("Click Set, then press the key you want. Esc cancels.")
    panel.bindingRows = {}
    for i, binding in ipairs(bindingCommands) do
        local row = CreateFrame("Frame", nil, panel.keysPage)
        row:SetPoint("TOPLEFT", 0, -65 - (i - 1) * 48)
        row:SetSize(WIDTH - GUTTER * 2, 40)
        local label = Font(row, 11)
        label:SetPoint("LEFT", 3, 0)
        label:SetText(binding.label)
        local set
        set = Button(row, "Click to set", 142, 30, function()
            if InCombatLockdown and InCombatLockdown() then
                panel.keyHint:SetText("Keys cannot be changed in combat.")
                return
            end
            bindCapture, replaceKey = binding.command, nil
            panel:EnableKeyboard(true)
            panel.keyHint:SetText("Press a key for " .. binding.label .. ". Esc cancels.")
            set.text:SetText("Press a key...")
        end)
        set:SetPoint("RIGHT", -43, 0)
        local clear = Button(row, "x", 30, 30, function()
            if InCombatLockdown and InCombatLockdown() then return end
            local key = GetBindingKey and GetBindingKey(binding.command)
            if key and SetBinding then
                SetBinding(key)
                if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 2) end
            end
            Refresh()
        end)
        clear:SetPoint("RIGHT", -3, 0)
        panel.bindingRows[i] = { set = set, clear = clear, command = binding.command }
    end
    local launchTitle = Font(panel.keysPage, 11)
    launchTitle:SetPoint("TOPLEFT", 3, -278)
    launchTitle:SetText("Small screen button")
    panel.launchToggle = Button(panel.keysPage, "", 160, 30, function()
        Settings().showLauncher = not Settings().showLauncher
        RefreshLauncher()
        Refresh()
    end)
    panel.launchToggle:SetPoint("TOPRIGHT", -43, -270)
    panel.keyHint = Font(panel.keysPage, 10, { 0.68, 0.72, 0.74 })
    panel.keyHint:SetPoint("TOPLEFT", 3, -339)
    panel.keyHint:SetWidth(WIDTH - GUTTER * 2 - 6)
    panel.keyHint:SetText("You can also use /whrandom, /whrandom mount, pet, or toy.")
    panel.keysPage:Hide()
    panel:Hide()
end

Refresh = function()
    if not panel or not panel:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local onKeys = selectedCategory == "keys"
    for _, widget in ipairs(panel.collectionWidgets) do widget:SetShown(not onKeys) end
    panel.keysPage:SetShown(onKeys)
    for category, tab in pairs(panel.tabs) do
        local active = category == selectedCategory
        tab:SetBackdropBorderColor(active and GREEN[1] or 1, active and GREEN[2] or 1,
            active and GREEN[3] or 1, active and 0.8 or 0.18)
    end
    if onKeys then
        for _, row in ipairs(panel.bindingRows) do
            row.set.text:SetText(bindCapture == row.command and "Press a key..." or BindLabel(row.command))
        end
        panel.launchToggle.text:SetText(Settings().showLauncher and "Shown (click to hide)" or "Hidden (click to show)")
        return
    end
    panel.action:SetShown(selectedCategory ~= "toy")
    panel.toyAction:SetShown(selectedCategory == "toy")
    currentRows = S.Collect(selectedCategory)
    currentCounts = S.Counts(selectedCategory, currentRows)
    local settings = Settings()[selectedCategory]
    panel.summary:SetText(currentCounts.selected .. " in pool  |  " .. currentCounts.usable .. " usable now  |  "
        .. #currentRows .. (selectedCategory == "toy" and " visible toys" or " collected"))
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
        if query == "" or SafeText(row.name):find(query, 1, true) then filtered[#filtered + 1] = row end
    end
    local pages = math.max(1, math.ceil(#filtered / rowsPerPage))
    page = math.min(page, pages)
    for i, button in ipairs(panel.listRows) do
        local row = filtered[(page - 1) * rowsPerPage + i]
        button.item = row
        button:SetShown(row ~= nil)
        if row then
            button.text:SetText((settings.picks[row.id] and "|cff0dd19e[x]|r " or "[ ] ") .. row.name)
        end
    end
    panel.previous:SetEnabled(page > 1)
    panel.next:SetEnabled(page < pages)
    panel.pageText:SetText(page .. "/" .. pages)
    panel.action.text:SetText("Random " .. LABELS[selectedCategory]:sub(1, -2))
end

function S.Toggle()
    if InCombatLockdown and InCombatLockdown() then
        Message("Open Random Summoner after combat.")
        return
    end
    EnsurePanel()
    if panel:IsShown() then panel:Hide(); return end
    selectedCategory = selectedCategory or "mount"
    page = page or 1
    search = search or ""
    panel:Show()
    Refresh()
end

RefreshLauncher = function()
    if not launcher then return end
    launcher:SetShown(Settings().showLauncher)
end

function S.SetLauncherShown(value)
    Settings().showLauncher = value == true
    RefreshLauncher()
end

local function EnsureLauncher()
    if launcher then return end
    launcher = Button(UIParent, "", 120, 38, S.Toggle)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    local position = Settings().position
    launcher:SetPoint("CENTER", UIParent, "CENTER", position and position.x or 240, position and position.y or -150)
    launcher.text:Hide()
    launcher:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.55)

    -- One high-contrast mark stays legible at normal UI scale; the labels
    -- explain the action without asking players to decode category initials.
    local dieBorder = launcher:CreateTexture(nil, "ARTWORK")
    dieBorder:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.9)
    dieBorder:SetPoint("TOPLEFT", 7, -6)
    dieBorder:SetSize(26, 26)
    local dieFace = launcher:CreateTexture(nil, "ARTWORK")
    dieFace:SetColorTexture(0.045, 0.105, 0.10, 1)
    dieFace:SetPoint("TOPLEFT", 8, -7)
    dieFace:SetSize(24, 24)
    for _, point in ipairs({ { 12, -11 }, { 25, -11 }, { 18.5, -17.5 }, { 12, -24 }, { 25, -24 } }) do
        local pip = launcher:CreateTexture(nil, "OVERLAY")
        pip:SetColorTexture(0.86, 1, 0.95, 1)
        pip:SetPoint("CENTER", launcher, "TOPLEFT", point[1], point[2])
        pip:SetSize(3, 3)
    end
    local randomLabel = Font(launcher, 10, GREEN)
    randomLabel:SetPoint("TOPLEFT", 40, -7)
    randomLabel:SetSize(72, 11)
    randomLabel:SetText("RANDOM")
    local summonerLabel = Font(launcher, 10, { 0.94, 0.96, 0.95 })
    summonerLabel:SetPoint("TOPLEFT", 40, -19)
    summonerLabel:SetSize(72, 12)
    summonerLabel:SetText("SUMMONER")
    launcher:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Random Summoner")
        GameTooltip:AddLine("Click to choose random mounts, pets, and toys. Drag to move.", 0.7, 0.75, 0.77, true)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnDragStart", function(self) self:StartMoving() end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        Settings().position = { x = x - ux, y = y - uy }
    end)
    RefreshLauncher()
end

local function EnsureToyKeyButton()
    if S.toyKeyButton then return end
    local button = MakeToyButton("WaffleHouseRandomToyKeyButton", UIParent)
    button:SetSize(1, 1)
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    button:SetAlpha(0)
    S.toyKeyButton = button
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
    if event == "PLAYER_LOGIN" then EnsureLauncher(); EnsureToyKeyButton()
    elseif panel and panel:IsShown() then Refresh() end
end)
