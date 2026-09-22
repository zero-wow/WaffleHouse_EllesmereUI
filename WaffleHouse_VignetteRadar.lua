local _, addon = ...
if type(addon) ~= "table" then return end

local PANEL_W, PANEL_H = 220, 252
local HEADER_H, FIELD_SIZE = 34, 200
local FIELD_RADIUS = (FIELD_SIZE / 2) - 9
local LAUNCHER_SIZE, LAUNCHER_RADIUS = 58, 23
local UPDATE_SECONDS, RESCAN_SECONDS = 0.05, 1
local MAX_BLIPS = 32
local ACCENT = { 0.05, 0.82, 0.62 }
local RED = { 1, 0.18, 0.14 }
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TWO_PI = math.pi * 2
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local Unpack = unpack or table.unpack

local panel, launcher
local preview = false
local manualPanelState
local activeTargets = {}
local activeMapID
local RefreshRadar, ScanVignettes, Render, UpdateLauncher, EnsureLauncher

local function Settings()
    local settings = addon.GetSettings and addon.GetSettings() or {}
    if settings.vignetteRadarLauncherVisible == nil then
        settings.vignetteRadarLauncherVisible = true
    end
    return settings
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local function SafeField(object, key)
    if object == nil or IsSecret(object) then return nil end
    local ok, value = pcall(function() return object[key] end)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" or value ~= value then return nil end
    return value
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function SafeBoolean(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local results = { pcall(func, ...) }
    if not results[1] then return nil end
    return Unpack(results, 2)
end

local function ReadXY(vector)
    if vector == nil or IsSecret(vector) then return nil end
    local x, y = SafeNumber(SafeField(vector, "x")), SafeNumber(SafeField(vector, "y"))
    if x and y then return x, y end
    local getXY = SafeField(vector, "GetXY")
    if type(getXY) ~= "function" then return nil end
    local ok, vx, vy = pcall(getXY, vector)
    if not ok then return nil end
    return SafeNumber(vx), SafeNumber(vy)
end

local function MapToWorld(mapID, mapPosition)
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local instanceID, worldPosition = Call(C_Map.GetWorldPosFromMapPos, mapID, mapPosition)
    local worldX, worldY = ReadXY(worldPosition)
    if not worldX or not worldY then return nil end
    return worldX, worldY, SafeNumber(instanceID)
end

local function CurrentMapID()
    return C_Map and C_Map.GetBestMapForUnit
        and SafeNumber(Call(C_Map.GetBestMapForUnit, "player")) or nil
end

local function PlayerSnapshot(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local mapPosition = Call(C_Map.GetPlayerMapPosition, mapID, "player")
    local mapX, mapY = ReadXY(mapPosition)
    if not mapX or not mapY then return nil end
    local worldX, worldY, instanceID = MapToWorld(mapID, mapPosition)
    if not worldX or not worldY then return nil end
    local facing = GetPlayerFacing and SafeNumber(Call(GetPlayerFacing)) or nil
    return {
        mapID = mapID,
        mapX = mapX,
        mapY = mapY,
        worldX = worldX,
        worldY = worldY,
        instanceID = instanceID,
        facing = facing or 0,
        headingAvailable = facing ~= nil,
    }
end

local function DisplayableVignetteInfo(info)
    return info ~= nil
        and SafeBoolean(SafeField(info, "onMinimap")) == true
        and SafeBoolean(SafeField(info, "isDead")) ~= true
end

local function ClassifyVignette(info)
    local vignetteType = SafeField(info, "type")
    local vignetteTypes = Enum and Enum.VignetteType
    if vignetteTypes then
        if vignetteTypes.Treasure ~= nil and vignetteType == vignetteTypes.Treasure then return "treasure" end
        if vignetteTypes.Rare ~= nil and vignetteType == vignetteTypes.Rare then return "rare" end
        if vignetteTypes.Event ~= nil and vignetteType == vignetteTypes.Event then return "event" end
    end

    local atlasName = (SafeString(SafeField(info, "atlasName")) or ""):lower()
    if atlasName:find("treasure", 1, true) or atlasName:find("chest", 1, true)
        or atlasName:find("container", 1, true) or atlasName:find("loot", 1, true) then
        return "treasure"
    end
    if atlasName:find("rare", 1, true) or atlasName:find("vignettekill", 1, true)
        or atlasName:find("skull", 1, true) then
        return "rare"
    end
    if atlasName:find("event", 1, true) or atlasName:find("horn", 1, true) then
        return "event"
    end
    return "other"
end

local function CollectVignettes(mapID)
    local targets = {}
    if not (mapID and C_VignetteInfo and C_VignetteInfo.GetVignettes
        and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignettePosition) then
        return targets
    end
    local vignetteGUIDs = Call(C_VignetteInfo.GetVignettes)
    if IsSecret(vignetteGUIDs) or type(vignetteGUIDs) ~= "table" then return targets end
    for index = 1, math.min(#vignetteGUIDs, 128) do
        local guid = vignetteGUIDs[index]
        if guid ~= nil and not IsSecret(guid) then
            local info = Call(C_VignetteInfo.GetVignetteInfo, guid)
            if DisplayableVignetteInfo(info) then
                local mapPosition = Call(C_VignetteInfo.GetVignettePosition, guid, mapID)
                local mapX, mapY = ReadXY(mapPosition)
                local worldX, worldY, instanceID = MapToWorld(mapID, mapPosition)
                if mapX and mapY and worldX and worldY then
                    targets[#targets + 1] = {
                        key = tostring(guid),
                        name = SafeString(SafeField(info, "name")) or "Detected vignette",
                        category = ClassifyVignette(info),
                        vignetteType = SafeField(info, "type"),
                        atlasName = SafeString(SafeField(info, "atlasName")),
                        worldX = worldX,
                        worldY = worldY,
                        instanceID = instanceID,
                    }
                    if #targets >= MAX_BLIPS then break end
                end
            end
        end
    end
    return targets
end

local function NormalizeAngle(angle)
    angle = angle % TWO_PI
    if angle > math.pi then angle = angle - TWO_PI end
    return angle
end

local function Project(dx, dy, distance, facing, pixelRadius, rangeYards)
    if not (SafeNumber(dx) and SafeNumber(dy) and SafeNumber(distance)
        and SafeNumber(facing) and SafeNumber(pixelRadius) and SafeNumber(rangeYards))
        or rangeYards <= 0 then return nil end
    local relative = NormalizeAngle(atan2(dy, dx) - facing)
    local radius = (distance / rangeYards) * pixelRadius
    return -math.sin(relative) * radius, math.cos(relative) * radius
end

addon.VignetteRadarTesting = {
    ClassifyVignette = ClassifyVignette,
    CollectVignettes = CollectVignettes,
    DisplayableVignetteInfo = DisplayableVignetteInfo,
    NormalizeAngle = NormalizeAngle,
    Project = Project,
}

local function Text(parent, size, value, accent)
    local label = parent:CreateFontString(nil, "OVERLAY")
    local font = EllesmereUI and (EllesmereUI.EXPRESSWAY or EllesmereUI._font)
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    label:SetFont(font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    label:SetTextColor(accent and ACCENT[1] or 0.88, accent and ACCENT[2] or 0.90,
        accent and ACCENT[3] or 0.92, 1)
    label:SetText(value or "")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Surface(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.045, 0.052, 0.06, alpha or 0.96)
    frame:SetBackdropBorderColor(1, 1, 1, 0.15)
end

local function AddRing(field, radius, alpha)
    local lines = {}
    for index = 1, 64 do
        local line = field:CreateLine(nil, "BORDER")
        local first = ((index - 1) / 64) * TWO_PI
        local last = (index / 64) * TWO_PI
        line:SetThickness(1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], alpha)
        line:SetStartPoint("CENTER", field, "CENTER", math.cos(first) * radius, math.sin(first) * radius)
        line:SetEndPoint("CENTER", field, "CENTER", math.cos(last) * radius, math.sin(last) * radius)
        lines[index] = line
    end
    return lines
end

local function LegendAPI()
    return type(addon.VignetteRadarLegend) == "table" and addon.VignetteRadarLegend or nil
end

local function CategoryEnabled(category)
    local legend = LegendAPI()
    if not (legend and type(legend.IsCategoryEnabled) == "function") then return true end
    local ok, enabled = pcall(legend.IsCategoryEnabled, category or "other")
    return not ok or enabled ~= false
end

local function CategoryColor(category)
    local legend = LegendAPI()
    if legend and type(legend.ColorFor) == "function" then
        local ok, r, g, b = pcall(legend.ColorFor, category or "other")
        if ok and SafeNumber(r) and SafeNumber(g) and SafeNumber(b) then return r, g, b end
    end
    return RED[1], RED[2], RED[3]
end

local function HighlightCategory()
    local legend = LegendAPI()
    if not (legend and type(legend.GetHighlight) == "function") then return nil end
    local ok, category = pcall(legend.GetHighlight)
    return ok and SafeString(category) or nil
end

local function CategoryOpacity(category)
    local legend = LegendAPI()
    if legend and type(legend.OpacityFor) == "function" then
        local ok, alpha = pcall(legend.OpacityFor, category or "other")
        if ok and SafeNumber(alpha) then return alpha end
    end
    local highlight = HighlightCategory()
    return highlight and highlight ~= (category or "other") and 0.18 or 1
end

local function Tooltip(owner)
    local target = owner.target
    if not (target and GameTooltip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(target.name or "Detected vignette", 1, 1, 1)
    if target.distance then
        GameTooltip:AddLine(math.floor(target.distance + 0.5) .. " yd from you", 0.72, 0.76, 0.78)
    end
    if target.sample then
        GameTooltip:AddLine("Layout preview; this is not a live detection.", 0.55, 0.86, 0.76, true)
    else
        GameTooltip:AddLine("Shown from Blizzard's active minimap vignette data.", 0.55, 0.86, 0.76, true)
    end
    GameTooltip:Show()
end

local function AcquireBlip()
    local blip = table.remove(panel.freeBlips)
    if not blip then
        if #panel.blips >= MAX_BLIPS then return nil end
        blip = CreateFrame("Button", nil, panel.field)
        blip:SetSize(11, 11)
        blip:SetFrameLevel(panel.field:GetFrameLevel() + 4)
        blip.glow = blip:CreateTexture(nil, "BACKGROUND")
        blip.glow:SetAllPoints()
        blip.glow:SetTexture(CIRCLE_TEXTURE)
        blip.glow:SetVertexColor(RED[1], RED[2], RED[3], 0.28)
        blip.dot = blip:CreateTexture(nil, "ARTWORK")
        blip.dot:SetSize(6, 6)
        blip.dot:SetPoint("CENTER")
        blip.dot:SetTexture(CIRCLE_TEXTURE)
        blip.dot:SetVertexColor(RED[1], RED[2], RED[3], 1)
        blip:SetScript("OnEnter", Tooltip)
        blip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.blips[#panel.blips + 1] = blip
    end
    blip:Show()
    return blip
end

local function ReleaseBlip(key, blip)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == blip then GameTooltip:Hide() end
    panel.blipByKey[key] = nil
    blip.target = nil
    blip._seen = nil
    blip:Hide()
    blip:ClearAllPoints()
    panel.freeBlips[#panel.freeBlips + 1] = blip
end

local function BeginBlips()
    if not panel then return end
    for _, blip in pairs(panel.blipByKey) do blip._seen = false end
end

local function EndBlips()
    if not panel then return end
    local stale = {}
    for key, blip in pairs(panel.blipByKey) do
        if not blip._seen then stale[#stale + 1] = { key, blip } end
    end
    for _, entry in ipairs(stale) do ReleaseBlip(entry[1], entry[2]) end
end

local function ReleaseAllBlips()
    if not panel then return end
    local assigned = {}
    for key, blip in pairs(panel.blipByKey) do assigned[#assigned + 1] = { key, blip } end
    for _, entry in ipairs(assigned) do ReleaseBlip(entry[1], entry[2]) end
end

local function PlaceBlip(key, screenX, screenY, target)
    local blip = panel.blipByKey[key]
    if not blip then
        blip = AcquireBlip()
        if not blip then return end
        panel.blipByKey[key] = blip
    end
    blip._seen = true
    blip.target = target
    local r, g, b = CategoryColor(target.category)
    blip.dot:SetVertexColor(r, g, b, 1)
    blip.glow:SetVertexColor(r, g, b, 0.28)
    blip:SetAlpha(CategoryOpacity(target.category))
    blip:ClearAllPoints()
    blip:SetPoint("CENTER", panel.field, "CENTER", screenX, screenY)
end

local CARDINALS = {
    { text = "N", angle = 0 },
    { text = "W", angle = math.pi / 2 },
    { text = "S", angle = math.pi },
    { text = "E", angle = -math.pi / 2 },
}

local function RenderCardinals(facing)
    for index, definition in ipairs(CARDINALS) do
        local relative = NormalizeAngle(definition.angle - facing)
        local label = panel.cardinals[index]
        label:ClearAllPoints()
        label:SetPoint("CENTER", panel.field, "CENTER",
            -math.sin(relative) * (FIELD_RADIUS - 5), math.cos(relative) * (FIELD_RADIUS - 5))
    end
end

local function UpdateRingLabels(range)
    panel.innerLabel:SetText(math.floor(range / 3) .. "y")
    panel.outerLabel:SetText(math.floor((range * 2) / 3) .. "y")
end

Render = function()
    if not panel or not panel:IsShown() then return end
    BeginBlips()
    local range = tonumber(Settings().vignetteRadarRange) or 450
    UpdateRingLabels(range)

    if preview then
        panel.summary:SetText("PREVIEW")
        RenderCardinals(0.65)
        local samples = {
            { x = 28, y = 52, distance = range * 0.34, name = "Sample rare", category = "rare", sample = true },
            { x = -58, y = -14, distance = range * 0.58, name = "Sample treasure", category = "treasure", sample = true },
        }
        for index, target in ipairs(samples) do
            if CategoryEnabled(target.category) then PlaceBlip("preview-" .. index, target.x, target.y, target) end
        end
        EndBlips()
        return
    end

    local mapID = CurrentMapID()
    if mapID ~= activeMapID then
        ScanVignettes(mapID)
    end
    local player = PlayerSnapshot(mapID)
    if not player then
        panel.summary:SetText("POSITION UNAVAILABLE")
        RenderCardinals(0)
        EndBlips()
        return
    end
    RenderCardinals(player.facing)
    local shown = 0
    for _, target in ipairs(activeTargets) do
        if CategoryEnabled(target.category)
            and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
            local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
            local distance = math.sqrt((dx * dx) + (dy * dy))
            if distance <= range then
                local screenX, screenY = Project(dx, dy, distance, player.facing, FIELD_RADIUS, range)
                if screenX and screenY then
                    target.distance = distance
                    PlaceBlip(target.key, screenX, screenY, target)
                    shown = shown + 1
                end
            end
        end
    end
    panel.summary:SetText(shown == 1 and "1 IN RANGE" or shown .. " IN RANGE")
    EndBlips()
end

local function SavePosition()
    if not panel then return end
    local left, top = panel:GetLeft(), panel:GetTop()
    if SafeNumber(left) and SafeNumber(top) and UIParent and UIParent.GetHeight then
        Settings().vignetteRadarPosition = { x = left, y = top - UIParent:GetHeight() }
    end
end

local function SaveLauncherPosition()
    if not launcher then return end
    local left, top = launcher:GetLeft(), launcher:GetTop()
    if SafeNumber(left) and SafeNumber(top) and UIParent and UIParent.GetHeight then
        Settings().vignetteRadarLauncherPosition = { x = left, y = top - UIParent:GetHeight() }
    end
end

local function LauncherTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Vignette Radar", 1, 1, 1)
    GameTooltip:AddLine("Left-click to show or tuck away the radar.", 0.65, 0.80, 0.77, true)
    GameTooltip:AddLine("Right-click to preview its live layout. Drag to move this launcher.", 0.65, 0.80, 0.77, true)
    GameTooltip:Show()
end

local function PlayLauncherSound()
    if type(PlaySound) ~= "function" then return end
    local sound = SOUNDKIT and (SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION)
    if sound then pcall(PlaySound, sound) end
end

local function ToggleRadarPanel()
    if panel and panel:IsShown() then
        manualPanelState = false
        preview = false
        panel:Hide()
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
    else
        Settings().vignetteRadarEnabled = true
        manualPanelState = true
        RefreshRadar(true)
    end
    if UpdateLauncher then UpdateLauncher(0, true) end
end

local function CreateLauncherRing(parent, radius, alpha)
    local ring = {}
    for index = 1, 32 do
        local line = parent:CreateLine(nil, "ARTWORK")
        local first = ((index - 1) / 32) * TWO_PI
        local last = (index / 32) * TWO_PI
        line:SetThickness(index % 4 == 0 and 1.6 or 1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], index % 4 == 0 and alpha or alpha * 0.58)
        line:SetStartPoint("CENTER", parent, "CENTER", math.cos(first) * radius, math.sin(first) * radius)
        line:SetEndPoint("CENTER", parent, "CENTER", math.cos(last) * radius, math.sin(last) * radius)
        ring[index] = line
    end
    return ring
end

local function UpdateLauncherSweep(frame, elapsed)
    local active = Settings().vignetteRadarEnabled == true or preview
    frame._animationTime = (frame._animationTime or 0) + elapsed
    local speed = frame._hovered and 2.9 or ((frame.detected or 0) > 0 and 2.1 or 1.15)
    frame._sweepAngle = ((frame._sweepAngle or 0) + elapsed * speed) % TWO_PI
    for index, line in ipairs(frame.sweepLines) do
        local angle = frame._sweepAngle - ((index - 1) * 0.10)
        local alpha = active and (0.72 / index) or (0.22 / index)
        line:SetColorTexture(active and ACCENT[1] or 0.45, active and ACCENT[2] or 0.49,
            active and ACCENT[3] or 0.50, alpha)
        line:SetEndPoint("CENTER", frame, "CENTER", math.sin(angle) * LAUNCHER_RADIUS,
            math.cos(angle) * LAUNCHER_RADIUS)
    end

    local pulse = 0.5 + (0.5 * math.sin(frame._animationTime * 5.5))
    frame.alert:SetAlpha((frame.detected or 0) > 0 and (0.16 + pulse * 0.28) or 0)
    frame.halo:SetAlpha(frame._pressed and 0.48 or (frame._hovered and 0.34 or (active and 0.20 or 0.08)))
    frame.face:SetVertexColor(frame._pressed and 0.025 or 0.018, frame._pressed and 0.09 or 0.055,
        frame._pressed and 0.075 or 0.064, 0.98)

    if frame._shock then
        frame._shock = frame._shock + elapsed / 0.34
        if frame._shock >= 1 then
            frame._shock = nil
            frame.shock:Hide()
        else
            local size = 35 + (frame._shock * 23)
            frame.shock:SetSize(size, size)
            frame.shock:SetAlpha((1 - frame._shock) * 0.58)
            frame.shock:Show()
        end
    end
end

UpdateLauncher = function(elapsed, updateTargets)
    if not launcher then return end
    UpdateLauncherSweep(launcher, elapsed or 0)
    if not updateTargets then return end

    local range = tonumber(Settings().vignetteRadarRange) or 450
    local shown = 0
    local highlight = HighlightCategory()
    local player = not preview and Settings().vignetteRadarEnabled == true and PlayerSnapshot(CurrentMapID()) or nil
    local function ShowDot(target, x, y)
        shown = shown + 1
        local dot = launcher.miniBlips[shown]
        if not dot then return false end
        local red, green, blue = CategoryColor(target.category)
        dot:SetVertexColor(red, green, blue, 1)
        dot:SetAlpha(CategoryOpacity(target.category))
        dot:SetSize(highlight == (target.category or "other") and 7 or 5,
            highlight == (target.category or "other") and 7 or 5)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", launcher, "CENTER", x, y)
        dot:Show()
        return shown < #launcher.miniBlips
    end

    if preview then
        if CategoryEnabled("rare") then ShowDot({ category = "rare" }, 7, 11) end
        if CategoryEnabled("treasure") then ShowDot({ category = "treasure" }, -13, -4) end
        if CategoryEnabled("event") then ShowDot({ category = "event" }, 12, -11) end
    elseif player then
        for _, target in ipairs(activeTargets) do
            if CategoryEnabled(target.category)
                and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
                local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
                local distance = math.sqrt((dx * dx) + (dy * dy))
                if distance <= range then
                    local x, y = Project(dx, dy, distance, player.facing, LAUNCHER_RADIUS - 3, range)
                    if x and y and not ShowDot(target, x, y) then break end
                end
            end
        end
    end
    for index = shown + 1, #launcher.miniBlips do launcher.miniBlips[index]:Hide() end
    launcher.detected = shown
    launcher.count:SetText(shown > 0 and tostring(shown) or "")
    launcher.status:SetAlpha(shown > 0 and 1 or 0.48)
end

EnsureLauncher = function()
    if launcher then return launcher end
    launcher = CreateFrame("Button", "WaffleHouseVignetteRadarLauncher", UIParent)
    launcher:SetSize(LAUNCHER_SIZE, LAUNCHER_SIZE)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    launcher:RegisterForDrag("LeftButton")
    local position = Settings().vignetteRadarLauncherPosition
    launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        type(position) == "table" and tonumber(position.x) or 30,
        type(position) == "table" and tonumber(position.y) or -170)

    launcher.shadow = launcher:CreateTexture(nil, "BACKGROUND")
    launcher.shadow:SetSize(LAUNCHER_SIZE, LAUNCHER_SIZE)
    launcher.shadow:SetPoint("CENTER", 1, -1)
    launcher.shadow:SetTexture(CIRCLE_TEXTURE)
    launcher.shadow:SetVertexColor(0, 0, 0, 0.68)
    launcher.halo = launcher:CreateTexture(nil, "BACKGROUND", nil, 1)
    launcher.halo:SetSize(LAUNCHER_SIZE, LAUNCHER_SIZE)
    launcher.halo:SetPoint("CENTER")
    launcher.halo:SetTexture(CIRCLE_TEXTURE)
    launcher.halo:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.face = launcher:CreateTexture(nil, "BORDER")
    launcher.face:SetSize(LAUNCHER_SIZE - 6, LAUNCHER_SIZE - 6)
    launcher.face:SetPoint("CENTER")
    launcher.face:SetTexture(CIRCLE_TEXTURE)
    launcher.face:SetVertexColor(0.018, 0.055, 0.064, 0.98)
    launcher.alert = launcher:CreateTexture(nil, "ARTWORK")
    launcher.alert:SetSize(LAUNCHER_SIZE - 1, LAUNCHER_SIZE - 1)
    launcher.alert:SetPoint("CENTER")
    launcher.alert:SetTexture(CIRCLE_TEXTURE)
    launcher.alert:SetVertexColor(RED[1], RED[2], RED[3], 1)
    launcher.alert:SetAlpha(0)
    launcher.ring = CreateLauncherRing(launcher, LAUNCHER_RADIUS, 0.76)
    launcher.innerRing = CreateLauncherRing(launcher, 13, 0.20)

    launcher.sweepLines = {}
    for index = 1, 4 do
        local line = launcher:CreateLine(nil, "OVERLAY")
        line:SetThickness(index == 1 and 1.8 or 1)
        line:SetStartPoint("CENTER", launcher, "CENTER", 0, 0)
        launcher.sweepLines[index] = line
    end
    launcher.centerGlow = launcher:CreateTexture(nil, "OVERLAY")
    launcher.centerGlow:SetSize(11, 11)
    launcher.centerGlow:SetPoint("CENTER")
    launcher.centerGlow:SetTexture(CIRCLE_TEXTURE)
    launcher.centerGlow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
    launcher.center = launcher:CreateTexture(nil, "OVERLAY", nil, 1)
    launcher.center:SetSize(5, 5)
    launcher.center:SetPoint("CENTER")
    launcher.center:SetTexture(CIRCLE_TEXTURE)
    launcher.center:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.miniBlips = {}
    for index = 1, 3 do
        local dot = launcher:CreateTexture(nil, "OVERLAY", nil, 2)
        dot:SetSize(5, 5)
        dot:SetTexture(CIRCLE_TEXTURE)
        dot:Hide()
        launcher.miniBlips[index] = dot
    end
    launcher.status = launcher:CreateTexture(nil, "OVERLAY", nil, 3)
    launcher.status:SetSize(15, 15)
    launcher.status:SetPoint("BOTTOMRIGHT", -2, 2)
    launcher.status:SetTexture(CIRCLE_TEXTURE)
    launcher.status:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.count = Text(launcher, 8, "")
    launcher.count:SetPoint("CENTER", launcher.status, "CENTER", 0, 0)
    launcher.count:SetJustifyH("CENTER")
    launcher.shock = launcher:CreateTexture(nil, "OVERLAY", nil, 4)
    launcher.shock:SetPoint("CENTER")
    launcher.shock:SetTexture(CIRCLE_TEXTURE)
    launcher.shock:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.shock:Hide()

    launcher:SetScript("OnEnter", function(self)
        self._hovered = true
        LauncherTooltip(self)
    end)
    launcher:SetScript("OnLeave", function(self)
        self._hovered = false
        self._pressed = false
        if GameTooltip then GameTooltip:Hide() end
    end)
    launcher:SetScript("OnMouseDown", function(self) self._pressed = true end)
    launcher:SetScript("OnMouseUp", function(self) self._pressed = false end)
    launcher:SetScript("OnDragStart", function(self)
        self._dragging = true
        self._suppressClick = true
        self:StartMoving()
        if GameTooltip then GameTooltip:Hide() end
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._dragging = false
        SaveLauncherPosition()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() self._suppressClick = false end)
        else
            self._suppressClick = false
        end
    end)
    launcher:SetScript("OnClick", function(self, button)
        if self._suppressClick or self._dragging then return end
        self._shock = 0.001
        PlayLauncherSound()
        if button == "RightButton" then
            preview = not preview
            manualPanelState = preview and true or nil
            RefreshRadar(true)
        else
            ToggleRadarPanel()
        end
    end)
    launcher:SetScript("OnUpdate", function(self, elapsed)
        UpdateLauncherSweep(self, elapsed)
        self._targetElapsed = (self._targetElapsed or 0) + elapsed
        self._scanElapsed = (self._scanElapsed or 0) + elapsed
        if self._targetElapsed >= 0.10 then
            self._targetElapsed = 0
            UpdateLauncher(0, true)
        end
        if self._scanElapsed >= RESCAN_SECONDS and (not panel or not panel:IsShown()) then
            self._scanElapsed = 0
            RefreshRadar(true)
        end
    end)
    UpdateLauncher(0, true)
    return launcher
end

local function EnsurePanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "WaffleHouseVignetteRadar", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    Surface(panel)
    local position = Settings().vignetteRadarPosition
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        type(position) == "table" and tonumber(position.x) or 30,
        type(position) == "table" and tonumber(position.y) or -520)

    panel.title = Text(panel, 11, "VIGNETTE RADAR", true)
    panel.title:SetPoint("TOPLEFT", 12, -6)
    panel.summary = Text(panel, 8, "0 IN RANGE")
    panel.summary:SetPoint("TOPLEFT", 12, -21)
    panel.summary:SetJustifyH("LEFT")

    panel.drag = CreateFrame("Frame", nil, panel)
    panel.drag:SetPoint("TOPLEFT", 4, -3)
    panel.drag:SetSize(PANEL_W - 66, HEADER_H - 6)
    panel.drag:EnableMouse(true)
    panel.drag:RegisterForDrag("LeftButton")
    panel.drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel.drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); SavePosition() end)

    panel.legend = CreateFrame("Button", nil, panel)
    panel.legend:SetSize(24, 24)
    panel.legend:SetPoint("TOPRIGHT", -31, -5)
    panel.legend:SetAlpha(0.68)
    panel.legend:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    panel.legend:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    local legendColors = {
        { 1.00, 0.24, 0.20 },
        { 1.00, 0.68, 0.16 },
        { 0.67, 0.42, 1.00 },
    }
    panel.legend.dots = {}
    for index, color in ipairs(legendColors) do
        local dot = panel.legend:CreateTexture(nil, "ARTWORK")
        dot:SetSize(4, 4)
        dot:SetPoint("LEFT", 4, 12 - (index * 6))
        dot:SetTexture(CIRCLE_TEXTURE)
        dot:SetVertexColor(color[1], color[2], color[3], 1)
        panel.legend.dots[index] = dot
        local line = panel.legend:CreateTexture(nil, "ARTWORK")
        line:SetSize(9, 1)
        line:SetPoint("LEFT", 11, 12 - (index * 6))
        line:SetColorTexture(0.68, 0.72, 0.74, 0.72)
    end
    panel.legend:SetScript("OnClick", function(self)
        local legend = LegendAPI()
        if not (legend and type(legend.Toggle) == "function") then return end
        local ok, shown = pcall(legend.Toggle, panel)
        if ok then self:SetAlpha(shown and 1 or 0.68) end
    end)
    panel.legend:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Radar legend and spotlight", 1, 1, 1)
        GameTooltip:AddLine("Filter vignette types or spotlight one category while keeping the others as dim context.",
            0.65, 0.80, 0.77, true)
        GameTooltip:Show()
    end)
    panel.legend:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel.close = CreateFrame("Button", nil, panel)
    panel.close:SetSize(24, 24)
    panel.close:SetPoint("TOPRIGHT", -5, -5)
    panel.close.label = Text(panel.close, 16, "×")
    panel.close.label:SetAllPoints()
    panel.close.label:SetJustifyH("CENTER")
    panel.close:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    panel.close:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    panel.close:SetScript("OnClick", function()
        manualPanelState = false
        preview = false
        panel:Hide()
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
        if UpdateLauncher then UpdateLauncher(0, true) end
    end)
    panel.close:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tuck away radar", 1, 1, 1)
        GameTooltip:AddLine("The launcher stays ready so you can bring the radar back without disabling detection.",
            0.72, 0.76, 0.78, true)
        GameTooltip:Show()
    end)
    panel.close:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel.field = CreateFrame("Frame", nil, panel)
    panel.field:SetSize(FIELD_SIZE, FIELD_SIZE)
    panel.field:SetPoint("BOTTOM", 0, 9)
    panel.field:SetFrameLevel(panel:GetFrameLevel() + 1)
    panel.field.background = panel.field:CreateTexture(nil, "BACKGROUND")
    panel.field.background:SetAllPoints()
    panel.field.background:SetTexture(CIRCLE_TEXTURE)
    panel.field.background:SetVertexColor(0.015, 0.022, 0.028, 0.94)
    panel.field.halo = panel.field:CreateTexture(nil, "BACKGROUND", nil, -1)
    panel.field.halo:SetPoint("CENTER")
    panel.field.halo:SetSize(FIELD_SIZE + 4, FIELD_SIZE + 4)
    panel.field.halo:SetTexture(CIRCLE_TEXTURE)
    panel.field.halo:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
    panel.outerRing = AddRing(panel.field, FIELD_RADIUS, 0.44)
    panel.middleRing = AddRing(panel.field, FIELD_RADIUS * (2 / 3), 0.23)
    panel.innerRing = AddRing(panel.field, FIELD_RADIUS / 3, 0.18)

    panel.innerLabel = Text(panel.field, 8, "150y")
    panel.innerLabel:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.55)
    panel.innerLabel:SetPoint("CENTER", 0, -(FIELD_RADIUS / 3))
    panel.outerLabel = Text(panel.field, 8, "300y")
    panel.outerLabel:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.55)
    panel.outerLabel:SetPoint("CENTER", 0, -(FIELD_RADIUS * 2 / 3))

    panel.cardinals = {}
    for index, definition in ipairs(CARDINALS) do
        local label = Text(panel.field, 9, definition.text)
        label:SetTextColor(0.65, 0.69, 0.71, 0.82)
        label:SetJustifyH("CENTER")
        panel.cardinals[index] = label
    end
    panel.direction = panel.field:CreateTexture(nil, "ARTWORK")
    panel.direction:SetSize(2, 18)
    panel.direction:SetPoint("BOTTOM", panel.field, "CENTER", 0, 3)
    panel.direction:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    panel.playerGlow = panel.field:CreateTexture(nil, "OVERLAY")
    panel.playerGlow:SetSize(14, 14)
    panel.playerGlow:SetPoint("CENTER")
    panel.playerGlow:SetTexture(CIRCLE_TEXTURE)
    panel.playerGlow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
    panel.player = panel.field:CreateTexture(nil, "OVERLAY", nil, 1)
    panel.player:SetSize(7, 7)
    panel.player:SetPoint("CENTER")
    panel.player:SetTexture(CIRCLE_TEXTURE)
    panel.player:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    panel.blips, panel.freeBlips, panel.blipByKey = {}, {}, {}

    panel:SetScript("OnUpdate", function(self, elapsed)
        self._renderElapsed = (self._renderElapsed or 0) + elapsed
        self._scanElapsed = (self._scanElapsed or 0) + elapsed
        if self._scanElapsed >= RESCAN_SECONDS then
            self._scanElapsed = 0
            RefreshRadar(true)
            if not self:IsShown() then return end
        end
        if self._renderElapsed >= UPDATE_SECONDS then
            self._renderElapsed = 0
            Render()
        end
    end)
    panel:SetScript("OnHide", function()
        ReleaseAllBlips()
        panel.legend:SetAlpha(0.68)
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
    end)
    RenderCardinals(0)
    return panel
end

ScanVignettes = function(mapID)
    activeMapID = mapID
    activeTargets = CollectVignettes(mapID)
end

RefreshRadar = function(rescan)
    local settings = Settings()
    if settings.vignetteRadarLauncherVisible ~= false then
        EnsureLauncher():Show()
    elseif launcher then
        launcher:Hide()
    end
    if rescan then ScanVignettes(CurrentMapID()) end
    if settings.vignetteRadarEnabled ~= true and not preview then
        if panel then panel:Hide() end
        if launcher then UpdateLauncher(0, true) end
        return
    end
    if manualPanelState == false then
        if panel then panel:Hide() end
    elseif manualPanelState == true or preview or settings.vignetteRadarHideWhenEmpty == false or #activeTargets > 0 then
        EnsurePanel():Show()
        Render()
    elseif panel then
        panel:Hide()
    end
    if launcher then UpdateLauncher(0, true) end
end

addon.RefreshVignetteRadar = function() RefreshRadar(true) end
addon.VignetteRadarAPI = {
    GetTargets = function() return activeTargets end,
    GetPanel = function() return panel end,
    GetLauncher = function() return launcher end,
    IsPreviewing = function() return preview end,
    Refresh = function(rescan) RefreshRadar(rescan == true) end,
    RefreshPresentation = function()
        if panel and panel:IsShown() then Render() end
        if launcher then UpdateLauncher(0, true) end
    end,
}

do
    local legend = LegendAPI()
    if legend and type(legend.ApplyDefaults) == "function" then pcall(legend.ApplyDefaults, Settings()) end
    if legend and type(legend.SetChangeCallback) == "function" then
        legend.SetChangeCallback(function()
            if panel and panel:IsShown() then Render() end
            if launcher then UpdateLauncher(0, true) end
        end)
    end
end

function addon.BuildVignetteRadarOptions(parent, y)
    local W, row, h = EllesmereUI.Widgets
    _, h = W:SectionHeader(parent, "VIGNETTE RADAR", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Enable Vignette Radar",
            tooltip = "Show a compact heading-up field for locations Blizzard is currently exposing as minimap vignettes. It does not reveal hidden objects or use a location database.",
            getValue = function() return Settings().vignetteRadarEnabled == true end,
            setValue = function(value)
                Settings().vignetteRadarEnabled = value == true
                manualPanelState = nil
                if not value then preview = false end
                RefreshRadar(true)
            end,
        },
        {
            type = "toggle",
            text = "Hide When Empty",
            tooltip = "Keep the radar out of the way until at least one active minimap vignette has a usable position.",
            getValue = function() return Settings().vignetteRadarHideWhenEmpty ~= false end,
            setValue = function(value)
                Settings().vignetteRadarHideWhenEmpty = value == true
                RefreshRadar(true)
            end,
        }); y = y - h
    row, h = W:DualRow(parent, y,
        {
            type = "dropdown",
            text = "Radar Range",
            values = { ["150"] = "150 yards", ["300"] = "300 yards", ["450"] = "450 yards", ["600"] = "600 yards" },
            order = { "150", "300", "450", "600" },
            tooltip = "Set the radius represented by the outer ring. Dots use map-to-world coordinates so distance is measured in yards rather than raw map percentages.",
            getValue = function() return tostring(Settings().vignetteRadarRange or 450) end,
            setValue = function(value)
                Settings().vignetteRadarRange = tonumber(value) or 450
                RefreshRadar(false)
            end,
        },
        {
            type = "toggle",
            text = "Show Radar Launcher",
            tooltip = "Keep the animated, draggable radar instrument available. Left-click it to show or tuck away the full field; right-click it for a layout preview.",
            getValue = function() return Settings().vignetteRadarLauncherVisible ~= false end,
            setValue = function(value)
                Settings().vignetteRadarLauncherVisible = value == true
                RefreshRadar(false)
            end,
        }); y = y - h
    row, h = W:DualRow(parent, y,
        {
            type = "labeledButton",
            text = "Panel Preview",
            buttonText = preview and "Hide Preview" or "Preview",
            tooltip = "Show the radar with two clearly labeled sample blips so you can place and inspect it without waiting for a live vignette.",
        },
        {
            type = "labeledButton",
            text = "Radar Positions",
            buttonText = "Reset Both",
            tooltip = "Return the full radar and its draggable launcher to their default positions on the left side of the screen.",
        }); y = y - h
    local previewButton = row and row._leftRegion and row._leftRegion._control
    local resetButton = row and row._rightRegion and row._rightRegion._control
    if previewButton then previewButton:SetScript("OnClick", function()
        preview = not preview
        manualPanelState = preview and true or nil
        RefreshRadar(true)
    end) end
    if resetButton then resetButton:SetScript("OnClick", function()
        Settings().vignetteRadarPosition = nil
        Settings().vignetteRadarLauncherPosition = nil
        if panel then panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -520) end
        if launcher then launcher:ClearAllPoints(); launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -170) end
    end) end
    return y
end

SLASH_WAFFLEHOUSEVIGNETTERADAR1 = "/whradar"
SlashCmdList.WAFFLEHOUSEVIGNETTERADAR = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "preview" then
        preview = not preview
        manualPanelState = preview and true or nil
    elseif message == "off" then
        Settings().vignetteRadarEnabled = false
        preview = false
        manualPanelState = nil
    elseif message == "on" then
        Settings().vignetteRadarEnabled = true
        preview = false
        manualPanelState = true
    else
        ToggleRadarPanel()
        return
    end
    RefreshRadar(true)
end

local events = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED",
}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    RefreshRadar(true)
    if event == "PLAYER_LOGIN" and C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() RefreshRadar(true) end)
    end
end)
