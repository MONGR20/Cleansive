local _, NS = ...

-- What a session leaves behind for whoever has to explain it afterwards.
--
-- Three things earned their place here on 28/08/2026, each because its absence
-- cost an evening:
--
--   * A pending flag with no record of what raised it. The pending plate was
--     appearing during dungeon pulls and the only way to find out why was to
--     audit eleven flags by hand against every event that can set them.
--   * A dispellable aura the seasonal sound list had never heard of. Finding
--     it meant reading 82 MB of combat log with grep. The client hands the
--     same information to any addon that listens.
--   * The protected engine's own failures, which existed as a live table and
--     were thrown away at logout.
--
-- Everything is local: it lives in this addon's SavedVariables and is printed
-- by /cleansive diag. Nothing is sent anywhere.

-- A dungeon has a few dozen distinct afflictions. This is a ceiling against a
-- pathological session, not a working size.
local MAX_UNLISTED = 40

function NS:GetDiagnostics()
    local global = self.dbRoot and self.dbRoot.global
    if not global then return nil end
    local record = global.diagnostics
    if type(record) ~= "table" then
        record = {}
        global.diagnostics = record
    end
    record.pending = type(record.pending) == "table" and record.pending or {}
    record.unlisted = type(record.unlisted) == "table" and record.unlisted or {}
    return record
end

-- Which event was being dispatched when a deferral was recorded. Core.lua sets
-- currentEvent around the dispatch; outside one, the cause is a player action
-- and there is no event name to give.
function NS:NotePendingFlag(flag, event)
    local record = self:GetDiagnostics()
    if not record then return end
    local entry = record.pending[flag]
    if type(entry) ~= "table" then
        entry = { count = 0 }
        record.pending[flag] = entry
    end
    entry.count = entry.count + 1
    entry.lastCause = event or "player"
end

-- Only harmful auras removed from an ally count. A combat log also records
-- enemy buffs stripped by a purge, and the two look alike in it: two entries
-- were nearly typed into the seasonal list by hand before the difference was
-- noticed. auraType carries it, so the filter is exact rather than careful.
function NS:NoteDispelledAura(spellID, name, auraType)
    if auraType ~= "DEBUFF" then return end
    spellID = tonumber(spellID)
    if not spellID or spellID == 0 then return end
    if self.GetKnownDispelType and self:GetKnownDispelType(spellID) then return end
    local record = self:GetDiagnostics()
    if not record then return end
    local entry = record.unlisted[spellID]
    if type(entry) == "table" then
        entry.count = entry.count + 1
        return
    end
    local count = 0
    for _ in pairs(record.unlisted) do count = count + 1 end
    if count >= MAX_UNLISTED then return end
    record.unlisted[spellID] = { name = tostring(name or "?"), count = 1 }
end

function NS:OnCombatLogEvent()
    local info = C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
    if not info then return end
    local ok, _, subevent, _, _, _, _, _, _, _, _, _, _, _, _, removedID, removedName, _, auraType = pcall(info)
    if not ok or subevent ~= "SPELL_DISPEL" then return end
    -- Names reach Lua as ordinary strings here, but a secret would poison the
    -- table it is stored in, so it goes through the same guard as everywhere.
    if not self:CanAccess(removedID) or not self:CanAccess(removedName) then return end
    self:NoteDispelledAura(removedID, removedName, auraType)
end

-- The engine and sound tables are live and complete; there is nothing to
-- accumulate during the session, only to keep before the client discards them.
function NS:SnapshotDiagnostics()
    local record = self:GetDiagnostics()
    if not record then return end
    record.version = self.version
    local engine = self.auraContainerDiagnostics
    if type(engine) == "table" then
        record.engine = {
            expected = engine.expected,
            added = engine.added,
            readyButtons = engine.readyButtons,
            firstError = engine.firstError,
            activeError = engine.activeError,
            retiredError = engine.retiredError,
        }
    end
    local sound = self.auraSoundDiagnostics
    if type(sound) == "table" then
        record.sound = {
            attempted = sound.attempted,
            registered = sound.registered,
            skippedUnits = sound.skippedUnits,
            season = self.KNOWN_DISPELLABLE_AURAS_SEASON,
        }
    end
end

function NS:ResetDiagnostics()
    local global = self.dbRoot and self.dbRoot.global
    if not global then return end
    global.diagnostics = nil
    self:GetDiagnostics()
    self:Print(self.L.DIAG_CLEARED)
end

function NS:PrintDiagnostics()
    self:SnapshotDiagnostics()
    local record = self:GetDiagnostics()
    if not record then return end

    local engine = record.engine
    if engine then
        self:Print(self.L.DIAG_ENGINE, tostring(engine.readyButtons or 0),
            tostring(engine.added or 0), tostring(engine.expected or 0),
            tostring(engine.firstError or "-"))
    end

    local sound = record.sound
    if sound then
        self:Print(self.L.DIAG_SOUND, tostring(sound.registered or 0),
            tostring(sound.attempted or 0), tostring(sound.skippedUnits or 0),
            tostring(sound.season or "?"))
    end

    local any = false
    for flag, entry in pairs(record.pending) do
        any = true
        self:Print(self.L.DIAG_PENDING, flag, tostring(entry.count),
            tostring(entry.lastCause))
    end
    if not any then self:Print(self.L.DIAG_PENDING_NONE) end

    any = false
    for spellID, entry in pairs(record.unlisted) do
        any = true
        self:Print(self.L.DIAG_UNLISTED, tostring(spellID), tostring(entry.name),
            tostring(entry.count))
    end
    if not any then self:Print(self.L.DIAG_UNLISTED_NONE) end
end
