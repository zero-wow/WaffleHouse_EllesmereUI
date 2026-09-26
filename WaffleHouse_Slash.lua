local addonName, addon = ...

local routes = {
    ["config"] = { "General" },
    ["setting"] = { "General" },
    ["settings"] = { "General" },
    ["general"] = { "General" },
    ["adventure"] = { "Adventure" },
    ["automation"] = { "Automation" },
    ["bag"] = { "Bags" },
    ["bags"] = { "Bags" },
    ["frozen"] = { "Bags", "FROZEN SLOTS" },
    ["frozen items"] = { "Bags", "MANAGEMENT", "Frozen Slots" },
    ["recent items"] = { "Bags", "RECENT ITEMS" },
    ["bag assistant"] = { "Bags", "BAG ASSISTANT" },
    ["queue"] = { "Item Queue" },
    ["item queue"] = { "Item Queue" },
    ["item use"] = { "Item Queue" },
    ["vendor"] = { "Vendor" },
    ["currency"] = { "Vendor", "CURRENCY LEGEND" },
    ["currencies"] = { "Vendor", "CURRENCY LEGEND" },
    ["item view"] = { "Vendor", "ITEM VIEW" },
    ["interact key"] = { "Vendor", "INTERACT KEY" },
    ["shopping list"] = { "Vendor", "SHOPPING LIST & NOTES" },
    ["transmog"] = { "Adventure", "RANDOM TRANSMOG", "Outfit Change Reminder" },
    ["random transmog"] = { "Adventure", "RANDOM TRANSMOG", "Outfit Change Reminder" },
    ["random saved outfit"] = { "Adventure", "RANDOM TRANSMOG", "Outfit Change Reminder" },
    ["instant outfit button"] = { "Adventure", "RANDOM TRANSMOG", "Show Instant Outfit Button" },
    ["mount"] = { "Adventure", "MOUNTING" },
    ["mounting"] = { "Adventure", "MOUNTING" },
    ["auto mount locations"] = { "Adventure", "AUTO-MOUNT LOCATIONS" },
    ["flight"] = { "Adventure", "FLIGHT STYLE INDICATOR" },
    ["flight style"] = { "Adventure", "FLIGHT STYLE INDICATOR" },
    ["delve"] = { "Adventure", "DELVE COMPANION" },
    ["quests"] = { "Automation", "QUESTS & NPC DIALOGUE" },
    ["npc dialogue"] = { "Automation", "QUESTS & NPC DIALOGUE" },
    ["cinematics"] = { "Automation", "CINEMATICS & MERCHANTS" },
    ["ethereal tools"] = { "Automation", "ETHEREAL TOOLS" },
    ["resource watch"] = { "General", "RESOURCE WATCH" },
    ["skinning"] = { "General", "SKINNING" },
    ["databars"] = { "General", "DATABARS & COMPANIONS" },
}

local function Message(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff40d8c6Waffle House:|r " .. message)
    end
end

local function Normalize(input)
    return (tostring(input or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

SLASH_WAFFLEHOUSEOPTIONS1 = "/wh"
SlashCmdList.WAFFLEHOUSEOPTIONS = function(input)
    local key = Normalize(input)
    if key == "" then key = "config" end
    if key == "help" then
        Message("/wh config, adventure, queue, bags, automation, vendor, transmog, mount, flight, delve; section names also work. /wh transmog now readies the wardrobe button; /wh transmog status diagnoses it.")
        return
    end
    if key == "transmog now" or key == "random now" then
        if addon.RandomizeTransmogNow then addon.RandomizeTransmogNow() end
        return
    end
    if key == "transmog status" or key == "random status" then
        if addon.ReportRandomTransmogStatus then addon.ReportRandomTransmogStatus() end
        return
    end
    local route = routes[key]
    if not route then
        Message("Unknown setting. Type /wh help for available shortcuts.")
        return
    end
    C_Timer.After(0, function()
        if InCombatLockdown() then
            Message("Settings cannot open during combat. Try again afterward.")
            return
        end
        if addon.EnsureOptionsRegistered and not addon.EnsureOptionsRegistered() then
            Message("EllesmereUI settings are not ready yet. Try again in a moment.")
            return
        end
        if not (EllesmereUI and EllesmereUI.NavigateToElementSettings) then
            Message("EllesmereUI settings are unavailable.")
            return
        end
        EllesmereUI:NavigateToElementSettings(addonName, route[1], route[2], nil, route[3])
    end)
end
