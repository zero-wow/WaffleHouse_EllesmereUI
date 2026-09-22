local _, addon = ...

-- Read the current invitation, never a fixed weekly guest or column order.
local Rules = {}
addon.SoireeRules = Rules
Rules.favorItemID = 238987
Rules.factions = {
    { id = 2711, name = "Magisters" },
    { id = 2712, name = "Blood Knights" },
    { id = 2713, name = "Farstriders" },
    { id = 2714, name = "Shades of the Row" },
}

function Rules.IsFocus(value)
    if value == "favor" then return true end
    for _, faction in ipairs(Rules.factions) do
        if value == faction.id then return true end
    end
    return false
end

function Rules.FactionName(id)
    local info = C_Reputation and C_Reputation.GetFactionDataByID
        and C_Reputation.GetFactionDataByID(id)
    if info and info.name and info.name ~= "" then return info.name end
    for _, faction in ipairs(Rules.factions) do
        if faction.id == id then return faction.name end
    end
    return tostring(id)
end

function Rules.FocusName(focus)
    return focus == "favor" and "Extra Favor" or Rules.FactionName(focus)
end

local function Plain(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
        :gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FactionForOption(option)
    local name = Plain(option.subHeader)
    for _, faction in ipairs(Rules.factions) do
        if name == Rules.FactionName(faction.id) or name == faction.name then
            return faction.id
        end
    end
end

function Rules.Evaluate(choice, focus)
    if not (type(choice) == "table" and type(choice.options) == "table"
        and #choice.options == 4) then return end
    focus = Rules.IsFocus(focus) and focus or "favor"
    local model = { entries = {}, byID = {}, focus = focus }
    local seen = {}
    for _, option in ipairs(choice.options) do
        if type(option) ~= "table" then return end
        local factionID = FactionForOption(option)
        -- All four named court factions must be present. This helper must not
        -- attach to unrelated PlayerChoice content with similar rewards.
        if not factionID or seen[factionID] or type(option.id) ~= "number"
            or model.byID[option.id] then return end
        seen[factionID] = true
        local button = type(option.buttons) == "table" and #option.buttons == 1 and option.buttons[1]
        if type(button) ~= "table" then button = nil end
        local entry = {
            optionID = option.id, factionID = factionID, name = Plain(option.header),
            enabled = option.disabledOption ~= true and button ~= nil
                and button.disabled ~= true and button.hideButtonShowText ~= true,
            favor = 0, rep = {},
        }
        local rewards = option.rewardInfo or {}
        for _, reward in ipairs(rewards.itemRewards or {}) do
            if reward.itemId == Rules.favorItemID and type(reward.quantity) == "number" then
                entry.favor = entry.favor + reward.quantity
            end
        end
        for _, reward in ipairs(rewards.repRewards or {}) do
            if type(reward.factionId) == "number" and type(reward.quantity) == "number" then
                entry.rep[reward.factionId] = (entry.rep[reward.factionId] or 0) + reward.quantity
            end
        end
        -- Some invitations put their changes in description text instead of
        -- structured rewards. Read only explicit signed values + faction names.
        for line in Plain(option.description):gmatch("[^\r\n]+") do
            local amount, name = line:match("^%s*([+-]%d+)%s+(.+)%s*$")
            if amount then
                name = Plain(name)
                for _, faction in ipairs(Rules.factions) do
                    if entry.rep[faction.id] == nil and
                        (name == Rules.FactionName(faction.id) or name == faction.name) then
                        entry.rep[faction.id] = tonumber(amount)
                    end
                end
            end
        end
        model.entries[#model.entries + 1] = entry
        model.byID[entry.optionID] = entry
    end

    if focus ~= "favor" then
        for _, entry in ipairs(model.entries) do
            if entry.enabled and entry.factionID == focus then
                model.recommendedID = entry.optionID
                model.reason = "Invites your chosen faction's guest and focuses this week's Runestone quest on "
                    .. Rules.FactionName(focus) .. "."
                break
            end
        end
        model.reason = model.reason or "Your chosen faction's invitation is currently unavailable."
    else
        local best, tied
        for _, entry in ipairs(model.entries) do
            if entry.enabled and entry.favor > 0 then
                if not best or entry.favor > best.favor then
                    best, tied = entry, false
                elseif entry.favor == best.favor then tied = true end
            end
        end
        if best and not tied then
            model.recommendedID = best.optionID
            model.reason = "This invitation offers the most Saltheril's Favor shown in the current choices. Favor unlocks additional faction tasks."
        else
            model.reason = "No single invitation offers more Favor in the available reward data. Choose a faction focus or compare the invitations."
        end
    end
    return model
end
