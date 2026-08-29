local _, NS = ...

-- What a session leaves behind for whoever has to explain it afterwards.
--
-- Three things earned their place here on 28/08/2026, each because its absence
-- cost an evening:
--
--   * A pending flag with no record of what raised it. The pending plate was
--     appearing during dungeon pulls and the only way to find out why was to
--     audit eleven flags by hand against every event that can set them.
--   * The client's own refusals: an event registration it declines, and a
--     restyle it forbids. Neither raises, so neither left a trace.
--   * The protected engine's own failures, which existed as a live table and
--     were thrown away at logout.
--
-- Everything is local: it lives in this addon's SavedVariables and is printed
-- by /cleansive diag. Nothing is sent anywhere.

function NS:GetDiagnostics()
    local global = self.dbRoot and self.dbRoot.global
    if not global then return nil end
    local record = global.diagnostics
    if type(record) ~= "table" then
        record = {}
        global.diagnostics = record
    end
    record.pending = type(record.pending) == "table" and record.pending or {}
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

-- The engine can refuse to let its own labels be restyled. The call is already
-- guarded, but the reason used to be discarded: only the count survived, and a
-- count cannot tell a forbidden object from a nil field.
function NS:NoteStyleFailure(err)
    local record = self:GetDiagnostics()
    if not record then return end
    record.styleFailures = (record.styleFailures or 0) + 1
    if not record.styleError then record.styleError = tostring(err) end
end

-- A refused event registration does not raise: it fires ADDON_ACTION_FORBIDDEN,
-- which shows the player a dialog whose first button disables this addon. The
-- refusal is remembered so the attempt is made once in the addon's life rather
-- than at every login.
function NS:NoteRefusedEvent(name)
    local record = self:GetDiagnostics()
    if not record then return end
    record.refusedEvents = type(record.refusedEvents) == "table" and record.refusedEvents or {}
    record.refusedEvents[name] = true
end

function NS:IsEventRefused(name)
    local record = self:GetDiagnostics()
    return record and record.refusedEvents and record.refusedEvents[name] or false
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

    for name in pairs(record.refusedEvents or {}) do
        self:Print(self.L.DIAG_REFUSED, name)
    end
    if record.styleFailures then
        self:Print(self.L.DIAG_STYLE, tostring(record.styleFailures),
            tostring(record.styleError or "-"))
    end

    local any = false
    for flag, entry in pairs(record.pending) do
        any = true
        self:Print(self.L.DIAG_PENDING, flag, tostring(entry.count),
            tostring(entry.lastCause))
    end
    if not any then self:Print(self.L.DIAG_PENDING_NONE) end

end
