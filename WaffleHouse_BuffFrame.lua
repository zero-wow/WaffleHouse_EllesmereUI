local _, addon = ...
if type(addon) ~= "table" then return end

-- Native expansion is not an addon-safe operation on Retail. Calling Blizzard's
-- SetBuffsExpandedState also calls Update, which can install the native OnUpdate
-- under addon taint. Later secret aura values then fail in that handler even if
-- the original call happened outside combat. pcall/restriction guards do not
-- prevent this. Leave native fields, scripts, buttons and anchors untouched.
-- Saved rules remain in BuffFrameRules for a future supported implementation.
addon.BuffFrameAutomationAvailable = false

function addon.RefreshBuffFrameControls()
    -- Keep the settings-page entry point without mutating any Blizzard frame.
    -- Existing session taint must be cleared with /reload, not a frame reset.
end

function addon.GetBuffFrameStatus()
    return "Automatic collapse/expand is unavailable because it taints Blizzard's aura updates. "
        .. "Saved rules are preserved but do not run. Use the native collapse/expand button and Blizzard Edit Mode for placement. "
        .. "Reload the UI after installing this fix to clear existing taint."
end
