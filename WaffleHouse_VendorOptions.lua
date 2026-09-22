local _, addon = ...
if not addon then return end

local CONTENT_PAD = 45
local ROW_H = 40
local HEADER_H = 28
local COLUMN_GUTTER = 12
local TABLE_PAD = 14
local KNOWN_VENDOR_NAMES = {
    [27914] = "Ethereal Soul-Trader",
}

local managerOpen
local draftIDs
local draftNames
local addIDText = ""
local addNameText = ""
local messageOwner

local function InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function ValidNPCID(value)
    local id = tonumber(value)
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    return id
end

local function GetSettings()
    return addon.GetSettings and addon.GetSettings() or {}
end

local function CopyIgnoredVendors()
    local ids, names = {}, {}
    local settings = GetSettings()
    for id, enabled in pairs(settings.ignoredInteractVendorNPCs or {}) do
        id = ValidNPCID(id)
        if id and enabled == true then ids[id] = true end
    end
    for id, name in pairs(settings.ignoredInteractVendorNames or {}) do
        id = ValidNPCID(id)
        if id and ids[id] and type(name) == "string" and name ~= "" then names[id] = name end
    end
    return ids, names
end

local function SafeUnitName(unit)
    if type(UnitName) ~= "function" then return nil end
    local name = UnitName(unit)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local function GetVendorID(unit)
    local getter = addon.GetInteractVendorNPCID
    if type(getter) ~= "function" then return nil end
    local id = getter(unit)
    if issecretvalue and issecretvalue(id) then return nil end
    return ValidNPCID(id)
end

local function CacheVisibleNames(ids, names)
    for _, unit in ipairs({ "softinteract", "target", "npc" }) do
        local id = GetVendorID(unit)
        if id and ids[id] then
            local name = SafeUnitName(unit)
            if name and not names[id] then names[id] = name end
        end
    end
end

local function SortedDraftIDs()
    local ids = {}
    for id, enabled in pairs(draftIDs or {}) do
        id = ValidNPCID(id)
        if id and enabled == true then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function DraftName(id)
    return (draftNames and draftNames[id]) or KNOWN_VENDOR_NAMES[id] or "Unknown NPC"
end

local function RebuildPage()
    if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
end

local function ClearMessage(owner)
    if messageOwner ~= owner then return end
    messageOwner = nil
    if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
end

local function ShowMessage(anchor, text)
    if not anchor then return end
    messageOwner = anchor
    if not anchor._waffleVendorMessageLifecycle and anchor.HookScript then
        anchor._waffleVendorMessageLifecycle = true
        anchor:HookScript("OnLeave", function() ClearMessage(anchor) end)
        anchor:HookScript("OnHide", function() ClearMessage(anchor) end)
    end
    if EllesmereUI and EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(anchor, text) end
end

local function BeginDraft()
    if InCombat() then return false end
    if not draftIDs then draftIDs, draftNames = CopyIgnoredVendors() end
    CacheVisibleNames(draftIDs, draftNames)
    managerOpen = true
    return true
end

local function CloseDraft()
    managerOpen = false
    draftIDs, draftNames = nil, nil
    addIDText, addNameText = "", ""
end

local function AddCurrentVendor(anchor)
    if InCombat() then
        ShowMessage(anchor, "Vendor ignore changes are available after combat.")
        return false
    end
    if not BeginDraft() then return false end
    for _, unit in ipairs({ "softinteract", "target", "npc" }) do
        local id = GetVendorID(unit)
        if id then
            draftIDs[id] = true
            local name = SafeUnitName(unit)
            if name and not draftNames[id] then draftNames[id] = name end
            RebuildPage()
            return true
        end
    end
    ShowMessage(anchor, "No NPC soft-interact target is available. Face the vendor, then try again after combat.")
    return false
end

local function AddManualVendor(anchor)
    if InCombat() then
        ShowMessage(anchor, "Vendor ignore changes are available after combat.")
        return false
    end
    if not BeginDraft() then return false end
    local id = ValidNPCID(tostring(addIDText):match("^%s*(%d+)%s*$"))
    if not id then
        ShowMessage(anchor, "Enter a positive numeric NPC ID.")
        return false
    end
    draftIDs[id] = true
    local name = tostring(addNameText or ""):match("^%s*(.-)%s*$")
    if name and name ~= "" then draftNames[id] = name end
    addIDText, addNameText = "", ""
    RebuildPage()
    return true
end

local function RemoveVendor(id)
    if InCombat() or not draftIDs then return end
    draftIDs[id], draftNames[id] = nil, nil
    RebuildPage()
end

local function SaveDraft(anchor)
    if InCombat() then
        ShowMessage(anchor, "Vendor ignore changes are available after combat.")
        return false
    end
    if not draftIDs then return false end
    local ids, names = {}, {}
    for _, id in ipairs(SortedDraftIDs()) do
        ids[id] = true
        local name = draftNames[id]
        if type(name) == "string" and name ~= "" then names[id] = name end
    end
    local settings = GetSettings()
    settings.ignoredInteractVendorNPCs = ids
    settings.ignoredInteractVendorNames = names
    if addon.RefreshIgnoredInteractBinding then addon.RefreshIgnoredInteractBinding() end
    CloseDraft()
    RebuildPage()
    return true
end

local function MakeText(parent, text, size, alpha)
    local label = parent:CreateFontString(nil, "OVERLAY")
    if label.SetFont then
        label:SetFont((EllesmereUI and (EllesmereUI._font or EllesmereUI.EXPRESSWAY)) or "Fonts\\FRIZQT__.TTF", size or 12, "")
    end
    if label.SetTextColor then label:SetTextColor(0.85, 0.86, 0.87, alpha or 1) end
    if label.SetJustifyH then label:SetJustifyH("LEFT") end
    if label.SetWordWrap then label:SetWordWrap(false) end
    if label.SetMaxLines then label:SetMaxLines(1) end
    label:SetText(text)
    return label
end

local function MakeButton(parent, text, width, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 28)
    if EllesmereUI and EllesmereUI.MakeStyledButton and EllesmereUI.RB_COLOURS then
        EllesmereUI.MakeStyledButton(button, text, 12, EllesmereUI.RB_COLOURS, callback)
    else
        local label = MakeText(button, text, 12)
        label:SetPoint("CENTER")
        button:SetScript("OnClick", callback)
    end
    return button
end

local function TableWidth(parent)
    local width = tonumber(parent:GetWidth()) or 1005
    return math.max(1, width - CONTENT_PAD * 2)
end

local function BuildTableHeader(parent, y, width)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, HEADER_H)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
    local contentWidth = math.max(1, width - TABLE_PAD * 2)
    local idWidth = math.min(150, math.max(80, math.floor(contentWidth * 0.22)))
    local removeWidth = math.min(110, math.max(72, math.floor(contentWidth * 0.18)))
    local nameWidth = math.max(20, contentWidth - idWidth - removeWidth - COLUMN_GUTTER * 2)
    frame._waffleColumns = { name = nameWidth, id = idWidth, remove = removeWidth, gutter = COLUMN_GUTTER, total = contentWidth, padding = TABLE_PAD }

    local name = MakeText(frame, "NPC NAME", 11, 0.58)
    name:SetPoint("LEFT", frame, "LEFT", TABLE_PAD, 0)
    name:SetWidth(nameWidth)
    local id = MakeText(frame, "NPC ID", 11, 0.58)
    id:SetPoint("LEFT", name, "RIGHT", COLUMN_GUTTER, 0)
    id:SetWidth(idWidth)
    local remove = MakeText(frame, "REMOVE", 11, 0.58)
    remove:SetPoint("LEFT", id, "RIGHT", COLUMN_GUTTER, 0)
    remove:SetWidth(removeWidth)
    return frame
end

local function BuildVendorRow(parent, y, width, columns, id)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
    row._skipRowDivider = true
    if EllesmereUI and EllesmereUI.RowBg then EllesmereUI.RowBg(row, parent) end
    row._waffleColumns = columns
    row._waffleNPCID = id

    local remove = MakeButton(row, "Remove", columns.remove, function() RemoveVendor(id) end)
    remove._waffleRemoveID = id
    remove:SetPoint("RIGHT", row, "RIGHT", -columns.padding, 0)
    local idLabel = MakeText(row, tostring(id), 12, 0.72)
    idLabel:SetPoint("RIGHT", remove, "LEFT", -COLUMN_GUTTER, 0)
    idLabel:SetWidth(columns.id)
    local name = MakeText(row, DraftName(id), 13)
    name:SetPoint("LEFT", row, "LEFT", columns.padding, 0)
    name:SetPoint("RIGHT", idLabel, "LEFT", -COLUMN_GUTTER, 0)
    return row
end

function addon.BuildIgnoredVendorOptions(parent, y)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return y end
    local h, row
    row, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Ignored Vendor NPCs",
            buttonText = managerOpen and "Managing" or "Manage",
            tooltip = "Manage vendor NPC IDs skipped by the Interact Key. Ethereal Soul-Trader (27914) is included by default.",
            disabled = InCombat,
            disabledTooltip = "Vendor ignore changes are available after combat.",
        },
        {
            type = "labeledButton",
            text = "Current Soft Target",
            buttonText = "Add Vendor",
            tooltip = "Add the current soft-interact vendor to this unsaved draft. Face the vendor first, then Save the list after combat.",
            disabled = InCombat,
            disabledTooltip = "Vendor ignore changes are available after combat.",
        })
    y = y - h
    local manage = row and row._leftRegion and row._leftRegion._control
    if manage then
        manage:SetScript("OnClick", function(self)
            if BeginDraft() then RebuildPage() else ShowMessage(self, "Vendor ignore changes are available after combat.") end
        end)
    end
    local current = row and row._rightRegion and row._rightRegion._control
    if current then current:SetScript("OnClick", function(self) AddCurrentVendor(self) end) end

    if not managerOpen then return y end

    _, h = W:SectionHeader(parent, "IGNORED VENDOR NPCS", y); y = y - h
    CacheVisibleNames(draftIDs, draftNames)
    local width = TableWidth(parent)
    local header = BuildTableHeader(parent, y, width)
    y = y - HEADER_H
    local ids = SortedDraftIDs()
    if #ids == 0 then
        local empty = CreateFrame("Frame", nil, parent)
        empty:SetSize(width, ROW_H)
        empty:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local text = MakeText(empty, "No vendor NPCs in this draft. Add a current vendor or enter an NPC ID below.", 12, 0.62)
        text:SetPoint("LEFT", empty, "LEFT", TABLE_PAD, 0)
        text:SetPoint("RIGHT", empty, "RIGHT", -TABLE_PAD, 0)
        y = y - ROW_H
    else
        for _, id in ipairs(ids) do
            BuildVendorRow(parent, y, width, header._waffleColumns, id)
            y = y - ROW_H
        end
    end

    _, h = W:DualRow(parent, y,
        {
            type = "input",
            text = "NPC ID",
            inputWidth = 110,
            getValue = function() return addIDText end,
            setValue = function(value) addIDText = value or "" end,
            tooltip = "Enter a positive numeric NPC ID.",
        },
        {
            type = "input",
            text = "Optional Name",
            inputWidth = 135,
            getValue = function() return addNameText end,
            setValue = function(value) addNameText = value or "" end,
            tooltip = "Optional custom name for a manually entered NPC ID. Unknown IDs stay labelled Unknown NPC until you name them or meet that NPC.",
        })
    y = y - h
    row, h = W:DualRow(parent, y,
        {
            type = "button",
            text = "Add Vendor to Draft",
            width = 210,
            disabled = InCombat,
            disabledTooltip = "Vendor ignore changes are available after combat.",
        },
        { type = "spacer" })
    y = y - h
    local add = row and row._leftRegion and row._leftRegion._control
    if add then add:SetScript("OnClick", function(self) AddManualVendor(self) end) end

    row, h = W:DualRow(parent, y,
        {
            type = "button",
            text = "Save",
            width = 180,
            disabled = InCombat,
            disabledTooltip = "Vendor ignore changes are available after combat.",
        },
        {
            type = "button",
            text = "Cancel",
            width = 180,
            disabled = InCombat,
            disabledTooltip = "Vendor ignore changes are available after combat.",
        })
    y = y - h
    local save = row and row._leftRegion and row._leftRegion._control
    if save then save:SetScript("OnClick", function(self) SaveDraft(self) end) end
    local cancel = row and row._rightRegion and row._rightRegion._control
    if cancel then
        cancel:SetScript("OnClick", function()
            if InCombat() then return end
            CloseDraft()
            RebuildPage()
        end)
    end
    return y
end
