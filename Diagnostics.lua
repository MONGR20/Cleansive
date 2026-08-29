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

-- Keep only the refusals that still mean something. A name the addon no longer
-- registers cannot be refused again, and printing it reads as a live problem.
function NS:ForgetRefusalsOutside(names)
    local record = self:GetDiagnostics()
    if not record or type(record.refusedEvents) ~= "table" then return end
    local current = {}
    for _, name in ipairs(names or {}) do current[name] = true end
    for name in pairs(record.refusedEvents) do
        if not current[name] then record.refusedEvents[name] = nil end
    end
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
            -- soundstatus shows the live error; the point of the record is to
            -- still have it after the client has thrown the table away.
            error = sound.error,
            pending = sound.pending,
            retries = sound.retries,
        }
    end
end

-- The refusals survive: they are not part of the report, they are why the addon
-- does not ask again. Clearing them would send it back for the same dialog at
-- the next login.
function NS:ResetDiagnostics()
    local global = self.dbRoot and self.dbRoot.global
    if not global then return end
    local refused = type(global.diagnostics) == "table" and global.diagnostics.refusedEvents or nil
    global.diagnostics = nil
    local record = self:GetDiagnostics()
    if record and refused then record.refusedEvents = refused end
    self:Print(self.L.DIAG_CLEARED)
end

function NS:PrintDiagnostics()
    self:SnapshotDiagnostics()
    local record = self:GetDiagnostics()
    if not record then return end

    local problems = 0

    local engine = record.engine
    if engine then
        self:Print(self.L.DIAG_ENGINE, tostring(engine.readyButtons or 0),
            tostring(engine.added or 0), tostring(engine.expected or 0),
            tostring(engine.firstError or "-"))
        -- A live type that failed and an old type that would not go quiet are
        -- different faults with different answers; firstError alone conflated
        -- them into one line.
        if engine.activeError then
            problems = problems + 1
            self:Print(self.L.DIAG_ENGINE_ACTIVE, tostring(engine.activeError))
        end
        if engine.retiredError then
            problems = problems + 1
            self:Print(self.L.DIAG_ENGINE_RETIRED, tostring(engine.retiredError))
        end
    end

    local sound = record.sound
    if sound then
        self:Print(self.L.DIAG_SOUND, tostring(sound.registered or 0),
            tostring(sound.attempted or 0), tostring(sound.skippedUnits or 0),
            tostring(sound.season or "?"))
        if sound.error then
            problems = problems + 1
            self:Print(self.L.DIAG_SOUND_ERROR, tostring(sound.error),
                tostring(sound.retries or 0))
        end
    end

    for name in pairs(record.refusedEvents or {}) do
        problems = problems + 1
        self:Print(self.L.DIAG_REFUSED, name)
    end
    if record.styleFailures then
        problems = problems + 1
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

    -- A deferral is not a fault: the plate is the addon working as designed.
    -- Only the client's refusals and the engine's failures count here.
    if problems == 0 then
        self:Print(self.L.DIAG_HEALTHY)
    else
        self:Print(self.L.DIAG_PROBLEMS, tostring(problems))
    end
end
