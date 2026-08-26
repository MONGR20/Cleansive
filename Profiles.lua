local _, NS = ...

local SCHEMA_VERSION = 2

local function deepCopy(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do result[key] = deepCopy(value) end
    return result
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
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if not name and UnitName then name, realm = UnitName("player") end
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
        .. "  •  " .. tostring(specName or "Default")
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
                language = migrated.language == "frFR" and "frFR" or "enUS",
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
    raw.global.language = raw.global.language == "frFR" and "frFR" or "enUS"
    if raw.global.setupComplete == nil then raw.global.setupComplete = true end
    raw.profiles[characterKey] = type(raw.profiles[characterKey]) == "table" and raw.profiles[characterKey] or {}
    self.dbRoot = raw

    -- 1.5.4 shipped "group untargetable cleanses" enabled, and applyDefaults
    -- wrote that into every profile. On the protected path the grouped types
    -- lost their engine cell without gaining a reliable replacement, so the
    -- option goes back to opt-in -- including for profiles that already
    -- recorded it. Runs once; a later deliberate choice is left alone.
    if not raw.global.groupManualOptOut then
        raw.global.groupManualOptOut = true
        for _, stored in pairs(raw.profiles[characterKey]) do
            if type(stored) == "table" then stored.groupManualTypes = false end
        end
    end

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
    prune(profile)
    absorbHistory(raw.global, profile)
    profile.language = raw.global.language

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
    prune(profile)
    absorbHistory(self.dbRoot.global, profile)
    profile.language = self.dbRoot.global.language
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
        self.pendingProfileSwitch = true
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
    self:LayoutButtons()
    self:RestorePosition(self.gridAnchor, "grid")
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
