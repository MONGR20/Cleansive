local _, NS = ...

-- Retail 12.1 forbids addon scripts from observing managed AuraButton
-- visibility. Public spell IDs are therefore registered with Blizzard's
-- native aura-sound service. Frames.lua supplies a separate UNIT_AURA
-- fallback only when an aura remains readable and has no native registration.
-- The list below covers one dungeon pool. When Blizzard rotates the season
-- it silently stops matching, and the only visible symptom is that sounds
-- stop firing. Bump this whenever the IDs are refreshed: /cleansive
-- soundstatus prints it so the staleness is at least legible.
NS.KNOWN_DISPELLABLE_AURAS_SEASON = "2"

NS.KNOWN_DISPELLABLE_AURAS = {
    Magic = {
        -- 1250043 « Fonte d'armure » : releve dans un journal de combat du
        -- 28/08/2026, dissipe sept fois et absent de cette liste, donc jamais
        -- annonce. Type confirme en jeu par Rodolphe : dissipation magique.
        -- Le journal de combat ne donne jamais le type, seulement l'ecole --
        -- ici le Feu -- ce qui ne suffit pas a trancher entre Magie, Poison et
        -- Maladie. Toute aura relevee de cette facon demande la meme
        -- verification a l'ecran.
        1250043,
        1294569, 1217633, 1228198, 1201554, 1235549, 1239860, 1259365,
        1238084, 1249238, 276031, 1294815, 270920, 270499, 372682,
        373589, 1305234, 381515, 392641, 392924, 1296052,
    },
    Curse = {
        1309980, 1310017, 1238255, 1217973, 1238801, 1252095, 269972,
        270492,
    },
    Poison = {
        1294845, 1305368, 1307571, 474515, 1216590, 1234846, 1250937,
        1226031, 1289258, 1263971, 267273, 271564, 1298104, 1306763,
        270865, 270507, 1308100, 1308148, 267027, 1303486, 1308546,
    },
    Disease = {
        1296069, 1302867, 1245456, 267763,
    },
    Bleed = {
        474740, 1216300, 1295035, 1295427, 1311136, 1238439, 1235865,
        1238076, 1241058, 1247746, 1242135, 1237267, 1267894, 1299133,
        1311778, 266191, 266231, 1297781, 1297918, 1301851, 1302945,
        1303490, 372796, 1291399,
    },
}

local function accessible(value)
    return not canaccessvalue or canaccessvalue(value)
end

local function registrationKey(unit, spellID)
    return tostring(unit) .. ":" .. tostring(spellID)
end

local SOUND_WARNING_THRESHOLD = 4500

local function nowMilliseconds()
    if debugprofilestop then return debugprofilestop() end
    if GetTime then return GetTime() * 1000 end
    return 0
end

local function tableCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function getInstanceContext()
    if not GetInstanceInfo then return "World", "none", 0 end
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    return name or "World", instanceType or "none", tonumber(instanceID) or 0
end

function NS:IsNativeAuraSoundAvailable()
    return C_UnitAuras
        and type(C_UnitAuras.AddAuraSound) == "function"
        and type(C_UnitAuras.RemoveAuraSound) == "function"
end

function NS:GetAuraSoundUnitTokens()
    local units, seen = {}, {}
    local function add(unit)
        if type(unit) ~= "string" or seen[unit] then return end
        if unit == "player" or not UnitExists or UnitExists(unit) then
            seen[unit] = true
            units[#units + 1] = unit
        end
    end

    -- Keep the player token available for self-only abilities. For every
    -- other roster entry, register only the token currently displayed by the
    -- secure cell. This includes an active vehicle without treating ordinary
    -- pets as passengers when "Scan pets" is disabled.
    add("player")
    for _, descriptor in ipairs(self.roster or {}) do
        if not descriptor.preview then
            local unit = self.GetDisplayUnit and self:GetDisplayUnit(descriptor.unit) or descriptor.unit
            add(unit)
        end
    end
    return units
end

function NS:BuildAuraSoundPlan()
    local allUnitSpellIDs, playerOnlySpellIDs = {}, {}
    local allUnitSeen, playerOnlySeen = {}, {}
    local inCombat = InCombatLockdown and InCombatLockdown()
    local function isIgnored(spellID)
        local always = self.db.ignoredAlways or {}
        local combat = self.db.ignoredCombat or {}
        return always[spellID] or always[tostring(spellID)]
            or (inCombat and (combat[spellID] or combat[tostring(spellID)]))
    end
    for auraType, ids in pairs(self.KNOWN_DISPELLABLE_AURAS or {}) do
        local clickable = self.typeToSlot and self.typeToSlot[auraType]
        local manual = not clickable and self.manualTypeSpell and self.manualTypeSpell[auraType]
        local scope = clickable and "all" or (manual and manual.selfOnly and "player" or (manual and "all" or nil))
        if self.db.enabledTypes[auraType] ~= false and scope then
            local target = scope == "player" and playerOnlySpellIDs or allUnitSpellIDs
            local seen = scope == "player" and playerOnlySeen or allUnitSeen
            for index = 1, #ids do
                local spellID = ids[index]
                if type(spellID) == "number" and spellID > 0 and not seen[spellID] and not isIgnored(spellID) then
                    seen[spellID] = true
                    target[#target + 1] = spellID
                end
            end
        end
    end
    for index = #playerOnlySpellIDs, 1, -1 do
        if allUnitSeen[playerOnlySpellIDs[index]] then table.remove(playerOnlySpellIDs, index) end
    end
    table.sort(allUnitSpellIDs)
    table.sort(playerOnlySpellIDs)
    local candidateUnits = self:GetAuraSoundUnitTokens()

    -- Spend the budget a complete unit at a time and preserve roster order.
    -- This prevents a normal pet from displacing a priority player and avoids
    -- leaving a retained unit with only a random subset of its dispels.
    local registrations, units, spellIDs = {}, {}, {}
    local includedSpellIDs, seenRegistration = {}, {}
    local skippedUnits = 0
    local budget = tonumber(self.db and self.db.soundMaxRegistrations) or 0
    for _, unit in ipairs(candidateUnits) do
        local entries = {}
        for _, spellID in ipairs(allUnitSpellIDs) do
            local key = registrationKey(unit, spellID)
            if not seenRegistration[key] then entries[#entries + 1] = { key = key, unit = unit, spellID = spellID } end
        end
        if unit == "player" then
            for _, spellID in ipairs(playerOnlySpellIDs) do
                local key = registrationKey(unit, spellID)
                if not seenRegistration[key] then entries[#entries + 1] = { key = key, unit = unit, spellID = spellID } end
            end
        end
        if #entries > 0 then
            if budget > 0 and #registrations + #entries > budget then
                skippedUnits = skippedUnits + 1
            else
                units[#units + 1] = unit
                for _, entry in ipairs(entries) do
                    seenRegistration[entry.key] = true
                    registrations[#registrations + 1] = entry
                    includedSpellIDs[entry.spellID] = true
                end
            end
        end
    end
    self.auraSoundSkippedUnits = skippedUnits

    for spellID in pairs(includedSpellIDs) do spellIDs[#spellIDs + 1] = spellID end
    table.sort(spellIDs)

    local spellParts, unitParts, registrationParts = {}, {}, {}
    for index = 1, #spellIDs do spellParts[index] = tostring(spellIDs[index]) end
    for index = 1, #units do unitParts[index] = tostring(units[index]) end
    for index = 1, #registrations do registrationParts[index] = registrations[index].key end
    local fingerprint = table.concat({
        self.db.sound and "1" or "0",
        self.enabled and "1" or "0",
        self.db.soundChannel or "Master",
        table.concat(spellParts, ","),
        table.concat(unitParts, ","),
        table.concat(registrationParts, ","),
    }, "|")
    return spellIDs, units, fingerprint, registrations
end

function NS:RequestAuraSoundRefresh(reason)
    self.pendingSoundRefreshReason = reason or self.pendingSoundRefreshReason or "requested"
    if self.auraSoundRefreshScheduled then return end
    if C_Timer and C_Timer.After then
        self.auraSoundRefreshScheduled = true
        C_Timer.After(0.10, function()
            self.auraSoundRefreshScheduled = false
            local refreshReason = self.pendingSoundRefreshReason
            self.pendingSoundRefreshReason = nil
            self:RefreshAuraSoundRegistrations(refreshReason)
        end)
    else
        local refreshReason = self.pendingSoundRefreshReason
        self.pendingSoundRefreshReason = nil
        self:RefreshAuraSoundRegistrations(refreshReason)
    end
end

function NS:IsAuraSoundRegistered(unit, spellID)
    return self.auraSoundRegistered
        and self.auraSoundRegistered[registrationKey(unit, spellID)] == true
end

function NS:GetKnownDispelType(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return nil end
    if not self.knownDispelTypeBySpellID then
        self.knownDispelTypeBySpellID = {}
        for auraType, ids in pairs(self.KNOWN_DISPELLABLE_AURAS or {}) do
            for index = 1, #ids do
                self.knownDispelTypeBySpellID[ids[index]] = auraType
            end
        end
    end
    return self.knownDispelTypeBySpellID[spellID]
end

-- A registration can fail transiently -- a protected handle, a refusal during a
-- loading screen. In combat the end of the fight already requests a refresh, so
-- a timer here would only race it. Out of combat nothing was asking, so ask:
-- twice, spaced, and no more, because a permanent refusal must not loop.
local MAX_SOUND_RETRIES = 2

function NS:ScheduleAuraSoundRetry()
    if InCombatLockdown and InCombatLockdown() then return end
    local attempts = self.auraSoundRetries or 0
    if attempts >= MAX_SOUND_RETRIES then return end
    self.auraSoundRetries = attempts + 1
    local diagnostics = self.auraSoundDiagnostics
    if diagnostics then diagnostics.retries = self.auraSoundRetries end
    if not (C_Timer and C_Timer.After) then return end
    local generation = self.auraSoundGeneration
    C_Timer.After(attempts == 0 and 1 or 3, function()
        -- Another refresh has already happened; it owns the outcome now.
        if self.auraSoundGeneration ~= generation then return end
        self:RequestAuraSoundRefresh("registration retry")
    end)
end

function NS:RefreshAuraSoundRegistrations(reason)

    local startedAt = nowMilliseconds()
    local spellIDs, units, fingerprint, registrations = self:BuildAuraSoundPlan()

    -- A replacement handle is normally removed immediately when its old
    -- registration could not be retired. Keep the exceptional refusal here so
    -- the next refresh can finish the cleanup instead of leaking a duplicate
    -- native alert for the rest of the session.
    self.auraSoundOrphanHandles = self.auraSoundOrphanHandles or {}
    if self:IsNativeAuraSoundAvailable() then
        for handle in pairs(self.auraSoundOrphanHandles) do
            local ok, result = pcall(C_UnitAuras.RemoveAuraSound, handle)
            if ok and result ~= false then self.auraSoundOrphanHandles[handle] = nil end
        end
    end

    local previous = self.auraSoundDiagnostics
    if fingerprint == self.auraSoundFingerprint and previous
        and previous.registered == previous.attempted then
        local handleCount = tableCount(self.auraSoundHandles)
            + tableCount(self.auraSoundOrphanHandles)
        if handleCount == previous.registered then
            local instanceName, instanceType, instanceID = getInstanceContext()
            previous.reason = reason or previous.reason
            previous.instanceName = instanceName
            previous.instanceType = instanceType
            previous.instanceID = instanceID
            previous.elapsedMs = 0
            previous.activeHandles = handleCount
            previous.cached = true
            return previous.registered
        end
    end
    local instanceName, instanceType, instanceID = getInstanceContext()
    local diagnostics = {
        reason = reason or "unknown",
        attempted = #registrations,
        registered = 0,
        units = #units,
        spells = #spellIDs,
        skippedUnits = self.auraSoundSkippedUnits or 0,
        instanceName = instanceName,
        instanceType = instanceType,
        instanceID = instanceID,
        added = 0,
        removed = 0,
        reused = 0,
        replaced = 0,
        preserved = 0,
        rolledBack = 0,
        batches = 0,
        elapsedMs = 0,
        cached = false,
        error = nil,
    }
    self.auraSoundDiagnostics = diagnostics
    -- The retry budget belongs to a plan, not to the session. Two permanent
    -- refusals on plan A used to leave a different plan B with no retries at
    -- all, because the counter only ever reset on a complete success.
    if fingerprint ~= self.auraSoundRetryFingerprint then
        self.auraSoundRetryFingerprint = fingerprint
        self.auraSoundRetries = 0
    end
    self.auraSoundGeneration = (self.auraSoundGeneration or 0) + 1
    local generation = self.auraSoundGeneration

    if not self:IsNativeAuraSoundAvailable() then
        diagnostics.error = "native API unavailable"
        diagnostics.elapsedMs = nowMilliseconds() - startedAt
        diagnostics.activeHandles = tableCount(self.auraSoundHandles)
            + tableCount(self.auraSoundOrphanHandles)
        self.auraSoundFingerprint = nil
        return 0
    end

    local desired = {}
    if self.db and self.db.sound and self.enabled then
        for _, entry in ipairs(registrations) do
            desired[entry.key] = entry
        end
    else
        diagnostics.attempted = 0
    end

    local handles = self.auraSoundHandles or {}
    local registered = self.auraSoundRegistered or {}
    local handleChannels = self.auraSoundHandleChannels or {}
    local staleHandles = 0
    local replacementFailures = 0
    local currentChannel = self.db.soundChannel or "Master"

    local pendingAdds = {}
    local pendingRemovals = {}

    for key in pairs(registered) do
        if not handles[key] then registered[key] = nil end
    end

    -- Registrations created before this per-handle map existed all used the
    -- session-wide channel. On a live upgrade this preserves that knowledge;
    -- after a reload there are no native handles to migrate.
    for key in pairs(handles) do
        if handleChannels[key] == nil then handleChannels[key] = self.auraSoundChannel end
        if not desired[key] then
            pendingRemovals[#pendingRemovals + 1] = { key = key, handle = handles[key] }
        end
    end

    -- Add before remove. A group change normally reuses almost everything;
    -- a channel change now replaces each pair transactionally. If Blizzard
    -- temporarily refuses AddAuraSound, the old working alert remains live.
    for _, planned in ipairs(registrations) do
        local key, entry = planned.key, desired[planned.key]
        if entry and handles[key] and handleChannels[key] == currentChannel then
            registered[key] = true
            diagnostics.registered = diagnostics.registered + 1
            diagnostics.reused = diagnostics.reused + 1
        elseif entry then
            pendingAdds[#pendingAdds + 1] = {
                key = key,
                unit = entry.unit,
                spellID = entry.spellID,
                oldHandle = handles[key],
            }
        end
    end

    self.auraSoundHandles = handles
    self.auraSoundRegistered = registered
    self.auraSoundHandleChannels = handleChannels

    local trigger = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    local nextAdd = 1
    diagnostics.pending = #pendingAdds > 0 or #pendingRemovals > 0

    local function removeNativeHandle(handle)
        local ok, result = pcall(C_UnitAuras.RemoveAuraSound, handle)
        return ok and result ~= false, ok and result or result
    end

    local function finalize()
        if self.auraSoundGeneration ~= generation then return end

        -- Obsolete pairs are retired only after every requested addition has
        -- had its chance. This keeps the useful half of the registry alive
        -- throughout a roster or filter transition.
        for _, entry in ipairs(pendingRemovals) do
            if handles[entry.key] == entry.handle and not desired[entry.key] then
                local removed, failure = removeNativeHandle(entry.handle)
                if removed then
                    handles[entry.key] = nil
                    registered[entry.key] = nil
                    handleChannels[entry.key] = nil
                    diagnostics.removed = diagnostics.removed + 1
                else
                    staleHandles = staleHandles + 1
                    diagnostics.error = diagnostics.error
                        or (failure == false and "sound registration removal failed" or tostring(failure))
                end
            end
        end

        diagnostics.pending = false
        diagnostics.elapsedMs = math.max(0, nowMilliseconds() - startedAt)
        diagnostics.activeHandles = tableCount(handles) + tableCount(self.auraSoundOrphanHandles)
        -- Recorded here, while the group exists. The logout snapshot cannot see
        -- it: by then the player is alone and the numbers are back to one unit.
        if self.NoteSoundLoad then
            self:NoteSoundLoad(diagnostics.attempted, diagnostics.units, diagnostics.registered)
        end
        if diagnostics.registered == diagnostics.attempted
            and staleHandles == 0 and replacementFailures == 0 then
            self.auraSoundFingerprint = fingerprint
            self.auraSoundChannel = currentChannel
            self.auraSoundRetries = 0
        else
            -- Clearing the fingerprint lets the next request rebuild instead of
            -- short-circuiting on a match. It does not, on its own, ask for
            -- one: a partial pass out of combat used to have no follow-up at
            -- all, and the missing sounds stayed missing until some unrelated
            -- event happened to request a refresh. Ask here instead.
            self.auraSoundFingerprint = nil
            self:ScheduleAuraSoundRetry()
        end
        if diagnostics.attempted >= SOUND_WARNING_THRESHOLD and not self.soundLoadWarningShown then
            self.soundLoadWarningShown = true
            self:Print(self.L.SOUND_STATUS_HIGH, diagnostics.attempted, diagnostics.units, diagnostics.spells)
        end
    end

    local function registerBatch()
        if self.auraSoundGeneration ~= generation then return end
        local batchSize = C_Timer and C_Timer.After and 180 or #pendingAdds
        local lastAdd = math.min(#pendingAdds, nextAdd + batchSize - 1)
        if lastAdd >= nextAdd then diagnostics.batches = diagnostics.batches + 1 end
        for index = nextAdd, lastAdd do
            local entry = pendingAdds[index]
            local info = {
                unitToken = entry.unit,
                spellID = entry.spellID,
                soundFileName = self.afflictionSoundFile,
                outputChannel = currentChannel,
            }
            local ok, handle = pcall(C_UnitAuras.AddAuraSound, trigger, info)
            if ok and type(handle) == "number" and accessible(handle) then
                if entry.oldHandle then
                    local removed, failure = removeNativeHandle(entry.oldHandle)
                    if removed then
                        handles[entry.key] = handle
                        handleChannels[entry.key] = currentChannel
                        registered[entry.key] = true
                        diagnostics.registered = diagnostics.registered + 1
                        diagnostics.added = diagnostics.added + 1
                        diagnostics.removed = diagnostics.removed + 1
                        diagnostics.replaced = diagnostics.replaced + 1
                    else
                        -- The new alert must not coexist with the old one: two
                        -- native registrations would play the sound twice.
                        local rolledBack = removeNativeHandle(handle)
                        if not rolledBack then self.auraSoundOrphanHandles[handle] = true end
                        registered[entry.key] = true
                        diagnostics.registered = diagnostics.registered + 1
                        diagnostics.reused = diagnostics.reused + 1
                        diagnostics.preserved = diagnostics.preserved + 1
                        diagnostics.rolledBack = diagnostics.rolledBack + 1
                        replacementFailures = replacementFailures + 1
                        diagnostics.error = diagnostics.error
                            or (failure == false and "sound registration removal failed" or tostring(failure))
                    end
                else
                    handles[entry.key] = handle
                    handleChannels[entry.key] = currentChannel
                    registered[entry.key] = true
                    diagnostics.registered = diagnostics.registered + 1
                    diagnostics.added = diagnostics.added + 1
                end
            elseif not ok then
                diagnostics.error = tostring(handle)
            else
                diagnostics.error = "registration returned no sound ID"
            end

            if (not ok or type(handle) ~= "number" or not accessible(handle)) and entry.oldHandle then
                -- A refused replacement is degraded (the requested channel was
                -- not applied) but it is not silent: the prior handle remains.
                registered[entry.key] = true
                diagnostics.registered = diagnostics.registered + 1
                diagnostics.reused = diagnostics.reused + 1
                diagnostics.preserved = diagnostics.preserved + 1
                replacementFailures = replacementFailures + 1
            end
        end
        nextAdd = lastAdd + 1
        if nextAdd <= #pendingAdds and C_Timer and C_Timer.After then
            C_Timer.After(0, registerBatch)
        else
            finalize()
        end
    end

    registerBatch()
    return diagnostics.registered
end

function NS:PrintAuraSoundStatus()
    local diagnostics = self.auraSoundDiagnostics or {}
    self:Print(self:AuraSoundStateSentence())
    local activeHandles = tableCount(self.auraSoundHandles)
        + tableCount(self.auraSoundOrphanHandles)
    self:Print(self.L.SOUND_STATUS,
        tonumber(diagnostics.registered) or 0,
        tonumber(diagnostics.attempted) or 0,
        tonumber(diagnostics.spells) or 0,
        tonumber(diagnostics.units) or 0)
    self:Print(self.L.SOUND_STATUS_DELTA,
        tonumber(diagnostics.added) or 0,
        tonumber(diagnostics.removed) or 0,
        tonumber(diagnostics.reused) or 0)
    if (tonumber(diagnostics.preserved) or 0) > 0 then
        self:Print(self.L.SOUND_STATUS_PRESERVED,
            tonumber(diagnostics.preserved) or 0,
            tonumber(diagnostics.rolledBack) or 0)
    end
    self:Print(self.L.SOUND_STATUS_PERFORMANCE,
        activeHandles,
        tonumber(diagnostics.batches) or 0,
        tonumber(diagnostics.elapsedMs) or 0)
    self:Print(self.L.SOUND_STATUS_INSTANCE,
        tostring(diagnostics.instanceName or "World"),
        tostring(diagnostics.instanceType or "none"),
        tostring(diagnostics.instanceID or 0))
    if (tonumber(diagnostics.skippedUnits) or 0) > 0 then
        self:Print(self.L.SOUND_STATUS_CAPPED, diagnostics.skippedUnits,
            tonumber(self.db.soundMaxRegistrations) or 0)
    end
    local total = 0
    for _, ids in pairs(self.KNOWN_DISPELLABLE_AURAS or {}) do total = total + #ids end
    self:Print(self.L.SOUND_STATUS_SEASON,
        tostring(self.KNOWN_DISPELLABLE_AURAS_SEASON or "?"), total)
    if diagnostics.pending then self:Print(self.L.SOUND_STATUS_PENDING) end
    if diagnostics.error then self:Print(self.L.SOUND_STATUS_ERROR, diagnostics.error) end
end

-- A player reports "this affliction never makes a sound". The answer is one of
-- five, and only the addon can tell which: the ID is not in the season list,
-- its type is switched off, it is filtered, the budget ran out, or it is
-- registered and something else is wrong. Answer with the one that applies.
function NS:DescribeSpellSound(spellID)
    spellID = tonumber(spellID)
    if not spellID then return self.L.SOUND_QUERY_USAGE end

    local auraType
    for candidate, ids in pairs(self.KNOWN_DISPELLABLE_AURAS or {}) do
        for _, id in ipairs(ids) do
            if id == spellID then auraType = candidate break end
        end
        if auraType then break end
    end
    if not auraType then
        return string.format(self.L.SOUND_QUERY_UNLISTED, spellID,
            tostring(self.KNOWN_DISPELLABLE_AURAS_SEASON))
    end

    local typeLabel = self:GetTypeLabel(auraType)
    if self.db.enabledTypes and self.db.enabledTypes[auraType] == false then
        return string.format(self.L.SOUND_QUERY_TYPE_OFF, spellID, typeLabel)
    end
    local always = self.db.ignoredAlways or {}
    local combat = self.db.ignoredCombat or {}
    if always[spellID] or always[tostring(spellID)] then
        return string.format(self.L.SOUND_QUERY_FILTERED, spellID, typeLabel)
    end
    if combat[spellID] or combat[tostring(spellID)] then
        return string.format(self.L.SOUND_QUERY_FILTERED_COMBAT, spellID, typeLabel)
    end

    local units = {}
    for key in pairs(self.auraSoundRegistered or {}) do
        local unit, id = string.match(tostring(key), "^(.*):(%d+)$")
        if id and tonumber(id) == spellID then units[#units + 1] = unit end
    end
    if #units == 0 then
        return string.format(self.L.SOUND_QUERY_NOT_REGISTERED, spellID, typeLabel,
            tonumber(self.auraSoundSkippedUnits) or 0)
    end
    table.sort(units)
    return string.format(self.L.SOUND_QUERY_REGISTERED, spellID, typeLabel,
        #units, table.concat(units, ", "))
end

function NS:AuraSoundState()
    if not self.db or not self.db.sound then return "OFF" end
    if not self:IsNativeAuraSoundAvailable() then return "UNAVAILABLE" end
    local diagnostics = self.auraSoundDiagnostics
    if not diagnostics then return "IDLE" end
    if diagnostics.pending then return "PENDING" end
    if diagnostics.error
        or (tonumber(diagnostics.preserved) or 0) > 0
        or (tonumber(diagnostics.registered) or 0) < (tonumber(diagnostics.attempted) or 0)
        or (tonumber(self.auraSoundSkippedUnits) or 0) > 0 then
        return "DEGRADED"
    end
    return "ACTIVE"
end

function NS:AuraSoundStateSentence()
    return self.L["SOUND_STATE_" .. self:AuraSoundState()] or self.L.SOUND_STATE_IDLE
end

-- Meme principe que pour le son : une conclusion, pas une suite de nombres.
function NS:AuraEngineState()
    if not self.engineAuraMode then return "OFF" end
    local diagnostics = self.auraContainerDiagnostics
    if type(diagnostics) ~= "table" then return "IDLE" end
    if self.pendingAuraEngineRebuild then return "PENDING" end
    if (tonumber(diagnostics.added) or 0) < (tonumber(diagnostics.expected) or 0)
        or diagnostics.firstError then
        return "DEGRADED"
    end
    return "ACTIVE"
end

function NS:AuraEngineStateSentence()
    return self.L["ENGINE_STATE_" .. self:AuraEngineState()] or self.L.ENGINE_STATE_IDLE
end
