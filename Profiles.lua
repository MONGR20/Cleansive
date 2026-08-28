local _, NS = ...

local SCHEMA_VERSION = 2

-- Until 1.5.7 an unset language fell back to English, so a French client
-- showed English labels next to the French spell and class names the game
-- API returns. Only a value the player actually chose is preserved; anything
-- else follows the client.
local function normalizeLanguage(value)
    if value == "frFR" or value == "enUS" then return value end
    return GetLocale() == "frFR" and "frFR" or "enUS"
end

local function deepCopy(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do result[key] = deepCopy(value) end
    return result
end

-- applyDefaults only fills what is missing, so a value that is present but
-- wrong survived it and reached CreateFrame: a string where a number belongs,
-- an opacity outside its slider, a layout mode that no longer exists. Bounds
-- are the ones the option sliders enforce, so a repaired profile always lands
-- somewhere the interface can actually represent.
local NUMERIC_BOUNDS = {
    frameSize = { 12, 40 },
    spacing = { 0, 12 },
    columns = { 1, 20 },
    inactiveAlpha = { 0.05, 0.80 },
    blacklistTime = { 0, 15 },
    soundMaxRegistrations = { 500, 8000 },
}

local ALLOWED_VALUES = {
    grow = { RIGHT_DOWN = true, RIGHT_UP = true, LEFT_DOWN = true, LEFT_UP = true },
    layoutMode = { GRID = true, HORIZONTAL = true, VERTICAL = true },
    soundChannel = { Master = true, SFX = true, Dialog = true },
}

-- The nine anchor points SetPoint accepts. Anything else raises, and a saved
-- position goes straight there at load: a hand-edited or truncated database
-- could stop the addon from starting at all.
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- The sliders all represent whole steps, so a fractional value that survived
-- clamping produced fractional layout arithmetic.
local INTEGER_SETTINGS = {
    frameSize = true, spacing = true, columns = true,
    blacklistTime = true, soundMaxRegistrations = true,
}

local BOOLEAN_SETTINGS = {
    "enabled", "locked", "showPets", "showFocus", "showNames", "showTooltips",
    "sound", "failureSound", "showCooldown", "showStacks", "showClickHints",
    "autoHide", "afflictedOnly", "groupManualTypes",
}

local function normalizePositions(profile, fallback)
    if type(profile.positions) ~= "table" then
        profile.positions = deepCopy(fallback.positions)
        return
    end
    for key, default in pairs(fallback.positions or {}) do
        local saved = profile.positions[key]
        if type(saved) ~= "table" then
            profile.positions[key] = deepCopy(default)
        else
            if not ANCHOR_POINTS[saved.point] then saved.point = default.point end
            if not ANCHOR_POINTS[saved.relativePoint] then saved.relativePoint = default.relativePoint end
            saved.x = tonumber(saved.x) or default.x
            saved.y = tonumber(saved.y) or default.y
        end
    end
end

-- typeOrder drives priority, click mapping and the grouped indicator. A
-- duplicate, an unknown name or a missing type silently dropped a dispel type
-- out of the interface, so it is rebuilt: the valid entries in their saved
-- order, then whatever is missing.
local function normalizeDispelTypes(profile, fallback)
    local known = {}
    for _, auraType in ipairs(fallback.typeOrder or {}) do known[auraType] = true end

    local rebuilt, seen = {}, {}
    for _, auraType in ipairs(type(profile.typeOrder) == "table" and profile.typeOrder or {}) do
        if known[auraType] and not seen[auraType] then
            seen[auraType] = true
            rebuilt[#rebuilt + 1] = auraType
        end
    end
    for _, auraType in ipairs(fallback.typeOrder or {}) do
        if not seen[auraType] then rebuilt[#rebuilt + 1] = auraType end
    end
    profile.typeOrder = rebuilt

    if type(profile.enabledTypes) ~= "table" then profile.enabledTypes = {} end
    for auraType in pairs(known) do
        local value = profile.enabledTypes[auraType]
        if type(value) ~= "boolean" then
            profile.enabledTypes[auraType] = (fallback.enabledTypes or {})[auraType] ~= false
        end
    end
    for auraType in pairs(profile.enabledTypes) do
        if not known[auraType] then profile.enabledTypes[auraType] = nil end
    end
end

local function normalizeProfile(profile, fallback)
    if type(profile) ~= "table" or type(fallback) ~= "table" then return end
    for key, bounds in pairs(NUMERIC_BOUNDS) do
        local value = tonumber(profile[key])
        if not value then
            profile[key] = fallback[key]
        else
            value = math.max(bounds[1], math.min(bounds[2], value))
            if INTEGER_SETTINGS[key] then value = math.floor(value + 0.5) end
            profile[key] = value
        end
    end
    for key, allowed in pairs(ALLOWED_VALUES) do
        if not allowed[profile[key]] then profile[key] = fallback[key] end
    end
    -- A non-boolean must fall back to the default, not be read for its Lua
    -- truthiness: "false", "non" and 0 are all truthy, so a database saying
    -- locked = "false" came back locked.
    for _, key in ipairs(BOOLEAN_SETTINGS) do
        local value = profile[key]
        if value ~= nil and type(value) ~= "boolean" then
            profile[key] = fallback[key]
        end
    end
    normalizePositions(profile, fallback)
    normalizeDispelTypes(profile, fallback)
end

local function applyDefaults(source, destination)
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then destination[key] = {} end
            applyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

function NS:GetCharacterProfileKey()
    local realm
    -- The short name only: the realm is appended below. SafeUnitFullName
    -- already carries it and would produce "Ekinoks-Hyjal-Hyjal", orphaning
    -- every profile ever saved.
    local name = NS:SafeUnitName("player")
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or "Realm"
    end
    return tostring(name or "Player") .. "-" .. tostring(realm or "Realm")
end

-- Specialization data is not available yet at ADDON_LOADED. Returning nil
-- instead of a "0" placeholder keeps a bogus profile out of the saved
-- variables: the real profile is bound once PLAYER_ENTERING_WORLD fires.
function NS:GetSpecializationProfileKey()
    local index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization() or nil
    local specID, specName
    if index and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(index)
    end
    if not specID then return nil, nil end
    return tostring(specID), tostring(specName or "Default")
end

-- Settings that belonged to features removed in 1.2.6. They survive inside
-- migrated databases and would otherwise be carried forward for ever.
local OBSOLETE_KEYS = { "liveCount", "scanInterval", "showLiveList" }

local function prune(profile)
    if type(profile) ~= "table" then return end
    for _, key in ipairs(OBSOLETE_KEYS) do profile[key] = nil end
    if type(profile.positions) == "table" then profile.positions.bar = nil end
end

-- 1.4.2 moved the affliction history out of the profiles and into the global
-- section. Profiles written before that still carry their own copy: fold it
-- into the shared history once, then drop it rather than discarding entries.
local function absorbHistory(global, profile)
    if type(profile) ~= "table" then return end
    local order, history = profile.auraHistoryOrder, profile.auraHistory
    if type(order) == "table" and type(history) == "table" then
        global.auraHistory = type(global.auraHistory) == "table" and global.auraHistory or {}
        global.auraHistoryOrder = type(global.auraHistoryOrder) == "table" and global.auraHistoryOrder or {}
        for index = 1, #order do
            local id = tonumber(order[index]) or order[index]
            local record = history[id] or history[tostring(id)]
            if record and not global.auraHistory[id] then
                global.auraHistory[id] = record
                global.auraHistoryOrder[#global.auraHistoryOrder + 1] = id
            end
        end
        while #global.auraHistoryOrder > 100 do
            local oldest = table.remove(global.auraHistoryOrder, 1)
            global.auraHistory[oldest] = nil
            global.auraHistory[tostring(oldest)] = nil
        end
    end
    profile.auraHistory = nil
    profile.auraHistoryOrder = nil
end

function NS:GetActiveProfileLabel()
    local specName = self.activeSpecName
    if not specName then specName = select(2, self:GetSpecializationProfileKey()) end
    return tostring(self.activeCharacterKey or self:GetCharacterProfileKey())
        .. "  -  " .. tostring(specName or "Default")
end

function NS:GetAuraHistory()
    local global = self.dbRoot and self.dbRoot.global
    if not global then return {}, {} end
    global.auraHistory = type(global.auraHistory) == "table" and global.auraHistory or {}
    global.auraHistoryOrder = type(global.auraHistoryOrder) == "table" and global.auraHistoryOrder or {}
    return global.auraHistory, global.auraHistoryOrder
end

function NS:InitializeProfiles()
    local raw = type(CleansiveDB) == "table" and CleansiveDB or {}
    local freshInstall = next(raw) == nil
    local characterKey = self:GetCharacterProfileKey()
    local specKey, specName = self:GetSpecializationProfileKey()

    if raw.schemaVersion ~= SCHEMA_VERSION or type(raw.profiles) ~= "table" then
        local migrated = deepCopy(raw)
        prune(migrated)
        raw = {
            schemaVersion = SCHEMA_VERSION,
            global = {
                language = normalizeLanguage(migrated.language),
                setupComplete = not freshInstall,
                -- The pre-1.4 database was account-wide. Keep it as the seed
                -- for every character's first profile, otherwise every alt
                -- but the first one to log in would silently start from
                -- scratch.
                migratedSeed = not freshInstall and migrated or nil,
            },
            profiles = {},
        }
        if specKey then raw.profiles[characterKey] = { [specKey] = migrated } end
        CleansiveDB = raw
    end

    raw.global = type(raw.global) == "table" and raw.global or {}
    raw.global.language = normalizeLanguage(raw.global.language)
    if raw.global.setupComplete == nil then raw.global.setupComplete = true end
    raw.profiles[characterKey] = type(raw.profiles[characterKey]) == "table" and raw.profiles[characterKey] or {}
    self.dbRoot = raw

    -- 1.5.4 shipped "group untargetable cleanses" enabled, and applyDefaults
    -- wrote that into every profile. On the protected path the grouped types
    -- lost their engine cell without gaining a reliable replacement, so the
    -- option goes back to opt-in -- including for profiles that already
    -- recorded it. Runs once; a later deliberate choice is left alone.
    -- The original global marker was already consumed by 1.5.8 after only
    -- visiting the logged-in character. A distinct marker is required here:
    -- reusing groupManualOptOut would skip this repaired all-profile sweep on
    -- the exact databases it is meant to fix.
    if not raw.global.groupManualOptOutAllProfiles159 then
        raw.global.groupManualOptOutAllProfiles159 = true
        raw.global.groupManualOptOut = true
        for _, character in pairs(raw.profiles) do
            if type(character) == "table" then
                for _, stored in pairs(character) do
                    if type(stored) == "table" then stored.groupManualTypes = false end
                end
            end
        end
    end

    -- 1.5.16 swept showStacks to false in every existing profile. That was
    -- wrong: a migration may repair invalid data or a removed feature, but the
    -- stack count is still supported and still has its button, so the sweep
    -- erased a choice a player had deliberately made. The new default applies
    -- to new profiles only, which is what a changed default means. The sweep is
    -- gone; the databases it already touched cannot be recovered.

    for _, stored in pairs(raw.profiles[characterKey]) do
        prune(stored)
        absorbHistory(raw.global, stored)
    end

    local profile
    if specKey then
        profile = raw.profiles[characterKey][specKey]
        if type(profile) ~= "table" then profile = self:NewProfileTable(characterKey) end
        raw.profiles[characterKey][specKey] = profile
    else
        -- Boot on a throwaway copy so nothing is written under an unknown key.
        profile = self:NewProfileTable(characterKey)
        self.bootstrapProfile = true
    end
    applyDefaults(self.profileDefaults, profile)
    normalizeProfile(profile, self.profileDefaults)
    prune(profile)
    absorbHistory(raw.global, profile)
    profile.language = raw.global.language

    -- Two profiles can share a grouped set but not a skip list, and the
    -- indicator signature only watches the set. Forget on every switch.
    if self.InvalidateGroupedCache then self:InvalidateGroupedCache() end
    self.db = profile
    self.activeCharacterKey = characterKey
    self.activeSpecKey = specKey
    self.activeSpecName = specName
end

-- A brand-new profile inherits the migrated account-wide settings when the
-- character has none yet, and falls back to the defaults afterwards.
function NS:NewProfileTable(characterKey)
    local raw = self.dbRoot
    local characterProfiles = raw and raw.profiles and raw.profiles[characterKey]
    local seed
    if raw and raw.global and next(characterProfiles or {}) == nil then
        seed = raw.global.migratedSeed
    end
    local profile = deepCopy(seed or self.profileDefaults)
    applyDefaults(self.profileDefaults, profile)
    normalizeProfile(profile, self.profileDefaults)
    prune(profile)
    return profile
end

function NS:LoadCurrentProfile(cloneCurrent)
    if not self.dbRoot then return false end
    local characterKey = self:GetCharacterProfileKey()
    local specKey, specName = self:GetSpecializationProfileKey()
    -- Still no specialization data: keep booting on the throwaway profile
    -- rather than persisting anything under an unknown key.
    if not specKey then return false end
    if characterKey == self.activeCharacterKey and specKey == self.activeSpecKey then return false end

    local profiles = self.dbRoot.profiles
    profiles[characterKey] = type(profiles[characterKey]) == "table" and profiles[characterKey] or {}

    -- Versions up to 1.4.0 resolved the profile before the specialization was
    -- known and persisted the result under the key "0". Now that a real key is
    -- available, drop it: it is never selected again, and it diverges from the
    -- profile the player actually edits.
    if specKey ~= "0" and profiles[characterKey]["0"] then
        profiles[characterKey]["0"] = nil
        self.prunedGhostProfile = true
    end

    local profile = profiles[characterKey][specKey]
    if type(profile) ~= "table" then
        if cloneCurrent and not self.bootstrapProfile then
            profile = deepCopy(self.db)
        else
            profile = self:NewProfileTable(characterKey)
        end
        profiles[characterKey][specKey] = profile
    end
    applyDefaults(self.profileDefaults, profile)
    normalizeProfile(profile, self.profileDefaults)
    prune(profile)
    absorbHistory(self.dbRoot.global, profile)
    profile.language = self.dbRoot.global.language
    -- Two profiles can share a grouped set but not a skip list, and the
    -- indicator signature only watches the set. Forget on every switch.
    if self.InvalidateGroupedCache then self:InvalidateGroupedCache() end
    self.db = profile
    self.activeCharacterKey = characterKey
    self.activeSpecKey = specKey
    self.activeSpecName = specName
    self.enabled = profile.enabled and true or false
    self.gridManuallyHidden = false
    self.pendingEnabled = nil
    return true
end

function NS:QueueProfileSwitch()
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingProfileSwitch")
        return false
    end
    if not self:LoadCurrentProfile(true) then
        self:UpdateSpells()
        return false
    end
    self.deferRefreshes = true
    self:UpdateSpells()
    self:RebuildRoster()
    self.deferRefreshes = false
    self:ApplySecureBindings()
    -- Position first, for the same reason as FlushCombatUpdates.
    self:RestorePosition(self.gridAnchor, "grid")
    self:LayoutButtons()
    self:UpdateGridVisibilityDriver()
    self:ApplyPriorityDispelBinding()
    self:RefreshOptions()
    self:RequestAuraSoundRefresh("profile changed")
    self:RefreshAll(true)
    if self.bootstrapProfile then
        -- Binding the real profile after login is not a profile change.
        self.bootstrapProfile = nil
        if self.prunedGhostProfile then
            self.prunedGhostProfile = nil
            self:Print(self.L.PROFILE_GHOST_REMOVED)
        end
    else
        self:Print(self.L.PROFILE_CHANGED, self:GetActiveProfileLabel())
    end
    return true
end
