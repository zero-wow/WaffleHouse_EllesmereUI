-- Mocked contract tests for the buff-check model.  Run with:
-- lua tests/buff_check_model_test.lua WaffleHouse_BuffCheck.lua
local SOURCE = arg[1] or "WaffleHouse_BuffCheck.lua"

local SECRET = {}
local combat, restricted = false, false
local auraCalls = 0
local auraCallsByUnit = {}
local auraInstanceCalls = 0
local guidCalls = 0
local playerGUID = "Player-1"
local known = {}
local units = {}
local auraByUnit = {}
local auraByInstance = {}

local function setUnit(token, values)
    units[token] = values
end
local function setAura(token, spellID, aura)
    auraByUnit[token] = auraByUnit[token] or {}
    auraByUnit[token][spellID] = aura
    if aura and aura.auraInstanceID then auraByInstance[token .. ":" .. aura.auraInstanceID] = aura end
end
local function clearAuras()
    auraByUnit = {}
    auraByInstance = {}
end

issecretvalue = function(value) return value == SECRET end
InCombatLockdown = function() return combat end
UnitExists = function(unit) return units[unit] and units[unit].exists ~= false end
UnitIsVisible = function(unit)
    local value = units[unit] and units[unit].visible
    if value == SECRET then return SECRET end
    return units[unit] and value ~= false
end
UnitGUID = function(unit)
    guidCalls = guidCalls + 1
    return units[unit] and units[unit].guid
end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitFullName = function(unit)
    local u = units[unit] or {}
    return u.name, u.realm
end
UnitClass = function(unit)
    local u = units[unit] or {}
    return u.class, u.class
end
UnitGroupRolesAssigned = function(unit) return units[unit] and units[unit].role or "NONE" end
UnitIsConnected = function(unit) return units[unit] and units[unit].connected ~= false end
UnitIsDeadOrGhost = function(unit) return units[unit] and units[unit].dead == true end
UnitIsUnit = function(a, b) return a == b end
IsInRaid = function() return units._raid == true end
GetNumGroupMembers = function() return units._raidCount or 0 end
GetNumSubgroupMembers = function() return units._partyCount or 0 end
IsPlayerSpell = function(id) return known[id] == true end
IsSpellKnown = IsPlayerSpell
GetSpellInfo = function(id) return "Spell " .. id end
C_Spell = { GetSpellName = function(id) return "Spell " .. id end }
C_Secrets = {
    ShouldAurasBeSecret = function() return restricted end,
    ShouldSpellAuraBeSecret = function(id) return id == 20707 and units._soulSecret == true end,
}
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, id)
        auraCalls = auraCalls + 1
        auraCallsByUnit[unit] = (auraCallsByUnit[unit] or 0) + 1
        return auraByUnit[unit] and auraByUnit[unit][id]
    end,
    GetAuraDataByAuraInstanceID = function(unit, instanceID)
        auraInstanceCalls = auraInstanceCalls + 1
        return auraByInstance[unit .. ":" .. instanceID]
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local list = units[unit] and units[unit].scan
        return list and list[index] or nil
    end,
}
EllesmereUI = { AuraKit = { AurasRestricted = function() return restricted end } }

local settings = {}
local addon = { GetSettings = function() return settings end }
assert(loadfile(SOURCE))("WaffleHouse_EllesmereUI", addon)
local B = assert(addon.BuffCheck)
local function Target(state, key)
    for _, target in ipairs(state.targets) do
        if target.def.key == key then return target end
    end
end

setUnit("player", { guid = playerGUID, name = "Player", class = "PRIEST", role = "HEALER" })
known[21562] = true
local defaults = B.GetSettings()
assert(defaults.enabled == true and defaults.collapsed == false and defaults.hideReady == true
    and defaults.onlyWhenNeeded == true and defaults.alwaysShowInGroup == false
    and defaults.groupedOnly == nil and type(defaults.situations) == "table")
assert(defaults.position.point == "TOPLEFT" and defaults.position.x == 30 and defaults.position.y == -240)
assert(type(defaults.assignments) == "table")
assert(B.groupDefs[2].auraIDs[2] == 432778 and B.groupDefs[3].auraIDs[2] == 432661)
assert(B.groupDefs[5].spellID == 364342 and B.targetDefs[4].noSelf == true)

-- A full 40-player raid is aggregated without adding the player twice.
units._raid, units._raidCount = true, 40
for i = 1, 40 do
    setUnit("raid" .. i, { guid = "Raid-" .. i, name = "Raid " .. i, class = i == 1 and "PRIEST" or "WARRIOR", role = "DAMAGER" })
end
setAura("raid1", 21562, { isFromPlayerOrPlayerPet = true })
local state = B.Collect()
assert(state.size == 40, "raid roster must cap at 40 without a duplicate player")
local fortitude = state.groups[1]
assert(fortitude.eligible == 40 and fortitude.covered == 1 and #fortitude.missing == 39)

-- The event driver uses the optimized path between roster/role/spell
-- boundaries.  A 40-player group must reuse every untouched member snapshot:
-- no new identity or aura API work occurs on a second presentation pass.
B.Invalidate(nil)
state = B.Collect(true)
assert(B.HasVisibilityWatch(), "an active multi-member roster must enable the cheap visibility watch")
local optimizedAuras, optimizedGUIDs = auraCalls, guidCalls
local cachedRoster = B.GetRoster(true)
assert(#cachedRoster == 40 and guidCalls == optimizedGUIDs,
    "optimized roster access must reuse the model snapshot without identity queries")
B.Collect(true)
assert(auraCalls == optimizedAuras and guidCalls == optimizedGUIDs,
    "optimized collection must not query untouched raid member identity or auras")

-- Visibility polling uses only availability probes.  It reports the changed
-- token but leaves the model untouched until the driver batches Invalidate.
units.raid4.visible = false
local visibleChanges = B.CheckVisibility()
assert(visibleChanges and visibleChanges.raid4, "visibility probe must identify only the changed roster token")
assert(auraCalls == optimizedAuras, "visibility probe must not query auras")
local raid4Before, raid5Before = auraCallsByUnit.raid4 or 0, auraCallsByUnit.raid5 or 0
B.Invalidate("raid4")
B.Collect(true)
assert((auraCallsByUnit.raid4 or 0) == raid4Before and (auraCallsByUnit.raid5 or 0) == raid5Before,
    "an unreadable invalidated member must not force untouched member aura reads")
units.raid4.visible = true
B.Invalidate("raid4")
B.Collect(true)

-- UNIT_AURA deltas skip an unrelated readable aura without enumerating the
-- unit.  Tracked removals and changed instances remain conservative.
setAura("raid3", 21562, { isFromPlayerOrPlayerPet = true, auraInstanceID = 301 })
B.Invalidate("raid3")
B.Collect(true)
local deltaCalls = auraInstanceCalls
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, addedAuras = { { spellId = 999999 } },
    updatedAuraInstanceIDs = {}, removedAuraInstanceIDs = {},
}) == false, "unrelated readable delta must not invalidate tracked auras")
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, addedAuras = { { spellId = 999999 } },
}) == false, "Retail sparse added-only deltas must still ignore unrelated auras")
assert(auraInstanceCalls == deltaCalls, "unrelated added aura must not fetch another aura instance")
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, removedAuraInstanceIDs = { 301 },
}) == true, "tracked aura removal must invalidate its unit")
auraByInstance["raid3:302"] = { spellId = 21562, auraInstanceID = 302 }
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, addedAuras = {}, updatedAuraInstanceIDs = { 302 }, removedAuraInstanceIDs = {},
}) == true and auraInstanceCalls == deltaCalls + 1, "changed tracked instance must be fetched and invalidate")
auraByInstance["raid3:303"] = { spellId = 999999, auraInstanceID = 303 }
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, addedAuras = {}, updatedAuraInstanceIDs = { 303 }, removedAuraInstanceIDs = {},
}) == false, "changed unrelated instance must not invalidate")
assert(B.AuraUpdateRelevant("raid3", nil) == true
    and B.AuraUpdateRelevant("raid3", {
        isFullUpdate = false, addedAuras = { SECRET }, updatedAuraInstanceIDs = {}, removedAuraInstanceIDs = {},
    }) == true
    and B.AuraUpdateRelevant("raid3", {
        isFullUpdate = false, addedAuras = SECRET,
    }) == true, "unknown or secret aura deltas must remain conservative")
B.Invalidate("raid3")
assert(B.AuraUpdateRelevant("raid3", {
    isFullUpdate = false, removedAuraInstanceIDs = { 999999 },
}) == true, "a removal after cache invalidation must remain conservative")
setAura("raid3", 21562, nil)
state = B.Collect(true)
assert(state.groups[1].covered == 1, "relevant removal followed by invalidation must refresh only that aura result")

-- Aura results cache until the driver invalidates an individual token.
local before = auraCalls
B.Collect()
assert(auraCalls == before, "unchanged Collect must reuse aura cache")
B.Invalidate("raid2")
B.Collect()
assert(auraCalls > before, "per-unit invalidation must rescan only its affected entry")

-- PLAYER and raid1 can refer to the same GUID.  A player UNIT_AURA invalidates
-- the matching raid-token cache as well.
units.raid1.guid = playerGUID
B.Invalidate(nil)
B.Collect()
before = auraCalls
B.Invalidate("player")
B.Collect()
assert(auraCalls > before, "player alias invalidation must clear matching raid-token cache")
units.raid1.guid = "Raid-1"
B.Invalidate(nil)

-- An assignment is keyed by the local character GUID and follows roster churn.
known[974] = true
local assignments = B.GetAssignments()
assignments.earth_shield = "Raid-2"
setAura("raid2", 974, { isFromPlayerOrPlayerPet = true })
B.Invalidate(nil)
state = B.Collect()
local earth = state.targets[1]
assert(earth.status == "ready" and earth.member.guid == "Raid-2")
units.raid2.visible = false
assert(B.Collect().targets[1].status == "unknown", "live invisibility must override a cached ready aura")
units.raid2.visible = true
setUnit("raid2", { guid = "Replacement-2", name = "Replacement", class = "WARRIOR" })
B.Invalidate(nil)
state = B.Collect()
assert(state.targets[1].status == "absent", "stale GUID assignments must not move to a replacement roster slot")
settings.buffCheck.assignments["Other-Player"] = { earth_shield = "Replacement-2" }
assert(B.GetAssignments().earth_shield == "Raid-2", "foreign character assignments must be isolated")

-- Source of Magic is invalidated live when the chosen target ceases to be a
-- healer, and it can never target the local player.
known[369459] = true
assignments.source_magic = "Raid-2"
setUnit("raid2", { guid = "Raid-2", name = "Raid 2", class = "PRIEST", role = "HEALER" })
setAura("raid2", 369459, { isFromPlayerOrPlayerPet = true })
B.Invalidate(nil)
assert(Target(B.Collect(), "source_magic").castable == true)
units.raid2.role = "DAMAGER"
local source = Target(B.Collect(), "source_magic")
assert(source.status == "unassigned" and source.castable == false, "role changes must invalidate Source of Magic assignment")
units.raid2.role = "HEALER"
assignments.source_magic = playerGUID
setUnit("raid1", { guid = playerGUID, name = "Player", class = "PRIEST", role = "HEALER" })
B.Invalidate(nil)
source = Target(B.Collect(), "source_magic")
assert(source.status == "unassigned" and source.castable == false, "Source of Magic must reject self assignment")
assignments.source_magic = nil
setUnit("raid1", { guid = "Raid-1", name = "Raid 1", class = "PRIEST", role = "DAMAGER" })

-- Direct ownership is trusted.  A foreign first match is only missing after a
-- readable PLAYER scan proves no owned instance exists; unknown source stays unknown.
setUnit("raid2", { guid = "Raid-2", name = "Raid 2", class = "WARRIOR", scan = { { spellId = 974, isFromPlayerOrPlayerPet = true } } })
setAura("raid2", 974, { isFromPlayerOrPlayerPet = false })
B.Invalidate("raid2")
assert(B.Collect().targets[1].status == "ready", "PLAYER scan must find own stacked aura")
units.raid2.scan = nil
B.Invalidate("raid2")
assert(B.Collect().targets[1].status == "missing", "a readable PLAYER scan can disprove an owned stacked aura")
setAura("raid2", 974, { isFromPlayerOrPlayerPet = SECRET })
B.Invalidate("raid2")
assert(B.Collect().targets[1].status == "unknown", "unknown ownership must never be reported missing")

-- Restriction, secret spell predicates, and unusable members are never shown missing.
restricted = true
B.Invalidate(nil)
state = B.Collect()
assert(state.groups[1].unknown == 0 and state.groups[1].eligible == 40,
    "per-spell readable raid auras remain available during broad restrictions")
assert(state.targets[1].status == "unknown")
restricted = false
units._soulSecret = true
known[20707] = true
B.Invalidate(nil)
state = B.Collect()
assert(state.targets[#state.targets].def.key == "soulstone" and state.targets[#state.targets].status == "unassigned")
assignments.soulstone = "Raid-2"
B.Invalidate(nil)
assert(B.Collect().targets[#B.Collect().targets].status == "unknown")
units._soulSecret = false
units.raid2.connected = false
B.Invalidate(nil)
assert(B.Collect().targets[#B.Collect().targets].status == "unknown", "offline assignment cannot be false missing")
units.raid2.connected = true
units.raid2.dead = true
B.Invalidate(nil)
assert(B.Collect().targets[#B.Collect().targets].status == "unknown", "dead assignment cannot be false missing")
units.raid2.dead = false
units.raid2.visible = false
B.Invalidate(nil)
assert(B.Collect().targets[#B.Collect().targets].status == "unknown", "invisible assignment cannot be false missing")
units.raid2.visible = SECRET
B.Invalidate(nil)
assert(B.Collect().targets[#B.Collect().targets].status == "unknown", "secret visibility cannot be false missing")
units.raid2.visible = true

-- No provider class and no known player spell means no permanent warning row.
known[21562] = nil
for i = 1, 40 do units["raid" .. i].class = "WARRIOR" end
units.raid2.dead = false
B.Invalidate(nil)
state = B.Collect()
for _, group in ipairs(state.groups) do assert(group.def.key ~= "fortitude") end

-- Solo is a one-member roster and combat never produces a stale affirmative state.
units._raid, units._raidCount = false, 0
units._partyCount = 0
setUnit("player", { guid = playerGUID, name = "Player", class = "PRIEST", role = "HEALER" })
known[21562] = true
C_SpellBook = { IsSpellKnown = function(id) return id == 1459 end }
assert(B.IsKnown(B.groupDefs[2]) == true, "modern spellbook knowledge must be used when available")
known[53563], known[200025] = true, true
B.Invalidate(nil)
for _, target in ipairs(B.Collect().targets) do
    assert(target.def.key ~= "beacon_light", "Beacon of Virtue suppresses Beacon of Light")
end
known[200025] = nil
clearAuras()
B.Invalidate(nil)
assert(B.Collect().size == 1, "solo must include player")
units._partyCount = 6
for i = 1, 6 do
    setUnit("party" .. i, { guid = "Party-" .. i, name = "Same", realm = "Realm" .. i, class = "WARRIOR" })
end
local partyRoster = B.GetRoster()
assert(#partyRoster == 5 and partyRoster[2].name == "Same-Realm1", "party roster must cap at four party tokens and keep realm identity")
units._partyCount = 0
combat = true
assert(B.Collect() == nil, "model must not collect in combat")

io.write("buff check model tests passed\n")
