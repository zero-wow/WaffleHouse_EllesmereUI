-- Vendor tracking grid regression harness.
--
-- Run from the addon source directory:
--   lua tests/vendor_tracking_layout_test.lua
--
-- This loads WaffleHouse_VendorTracking.lua through its public addon table and
-- supplies the small part of the WoW frame API used by the layout.  The host
-- renderer is deliberately not copied here: categories are represented by
-- its real shape (20px headers and 34px slot parents anchored to ScrollChild).

local SOURCE = arg[1] or "WaffleHouse_VendorTracking.lua"
local unpack = table.unpack or unpack
_G.unpack = unpack -- WoW exposes this Lua 5.1 global; stock Lua 5.4 does not.

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertNear(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local timers = {}
local function flushTimers()
    local turns = 0
    while #timers > 0 do
        turns = turns + 1
        assertTrue(turns < 40, "layout kept scheduling itself")
        local pending = timers
        timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
end

C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }

-- hooksecurefunc is used by the module to preserve the host renderer's latest
-- source anchors.  The mock retains the original method and runs the hook
-- after it, as Blizzard's object-method form does.
function hooksecurefunc(object, method, callback)
    assertTrue(type(object) == "table" and type(method) == "string", "unexpected hooksecurefunc form")
    local original = assert(object[method], "missing method for hook: " .. method)
    object[method] = function(self, ...)
        local results = { original(self, ...) }
        callback(self, ...)
        return unpack(results)
    end
end

local Object = {}
Object.__index = Object

local function anchorPosition(frame, point)
    point = point or "TOPLEFT"
    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if point == "TOPLEFT" then return left, top end
    if point == "TOPRIGHT" then return right, top end
    if point == "BOTTOMLEFT" then return left, bottom end
    if point == "BOTTOMRIGHT" then return right, bottom end
    if point == "LEFT" then return left, (top + bottom) / 2 end
    if point == "RIGHT" then return right, (top + bottom) / 2 end
    if point == "TOP" then return (left + right) / 2, top end
    if point == "BOTTOM" then return (left + right) / 2, bottom end
    return (left + right) / 2, (top + bottom) / 2
end

local function pointOffset(width, height, point)
    if point == "TOPLEFT" then return 0, 0 end
    if point == "TOPRIGHT" then return -width, 0 end
    if point == "BOTTOMLEFT" then return 0, height end
    if point == "BOTTOMRIGHT" then return -width, height end
    if point == "LEFT" then return 0, height / 2 end
    if point == "RIGHT" then return -width, height / 2 end
    if point == "TOP" then return -width / 2, 0 end
    if point == "BOTTOM" then return -width / 2, height end
    return -width / 2, height / 2
end

function Object:SetSize(width, height)
    local changed = self.width ~= width or self.height ~= height
    self.width, self.height = width, height
    self:_ResolvePoint()
    if changed then self:Fire("OnSizeChanged", width, height) end
end
function Object:SetWidth(width) self:SetSize(width, self:GetHeight()) end
function Object:SetHeight(height) self:SetSize(self:GetWidth(), height) end
function Object:GetWidth() return self.width or 0 end
function Object:GetHeight() return self.height or 0 end
function Object:_ResolvePoint()
    local point = self.points and self.points[1]
    if point and point[2] then
        local anchorX, anchorY = anchorPosition(point[2], point[3])
        local offsetX, offsetY = pointOffset(self:GetWidth(), self:GetHeight(), point[1])
        self.left, self.top = anchorX + point[4] + offsetX, anchorY + point[5] + offsetY
    end
    -- WoW anchors are live.  A slot parent moving also moves the button and
    -- its pin, without firing either child's SetPoint hook.
    for _, child in ipairs(self.children) do
        if child.points and child.points[1] and child.points[1][2] == self then child:_ResolvePoint() end
    end
end
function Object:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) ~= "table" then
        self.points = { { point, nil, nil, 0, 0 } }
        return
    end
    relativePoint, x, y = relativePoint or point, x or 0, y or 0
    self.points = { { point, relative, relativePoint, x, y } }
    self:_ResolvePoint()
end
function Object:GetPoint(index)
    local point = self.points and self.points[index or 1]
    if point then return unpack(point) end
end
function Object:GetNumPoints() return self.points and #self.points or 0 end
function Object:ClearAllPoints() self.points = {} end
function Object:SetAllPoints(relative)
    relative = relative or self.parent
    self:SetPoint("TOPLEFT", relative, "TOPLEFT", 0, 0)
    self.width, self.height = relative:GetWidth(), relative:GetHeight()
    self:_ResolvePoint()
end
function Object:GetLeft() return self.left or 0 end
function Object:GetTop() return self.top or (self:GetHeight()) end
function Object:GetRight() return self:GetLeft() + self:GetWidth() end
function Object:GetBottom() return self:GetTop() - self:GetHeight() end
function Object:SetParent(parent)
    if self.parent == parent then return end
    if self.parent then
        for index, child in ipairs(self.parent.children) do
            if child == self then table.remove(self.parent.children, index); break end
        end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Object:GetParent() return self.parent end
function Object:GetChildren() return unpack(self.children) end
function Object:SetScript(name, callback) self.scripts[name] = callback end
function Object:HookScript(name, callback)
    local prior = self.scripts[name]
    self.scripts[name] = function(...)
        if prior then prior(...) end
        callback(...)
    end
end
function Object:GetScript(name) return self.scripts[name] end
function Object:Fire(name, ...)
    local callback = self.scripts[name]
    if callback then callback(self, ...) end
end
function Object:Show() self.shown = true; self:Fire("OnShow") end
function Object:Hide() self.shown = false; self:Fire("OnHide") end
function Object:SetShown(value) if value then self:Show() else self:Hide() end end
function Object:IsShown() return self.shown == true end
function Object:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function Object:SetFrameLevel(level) self.frameLevel = level end
function Object:GetFrameLevel() return self.frameLevel or 1 end
function Object:SetScale(scale) self.scale = scale end
function Object:GetScale() return self.scale or 1 end
function Object:GetEffectiveScale() return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Object:SetText(value) self.text = value end
function Object:GetText() return self.text end
function Object:SetFont() end
function Object:SetTextColor() end
function Object:SetJustifyH() end
function Object:SetWordWrap() end
function Object:SetColorTexture() end
function Object:SetTexture() end
function Object:SetAlpha(value) self.alpha = value end
function Object:GetAlpha() return self.alpha or 1 end
function Object:EnableMouse() end
function Object:RegisterForClicks() end
function Object:SetFrameStrata() end
function Object:SetClampedToScreen() end
function Object:CreateTexture()
    return setmetatable({ parent = self, children = {}, scripts = {}, shown = true }, Object)
end
function Object:CreateFontString()
    return setmetatable({ parent = self, children = {}, scripts = {}, shown = true }, Object)
end
function Object:SetVerticalScroll(value) self.verticalScroll = value end
function Object:GetVerticalScroll() return self.verticalScroll or 0 end
function Object:GetVerticalScrollRange()
    local child = self.ScrollChild
    return math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
end
function Object:UpdateThumb() self.thumbUpdates = (self.thumbUpdates or 0) + 1 end

local function newFrame(kind, parent)
    local frame = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true }, Object)
    if parent then parent.children[#parent.children + 1] = frame end
    return frame
end

UIParent = newFrame("Frame")
UIParent:SetSize(1920, 1080)
UIParent.left, UIParent.top = 0, 1080
function CreateFrame(kind, _, parent) return newFrame(kind, parent or UIParent) end

local addon = {}
local chunk, loadErr = loadfile(SOURCE)
assert(chunk, loadErr)
chunk("WaffleHouse_EllesmereUI", addon)
assertTrue(type(addon.LayoutVendorTracking) == "function", "module must expose addon.LayoutVendorTracking")

local function newVendor(contentWidth, viewportHeight)
    local frame = newFrame("Frame", UIParent)
    frame:SetSize(contentWidth + 80, viewportHeight + 90)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
    frame.ScrollFrame = newFrame("ScrollFrame", frame)
    frame.ScrollFrame:SetSize(contentWidth, viewportHeight)
    frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -40)
    frame.ScrollChild = newFrame("Frame", frame.ScrollFrame)
    frame.ScrollChild:SetSize(contentWidth, viewportHeight)
    frame.ScrollChild:SetPoint("TOPLEFT", frame.ScrollFrame, "TOPLEFT", 0, 0)
    frame.ScrollFrame.ScrollChild = frame.ScrollChild
    frame.Header = newFrame("Frame", frame)
    frame.Header:SetSize(frame:GetWidth(), 20)
    frame.Footer = newFrame("Frame", frame)
    frame.Footer:SetSize(frame:GetWidth(), 20)
    return frame
end

local function addHeader(frame, y, title)
    local header = newFrame("Frame", frame.ScrollChild)
    header:SetSize(frame.ScrollChild:GetWidth() - 8, 20)
    header.label = header:CreateFontString()
    header.label:SetText(title)
    header.line = header:CreateTexture()
    header:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 8, y)
    return header
end

local function addItem(frame, x, y, merchantIndex, isBuyback)
    local slot = newFrame("Frame", frame.ScrollChild)
    slot:SetSize(34, 34)
    slot:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", x, y)
    local button = newFrame("Button", slot)
    button:SetSize(34, 34)
    button:SetAllPoints(slot)
    button.SlotParent = slot
    button._merchantIndex = merchantIndex
    button._isBuyback = isBuyback
    -- Main creates this control before calling LayoutVendorTracking.  Its
    -- anchor is intentionally relative to the unchanged 34px button, so the
    -- layout must move its slot parent rather than resizing the item itself.
    local pin = newFrame("Button", button)
    pin:SetSize(24, 28)
    pin:SetPoint("LEFT", button, "RIGHT", 6, 0)
    button._wafflePlannerControl = pin
    if isBuyback then pin:Hide() end
    return button
end

local function sourceRender(frame, definitions)
    -- Mimics EllesmereUIVendorBag's pooled render pass: it restores its own
    -- original anchors before a post-render hook has a chance to lay out pins.
    for _, definition in ipairs(definitions) do
        definition.object:Show()
        definition.object:ClearAllPoints()
        definition.object:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", definition.x, definition.y)
    end
end

local function pinFor(button)
    local found = {}
    for _, child in ipairs({ button:GetChildren() }) do
        if child ~= button and math.abs(child:GetWidth() - 24) < 0.01 and math.abs(child:GetHeight() - 28) < 0.01 then
            found[#found + 1] = child
        end
    end
    assertEqual(#found, 1, "each item must own exactly one 24px pin control")
    return found[1]
end

local function pinCount(button)
    local count = 0
    for _, child in ipairs({ button:GetChildren() }) do
        if math.abs(child:GetWidth() - 24) < 0.01 and math.abs(child:GetHeight() - 28) < 0.01 then
            count = count + 1
        end
    end
    return count
end

local function rectsOverlap(a, b)
    return a:GetLeft() < b:GetRight() - 0.01 and a:GetRight() > b:GetLeft() + 0.01
        and a:GetBottom() < b:GetTop() - 0.01 and a:GetTop() > b:GetBottom() + 0.01
end

local function visibleObjects(frame, buttons)
    local output = {}
    for _, button in ipairs(buttons) do
        if button:IsVisible() and button.SlotParent:IsVisible() then
            output[#output + 1] = button
            output[#output + 1] = pinFor(button)
        end
    end
    for _, child in ipairs({ frame.ScrollChild:GetChildren() }) do
        if child.label and child:IsVisible() then output[#output + 1] = child end
    end
    return output
end

local function assertContained(frame, object, message)
    local child = frame.ScrollChild
    assertTrue(object:GetLeft() >= child:GetLeft() - 0.01, message .. " escapes left")
    assertTrue(object:GetRight() <= child:GetRight() + 0.01, message .. " escapes right")
end

local function assertGrid(frame, buttons, context)
    for _, button in ipairs(buttons) do
        if button:IsVisible() and button.SlotParent:IsVisible() then
            assertNear(button:GetWidth(), 34, 0.01, context .. " changed item width")
            assertNear(button:GetHeight(), 34, 0.01, context .. " changed item height")
            local pin = pinFor(button)
            assertNear(pin:GetLeft(), button:GetRight() + 6, 0.01, context .. " pin is not in its dedicated rail")
            assertNear(pin:GetWidth(), 24, 0.01, context .. " pin width")
            assertNear(pin:GetHeight(), 28, 0.01, context .. " pin height")
            assertContained(frame, button, context .. " item")
            assertContained(frame, pin, context .. " pin")
        end
    end
    local objects = visibleObjects(frame, buttons)
    for left = 1, #objects do
        for right = left + 1, #objects do
            assertTrue(not rectsOverlap(objects[left], objects[right]), context .. " has overlapping visible objects")
        end
    end
    assertTrue(frame.ScrollChild:GetHeight() >= frame.ScrollFrame:GetHeight(), context .. " scroll child is shorter than viewport")
    assertTrue(frame.ScrollFrame:GetVerticalScroll() <= frame.ScrollFrame:GetVerticalScrollRange(), context .. " scroll position was not clamped")
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end

local refreshFrame, refreshButtons
addon.Refresh = function()
    if refreshFrame then addon.LayoutVendorTracking(refreshFrame, refreshButtons) end
end

local function refreshFrom(frame, buttons)
    refreshFrame, refreshButtons = frame, buttons
end

test("minimum width reserves a rail and preserves two source sections", function()
    local frame = newVendor(186, 96)
    local first = addHeader(frame, -6, "Weapons")
    local a = addItem(frame, 8, -30, 1)
    local b = addItem(frame, 46, -30, 2)
    local second = addHeader(frame, -78, "Consumables")
    local c = addItem(frame, 8, -102, 3)
    local d = addItem(frame, 46, -102, 4)
    local buttons = { a, b, c, d }
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    assertEqual(addon.VendorTrackingLayout.cellWidth, 72, "public cell pitch")
    assertEqual(addon.VendorTrackingLayout.rowPitch, 42, "public row pitch")
    assertEqual(addon.VendorTrackingLayout.leftPadding, 15, "public left padding")
    assertEqual(addon.VendorTrackingLayout.rightPadding, 24, "public right padding")
    assertGrid(frame, buttons, "minimum-width layout")
    assertTrue(first:GetTop() > a:GetTop(), "first section header must stay above its source items")
    assertTrue(second:GetTop() > c:GetTop(), "second section header must stay above its source items")
    assertTrue(second:GetTop() < a:GetBottom(), "sections must retain their source membership and ordering")
    assertTrue(frame.ScrollChild:GetHeight() >= 176,
        "content height must include headers and row pitch")
end)

test("resize and repeated calls recompute columns without cumulative drift", function()
    local frame = newVendor(186, 100)
    local header = addHeader(frame, -6, "General")
    local buttons = {}
    for index = 1, 6 do buttons[index] = addItem(frame, 8 + ((index - 1) % 3) * 38, -30 - math.floor((index - 1) / 3) * 38, index) end
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    local firstLeft, firstTop = buttons[1]:GetLeft(), buttons[1]:GetTop()
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    assertNear(buttons[1]:GetLeft(), firstLeft, 0.01, "repeat layout drifted horizontally")
    assertNear(buttons[1]:GetTop(), firstTop, 0.01, "repeat layout drifted vertically")

    frame.ScrollFrame:SetWidth(330)
    frame.ScrollChild:SetWidth(330)
    refreshFrom(frame, buttons)
    flushTimers()
    assertGrid(frame, buttons, "expanded resize")
    assertTrue(buttons[3]:GetTop() > buttons[1]:GetBottom(), "expanded width should fit more than two columns")

    frame.ScrollFrame:SetWidth(186)
    frame.ScrollChild:SetWidth(186)
    refreshFrom(frame, buttons)
    flushTimers()
    assertGrid(frame, buttons, "collapsed resize")
    assertNear(header:GetHeight(), 20, 0.01, "host header height changed during resize")
end)

test("pooled host rerender restores source anchors then layout reflows again", function()
    local frame = newVendor(186, 100)
    local header = addHeader(frame, -6, "Reagents")
    local a = addItem(frame, 8, -30, 1)
    local b = addItem(frame, 46, -30, 2)
    local buttons = { a, b }
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    local initialTop = a:GetTop()
    sourceRender(frame, {
        { object = header, x = 8, y = -6 },
        { object = a.SlotParent, x = 8, y = -30 },
        { object = b.SlotParent, x = 46, y = -30 },
    })
    -- A visible parent/slot is the post-render signal available to the addon.
    frame.ScrollChild:Fire("OnShow")
    refreshFrom(frame, buttons)
    frame.ScrollFrame:Fire("OnSizeChanged", frame.ScrollFrame:GetWidth(), frame.ScrollFrame:GetHeight())
    flushTimers()
    assertGrid(frame, buttons, "pooled rerender")
    assertNear(a:GetTop(), initialTop, 0.01, "rerender did not reapply tracking layout")
end)

test("filtered, empty, and buyback-restored slots do not leak into layout", function()
    local frame = newVendor(186, 100)
    addHeader(frame, -6, "All Items")
    local a = addItem(frame, 8, -30, 1)
    local b = addItem(frame, 46, -30, 2)
    local buttons = { a, b }
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    local click = function() end
    a:SetScript("OnClick", click)
    b:Hide(); b.SlotParent:Hide()
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    assertTrue(not pinFor(b):IsVisible(), "filtered slot pin must not remain visible")
    assertGrid(frame, { a }, "filtered layout")
    assertTrue(a:GetScript("OnClick") == click, "layout must not replace purchase scripts")

    a:Hide(); a.SlotParent:Hide()
    addon.LayoutVendorTracking(frame, buttons)
    flushTimers()
    assertTrue(frame.ScrollChild:GetHeight() >= frame.ScrollFrame:GetHeight(), "empty content must retain viewport height")
    for _, child in ipairs({ frame.ScrollChild:GetChildren() }) do
        if child.label then assertTrue(child:IsShown(), "layout must leave host section visibility alone") end
    end
end)

test("buyback restores native host layout and keeps its already-hidden pin hidden", function()
    local frame = newVendor(186, 100)
    local header = addHeader(frame, -6, "Buyback")
    local buyback = addItem(frame, 8, -30, 1, true)
    local nativeLeft, nativeTop = buyback:GetLeft(), buyback:GetTop()
    addon.LayoutVendorTracking(frame, { buyback })
    flushTimers()
    assertNear(header:GetLeft(), frame.ScrollChild:GetLeft() + 8, 0.01, "buyback header must retain host position")
    assertNear(buyback:GetLeft(), nativeLeft, 0.01, "buyback item must retain host x position")
    assertNear(buyback:GetTop(), nativeTop, 0.01, "buyback item must retain host y position")
    assertTrue(not pinFor(buyback):IsShown(), "buyback pin must remain hidden")
    assertTrue(frame.ScrollChild:GetHeight() >= frame.ScrollFrame:GetHeight(), "buyback scroll child must fit viewport")
end)

for _, entry in ipairs(tests) do
    entry.callback()
    io.write("ok - " .. entry.name .. "\n")
end
io.write("vendor tracking layout tests passed\n")
