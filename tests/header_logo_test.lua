-- Header-logo regression harness.
-- Run from the addon source directory: lua tests/header_logo_test.lua

local SOURCE = arg[1] or "WaffleHouse_Logo.lua"

local function readFile(path)
    local file, err = io.open(path, "rb")
    assert(file, "could not open " .. path .. ": " .. tostring(err))
    local text = file:read("*a")
    file:close()
    return text
end

local Texture = {}
Texture.__index = Texture
function Texture:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
function Texture:SetTexture(path)
    if self.failTexture then error("missing texture") end
    if self.returnFalse then
        self.texture = self.staleTexture or path
        return false
    end
    if self.clearTexture then
        self.texture = nil
        return
    end
    self.texture = path
end
function Texture:GetTexture() return self.texture end
function Texture:SetTexCoord(left, right, top, bottom) self.uv = { left, right, top, bottom } end
function Texture:ClearAllPoints() self.point = nil end
function Texture:SetPoint(point, relative, relativePoint, x, y)
    self.point = { point, relative, relativePoint, x, y }
end
function Texture:SetSize(width, height) self.width, self.height = width, height end
function Texture:Show() self.shown = true end
function Texture:Hide() self.shown = false end

local Title = {}
Title.__index = Title
function Title:GetStringWidth() return self.width end
function Title:GetStringHeight() return self.height end
function Title:Show() self.shown = true end
function Title:Hide() self.shown = false end
function Title:IsShown() return self.shown end

local header = {
    _title = setmetatable({ width = 220, height = 36, shown = true }, Title),
    _desc = { point = "unchanged" },
}
function header:CreateTexture()
    self.logo = setmetatable({}, Texture)
    return self.logo
end

local tabBar = {}
function tabBar:GetPoint() return "TOPLEFT", header, "BOTTOMLEFT", -9, 0 end

local callbacks = {}
local activeModule
local denied = {}
local moduleTitles = {
    WaffleHouse_EllesmereUI = "Waffle House",
    EllesmereUIVendorBag = "Vendor Bags",
}
EllesmereUI = {
    _tabBar = tabBar,
    RegisterOnShow = function(_, callback) callbacks[#callbacks + 1] = callback end,
    SelectModule = function(_, folderName)
        if not moduleTitles[folderName] or denied[folderName] then return end
        activeModule = folderName
    end,
    GetActiveModule = function() return activeModule end,
}

function hooksecurefunc(target, method, hook)
    local original = target[method]
    target[method] = function(...)
        local results = { original(...) }
        hook(...)
        return table.unpack(results)
    end
end

local addon = {}
local environment = setmetatable({
    EllesmereUI = EllesmereUI,
    hooksecurefunc = hooksecurefunc,
}, { __index = _G })
local chunk, err = load(readFile(SOURCE), "@" .. SOURCE, "t", environment)
assert(chunk, err)
chunk("WaffleHouse_EllesmereUI", addon)

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertNear(actual, expected, message)
    if math.abs(actual - expected) > 0.001 then
        error((message or "values differ") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

local tests = {}
local function test(name, callback) tests[#tests + 1] = { name = name, callback = callback } end

test("Waffle House selection replaces only the visible header title", function()
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    local logo = assert(header.logo, "logo texture was not created")
    assertTrue(logo.shown, "logo should be visible for Waffle House")
    assertTrue(not header._title:IsShown(), "text title should be hidden under the logo")
    assertEqual(header._desc.point, "unchanged", "subtitle anchor must not change")
    assertEqual(logo.point[2], header._title, "logo should follow the original title anchor")
    assertNear(logo.width, 201.6, "cropped asset should preserve its 5.6:1 aspect within a 36px title")
    assertNear(logo.height, 36, "logo should match the title height")
end)

test("other modules restore the original text title", function()
    EllesmereUI:SelectModule("EllesmereUIVendorBag")
    assertTrue(not header.logo.shown, "logo should not remain visible on another module")
    assertTrue(header._title:IsShown(), "other module title should be visible")
end)

test("denied valid selections preserve the active header in both directions", function()
    denied.WaffleHouse_EllesmereUI = true
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    assertTrue(not header.logo.shown, "denied Waffle House selection should retain the Vendor Bags title")
    assertTrue(header._title:IsShown(), "denied Waffle House selection should retain visible text")
    denied.WaffleHouse_EllesmereUI = nil
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    denied.EllesmereUIVendorBag = true
    EllesmereUI:SelectModule("EllesmereUIVendorBag")
    assertTrue(header.logo.shown, "denied Vendor Bags selection should retain the Waffle House logo")
    assertTrue(not header._title:IsShown(), "denied Vendor Bags selection should retain hidden Waffle House text")
    denied.EllesmereUIVendorBag = nil
end)

test("cropped UV metadata changes the displayed aspect without changing the subtitle", function()
    addon.LogoTextureInfo.left, addon.LogoTextureInfo.right = 0.1, 0.9
    addon.LogoTextureInfo.top, addon.LogoTextureInfo.bottom = 0.2, 0.8
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    assertNear(header.logo.width, 192, "cropped width should use the cropped 16:3 aspect")
    assertNear(header.logo.height, 36, "cropped logo should remain title-height constrained")
    assertEqual(header._desc.point, "unchanged", "metadata must not move the subtitle")
end)

test("texture errors leave the normal title visible even with a stale texture path", function()
    header.logo.texture = "stale-path"
    header.logo.failTexture = true
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    assertTrue(header._title:IsShown(), "missing texture must fall back to text")
    assertTrue(not header.logo.shown, "failed logo should remain hidden")
    header.logo.failTexture = false
end)

test("false texture return and an empty texture both leave the normal title visible", function()
    header.logo.staleTexture = "stale-path"
    header.logo.returnFalse = true
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    assertTrue(header._title:IsShown(), "false texture result must fall back to text")
    assertTrue(not header.logo.shown, "false texture result should remain hidden")
    header.logo.returnFalse = false
    header.logo.clearTexture = true
    EllesmereUI:SelectModule("WaffleHouse_EllesmereUI")
    assertTrue(header._title:IsShown(), "empty texture must fall back to text")
    assertTrue(not header.logo.shown, "empty texture should remain hidden")
    header.logo.clearTexture = false
end)

test("reopening a cached Waffle House page restores the logo", function()
    header._title:Show()
    for _, callback in ipairs(callbacks) do callback() end
    assertTrue(header.logo.shown, "on-show refresh should restore the cached logo")
    assertTrue(not header._title:IsShown(), "on-show refresh should hide the cached text title")
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
io.write(string.format("All %d header-logo scenarios passed\n", #tests))
