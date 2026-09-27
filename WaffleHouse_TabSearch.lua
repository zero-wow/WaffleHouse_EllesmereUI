local _, addon = ...

-- Search destinations are the visible labels and section names from Waffle
-- House's six options pages. Keep this list beside the UI implementation so
-- unopened pages are searchable without building every options frame.
local CATALOG = {
    { page = "General", terms = "wonderbar databars companion resource cpu cvar nameplate buff", sections = {
        { "DATABARS & COMPANIONS", "Reorder Wonderbar Entries", "Keep Soul-Trader Summoned" },
        { "RESOURCE WATCH", "Warn About High Addon CPU", "CPU Warning Threshold" },
        { "NAMEPLATE CVAR PROTECTOR", "Protect Selected Nameplate CVars", "Apply All Targets Now",
            "Friendly NPCs Target", "Protect Friendly NPCs", "Friendly Guardians Target",
            "Protect Friendly Guardians", "Friendly Minions Target", "Protect Friendly Minions",
            "Friendly Pets Target", "Protect Friendly Pets" },
        { "SKINNING", "Skin Zygor Guide Pointer" },
        { "BUFF FRAME", "Position with Blizzard Edit Mode" },
    } },
    { page = "Adventure", terms = "mount flight skyriding random transmog delve curio pet toy", sections = {
        { "MOUNTING", "Auto Mount Out of Combat", "Mount Picker" },
        { "AUTO-MOUNT LOCATIONS", "Allow Open World", "Allow Dungeons", "Allow Raids",
            "Allow Delves", "Allow Other Scenarios", "Allow Battlegrounds & Arenas",
            "Allow Housing", "Allow Other Instances" },
        { "RANDOM SUMMONER", "Show Random Summoner Button", "Open Pools & Keys" },
        { "FLIGHT STYLE INDICATOR", "Show Flight Style Indicator", "Indicator Layout", "Emblem Size",
            "Compact Size", "Skyriding Charges", "Cast Progress", "Compact Panel Theme" },
        { "RANDOM TRANSMOG", "Outfit Change Reminder", "Remind Every", "Show Instant Outfit Button" },
        { "DELVE COMPANION", "Show Curio Helper", "Mute Valeera Voice Lines" },
    } },
    { page = "Automation", terms = "quest dialogue npc cinematic vendor sell repair ethereal", sections = {
        { "AUTOMATION CONTROLS", "Pause Key", "Reverse Mode", "Where to Automate" },
        { "ETHEREAL TOOLS", "Auto Choose Ethereal Tools", "Ethereal Tool Preference" },
        { "QUESTS & NPC DIALOGUE", "Auto Accept Quests", "Auto Complete Quests",
            "Skip Single-Option Dialogue", "Select Campaign Skips", "Don't Accept Low-Level Quests",
            "Skip Warband-Completed Quests" },
        { "REMEMBERED NPC CHOICES", "Remember NPC Choices", "Current NPC Route" },
        { "CINEMATICS & MERCHANTS", "Skip Cinematics", "Auto Sell Junk", "Auto Repair", "Repair Source" },
    } },
    { page = "Bags", terms = "bag inventory bank warband guild freeze frozen sort assistant", sections = {
        { "FROZEN SLOTS", "Freeze Bag Slots", "Freeze Modifier", "Frozen Marker" },
        { "MANAGEMENT", "Frozen Slots" },
        { "BAG ASSISTANT", "Show Bag Assistant", "Include Guild Bank" },
    } },
    { page = "Item Queue", terms = "queue item use decor housing pinned banned", sections = {
        { "QUEUE BEHAVIOR", "Enable Item Queue", "Hide Completed Items", "Hide Queue in Combat" },
        { "ITEM USE ORDER", "Auto Sort" },
        { "CATEGORIES" },
        { "HOUSING DECOR", "Show Already Owned Decor" },
        { "ITEM EXCEPTIONS", "Pinned Item IDs", "Banned Item IDs" },
        { "QUEUE TOOLS", "Bag Queue Audit" },
    } },
    { page = "Vendor", terms = "merchant currency price cost shopping list interact known renown", sections = {
        { "CURRENCY LEGEND", "Legend Display", "Alternating Currency Rows", "Filter Selected Currency",
            "Only Affordable Items", "Only Saved Vendor Items", "Vendor Tooltip Details",
            "Hide Known Vendor Items", "Hide Renown-Locked Items" },
        { "ITEM VIEW", "Vendor Item View", "Alternating Item Rows", "Show Rarity Column" },
        { "INTERACT KEY", "Ignore In Combat", "Ignore Out of Combat" },
        { "IGNORED VENDOR NPCS", "Ignored Vendor NPCs" },
        { "SHOPPING LIST & NOTES", "Saved Vendor Items" },
    } },
}

local Search = {}
addon.TabSearch = Search
local MODULE = "WaffleHouse_EllesmereUI"
local MAX_RESULTS = 8
local entries = {}
local seen = {}
local function AddEntry(entry)
    local key = entry.page .. "\031" .. (entry.section or "") .. "\031" .. entry.label
    if seen[key] then return end
    seen[key] = true
    entries[#entries + 1] = entry
end
for _, page in ipairs(CATALOG) do
    AddEntry({ page = page.page, label = page.page, terms = page.terms, kind = "page" })
    for _, section in ipairs(page.sections) do
        AddEntry({ page = page.page, section = section[1], label = section[1], kind = "section" })
        for i = 2, #section do
            AddEntry({ page = page.page, section = section[1], label = section[i], kind = "feature" })
        end
    end
end

function Search.AddDiscovered(label, labelLoc, tooltip, moduleFolder, page, sectionName, isSection)
    if moduleFolder ~= MODULE or type(label) ~= "string" or type(page) ~= "string" then return end
    AddEntry({ page = page, section = isSection and label or sectionName, label = label,
        localized = labelLoc, terms = tooltip, kind = isSection and "section" or "feature" })
end

local function Normalize(value)
    return (type(value) == "string" and value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function ContainsWords(haystack, query)
    for word in query:gmatch("%S+") do
        if not haystack:find(word, 1, true) then return false end
    end
    return true
end

function Search.Find(query)
    query = Normalize(query)
    if query == "" then return {} end
    local found = {}
    for _, entry in ipairs(entries) do
        local label = Normalize(entry.label)
        local section = Normalize(entry.section)
        local page = Normalize(entry.page)
        local terms = Normalize(entry.terms)
        local localized = Normalize(entry.localized)
        local score
        if label == query then score = 100
        elseif label:sub(1, #query) == query then score = 85
        elseif label:find(query, 1, true) then score = 70
        elseif ContainsWords(label, query) then score = 60
        elseif localized ~= "" and ContainsWords(localized, query) then score = 55
        elseif entry.kind == "page" and ContainsWords(terms, query) then score = 35
        elseif entry.kind == "feature" and ContainsWords(section, query) then score = 22
        elseif entry.kind == "feature" and terms ~= "" and ContainsWords(terms, query) then score = 18
        elseif entry.kind == "section" and ContainsWords(page, query) then score = 15 end
        if score then found[#found + 1] = { entry = entry, score = score } end
    end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.entry.page ~= b.entry.page then return a.entry.page < b.entry.page end
        return a.entry.label < b.entry.label
    end)
    local results = {}
    for i = 1, math.min(#found, MAX_RESULTS) do results[i] = found[i].entry end
    return results
end

function Search.Navigate(entry, ui)
    ui = ui or EllesmereUI
    if not (entry and ui) then return end
    if entry.section and ui.NavigateToElementSettings then
        ui:NavigateToElementSettings(MODULE, entry.page, entry.section, nil,
            entry.kind == "feature" and entry.label or nil)
    elseif ui.SelectModule and ui.SelectPage then
        ui:SelectModule(MODULE)
        ui:SelectPage(entry.page)
    end
end

local frame, edit, placeholder, clear, popup, resultRows, currentResults, selected
currentResults, selected = {}, 1
local function UpdateResults()
    if not edit then return end
    local query = edit:GetText() or ""
    placeholder:SetShown(query == "")
    clear:SetShown(query ~= "")
    currentResults = Search.Find(query)
    selected = 1
    for i, row in ipairs(resultRows) do
        local entry = currentResults[i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.label:SetText(entry.kind == "page" and ("Open " .. entry.page) or entry.label)
            row.context:SetText(entry.kind == "page" and "Waffle House" or
                (entry.page .. "  /  " .. entry.section))
            row.label:SetTextColor(i == selected and 0.05 or 0.94,
                i == selected and 0.82 or 0.97, i == selected and 0.62 or 0.97)
        end
    end
    popup.empty:SetShown(query ~= "" and #currentResults == 0)
    if #currentResults > 0 then
        popup:SetHeight(#currentResults * 35 + 8)
        popup:Show()
    elseif query ~= "" then
        popup:SetHeight(38)
        popup:Show()
    else popup:Hide() end
end

local function OpenSelected()
    local entry = currentResults and currentResults[selected]
    if not entry then return end
    edit:SetText("")
    edit:ClearFocus()
    popup:Hide()
    Search.Navigate(entry)
end

local function MakeFont(parent, size, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont((EllesmereUI and EllesmereUI.EXPRESSWAY) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    text:SetTextColor(r, g, b)
    text:SetWordWrap(false)
    text:SetJustifyH("LEFT")
    return text
end

local function BuildUI(bar)
    if frame then return end
    frame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    frame:SetSize(230, 28)
    frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -10, 8)
    frame:SetFrameLevel(bar:GetFrameLevel() + 3)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.085, 0.105, 0.115, 0.95)
    frame:SetBackdropBorderColor(0.45, 0.52, 0.54, 0.34)
    bar._waffleSearchFrame = frame

    edit = CreateFrame("EditBox", nil, frame)
    edit:SetAllPoints()
    edit:SetAutoFocus(false)
    edit:SetFont((EllesmereUI and EllesmereUI.EXPRESSWAY) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    edit:SetTextColor(0.95, 0.97, 0.97)
    edit:SetTextInsets(10, 27, 0, 0)
    edit:SetMaxLetters(50)
    placeholder = MakeFont(frame, 11, 0.5, 0.56, 0.58)
    placeholder:SetPoint("LEFT", frame, "LEFT", 10, 0)
    placeholder:SetText("Search Waffle House Features...")
    clear = CreateFrame("Button", nil, frame)
    clear:SetSize(21, 21)
    clear:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    clear:SetFrameLevel(edit:GetFrameLevel() + 1)
    clear.label = MakeFont(clear, 14, 0.72, 0.76, 0.77)
    clear.label:SetPoint("CENTER")
    clear.label:SetText("x")
    clear:SetScript("OnClick", function() edit:SetText(""); edit:ClearFocus() end)
    clear:Hide()

    popup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    popup:SetWidth(360)
    popup:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -10, -4)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(220)
    popup:SetClampedToScreen(true)
    popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    popup:SetBackdropColor(0.065, 0.078, 0.085, 0.98)
    popup:SetBackdropBorderColor(0.45, 0.52, 0.54, 0.38)
    popup:Hide()
    resultRows = {}
    for i = 1, MAX_RESULTS do
        local row = CreateFrame("Button", nil, popup)
        row:SetSize(350, 33)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 5, -4 - (i - 1) * 35)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(0.05, 0.82, 0.62, 0.13)
        row.label = MakeFont(row, 12, 0.94, 0.97, 0.97)
        row.label:SetPoint("TOPLEFT", 7, -3)
        row.label:SetWidth(334)
        row.context = MakeFont(row, 10, 0.43, 0.77, 0.69)
        row.context:SetPoint("TOPLEFT", 7, -18)
        row.context:SetWidth(334)
        row:SetScript("OnClick", function(self)
            for index, entry in ipairs(currentResults or {}) do
                if entry == self.entry then selected = index; break end
            end
            OpenSelected()
        end)
        resultRows[i] = row
    end
    popup.empty = MakeFont(popup, 11, 0.67, 0.72, 0.73)
    popup.empty:SetPoint("LEFT", popup, "LEFT", 12, 0)
    popup.empty:SetText("No matching Waffle House features")
    popup.empty:Hide()
    local clickOff = CreateFrame("Frame")
    clickOff:SetScript("OnEvent", function()
        if popup:IsShown() and not popup:IsMouseOver() and not frame:IsMouseOver() then popup:Hide() end
    end)
    popup:SetScript("OnShow", function() clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    popup:SetScript("OnHide", function() clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    edit:SetScript("OnTextChanged", UpdateResults)
    edit:SetScript("OnEditFocusGained", function() frame:SetBackdropBorderColor(0.05, 0.82, 0.62, 0.72) end)
    edit:SetScript("OnEditFocusLost", function() frame:SetBackdropBorderColor(0.45, 0.52, 0.54, 0.34) end)
    edit:SetScript("OnEnterPressed", OpenSelected)
    edit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    edit:SetScript("OnArrowPressed", function(_, key)
        if #currentResults == 0 then return end
        selected = selected + (key == "UP" and -1 or 1)
        if selected < 1 then selected = #currentResults end
        if selected > #currentResults then selected = 1 end
        for i, row in ipairs(resultRows) do
            row.label:SetTextColor(i == selected and 0.05 or 0.94,
                i == selected and 0.82 or 0.97, i == selected and 0.62 or 0.97)
        end
    end)
end

function addon.InstallTabSearch()
    if addon._waffleTabSearchHooked or not (EllesmereUI and EllesmereUI.SelectModule and hooksecurefunc) then return end
    if EllesmereUI._RegisterSearchEntry then
        hooksecurefunc(EllesmereUI, "_RegisterSearchEntry", function(label, labelLoc, tooltip,
            moduleFolder, page, sectionName, _, _, isSection)
            Search.AddDiscovered(label, labelLoc, tooltip, moduleFolder, page, sectionName, isSection)
        end)
    end
    hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
        local bar = EllesmereUI._tabBar
        if not bar then return end
        if folderName == MODULE then
            BuildUI(bar)
            frame:Show()
        elseif frame then
            edit:SetText("")
            popup:Hide()
            frame:Hide()
        end
    end)
    addon._waffleTabSearchHooked = true
end
