local _, addon = ...
if type(addon) ~= "table" then return end

-- Only expose the supported repair. Saved automation rules are retained by
-- BuffFrameRules, but their disabled runtime must not advertise working controls.
function addon.BuildBuffFrameOptions(parent, y)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return y end

    local _, h = W:SectionHeader(parent, "BUFF FRAME", y); y = y - h
    _, h = W:DualRow(parent, y, {
        type = "labeledButton",
        text = "Position with Blizzard Edit Mode",
        buttonText = "Repair Missing Anchor",
        width = 180,
        tooltip = "Move your buffs with Blizzard Edit Mode and use Blizzard's button to collapse or expand them. Repair Missing Anchor fixes only a saved Buff Frame position that points to the removed PlayerBuffsMover, after backing up the layouts. Close Edit Mode and leave combat first.",
        disabled = function()
            return type(addon.RepairBuffFrameAnchor) ~= "function"
                or (InCombatLockdown and InCombatLockdown())
        end,
        disabledTooltip = function()
            if type(addon.RepairBuffFrameAnchor) ~= "function" then return "Buff anchor repair is unavailable." end
            return "Leave combat before repairing the saved buff position."
        end,
        onClick = function()
            if InCombatLockdown and InCombatLockdown() then return end
            if type(addon.RepairBuffFrameAnchor) == "function" then addon.RepairBuffFrameAnchor(true) end
        end,
    }); y = y - h
    return y
end
