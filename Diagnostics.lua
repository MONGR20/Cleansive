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
    -- A counter that never resets cannot be read. The 29/08/2026 record showed
    -- 630 deferrals and 315 refused restyles with no way to tell which session
    -- or which version produced them -- the only way to date them was to
    -- compare against an older copy of the file kept by chance. Every count is
    -- now scoped to the installed version: the numbers mean "since this
    -- version", and the version is printed beside them.
    if record.version and record.version ~= self.version then
        record.pending = {}
        record.styleFailures, record.styleError, record.styleSteps = nil, nil, nil
        record.styleContext, record.forbidden = nil, nil
        record.forbiddenVisuals = nil
        record.soundPeak = nil
    end
    record.version = self.version
    -- Dead field left by 1.5.37; it never held anything a reader could use.
    record.unlisted = nil
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

-- 12.1 knows six kinds of addon restriction, not one. InCombatLockdown()
-- answers only for Combat -- and a mythic keystone keeps ChallengeMode active
-- for the whole run, including between packs, exactly where this addon believes
-- itself free to act. Nothing here changes behaviour: it writes down what was
-- true at the instant of a refusal, so a real key can confirm or kill that
-- hypothesis instead of us reasoning about it.
local RESTRICTION_TYPES = {
    "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat",
}

function NS:RestrictionSnapshot()
    local api = C_RestrictedActions
    local types = Enum and Enum.AddOnRestrictionType
    if not (api and api.IsAddOnRestrictionActive and types) then return nil end
    local active = {}
    for _, name in ipairs(RESTRICTION_TYPES) do
        local value = types[name]
        if value ~= nil then
            local ok, isActive = pcall(api.IsAddOnRestrictionActive, value)
            if ok and isActive then active[#active + 1] = name end
        end
    end
    -- The lock flag is the whole point of the comparison: a refusal recorded
    -- with lock=0 and a restriction active is the case the code does not model.
    return "lock=" .. ((InCombatLockdown and InCombatLockdown()) and "1" or "0")
        .. "|" .. (active[1] and table.concat(active, ",") or "none")
end

-- The client tells an addon when it forbids one of its calls, with the name of
-- the function. Cleansive used to infer its refusals after the fact by asking
-- the frame whether a registration had taken; this is the first-hand account.
function NS:NoteForbiddenAction(addon, func)
    if addon ~= self.addonName then return end
    local record = self:GetDiagnostics()
    if not record then return end
    record.forbidden = type(record.forbidden) == "table" and record.forbidden or {}
    local key = tostring(func or "?")
    local entry = record.forbidden[key]
    if type(entry) ~= "table" then
        entry = { count = 0 }
        record.forbidden[key] = entry
    end
    entry.count = entry.count + 1
    entry.context = self:RestrictionSnapshot() or entry.context
end

-- Counted once per visual, not once per attempt: the point is how many cells
-- the engine has taken away, not how many times we noticed.
function NS:NoteForbiddenVisual()
    local record = self:GetDiagnostics()
    if not record then return end
    record.forbiddenVisuals = (record.forbiddenVisuals or 0) + 1
end

-- The engine can refuse to let its own labels be restyled. The call is already
-- guarded, but the reason used to be discarded: only the count survived, and a
-- count cannot tell a forbidden object from a nil field.
-- steps says how much of the pass was lost. One refused step out of nine is a
-- cosmetic dent; nine out of nine is the whole styling gone, and before 1.5.40
-- the two were indistinguishable because a single refusal aborted the rest.
function NS:NoteStyleFailure(err, steps)
    local record = self:GetDiagnostics()
    if not record then return end
    record.styleFailures = (record.styleFailures or 0) + 1
    record.styleSteps = (record.styleSteps or 0) + (tonumber(steps) or 1)
    if not record.styleError then record.styleError = tostring(err) end
    -- Grouped by context rather than kept as a single sample: the question is
    -- not what the last refusal looked like, it is whether they all happen
    -- while the addon thinks it is unlocked.
    local context = self:RestrictionSnapshot()
    if context then
        record.styleContext = type(record.styleContext) == "table" and record.styleContext or {}
        record.styleContext[context] = (record.styleContext[context] or 0) + 1
    end
end

-- The snapshot is taken at logout, so it describes the player standing alone in
-- a capital: 46 registrations for one unit. The dungeon it was meant to measure
-- is exactly what it cannot see. The peak is kept as it happens instead.
function NS:NoteSoundLoad(attempted, units, registered)
    local record = self:GetDiagnostics()
    if not record then return end
    local peak = record.soundPeak
    if type(peak) ~= "table" then
        peak = { attempted = 0, units = 0, registered = 0 }
        record.soundPeak = peak
    end
    if (tonumber(attempted) or 0) > peak.attempted then
        peak.attempted = tonumber(attempted) or 0
        peak.units = tonumber(units) or 0
        peak.registered = tonumber(registered) or 0
    end
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

    local peak = record.soundPeak
    if peak and peak.attempted > 0 then
        self:Print(self.L.DIAG_SOUND_PEAK, tostring(peak.registered or 0),
            tostring(peak.attempted), tostring(peak.units or 0))
        -- The peak is the only place a dungeon-sized failure can show up: the
        -- logout snapshot has already fallen back to a single unit.
        if (peak.registered or 0) < peak.attempted then problems = problems + 1 end
    end

    for name in pairs(record.refusedEvents or {}) do
        problems = problems + 1
        self:Print(self.L.DIAG_REFUSED, name)
    end
    if record.styleFailures then
        problems = problems + 1
        self:Print(self.L.DIAG_STYLE, tostring(record.styleFailures),
            tostring(record.styleSteps or record.styleFailures),
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
    if record.forbiddenVisuals then
        problems = problems + 1
        self:Print(self.L.DIAG_FORBIDDEN_VISUAL, tostring(record.forbiddenVisuals))
    end
    for context, count in pairs(record.styleContext or {}) do
        self:Print(self.L.DIAG_STYLE_CONTEXT, context, tostring(count))
    end
    for func, entry in pairs(record.forbidden or {}) do
        problems = problems + 1
        self:Print(self.L.DIAG_FORBIDDEN, func, tostring(entry.count),
            tostring(entry.context or "-"))
    end
    local now = self:RestrictionSnapshot()
    if now then self:Print(self.L.DIAG_RESTRICTIONS, now) end

    self:Print(self.L.DIAG_SCOPE, tostring(record.version or "?"))
    if problems == 0 then
        self:Print(self.L.DIAG_HEALTHY)
    else
        self:Print(self.L.DIAG_PROBLEMS, tostring(problems))
    end
end
