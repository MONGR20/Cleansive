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

--------------------------------------------------------------------------
-- Profile transfer
--------------------------------------------------------------------------

-- Only these keys travel, and only with these shapes. An import is a string a
-- stranger wrote: nothing outside this table can enter a profile, and the text
-- is never handed to loadstring. A key=value parser cannot execute anything.
--
-- Deliberately absent: positions (a screen the sender had, not the one you
-- have), language (it is global, not per profile), and the priority and skip
-- lists (they name the sender's guildmates, not yours).
local TRANSFER_FIELDS = {
    { key = "enabled", kind = "boolean" },
    { key = "locked", kind = "boolean" },
    { key = "showPets", kind = "boolean" },
    { key = "showFocus", kind = "boolean" },
    { key = "showNames", kind = "boolean" },
    { key = "showTooltips", kind = "boolean" },
    { key = "sound", kind = "boolean" },
    { key = "failureSound", kind = "boolean" },
    { key = "showCooldown", kind = "boolean" },
    { key = "showStacks", kind = "boolean" },
    { key = "showClickHints", kind = "boolean" },
    { key = "autoHide", kind = "boolean" },
    { key = "afflictedOnly", kind = "boolean" },
    { key = "groupManualTypes", kind = "boolean" },
    { key = "frameSize", kind = "number", min = 12, max = 40, step = 1 },
    { key = "spacing", kind = "number", min = 0, max = 12, step = 1 },
    { key = "columns", kind = "number", min = 1, max = 20, step = 1 },
    { key = "blacklistTime", kind = "number", min = 0, max = 15, step = 1 },
    { key = "soundMaxRegistrations", kind = "number", min = 500, max = 8000, step = 1 },
    { key = "testUnits", kind = "number", min = 1, max = 40, step = 1 },
    { key = "inactiveAlpha", kind = "number", min = 0.05, max = 0.80 },
    { key = "grow", kind = "enum", values = { "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP" } },
    { key = "layoutMode", kind = "enum", values = { "GRID", "HORIZONTAL", "VERTICAL" } },
    { key = "soundChannel", kind = "enum", values = { "Master", "SFX", "Dialog" } },
    { key = "testState", kind = "enum", values = { "MIXED", "ALL", "HEALTHY" } },
    { key = "typeOrder", kind = "typelist" },
    { key = "enabledTypes", kind = "typemap" },
    { key = "ignoredAlways", kind = "idset" },
    { key = "ignoredCombat", kind = "idset" },
}

local TRANSFER_PREFIX = "CLEANSIVE1"
local VALID_TYPES = { Magic = true, Curse = true, Poison = true, Disease = true, Bleed = true, Charm = true }

local function encodeValue(field, value)
    if field.kind == "boolean" then return value and "1" or "0" end
    if field.kind == "number" then
        if field.step == 1 then return tostring(math.floor(value + 0.5)) end
        return string.format("%.4f", value)
    end
    if field.kind == "enum" then return tostring(value) end
    if field.kind == "typelist" then
        local parts = {}
        for _, dispelType in ipairs(value) do parts[#parts + 1] = dispelType end
        return table.concat(parts, ",")
    end
    if field.kind == "typemap" then
        local parts = {}
        for dispelType in pairs(VALID_TYPES) do
            parts[#parts + 1] = dispelType .. ":" .. (value[dispelType] == false and "0" or "1")
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    if field.kind == "idset" then
        local ids = {}
        for id in pairs(value) do
            local number = tonumber(id)
            if number then ids[#ids + 1] = number end
        end
        table.sort(ids)
        local parts = {}
        for index, id in ipairs(ids) do parts[index] = tostring(id) end
        return table.concat(parts, ",")
    end
end

-- Returns nil when the text does not describe a valid value. Silence is not an
-- option here: a rejected field must be reported, never quietly defaulted, or
-- an import would look like it worked and leave half the settings behind.
local function decodeValue(field, text)
    if field.kind == "boolean" then
        if text == "1" then return true end
        if text == "0" then return false end
        return nil
    end
    if field.kind == "number" then
        local number = tonumber(text)
        if not number then return nil end
        if number < field.min or number > field.max then return nil end
        if field.step == 1 then number = math.floor(number + 0.5) end
        return number
    end
    if field.kind == "enum" then
        for _, candidate in ipairs(field.values) do
            if candidate == text then return candidate end
        end
        return nil
    end
    if field.kind == "typelist" then
        local list, seen = {}, {}
        for part in string.gmatch(text, "[^,]+") do
            if not VALID_TYPES[part] or seen[part] then return nil end
            seen[part] = true
            list[#list + 1] = part
        end
        -- A partial order would silently drop a type from the interface.
        for dispelType in pairs(VALID_TYPES) do
            if not seen[dispelType] then return nil end
        end
        return list
    end
    if field.kind == "typemap" then
        local map = {}
        for part in string.gmatch(text, "[^,]+") do
            local name, state = string.match(part, "^(%a+):([01])$")
            if not name or not VALID_TYPES[name] then return nil end
            map[name] = state == "1"
        end
        for dispelType in pairs(VALID_TYPES) do
            if map[dispelType] == nil then return nil end
        end
        return map
    end
    if field.kind == "idset" then
        local set = {}
        if text ~= "" then
            for part in string.gmatch(text, "[^,]+") do
                local id = tonumber(part)
                if not id or id <= 0 or id ~= math.floor(id) then return nil end
                set[id] = true
            end
        end
        return set
    end
end

function NS:ExportProfile()
    local parts = { TRANSFER_PREFIX }
    for _, field in ipairs(TRANSFER_FIELDS) do
        local value = self.db and self.db[field.key]
        if value ~= nil then
            parts[#parts + 1] = field.key .. "=" .. encodeValue(field, value)
        end
    end
    return table.concat(parts, ";")
end

-- Reads without writing. The caller shows what would change and only then asks
-- for a second click: an import that applies on the first one is a setup lost.
function NS:AnalyzeProfileImport(text)
    text = type(text) == "string" and string.gsub(text, "%s", "") or ""
    if text == "" then return nil, self.L.IMPORT_EMPTY end
    local prefix = string.match(text, "^([^;]+);")
    if prefix ~= TRANSFER_PREFIX then return nil, self.L.IMPORT_BAD_PREFIX end

    local byKey = {}
    for _, field in ipairs(TRANSFER_FIELDS) do byKey[field.key] = field end

    local accepted, changes, rejected = {}, {}, {}
    local seen = {}
    for chunk in string.gmatch(string.sub(text, #prefix + 2), "[^;]+") do
        local key, raw = string.match(chunk, "^([%a]+)=(.*)$")
        local field = key and byKey[key]
        if not field then
            rejected[#rejected + 1] = key or chunk
        elseif seen[key] then
            rejected[#rejected + 1] = key
        else
            seen[key] = true
            local value = decodeValue(field, raw)
            if value == nil then
                rejected[#rejected + 1] = key
            else
                accepted[key] = value
                local current = self.db and self.db[field.key]
                if encodeValue(field, value) ~= (current ~= nil and encodeValue(field, current) or nil) then
                    changes[#changes + 1] = {
                        key = key,
                        from = current ~= nil and encodeValue(field, current) or "-",
                        to = encodeValue(field, value),
                    }
                end
            end
        end
    end
    if not next(accepted) then return nil, self.L.IMPORT_NOTHING_VALID end
    table.sort(changes, function(a, b) return a.key < b.key end)
    table.sort(rejected)
    return { accepted = accepted, changes = changes, rejected = rejected }
end

function NS:ApplyProfileImport(analysis)
    if not analysis or not analysis.accepted or not self.db then return false end
    for key, value in pairs(analysis.accepted) do self.db[key] = value end
    self.enabled = self.db.enabled and true or false
    self.deferRefreshes = true
    self:UpdateSpells()
    self:RebuildRoster()
    self.deferRefreshes = false
    self:ApplySecureBindings()
    self:LayoutButtons()
    self:RefreshAll(true)
    self:UpdateGridVisibilityDriver()
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("profile imported") end
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(string.format(self.L.IMPORT_APPLIED, #analysis.changes))
    return true
end

-- Copying to another specialization of the same character. The target may not
-- exist yet, which is the common case: you set one spec up and want the other
-- to match before you ever play it.
function NS:CopyProfileToSpec(specKey)
    specKey = tostring(specKey or "")
    if specKey == "" or specKey == tostring(self.activeSpecKey) then return false end
    local characterKey = self.activeCharacterKey
    local profiles = self.dbRoot and self.dbRoot.profiles
    if not profiles or not characterKey or not profiles[characterKey] then return false end
    local copy = deepCopy(self.db)
    copy.positions = deepCopy(self.profileDefaults.positions)
    profiles[characterKey][specKey] = copy
    self:Print(string.format(self.L.PROFILE_COPIED, specKey))
    return true
end

--------------------------------------------------------------------------
-- Presets and per-page reset
--------------------------------------------------------------------------

-- Four starting points, not four modes: a preset writes ordinary settings the
-- player can then change one by one. Nothing here is remembered as "the preset
-- you are on", because the moment you move a slider you would no longer be on
-- it and the label would lie.
NS.VISUAL_PRESETS = {
    { key = "COMPACT", values = {
        frameSize = 18, spacing = 2, columns = 10, inactiveAlpha = 0.15,
        showNames = false, showClickHints = false, showStacks = false, showCooldown = true } },
    { key = "READABLE", values = {
        frameSize = 34, spacing = 6, columns = 8, inactiveAlpha = 0.30,
        showNames = true, showClickHints = true, showStacks = true, showCooldown = true } },
    { key = "RAID", values = {
        frameSize = 20, spacing = 1, columns = 8, inactiveAlpha = 0.15,
        showNames = false, showClickHints = true, showStacks = false, showCooldown = true } },
    { key = "MINIMAL", values = {
        frameSize = 16, spacing = 1, columns = 12, inactiveAlpha = 0.05,
        showNames = false, showClickHints = false, showStacks = false, showCooldown = false } },
}

function NS:ApplyVisualPreset(key)
    local preset
    for _, candidate in ipairs(self.VISUAL_PRESETS) do
        if candidate.key == key then preset = candidate end
    end
    if not preset or not self.db then return false end
    for setting, value in pairs(preset.values) do self.db[setting] = value end
    self:LayoutButtons()
    self:RefreshAll(true)
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(string.format(self.L.PRESET_APPLIED, self.L["PRESET_" .. key]))
    return true
end

-- One reset per page rather than one for everything. A player who wants his
-- grid back should not have to lose his lists and his filters to get it.
NS.PAGE_RESET_KEYS = {
    general = { "enabled", "locked", "showPets", "showFocus", "showTooltips",
        "sound", "failureSound", "soundChannel", "soundMaxRegistrations",
        "blacklistTime", "autoHide" },
    appearance = { "frameSize", "spacing", "columns", "inactiveAlpha", "grow",
        "layoutMode", "showNames", "showCooldown", "showStacks", "showClickHints",
        "afflictedOnly", "testUnits", "testState", "positions" },
    dispels = { "typeOrder", "enabledTypes", "groupManualTypes", "priority", "skip" },
}

function NS:ResetOptionsPage(page)
    local keys = self.PAGE_RESET_KEYS[page or ""]
    if not keys or not self.db then return false end
    for _, key in ipairs(keys) do
        self.db[key] = deepCopy(self.profileDefaults[key])
    end
    self.enabled = self.db.enabled and true or false
    self.deferRefreshes = true
    self:UpdateSpells()
    self:RebuildRoster()
    self.deferRefreshes = false
    self:ApplySecureBindings()
    self:RestorePosition(self.gridAnchor, "grid")
    self:LayoutButtons()
    self:RefreshAll(true)
    self:UpdateGridVisibilityDriver()
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("page reset") end
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(string.format(self.L.PAGE_RESET_DONE, #keys))
    return true
end
