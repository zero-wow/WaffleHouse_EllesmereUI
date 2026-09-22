local _, addon = ...

-- Leave each merchant button at its original size.  The pin occupies its own
-- right-hand column, with gutters between both the item and the next cell.
local LAYOUT = {
    cellWidth = 72,
    rowPitch = 42,
    leftPadding = 15,
    rightPadding = 24,
    headerGap = 8,
    sectionGap = 10,
}
addon.VendorTrackingLayout = LAYOUT

local function IsListView()
    return addon.IsVendorListView and addon.IsVendorListView() == true
end

local function QueueLayout(frame, state)
    if state.applying or state.queued or IsListView() then return end
    state.queued = true
    C_Timer.After(0, function()
        state.queued = nil
        if frame:IsShown() and addon.Refresh then addon.Refresh() end
    end)
end

local function CapturePoint(region, scrollChild)
    local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
    if point ~= "TOPLEFT" or relativeTo ~= scrollChild or relativePoint ~= "TOPLEFT" then return end
    return { point, relativeTo, relativePoint, x or 0, y or 0 }
end

local function WatchRegion(frame, state, region, isHeader)
    local record = state.regions[region]
    if record then return record end
    record = { point = CapturePoint(region, frame.ScrollChild), isHeader = isHeader }
    if isHeader then record.width = region:GetWidth() end
    state.regions[region] = record
    hooksecurefunc(region, "SetPoint", function()
        if state.applying or IsListView() then return end
        record.point = CapturePoint(region, frame.ScrollChild)
        QueueLayout(frame, state)
    end)
    if isHeader then
        hooksecurefunc(region, "SetWidth", function(_, width)
            if state.applying then return end
            record.width = width
        end)
    end
    return record
end

local function GetLayoutState(frame)
    if frame._waffleTrackingLayout then return frame._waffleTrackingLayout end
    local state = { regions = {}, nativeHeight = frame.ScrollChild:GetHeight() }
    frame._waffleTrackingLayout = state
    -- The host renderer resets these before it places its pooled items.  Its
    -- changes schedule one refresh after rendering; our own layout is guarded.
    hooksecurefunc(frame.ScrollChild, "SetHeight", function(_, height)
        if state.applying or IsListView() then return end
        state.nativeHeight = height
        QueueLayout(frame, state)
    end)
    frame.ScrollFrame:HookScript("OnSizeChanged", function() QueueLayout(frame, state) end)
    return state
end

local function RestoreLayout(frame, state)
    for region, record in pairs(state.regions) do
        if record.point then
            region:ClearAllPoints()
            region:SetPoint(unpack(record.point))
        end
        if record.width then region:SetWidth(record.width) end
    end
    frame.ScrollChild:SetHeight(math.max(state.nativeHeight, frame.ScrollFrame:GetHeight()))
end

local function ClampScroll(frame)
    local scroll = frame.ScrollFrame
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, scroll:GetVerticalScrollRange())))
end

function addon.LayoutVendorTracking(frame, buttons)
    if not (frame and frame.ScrollChild and frame.ScrollFrame) then return end
    -- Easy Access list view owns the item rows while it is active.  Do not
    -- observe or rewrite those anchors; grid tracking resumes on restore.
    if IsListView() then return end
    local state = GetLayoutState(frame)
    local sections = {}
    for _, child in ipairs({ frame.ScrollChild:GetChildren() }) do
        if child.label and child.line then
            local record = WatchRegion(frame, state, child, true)
            if record.point and child:IsShown() then
                sections[#sections + 1] = { header = child, point = record.point, items = {} }
            end
        end
    end
    table.sort(sections, function(a, b) return a.point[5] > b.point[5] end)

    local hasBuyback = false
    for _, button in ipairs(buttons) do
        local slot = button.SlotParent or button:GetParent()
        local record = WatchRegion(frame, state, slot, false)
        if record.point and button:IsShown() and slot:IsShown() then
            if button._isBuyback then
                hasBuyback = true
            else
                local section
                for _, candidate in ipairs(sections) do
                    if record.point[5] < candidate.point[5] then section = candidate end
                end
                if section then
                    section.items[#section.items + 1] = { slot = slot, point = record.point }
                end
            end
        end
    end

    state.applying = true
    -- Buyback remains the host's compact grid and never offers shopping pins.
    if hasBuyback or #sections == 0 then
        RestoreLayout(frame, state)
        state.applying = nil
        ClampScroll(frame)
        return
    end

    local available = frame.ScrollFrame:GetWidth() - LAYOUT.leftPadding - LAYOUT.rightPadding
    local columns = math.max(1, math.floor(available / LAYOUT.cellWidth))
    local y = -6
    for _, section in ipairs(sections) do
        local header = section.header
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", LAYOUT.leftPadding, y)
        header:SetWidth(math.max(1, available))
        y = y - header:GetHeight() - LAYOUT.headerGap
        table.sort(section.items, function(a, b)
            if a.point[5] ~= b.point[5] then return a.point[5] > b.point[5] end
            return a.point[4] < b.point[4]
        end)
        for index, item in ipairs(section.items) do
            item.slot:ClearAllPoints()
            item.slot:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT",
                LAYOUT.leftPadding + ((index - 1) % columns) * LAYOUT.cellWidth,
                y - math.floor((index - 1) / columns) * LAYOUT.rowPitch)
        end
        y = y - math.ceil(#section.items / columns) * LAYOUT.rowPitch - LAYOUT.sectionGap
    end
    local contentHeight = math.max(math.abs(y) + 10, frame.ScrollFrame:GetHeight())
    frame.ScrollChild:SetHeight(contentHeight)
    state.applying = nil
    ClampScroll(frame)
end
