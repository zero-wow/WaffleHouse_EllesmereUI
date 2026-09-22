-- Pure settings and policy rules for Blizzard's native BuffFrame controls.
-- The runtime owns all frame/event work; this module only prepares data.
local addonName, addon = ...
if type(addon) ~= "table" then return end

local R = {}
addon.BuffFrameRules = R

R.ConditionLabels = {
    always = "Always",
    hover = "While Hovering",
    combat = "In Combat",
    outOfCombat = "Out of Combat",
    group = "In a Group",
    solo = "Solo",
    mounted = "Mounted",
    instance = "In an Instance",
    login = "At Login",
}
R.ConditionOrder = { "always", "hover", "combat", "outOfCombat", "group", "solo", "mounted", "instance", "login" }

R.ActionLabels = {
    collapse = "Collapse",
    expand = "Expand",
    own = "Own-Cast Buffs Only",
    normal = "Native Collapsed Buffs",
}
R.ActionOrder = { "collapse", "expand", "own", "normal" }

R.AnchorLabels = {
    TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
R.AnchorOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

R.TargetLabels = {
    player = "Player Frame",
    target = "Target Frame",
    focus = "Focus Frame",
    screen = "Screen",
    custom = "Custom Frame",
}
R.TargetOrder = { "player", "target", "focus", "screen", "custom" }

local DEFAULT_RULES = {
    { id = 1, enabled = true, condition = "hover", action = "expand", delay = 0 },
    { id = 2, enabled = true, condition = "always", action = "collapse", delay = 15 },
}

local function IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeBoolean(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function SafeTable(value)
    if IsSecret(value) or type(value) ~= "table" then return nil end
    return value
end

local function Round(value)
    if value < 0 then return math.ceil(value - 0.5) end
    return math.floor(value + 0.5)
end

local function Integer(value, fallback, minimum, maximum)
    value = SafeNumber(value)
    if not value then return fallback end
    value = Round(value)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Allowed(value, labels, fallback)
    value = SafeString(value)
    return value and labels[value] and value or fallback
end

local function DefaultRules()
    local rules = {}
    for i = 1, #DEFAULT_RULES do
        local source = DEFAULT_RULES[i]
        rules[i] = { id = source.id, enabled = source.enabled, condition = source.condition,
            action = source.action, delay = source.delay }
    end
    return rules
end

local function NormalizeRules(settings)
    local existing = SafeTable(settings.rules)
    if not existing then
        settings.rules = DefaultRules()
        settings.nextRuleID = 3
        return
    end

    -- An empty array is a deliberate user choice, so only an absent/malformed
    -- rules value receives defaults.
    local used, largest = {}, 0
    local count, write = #existing, 1
    for index = 1, count do
        local source = SafeTable(existing[index])
        if source then
            local id = Integer(source.id, nil, 1, 2147483647)
            if not id or used[id] then
                id = largest + 1
                while used[id] do id = id + 1 end
            end
            used[id] = true
            if id > largest then largest = id end

            -- Keep unsupported action/condition strings intact for the UI and
            -- SavedVariables. Evaluate deliberately ignores them.
            -- Mutate valid entries rather than replacing them: UI callbacks
            -- can safely retain a rule table across a 10Hz evaluation pass.
            source.id = id
            source.enabled = SafeBoolean(source.enabled) == true
            source.condition = SafeString(source.condition)
            source.action = SafeString(source.action)
            source.delay = Integer(source.delay, 0, 0, 300)
            if write ~= index then existing[write] = source end
            write = write + 1
        end
    end
    -- Remove malformed array entries only after compacting the valid values
    -- forward. This preserves both the rules array and surviving rule-table
    -- identities instead of allocating replacements on every evaluation.
    for index = write, count do existing[index] = nil end
    settings.nextRuleID = Integer(settings.nextRuleID, largest + 1, 1, 2147483647)
    if settings.nextRuleID <= largest then settings.nextRuleID = largest + 1 end
end

local function NormalizeSettings(settings)
    settings = SafeTable(settings)
    if not settings then return nil end

    if SafeBoolean(settings.enabled) == nil then settings.enabled = false end
    if SafeBoolean(settings.anchorEnabled) == nil then settings.anchorEnabled = true end
    settings.target = Allowed(settings.target, R.TargetLabels, "player")
    settings.customFrame = SafeString(settings.customFrame) or ""
    settings.point = Allowed(settings.point, R.AnchorLabels, "RIGHT")
    settings.relativePoint = Allowed(settings.relativePoint, R.AnchorLabels, "LEFT")
    settings.x = Integer(settings.x, -12, -2000, 2000)
    settings.y = Integer(settings.y, 0, -2000, 2000)
    if SafeBoolean(settings.ownOnlyCollapsed) == nil then settings.ownOnlyCollapsed = true end
    if SafeBoolean(settings.euiSkin) == nil then settings.euiSkin = false end
    NormalizeRules(settings)
    return settings
end

function R.GetSettings()
    local root = type(addon.GetSettings) == "function" and addon.GetSettings() or nil
    root = SafeTable(root)
    if not root then
        -- A broken host settings provider cannot be repaired here. Return an
        -- independent usable value rather than exposing malformed data.
        return NormalizeSettings({})
    end
    if not SafeTable(root.buffFrame) then root.buffFrame = {} end
    return NormalizeSettings(root.buffFrame)
end

local function Matches(condition, context)
    context = SafeTable(context) or {}
    if condition == "always" then return true end
    if condition == "hover" then return SafeBoolean(context.hover) == true end
    if condition == "combat" then return SafeBoolean(context.combat) == true end
    if condition == "outOfCombat" then return SafeBoolean(context.combat) == false end
    if condition == "group" then return SafeBoolean(context.group) == true end
    if condition == "solo" then return SafeBoolean(context.group) == false end
    if condition == "mounted" then return SafeBoolean(context.mounted) == true end
    if condition == "instance" then return SafeBoolean(context.instance) == true end
    if condition == "login" then return SafeBoolean(context.login) == true end
    return false
end

function R.Evaluate(settings, context)
    settings = NormalizeSettings(settings) or R.GetSettings()
    local result = {
        expanded = nil,
        ownOnly = settings.ownOnlyCollapsed,
        euiSkin = settings.euiSkin,
        delay = nil,
        stateRule = nil,
        stateCondition = nil,
        filterRule = nil,
    }
    for index = 1, #settings.rules do
        local rule = settings.rules[index]
        if rule.enabled == true and Matches(rule.condition, context) then
            if (rule.action == "collapse" or rule.action == "expand") and not result.stateRule then
                result.expanded = rule.action == "expand"
                result.delay = rule.action == "collapse" and rule.delay or nil
                result.stateRule = rule.id
                result.stateCondition = rule.condition
            elseif (rule.action == "own" or rule.action == "normal") and rule.condition ~= "login" and not result.filterRule then
                result.ownOnly = rule.action == "own"
                result.filterRule = rule.id
            end
        end
    end
    return result
end

local function MutableSettings(settings)
    if SafeTable(settings) then return NormalizeSettings(settings) end
    return R.GetSettings()
end

function R.AddRule(settings)
    settings = MutableSettings(settings)
    local id = settings.nextRuleID
    local used = {}
    for i = 1, #settings.rules do used[settings.rules[i].id] = true end
    while used[id] do id = id + 1 end
    local rule = { id = id, enabled = true, condition = "always", action = "collapse", delay = 15 }
    settings.rules[#settings.rules + 1] = rule
    settings.nextRuleID = id + 1
    return rule
end

function R.RemoveRule(settings, id)
    settings = MutableSettings(settings)
    id = Integer(id, nil, 1, 2147483647)
    if not id then return false end
    for index = 1, #settings.rules do
        if settings.rules[index].id == id then
            table.remove(settings.rules, index)
            return true
        end
    end
    return false
end

function R.MoveRule(settings, id, direction)
    settings = MutableSettings(settings)
    id = Integer(id, nil, 1, 2147483647)
    direction = SafeNumber(direction)
    if not id or (direction ~= -1 and direction ~= 1) then return false end
    for index = 1, #settings.rules do
        if settings.rules[index].id == id then
            local target = index + direction
            if target < 1 or target > #settings.rules then return false end
            settings.rules[index], settings.rules[target] = settings.rules[target], settings.rules[index]
            return true
        end
    end
    return false
end
