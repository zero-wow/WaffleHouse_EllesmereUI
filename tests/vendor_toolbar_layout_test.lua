-- Currency-toolbar width and wrap regression checks.
-- Run from the addon source directory:
--   lua tests/vendor_toolbar_layout_test.lua
--
-- This extracts and runs the production LayoutVendorToolbar body with small
-- frame/font-string mocks.  It deliberately uses measured label widths rather
-- than the former fixed button widths, so a shortened label or an overlap at
-- the minimum Vendor Bags panel width fails here.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file, err = io.open(SOURCE, "rb")
assert(file, "could not open " .. SOURCE .. ": " .. tostring(err))
local source = file:read("*a")
file:close()

local startAt = assert(source:find("function addon%.LayoutVendorToolbar%("), "missing toolbar layout function")
local endAt = assert(source:find("\nend\n\nlocal function RestoreScrollLayout", startAt), "unterminated toolbar layout function")
local functionSource = source:sub(startAt, endAt + #"\nend" - 1)
local chunk, loadErr = load([[local TITLE_H = 26
local addon = {}
]] .. functionSource .. [[

return addon.LayoutVendorToolbar
]], "@extracted-vendor-toolbar-layout")
assert(chunk, loadErr)
local LayoutVendorToolbar = chunk()

local function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function assertTrue(value, message)
    assert(value, message or "assertion failed")
end

local function CreateLabel(width)
    return {
        measuredWidth = width,
        points = {},
        -- Simulate a label that has already been narrowed by a prior layout.
        -- The production function must use the unbounded result instead.
        GetStringWidth = function(self) return math.min(7, self.measuredWidth) end,
        GetUnboundedStringWidth = function(self) return self.measuredWidth end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        SetShown = function(self, shown) self.shown = shown end,
        SetJustifyH = function(self, justify) self.justifyH = justify end,
    }
end

local function CreateControl(name, width, action)
    local control = {
        name = name,
        label = CreateLabel(width),
        points = {},
        SetSize = function(self, controlWidth, controlHeight)
            self.width, self.height = controlWidth, controlHeight
        end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
    }
    if action then
        control._waffleActionIconAnchor = { name = name .. " icon" }
    else
        control._box = { name = name .. " checkbox" }
    end
    return control
end

local order = { "list", "saved", "plan", "afford", "filter", "mode" }
local actionControls = { plan = true, mode = true }
local baseWidths = {
    list = 24,
    saved = 35,
    plan = 24,
    afford = 39,
    filter = 35,
}

local function CreateLegend(mode)
    local legend = { width = 900, _waffleHasCurrencies = true }
    legend.GetWidth = function(self) return self.width end
    legend.title = CreateLabel(61) -- Measured CURRENCIES title width at its configured font.
    for _, name in ipairs(order) do
        local measuredWidth = baseWidths[name] or (mode == "TEXT" and 27 or 25)
        legend[name] = CreateControl(name, measuredWidth, actionControls[name])
    end
    return legend
end

local function Rectangle(control)
    local point = assert(control.points[1], control.name .. " was not positioned")
    assertEqual(point[1], "TOPLEFT", control.name .. " must anchor from the top left")
    return point[4], point[5], point[4] + control.width, point[5] - control.height
end

local function AssertLayout(panelWidth, mode)
    local legend = CreateLegend(mode)
    local returnedHeight = LayoutVendorToolbar(legend, panelWidth)
    local rectangles = {}
    local rowCount = 0
    local sharesTitleRow

    for _, name in ipairs(order) do
        local control = legend[name]
        local expectedWidth = math.max(41, control.label.measuredWidth + 22) + (name == "mode" and 20 or 0)
        assertEqual(control.width, expectedWidth, name .. " must use its measured label width plus icon/checkmark padding")
        assertEqual(control.height, 22, name .. " must leave vertical gutters between toolbar rows")
        assertEqual(control.label.justifyH, "LEFT", name .. " label must stay left-aligned")
        assertEqual(#control.label.points, 2, name .. " label must be bounded on both sides")
        assertEqual(control.label.points[2][1], "RIGHT", name .. " label needs a right clipping guard")
        assertEqual(control.label.points[2][4], name == "mode" and -23 or -3,
            name .. " label needs a gutter before the native-view dot")

        if actionControls[name] then
            assertEqual(control.label.points[1][2], control._waffleActionIconAnchor, name .. " label must follow its action icon")
            assertEqual(control.label.points[1][4], 4, name .. " needs the 4px icon-to-label gap")
        else
            assertEqual(control.label.points[1][2], control._box, name .. " label must follow its checkbox")
            assertEqual(control.label.points[1][4], 5, name .. " needs the checkbox-to-label gap")
        end

        local left, top, right, bottom = Rectangle(control)
        assertTrue(left >= 6, name .. " crossed the left toolbar gutter")
        assertTrue(right <= panelWidth - 6, name .. " crossed the right toolbar gutter")
        if top == -2 then
            sharesTitleRow = true
            assertTrue(left >= 8 + legend.title.measuredWidth + 10, name .. " overlaps the CURRENCIES title")
        else
            assertTrue(top <= -29, name .. " overlaps the CURRENCIES title row")
        end
        local trailingGutter = top == -2 and 2 or 3
        assertTrue(bottom >= -returnedHeight + trailingGutter, name .. " extends below the reserved toolbar height")
        if not sharesTitleRow then
            rowCount = math.max(rowCount, math.floor((-top - 29) / 25) + 1)
        end
        rectangles[#rectangles + 1] = { name = name, left = left, top = top, right = right, bottom = bottom }
    end

    for first = 1, #rectangles do
        for second = first + 1, #rectangles do
            local a, b = rectangles[first], rectangles[second]
            local intersects = a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
            assertTrue(not intersects, a.name .. " intersects " .. b.name)
        end
    end

    if sharesTitleRow then
        assertEqual(returnedHeight, 26, "shared title row must keep the compact single-row height")
        return returnedHeight, 1
    end
    assertEqual(returnedHeight, 26 + 3 + (rowCount * 25), "returned height must reserve every wrapped toolbar row")
    return returnedHeight, rowCount
end

for _, mode in ipairs({ "ICON", "TEXT" }) do
    local narrowHeight, narrowRows = AssertLayout(183, mode)
    local mediumHeight, mediumRows = AssertLayout(340, mode)
    local wideHeight, wideRows = AssertLayout(500, mode)
    local fullHeight, fullRows = AssertLayout(900, mode)
    assertTrue(narrowRows >= 2 and narrowHeight > 26, mode .. " toolbar must wrap at the host minimum panel width")
    assertTrue(mediumRows >= 2 and mediumHeight > 54, mode .. " toolbar must wrap at medium widths")
    assertEqual(wideRows, 1, mode .. " toolbar should share the title row at 500px")
    assertEqual(fullRows, 1, mode .. " toolbar should share the title row at 900px")
    assertEqual(wideHeight, 26, mode .. " shared title row must keep the original compact height")
    assertEqual(fullHeight, 26, mode .. " full-width toolbar height must stay compact")
end

-- A currency-free vendor keeps every action but must not reserve or display a
-- misleading CURRENCIES heading. The compact action group remains at right.
local emptyLegend = CreateLegend("ICON")
emptyLegend._waffleHasCurrencies = false
assertEqual(LayoutVendorToolbar(emptyLegend, 900), 26, "currency-free toolbar stays compact")
assertEqual(emptyLegend.title.shown, false, "currency-free toolbar hides CURRENCIES")
local _, _, modeRight = Rectangle(emptyLegend.mode)
assertEqual(modeRight, 894, "currency-free actions remain right-aligned")
local emptyNarrow = CreateLegend("ICON")
emptyNarrow._waffleHasCurrencies = false
assertTrue(LayoutVendorToolbar(emptyNarrow, 183) > 26, "currency-free narrow toolbar still wraps")

io.write("Vendor toolbar layout tests passed\n")
