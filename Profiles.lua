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
local TRANSFER_FIELDS = {
    { key = "enabled", kind = "boolean" },
    { key = "locked", kind = "boolean" },
    { key = "showPets", kind = "boolean" },
    { key = "showFocus", kind = "boolean" },
    { key = "showNames", kind = "boolean" },
    { key = "classColorCells", kind = "boolean" },
    { key = "separateRaidSize", kind = "boolean" },
    { key = "raidFrameSize", kind = "number", min = 12, max = 40, step = 1 },
    { key = "raidSpacing", kind = "number", min = 0, max = 12, step = 1 },
    { key = "alertSound", kind = "enum",
      values = { "DEFAULT", "RAID_WARNING", "READY_CHECK", "QUEST_FAILED", "ALARM" } },
    { key = "showTooltips", kind = "boolean" },
    { key = "sound", kind = "boolean" },
    { key = "failureSound", kind = "boolean" },
    { key = "showCooldown", kind = "boolean" },
    { key = "showDuration", kind = "boolean" },
    { key = "controlWarning", kind = "boolean" },
    { key = "showStacks", kind = "boolean" },
    { key = "showClickHints", kind = "boolean" },
    { key = "autoHide", kind = "boolean" },
    { key = "showSolo", kind = "boolean" },
    { key = "showParty", kind = "boolean" },
    { key = "showRaid", kind = "boolean" },
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
    { key = "sortMode", kind = "enum", values = { "GROUP", "ROLE", "CLASS" } },
    { key = "soundChannel", kind = "enum", values = { "Master", "SFX", "Dialog" } },
    { key = "testState", kind = "enum", values = { "MIXED", "ALL", "HEALTHY" } },
    { key = "typeOrder", kind = "typelist" },
    { key = "enabledTypes", kind = "typemap" },
    { key = "ignoredAlways", kind = "idset" },
    { key = "ignoredCombat", kind = "idset" },
}

local TRANSFER_PREFIX = "CLEANSIVE1"

-- Declarees ici et non pres de leur usage : une locale definie plus bas est
-- invisible au-dessus, et decodeValue lisait une globale nil.
-- P2 de l'audit du 30/08 : la borne d'import etait plus PETITE que le plus
-- gros export possible. Deux ensembles de 500 identifiants a sept chiffres
-- font deja 8 038 caracteres avant meme le reste du profil : Cleansive
-- produisait un texte qu'il refusait ensuite de relire. Le contrat qui compte
-- est celui-ci, et un test le tient a la taille maximale :
--     AnalyzeProfileImport(ExportProfile()) doit toujours reussir.
-- 2 ensembles x 500 identifiants x 8 caracteres = 8 000, plus les cles, plus
-- tous les autres reglages : 20 000 laisse une marge franche sans devenir une
-- borne qui n'en est plus une.
local MAX_IMPORT_LENGTH = 20000
local MAX_IDS_PER_SET = 500

-- Les bornes, les valeurs permises et la liste des booleens ne sont plus
-- ecrites une seconde fois : elles se lisent dans la declaration ci-dessus.
-- Ajouter un reglage transferable suffit desormais a le faire reparer au
-- chargement -- l'oubli inverse a laisse passer testUnits, sortMode, testState
-- et cinq booleens de la 1.6.
local NUMERIC_BOUNDS, ALLOWED_VALUES, BOOLEAN_SETTINGS, INTEGER_SETTINGS = {}, {}, {}, {}
for _, field in ipairs(TRANSFER_FIELDS) do
    if field.kind == "number" then
        NUMERIC_BOUNDS[field.key] = { field.min, field.max }
        if field.step == 1 then INTEGER_SETTINGS[field.key] = true end
    elseif field.kind == "enum" then
        local allowed = {}
        for _, value in ipairs(field.values) do allowed[value] = true end
        ALLOWED_VALUES[field.key] = allowed
    elseif field.kind == "boolean" then
        BOOLEAN_SETTINGS[#BOOLEAN_SETTINGS + 1] = field.key
    end
end

-- The nine anchor points SetPoint accepts. Anything else raises, and a saved
-- position goes straight there at load: a hand-edited or truncated database
-- could stop the addon from starting at all.
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
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

-- Exposes pour que la suite puisse verifier qu'aucun reglage transferable
-- n'echappe a la reparation. Une liste tenue a la main se verifie mal ; une
-- liste derivee se verifie en la parcourant.
NS.TRANSFER_FIELDS = TRANSFER_FIELDS

function NS:IsRepairableSetting(key)
    if NUMERIC_BOUNDS[key] or ALLOWED_VALUES[key] then return true end
    for _, name in ipairs(BOOLEAN_SETTINGS) do
        if name == key then return true end
    end
    return false
end

-- P2 de l'audit du 30/08 : la reparation couvrait les nombres, les booleens,
-- les enumerations, les positions et les types -- mais jamais le CONTENU des
-- deux listes. Une base contenant « priority = { 42 } », ou une entree sans
-- kind, faisait lever EntryMatches sur entry.kind des le premier roster.
-- Une entree qui ne peut plus rien identifier n'est pas reparable : on la
-- retire, ce qui est le seul choix qui laisse l'addon demarrer.
local VALID_ENTRY_KINDS = { PLAYER = true, CLASS = true, GROUP = true }

local function normalizeEntryList(list)
    if type(list) ~= "table" then return {} end
    local clean = {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" and VALID_ENTRY_KINDS[entry.kind] then
            local value = entry.value
            if type(value) == "number" then value = tostring(value) end
            if type(value) == "string" and value ~= "" then
                clean[#clean + 1] = {
                    kind = entry.kind,
                    value = value,
                    label = type(entry.label) == "string" and entry.label or value,
                }
            end
        end
    end
    return clean
end

local function normalizeProfile(profile, fallback)
    if type(profile) ~= "table" or type(fallback) ~= "table" then return end
    profile.priority = normalizeEntryList(profile.priority)
    profile.skip = normalizeEntryList(profile.skip)
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
    local environment = self:CurrentEnvironment()
    local override = not self:EnvironmentLocked() and self:EnvironmentOverride(environment)
    if override then
        return override .. "  -  "
            .. (self.L["ENVIRONMENT_" .. string.upper(environment)] or environment)
    end
    local named = self:ActiveNamedProfile()
    if named then return named .. "  -  " .. self.L.PROFILE_SHARED end
    local specName = self.activeSpecName
    if not specName then specName = select(2, self:GetSpecializationProfileKey()) end
    return tostring(self.activeCharacterKey or self:GetCharacterProfileKey())
        .. "  -  " .. tostring(specName or "Default")
end

--------------------------------------------------------------------------
-- Profils nommes
--
-- Le modele d'origine ne connait qu'une adresse : personnage + specialisation.
-- Un profil nomme est une SECONDE adresse, account-wide, vers laquelle une
-- specialisation peut pointer. Deux regles tiennent tout le reste :
--
--   1. Le profil propre d'une specialisation n'est JAMAIS supprime quand elle
--      pointe ailleurs. Revenir dessus doit toujours etre possible, y compris
--      apres la suppression du profil nomme -- sinon supprimer un profil
--      partage laisserait des personnages sans rien.
--   2. Rien ne bascule tout seul. Le point 304 de l'inventaire est explicite :
--      pas de profils automatiques incomprehensibles. Une specialisation ne
--      pointe vers un profil nomme que si on le lui a demande.
--------------------------------------------------------------------------
local MAX_PROFILE_NAME = 32

function NS:NamedProfileStore()
    local raw = self.dbRoot
    if not raw then return nil end
    if type(raw.named) ~= "table" then raw.named = {} end
    if type(raw.assignments) ~= "table" then raw.assignments = {} end
    if not raw.namedStoreChecked then
        raw.namedStoreChecked = true
        for key, value in pairs(raw.named) do
            if type(key) ~= "string" or key == "" or type(value) ~= "table" then
                raw.named[key] = nil
            end
        end
        for character, specs in pairs(raw.assignments) do
            if type(character) ~= "string" or type(specs) ~= "table" then
                raw.assignments[character] = nil
            else
                for spec, name in pairs(specs) do
                    if type(spec) ~= "string" or type(name) ~= "string" then
                        specs[spec] = nil
                    end
                end
            end
        end
    end

    -- Les 1.6.9 et 1.6.10 acceptaient la barre verticale dans un nom. La 1.6.11
    -- la retire des saisies, mais laissait les noms DEJA enregistres tels
    -- quels : un bouton transmettait « Raid|Soins », la normalisation en
    -- faisait « RaidSoins », et le profil devenait introuvable.
    --
    -- La 1.6.12 a ajoute cette migration DANS le bloc ci-dessus -- dont le
    -- marqueur etait deja pose par la 1.6.11, qui ne migrait rien. Elle ne s'est
    -- donc jamais executee chez les seules personnes qui en avaient besoin :
    -- celles passees par la 1.6.11. Un marqueur qui decrit un autre nettoyage
    -- ne peut pas servir de marqueur de migration. Celui-ci lui est propre, et
    -- porte le numero de version qui l'introduit.
    if not raw.namedBarMigration1615 then
        raw.namedBarMigration1615 = true
        local renames = {}
        for key, value in pairs(raw.named) do
            if type(key) == "string" and key:find("|", 1, true) and type(value) == "table" then
                local wanted = self:NormalizeProfileName(key) or "Profil"
                local candidate, suffix = wanted, 2
                while raw.named[candidate] or renames[candidate] do
                    -- La place du suffixe est RESERVEE avant de raccourcir la
                    -- base : « nom de 32 octets » + « (2) » faisait 36, la cle
                    -- etait bien enregistree, et toute recherche ulterieure la
                    -- cherchait a 32 octets. Le profil devenait inatteignable.
                    local tail = " (" .. suffix .. ")"
                    local base = self:NormalizeProfileName(wanted, MAX_PROFILE_NAME - #tail) or "Profil"
                    candidate = base .. tail
                    suffix = suffix + 1
                end
                renames[candidate] = key
            end
        end
        for candidate, key in pairs(renames) do
            raw.named[candidate], raw.named[key] = raw.named[key], nil
            for _, specs in pairs(raw.assignments) do
                if type(specs) == "table" then
                    for spec, name in pairs(specs) do
                        if name == key then specs[spec] = candidate end
                    end
                end
            end
        end
    end
    return raw.named, raw.assignments
end

-- Un nom venu d'une saisie libre : longueur bornee, espaces rognes, et aucun
-- caractere de controle -- un retour a la ligne dans un nom casserait la liste
-- et l'export sans que rien ne le dise.
function NS:NormalizeProfileName(raw, limit)
    if type(raw) ~= "string" then return nil end
    limit = tonumber(limit) or MAX_PROFILE_NAME
    -- La barre verticale est refusee pour deux raisons : elle separe les deux
    -- noms de la commande de renommage, et dans un texte affiche par WoW elle
    -- ouvre une sequence de mise en forme -- un nom bien choisi pourrait donc
    -- colorer, voire masquer, le reste de la ligne.
    local name = raw:gsub("%c", ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    -- La borne compte des OCTETS. Couper a l'octet 32 au milieu d'une sequence
    -- UTF-8 -- « Chasseur de démons » et ses accents -- produisait un nom
    -- invalide, affiche en caractere de remplacement et impossible a retaper.
    -- La coupe recule donc jusqu'au debut du caractere.
    if #name > limit then
        local cut = limit
        while cut > 0 do
            local byte = name:byte(cut + 1)
            -- 0x80..0xBF est une continuation : le caractere commence avant.
            if not byte or byte < 128 or byte >= 192 then break end
            cut = cut - 1
        end
        name = name:sub(1, cut):gsub("%s+$", "")
        if name == "" then return nil end
    end
    return name
end

function NS:NamedProfiles()
    local named = self:NamedProfileStore()
    local list = {}
    if not named then return list end
    for name in pairs(named) do list[#list + 1] = name end
    table.sort(list)
    return list
end

function NS:ActiveNamedProfile()
    local named, assignments = self:NamedProfileStore()
    if not named then return nil end
    local character = assignments[self.activeCharacterKey or ""]
    local name = type(character) == "table" and character[self.activeSpecKey or ""]
    if type(name) == "string" and named[name] then return name end
    return nil
end

-- P1 de l'audit du 30/08. Ces trois operations changeaient la base PUIS
-- demandaient un rechargement que le combat refuse. Les cles actives restaient
-- alors a nil pendant que self.db pointait encore sur l'ancienne table : le
-- message annoncait un profil, les reglages en modifiaient un autre, et une
-- seconde operation ecrivait dans assignments[""] au lieu du personnage.
--
-- Refuser est la seule reponse honnete. Un changement de profil a moitie
-- applique est pire que pas de changement du tout, et c'est deja la regle
-- retenue pour l'apercu en 1.6.1.
-- Silencieuse : elle repond, elle n'annonce pas. Elle imprimait le refus ET le
-- rendait a l'appelant, qui l'imprimait a son tour -- le joueur lisait deux
-- fois la meme phrase.
function NS:ProfileChangeBlockedByCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

function NS:CreateNamedProfile(rawName)
    local name = self:NormalizeProfileName(rawName)
    if not name then return false, self.L.PROFILE_NAME_INVALID end
    local named = self:NamedProfileStore()
    if not named then return false, self.L.PROFILE_NAME_INVALID end
    if named[name] then return false, string.format(self.L.PROFILE_NAME_TAKEN, name) end
    -- Cree a partir des reglages COURANTS : creer un profil vide obligerait a
    -- tout re-regler, et personne ne cree un profil pour repartir de zero.
    named[name] = deepCopy(self.db)
    return true, string.format(self.L.PROFILE_CREATED, name)
end

function NS:DeleteNamedProfile(rawName)
    if self:ProfileChangeBlockedByCombat() then return false, self.L.PROFILE_COMBAT_REFUSED end
    local name = self:NormalizeProfileName(rawName)
    local named, assignments = self:NamedProfileStore()
    if not named or not name or not named[name] then
        return false, self.L.PROFILE_UNKNOWN
    end
    -- L'identite, pas le chemin : un profil peut etre actif par affectation OU
    -- par surcharge de lieu, et la seconde n'etait pas regardee. Supprimer le
    -- profil du donjon depuis le donjon laissait donc self.db pointer sur une
    -- table qui n'existe plus dans la base.
    local wasActive = self.db ~= nil and self.db == named[name]
    named[name] = nil
    -- Toute specialisation qui pointait dessus revient a SON profil, qui n'a
    -- jamais ete supprime. Laisser un pointeur mort ferait repartir un autre
    -- personnage sur les valeurs d'origine a sa prochaine connexion, sans que
    -- rien ne le dise.
    for _, character in pairs(assignments) do
        if type(character) == "table" then
            for spec, assigned in pairs(character) do
                if assigned == name then character[spec] = nil end
            end
        end
    end
    -- Et les surcharges de lieu, pour la meme raison que les affectations : un
    -- pointeur mort laisse en place ressusciterait au premier profil qui
    -- reprendrait ce nom.
    local raw = self.dbRoot
    if raw and type(raw.environments) == "table" then
        for _, character in pairs(raw.environments) do
            if type(character) == "table" then
                for _, specs in pairs(character) do
                    if type(specs) == "table" then
                        for place, assigned in pairs(specs) do
                            if assigned == name then specs[place] = nil end
                        end
                    end
                end
            end
        end
    end
    if wasActive then self:ReloadActiveProfile() end
    return true, string.format(self.L.PROFILE_DELETED, name)
end

function NS:RenameNamedProfile(rawOld, rawNew)
    local old, new = self:NormalizeProfileName(rawOld), self:NormalizeProfileName(rawNew)
    local named, assignments = self:NamedProfileStore()
    if not named or not old or not named[old] then return false, self.L.PROFILE_UNKNOWN end
    if not new then return false, self.L.PROFILE_NAME_INVALID end
    if new ~= old and named[new] then return false, string.format(self.L.PROFILE_NAME_TAKEN, new) end
    named[new], named[old] = named[old], nil
    for _, character in pairs(assignments) do
        if type(character) == "table" then
            for spec, assigned in pairs(character) do
                if assigned == old then character[spec] = new end
            end
        end
    end
    return true, string.format(self.L.PROFILE_RENAMED, old, new)
end

function NS:UseNamedProfile(rawName)
    if self:ProfileChangeBlockedByCombat() then return false, self.L.PROFILE_COMBAT_REFUSED end
    local name = self:NormalizeProfileName(rawName)
    local named, assignments = self:NamedProfileStore()
    if not named or not name or not named[name] then return false, self.L.PROFILE_UNKNOWN end
    local characterKey = self.activeCharacterKey or self:GetCharacterProfileKey()
    local specKey = self.activeSpecKey or select(1, self:GetSpecializationProfileKey())
    if not specKey then return false, self.L.PROFILE_UNKNOWN end
    assignments[characterKey] = type(assignments[characterKey]) == "table" and assignments[characterKey] or {}
    assignments[characterKey][specKey] = name
    self:ReloadActiveProfile()
    return true, string.format(self.L.PROFILE_IN_USE, name)
end

function NS:UseOwnProfile()
    if self:ProfileChangeBlockedByCombat() then return false, self.L.PROFILE_COMBAT_REFUSED end
    local _, assignments = self:NamedProfileStore()
    if not assignments then return false, self.L.PROFILE_UNKNOWN end
    local character = assignments[self.activeCharacterKey or ""]
    if type(character) == "table" then character[self.activeSpecKey or ""] = nil end
    self:ReloadActiveProfile()
    return true, self.L.PROFILE_OWN_IN_USE
end

-- Recharger n'est pas changer de specialisation : LoadCurrentProfile sort tot
-- quand les cles n'ont pas bouge, ce qui est exactement le cas ici.
function NS:ReloadActiveProfile()
    -- Effacer les cles avant un changement que le combat va refuser laissait
    -- l'addon sans identite : ActiveNamedProfile lisait assignments[""].
    -- Les appelants refusent deja ; ceci empeche qu'un futur appelant oublie.
    if InCombatLockdown and InCombatLockdown() then return false end
    self.activeCharacterKey, self.activeSpecKey = nil, nil
    self:QueueProfileSwitch()
    return true
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
        -- Le profil propre est garanti ci-dessus et le reste ; ce n'est
        -- qu'ensuite que l'affectation nommee est suivie.
        profile = self:ResolveActiveProfileTable(characterKey, specKey, profile)
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

-- P1 de l'audit du 30/08 : cette resolution n'existait QUE dans
-- LoadCurrentProfile. InitializeProfiles, lui, prenait directement le profil
-- propre -- et LoadCurrentProfile sort tot quand les cles n'ont pas bouge. Une
-- connexion ou la specialisation est deja connue au chargement laissait donc
-- ActiveNamedProfile annoncer le profil partage pendant que self.db pointait
-- ailleurs : les reglages partaient au mauvais endroit, sans rien dire.
-- Il n'y a plus qu'un seul endroit ou la question se pose.
--------------------------------------------------------------------------
-- Surcharges par environnement
--
-- Le point 304 de l'inventaire interdit « une multitude de profils
-- automatiques incomprehensibles ». La surcharge est donc la plus petite qui
-- puisse exister : elle ne porte AUCUN reglage, elle designe seulement un
-- profil nomme deja existant pour un lieu donne. Rien de neuf a comprendre,
-- rien qui bascule sans qu'on l'ait demande lieu par lieu.
--
-- Et un verrou global, parce qu'un joueur qui regle sa grille veut parfois
-- qu'elle ne bouge plus, quoi qu'il traverse.
--------------------------------------------------------------------------
local ENVIRONMENTS = { "world", "dungeon", "raid", "pvp" }
NS.ENVIRONMENTS = ENVIRONMENTS

function NS:CurrentEnvironment()
    if not IsInInstance then return "world" end
    local inside, kind = IsInInstance()
    if not inside then return "world" end
    if kind == "raid" then return "raid" end
    if kind == "pvp" or kind == "arena" then return "pvp" end
    if kind == "party" or kind == "scenario" then return "dungeon" end
    return "world"
end

function NS:EnvironmentLocked()
    local global = self.dbRoot and self.dbRoot.global
    return global and global.lockEnvironment and true or false
end

function NS:SetEnvironmentLocked(locked)
    local global = self.dbRoot and self.dbRoot.global
    if not global then return false end
    global.lockEnvironment = locked and true or false
    self:ReloadActiveProfile()
    return true
end

local function environmentStore(self, characterKey, specKey)
    local raw = self.dbRoot
    if not raw then return nil end
    if type(raw.environments) ~= "table" then raw.environments = {} end
    local character = raw.environments[characterKey]
    if type(character) ~= "table" then character = {} raw.environments[characterKey] = character end
    local spec = character[specKey]
    if type(spec) ~= "table" then spec = {} character[specKey] = spec end
    return spec
end

function NS:EnvironmentOverride(environment)
    local raw = self.dbRoot
    local character = raw and type(raw.environments) == "table"
        and raw.environments[self.activeCharacterKey or ""]
    local spec = type(character) == "table" and character[self.activeSpecKey or ""]
    local name = type(spec) == "table" and spec[environment]
    local named = self:NamedProfileStore()
    if type(name) == "string" and named and named[name] then return name end
    return nil
end

function NS:SetEnvironmentOverride(environment, rawName)
    if self:ProfileChangeBlockedByCombat() then return false, self.L.PROFILE_COMBAT_REFUSED end
    local valid = false
    for _, candidate in ipairs(ENVIRONMENTS) do
        if candidate == environment then valid = true end
    end
    if not valid then return false, self.L.PROFILE_ENVIRONMENT_UNKNOWN end
    local specKey = self.activeSpecKey
    if not specKey then return false, self.L.PROFILE_UNKNOWN end
    local store = environmentStore(self, self.activeCharacterKey, specKey)
    if not store then return false, self.L.PROFILE_UNKNOWN end

    if rawName == nil or rawName == "" then
        store[environment] = nil
        self:ReloadActiveProfile()
        return true, string.format(self.L.PROFILE_ENVIRONMENT_CLEARED,
            self.L["ENVIRONMENT_" .. string.upper(environment)] or environment)
    end
    local name = self:NormalizeProfileName(rawName)
    local named = self:NamedProfileStore()
    if not name or not named or not named[name] then return false, self.L.PROFILE_UNKNOWN end
    store[environment] = name
    self:ReloadActiveProfile()
    return true, string.format(self.L.PROFILE_ENVIRONMENT_SET,
        self.L["ENVIRONMENT_" .. string.upper(environment)] or environment, name)
end

function NS:ResolveActiveProfileTable(characterKey, specKey, ownProfile)
    local named, assignments = self:NamedProfileStore()
    if not named then return ownProfile end

    -- La surcharge de lieu passe AVANT l'affectation : c'est sa raison d'etre.
    -- Elle ne s'applique jamais quand l'environnement est verrouille, et jamais
    -- vers un profil qui n'existe plus.
    if not self:EnvironmentLocked() then
        local raw = self.dbRoot
        local envCharacter = type(raw.environments) == "table" and raw.environments[characterKey]
        local envSpec = type(envCharacter) == "table" and envCharacter[specKey]
        local wanted = type(envSpec) == "table" and envSpec[self:CurrentEnvironment()]
        if type(wanted) == "string" and type(named[wanted]) == "table" then
            return named[wanted]
        end
    end

    local character = assignments[characterKey]
    local assigned = type(character) == "table" and character[specKey]
    if type(assigned) ~= "string" then return ownProfile end
    if type(named[assigned]) == "table" then return named[assigned] end
    -- Pointeur mort : le profil nomme a disparu d'une facon ou d'une autre. On
    -- revient au profil propre, et on OUBLIE le pointeur -- laisse en place, il
    -- ressusciterait le jour ou un profil reprendrait le meme nom.
    character[specKey] = nil
    return ownProfile
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
    -- L'environnement fait partie de l'identite : sans lui, entrer en donjon ne
    -- rechargeait rien, puisque le personnage et la specialisation n'avaient
    -- pas bouge -- et la surcharge n'aurait jamais servi a rien.
    local environment = self:CurrentEnvironment()
    if characterKey == self.activeCharacterKey and specKey == self.activeSpecKey
        and environment == self.activeEnvironment then return false end

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
    profile = self:ResolveActiveProfileTable(characterKey, specKey, profile)
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
    self.activeEnvironment = environment
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
        local set, count = {}, 0
        if text ~= "" then
            for part in string.gmatch(text, "[^,]+") do
                local id = tonumber(part)
                if not id or id <= 0 or id ~= math.floor(id) then return nil end
                count = count + 1
                if count > MAX_IDS_PER_SET then return nil end
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
    if #text > MAX_IMPORT_LENGTH then
        return nil, string.format(self.L.IMPORT_TOO_LONG, MAX_IMPORT_LENGTH)
    end
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
        "showSolo", "showParty", "showRaid", "priorityKey", "alertSound",
        "sound", "failureSound", "soundChannel", "soundMaxRegistrations",
        "blacklistTime", "autoHide" },
    appearance = { "frameSize", "spacing", "columns", "inactiveAlpha", "grow",
        "layoutMode", "separateRaidSize", "raidFrameSize", "raidSpacing", "showNames", "classColorCells", "showCooldown", "showDuration", "showStacks", "showClickHints",
        "afflictedOnly", "testUnits", "testState", "positions" },
    dispels = { "typeOrder", "enabledTypes", "groupManualTypes", "controlWarning", "controlTypes",
        "priority", "skip", "sortMode" },
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
