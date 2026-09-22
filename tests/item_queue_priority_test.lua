-- Item Use Order drag-reorder regression harness.
--
-- Run from the addon source directory:
--   lua tests/item_queue_priority_test.lua
--
-- This intentionally extracts BuildItemQueuePriorityList from the production
-- file.  It supplies only the WoW API surface that function needs and drives
-- its exposed frame scripts; no test-only production hooks are required.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text
end

-- Return the complete local function declaration, while ignoring Lua strings
-- and comments.  Counting the block-opening keywords keeps this independent
-- of the function's internal formatting.
local function extractFunction(source, name, declarationPattern)
    local startAt = assert(source:find(declarationPattern or ("local%s+function%s+" .. name .. "%s*%("), 1),
        "could not find function " .. name)
    local depth, index = 0, startAt

    local function skipQuoted(pos, quote)
        pos = pos + 1
        while pos <= #source do
            local char = source:sub(pos, pos)
            if char == "\\" then
                pos = pos + 2
            elseif char == quote then
                return pos + 1
            else
                pos = pos + 1
            end
        end
        return pos
    end

    while index <= #source do
        local char = source:sub(index, index)
        local nextTwo = source:sub(index, index + 1)
        if nextTwo == "--" then
            if source:sub(index + 2, index + 3) == "[[" then
                local closeAt = source:find("]]", index + 4, true)
                index = closeAt and closeAt + 2 or #source + 1
            else
                local newline = source:find("\n", index + 2, true)
                index = newline and newline + 1 or #source + 1
            end
        elseif char == "\"" or char == "'" then
            index = skipQuoted(index, char)
        elseif char == "[" and source:sub(index, index + 1) == "[[" then
            local closeAt = source:find("]]", index + 2, true)
            index = closeAt and closeAt + 2 or #source + 1
        elseif char:match("[%a_]") then
            local first, last, word = source:find("([%a_][%w_]*)", index)
            index = last + 1
            if word == "function" or word == "if" or word == "for" or word == "while" or word == "repeat" then
                depth = depth + 1
            elseif word == "end" or word == "until" then
                depth = depth - 1
                if depth == 0 then return source:sub(startAt, last) end
            end
        else
            index = index + 1
        end
    end
    error("unterminated function " .. name)
end

local cursorX, cursorY, mouseDown = 0, 0, true
local refreshes = 0

local Object = {}
Object.__index = Object

function Object:SetSize(width, height) self.width, self.height = width, height end
function Object:SetWidth(width) self.width = width end
function Object:SetHeight(height) self.height = height end
function Object:GetWidth() return self.width or 0 end
function Object:GetHeight() return self.height or 0 end
function Object:SetScale(scale) self.scale = scale end
function Object:GetScale() return self.scale or 1 end
function Object:GetEffectiveScale()
    if self.effectiveScale then return self.effectiveScale end
    if self.parent then return self.parent:GetEffectiveScale() * self:GetScale() end
    return self:GetScale()
end
function Object:SetFrameStrata() end
function Object:SetFrameLevel(level) self.frameLevel = level end
function Object:GetFrameLevel() return self.frameLevel or 0 end
function Object:EnableMouse(value) self.mouseEnabled = value end
function Object:RegisterForDrag(...) self.dragButtons = { ... } end
function Object:SetAllPoints() end
function Object:SetJustifyH() end
function Object:SetWordWrap() end
function Object:SetFont() end
function Object:SetText(value) self.text = tostring(value) end
function Object:GetText() return self.text end
function Object:SetTextColor() end
function Object:SetColorTexture(...) self.color = { ... } end
function Object:SetAlpha(value) self.alpha = value end
function Object:GetAlpha() return self.alpha == nil and 1 or self.alpha end
function Object:ClearAllPoints() self.point = nil end
function Object:SetPoint(point, relative, relativePoint, x, y)
    -- WoW permits the abbreviated SetPoint(point) form.  The queue list only
    -- needs coordinates for the explicit frame anchors used by its layout.
    if type(relative) ~= "table" then
        self.point = { point = point }
        return
    end
    relativePoint, x, y = relativePoint or point, x or 0, y or 0
    local anchors = {
        TOPLEFT = function(frame) return frame:GetLeft(), frame:GetTop() end,
        TOPRIGHT = function(frame) return frame:GetRight(), frame:GetTop() end,
        BOTTOMLEFT = function(frame) return frame:GetLeft(), frame:GetBottom() end,
        BOTTOMRIGHT = function(frame) return frame:GetRight(), frame:GetBottom() end,
        CENTER = function(frame) return (frame:GetLeft() + frame:GetRight()) / 2, (frame:GetTop() + frame:GetBottom()) / 2 end,
    }
    local getter = anchors[relativePoint] or anchors.TOPLEFT
    local anchorX, anchorY = getter(relative)
    if point == "TOPLEFT" then
        self.left, self.top = anchorX + x, anchorY + y
    elseif point == "BOTTOMLEFT" then
        self.left, self.bottom = anchorX + x, anchorY + y
        self.top = self.bottom + self:GetHeight()
    else
        self.left, self.top = anchorX + x, anchorY + y
    end
    self.point = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
end
function Object:GetLeft() return self.left or 0 end
function Object:GetTop() return self.top or ((self.bottom or 0) + self:GetHeight()) end
function Object:GetRight() return self:GetLeft() + self:GetWidth() end
function Object:GetBottom() return self:GetTop() - self:GetHeight() end
function Object:SetScript(name, callback)
    self.scripts = self.scripts or {}
    self.scripts[name] = callback
end
function Object:GetScript(name) return self.scripts and self.scripts[name] end
function Object:Show()
    self.shown = true
    local callback = self:GetScript("OnShow")
    if callback then callback(self) end
end
function Object:Hide()
    self.shown = false
    local callback = self:GetScript("OnHide")
    if callback then callback(self) end
end
function Object:IsShown() return self.shown == true end
function Object:CreateTexture()
    local texture = setmetatable({ parent = self }, Object)
    self.children[#self.children + 1] = texture
    return texture
end
function Object:CreateFontString()
    local string = setmetatable({ parent = self }, Object)
    self.children[#self.children + 1] = string
    return string
end

local function newFrame(kind, parent)
    local frame = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true, alpha = 1 }, Object)
    if parent then parent.children[#parent.children + 1] = frame end
    return frame
end

UIParent = newFrame("Frame", nil)
UIParent:SetSize(1600, 900)
UIParent.left, UIParent.top, UIParent.effectiveScale = 0, 900, 1

function CreateFrame(kind, _, parent)
    return newFrame(kind, parent or UIParent)
end
function GetCursorPosition() return cursorX, cursorY end
function IsMouseButtonDown(button) return button == "LeftButton" and mouseDown end
STANDARD_TEXT_FONT = "MockFont"
ACCENT_R, ACCENT_G, ACCENT_B = 0.05, 0.82, 0.62
C_Timer = { After = function(_, _) end }
EllesmereUI = {
    GetFontPath = function() return "MockFont" end,
    HideWidgetTooltip = function() end,
    ShowWidgetTooltip = function() end,
}
_G.__dualRows = {}
function OptionsSectionIntro() return nil, 18 end
EllesmereUI.Widgets = {
    SectionHeader = function(_, parent, text, yOffset)
        local header = newFrame("Frame", parent)
        header._sectionText = text
        header:SetSize(parent:GetWidth() - 90, 40)
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 45, yOffset or 0)
        return header, 40
    end,
    DualRow = function(_, parent, y, left, right)
        local row = newFrame("Frame", parent)
        row:SetSize(parent:GetWidth() - 90, 50)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 45, y)
        for index, cfg in ipairs({ left, right }) do
            local region = newFrame("Frame", row)
            region:SetSize(right and math.floor(row:GetWidth() / 2) or row:GetWidth(), 50)
            region:SetPoint("TOPLEFT", row, "TOPLEFT", index == 2 and row:GetWidth() - region:GetWidth() or 0, 0)
            local label = region:CreateFontString()
            label:SetText(cfg.text or "")
            local control = newFrame("Button", region)
            control:SetSize(cfg.width or 180, 32)
            control:SetPoint("TOPLEFT", region, "TOPLEFT", region:GetWidth() - control:GetWidth() - 20, -9)
            if cfg.onClick then control:SetScript("OnClick", cfg.onClick) end
            region._label, region._control = label, control
            row[index == 1 and "_leftRegion" or "_rightRegion"] = region
        end
        _G.__dualRows[#_G.__dualRows + 1] = { config = left, row = row }
        return row, 50
    end,
}

local keys = { "knowledge", "recipes", "appearances", "tabards", "mounts", "heirlooms", "toys", "pets", "housing", "account", "combination", "containers", "custom" }
local prelude = [[
local ITEM_QUEUE_TYPES = {}
for _, key in ipairs(_G.__queueKeys) do
    ITEM_QUEUE_TYPES[key] = { label = key, color = { r = 0.2, g = 0.4, b = 0.6 } }
end
local ITEM_QUEUE_ORDER = _G.__queueKeys
local function GetItemQueueSettings() return assert(_G.__itemQueueSettings) end
local function IsItemQueueCategoryEnabled() return true end
local function GetItemQueueColor(key)
    local color = ITEM_QUEUE_TYPES[key].color
    return color.r, color.g, color.b
end
local function SetFont(fontString, size, flags) fontString:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE") end
local function RefreshItemQueue() _G.__refreshes = _G.__refreshes + 1 end
]]

_G.__queueKeys = keys
_G.__refreshes = 0
local sourceFunction = extractFunction(readFile(SOURCE), "BuildItemQueuePriorityList")
local chunk, loadErr = load(prelude .. "\n" .. sourceFunction .. "\nreturn BuildItemQueuePriorityList", "@extracted-item-queue-priority", "t", _G)
assert(chunk, loadErr)
local BuildItemQueuePriorityList = chunk()
_G.BuildItemQueuePriorityList = BuildItemQueuePriorityList

local pageFunction = extractFunction(readFile(SOURCE), "BuildItemQueuePage", "BuildItemQueuePage%s*=%s*function%s*%(")
local pageChunk, pageLoadErr = load(prelude .. "\n" .. pageFunction .. "\nreturn BuildItemQueuePage", "@extracted-item-queue-page", "t", _G)
assert(pageChunk, pageLoadErr)
local BuildItemQueuePage = pageChunk()

local function copy(list)
    local result = {}
    for i, value in ipairs(list) do result[i] = value end
    return result
end

local function join(list) return table.concat(list, ",") end

local function assertEqual(actual, expected, message)
    if actual ~= expected then error((message or "values differ") .. "\nexpected: " .. tostring(expected) .. "\nactual:   " .. tostring(actual), 2) end
end

local function assertNear(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "values differ") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function collect(frame, predicate, output)
    output = output or {}
    if predicate(frame) then output[#output + 1] = frame end
    for _, child in ipairs(frame.children or {}) do collect(child, predicate, output) end
    return output
end

local function rowFrames(holder)
    return collect(holder, function(frame) return frame.kind == "Button" and frame._queueKey ~= nil end)
end

local function rowForKey(holder, key)
    for _, row in ipairs(rowFrames(holder)) do
        if row._queueKey == key then return row end
    end
    error("missing row for " .. key)
end

local function visualOrder(holder)
    local rows = rowFrames(holder)
    table.sort(rows, function(a, b)
        -- The priority order is column-major: all left-column rows, then right.
        if math.abs(a:GetLeft() - b:GetLeft()) > 0.5 then return a:GetLeft() < b:GetLeft() end
        return a:GetTop() > b:GetTop()
    end)
    local order = {}
    for index, row in ipairs(rows) do order[index] = row._queueKey end
    return order
end

local function moveToFinalSlot(order, sourceIndex, targetIndex)
    local result, source = copy(order), order[sourceIndex]
    table.remove(result, sourceIndex)
    table.insert(result, targetIndex, source)
    return result
end

local function setCursorAt(holder, x, y)
    local scale = holder:GetEffectiveScale()
    cursorX, cursorY = x * scale, y * scale
end

local function setCursorAtRow(holder, row)
    setCursorAt(holder, (row:GetLeft() + row:GetRight()) / 2, (row:GetTop() + row:GetBottom()) / 2)
end

local function invoke(frame, script, ...)
    local callback = frame:GetScript(script)
    assertTrue(callback ~= nil, "missing " .. script .. " on exposed frame")
    return callback(frame, ...)
end

local function buildList(width, scale)
    _G.__itemQueueSettings = { order = copy(keys), colors = {} }
    _G.__refreshes = 0
    mouseDown = true
    local callbacks = {}
    local parent = newFrame("Frame", UIParent)
    parent:SetSize(width or 1005, 900)
    parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50)
    parent:SetScale(scale or 1)
    local holder, height = BuildItemQueuePriorityList(parent, -80, function(savedOrder)
        callbacks[#callbacks + 1] = savedOrder
    end)
    assertTrue(holder ~= nil and height > 0, "list did not return a holder and height")
    return parent, holder, callbacks
end

local function assertOrder(order, expected, context)
    assertEqual(join(order), join(expected), context)
    local seen = {}
    for _, key in ipairs(order) do
        assertTrue(not seen[key], context .. " duplicated " .. key)
        seen[key] = true
    end
    assertEqual(#order, #keys, context .. " lost a category")
end

local function findGhost(holder, knownRows)
    local rowSet = {}
    for _, row in ipairs(knownRows) do rowSet[row] = true end
    local candidates = collect(holder, function(frame)
        return frame ~= holder and frame.kind == "Frame" and not rowSet[frame] and frame:IsShown() and frame:GetWidth() > 0 and frame:GetHeight() > 0
    end)
    -- A ghost may live on UIParent in older implementations, or holder in the
    -- fixed version.  Search the root only when it was not holder-owned.
    if #candidates == 0 then
        candidates = collect(UIParent, function(frame)
            return frame ~= UIParent and frame.kind == "Frame" and frame:IsShown() and frame._rank and frame._label
        end)
    end
    return candidates[1]
end

local function beginAndHover(holder, sourceIndex, targetIndex)
    local source = rowForKey(holder, keys[sourceIndex])
    local target = rowForKey(holder, keys[targetIndex])
    setCursorAtRow(holder, source)
    invoke(source, "OnDragStart")
    setCursorAtRow(holder, target)
    invoke(holder, "OnUpdate", 0)
    return source, target
end

local function priorityHolderFromPage(parent)
    for _, frame in ipairs(collect(parent, function(candidate) return candidate.kind == "Frame" end)) do
        local directRows = 0
        for _, child in ipairs(frame.children) do
            if child.kind == "Button" and child._queueKey then directRows = directRows + 1 end
        end
        if directRows == #keys then return frame end
    end
    error("BuildItemQueuePage did not create an exposed priority holder")
end

local function autoSortButtonFromPage(parent)
    for _, frame in ipairs(collect(parent, function(candidate)
        return candidate.kind == "Button" and candidate._waffleAutoSort
    end)) do
        return frame
    end
    error("BuildItemQueuePage did not create an Auto Sort button")
end

local function categoryLabel(key)
    for _, record in ipairs(_G.__dualRows) do
        if record.config and record.config.type == "toggle" and record.config.text == key then
            return record.row._leftRegion._label, record.config
        end
    end
    error("missing category label for " .. key)
end

local function buildPage(width)
    _G.__itemQueueSettings = { order = copy(keys), colors = {}, categories = {} }
    _G.__refreshes = 0
    mouseDown = true
    _G.__dualRows = {}
    local parent = newFrame("Frame", UIParent)
    parent:SetSize(width or 1005, 1600)
    parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -30)
    BuildItemQueuePage("Item Queue", parent, -40)
    return parent, priorityHolderFromPage(parent)
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end

test("column-major layout fits normal and compact options widths", function()
    for _, width in ipairs({ 1005, 640 }) do
        local _, holder = buildList(width)
        assertTrue(holder:GetWidth() > 0, "holder width must remain positive at " .. width)
        assertOrder(visualOrder(holder), keys, "initial column-major layout at width " .. width)
        for _, row in ipairs(rowFrames(holder)) do
            assertTrue(row:GetWidth() > 0 and row:GetHeight() > 0, "row has invalid bounds at width " .. width)
            assertTrue(row:GetLeft() >= holder:GetLeft() - 0.01 and row:GetRight() <= holder:GetRight() + 0.01,
                "row escapes holder at width " .. width)
        end
    end
end)

test("order tools and list share native margins with clear header and button gutters", function()
    for _, width in ipairs({ 1005, 640 }) do
        local parent, holder = buildPage(width)
        local button = autoSortButtonFromPage(parent)
        local toolsRow = button.parent.parent
        assertNear(holder:GetLeft(), toolsRow:GetLeft(), 0.01, "priority list left margin")
        assertNear(holder:GetRight(), toolsRow:GetRight(), 0.01, "priority list right margin")
        assertNear(holder:GetLeft() - parent:GetLeft(), 45, 0.01, "native content inset")
        assertTrue(button:GetTop() <= toolsRow:GetTop() - 8 and button:GetBottom() >= toolsRow:GetBottom() + 8,
            "Auto Sort must have a visible gutter above and below")
        assertTrue(button:GetRight() <= toolsRow:GetRight() - 20, "Auto Sort must stay inside the row")
        assertTrue(holder:GetTop() <= toolsRow:GetBottom() - 8, "list must clear the toolbar")
        local headers = collect(parent, function(frame) return frame._sectionText == "ITEM USE ORDER" end)
        assertEqual(#headers, 1, "one owning priority header")
        assertTrue(button:GetTop() <= headers[1]:GetBottom() - 8, "button must clear the header divider")
    end
end)

test("same-height left-to-right and reverse drops use the final target slot", function()
    local _, holder = buildList(1005)
    local left, right = rowForKey(holder, keys[1]), rowForKey(holder, keys[8])
    assertNear((left:GetTop() + left:GetBottom()) / 2, (right:GetTop() + right:GetBottom()) / 2, 0.01,
        "indices 1 and 8 must share a visual row")
    beginAndHover(holder, 1, 8)
    invoke(left, "OnDragStop")
    assertOrder(_G.__itemQueueSettings.order, moveToFinalSlot(keys, 1, 8), "left-to-right same-height drop")

    _, holder = buildList(1005)
    local reverse = rowForKey(holder, keys[8])
    beginAndHover(holder, 8, 1)
    invoke(reverse, "OnDragStop")
    assertOrder(_G.__itemQueueSettings.order, moveToFinalSlot(keys, 8, 1), "right-to-left same-height drop")
end)

test("every source and destination persists the expected order without duplicates", function()
    for sourceIndex = 1, #keys do
        for targetIndex = 1, #keys do
            local _, holder = buildList(1005)
            local source = beginAndHover(holder, sourceIndex, targetIndex)
            invoke(source, "OnDragStop")
            local expected = moveToFinalSlot(keys, sourceIndex, targetIndex)
            local context = string.format("source %d -> target %d", sourceIndex, targetIndex)
            assertOrder(_G.__itemQueueSettings.order, expected, context)
            assertOrder(visualOrder(holder), expected, context .. " visual order")
            assertTrue(_G.__refreshes == (sourceIndex == targetIndex and 0 or 1), context .. " saved an unexpected number of times")
        end
    end
end)

test("drag preview live-reflows into the final target order", function()
    local _, holder = buildList(1005)
    local source = beginAndHover(holder, 2, 12)
    local expected = moveToFinalSlot(keys, 2, 12)
    assertOrder(visualOrder(holder), expected, "live preview order")
    assertTrue(source:GetAlpha() <= 0.36, "dragged source should be visibly dimmed during preview")
    invoke(source, "OnDragStop")
    assertOrder(_G.__itemQueueSettings.order, expected, "live preview final order")
end)

test("mouse-release fallback commits when OnDragStop is absent", function()
    local _, holder = buildList(1005)
    beginAndHover(holder, 3, 11)
    -- Deliberately do not call OnDragStop or OnMouseUp.  A dropped button can
    -- miss either event; the holder's update loop must notice the release.
    mouseDown = false
    invoke(holder, "OnUpdate", 0)
    mouseDown = true
    assertOrder(_G.__itemQueueSettings.order, moveToFinalSlot(keys, 3, 11), "mouse-release fallback")
    assertEqual(_G.__refreshes, 1, "mouse-release fallback should persist once")
end)

test("order-change callback receives the persisted order only after a real drop", function()
    local _, holder, callbacks = buildList(1005)
    beginAndHover(holder, 5, 9)
    assertEqual(#callbacks, 0, "preview must not notify the order-change callback")
    local source = rowForKey(holder, keys[5])
    invoke(source, "OnDragStop")
    local expected = moveToFinalSlot(keys, 5, 9)
    assertEqual(#callbacks, 1, "drop should notify exactly once")
    assertOrder(callbacks[1], expected, "callback order")
    assertTrue(callbacks[1] == _G.__itemQueueSettings.order, "callback must receive the saved order object")

    _, holder, callbacks = buildList(1005)
    beginAndHover(holder, 5, 9)
    holder:Hide()
    assertEqual(#callbacks, 0, "cancelling on hide must not notify the callback")
end)

test("page category rank labels reflect saved order after drag and reopen", function()
    local parent, holder = buildPage()
    for rank, key in ipairs(keys) do
        local label, config = categoryLabel(key)
        assertEqual(label:GetText(), "#" .. rank .. "  " .. key, "initial visible category rank for " .. key)
        assertEqual(config.text, key, "category config text must remain stable for " .. key)
    end

    local source = beginAndHover(holder, 2, 10)
    invoke(source, "OnDragStop")
    local expected = moveToFinalSlot(keys, 2, 10)
    for rank, key in ipairs(expected) do
        local label = categoryLabel(key)
        assertEqual(label:GetText(), "#" .. rank .. "  " .. key, "live category rank after drop for " .. key)
    end

    -- Rebuild the page from the SavedVariables order, as the options panel
    -- does on reopen.  It must not depend on the prior label objects.
    _G.__dualRows = {}
    local reopened = newFrame("Frame", UIParent)
    reopened:SetSize(1005, 1600)
    reopened:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -30)
    BuildItemQueuePage("Item Queue", reopened, -40)
    for rank, key in ipairs(expected) do
        local label, config = categoryLabel(key)
        assertEqual(label:GetText(), "#" .. rank .. "  " .. key, "reopened category rank for " .. key)
        assertEqual(config.text, key, "reopened category config text for " .. key)
    end
end)

test("Auto Sort restores the recommended priority and updates every visible rank", function()
    local parent, holder = buildPage()
    local source = beginAndHover(holder, 13, 1)
    invoke(source, "OnDragStop")
    assertTrue(join(_G.__itemQueueSettings.order) ~= join(keys), "setup drag must change the order")

    local autoSort = autoSortButtonFromPage(parent)
    invoke(autoSort, "OnClick")
    assertOrder(_G.__itemQueueSettings.order, keys, "Auto Sort saved order")
    assertOrder(visualOrder(holder), keys, "Auto Sort visible priority list")
    assertEqual(_G.__refreshes, 2, "drag and Auto Sort must each refresh the queue once")
    for rank, key in ipairs(keys) do
        local label = categoryLabel(key)
        assertEqual(label:GetText(), "#" .. rank .. "  " .. key, "Auto Sort category rank for " .. key)
    end
end)

test("holder OnHide cancels a drag and restores the original order", function()
    local _, holder = buildList(1005)
    local source = beginAndHover(holder, 4, 10)
    holder:Hide()
    assertOrder(_G.__itemQueueSettings.order, keys, "hide cancellation")
    assertOrder(visualOrder(holder), keys, "hide cancellation visual restoration")
    assertEqual(_G.__refreshes, 0, "hide cancellation must not persist")
    assertNear(source:GetAlpha(), 1, 0.001, "hide cancellation must restore source opacity")
end)

test("ghost follows holder-scaled cursor movement and stays inside the holder", function()
    for _, scale in ipairs({ 0.5, 1.5 }) do
        local _, holder = buildList(1005, scale)
        local source = rowForKey(holder, keys[2])
        -- Begin near the source's left edge to prove the ghost preserves the
        -- grab offset.  The following small move stays clear of every clamp.
        setCursorAt(holder, source:GetLeft() + 20, source:GetTop() - 10)
        invoke(source, "OnDragStart")
        local ghost = findGhost(holder, rowFrames(holder))
        assertTrue(ghost ~= nil, "no visible drag ghost at scale " .. scale)
        local beforeLeft, beforeTop = ghost:GetLeft(), ghost:GetTop()
        setCursorAt(holder, cursorX / holder:GetEffectiveScale() + 5, cursorY / holder:GetEffectiveScale() + 5)
        invoke(holder, "OnUpdate", 0)
        assertNear(ghost:GetLeft() - beforeLeft, 5, 0.2, "ghost horizontal cursor tracking at scale " .. scale)
        assertNear(ghost:GetTop() - beforeTop, 5, 0.2, "ghost vertical cursor tracking at scale " .. scale)
        assertTrue(ghost:GetLeft() >= holder:GetLeft() - 0.01 and ghost:GetRight() <= holder:GetRight() + 0.01,
            "ghost horizontal bounds at scale " .. scale)
        assertTrue(ghost:GetBottom() >= holder:GetBottom() - 0.01 and ghost:GetTop() <= holder:GetTop() + 0.01,
            "ghost vertical bounds at scale " .. scale)
        holder:Hide()
    end
end)

test("release samples the latest cursor and duplicate release events do not save twice", function()
    for _, scale in ipairs({ 0.5, 1, 1.5 }) do
        local _, holder = buildList(1005, scale)
        local source, target = rowForKey(holder, keys[1]), rowForKey(holder, keys[13])
        setCursorAtRow(holder, source)
        invoke(source, "OnMouseDown", "LeftButton")
        invoke(source, "OnDragStart")
        -- Release at the last slot before the holder gets another update.
        setCursorAtRow(holder, target)
        invoke(source, "OnMouseUp", "LeftButton")
        invoke(source, "OnDragStop")
        assertOrder(_G.__itemQueueSettings.order, moveToFinalSlot(keys, 1, 13), "release position at scale " .. scale)
        assertEqual(_G.__refreshes, 1, "duplicate release must save once")
        assertTrue(holder:GetScript("OnUpdate") == nil, "release must stop drag updates")
    end
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, err = xpcall(entry.callback, debug.traceback)
    if ok then
        io.write("PASS  " .. entry.name .. "\n")
    else
        failures = failures + 1
        io.write("FAIL  " .. entry.name .. "\n" .. err .. "\n")
    end
end

if failures > 0 then
    io.write(string.format("%d of %d scenarios failed\n", failures, #tests))
    os.exit(1)
end
io.write(string.format("All %d Item Use Order drag scenarios passed\n", #tests))
