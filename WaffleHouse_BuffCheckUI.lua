local _, addon = ...
local B = addon.BuffCheck
local WIDTH, PAD, HEADER, ICON, GAP, ROW, MAX_ROWS = 280, 14, 32, 34, 8, 38, 4
local GREEN = { 0.05, 0.82, 0.62 }
local panel, picker, pending, visibilityTicker, preview
local page, pickerPage = 1, 1
local Refresh, QueueRefresh, RenderPicker, UpdateVisibilityWatch

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local SITUATIONS = {
    { key = "overworld", label = "Overworld" },
    { key = "dungeon", label = "Dungeon" },
    { key = "delve", label = "Delve" },
    { key = "raid", label = "Raid" },
    { key = "scenario", label = "Scenario" },
    { key = "pvp", label = "Battleground" },
    { key = "arena", label = "Arena" },
}

local function IsGrouped()
    return type(IsInGroup) == "function" and IsInGroup() == true
end

local function GetSituation()
    if type(IsInRaid) == "function" and IsInRaid() == true then return "raid" end
    if type(IsInInstance) ~= "function" then return "overworld" end
    local inInstance, instanceType = IsInInstance()
    if inInstance ~= true then return "overworld" end
    if instanceType == "party" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    -- Delves use the scenario instance family on current Retail.  Keep a
    -- separate Scenario option so an unusual scenario can still be filtered.
    if instanceType == "scenario" then return "delve" end
    if instanceType == "pvp" then return "pvp" end
    if instanceType == "arena" then return "arena" end
    return "scenario"
end

local function SituationAllowed(settings)
    if settings.groupedOnly == true and not IsGrouped() then return false end
    local selected = type(settings.situations) == "table" and settings.situations or nil
    -- No situation boxes means no location restriction, rather than a panel
    -- that silently never appears.
    if not selected or next(selected) == nil then return true end
    return selected[GetSituation()] == true
end

local function EnableBuffCheck()
    local settings = B.GetSettings()
    settings.enabled = true
    if settings.visibilitySeeded ~= true then
        settings.visibilitySeeded = true
        -- This is intentionally the only automatic visibility choice.  It is
        -- made once, on first enable, and any subsequent player edit wins.
        if settings.groupedOnly == nil then settings.groupedOnly = true end
    end
    return settings
end

local function Font(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    local path = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")
    text:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    text:SetTextColor(unpack(color or { 0.85, 0.86, 0.87 }))
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Surface(frame)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.055, 0.061, 0.068, 0.96)
    frame:SetBackdropBorderColor(1, 1, 1, 0.14)
end

local function LabelButton(parent, text, width, height, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.label = Font(button, 11)
    button.label:SetAllPoints()
    button.label:SetJustifyH("CENTER")
    button.label:SetText(text)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    button:SetScript("OnClick", function(...) if not InCombat() then callback(...) end end)
    return button
end

local function Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.72, 0.76, 0.78, true) end
    GameTooltip:Show()
end

local function GroupTooltip(button)
    local entry = button.entry
    if not entry then return end
    local lines = { #entry.missing .. " missing / " .. entry.eligible .. " checked" }
    for i = 1, math.min(10, #entry.missing) do lines[#lines + 1] = entry.missing[i].name end
    if #entry.missing > 10 then lines[#lines + 1] = "+" .. (#entry.missing - 10) .. " more" end
    if entry.unknown > 0 then lines[#lines + 1] = entry.unknown .. " unavailable or unreadable" end
    lines[#lines + 1] = entry.castable and "Click to cast your group buff. Players must be in range."
        or "Coverage only. A " .. entry.def.class:lower() .. " must cast this buff."
    if preview then lines[#lines + 1] = "Preview: sample data; casting disabled." end
    Tooltip(button, B.SpellName(entry.def), lines)
end

local function CastButton(parent, size)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetSize(size, size)
    button:RegisterForClicks("AnyDown", "AnyUp")
    Surface(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = Font(button, 12, { 1, 1, 1 })
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    button.count:SetShadowOffset(1, -1)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function ConfigureCast(button, def, unit, castable, status)
    -- Every caller is gated out of combat. Never retarget a protected action
    -- from PreClick, or infer a target from the current raid order on click.
    button:SetAttribute("type", nil)
    button:SetAttribute("type1", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("unit", nil)
    if castable and unit and not preview then
        button:SetAttribute("spell", def.spellID)
        button:SetAttribute("unit", unit)
        button:SetAttribute("type1", "spell")
    end
    button.icon:SetTexture(C_Spell.GetSpellTexture(def.spellID))
    button.icon:SetDesaturated(not castable)
    button.icon:SetAlpha(status == "ready" and 0.45 or 1)
    button:SetBackdropBorderColor(unpack(status == "ready" and { 0.05, 0.82, 0.62, 0.55 }
        or { 1, 1, 1, castable and 0.3 or 0.12 }))
end

local function CanAssign(def, member)
    if not member.guid then return false end
    if def.noSelf and UnitIsUnit(member.unit, "player") then return false end
    if def.healerOnly and member.role ~= "HEALER" then return false end
    if def.spellID == 53563 or def.spellID == 156910 then
        local otherID = def.spellID == 53563 and 156910 or 53563
        for _, other in ipairs(B.targetDefs) do
            if other.spellID == otherID and B.GetAssignments()[other.key] == member.guid then return false end
        end
    end
    return true
end

local function ClosePicker()
    if picker then picker:Hide(); picker.def = nil end
end

local function ClosePanel()
    -- Closing the shared Buff Check panel also exits preview. Otherwise the
    -- next refresh would immediately redraw the deliberately always-visible
    -- preview frame.
    if preview then B.Invalidate(); pending = nil end
    preview = false
    UpdateVisibilityWatch()
    ClosePicker()
    if panel then panel:Hide() end
end

local function OpenPicker(def)
    if preview then return end
    picker.def = def
    pickerPage = 1
    RenderPicker()
    picker:Show()
end

RenderPicker = function()
    if InCombat() or not picker.def then return end
    local roster = {}
    for _, member in ipairs(B.GetRoster(true)) do
        if CanAssign(picker.def, member) then roster[#roster + 1] = member end
    end
    table.sort(roster, function(a, b)
        local roles = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
        local ar, br = roles[a.role] or 4, roles[b.role] or 4
        if ar ~= br then return ar < br end
        return a.name < b.name
    end)
    local pages = math.max(1, math.ceil(#roster / 8))
    pickerPage = math.min(pickerPage, pages)
    picker.title:SetText(B.SpellName(picker.def))
    picker.counter:SetText(pickerPage .. " / " .. pages)
    picker.previous:SetEnabled(pickerPage > 1)
    picker.next:SetEnabled(pickerPage < pages)
    for i, button in ipairs(picker.rows) do
        local member = roster[(pickerPage - 1) * 8 + i]
        button.member = member
        button:SetShown(member ~= nil)
        if member then
            button.label:SetText(member.name)
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
            button.label:SetTextColor(color and color.r or 0.85, color and color.g or 0.85, color and color.b or 0.85)
            button.role:SetText(member.role == "TANK" and "Tank" or member.role == "HEALER" and "Healer" or "")
        end
    end
    picker.empty:SetShown(#roster == 0)
end

local function EnsurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "WaffleHouseBuffCheck", UIParent, "SecureHandlerStateTemplate,BackdropTemplate")
    panel:SetSize(WIDTH, HEADER)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    Surface(panel)
    local settings = B.GetSettings()
    local pos = settings.position
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", type(pos) == "table" and tonumber(pos.x) or 30,
        type(pos) == "table" and tonumber(pos.y) or -240)
    panel.title = Font(panel, 12, GREEN)
    panel.title:SetPoint("TOPLEFT", PAD, -10)
    panel.title:SetText("BUFF CHECK")
    panel.summary = Font(panel, 10)
    panel.summary:SetPoint("TOPLEFT", 112, -11)
    panel.summary:SetWidth(116)
    panel.drag = CreateFrame("Frame", nil, panel)
    panel.drag:SetPoint("TOPLEFT", 4, -3)
    -- Leave a visible gutter before both header actions so the drag surface
    -- cannot intercept a close or minimize click.
    panel.drag:SetSize(WIDTH - 70, HEADER - 6)
    panel.drag:EnableMouse(true)
    panel.drag:RegisterForDrag("LeftButton")
    panel.drag:SetScript("OnDragStart", function() if not InCombat() then panel:StartMoving() end end)
    panel.drag:SetScript("OnDragStop", function()
        if InCombat() then return end
        panel:StopMovingOrSizing()
        B.GetSettings().position = { x = panel:GetLeft(), y = panel:GetTop() - UIParent:GetHeight() }
    end)
    panel.collapse = LabelButton(panel, "-", 24, 24, function()
        B.GetSettings().collapsed = not B.GetSettings().collapsed
        ClosePicker()
        Refresh()
    end)
    panel.close = LabelButton(panel, "×", 24, 24, ClosePanel)
    panel.close:SetPoint("TOPRIGHT", -6, -4)
    panel.close:SetScript("OnEnter", function(self) Tooltip(self, "Close Buff Check", { "Close this panel and exit preview." }) end)
    panel.close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.collapse:SetPoint("RIGHT", panel.close, "LEFT", -2, 0)
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetPoint("TOPLEFT", 0, -HEADER)
    panel.body:SetWidth(WIDTH)
    panel.groupLabel = Font(panel.body, 9, { 0.52, 0.57, 0.59 })
    panel.groupLabel:SetPoint("TOPLEFT", PAD, -3)
    panel.groupLabel:SetText("GROUP BUFFS")
    panel.groupIcons = {}
    for i = 1, 6 do
        local button = CastButton(panel.body, ICON)
        button:SetPoint("TOPLEFT", PAD + (i - 1) * (ICON + GAP), -20)
        button:SetScript("OnEnter", GroupTooltip)
        panel.groupIcons[i] = button
    end
    panel.targetLabel = Font(panel.body, 9, { 0.52, 0.57, 0.59 })
    panel.targetLabel:SetText("YOUR ASSIGNMENTS")
    panel.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel.body)
        row:SetSize(WIDTH - PAD * 2, ROW)
        row.select = LabelButton(row, "", WIDTH - PAD * 2 - 42, ROW - 4, function() OpenPicker(row.entry.def) end)
        row.select:SetPoint("TOPLEFT")
        row.select.label:Hide()
        row.name = Font(row.select, 11)
        row.name:SetPoint("TOPLEFT", 1, -3)
        row.name:SetWidth(WIDTH - PAD * 2 - 45)
        row.spell = Font(row.select, 9, { 0.52, 0.57, 0.59 })
        row.spell:SetPoint("TOPLEFT", 1, -18)
        row.spell:SetWidth(WIDTH - PAD * 2 - 45)
        row.cast = CastButton(row, 30)
        row.cast:SetPoint("TOPRIGHT", 0, -1)
        row.select:SetScript("OnEnter", function(self)
            Tooltip(self, B.SpellName(row.entry.def), { "Click the name to choose a recipient.",
                "Each assignment follows that player when the group changes." })
        end)
        row.select:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.cast:SetScript("OnEnter", function(self)
            local status = row.entry.status
            local descriptions = {
                missing = "Missing. Click to cast on this recipient.", ready = "Your buff is active.",
                unknown = "Coverage unavailable. You can still cast on the assigned recipient.",
                unassigned = "Choose a recipient by clicking the name.", absent = "The assigned recipient is not available in this group.",
            }
            Tooltip(self, B.SpellName(row.entry.def), { descriptions[status] or "Coverage unavailable.",
                "Range, cooldown and target restrictions still apply." })
        end)
        panel.rows[i] = row
    end
    panel.footer = Font(panel.body, 10, { 0.6, 0.65, 0.65 })
    panel.footer:SetWidth(180)
    panel.previous = LabelButton(panel.body, "<", 22, 22, function() page = math.max(1, page - 1); Refresh() end)
    panel.next = LabelButton(panel.body, ">", 22, 22, function() page = page + 1; Refresh() end)
    picker = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    picker:SetSize(WIDTH, 300)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
    picker:EnableMouse(true)
    Surface(picker)
    picker.title = Font(picker, 11, GREEN)
    picker.title:SetPoint("TOPLEFT", PAD, -12)
    picker.title:SetWidth(214)
    picker.close = LabelButton(picker, "x", 22, 22, ClosePicker)
    picker.close:SetPoint("TOPRIGHT", -6, -6)
    picker.rows = {}
    for i = 1, 8 do
        local button = LabelButton(picker, "", WIDTH - PAD * 2, 25, function(self)
            B.GetAssignments()[picker.def.key] = self.member.guid
            ClosePicker()
            B.Invalidate()
            Refresh()
        end)
        button:SetPoint("TOPLEFT", PAD, -38 - (i - 1) * 26)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", 4, 0)
        button.label:SetSize(182, 25)
        button.label:SetJustifyH("LEFT")
        button.role = Font(button, 9, { 0.5, 0.55, 0.56 })
        button.role:SetPoint("RIGHT", -4, 0)
        picker.rows[i] = button
    end
    picker.empty = Font(picker, 11)
    picker.empty:SetPoint("TOPLEFT", PAD, -50)
    picker.empty:SetText("No eligible recipients in this group.")
    picker.counter = Font(picker, 10)
    picker.counter:SetPoint("BOTTOM", 0, 18)
    picker.previous = LabelButton(picker, "<", 24, 24, function() pickerPage = math.max(1, pickerPage - 1); RenderPicker() end)
    picker.previous:SetPoint("BOTTOMRIGHT", -42, 12)
    picker.next = LabelButton(picker, ">", 24, 24, function() pickerPage = pickerPage + 1; RenderPicker() end)
    picker.next:SetPoint("BOTTOMRIGHT", -14, 12)
    picker.clear = LabelButton(picker, "Clear", 50, 24, function()
        B.GetAssignments()[picker.def.key] = nil
        ClosePicker()
        B.Invalidate()
        Refresh()
    end)
    picker.clear:SetPoint("BOTTOMLEFT", PAD, 12)
    picker:Hide()
    panel:Hide()
    -- The secure driver, not an insecure combat event callback, owns hiding.
    -- On leaving combat remain hidden until fresh GUIDs and spell attributes
    -- have been installed, so stale raid-slot actions are never exposed.
    panel:SetAttribute("_onstate-combat", "if newstate == 'combat' then self:Hide() end")
    RegisterStateDriver(panel, "combat", "[combat] combat; peace")
end

local function PreviewState()
    local groups = {}
    for i, def in ipairs(B.groupDefs) do
        local missing = {}
        for j = 1, i + 1 do missing[j] = { name = "Example " .. j } end
        groups[i] = { def = def, missing = missing, covered = 40 - #missing, eligible = 40, unknown = 0, castable = false }
    end
    local targets = {}
    for i = 1, math.min(4, #B.targetDefs) do
        targets[i] = { def = B.targetDefs[i], member = { name = i == 1 and "Example Tank" or "Example Healer" }, status = "missing", castable = false }
    end
    return { groups = groups, targets = targets, size = 40, skipped = 0 }
end

Refresh = function()
    if InCombat() then UpdateVisibilityWatch(); return end
    local settings = B.GetSettings()
    if not preview and (not settings.enabled or not SituationAllowed(settings)) then
        UpdateVisibilityWatch()
        if panel then ClosePicker(); panel:Hide() end
        return
    end
    EnsurePanel()
    local state = preview and PreviewState() or B.Collect(true)
    UpdateVisibilityWatch()
    if not state then panel:Hide(); return end
    local groups, targets, missing, unknown, unassigned = {}, {}, 0, 0, 0
    for _, entry in ipairs(state.groups) do
        missing = missing + #entry.missing
        unknown = unknown + entry.unknown
        if not settings.hideReady or #entry.missing > 0 or entry.unknown > 0 then groups[#groups + 1] = entry end
    end
    for _, entry in ipairs(state.targets) do
        if entry.status == "missing" then missing = missing + 1 end
        if entry.status == "unknown" or entry.status == "absent" then unknown = unknown + 1 end
        if entry.status == "unassigned" then unassigned = unassigned + 1 end
        if not settings.hideReady or entry.status ~= "ready" then targets[#targets + 1] = entry end
    end
    local needsAttention = missing > 0 or unknown > 0 or unassigned > 0
    if not preview and settings.onlyWhenNeeded ~= false
        and not needsAttention and not (settings.alwaysShowInGroup == true and IsGrouped()) then
        if panel then ClosePicker(); panel:Hide() end
        return
    end
    panel.summary:SetText(preview and "Preview · 40 players" or state.size .. (state.size == 1 and " player" or " players"))
    panel.collapse.label:SetText(settings.collapsed and "+" or "-")
    panel.body:SetShown(not settings.collapsed)
    if settings.collapsed then
        ClosePicker()
        panel:SetHeight(HEADER)
        panel:Show()
        return
    end
    panel.groupLabel:SetShown(#groups > 0)
    for i, button in ipairs(panel.groupIcons) do
        local entry = groups[i]
        button.entry = entry
        button:SetShown(entry ~= nil)
        if entry then
            local ready = #entry.missing == 0 and entry.unknown == 0
            ConfigureCast(button, entry.def, "player", entry.castable, ready and "ready" or "missing")
            button.count:SetText(#entry.missing > 0 and tostring(#entry.missing) or entry.unknown > 0 and "?" or "")
        end
    end
    local y = #groups > 0 and 66 or 4
    panel.targetLabel:ClearAllPoints()
    panel.targetLabel:SetPoint("TOPLEFT", PAD, -y)
    panel.targetLabel:SetShown(#targets > 0)
    if #targets > 0 then y = y + 19 end
    local pages = math.max(1, math.ceil(#targets / MAX_ROWS))
    page = math.min(page, pages)
    local rowsShown = 0
    for i, row in ipairs(panel.rows) do
        local entry = targets[(page - 1) * MAX_ROWS + i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            rowsShown = rowsShown + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -y - (i - 1) * ROW)
            row.name:SetText(entry.member and entry.member.name or entry.status == "absent" and "Recipient unavailable" or "Choose recipient")
            local color = entry.member and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.member.class]
            row.name:SetTextColor(color and color.r or 0.85, color and color.g or 0.86, color and color.b or 0.87)
            row.spell:SetText(B.SpellName(entry.def))
            ConfigureCast(row.cast, entry.def, entry.member and entry.member.unit, entry.castable, entry.status)
            row.cast.count:SetText(entry.status == "unknown" and "?" or "")
        end
    end
    y = y + rowsShown * ROW + 4
    panel.footer:ClearAllPoints()
    panel.footer:SetPoint("TOPLEFT", PAD, -y - 6)
    panel.footer:SetText(preview and "Preview · Close or /whbuffs preview to exit"
        or missing > 0 and "Missing buffs · " .. missing
        or unknown > 0 and "Some coverage unavailable"
        or unassigned > 0 and "Choose your recipients"
        or (#state.groups == 0 and #state.targets == 0) and "No tracked buffs in this group" or "All set")
    panel.previous:ClearAllPoints()
    panel.previous:SetPoint("TOPRIGHT", -42, -y)
    panel.next:ClearAllPoints()
    panel.next:SetPoint("TOPRIGHT", -14, -y)
    panel.previous:SetShown(pages > 1)
    panel.next:SetShown(pages > 1)
    panel.previous:SetEnabled(page > 1)
    panel.next:SetEnabled(page < pages)
    panel.body:SetHeight(y + 28)
    panel:SetHeight(HEADER + y + 28)
    panel:Show()
    if picker:IsShown() then RenderPicker() end
end

QueueRefresh = function(unit)
    local settings = B.GetSettings()
    if preview or InCombat() or not settings.enabled or not SituationAllowed(settings) then return end
    local batch = pending or { units = {} }
    if unit then batch.units[unit] = true else batch.all = true end
    if pending then return end
    pending = batch
    C_Timer.After(0.2, function()
        if pending ~= batch then return end
        pending = nil
        local current = B.GetSettings()
        if preview or InCombat() or not current.enabled or not SituationAllowed(current) then return end
        -- Invalidate once per affected member, after the entire event burst.
        if batch.all then B.Invalidate()
        else for token in pairs(batch.units) do B.Invalidate(token) end end
        Refresh()
    end)
end

UpdateVisibilityWatch = function()
    local settings = B.GetSettings()
    local run = not preview and settings.enabled and not InCombat() and SituationAllowed(settings)
        and IsGrouped() and B.HasVisibilityWatch()
    if not run and visibilityTicker then visibilityTicker:Cancel(); visibilityTicker = nil end
    if run and not visibilityTicker then
        -- Distant group members can become readable without an aura event.
        -- Probe only cached members' availability; unchanged probes do not
        -- collect buffs, invalidate caches, rebuild the roster, or redraw UI.
        visibilityTicker = C_Timer.NewTicker(5, function()
            if preview or InCombat() or not B.GetSettings().enabled or not SituationAllowed(B.GetSettings()) then
                UpdateVisibilityWatch()
                return
            end
            for unit in pairs(B.CheckVisibility() or {}) do QueueRefresh(unit) end
        end)
    end
end

addon.RefreshBuffCheck = function()
    pending = nil
    B.Invalidate()
    Refresh()
end

local function TogglePreview()
    preview = not preview
    pending = nil
    if not preview then B.Invalidate() end
    ClosePicker()
    page = 1
    Refresh()
end

addon.BuildBuffCheckPage = function(parent, y)
    local W, h, row = EllesmereUI.Widgets
    _, h = W:SectionHeader(parent, "GROUP BUFF CHECK", y); y = y - h
    local function Toggle(key, text, tooltip, setValue)
        return { type = "toggle", text = text, tooltip = tooltip,
            getValue = function() return B.GetSettings()[key] end,
            setValue = setValue or function(value) B.GetSettings()[key] = value and true or false; addon.RefreshBuffCheck() end }
    end
    _, h = W:DualRow(parent, y,
        Toggle("enabled", "Enable Buff Check", "A movable buff panel between pulls. One icon per available group buff; click your own spells to cast. Hides in combat.", function(value)
            if value then EnableBuffCheck() else B.GetSettings().enabled = false end
            addon.RefreshBuffCheck()
        end),
        Toggle("groupedOnly", "Only Show in a Group", "Keep Buff Check out of solo play. It is selected automatically only the first time you enable Buff Check.", function(value)
            local settings = B.GetSettings()
            settings.groupedOnly = value == true
            settings.visibilitySeeded = true
            addon.RefreshBuffCheck()
        end)); y = y - h
    _, h = W:DualRow(parent, y,
        Toggle("onlyWhenNeeded", "Only Show When Needed", "Hide the entire panel when every tracked buff and assignment is ready. Unknown coverage and unassigned recipients count as needing attention."),
        Toggle("alwaysShowInGroup", "Always Show in Group", "Keep the panel visible in a party or raid even when every tracked buff is ready. This overrides Only Show When Needed while grouped.")); y = y - h
    local function SituationSummary()
        local selected, count = B.GetSettings().situations, 0
        if type(selected) ~= "table" then selected = {} end
        for _, entry in ipairs(SITUATIONS) do if selected[entry.key] == true then count = count + 1 end end
        return count == 0 and "Any Situation" or count == 1 and "1 Selected" or count .. " Selected"
    end
    row, h = W:DualRow(parent, y,
        Toggle("hideReady", "Hide Ready Buffs", "Keep only missing, unknown or unassigned rows visible whenever the panel is shown. Group buffs appear once with a missing-player count."),
        { type = "labeledButton", text = "Situations", buttonText = SituationSummary(), tooltip = "Choose the places where Buff Check may appear. Leave every box clear to allow it everywhere." }); y = y - h
    local situationButton = row and row._rightRegion and row._rightRegion._control
    if situationButton then situationButton:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("BUFF CHECK SITUATIONS")
            for _, entry in ipairs(SITUATIONS) do
                local key, label = entry.key, entry.label
                root:CreateCheckbox(label, function() return B.GetSettings().situations[key] == true end, function()
                    local settings = B.GetSettings()
                    settings.situations[key] = not settings.situations[key]
                    addon.RefreshBuffCheck()
                end)
            end
        end)
    end) end
    row, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Panel Preview", buttonText = "Preview", tooltip = "Toggle a 40-player sample. Preview buttons do not cast spells.", disabled = InCombat, disabledTooltip = "Available outside combat." },
        { type = "labeledButton", text = "Panel Position", buttonText = "Reset", tooltip = "Return Buff Check to its default screen position.", disabled = InCombat, disabledTooltip = "Available outside combat." }); y = y - h
    local left = row and row._leftRegion and row._leftRegion._control
    local right = row and row._rightRegion and row._rightRegion._control
    if left then left:SetScript("OnClick", function() if not InCombat() then TogglePreview() end end) end
    if right then right:SetScript("OnClick", function()
        if InCombat() then return end
        B.GetSettings().position = nil
        if panel then panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -240) end
    end) end
    return math.abs(y)
end

SLASH_WAFFLEHOUSEBUFFS1 = "/whbuffs"
SlashCmdList.WAFFLEHOUSEBUFFS = function(message)
    if InCombat() then print("Waffle House: Buff Check can be changed after combat."); return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "preview" then TogglePreview(); return end
    if message == "off" then B.GetSettings().enabled = false; preview = false
    else EnableBuffCheck(); B.GetSettings().collapsed = false end
    addon.RefreshBuffCheck()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA", "UNIT_FLAGS",
    "UNIT_CONNECTION", "UNIT_PHASE", "UNIT_NAME_UPDATE", "PLAYER_ROLES_ASSIGNED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "READY_CHECK" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit, updateInfo)
    if event == "PLAYER_REGEN_DISABLED" then pending = nil; UpdateVisibilityWatch(); return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- A raid token can now refer to somebody else. Remove the old click
        -- surface immediately; the coalesced refresh installs new GUIDs first.
        if not InCombat() and panel then ClosePicker(); panel:Hide() end
    end
    if event == "UNIT_AURA" or event == "UNIT_FLAGS" or event == "UNIT_CONNECTION"
        or event == "UNIT_PHASE" or event == "UNIT_NAME_UPDATE" then
        local settings = B.GetSettings()
        if preview or not settings.enabled or InCombat() or not SituationAllowed(settings) then return end
        if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" then return end
        if unit ~= "player" and not unit:match("^party%d+$") and not unit:match("^raid%d+$") then return end
        if event == "UNIT_NAME_UPDATE" then QueueRefresh(); return end
        if pending and (pending.all or pending.units[unit]) then return end
        if event == "UNIT_AURA" and not B.AuraUpdateRelevant(unit, updateInfo) then return end
        QueueRefresh(unit)
        return
    end
    UpdateVisibilityWatch()
    QueueRefresh()
end)
