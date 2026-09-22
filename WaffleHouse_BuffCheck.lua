-- Out-of-combat raid-buff model.  The driver owns events and presentation;
-- this file intentionally has no frames, timers, or event registrations.
local addonName, addon = ...
if type(addon) ~= "table" then return end

local B = {}
addon.BuffCheck = B

-- `spellID` is the spell shown/cast by the panel.  `auraIDs` includes known
-- equivalent aura variants, so one panel row represents one raid benefit.
B.groupDefs = {
    { key = "fortitude", name = "Fortitude", spellID = 21562, auraIDs = { 21562 }, class = "PRIEST" },
    { key = "intellect", name = "Intellect", spellID = 1459, auraIDs = { 1459, 432778 }, class = "MAGE" },
    { key = "mark", name = "Mark", spellID = 1126, auraIDs = { 1126, 432661 }, class = "DRUID" },
    { key = "shout", name = "Shout", spellID = 6673, auraIDs = { 6673 }, class = "WARRIOR" },
    { key = "bronze", name = "Blessing of the Bronze", spellID = 364342,
        auraIDs = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752,
            381753, 381754, 381756, 381757, 381758 }, class = "EVOKER" },
    { key = "skyfury", name = "Skyfury", spellID = 462854, auraIDs = { 462854 }, class = "SHAMAN" },
}

-- Only spells with a target aura whose ownership can be established are kept
-- here.  Symbiotic Relationship deliberately remains out: its exposed aura is
-- a caster indication, not a reliable per-target assignment result.
B.targetDefs = {
    { key = "earth_shield", name = "Earth Shield", spellID = 974, auraIDs = { 974 }, class = "SHAMAN" },
    { key = "beacon_light", name = "Beacon of Light", spellID = 53563, auraIDs = { 53563 }, class = "PALADIN", distinctBeacons = true },
    { key = "beacon_faith", name = "Beacon of Faith", spellID = 156910, auraIDs = { 156910 }, class = "PALADIN", distinctBeacons = true },
    { key = "source_magic", name = "Source of Magic", spellID = 369459, auraIDs = { 369459 }, class = "EVOKER", healerOnly = true, noSelf = true },
    { key = "blistering_scales", name = "Blistering Scales", spellID = 360827, auraIDs = { 360827 }, class = "EVOKER" },
    { key = "soulstone", name = "Soulstone", spellID = 20707, auraIDs = { 20707 }, class = "WARLOCK" },
}

-- Aura data changes independently of roster, provider, and spell metadata.
-- The event driver can therefore collect an incremental presentation state
-- without re-reading the whole group every few seconds.
local auraCache = {}
local collectionCache

local trackedAuraIDs = {}
for _, defs in ipairs({ B.groupDefs, B.targetDefs }) do
    for _, def in ipairs(defs) do
        for _, spellID in ipairs(def.auraIDs) do trackedAuraIDs[spellID] = true end
    end
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeBoolean(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function AurasRestricted()
    local ak = EllesmereUI and EllesmereUI.AuraKit
    if ak and type(ak.AurasRestricted) == "function" then
        local ok, restricted = Call(ak.AurasRestricted)
        if not ok or IsSecret(restricted) then return true end
        if SafeBoolean(restricted) == true then return true end
    end
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
        local ok, restricted = Call(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(restricted) then return true end
        if SafeBoolean(restricted) == true then return true end
    end
    return false
end

-- true means secret/unsafe, false means Blizzard explicitly allows the spell,
-- and nil means this client has no per-spell answer (use the broad fallback).
local function SpellAuraMayBeSecret(spellID)
    if C_Secrets and type(C_Secrets.ShouldSpellAuraBeSecret) == "function" then
        local ok, secret = Call(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if not ok or IsSecret(secret) then return true end
        local readable = SafeBoolean(secret)
        if readable == nil or readable == true then return true end
        return false
    end
    return nil
end

local function UnitVisible(unit)
    local ok, exists = Call(UnitExists, unit)
    if not ok or SafeBoolean(exists) ~= true then return nil end
    if type(UnitIsVisible) ~= "function" then return true end
    local visibleOK, visible = Call(UnitIsVisible, unit)
    if not visibleOK then return nil end
    return SafeBoolean(visible)
end

local function MemberCanBeRead(member)
    if not member or UnitVisible(member.unit) ~= true then return false end
    local ok, connected = Call(UnitIsConnected, member.unit)
    if not ok or SafeBoolean(connected) ~= true then return false end
    local deadOK, dead = Call(UnitIsDeadOrGhost, member.unit)
    if not deadOK or SafeBoolean(dead) ~= false then return false end
    return true
end

local function GetAura(unit, spellID)
    if not (C_UnitAuras and type(C_UnitAuras.GetUnitAuraBySpellID) == "function") then
        return nil, "unknown"
    end
    local ok, aura = Call(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    if not ok or IsSecret(aura) then return nil, "unknown" end
    if aura == nil then return nil, "missing" end
    return aura, "ready"
end

local function GetCached(member, def)
    local bucket = auraCache[member.unit]
    local record = bucket and bucket.guid == member.guid and bucket[def.key]
    return record and record.status or nil
end

local function PutCached(member, def, status, aura)
    local bucket = auraCache[member.unit]
    if not bucket or bucket.guid ~= member.guid then
        bucket = { guid = member.guid }
        auraCache[member.unit] = bucket
    end
    local record = { status = status }
    if status == "ready" then
        local instanceID = type(aura) == "table" and SafeNumber(aura.auraInstanceID) or nil
        if instanceID then
            record.instanceIDs = { [instanceID] = true }
        else
            -- We cannot prove a future removal is unrelated without a
            -- readable instance identity.
            record.untrackedReady = true
        end
    end
    bucket[def.key] = record
    return status
end

local function GroupAuraStatus(member, def, readable)
    if readable ~= true then return "unknown" end
    local cached = GetCached(member, def)
    if cached then return cached end
    for i = 1, #def.auraIDs do
        local spellID = def.auraIDs[i]
        local secret = SpellAuraMayBeSecret(spellID)
        if secret == true or (secret == nil and AurasRestricted()) then return PutCached(member, def, "unknown") end
        local aura, status = GetAura(member.unit, spellID)
        if status == "unknown" then return PutCached(member, def, "unknown") end
        if status == "ready" then return PutCached(member, def, "ready", aura) end
    end
    return PutCached(member, def, "missing")
end

local function AuraIsFromPlayer(aura)
    if IsSecret(aura) or type(aura) ~= "table" then return nil end
    local fromPlayer = aura.isFromPlayerOrPlayerPet
    if not IsSecret(fromPlayer) and SafeBoolean(fromPlayer) ~= nil then
        return SafeBoolean(fromPlayer)
    end
    local sourceUnit = aura.sourceUnit
    if not SafeString(sourceUnit) then return nil end
    local ok, same = Call(UnitIsUnit, sourceUnit, "player")
    if not ok then return nil end
    return SafeBoolean(same)
end

-- A direct spell-ID query can return another caster's stack first.  In an
-- unrestricted readable context, a PLAYER-filtered scan settles that case.
local function HasOwnAuraByScan(unit, def)
    if AurasRestricted() or not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return "unknown"
    end
    for i = 1, 255 do
        local ok, aura = Call(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
        if not ok or IsSecret(aura) then return "unknown" end
        if aura == nil then return "missing" end
        if type(aura) ~= "table" then return "unknown" end
        local spellID = aura.spellId
        if IsSecret(spellID) then return "unknown" end
        local id = SafeNumber(spellID)
        if id then
            for j = 1, #def.auraIDs do
                if id == def.auraIDs[j] then
                    local owned = AuraIsFromPlayer(aura)
                    return owned == true and "ready" or (owned == false and "missing" or "unknown")
                end
            end
        end
    end
    return "unknown"
end

local function TargetAuraStatus(member, def, readable)
    -- Visibility, connection, and life state change independently of aura
    -- events.  Always use the live collection snapshot before a cached ready.
    if readable ~= true then return "unknown" end
    local cached = GetCached(member, def)
    if cached then return cached end
    local sawAmbiguous = false
    for i = 1, #def.auraIDs do
        local spellID = def.auraIDs[i]
        local secret = SpellAuraMayBeSecret(spellID)
        if secret == true or (secret == nil and AurasRestricted()) then return PutCached(member, def, "unknown") end
        local aura, status = GetAura(member.unit, spellID)
        if status == "unknown" then return PutCached(member, def, "unknown") end
        if status == "ready" then
            local owned = AuraIsFromPlayer(aura)
            if owned == true then return PutCached(member, def, "ready", aura) end
            if owned == nil then return PutCached(member, def, "unknown") end
            sawAmbiguous = true
        end
    end
    if sawAmbiguous then
        return PutCached(member, def, HasOwnAuraByScan(member.unit, def))
    end
    return PutCached(member, def, "missing")
end

function B.GetSettings()
    local root = type(addon.GetSettings) == "function" and addon.GetSettings() or nil
    if type(root) ~= "table" then return {} end
    if type(root.buffCheck) ~= "table" then root.buffCheck = {} end
    local settings = root.buffCheck
    if settings.enabled == nil then settings.enabled = true end
    if settings.collapsed == nil then settings.collapsed = false end
    if settings.hideReady == nil then settings.hideReady = true end
    -- Keep this unset until the first explicit enable.  That lets first-use
    -- setup seed the sensible group-only default exactly once without ever
    -- writing over a later player choice.
    if settings.onlyWhenNeeded == nil then settings.onlyWhenNeeded = true end
    if settings.alwaysShowInGroup == nil then settings.alwaysShowInGroup = false end
    if type(settings.situations) ~= "table" then settings.situations = {} end
    if type(settings.position) ~= "table" then
        settings.position = { point = "TOPLEFT", x = 30, y = -240 }
    end
    if type(settings.assignments) ~= "table" then settings.assignments = {} end
    return settings
end

function B.GetAssignments()
    local settings = B.GetSettings()
    local ok, guid = Call(UnitGUID, "player")
    local playerGUID = ok and SafeString(guid) or nil
    if not playerGUID then return {} end
    if type(settings.assignments) ~= "table" then settings.assignments = {} end
    if type(settings.assignments[playerGUID]) ~= "table" then settings.assignments[playerGUID] = {} end
    return settings.assignments[playerGUID]
end

function B.GetRoster(optimized)
    if optimized == true and collectionCache and collectionCache.roster then return collectionCache.roster end
    local roster, seen = {}, {}
    local function Add(unit)
        if #roster >= 40 then return end
        local guidOK, guidValue = Call(UnitGUID, unit)
        local guid = guidOK and SafeString(guidValue) or nil
        if guid and seen[guid] then return end
        if guid then seen[guid] = true end
        local nameOK, nameValue, realmValue = Call(UnitFullName, unit)
        local name = nameOK and SafeString(nameValue) or nil
        local realm = nameOK and SafeString(realmValue) or nil
        if name and realm and realm ~= "" then name = name .. "-" .. realm end
        if not name then
            nameOK, nameValue = Call(UnitName, unit)
            name = nameOK and SafeString(nameValue) or nil
        end
        local class = nil
        local classOK, _, token = Call(UnitClass, unit)
        if classOK then class = SafeString(token) end
        local roleOK, roleValue = Call(UnitGroupRolesAssigned, unit)
        local role = roleOK and SafeString(roleValue) or nil
        roster[#roster + 1] = { unit = unit, guid = guid, name = name or unit, class = class, role = role }
    end

    local raidOK, raidValue = Call(IsInRaid)
    local inRaid = raidOK and SafeBoolean(raidValue) == true
    if inRaid then
        local countOK, countValue = Call(GetNumGroupMembers)
        local count = countOK and SafeNumber(countValue) or 0
        for i = 1, math.min(count or 0, 40) do Add("raid" .. i) end
    else
        Add("player")
        local countOK, countValue = Call(GetNumSubgroupMembers)
        local count = countOK and SafeNumber(countValue) or 0
        for i = 1, math.min(count or 0, 4) do Add("party" .. i) end
    end
    return roster
end

local function IsSpellKnownID(spellID)
    if not SafeNumber(spellID) then return false end
    local modern = C_SpellBook and C_SpellBook.IsSpellKnown
    local ok, known = Call(modern, spellID)
    if ok and SafeBoolean(known) == true then return true end
    for _, fn in pairs({ IsPlayerSpell, IsSpellKnown }) do
        local ok, known = Call(fn, spellID)
        if ok and SafeBoolean(known) == true then return true end
    end
    return false
end

local function IsPlayerMember(member, playerGUID)
    if member.guid and playerGUID and member.guid == playerGUID then return true end
    local ok, same = Call(UnitIsUnit, member.unit, "player")
    return ok and SafeBoolean(same) == true
end

function B.IsKnown(def)
    return type(def) == "table" and IsSpellKnownID(def.spellID) or false
end

function B.SpellName(def)
    if type(def) ~= "table" then return nil end
    local spellID = SafeNumber(def.spellID)
    if not spellID then return def.name end
    local fn = C_Spell and C_Spell.GetSpellName or GetSpellInfo
    local ok, name = Call(fn, spellID)
    return ok and SafeString(name) or def.name
end

local function BuildCollectionContext()
    local roster = B.GetRoster()
    local context = { roster = roster, byGUID = {}, readable = {}, groupCastable = {}, groupActive = {}, targetKnown = {} }
    local providerClasses = {}
    local playerGUIDOK, playerGUIDValue = Call(UnitGUID, "player")
    context.playerGUID = playerGUIDOK and SafeString(playerGUIDValue) or nil
    for i = 1, #roster do
        local member = roster[i]
        if member.guid then context.byGUID[member.guid] = member end
        if member.class then providerClasses[member.class] = true end
        context.readable[member.unit] = MemberCanBeRead(member)
        member.isPlayer = IsPlayerMember(member, context.playerGUID)
    end
    for i = 1, #B.groupDefs do
        local def = B.groupDefs[i]
        local castable = B.IsKnown(def)
        context.groupCastable[def.key] = castable
        context.groupActive[def.key] = castable or providerClasses[def.class] == true
        if context.groupActive[def.key] then context.hasActive = true end
    end
    for i = 1, #B.targetDefs do
        local def = B.targetDefs[i]
        local known = B.IsKnown(def) and not (def.key == "beacon_light" and IsSpellKnownID(200025))
        context.targetKnown[def.key] = known
        if known then context.hasActive = true end
    end
    local assignments = B.GetAssignments()
    context.assignments = {}
    for key, guid in pairs(assignments) do
        if type(guid) == "string" then context.assignments[key] = guid end
    end
    return context
end

local function BuildCollectionState(context)
    local roster, readable = context.roster, context.readable
    local state = { groups = {}, targets = {}, size = #roster, skipped = 0 }
    for i = 1, #roster do
        if readable[roster[i].unit] ~= true then state.skipped = state.skipped + 1 end
    end
    for i = 1, #B.groupDefs do
        local def = B.groupDefs[i]
        local castable = context.groupCastable[def.key]
        if context.groupActive[def.key] then
            local group = { def = def, missing = {}, unknown = 0, covered = 0, eligible = 0, castable = castable }
            for j = 1, #roster do
                local member = roster[j]
                if readable[member.unit] then
                    group.eligible = group.eligible + 1
                    local status = GroupAuraStatus(member, def, true)
                    if status == "ready" then group.covered = group.covered + 1
                    elseif status == "missing" then group.missing[#group.missing + 1] = member
                    else group.unknown = group.unknown + 1 end
                else
                    group.unknown = group.unknown + 1
                end
            end
            state.groups[#state.groups + 1] = group
        end
    end
    for i = 1, #B.targetDefs do
        local def = B.targetDefs[i]
        if context.targetKnown[def.key] then
            local assignedGUID = context.assignments[def.key]
            local member = assignedGUID and context.byGUID[assignedGUID] or nil
            local status, castable = nil, true
            if not assignedGUID then status = "unassigned"
            elseif not member then status = "absent"
            elseif (def.healerOnly and member.role ~= "HEALER")
                or (def.noSelf and member.isPlayer) then
                status, castable = "unassigned", false
            else status = TargetAuraStatus(member, def, readable[member.unit]) end
            state.targets[#state.targets + 1] = { def = def, member = member, status = status, castable = castable }
        end
    end
    return state
end

local function CachedUnitMatches(unit, token, bucket, guid)
    return bucket and (unit == token or (guid and bucket.guid == guid))
end

local function CachedAuraInstanceRelevant(unit, instanceID)
    local guidOK, guidValue = Call(UnitGUID, unit)
    local guid = guidOK and SafeString(guidValue) or nil
    local matched, uncertain = false, false
    for token, bucket in pairs(auraCache) do
        if CachedUnitMatches(unit, token, bucket, guid) then
            matched = true
            for key, record in pairs(bucket) do
                if key ~= "guid" and type(record) == "table" then
                    if record.instanceIDs and record.instanceIDs[instanceID] then return true end
                    if record.untrackedReady or record.status == "unknown" then uncertain = true end
                end
            end
        end
    end
    if not matched or uncertain then return nil end
    return false
end

local function AuraDeltaSpellRelevant(aura)
    if IsSecret(aura) or type(aura) ~= "table" then return nil end
    local spellID = SafeNumber(aura.spellId)
    if not spellID then return nil end
    return trackedAuraIDs[spellID] == true
end

-- Returns false only when the Retail delta is completely readable and every
-- changed aura is demonstrably outside the tracked definitions.
function B.AuraUpdateRelevant(unit, updateInfo)
    if not SafeString(unit) or IsSecret(updateInfo) or type(updateInfo) ~= "table" then return true end
    if AurasRestricted() then return true end
    local full = SafeBoolean(updateInfo.isFullUpdate)
    if full ~= false then return true end
    local added, updated, removed = updateInfo.addedAuras, updateInfo.updatedAuraInstanceIDs, updateInfo.removedAuraInstanceIDs
    if IsSecret(added) or IsSecret(updated) or IsSecret(removed)
        or (added ~= nil and type(added) ~= "table")
        or (updated ~= nil and type(updated) ~= "table")
        or (removed ~= nil and type(removed) ~= "table") then
        return true
    end
    if added then
        for _, aura in pairs(added) do
            local relevant = AuraDeltaSpellRelevant(aura)
            if relevant ~= false then return true end
        end
    end
    if updated then
        for _, value in pairs(updated) do
            local instanceID = SafeNumber(value)
            if not instanceID then return true end
            local cached = CachedAuraInstanceRelevant(unit, instanceID)
            if cached ~= false then return true end
            local api = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
            local ok, aura = Call(api, unit, instanceID)
            if not ok or aura == nil or IsSecret(aura) then return true end
            local relevant = AuraDeltaSpellRelevant(aura)
            if relevant ~= false then return true end
        end
    end
    if removed then
        for _, value in pairs(removed) do
            local instanceID = SafeNumber(value)
            if not instanceID or CachedAuraInstanceRelevant(unit, instanceID) ~= false then return true end
        end
    end
    return false
end

function B.Invalidate(unit)
    if IsSecret(unit) then return end
    if unit == nil then
        auraCache, collectionCache = {}, nil
        return
    end
    unit = SafeString(unit)
    if not unit then return end
    local guidOK, guidValue = Call(UnitGUID, unit)
    local guid = guidOK and SafeString(guidValue) or nil
    auraCache[unit] = nil
    for token, bucket in pairs(auraCache) do
        if guid and bucket.guid == guid then auraCache[token] = nil end
    end
    if collectionCache then
        for i = 1, #collectionCache.roster do
            local member = collectionCache.roster[i]
            if member.unit == unit or (guid and member.guid == guid) then
                collectionCache.readable[member.unit] = MemberCanBeRead(member)
            end
        end
    end
end

-- A direct call keeps the previous live-roster behavior.  The driver passes
-- true only after it has invalidated the affected units or a full metadata
-- boundary such as GROUP_ROSTER_UPDATE.
function B.Collect(optimized)
    if InCombatLockdown and SafeBoolean(InCombatLockdown()) == true then return nil end
    if optimized == true then
        collectionCache = collectionCache or BuildCollectionContext()
        return BuildCollectionState(collectionCache)
    end
    return BuildCollectionState(BuildCollectionContext())
end

function B.CheckVisibility()
    if not collectionCache then return nil end
    local changed
    for i = 1, #collectionCache.roster do
        local member = collectionCache.roster[i]
        if MemberCanBeRead(member) ~= collectionCache.readable[member.unit] then
            changed = changed or {}
            changed[member.unit] = true
        end
    end
    return changed
end

function B.HasVisibilityWatch()
    return collectionCache and #collectionCache.roster > 1 and collectionCache.hasActive == true or false
end
