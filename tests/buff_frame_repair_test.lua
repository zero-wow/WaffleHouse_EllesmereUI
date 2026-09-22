local SOURCE = arg[1] or "WaffleHouse_BuffFrameRepair.lua"
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function anchor(target)
    return { point = "RIGHT", relativeTo = target, relativePoint = "LEFT", offsetX = 0, offsetY = 0 }
end
local function buff(target)
    return { system = 6, systemIndex = 1, anchorInfo = anchor(target), isInDefaultPosition = false,
        settings = { { setting = 2, value = 1 }, { setting = 5, value = 40 } }, extra = "preserved" }
end
local function fixture(options)
    options = options or {}
    local dual = buff("PlayerBuffsMover"); dual.anchorInfo2 = anchor("UIParent")
    local otherSystem = buff("PlayerBuffsMover"); otherSystem.systemIndex = 2
    local raw = { activeLayout = 3, layouts = {
        { layoutName = "Main", layoutType = 1, systems = { buff("PlayerBuffsMover"), otherSystem } },
        { layoutName = "Character", layoutType = 2, systems = { buff("UIParent") } },
        { layoutName = "Dual", layoutType = 2, systems = { dual } },
    } }
    local presets = {
        { layoutName = "Modern", layoutType = 0, layoutIndex = 1, systems = { buff("UIParent") } },
        { layoutName = "Classic", layoutType = 0, layoutIndex = 2, systems = { buff("UIParent") } },
    }
    local state = { raw = raw, original = copy(raw), presets = presets, timers = {}, messages = {},
        saves = 0, applies = 0, reads = 0, root = { buffFrame = { enabled = true, rules = { "keep" } } } }
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:UnregisterEvent(name) self.events[name] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    local function forbidden() error("must not access or mutate the native buff frame") end
    local env = setmetatable({
        BuffFrame = setmetatable({}, { __index = forbidden, __newindex = forbidden }),
        Enum = { EditModeSystem = { AuraFrame = 6 }, EditModeAuraFrameSystemIndices = { BuffFrame = 1 },
            EditModeLayoutType = { Preset = 0 } },
        CreateFrame = function() return frame end,
        C_Timer = { After = function(_, fn) state.timers[#state.timers + 1] = fn end },
        SlashCmdList = {},
        InCombatLockdown = function() return options.combat == true end,
        EditModeManagerFrame = {
            IsEditModeActive = function() return options.editing == true end,
            HasActiveChanges = function() return options.dirty == true end,
        },
        EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return presets end },
        print = function(message) state.messages[#state.messages + 1] = message end,
    }, { __index = _G })
    env.C_EditMode = {
        GetLayouts = function() state.reads = state.reads + 1; return state.raw end,
        SaveLayouts = function(info)
            state.saves = state.saves + 1
            assert(equal(raw, state.original), "repair must not mutate the API's original data")
            assert(equal(state.root.buffFrameAnchorRepairBackup, state.original), "backup must precede saving")
            assert(info.activeLayout == 3, "saving must preserve selection")
            assert(#info.layouts == 5 and equal(info.layouts[1], presets[1]) and equal(info.layouts[2], presets[2]),
                "save must include Blizzard's presets before custom layouts")
            if options.failSave then error("save rejected") end
            if not options.ignoreSave then
                state.raw = copy(info)
                table.remove(state.raw.layouts, 1); table.remove(state.raw.layouts, 1)
            end
        end,
        SetActiveLayout = function(id)
            state.applies = state.applies + 1
            assert(id == state.raw.activeLayout, "repair must not switch the selected layout")
            assert(not options.combat and not options.editing, "do not reapply in combat or Edit Mode")
        end,
    }
    state.env, state.frame = env, frame
    state.addon = { GetSettings = function() return state.root end }
    assert(loadfile(SOURCE, "t", env))("WaffleHouse_EllesmereUI", state.addon)
    function state:flush()
        local rounds = 0
        while #self.timers > 0 do
            rounds = rounds + 1; assert(rounds < 10, "repair must not poll or retry")
            local ready = self.timers; self.timers = {}
            for _, fn in ipairs(ready) do fn() end
        end
    end
    return state
end

local s = fixture()
assert(s.saves == 0 and s.reads == 0, "loading must wait for login")
s.frame.scripts.OnEvent(s.frame, "PLAYER_LOGIN"); s:flush()
assert(not s.frame.events.PLAYER_LOGIN and s.saves == 1 and s.applies == 0, "startup repair must save once without mutating live frames")
local expected = copy(s.original)
expected.layouts[1].systems[1].anchorInfo = {
    point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = -255, offsetY = -10,
}
assert(equal(s.raw, expected), "only the broken primary Buff Frame anchor may change")
assert(equal(s.root.buffFrameAnchorRepairBackup, s.original), "the pre-repair backup must be exact")
assert(s.root.buffFrame.enabled and s.root.buffFrame.rules[1] == "keep", "legacy preferences must remain unchanged")
s.env.SlashCmdList.WAFFLEHOUSEBUFFREPAIR(); s:flush()
assert(s.saves == 1 and s.applies == 0, "re-running after success must not save again")
assert(equal(s.root.buffFrameAnchorRepairBackup, s.original), "a repeated repair must not replace the backup")

for _, key in ipairs({ "combat", "editing", "dirty" }) do
    local options = {}; options[key] = true
    s = fixture(options)
    assert(s.addon.RepairBuffFrameAnchor(true) == false and s.reads == 0 and s.saves == 0, key .. " must block the repair")
end
s = fixture({ failSave = true })
assert(s.addon.RepairBuffFrameAnchor(true) == false)
s:flush()
assert(s.saves == 1 and s.applies == 0 and equal(s.raw, s.original), "rejected save must not reapply or retry")
assert(s.root.buffFrameAnchorRepairBackup, "rejected save must retain the backup")
s = fixture({ ignoreSave = true })
s.addon.RepairBuffFrameAnchor(true); s:flush()
assert(s.applies == 0 and s.messages[#s.messages]:find("not confirmed", 1, true), "unconfirmed writes must not claim repair or reapply")
s = fixture()
s.env.EditModePresetLayoutManager = nil
assert(not s.addon.RepairBuffFrameAnchor(true) and s.saves == 0, "missing presets must never produce a malformed save")
s = fixture()
s.addon.RepairBuffFrameAnchor(true)
assert(not s.addon.RepairBuffFrameAnchor(true) and s.saves == 1, "pending verification must block duplicate submissions")
s:flush()
local combatDuringVerification = {}
s = fixture(combatDuringVerification)
s.addon.RepairBuffFrameAnchor(true)
combatDuringVerification.combat = true
s:flush()
assert(s.applies == 0 and s.messages[#s.messages]:find("/reload", 1, true), "new combat must defer application after a confirmed save")
print("buff_frame_repair_test: ok")
