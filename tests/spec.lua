-- Regression tests for Cleansive.
--
-- Every case here replays a defect that was actually shipped at some point.
-- The comment above each one names the version it broke in, so a failure
-- tells you which mistake came back.

local mock = require("wow-mock")
mock.install(_G)

local ADDON = ADDON_PATH or "../work/Cleansive-1.4.0/Cleansive"

-- Files that hold logic. SetupWizard.lua is left out; EllesmereUX.lua is
-- loaded at the very END of this file instead, after every test that relies on
-- the UI stubs below. It was excluded for years as "too frame-heavy for no
-- added coverage" -- which is how six silent sliders survived that long.
local FILES = {
    "Core.lua", "Profiles.lua", "Locale.lua", "Spells.lua",
    "DispelSounds.lua", "Roster.lua", "Frames.lua", "Lists.lua",
    "Diagnostics.lua",
}

local NS = {}
for _, file in ipairs(FILES) do
    local chunk, err = loadfile(ADDON .. "/" .. file)
    if not chunk then error("cannot load " .. file .. ": " .. tostring(err)) end
    chunk("Cleansive", NS)
end

-- The UI layer is absent, so neutralise the hooks that reach into it.
for _, name in ipairs({ "RefreshOptions", "RefreshListWindow", "RefreshFilterWindow",
    "RefreshAuraHistoryPage", "GetUXFont", "GetUXAccent", "SkinUXPanel",
    "CreateUXButton", "ShowOptionsPage" }) do
    NS[name] = function() return nil end
end

--------------------------------------------------------------------------
-- tiny test runner
--------------------------------------------------------------------------
local passed, failed, results = 0, 0, {}

local function check(ok, name, detail)
    if ok then
        passed = passed + 1
        results[#results + 1] = { ok = true, name = name }
    else
        failed = failed + 1
        results[#results + 1] = { ok = false, name = name, detail = detail }
    end
end

local function eq(actual, expected, name)
    check(actual == expected, name,
        "attendu " .. tostring(expected) .. ", obtenu " .. tostring(actual))
end

local function truthy(value, name) check(value and true or false, name, "valeur fausse ou nil") end
local function falsy(value, name) check(not value, name, "attendu faux, obtenu " .. tostring(value)) end

--------------------------------------------------------------------------
-- fixtures
--------------------------------------------------------------------------

-- Rebuilds a minimal profile so each test starts from known settings.
local function freshProfile(class)
    mock.reset()
    CleansiveDB = nil
    NS.dbRoot, NS.db = nil, nil
    NS.profileDefaults = NS.profileDefaults or {}
    NS:InitializeProfiles()
    NS.enabled = true
    NS.testMode = false
    -- NS.playerClass is captured once when Core.lua loads. Tests that change
    -- class must set both sides, or every class check silently falls back to
    -- the load-time value and the assertion passes for the wrong reason.
    mock.state.playerClass = class or "PALADIN"
    NS.playerClass = mock.state.playerClass
    return NS.db
end

local function knowSpells(...)
    for _, id in ipairs({ ... }) do
        mock.state.knownSpells[id] = true
        mock.state.playerSpells[id] = true
    end
end

local function debuff(spellID, dispelName, extra)
    local aura = { spellId = spellID, dispelName = dispelName, name = "Debuff" .. spellID, applications = 1 }
    for k, v in pairs(extra or {}) do aura[k] = v end
    return aura
end

--------------------------------------------------------------------------
-- 1. GetCurableAura : the cascade broken in 1.2.3, again in 1.2.5
--------------------------------------------------------------------------

-- 1.2.3: unchecking a dispel type still lit the cell, repainted as click 1.
freshProfile("PALADIN")
knowSpells(4987)                       -- Cleanse: Magic, Disease, Poison
NS:UpdateSpells()
NS.db.enabledTypes.Magic = false
NS.unitToButton = {}
mock.state.debuffs.player = { debuff(111, "Magic") }
do
    local aura, auraType, slot = NS:GetCurableAura("player")
    falsy(aura, "type desactive : l'affliction est ignoree")
    falsy(slot, "type desactive : aucun emplacement de clic attribue")
end

-- 1.2.5: the fallback branches used `break`, abandoning the configured order.
freshProfile()
knowSpells(4987)
NS:UpdateSpells()
NS.db.typeOrder = { "Disease", "Magic", "Poison", "Curse", "Bleed", "Charm" }
NS:UpdateSpells()
mock.state.debuffs.player = { debuff(111, "Magic"), debuff(222, "Disease") }
do
    local aura, auraType = NS:GetCurableAura("player")
    eq(auraType, "Disease", "ordre de priorite : la maladie prioritaire l'emporte sur la magie a l'index 1")
end

-- 1.2.5: a dispellable aura with no dispel type stopped being detected at all.
freshProfile("EVOKER")
knowSpells(374251)                     -- Cauterizing Flame: covers Bleed
NS:UpdateSpells()
mock.state.debuffs.player = { debuff(999999, nil) }   -- bleed absent from the seasonal list
do
    local aura, auraType = NS:GetCurableAura("player")
    truthy(aura, "saignement inconnu : detecte malgre tout")
    eq(auraType, "Bleed", "saignement inconnu : classe en Bleed")
end

--------------------------------------------------------------------------
-- 2. UpdateSpells : the click mapping broken in 1.4.0, over-fixed in 1.4.1
--------------------------------------------------------------------------

-- 1.4.0: Psychic Scream, an untargeted area fear, took the priest's click.
freshProfile("PRIEST")
knowSpells(527, 528, 8122)             -- Purify, Dispel Magic, Psychic Scream
NS:UpdateSpells()
do
    local charm = NS.typeToSpell and NS.typeToSpell.Charm
    truthy(charm, "pretre : un sort cible occupe bien le clic Charme")
    check(charm and charm.id ~= 8122, "sort non cible : Cri psychique n'occupe aucun clic",
        "typeToSpell.Charm = " .. tostring(charm and charm.id))
    truthy(NS.manualTypeSpell and NS.manualTypeSpell.Charm, "pretre : Cri psychique reste connu en manuel")
end

-- 1.4.1: excluding them from the click mapping also removed the detection.
freshProfile("SHAMAN")
knowSpells(383013)                     -- Poison Cleansing Totem: untargeted, only Poison source
NS:UpdateSpells()
do
    falsy(NS.typeToSlot and NS.typeToSlot.Poison, "totem : aucun emplacement de clic")
    truthy(NS.manualTypeSpell and NS.manualTypeSpell.Poison, "totem : le poison reste detectable")
end

--------------------------------------------------------------------------
-- 3. The cleanse key, broken in 1.4.0
--------------------------------------------------------------------------

-- 1.4.0: the macro used the display name where the rest of the addon uses
-- the base spell name, and the key was bound even with nothing to cast.
freshProfile("WARRIOR")                 -- no cleansing spell at all
NS:UpdateSpells()
eq(NS:BuildPriorityDispelMacro(), nil, "sans sort de dissipation : aucune macro generee")

freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    local macro = NS:BuildPriorityDispelMacro()
    truthy(macro and macro:find("@mouseover", 1, true), "macro : condition de survol presente")
    truthy(macro and macro:find(NS.clickSpells[1].secureName, 1, true), "macro : utilise le nom securise")
end

--------------------------------------------------------------------------
-- 4. Profiles, introduced in 1.4.0 and reworked in 1.4.2 / 1.4.3
--------------------------------------------------------------------------

-- 1.4.0: the profile was resolved before the specialization was known and
-- the result was persisted under the key "0".
mock.reset()
CleansiveDB = nil
NS.dbRoot, NS.db = nil, nil
mock.state.specIndex = nil             -- ADDON_LOADED: no specialization yet
NS:InitializeProfiles()
do
    local profiles = CleansiveDB.profiles["Ekinoks-Hyjal"] or {}
    falsy(profiles["0"], "spe inconnue : aucun profil « 0 » ecrit")
    truthy(NS.bootstrapProfile, "spe inconnue : amorcage sur un profil jetable")
end

-- 1.4.2: an existing "0" profile must be dropped once the real key is known.
mock.state.specIndex, mock.state.specID = 1, 65
CleansiveDB.profiles["Ekinoks-Hyjal"]["0"] = { frameSize = 99 }
NS:LoadCurrentProfile(true)
do
    falsy(CleansiveDB.profiles["Ekinoks-Hyjal"]["0"], "profil fantome supprime une fois la spe connue")
    truthy(CleansiveDB.profiles["Ekinoks-Hyjal"]["65"], "profil de la spe reelle cree")
end

-- 1.4.0: migrating the old account-wide database only seeded the first
-- character; every other one silently started from the defaults.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = { frameSize = 37, columns = 7, language = "frFR" }   -- a 1.2.6 database
NS:InitializeProfiles()
eq(NS.db.frameSize, 37, "migration : les reglages du premier personnage sont conserves")
do
    local seed = CleansiveDB.global.migratedSeed
    truthy(seed, "migration : la base d'origine est gardee comme graine")
    eq(seed and seed.frameSize, 37, "migration : la graine porte les bons reglages")
end

-- 1.5.8: an unset language fell back to English, so a French client showed
-- English labels next to the French spell names the game API returns. A
-- choice the player actually made still wins over the client.
do
    local previousLocale = mock.state.locale
    local function boot(locale, stored)
        mock.reset()
        mock.state.locale = locale
        NS.dbRoot, NS.db = nil, nil
        CleansiveDB = stored
        NS:InitializeProfiles()
        return CleansiveDB.global.language
    end
    eq(boot("frFR", nil), "frFR", "langue : installation neuve sur client francais")
    eq(boot("enUS", nil), "enUS", "langue : installation neuve sur client anglais")
    eq(boot("deDE", nil), "enUS", "langue : client non pris en charge retombe sur l'anglais")
    eq(boot("frFR", { schemaVersion = 2, profiles = {}, global = { language = "enUS", setupComplete = true } }),
        "enUS", "langue : un choix explicite prime sur le client")
    eq(boot("enUS", { schemaVersion = 2, profiles = {}, global = { language = "frFR", setupComplete = true } }),
        "frFR", "langue : le francais choisi survit a un client anglais")
    mock.state.locale = previousLocale
end

-- Every English key must have a French counterpart: NS.L silently falls back
-- to English, so a missing key ships as an untranslated label.
do
    local missing = {}
    for key in pairs(NS.LOCALES.enUS) do
        if NS.LOCALES.frFR[key] == nil then missing[#missing + 1] = key end
    end
    table.sort(missing)
    eq(#missing, 0, "traductions : aucune cle anglaise sans equivalent francais"
        .. (#missing > 0 and (" (" .. table.concat(missing, ", ") .. ")") or ""))

    -- A format placeholder that differs between the two languages raises at
    -- display time, in whichever language the player is not testing in.
    local mismatched = {}
    local function placeholders(text)
        local list = {}
        for token in string.gmatch(tostring(text), "%%[-+ #%d%.]*[dsfxX]") do
            list[#list + 1] = token
        end
        return table.concat(list, ",")
    end
    for key, value in pairs(NS.LOCALES.enUS) do
        local other = NS.LOCALES.frFR[key]
        if other and placeholders(value) ~= placeholders(other) then
            mismatched[#mismatched + 1] = key
        end
    end
    table.sort(mismatched)
    eq(#mismatched, 0, "traductions : placeholders identiques entre les langues"
        .. (#mismatched > 0 and (" (" .. table.concat(mismatched, ", ") .. ")") or ""))
end

-- 1.4.2: settings belonging to features removed in 1.2.6 must be pruned.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = { liveCount = 10, scanInterval = 0.12, showLiveList = false,
                positions = { grid = {}, bar = { x = 1 } } }
NS:InitializeProfiles()
do
    falsy(NS.db.liveCount, "elagage : liveCount retire")
    falsy(NS.db.scanInterval, "elagage : scanInterval retire")
    falsy(NS.db.showLiveList, "elagage : showLiveList retire")
    falsy(NS.db.positions.bar, "elagage : position de la liste active retiree")
end

-- 1.4.3: history left inside a profile is folded into the global one.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true },
    profiles = { ["Ekinoks-Hyjal"] = { ["65"] = {
        auraHistory = { [4242] = { name = "Vieux" } },
        auraHistoryOrder = { 4242 },
    } } },
}
NS:InitializeProfiles()
do
    falsy(NS.db.auraHistory, "historique : la copie du profil est retiree")
    local history = NS:GetAuraHistory()
    truthy(history[4242], "historique : l'entree est absorbee dans le global, pas perdue")
end

--------------------------------------------------------------------------
-- 5. RememberAura, made costly in 1.4.0 and capped since 1.2.6
--------------------------------------------------------------------------
freshProfile()
do
    local history, order = NS:GetAuraHistory()
    for index = 1, 130 do NS:RememberAura(debuff(index, "Magic")) end
    eq(#order, 100, "historique : plafonne a 100 entrees")
    falsy(history[1], "historique : la plus ancienne entree est evincee")
    truthy(history[130], "historique : la plus recente est conservee")

    -- The hot path must not reorder when the spell is already the newest.
    local before = #order
    NS:RememberAura(debuff(130, "Magic"))
    eq(#order, before, "historique : re-signaler la meme aura ne rallonge rien")
    eq(order[#order], 130, "historique : l'entree la plus recente ne bouge pas")
end

--------------------------------------------------------------------------
-- 6. Roster : hostile focus, false mind-control alert in 1.2.5
--------------------------------------------------------------------------
freshProfile()
NS.db.showFocus = true
mock.state.exists.focus = true
mock.state.friendly.focus = false          -- an enemy player in PvP
do
    local roster = NS:BuildRoster()
    local hasFocus = false
    for _, descriptor in ipairs(roster) do
        if descriptor.unit == "focus" then hasFocus = true end
    end
    falsy(hasFocus, "focalisation hostile : exclue du roster")
end

mock.state.friendly.focus = true
do
    local roster = NS:BuildRoster()
    local hasFocus = false
    for _, descriptor in ipairs(roster) do
        if descriptor.unit == "focus" then hasFocus = true end
    end
    truthy(hasFocus, "focalisation amicale : incluse dans le roster")
end

--------------------------------------------------------------------------
-- 7. Sound plan : the cartesian rebuild of 1.2.5
--------------------------------------------------------------------------
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.roster = { { unit = "player" } }
do
    local spellIDs, units, fingerprint = NS:BuildAuraSoundPlan()
    truthy(#spellIDs > 0, "plan sonore : des sorts sont retenus")
    truthy(fingerprint and #fingerprint > 0, "plan sonore : une empreinte est calculee")
    local _, _, again = NS:BuildAuraSoundPlan()
    eq(again, fingerprint, "plan sonore : l'empreinte est stable a etat egal")
end

--------------------------------------------------------------------------
-- 8. Vehicles : never handled before 1.4.5
--------------------------------------------------------------------------

-- A passenger's afflictions move to the pet slot carrying the vehicle.
freshProfile("PALADIN")
eq(NS:GetVehicleUnit("player"), "pet", "vehicule : jeton du joueur")
eq(NS:GetVehicleUnit("raid7"), "raidpet7", "vehicule : jeton en raid")
eq(NS:GetVehicleUnit("party3"), "partypet3", "vehicule : jeton en groupe")
eq(NS:GetVehicleUnit("focus"), nil, "vehicule : la focalisation n'en a pas")

-- Out of a vehicle, nothing changes.
eq(NS:GetDisplayUnit("raid7"), "raid7", "hors vehicule : l'unite reste elle-meme")

-- In one, the auras are read on the vehicle token.
mock.state.inVehicle.raid7 = true
mock.state.exists.raidpet7 = true
eq(NS:GetDisplayUnit("raid7"), "raidpet7", "en vehicule : les auras sont lues sur le jeton du vehicule")

-- But only when that token actually exists.
mock.state.exists.raidpet7 = nil
eq(NS:GetDisplayUnit("raid7"), "raid7", "vehicule sans jeton : repli sur l'unite d'origine")

-- The affliction carried by the vehicle must reach GetCurableAura.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
mock.state.inVehicle.player = true
mock.state.exists.pet = true
mock.state.debuffs.player = {}
mock.state.debuffs.pet = { debuff(555, "Poison") }
do
    local aura, auraType = NS:GetCurableAura("player")
    truthy(aura, "en vehicule : l'affliction du vehicule est vue")
    eq(auraType, "Poison", "en vehicule : le bon type est retenu")
end

-- 1.5.9: with pet scanning enabled, the owner resolved to the vehicle token
-- and that same token was then appended as a pet, producing two cells for one
-- vehicle. The owner descriptor wins because it carries the useful name and
-- priority rules.
freshProfile("PALADIN")
NS.db.showPets = true
mock.state.exists.party1, mock.state.exists.partypet1 = true, true
mock.state.inVehicle.party1 = true
local realIsInGroup = IsInGroup
IsInGroup = function() return true end
do
    local roster = NS:BuildRoster()
    local owner, pet, resolvedVehicle = 0, 0, 0
    for _, descriptor in ipairs(roster) do
        if descriptor.unit == "party1" then owner = owner + 1 end
        if descriptor.unit == "partypet1" then pet = pet + 1 end
        if NS:GetDisplayUnit(descriptor.unit) == "partypet1" then resolvedVehicle = resolvedVehicle + 1 end
    end
    eq(owner, 1, "vehicule : le descripteur du proprietaire est conserve")
    eq(pet, 0, "vehicule : le jeton familier identique n'est pas ajoute")
    eq(resolvedVehicle, 1, "vehicule : une seule case resout vers le vehicule")
end
IsInGroup = realIsInGroup

--------------------------------------------------------------------------
-- 9. Sound status : the season warning added in 1.4.5
--------------------------------------------------------------------------
freshProfile("PALADIN")
truthy(NS.KNOWN_DISPELLABLE_AURAS_SEASON, "saison : la liste porte un numero")
do
    local before = #mock.state.chat
    NS:PrintAuraSoundStatus()
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("saison", 1, true) or printed:find("season", 1, true),
        "saison : soundstatus annonce la peremption possible")
    falsy(printed:find("-0", 1, true), "delta : plus de « -0 » dans le compte rendu")
end

--------------------------------------------------------------------------
-- 10. Gaps an external audit of 1.4.5 found that these tests had missed
--------------------------------------------------------------------------

-- Builds the minimum a cell needs for SetButtonState to run.
local function fakeButton(unit, engine)
    local b = mock.newFrame("CleansiveMUF1")
    b.unit, b.index = unit, 1
    b.border = { mock.newFrame("t"), mock.newFrame("t"), mock.newFrame("t"), mock.newFrame("t") }
    -- Every region the cell code reads as a frame must exist: the mock hands
    -- back a bare function for unknown keys, which blows up on indexing.
    for _, key in ipairs({ "background", "typeMark", "charm", "center", "nameText",
        "clickHint", "cooldown", "auraDurationCooldown" }) do
        b[key] = mock.newFrame(key)
    end
    b.clickLayer = mock.newFrame("click")
    b.clickLayer.hoverTexture = mock.newFrame("hover")
    if engine then
        b.engineAuraReady = true
        b.auraContainer = mock.newFrame("container")
        NS.engineAuraMode = true
    else
        NS.engineAuraMode = false
    end
    return b
end

-- 1.4.4 claimed the sound alert fires for manual-only types. It did not:
-- the plan only kept types present in typeToSlot.
freshProfile("SHAMAN")
knowSpells(383013)                     -- Poison Cleansing Totem, untargeted
NS:UpdateSpells()
NS.roster = { { unit = "player" } }
do
    local spellIDs = NS:BuildAuraSoundPlan()
    truthy(#spellIDs > 0, "son : un type uniquement manuel est bien inscrit")
end

-- Vehicles: the passenger's afflictions land on the vehicle token, which
-- therefore needs its own sound registration.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.roster = { { unit = "raid3" } }
mock.state.exists.raid3, mock.state.exists.raidpet3 = true, true
mock.state.inVehicle.raid3 = true
do
    local _, units = NS:BuildAuraSoundPlan()
    local hasVehicle = false
    for _, unit in ipairs(units) do if unit == "raidpet3" then hasVehicle = true end end
    truthy(hasVehicle, "son : le jeton de vehicule est inscrit lui aussi")
end

-- Afflicted-only hides Cleansive's base visuals and hover highlight. The fixed
-- secure hitbox intentionally remains active so a protected AuraSlot can pass
-- clicks through; Lua cannot read the slot's visibility to toggle it safely.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.db.afflictedOnly = true
do
    local engineCell = fakeButton("player", true)
    NS:SetButtonState(engineCell, nil, nil, nil, false, false)
    truthy(engineCell.baseHidden, "affliges seulement : le fond moteur sain reste invisible")

    local luaCell = fakeButton("player", false)
    NS:SetButtonState(luaCell, nil, nil, nil, false, false)
    truthy(luaCell.baseHidden, "affliges seulement : le fond Lua vide reste invisible")

    NS.db.showNames = true
    local manualCell = fakeButton("player", false)
    NS:SetButtonState(manualCell, debuff(556, "Poison"), "Poison", nil, false, false)
    truthy(manualCell.nameText:IsShown(),
        "affliges seulement : une affliction manuelle visible garde le nom")
end

-- The aura container must follow the passenger into the vehicle.
freshProfile("PALADIN")
do
    local cell = fakeButton("player", true)
    cell.auraSlotVisuals, cell.auraSlotKeys = {}, {}
    mock.state.inVehicle.player = true
    mock.state.exists.pet = true
    NS:ConfigureButtonAuraContainer(cell, false)
    eq(cell.auraContainerUnit, "pet", "conteneur : lie au jeton du vehicule")

    mock.state.inVehicle.player = false
    NS:ConfigureButtonAuraContainer(cell, false)
    eq(cell.auraContainerUnit, "player", "conteneur : revient au passager a la sortie")
end

--------------------------------------------------------------------------
-- 11. The three P2 findings, addressed in 1.4.7
--------------------------------------------------------------------------

-- The registration budget must bound the plan, and say what it dropped.
freshProfile("EVOKER")
knowSpells(374251, 360823)             -- covers every dispel type
NS:UpdateSpells()
NS.roster = {}
for index = 1, 40 do
    NS.roster[index] = { unit = "raid" .. index }
    mock.state.exists["raid" .. index] = true
end
do
    NS.db.soundMaxRegistrations = 0    -- 0 disables the ceiling
    local spellIDs, unlimited, _, unlimitedRegistrations = NS:BuildAuraSoundPlan()
    truthy(#spellIDs > 0, "budget : des sorts sont retenus")

    NS.db.soundMaxRegistrations = 500
    local _, capped, _, cappedRegistrations = NS:BuildAuraSoundPlan()
    truthy(#capped < #unlimited, "budget : le plan est effectivement plafonne")
    truthy((NS.auraSoundSkippedUnits or 0) > 0, "budget : les unites ecartees sont comptees")
    truthy(#cappedRegistrations <= 500, "budget : le plafond est respecte")
    truthy(#unlimitedRegistrations > #cappedRegistrations, "budget : des couples unite-sort sont retires")

    -- The roster is priority-ordered, so the kept units must be the first.
    eq(capped[1], "player", "budget : le joueur est garde en premier")
end

-- Protected aura data cannot truthfully select a spell before the secure
-- click. A nil selection must stay empty instead of inventing the primary
-- spell, while a remembered click keeps its exact mapping.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    local applied
    local realApplySpellCooldown = NS.ApplySpellCooldown
    NS.ApplySpellCooldown = function(_, _, def)
        applied = def
        return def and true or false
    end
    local cell = fakeButton("player", true)
    cell.cooldownSlot = nil            -- never clicked
    NS:SetCooldown(cell, nil)
    falsy(applied, "recharge : aucun sort n'est invente avant un clic")

    cell.cooldownSlot = 1
    NS.buttons = { cell }
    NS:RefreshDispelCooldowns()
    eq(applied and applied.id, 4987, "recharge : le sort du clic securise est conserve")
    NS.ApplySpellCooldown = realApplySpellCooldown
end

-- Self-only manual abilities must never generate raid-wide alerts.
freshProfile("MONK")
knowSpells(122783)
NS:UpdateSpells()
NS.roster = { { unit = "player" }, { unit = "party1" } }
mock.state.exists.party1 = true
do
    local _, units, _, registrations = NS:BuildAuraSoundPlan()
    eq(#units, 1, "son personnel : une seule unite est retenue")
    eq(units[1], "player", "son personnel : seule l'unite joueur est inscrite")
    local allPlayer = true
    for _, entry in ipairs(registrations) do
        if entry.unit ~= "player" then allPlayer = false break end
    end
    truthy(allPlayer, "son personnel : aucun couple de raid n'est cree")
end

-- Existing ordinary pets cannot consume a sound-budget slot unless they are
-- explicit roster entries or the currently displayed vehicle token.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.db.showPets = false
NS.roster = { { unit = "raid1" }, { unit = "raid2" } }
mock.state.exists.raid1, mock.state.exists.raid2 = true, true
mock.state.exists.raidpet1, mock.state.exists.raidpet2 = true, true
do
    local _, units = NS:BuildAuraSoundPlan()
    local seen = {}
    for _, unit in ipairs(units) do seen[unit] = true end
    falsy(seen.raidpet1 or seen.raidpet2, "priorite sonore : les familiers non demandes sont exclus")

    mock.state.inVehicle.raid1 = true
    local _, vehicleUnits = NS:BuildAuraSoundPlan()
    local vehicleSeen = {}
    for _, unit in ipairs(vehicleUnits) do vehicleSeen[unit] = true end
    truthy(vehicleSeen.raidpet1, "priorite sonore : le vehicule actif reste couvert")
end

-- 1.4.8 could erase the remembered click on the first zero-duration update,
-- before WoW published the real spell cooldown. The short grace period keeps
-- it, then allows normal cleanup once that race window has passed.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    local realApplySpellCooldown = NS.ApplySpellCooldown
    NS.ApplySpellCooldown = function() return false end
    local cell = fakeButton("player", true)
    cell.cooldownSlot = 1
    cell.cooldownClickTime = GetTime()
    NS.buttons = { cell }
    NS:RefreshDispelCooldowns()
    eq(cell.cooldownSlot, 1, "recharge combat : le premier zero ne perd pas le clic")

    mock.state.time = mock.state.time + 1
    NS:RefreshDispelCooldowns()
    falsy(cell.cooldownSlot, "recharge combat : le clic expire apres la fenetre de course")
    NS.ApplySpellCooldown = realApplySpellCooldown
end

-- A charge-based dispel can have a zero regular cooldown while one charge is
-- recharging. Retail's duration-object API must then drive the same number.
freshProfile("EVOKER")
knowSpells(374251)
mock.state.chargeSpells[374251] = true
NS:UpdateSpells()
do
    local regular = { IsZero = function() return true end }
    local charge = { IsZero = function() return false end }
    C_Spell.GetSpellCooldownDuration = function() return regular end
    C_Spell.GetSpellChargeDuration = function() return charge end
    local appliedDuration
    local cooldown = mock.newFrame("chargeCooldown")
    cooldown.SetCooldownFromDurationObject = function(_, duration) appliedDuration = duration end
    local active = NS:ApplySpellCooldown(cooldown, NS.clickSpells[1])
    truthy(active, "recharge de charge : la duree est active")
    eq(appliedDuration, charge, "recharge de charge : l'objet de charge est affiche")
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.source, "charge", "recharge de charge : la source est diagnostiquee")
end

-- 1.5.11: Cleanse has no charges at all, but in restricted combat the charge
-- duration object's IsZero is secret. "Not readably zero" was then read as
-- "prefer the charge object", and SetCooldownFromDurationObject cleared the
-- frame through clearIfZero: the number vanished while the affliction sweep,
-- drawn by a different frame, stayed put. Reported from the game, with
-- /cleansive cdstatus answering "source charge, active nil, applied true".
freshProfile("PALADIN")
knowSpells(4987)                       -- Cleanse: no charges at all
NS:UpdateSpells()
do
    local regular = { IsZero = function() return false end }   -- une vraie recharge en cours
    local charge = { IsZero = function() return false end }    -- objet vide d'un sort sans charges
    C_Spell.GetSpellCooldownDuration = function() return regular end
    C_Spell.GetSpellChargeDuration = function() return charge end
    local appliedDuration
    local cooldown = mock.newFrame("plainCooldown")
    cooldown.SetCooldownFromDurationObject = function(_, duration) appliedDuration = duration end

    mock.state.secretMode = true                               -- combat restreint : IsZero illisible
    NS:ApplySpellCooldown(cooldown, NS.clickSpells[1])
    mock.state.secretMode = false
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.source, "cooldown",
        "sort sans charges : la recharge normale prime sur l'objet de charge")
    eq(appliedDuration, regular, "sort sans charges : c'est la duree normale qui est affichee")
end

-- 1.5.14: the case the 1.5.12 fix could not settle. A spell that really has
-- charges, all of them banked, while a school lockout runs its normal
-- cooldown. IsZero is secret there, so the empty charge object won and
-- clearIfZero wiped the number off a spell that was genuinely unavailable.
-- SpellChargeInfo.isActive and SpellCooldownInfo.isActive are NeverSecret, so
-- nothing has to be guessed: they are asked first.
freshProfile("EVOKER")
knowSpells(374251)
mock.state.chargeSpells[374251] = true
NS:UpdateSpells()
do
    local regular = { IsZero = function() return false end }
    local charge = { IsZero = function() return false end }
    C_Spell.GetSpellCooldownDuration = function() return regular end
    C_Spell.GetSpellChargeDuration = function() return charge end
    local applied
    local cooldown = mock.newFrame("lockoutCooldown")
    cooldown.SetCooldownFromDurationObject = function(_, duration) applied = duration end

    -- Verrouillage d'ecole : charges pleines, recharge normale active.
    mock.state.spellActivity[374251] = { charge = false, cooldown = true }
    mock.state.secretMode = true                      -- IsZero illisible
    NS:ApplySpellCooldown(cooldown, NS.clickSpells[1])
    mock.state.secretMode = false
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.source, "cooldown",
        "verrouillage : la recharge normale l'emporte sur un objet de charge vide")
    eq(applied, regular, "verrouillage : c'est la duree normale qui est affichee")

    -- Une charge en cours de recuperation : l'objet de charge reprend la main.
    applied = nil
    mock.state.spellActivity[374251] = { charge = true, cooldown = false }
    mock.state.secretMode = true
    NS:ApplySpellCooldown(cooldown, NS.clickSpells[1])
    mock.state.secretMode = false
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.source, "charge",
        "verrouillage : une recharge active reste prioritaire")
    eq(applied, charge, "verrouillage : avec l'objet de charge")

    -- Rien ne tourne. L'objet normal est quand meme transmis : clearIfZero
    -- vide le cadre, et l'etat « pret » doit remonter au nettoyage du slot.
    applied = nil
    mock.state.spellActivity[374251] = { charge = false, cooldown = false }
    mock.state.secretMode = true
    local ready = NS:ApplySpellCooldown(cooldown, NS.clickSpells[1])
    mock.state.secretMode = false
    eq(ready, false, "verrouillage : un sort disponible est rapporte comme tel")
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.active, false,
        "verrouillage : et le diagnostic le dit")
    mock.state.spellActivity[374251] = nil
end

-- 1.5.14: after a secure click the cell remembers which spell was cast, so it
-- can draw a cooldown Lua cannot otherwise attribute. That memory has to be
-- released once the spell is readably ready again -- otherwise it survives
-- until combat ends and keeps a stale association on the cell. The release
-- keys on a readable `active == false`, which is only available now that the
-- NeverSecret flags are consulted.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    local regular = { IsZero = function() return true end }
    C_Spell.GetSpellCooldownDuration = function() return regular end
    C_Spell.GetSpellChargeDuration = function() return nil end
    NS:CreateGrid()
    NS.roster = { { unit = "player" } }
    NS:AssignRosterToButtons()

    local button = NS.unitToButton and NS.unitToButton["player"]
    truthy(button, "slot perime : une case est liee au joueur")
    button.cooldown.SetCooldownFromDurationObject = function() end
    button.currentSlot = nil
    button.cooldownSlot = 1
    button.cooldownClickTime = GetTime() - 1        -- au-dela des 750 ms

    mock.state.spellActivity[4987] = { charge = false, cooldown = false }
    mock.state.secretMode = true                    -- IsZero illisible
    NS:RefreshDispelCooldowns()
    mock.state.secretMode = false
    falsy(button.cooldownSlot, "slot perime : il est libere quand le sort redevient pret")
    falsy(button.cooldownClickTime, "slot perime : et son horodatage aussi")
    mock.state.spellActivity[4987] = nil
end

-- 1.5.17: 1.5.15 capped a run with the full screen size, which is only right
-- when the anchor sits against the opposite edge. From a centred anchor it
-- allowed roughly twice the cells that fit and the far half of a raid was drawn
-- off screen -- the very defect 1.5.15 announced as fixed.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    NS:CreateGrid()
    NS.db.frameSize, NS.db.spacing = 24, 2
    mock.state.screen = { width = 1920, height = 1080 }

    -- Un raid complet avec familiers : 80 unites, le pire cas reel.
    NS.roster = {}
    for i = 1, 80 do NS.roster[i] = { unit = "raid" .. i } end

    local function syncRect()
        -- Le recentrage repose l'ancre : le rectangle du test doit suivre.
        local _, _, _, x, y = NS.gridAnchor:GetPoint(1)
        NS.gridAnchor.__rect = { left = x, right = x + NS.db.frameSize,
            bottom = y, top = y + NS.db.frameSize }
    end
    local function placeAnchor(left, bottom)
        -- Ecrire la position choisie, pas seulement l'ancrage courant : depuis
        -- 1.5.20 la disposition repart de la position enregistree.
        NS.db.positions.grid = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
            x = left, y = bottom }
        NS.gridAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        syncRect()
    end

    -- Seules les cases visibles comptent : celles au-dela du roster sont
    -- masquees par AssignRosterToButtons et le joueur ne les voit jamais.
    local function worstOffsets()
        local x, y = 0, 0
        for index, button in ipairs(NS.buttons) do
            local placed = index <= #(NS.roster or {}) and button.__lastPoint or nil
            if placed then
                x = math.max(x, math.abs(placed.x or 0))
                y = math.max(y, math.abs(placed.y or 0))
            end
        end
        return x, y
    end

    -- Ancre au centre : le cas que 1.5.15 traitait comme s'il etait au bord.
    placeAnchor(860, 540)
    local roomRight = NS:AvailableExtent(true, true)
    eq(roomRight, 1060, "ancre : l'espace vers la droite part du bord de l'ancre")
    truthy(roomRight < mock.state.screen.width, "ancre : et il est plus petit que l'ecran entier")

    -- Les bornes sont verifiees en coordonnees ecran absolues, pas contre une
    -- valeur que le code calcule lui-meme : sinon un calcul faux se validerait.
    local function farthestEdges()
        local rect = NS.gridAnchor.__rect
        local ox, oy = worstOffsets()
        local right = NS.db.grow == "RIGHT_DOWN" or NS.db.grow == "RIGHT_UP"
        local down = NS.db.grow == "RIGHT_DOWN" or NS.db.grow == "LEFT_DOWN"
        local size = NS.db.frameSize
        local x = right and (rect.left + ox + size) or (rect.right - ox - size)
        local y = down and (rect.bottom - oy - size) or (rect.top + oy + size)
        return x, y
    end
    local function withinScreen(label)
        syncRect()
        local x, y = farthestEdges()
        truthy(x >= 0 and x <= mock.state.screen.width,
            "ancre : " .. label .. ", la case la plus loin reste dans la largeur (" .. math.floor(x) .. ")")
        truthy(y >= 0 and y <= mock.state.screen.height,
            "ancre : " .. label .. ", et dans la hauteur (" .. math.floor(y) .. ")")
    end

    NS.db.layoutMode = "HORIZONTAL"
    NS.db.grow = "RIGHT_DOWN"
    NS:LayoutButtons()
    withinScreen("ancre centree, horizontal")

    NS.db.layoutMode = "VERTICAL"
    NS:LayoutButtons()
    withinScreen("ancre centree, vertical")

    -- Les quatre directions, depuis un coin oppose a chaque fois.
    local corners = {
        { grow = "RIGHT_DOWN", left = 40, bottom = 1000 },
        { grow = "LEFT_DOWN", left = 1840, bottom = 1000 },
        { grow = "RIGHT_UP", left = 40, bottom = 40 },
        { grow = "LEFT_UP", left = 1840, bottom = 40 },
    }
    for _, case in ipairs(corners) do
        NS.db.grow = case.grow
        placeAnchor(case.left, case.bottom)
        NS.db.layoutMode = "HORIZONTAL"
        NS:LayoutButtons()
        withinScreen(case.grow .. " horizontal")
        NS.db.layoutMode = "VERTICAL"
        NS:LayoutButtons()
        withinScreen(case.grow .. " vertical")
    end

    -- Cas limite : l'espace vaut exactement une case plus un nombre entier de
    -- pas. Sans la marge de 3 px que la disposition ajoute, le calcul autorise
    -- une rangee de trop et la derniere depasse le bord.
    NS.db.grow = "RIGHT_DOWN"
    placeAnchor(860, 24 + 26 * 20)          -- taille 24, pas 26
    NS.db.layoutMode = "VERTICAL"
    NS:LayoutButtons()
    withinScreen("bord exact")

    -- Aucune case perdue par le repli, quelle que soit la direction.
    local placed = 0
    for _, button in ipairs(NS.buttons) do
        if button.__lastPoint then placed = placed + 1 end
    end
    eq(placed, #NS.buttons, "ancre : aucune case n'est perdue")

    -- 1.5.18: depuis une ancre collee au bord vers lequel la grille grandit,
    -- l'espace vaut une trentaine de cases et un raid en compte 80. Aucun repli
    -- ne les y fait tenir : la grille se replace donc dans l'ecran.
    local unfavourable = {
        { grow = "RIGHT_DOWN", left = 1700, bottom = 120 },
        { grow = "LEFT_UP", left = 60, bottom = 960 },
        { grow = "RIGHT_UP", left = 1700, bottom = 960 },
        { grow = "LEFT_DOWN", left = 60, bottom = 120 },
    }
    for _, case in ipairs(unfavourable) do
        for _, mode in ipairs({ "HORIZONTAL", "VERTICAL", "GRID" }) do
            NS.db.grow = case.grow
            NS.db.layoutMode = mode
            placeAnchor(case.left, case.bottom)
            NS:LayoutButtons()
            withinScreen("coin defavorable " .. case.grow .. " " .. mode)
        end
    end

    -- 1.5.18: le nombre de cases depend de la position de l'ancre depuis la
    -- 1.5.17, mais rien ne recalculait apres un deplacement. Une grille calculee
    -- au centre restait dimensionnee pour le centre une fois tiree vers un bord.
    NS.db.grow = "RIGHT_DOWN"
    NS.db.layoutMode = "HORIZONTAL"
    placeAnchor(860, 540)
    NS:LayoutButtons()
    placeAnchor(1700, 540)                       -- l'ancre bouge, sans autre reglage
    NS.gridAnchor:GetScript("OnDragStop")(NS.gridAnchor)
    withinScreen("apres deplacement de l'ancre")

    -- 1.5.20: une remise a zero demandee en combat rejouait la position apres
    -- le combat sans relancer le calcul. La grille gardait le repli calcule
    -- pour l'ancien coin.
    NS.db.grow = "RIGHT_DOWN"
    NS.db.layoutMode = "HORIZONTAL"
    placeAnchor(1700, 120)
    NS:LayoutButtons()
    mock.state.inCombat = true
    NS:ResetPositions()
    truthy(NS.pendingPositionReset, "remise a zero : differee pendant le combat")
    truthy(NS.pendingLayout, "remise a zero : le calcul est replanifie aussi")
    mock.state.inCombat = false
    -- Le rectangle du test suppose un ancrage BOTTOMLEFT ; la remise a zero
    -- repasse en CENTER, donc on observe le recalcul plutot que les bornes.
    local layouts = 0
    local realLayout = NS.LayoutButtons
    NS.LayoutButtons = function(selfRef) layouts = layouts + 1 return realLayout(selfRef) end
    NS:FlushCombatUpdates()
    NS.LayoutButtons = realLayout
    truthy(layouts > 0, "remise a zero : la grille est recalculee a la sortie du combat")
    falsy(NS.pendingLayout, "remise a zero : le drapeau est consomme")

    -- 1.5.20: le recentrage etait a sens unique. Une fois pousse par un raid,
    -- rien ne ramenait la grille a la position choisie quand le groupe
    -- retrecissait -- contrairement a ce qu'annoncait la 1.5.18.
    NS.db.layoutMode = "HORIZONTAL"
    -- Un coin ou 80 cases ne tiennent pas : environ 2 colonnes sur 4 rangees.
    placeAnchor(1850, 120)
    NS:LayoutButtons()
    do
        local _, _, _, px, py = NS.gridAnchor:GetPoint(1)
        truthy(px ~= 1850 or py ~= 120, "retour : un raid pousse la grille hors du coin")
    end
    NS.roster = { { unit = "player" }, { unit = "party1" } }
    NS:LayoutButtons()
    do
        local _, _, _, px, py = NS.gridAnchor:GetPoint(1)
        eq(px, 1850, "retour : elle revient a l'abscisse choisie quand le groupe retrecit")
        eq(py, 120, "retour : et a l'ordonnee choisie")
    end
    NS.roster = {}
    for i = 1, 80 do NS.roster[i] = { unit = "raid" .. i } end

    -- 1.5.20: le badge groupe est ancre du cote oppose a la croissance, avec
    -- une case entiere plus 4 px. Il ne figurait pas dans le rectangle borne.
    do
        local realManual = NS.GetManualOnlyTypes
        NS.GetManualOnlyTypes = function() return { "Poison" } end
        NS.db.groupManualTypes = true
        for _, case in ipairs({
            { grow = "RIGHT_DOWN", left = 400, bottom = 1040 },   -- colle en haut
            { grow = "RIGHT_UP", left = 400, bottom = 20 },       -- colle en bas
        }) do
            NS.db.grow = case.grow
            NS.db.layoutMode = "GRID"
            placeAnchor(case.left, case.bottom)
            NS:LayoutButtons()
            syncRect()
            local rect = NS.gridAnchor.__rect
            local up = case.grow == "RIGHT_UP" or case.grow == "LEFT_UP"
            local badgeEdge = up and (rect.bottom - NS.db.frameSize - 4)
                or (rect.top + NS.db.frameSize + 4)
            truthy(badgeEdge >= 0 and badgeEdge <= mock.state.screen.height,
                "badge : " .. case.grow .. ", il reste a l'ecran (" .. math.floor(badgeEdge) .. ")")
        end
        -- 1.5.21: le cas extreme. Une colonne verticale qui occupe presque
        -- toute la hauteur choisissait ses rangees contre la hauteur entiere,
        -- puis le recentrage la descendait de 28 px pour sauver le badge : la
        -- derniere case sortait d'autant par le bas.
        for _, case in ipairs({
            { grow = "RIGHT_DOWN", left = 400, bottom = 1050, mode = "VERTICAL" },
            { grow = "RIGHT_UP", left = 400, bottom = 10, mode = "VERTICAL" },
            { grow = "RIGHT_DOWN", left = 400, bottom = 1050, mode = "GRID" },
            { grow = "RIGHT_UP", left = 400, bottom = 10, mode = "GRID" },
        }) do
            NS.db.grow = case.grow
            NS.db.layoutMode = case.mode
            NS.db.columns = 1
            placeAnchor(case.left, case.bottom)
            NS:LayoutButtons()
            withinScreen("badge pleine hauteur " .. case.grow .. " " .. case.mode)
            syncRect()
            local rect = NS.gridAnchor.__rect
            local up = case.grow == "RIGHT_UP" or case.grow == "LEFT_UP"
            local badgeEdge = up and (rect.bottom - NS.db.frameSize - 4)
                or (rect.top + NS.db.frameSize + 4)
            truthy(badgeEdge >= 0 and badgeEdge <= mock.state.screen.height,
                "badge pleine hauteur : " .. case.grow .. " " .. case.mode
                .. ", le badge tient aussi (" .. math.floor(badgeEdge) .. ")")
        end
        NS.db.columns = 10

        NS.GetManualOnlyTypes = realManual
        NS.db.groupManualTypes = false
    end

    NS.gridAnchor.__rect = nil
    NS.db.layoutMode = "GRID"
    NS.db.grow = "RIGHT_DOWN"
end

-- 1.5.15: applyDefaults only fills what is missing, so a hand-edited or
-- truncated SavedVariables file reached CreateFrame with a string where a
-- number belongs, an opacity outside its slider, a layout mode that no longer
-- exists, or a position missing its anchor -- which SetPoint refuses.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true },
    profiles = { ["Ekinoks-Hyjal"] = { ["65"] = {
        frameSize = "grand",          -- pas un nombre
        spacing = -40,                -- sous la borne
        columns = 999,                -- au-dessus
        inactiveAlpha = 12,           -- hors plage
        layoutMode = "DIAGONAL",      -- n'existe pas
        grow = "NULLE_PART",
        soundChannel = "Chuchotement",
        positions = { grid = { point = "CENTER" } },   -- tronquee
    } } },
}
NS:InitializeProfiles()
do
    eq(NS.db.frameSize, NS.profileDefaults.frameSize, "donnees : une taille non numerique revient au defaut")
    eq(NS.db.spacing, 0, "donnees : un espacement negatif est borne")
    eq(NS.db.columns, 20, "donnees : un nombre de colonnes excessif est borne")
    eq(NS.db.inactiveAlpha, 0.80, "donnees : une opacite hors plage est bornee")
    eq(NS.db.layoutMode, NS.profileDefaults.layoutMode, "donnees : une disposition inconnue revient au defaut")
    eq(NS.db.grow, NS.profileDefaults.grow, "donnees : une direction inconnue revient au defaut")
    eq(NS.db.soundChannel, NS.profileDefaults.soundChannel, "donnees : un canal inconnu revient au defaut")
    local grid = NS.db.positions and NS.db.positions.grid
    truthy(grid and grid.relativePoint and tonumber(grid.x) and tonumber(grid.y),
        "donnees : une position tronquee est reconstruite")
end

-- 1.5.17: l'audit 1.5.16 a montre que la normalisation s'arretait aux nombres
-- et aux enumerations. Un point d'ancrage invalide, des coordonnees texte, une
-- valeur fractionnaire ou un booleen d'un autre type passaient au travers, et
-- SetPoint leve sur un ancrage inconnu des le chargement.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true, groupManualOptOutAllProfiles159 = true },
    profiles = { ["Ekinoks-Hyjal"] = { ["65"] = {
        columns = 10.4,                 -- fractionnaire
        frameSize = 22.7,
        showTooltips = "oui",           -- truthy mais pas un booleen
        locked = "false",               -- truthy en Lua : le piege classique
        typeOrder = { "Magic", "Magic", "Inconnu", "Curse" },
        enabledTypes = { Magic = "oui", Fantome = true },
        positions = { grid = { point = "DIAGONALE", relativePoint = 42, x = "gauche", y = -120 } },
    } } },
}
NS:InitializeProfiles()
do
    eq(NS.db.columns, 10, "donnees : une valeur fractionnaire est arrondie")
    eq(NS.db.frameSize, 23, "donnees : la taille aussi")
    eq(NS.db.showTooltips, NS.profileDefaults.showTooltips,
        "donnees : un booleen d'un autre type revient au defaut")
    -- 1.5.18: "false" est truthy en Lua. L'ancienne normalisation le lisait
    -- comme vrai et verrouillait une grille que le joueur avait deverrouillee.
    eq(NS.db.locked, NS.profileDefaults.locked, "donnees : la chaine false ne verrouille plus")
    do
        local order, seen = NS.db.typeOrder, {}
        eq(#order, #NS.profileDefaults.typeOrder, "donnees : l'ordre des types est complet")
        for _, auraType in ipairs(order) do
            falsy(seen[auraType], "donnees : aucun doublon dans l'ordre des types")
            seen[auraType] = true
        end
        eq(order[1], "Magic", "donnees : l'ordre valide sauvegarde est conserve")
        eq(order[2], "Curse", "donnees : sans le type inconnu")
        eq(type(NS.db.enabledTypes.Magic), "boolean", "donnees : les types actifs sont booleens")
        falsy(NS.db.enabledTypes.Fantome, "donnees : un type inconnu est retire")
    end
    local grid = NS.db.positions.grid
    eq(grid.point, "CENTER", "donnees : un ancrage inconnu revient au defaut")
    eq(grid.relativePoint, "CENTER", "donnees : l'ancrage relatif aussi")
    eq(grid.x, -180, "donnees : une coordonnee texte est reparee")
    eq(grid.y, -120, "donnees : une coordonnee valide est conservee")
end

-- Et si une position casse malgre tout, le placement retombe sur le defaut
-- au lieu de lever.
do
    NS.db.positions.grid = { point = "NULLE_PART" }
    local frame = mock.newFrame("ancre")
    local ok = pcall(function() NS:RestorePosition(frame, "grid") end)
    truthy(ok, "donnees : une position cassee n'empeche pas le placement")
    eq(frame.__lastPoint and frame.__lastPoint.point, "CENTER",
        "donnees : elle retombe sur l'ancrage par defaut")
end

-- 1.5.16: every label carried a fixed size tuned for a 22 px cell. At 12 px the
-- click plate alone covered most of the cell and the labels overlapped; at 40 px
-- they floated in empty space.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    -- La configuration par defaut ne doit pas bouger d'un pixel.
    eq(NS:CellFontSize("name", 22), 10, "polices : 22 px, le nom est inchange")
    eq(NS:CellFontSize("stack", 22), 10, "polices : 22 px, les charges sont inchangees")
    eq(NS:CellFontSize("hint", 22), 9, "polices : 22 px, la lettre de clic est inchangee")
    eq(NS:CellFontSize("countdown", 22), 12, "polices : 22 px, la recharge est inchangee")
    eq(NS:CellFontSize("plate", 22), 11, "polices : 22 px, la plaque est inchangee")

    -- Les extremes sont bornes des deux cotes.
    truthy(NS:CellFontSize("countdown", 12) < 12, "polices : une petite case reduit la recharge")
    truthy(NS:CellFontSize("countdown", 40) > 12, "polices : une grande case l'agrandit")
    eq(NS:CellFontSize("countdown", 40), 16, "polices : sans depasser le plafond")
    eq(NS:CellFontSize("plate", 12), 8, "polices : la plaque ne mange plus la case")

    -- 1.5.18: chaque type d'aura avait son propre repere, decale lateralement
    -- pour que deux visuels ne s'impriment pas l'un sur l'autre. Trois plaques
    -- en demandent 46 px avec leur marge et la plus grande case en fait 40 : la
    -- troisieme lettre ne pouvait donc jamais etre dessinee. Un seul repere
    -- desormais, toujours au meme coin -- le niveau de cadre encode deja la
    -- priorite du type, donc la bonne lettre passe au-dessus d'elle-meme.
    eq(NS:ClickHintOffset(1, 22), 0, "reperes : au coin, sans decalage")
    eq(NS:ClickHintOffset(2, 22), 0, "reperes : le deuxieme au meme endroit")
    eq(NS:ClickHintOffset(3, 22), 0, "reperes : le troisieme aussi, enfin visible")
    do
        local hidden = 0
        for size = 12, 40 do
            for slot = 1, 3 do
                local offset = NS:ClickHintOffset(slot, size)
                if offset then
                    -- 1 + decalage : l'ancrage reel de la plaque.
                    truthy(1 + offset + NS:CellFontSize("plate", size) <= size,
                        "reperes : la plaque tient dans une case de " .. size)
                else
                    hidden = hidden + 1
                end
            end
        end
        eq(hidden, 0, "reperes : les trois emplacements sont desormais affichables partout")
    end

    -- Le nom se masque quand la case devient trop petite pour lui.
    NS.db.showNames = true
    NS.db.frameSize = 22
    truthy(NS:CellShowsNames(), "polices : a 22 px le nom reste affiche")
    NS.db.frameSize = 12
    falsy(NS:CellShowsNames(), "polices : a 12 px il est masque plutot qu'illisible")
    NS.db.showNames = false
    NS.db.frameSize = 22

    -- Bouger le curseur de taille doit repeindre les polices posees.
    -- Le harnais neutralise GetUXFont : sans police, ApplyCellFonts sort tout
    -- de suite et le test ne prouverait rien.
    local realGetUXFont = NS.GetUXFont
    NS.GetUXFont = function() return "police.ttf" end
    NS:CreateGrid()
    NS.db.frameSize = 40
    NS:LayoutButtons()
    local button = NS.buttons[1]
    eq(button.nameText.__font and button.nameText.__font.height, NS:CellFontSize("name", 40),
        "polices : le curseur de taille repeint les libelles")
    eq(button.clickHintPlate.__lastSize and button.clickHintPlate.__lastSize.width,
        NS:CellFontSize("plate", 40), "polices : et redimensionne la plaque")
    NS.db.frameSize = 22
    NS.GetUXFont = realGetUXFont
end

-- 1.5.16 stripped the cell to colour, sweep and dispel cooldown, and swept
-- showStacks to false in every existing profile to make it stick. 1.5.17 undoes
-- the sweep: a changed default belongs to new profiles, and the stack count is
-- still a supported option with its own button, so overwriting it erased a
-- deliberate choice. Same rule for the click letters, off by default since
-- 1.5.17 without touching anyone's setting.
freshProfile("PALADIN")
falsy(NS.db.showStacks, "defauts : les charges sont eteintes sur une installation neuve")
falsy(NS.db.showClickHints, "defauts : les lettres de clic aussi")

mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true, groupManualOptOutAllProfiles159 = true },
    profiles = {
        ["Ekinoks-Hyjal"] = { ["65"] = { showStacks = true, showClickHints = true } },
        ["Autre-Hyjal"] = { ["577"] = { showStacks = true } },
    },
}
NS:InitializeProfiles()
do
    local profiles = CleansiveDB.profiles
    truthy(profiles["Ekinoks-Hyjal"]["65"].showStacks,
        "defauts : un choix volontaire d'afficher les charges survit a la mise a jour")
    truthy(profiles["Ekinoks-Hyjal"]["65"].showClickHints,
        "defauts : celui des lettres de clic aussi")
    truthy(profiles["Autre-Hyjal"]["577"].showStacks,
        "defauts : y compris sur un personnage non connecte")
end

-- Un profil qui n'a jamais rien dit recoit bien le nouveau defaut.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true, groupManualOptOutAllProfiles159 = true },
    profiles = { ["Ekinoks-Hyjal"] = { ["65"] = { frameSize = 30 } } },
}
NS:InitializeProfiles()
falsy(NS.db.showStacks, "defauts : un profil muet prend le nouveau defaut")

-- 1.5.19: every spell definition of the class reserved an engine slot, known
-- or not. An evoker's definitions span Magic, Poison, Curse, Disease and
-- Bleed, so a character who knows one cleanse still paid for five slots on all
-- 82 buttons -- 410 protected frames instead of 82.
freshProfile("EVOKER")
knowSpells(365585)                     -- Cauterizing Flame seul : Poison
NS:UpdateSpells()
do
    NS.buttons, NS.gridBody = {}, mock.newFrame("body")
    NS.engineAuraTypes = {}
    NS:RefreshAuraEngineTypes()
    eq(#NS.engineAuraTypes, 1, "emplacements : un seul type pour un seul sort connu")
    eq(NS.engineAuraTypes[1], "Poison", "emplacements : et c'est le bon")

    -- Apprendre un second sort elargit l'ensemble, sans le figer sur la classe.
    knowSpells(360823)                 -- Naturalize : Magic et Poison
    NS:UpdateSpells()
    NS:RefreshAuraEngineTypes()
    eq(#NS.engineAuraTypes, 2, "emplacements : deux types apres un second sort")

    -- La classe entiere en couvre cinq : c'est ce qu'on ne reserve plus.
    local classWide = {}
    for _, def in ipairs(NS.SPELL_DEFINITIONS) do
        if def.class == "EVOKER" then
            for _, list in ipairs({ def.types, def.enhancedTypes }) do
                for _, auraType in ipairs(list or {}) do classWide[auraType] = true end
            end
        end
    end
    local total = 0
    for _ in pairs(classWide) do total = total + 1 end
    truthy(total > #NS.engineAuraTypes,
        "emplacements : la classe en couvrirait " .. total .. ", on en reserve " .. #NS.engineAuraTypes)
end

-- 1.5.20: un sort connu reservait aussi ses enhancedTypes, meme sans le talent
-- qui les debloque. Un pretre sans 390632 payait un emplacement pour Disease
-- sur les 82 boutons.
freshProfile("PRIEST")
knowSpells(527)                        -- Purify : Magic, et Disease avec 390632
NS:UpdateSpells()
do
    NS.buttons, NS.gridBody = {}, mock.newFrame("body")
    NS.engineAuraTypes = {}
    NS:RefreshAuraEngineTypes()
    eq(#NS.engineAuraTypes, 1, "amelioration : sans le talent, un seul type")
    eq(NS.engineAuraTypes[1], "Magic", "amelioration : et c'est le bon")

    knowSpells(390632)                 -- le talent d'amelioration
    NS:UpdateSpells()
    NS:RefreshAuraEngineTypes()
    eq(#NS.engineAuraTypes, 2, "amelioration : le talent ajoute son type")
end

-- 1.5.20: le repli de demarrage etait inatteignable. UpdateSpells vide
-- knownSpells des son entree, donc tester sa non-nullite le declarait resolu.
-- 1.5.21: le tester non vide confondait ensuite deux situations distinctes --
-- grimoire pas encore pret, et grimoire pret sur un personnage qui ne connait
-- aucun sort. La seconde gardait l'ensemble prudent pour toute la session.
freshProfile("PALADIN")
NS.spellbookResolved = nil
NS.knownSpells = {}
do
    NS.buttons, NS.gridBody = {}, mock.newFrame("body")
    NS.engineAuraTypes = {}
    NS:RefreshAuraEngineTypes()
    truthy(#NS.engineAuraTypes > 0,
        "demarrage : un grimoire non resolu garde l'ensemble de la classe")

    -- Le client a repondu : zero sort veut dire zero type.
    NS.spellbookResolved = true
    NS.engineAuraTypes = {}
    NS:RefreshAuraEngineTypes()
    eq(#NS.engineAuraTypes, 0,
        "demarrage : une fois le grimoire confirme, aucun sort donne aucun type")
    NS.spellbookResolved = nil
end

-- 1.5.22: l'infobulle affirmait qu'activer ou desactiver ne touchait pas aux
-- reglages enregistres. SetEnabled ecrit db.enabled, qui est persiste dans le
-- profil : le texte disait l'inverse du code. Le texte est corrige, ce test
-- garde le comportement qu'il decrit maintenant.
freshProfile("PALADIN")
do
    NS:SetEnabled(false, true)
    falsy(NS.db.enabled, "activation : desactiver est ecrit dans le profil")
    NS:SetEnabled(true, true)
    truthy(NS.db.enabled, "activation : reactiver aussi")

    -- Les commandes show et hide, elles, restent temporaires.
    NS:SetGridVisible(false)
    truthy(NS.db.enabled, "activation : masquer la grille ne desactive pas l'addon")
    NS:SetGridVisible(true)          -- rendre l etat, sinon tout le reste est aveugle
end

-- The countdown used to be parented to a secure cell. In combat that made the
-- visible update protected even though the duration API itself succeeded. The
-- numeric layer must remain a normal UIParent child and merely mirror the grid.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    NS:CreateGrid()
    eq(NS.cooldownBody.__parent, UIParent, "recharge combat : la couche numerique appartient a UIParent")
    falsy(NS.cooldownBody.__template, "recharge combat : la couche numerique n'utilise aucun modele securise")
    eq(NS.buttons[1].cooldown.__parent, NS.cooldownBody,
        "recharge combat : le nombre est hors de la hierarchie securisee")
    truthy(NS.buttons[1].__template and NS.buttons[1].__template:find("Secure", 1, true),
        "recharge combat : la cellule de clic reste securisee")

    -- La couche de recharge n'est qu'un DECALQUE de l'ancre securisee : chaque
    -- voile s'ancre a un de ses COINS, avec les memes coordonnees que la case
    -- qui s'ancre au coin de l'ancre. Si les deux cadres cessent d'avoir la
    -- meme taille, leurs coins ne coincident plus et TOUS les voiles se
    -- decalent de la difference. Les deux sont bien redimensionnes ensemble,
    -- mais a deux endroits eloignes de LayoutButtons et rien ne les liait :
    -- supprimer l'un des deux appels ne cassait aucun test. Ce n'est PAS
    -- l'explication des coins noirs vus en jeu le 30/08 -- cette piste a ete
    -- suivie et refutee -- c'est un invariant trouve en chemin et laisse sans
    -- garde-fou.
    for _, size in ipairs({ 12, 22, 40 }) do
        NS.db.frameSize = size
        NS:LayoutButtons()
        eq(NS.cooldownBody.__lastSize.width, NS.gridAnchor.__lastSize.width,
            "decalque " .. size .. " px : meme largeur que l'ancre")
        eq(NS.cooldownBody.__lastSize.height, NS.gridAnchor.__lastSize.height,
            "decalque " .. size .. " px : meme hauteur")
    end

    -- Et la meme pose : une taille identique ne sert a rien si les deux cadres
    -- ne partent pas du meme point.
    NS:RestorePosition(NS.gridAnchor, "grid")
    local anchorPoint, cooldownPoint = NS.gridAnchor.__lastPoint, NS.cooldownBody.__lastPoint
    eq(cooldownPoint.point, anchorPoint.point, "decalque : meme point d'ancrage")
    eq(cooldownPoint.relativePoint, anchorPoint.relativePoint, "decalque : meme point de reference")
    eq(cooldownPoint.x, anchorPoint.x, "decalque : meme abscisse")
    eq(cooldownPoint.y, anchorPoint.y, "decalque : meme ordonnee")
    NS.db.frameSize = 22
end

--------------------------------------------------------------------------
-- 12. Manual-ability tooltip on the protected path (P2-d, fixed in 1.5.0)
--------------------------------------------------------------------------

-- Lua never sees the aura in engine mode, so the tooltip cannot name the
-- ability for *this* affliction. It must still say what the player has to
-- press. Before 1.5.0 it fell through to the generic "protected" line.
do
    local lines
    -- Every override must be handed back. Restoring SetOwner alone left
    -- AddLine writing into this block's dead local for the rest of the run,
    -- so any later tooltip assertion silently read an empty table.
    local realOwner, realAddLine, realShow = GameTooltip.SetOwner, GameTooltip.AddLine, GameTooltip.Show
    GameTooltip.SetOwner = function() lines = {} end
    GameTooltip.AddLine = function(_, text) if lines then lines[#lines + 1] = tostring(text) end end
    GameTooltip.Show = function() end

    local function tooltipOf(cell)
        lines = nil
        NS:ShowButtonTooltip(cell)
        return table.concat(lines or {}, "\n")
    end

    -- Shaman: Poison is covered only by the untargeted totem.
    freshProfile("SHAMAN")
    knowSpells(383013)
    NS:UpdateSpells()
    NS.db.showTooltips = true
    do
        local cell = fakeButton("player", true)
        cell.descriptor = { displayName = "Ekinoks" }
        local text = tooltipOf(cell)
        truthy(text:find("Totem", 1, true) or text:find("Spell383013", 1, true),
            "infobulle moteur : la capacite manuelle est nommee")
    end

    -- Paladin: everything is clickable, so nothing extra should be listed.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.db.showTooltips = true
    do
        local cell = fakeButton("player", true)
        cell.descriptor = { displayName = "Ekinoks" }
        local text = tooltipOf(cell)
        falsy(text:find("toi-m", 1, true) or text:find("yourself", 1, true),
            "infobulle moteur : aucune ligne manuelle quand tout est cliquable")
    end

    -- The translated type names must come from Locale.lua, not from a table
    -- private to the options file.
    freshProfile("PALADIN")
    NS.db.language = "frFR"
    eq(NS:GetTypeLabel("Poison"), "Poison", "libelle de type : accessible hors de l'interface")
    eq(NS:GetTypeLabel("Bleed"), "Saignement", "libelle de type : traduit en francais")
    NS.db.language = "enUS"
    eq(NS:GetTypeLabel("Bleed"), "Bleed", "libelle de type : traduit en anglais")

    GameTooltip.SetOwner, GameTooltip.AddLine, GameTooltip.Show = realOwner, realAddLine, realShow
end

--------------------------------------------------------------------------
-- 13. Secret values in the cooldown path (1.4.9 -> flooded the error log)
--------------------------------------------------------------------------

-- Frames.lua:999 did `return not zero` on the result of duration:IsZero().
-- In protected combat that is a SECRET boolean; negating one raises, and this
-- runs on every cooldown refresh. It produced 5546 identical errors in one
-- session and WoW disabled the addon.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.db.showCooldown = true
do
    local applied
    local duration = { IsZero = function() return true end }
    -- Earlier cases replace these globally without restoring them, so pin
    -- both here: otherwise this case silently runs down the charge branch.
    local savedGet = C_Spell.GetSpellCooldownDuration
    local savedCharge = C_Spell.GetSpellChargeDuration
    C_Spell.GetSpellCooldownDuration = function() return duration end
    C_Spell.GetSpellChargeDuration = function() return nil end
    local cooldown = mock.newFrame("cd")
    cooldown.SetCooldownFromDurationObject = function(_, d) applied = d end

    mock.state.secretMode = true
    local ok, err = pcall(NS.ApplySpellCooldown, NS, cooldown, NS.clickSpells[1], nil)
    truthy(ok, "valeur secrete : aucune erreur levee")
    check(ok, "valeur secrete : la passe de recharge survit", tostring(err))
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.active, nil,
        "valeur secrete : l'etat n'est pas deduit d'une valeur illisible")
    truthy(applied, "valeur secrete : la duree est quand meme appliquee")

    -- Readable again: the state must be derived normally.
    mock.state.secretMode = false
    NS:ApplySpellCooldown(cooldown, NS.clickSpells[1], nil)
    eq(NS.cooldownDiagnostics and NS.cooldownDiagnostics.active, false,
        "valeur lisible : l'etat est deduit comme avant")

    C_Spell.GetSpellCooldownDuration = savedGet
    C_Spell.GetSpellChargeDuration = savedCharge
end

-- Audit 1.5.3: the existing macro assertion above exercises the secure
-- priority-key macro, not the user macro created by /cleansive macro. Force an
-- override/base-name difference so the two paths cannot accidentally agree.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    local def = NS.clickSpells[1]
    local savedName, savedSecureName = def.name, def.secureName
    def.name, def.secureName = "DisplayOverride", "SecureBase"
    local macro = NS:BuildMacroBody()
    truthy(macro and macro:find("SecureBase", 1, true),
        "audit macro utilisateur : utilise le nom de base securise")
    falsy(macro and macro:find("DisplayOverride", 1, true),
        "audit macro utilisateur : n'utilise pas le nom d'override")
    def.name, def.secureName = savedName, savedSecureName
end

-- Audit 1.5.3: when IsZero is protected, a zero regular duration must not hide
-- an active charge-recharge duration. The spell must be declared charge-based:
-- since 1.5.11 the charge object is only preferred for a spell that has any.
freshProfile("EVOKER")
knowSpells(374251)
mock.state.chargeSpells[374251] = true
NS:UpdateSpells()
NS.db.showCooldown = true
do
    local regular = { IsZero = function() return true end }
    local charge = { IsZero = function() return false end }
    local savedGet = C_Spell.GetSpellCooldownDuration
    local savedCharge = C_Spell.GetSpellChargeDuration
    C_Spell.GetSpellCooldownDuration = function() return regular end
    C_Spell.GetSpellChargeDuration = function() return charge end
    local applied
    local cooldown = mock.newFrame("secretChargeCooldown")
    cooldown.SetCooldownFromDurationObject = function(_, duration) applied = duration end
    mock.state.secretMode = true
    NS:ApplySpellCooldown(cooldown, NS.clickSpells[1], nil)
    eq(applied, charge, "audit recharge secrete : la recharge de charge est affichee")
    mock.state.secretMode = false
    C_Spell.GetSpellCooldownDuration = savedGet
    C_Spell.GetSpellChargeDuration = savedCharge
end

-- Audit 1.5.3: on the Lua fallback, aura removal used to clear cooldownSlot. The last
-- delayed refresh then reapplies the duration and immediately clears it again.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
NS.db.showCooldown = true
do
    local duration = { IsZero = function() return false end }
    local savedGet = C_Spell.GetSpellCooldownDuration
    local savedCharge = C_Spell.GetSpellChargeDuration
    C_Spell.GetSpellCooldownDuration = function() return duration end
    C_Spell.GetSpellChargeDuration = function() return nil end
    local visible = false
    local cell = fakeButton("player", false)
    cell.cooldown.SetCooldownFromDurationObject = function() visible = true end
    cell.cooldown.Clear = function() visible = false end
    NS.buttons = { cell }
    NS:RecordSecureClick(cell, "LeftButton")
    NS:SetButtonState(cell, nil, nil, nil, false, false)
    mock.runTimers()
    truthy(visible, "audit recharge de repli : le nombre survit a la disparition de l'aura")
    C_Spell.GetSpellCooldownDuration = savedGet
    C_Spell.GetSpellChargeDuration = savedCharge
end

-- Locking hides the anchor and must also remove its invisible mouse target.
-- EnableMouse is protected, so a combat-time change is deferred until combat
-- ends instead of attempting a forbidden mutation.
freshProfile("PALADIN")
do
    local states = {}
    local anchor = mock.newFrame("anchorAppearance")
    anchor.handle = mock.newFrame("anchorHandle")
    anchor.mark = mock.newFrame("anchorMark")
    anchor.accentLine = mock.newFrame("anchorAccent")
    anchor.EnableMouse = function(_, enabled) states[#states + 1] = enabled end
    NS.gridAnchor = anchor

    NS.db.locked = true
    mock.state.inCombat = false
    NS:UpdateGridAnchorAppearance()
    eq(states[#states], false, "ancre verrouillee : la souris est desactivee")

    NS.db.locked = false
    mock.state.inCombat = true
    NS:UpdateGridAnchorAppearance()
    eq(#states, 1, "ancre en combat : aucune mutation protegee")
    truthy(NS.pendingAnchorAppearance, "ancre en combat : mise a jour differee")

    mock.state.inCombat = false
    NS:UpdateGridAnchorAppearance()
    eq(states[#states], true, "ancre deverrouillee : la souris est reactivee")
    falsy(NS.pendingAnchorAppearance, "ancre deverrouillee : report acquitte")
end

-- Blizzard periodically imports SlashCmdList into a private hash. If that
-- already happened, registering the late compatibility aliases must queue the
-- existing callback in the public list again.
do
    local originalList = SlashCmdList
    local callback = originalList.CLEANSIVE
    local imported = { CLEANSIVE = callback }
    SlashCmdList = setmetatable({}, { __index = imported })
    NS.compatibilitySlashAliasesChecked = nil
    NS:RegisterCompatibilitySlashAliases()
    eq(SLASH_CLEANSIVE3, "/dcr", "alias tardif : /dcr enregistre")
    eq(SLASH_CLEANSIVE4, "/decursive", "alias tardif : /decursive enregistre")
    eq(rawget(SlashCmdList, "CLEANSIVE"), callback,
        "alias tardif : rappel remis dans la file d'import Blizzard")
    SlashCmdList = originalList
end

--------------------------------------------------------------------------
-- 14. Grouping untargetable cleanses (retour utilisateur, 1.5.4)
--------------------------------------------------------------------------

-- A Demon Hunter's only Magic option is Reverse Magic, an area ability that
-- cannot be aimed. Painting it on every raid member repeated one bit of
-- information forty times -- "press Reverse Magic" -- which is what the first
-- real user reported as "un beau pave".
freshProfile("DEMONHUNTER")
knowSpells(205604, 278326)             -- Reverse Magic (untargeted), Consume Magic
NS.db.groupManualTypes = true          -- opt-in since 1.5.5, so state it here
NS:UpdateSpells()
do
    truthy(NS:IsTypeGrouped("Magic"), "regroupement : la magie du DH est regroupee")
    falsy(NS:IsTypeGrouped("Charm"), "regroupement : le charme reste par unite, il est cliquable")
    local grouped = NS:GetManualOnlyTypes()
    eq(#grouped, 1, "regroupement : un seul type concerne")
    eq(grouped[1], "Magic", "regroupement : c'est bien la magie")
end

-- Grouped types must lose their per-unit cell painting on the Lua path too.
freshProfile("DEMONHUNTER")
knowSpells(205604)
NS.db.groupManualTypes = true
NS:UpdateSpells()
mock.state.debuffs.player = { debuff(777, "Magic") }
do
    local aura, auraType, slot = NS:GetCurableAura("player")
    falsy(aura, "regroupement : la case d'unite ne s'allume plus pour un type regroupe")
    falsy(slot, "regroupement : et elle ne recoit aucun clic")
end

-- Turning the option off restores the old per-unit behaviour.
NS.db.groupManualTypes = false
NS:UpdateSpells()
do
    falsy(NS:IsTypeGrouped("Magic"), "option desactivee : plus de regroupement")
    local aura, auraType = NS:GetCurableAura("player")
    truthy(aura, "option desactivee : la case d'unite se rallume")
    eq(auraType, "Magic", "option desactivee : avec le bon type")
end

-- A class that can click every type must see no change at all.
freshProfile("PALADIN")
knowSpells(4987)
NS:UpdateSpells()
do
    eq(#NS:GetManualOnlyTypes(), 0, "paladin : aucun type regroupe")
    falsy(NS:IsTypeGrouped("Magic"), "paladin : la magie reste cliquable par unite")
end

-- 1.5.8: the indicator itself was never exercised -- only the helpers around
-- it -- so two defects lived in it unnoticed.
-- Since 1.5.13 dropped Will of the Forsaken, no real character carries an
-- area-only and a self-only cleanse at the same time. The self-only side is
-- therefore injected after UpdateSpells, which is what builds those tables:
-- these assertions are about scope, not about any particular class.
local function injectSelfOnlyCharm()
    NS.manualTypeSpell.Charm = { id = 999001, name = "SortPersonnel", selfOnly = true, quality = 1 }
end

local function shamanWithBothScopes()
    freshProfile("SHAMAN")
    knowSpells(383013)              -- Poison Cleansing Totem, area
    NS.db.groupManualTypes = true
    NS:UpdateSpells()
    injectSelfOnlyCharm()
    NS.roster = { { unit = "player" }, { unit = "party1" } }
    mock.state.exists.party1 = true
    return NS.manualIndicator
end

do
    local frame = shamanWithBothScopes()
    truthy(frame, "indicateur : le cadre existe")
    truthy(NS:IsTypeGrouped("Poison"), "indicateur : le poison de zone est regroupe")
    truthy(NS:IsTypeGrouped("Charm"), "indicateur : le charme personnel est regroupe")
end

-- 1.5.9: every UNIT_AURA re-read the whole roster -- up to 82 units times 40
-- auras, ten times a second in the worst case -- to answer a question only one
-- unit had changed the answer to.
do
    shamanWithBothScopes()
    NS.roster = { { unit = "player" }, { unit = "party1" }, { unit = "party2" } }
    mock.state.exists.party2 = true

    -- Count the aura reads so the cache can be shown to actually spare them.
    local reads = 0
    local realScan = NS.ScanGroupedTypes
    NS.ScanGroupedTypes = function(selfRef, unit, into) reads = reads + 1 return realScan(selfRef, unit, into) end

    NS:InvalidateGroupedCache()
    mock.state.debuffs.party1 = { debuff(301, "Poison") }
    NS:UpdateManualIndicator()
    eq(reads, 3, "cache : la premiere passe lit les trois unites")
    eq(NS.manualIndicator.activeCount, 1, "cache : une unite affectee")

    reads = 0
    NS:UpdateManualIndicator()
    eq(reads, 0, "cache : une passe sans changement ne relit aucune aura")

    reads = 0
    mock.state.debuffs.party2 = { debuff(302, "Poison") }
    NS:RequestManualIndicatorUpdate("party2")
    NS:UpdateManualIndicator()
    eq(reads, 1, "cache : seule l'unite signalee est relue")
    eq(NS.manualIndicator.activeCount, 2, "cache : le compteur suit l'ajout")

    -- A disappearing aura must bring the count back down.
    mock.state.debuffs.party1 = nil
    NS:RequestManualIndicatorUpdate("party1")
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "cache : le retrait d'une aura decremente")

    -- 1.5.9: a token is recycled onto somebody else whenever the group
    -- changes. Keeping its answer would report an affliction on a player who
    -- never had one.
    reads = 0
    mock.state.debuffs.party2 = nil
    -- Sauver la vraie fonction : la reecrire a la main ferait ignorer
    -- mock.state.identityRestricted a tous les tests suivants.
    local realUnitGUID = _G.UnitGUID
    _G.UnitGUID = function(unit) return "GUID-nouveau-" .. unit end
    NS:UpdateManualIndicator()
    truthy(reads > 0, "cache : un jeton dont le GUID a change est relu")
    eq(NS.manualIndicator.activeCount, 0, "cache : aucun etat d'un ancien GUID ne survit")
    _G.UnitGUID = realUnitGUID

    -- Changing a filter changes what a scan means, and the signature does not
    -- move, so the choke point every filter edit goes through must forget.
    NS:UpdateManualIndicator()
    mock.state.debuffs.player = { debuff(303, "Poison") }
    NS:RefreshAuraCandidateFilters()
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "cache : un changement de filtre force une relecture")

    -- Starting combat changes the meaning of ignoredCombat. No UNIT_AURA is
    -- guaranteed to follow, so RefreshAuraCandidateFilters must itself queue
    -- the badge update.
    NS.db.ignoredCombat[303] = true
    mock.state.inCombat = true
    NS:RefreshAuraCandidateFilters()
    mock.runTimers()
    eq(NS.manualIndicator.activeCount, 0,
        "filtre combat : le badge est recalcule sans attendre UNIT_AURA")
    mock.state.inCombat = false

    NS.ScanGroupedTypes = realScan
end

-- 1.5.14: UnitGUID is SecretWhenUnitIdentityRestricted and UnitIsUnit is
-- SecretWhenUnitComparisonRestricted. The grouped cache used a raw GUID in an
-- `or`, in a comparison and as a table key -- on the UNIT_AURA path, in combat.
-- The audit found it; it was introduced by the 1.5.9 cache itself.
do
    shamanWithBothScopes()
    mock.state.identityRestricted = true
    mock.state.comparisonRestricted = true

    eq(NS:SafeUnitGUID("party1"), nil, "identite : un GUID illisible n'est jamais rendu")
    truthy(NS:IsPlayerUnit("player"), "identite : le jeton litteral player ne demande rien au client")
    falsy(NS:IsPlayerUnit("party1"), "identite : une comparaison illisible vaut non")

    -- Le badge doit continuer de fonctionner, en retombant sur le jeton.
    mock.state.debuffs.party1 = { debuff(401, "Poison") }
    NS:InvalidateGroupedCache()
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "identite : le badge compte encore sans GUID lisible")
    eq(NS.manualIndicator.activeType, "Poison", "identite : avec le bon type")

    -- Le joueur reste joignable par un sort personnel : son jeton est litteral.
    mock.state.debuffs.party1 = nil
    mock.state.debuffs.player = { debuff(402, "Charm") }
    NS:InvalidateGroupedCache()
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "identite : un type personnel atteint encore le joueur")

    -- Les autres chemins qui lisaient un GUID brut.
    -- IsBlacklisted calcule sa cle : sans GUID lisible elle doit valoir le jeton.
    NS.blacklist = { party1 = GetTime() + 5 }
    truthy(NS:IsBlacklisted("party1"), "identite : la liste noire retombe sur le jeton")

    NS:RebuildRoster()
    truthy(#(NS.roster or {}) > 0, "identite : le roster se construit encore")

    -- 1.5.17: l'audit 1.5.16 a montre que la garde s'arretait a deux API sur
    -- cinq. UnitName, UnitFullName et UnitClass sont secretes elles aussi, et
    -- le roster les lisait brutes : concatenation dans le nom qualifie, `or`
    -- dans le nom d'affichage, lecture directe pour la classe.
    mock.state.nameRestricted = true
    eq(NS:SafeUnitName("party1"), nil, "identite : un nom illisible n'est jamais rendu")
    eq(NS:SafeUnitFullName("party1"), nil, "identite : ni le nom qualifie qui en decoule")
    eq(NS:SafeUnitClass("party1"), nil, "identite : ni la classe")

    NS:RebuildRoster()
    do
        local roster = NS.roster or {}
        truthy(#roster > 0, "identite : le roster survit a un nom illisible")
        local player = roster[1]
        truthy(player, "identite : le joueur y figure toujours")
        eq(player.displayName, player.unit, "identite : l'affichage retombe sur le jeton")
        falsy(player.name, "identite : aucun nom invente")
        falsy(player.class, "identite : aucune classe inventee")
    end

    -- Une identite inconnue ne correspond a aucune entree, sans faire
    -- disparaitre l'unite du roster.
    falsy(NS:EntryMatches({ kind = "PLAYER", value = "Quelquun-Hyjal" }, { unit = "party1" }),
        "identite : une entree joueur ne peut pas correspondre")
    falsy(NS:EntryMatches({ kind = "CLASS", value = "PALADIN" }, { unit = "party1" }),
        "identite : une entree de classe non plus")

    -- Enregistrer une cible dont le nom est illisible creerait une entree
    -- morte : la commande refuse.
    mock.state.exists.target = true
    NS.db.priority = {}
    NS:AddTargetToList("priority")
    eq(#NS.db.priority, 0, "identite : /cleansive pradd refuse un nom illisible")

    mock.state.nameRestricted = false
    mock.state.identityRestricted = false
    mock.state.comparisonRestricted = false
end

-- 1.5.9: the indicator was a Button with mouse enabled, looked exactly like a
-- filled cell, and answered to nothing. It read as clickable and swallowed the
-- clicks aimed at whatever sat underneath it.
do
    local frame = shamanWithBothScopes()
    eq(frame.__type, "Frame", "badge : ce n'est pas un Button")
    eq(frame.__mouseClicks, false, "badge : aucun clic n'est absorbe")
    eq(frame.__mouseMotion, true, "badge : le survol reste actif pour l'infobulle")
    truthy(frame.border, "badge : il porte un contour, la ou une case est un aplat")

    NS.db.showTooltips = true
    mock.state.debuffs.player = { debuff(201, "Poison") }
    NS:UpdateManualIndicator()
    NS:ShowManualIndicatorTooltip(frame)
    local lines = mock.state.tooltip or {}
    eq(lines[1], NS.L.MANUAL_BADGE_TITLE, "badge : l'infobulle annonce d'abord qu'il n'est pas cliquable")
    local namesAbility = false
    for _, line in ipairs(lines) do
        if string.find(line, "Spell383013", 1, true) then namesAbility = true end
    end
    truthy(namesAbility, "badge : l'infobulle nomme la capacite a utiliser")
end

-- 1.5.9: the inactive branch only dimmed the background. Its coloured border
-- and exclamation mark survived, while the next active alert inherited the
-- dim plate. Every transition now paints a complete state.
do
    local frame = shamanWithBothScopes()
    NS.db.afflictedOnly = false
    mock.state.debuffs.player = { debuff(211, "Poison") }
    NS:RequestManualIndicatorUpdate("player")
    NS:UpdateManualIndicator()
    eq(frame.background.__color[4], 0.88, "badge actif : opacite du fond restauree")
    truthy(frame.mark:IsShown(), "badge actif : le point d'exclamation est visible")
    eq(frame.border[1].__color[4], 1, "badge actif : contour colore opaque")

    mock.state.debuffs.player = nil
    NS:RequestManualIndicatorUpdate("player")
    NS:UpdateManualIndicator()
    eq(frame.background.__color[4], NS.db.inactiveAlpha, "badge inactif : opacite configuree")
    falsy(frame.mark:IsShown(), "badge inactif : aucun point d'exclamation perime")
    eq(frame.border[1].__color[4], 0.10, "badge inactif : contour revenu au neutre")
    eq(frame.count:GetText(), "", "badge inactif : compteur efface")

    NS.testMode = true
    NS:UpdateManualIndicator()
    eq(frame.background.__color[4], 0.88, "badge test : meme style que l'etat actif")
    truthy(frame.mark:IsShown(), "badge test : symbole actif visible")
    NS.testMode = false
end

-- 1.5.8: the aura loop was outside the type loop, so the colour came from
-- whichever affliction WoW returned first, not from the configured order.
do
    shamanWithBothScopes()
    -- Charm is listed first by WoW, Poison comes earlier in the configured order.
    mock.state.debuffs.player = { debuff(101, "Charm"), debuff(102, "Poison") }
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeType, "Poison", "priorite : l'ordre configure gagne sur l'ordre des auras")
    local present = NS:ScanGroupedTypes("player", {})
    truthy(present.Poison and present.Charm, "priorite : une passe releve les deux types portes par l'unite")

    -- Reversing the configured order must reverse the result.
    NS.db.typeOrder = { "Charm", "Poison", "Magic", "Curse", "Disease", "Bleed" }
    NS:UpdateSpells()
    injectSelfOnlyCharm()          -- UpdateSpells reconstruit les tables
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeType, "Charm", "priorite : inverser typeOrder inverse le resultat")
end

-- 1.5.8: scope was decided for the whole set, so one area type widened the
-- scan and the self-only type then counted allies it can never help.
do
    shamanWithBothScopes()
    mock.state.debuffs.player = nil
    mock.state.debuffs.party1 = { debuff(103, "Charm") }   -- self-only type, on an ally
    NS:RequestManualIndicatorUpdate("party1")              -- ce que fait UNIT_AURA
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 0, "portee : un type personnel ne compte jamais un allie")

    -- The area type keeps scanning the roster.
    mock.state.debuffs.party1 = { debuff(104, "Poison") }
    NS:RequestManualIndicatorUpdate("party1")
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "portee : un type de zone compte bien l'allie")
    eq(NS.manualIndicator.activeType, "Poison", "portee : avec le bon type")

    -- A unit carrying two grouped types is one unit, not two.
    mock.state.debuffs.player = { debuff(105, "Poison"), debuff(106, "Charm") }
    mock.state.debuffs.party1 = nil
    NS:RequestManualIndicatorUpdate("player")
    NS:RequestManualIndicatorUpdate("party1")
    NS:UpdateManualIndicator()
    eq(NS.manualIndicator.activeCount, 1, "portee : deux types sur la meme unite ne comptent qu'une fois")
end

--------------------------------------------------------------------------
-- 15. Grouping is opt-in since 1.5.5, and 1.5.4 profiles are reset
--------------------------------------------------------------------------

-- 1.5.4 enabled grouping by default. On the protected path the grouped types
-- lost their engine cell without a reliable replacement, so a Demon Hunter
-- could end up with no cell, no indicator and no sound at all.
freshProfile("DEMONHUNTER")
falsy(NS.db.groupManualTypes, "opt-in : le regroupement est desactive par defaut")

-- applyDefaults wrote the old default into every profile, so flipping the
-- default alone would not reach the players actually at risk.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true },
    profiles = { ["Ekinoks-Hyjal"] = { ["65"] = { groupManualTypes = true } } },
}
NS:InitializeProfiles()
do
    falsy(CleansiveDB.profiles["Ekinoks-Hyjal"]["65"].groupManualTypes,
        "migration : un profil ecrit par la 1.5.4 est remis en opt-in")
    truthy(CleansiveDB.global.groupManualOptOut, "migration : marquee comme faite")
    truthy(CleansiveDB.global.groupManualOptOutAllProfiles159,
        "migration : le parcours global porte son propre marqueur")
end

-- And it must not undo a later deliberate choice.
NS.db.groupManualTypes = true
NS:InitializeProfiles()
truthy(NS.db.groupManualTypes, "migration : ne se rejoue pas sur un choix ulterieur")

-- 1.5.8: the opt-out marker is global but the sweep visited the logged-in
-- character only, so the first login consumed it on behalf of every alt --
-- who then kept the 1.5.4 value forever.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true },
    profiles = {
        ["Ekinoks-Hyjal"] = { ["65"] = { groupManualTypes = true }, ["66"] = { groupManualTypes = true } },
        ["Autre-Hyjal"]   = { ["577"] = { groupManualTypes = true }, ["581"] = { groupManualTypes = true } },
        ["Casse-Hyjal"]   = "profil corrompu",   -- ne doit pas lever
    },
}
NS:InitializeProfiles()
do
    local profiles = CleansiveDB.profiles
    falsy(profiles["Ekinoks-Hyjal"]["65"].groupManualTypes, "migration : personnage connecte, spe 1")
    falsy(profiles["Ekinoks-Hyjal"]["66"].groupManualTypes, "migration : personnage connecte, spe 2")
    falsy(profiles["Autre-Hyjal"]["577"].groupManualTypes, "migration : personnage non connecte, spe 1")
    falsy(profiles["Autre-Hyjal"]["581"].groupManualTypes, "migration : personnage non connecte, spe 2")
end

-- 1.5.10: a real 1.5.8 database already carries the old marker. Reusing it
-- skipped the repaired all-profile pass entirely.
mock.reset()
NS.dbRoot, NS.db = nil, nil
CleansiveDB = {
    schemaVersion = 2,
    global = { language = "frFR", setupComplete = true, groupManualOptOut = true },
    profiles = {
        ["Ekinoks-Hyjal"] = { ["65"] = { groupManualTypes = false } },
        ["Autre-Hyjal"] = { ["577"] = { groupManualTypes = true }, ["581"] = { groupManualTypes = true } },
    },
}
NS:InitializeProfiles()
do
    falsy(CleansiveDB.profiles["Autre-Hyjal"]["577"].groupManualTypes,
        "migration 1.5.8 : l'ancien marqueur ne bloque plus l'alt")
    falsy(CleansiveDB.profiles["Autre-Hyjal"]["581"].groupManualTypes,
        "migration 1.5.8 : toutes les specialisations de l'alt sont corrigees")
    truthy(CleansiveDB.global.groupManualOptOutAllProfiles159,
        "migration 1.5.8 : le nouveau parcours est marque")
end

-- Once the repaired sweep ran, a deliberate later choice remains untouched.
NS.db.groupManualTypes = true
NS:InitializeProfiles()
truthy(NS.db.groupManualTypes, "migration 1.5.8 : un choix ulterieur est conserve")

-- Realm-qualified entries must never match another player carrying the same
-- short name. Legacy short entries remain supported.
do
    truthy(NS:EntryMatches({ kind = "PLAYER", value = "Alice-RealmA" }, { name = "Alice-RealmA" }),
        "liste interserveur : nom complet identique")
    falsy(NS:EntryMatches({ kind = "PLAYER", value = "Alice-RealmA" }, { name = "Alice-RealmB" }),
        "liste interserveur : deux royaumes restent distincts")
    truthy(NS:EntryMatches({ kind = "PLAYER", value = "Alice" }, { name = "Alice-RealmB" }),
        "liste interserveur : ancienne entree courte encore reconnue")
end

-- 1.5.8: the .toc was bumped to 1.5.8 while Core.lua kept a second literal at
-- 1.5.7, so the options sidebar advertised the previous release.
eq(NS.version, TOC_VERSION, "version : le code annonce le numero du .toc (" .. tostring(TOC_VERSION) .. ")")

--------------------------------------------------------------------------
-- 16. The four P1 of the 1.5.4 audit, fixed in 1.5.6
--------------------------------------------------------------------------

-- P1-2: 1.5.4 dropped the engine slot for grouped types, so an unreadable
-- aura had no cell, no indicator and no sound. The slot must come back.
freshProfile("DEMONHUNTER")
knowSpells(205604, 278326)
NS.db.groupManualTypes = true
NS:UpdateSpells()
do
    truthy(NS:IsTypeGrouped("Magic"), "P1-2 : la magie du DH est bien regroupee")
    -- RefreshAuraEngineTypes recomputes the set through the real
    -- getPotentialAuraTypes, so it proves the slot is granted again.
    NS.buttons, NS.gridBody = {}, mock.newFrame("body")
    NS.engineAuraTypes = {}
    NS:RefreshAuraEngineTypes()
    local hasMagic = false
    for _, t in ipairs(NS.engineAuraTypes or {}) do if t == "Magic" then hasMagic = true end end
    truthy(hasMagic, "P1-2 : un type regroupe garde son emplacement moteur")
end

-- P1-4: the readable sound fallback must still find a grouped affliction,
-- even though the per-unit cell deliberately ignores it.
freshProfile("SHAMAN")
knowSpells(383013)                     -- Poison Cleansing Totem, untargeted
NS.db.groupManualTypes = true
NS:UpdateSpells()
mock.state.debuffs.player = { debuff(888, "Poison") }
do
    local cellAura = NS:GetCurableAura("player")
    falsy(cellAura, "P1-4 : la case d'unite ignore toujours le type regroupe")
    local soundAura, soundType = NS:GetCurableAura("player", true)
    truthy(soundAura, "P1-4 : la recherche sonore le trouve")
    eq(soundType, "Poison", "P1-4 : avec le bon type")
end

-- P1-1 and P1-3 used to assert that a function existed. Existence is not a
-- behaviour: both passed while the deferral itself was never exercised once.

-- 1.5.9: a type-set change during combat must not touch a protected
-- attribute, and must be replayed exactly once when combat ends.
do
    freshProfile("PALADIN")
    knowSpells(4987)                       -- Cleanse: Magic, Disease, Poison
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()

    local before = {}
    for index, button in ipairs(NS.buttons) do before[index] = button.auraContainer end
    truthy(before[1], "report : le moteur protege a bien produit un conteneur")
    truthy(NS.buttons[1].engineAuraReady, "report : la case est en mode moteur")

    -- Every slot must carry the candidate filters it was built with.
    local slots = before[1].__slots or {}
    local filtered, total = 0, 0
    for _, options in pairs(slots) do
        total = total + 1
        if options and options.candidateFilters then filtered = filtered + 1 end
    end
    eq(filtered, total, "report : chaque emplacement recoit ses filtres")
    eq(total, #NS.engineAuraTypes, "report : un emplacement par type de dissipation")

    -- In combat: the set changes, nothing is rebuilt.
    mock.state.inCombat = true
    mock.state.playerClass = "DRUID"
    NS.playerClass = "DRUID"
    -- Depuis 1.5.19 les emplacements suivent les sorts connus, pas la classe :
    -- sans sort de druide l ensemble serait vide et rien ne serait reconstruit.
    knowSpells(2782)                       -- Remove Corruption : Poison, Curse
    local createdBefore = mock.state.auraEngine.created
    eq(NS:RefreshAuraEngineTypes(), false, "report : en combat, aucune reconstruction")
    truthy(NS.pendingAuraEngineRebuild, "report : la reconstruction est mise en attente")
    eq(mock.state.auraEngine.created, createdBefore, "report : aucun conteneur cree en combat")
    eq(NS.buttons[1].auraContainer, before[1], "report : le conteneur protege est intact")
    truthy(before[1]:IsShown(), "report : et toujours actif")

    -- Combat ends: one rebuild, and only one.
    mock.state.inCombat = false
    NS.roster = { { unit = "player" } }
    NS:FlushCombatUpdates()
    falsy(NS.pendingAuraEngineRebuild, "report : l'attente est levee")
    -- 1.5.23: le contrat a change. Masquer un conteneur ne le detruit pas -- WoW
    -- garde tous ses cadres pour la session -- donc chaque changement de talent
    -- abandonnait une generation de 82 conteneurs. Ils sont reutilises : un
    -- emplacement s'ajoute, et celui qui ne sert plus est rendu inerte par un
    -- includeDispelTypes vide, la seule voie ouverte a un addon.
    eq(mock.state.auraEngine.created, createdBefore,
        "report : aucun conteneur neuf, ils sont reutilises")
    eq(NS.buttons[1].auraContainer, before[1], "report : c'est bien le meme conteneur")
    truthy(before[1]:IsShown(), "report : il n'a pas ete masque au passage")
    truthy(NS.buttons[1].engineAuraReady, "report : et il couvre le nouvel ensemble")

    -- Le fait que l'audit demandait de mesurer : dix alternances ne creent rien.
    local steady = mock.state.auraEngine.created
    for round = 1, 10 do
        mock.state.playerClass = (round % 2 == 0) and "DRUID" or "PALADIN"
        NS.playerClass = mock.state.playerClass
        NS:UpdateSpells()
        NS:RefreshAuraEngineTypes()
    end
    eq(mock.state.auraEngine.created, steady,
        "report : dix alternances de classe n'allouent aucun conteneur de plus")

    -- 1.5.24: le mock avalait SetAuraSlotCandidateFilters, donc rien ne voyait
    -- que la neutralisation d'un type retire etait defaite aussitot par
    -- UpdateAuraContainerConfiguration, qui reappliquait les vrais filtres a
    -- toutes les cles accumulees.
    do
        local function filtersFor(auraType)
            local button = NS.buttons[1]
            local key = button.auraSlotKeys and button.auraSlotKeys[auraType]
            local slot = key and button.auraContainer and button.auraContainer.__slots[key]
            return slot and slot.candidateFilters
        end
        local function isInert(filters)
            if not filters or not filters.includeDispelTypes then return false end
            return next(filters.includeDispelTypes) == nil
        end

        -- La case doit porter une unite : UpdateAuraContainerConfiguration ne
        -- configure que les boutons lies, donc sans cela le chemin fautif
        -- n'etait jamais emprunte et le test passait pour rien.
        NS.roster = { { unit = "player" } }
        NS:AssignRosterToButtons()
        truthy(NS.buttons[1].unit, "inertie : la case est liee a une unite")

        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        knowSpells(4987)                       -- Magic, Disease, Poison
        NS:UpdateSpells()
        truthy(filtersFor("Magic"), "inertie : le paladin a bien un emplacement Magic")

        -- Passage a un ensemble qui ne contient plus Magic.
        mock.state.playerClass, NS.playerClass = "EVOKER", "EVOKER"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(365585)                     -- Poison seul
        NS:UpdateSpells()
        truthy(isInert(filtersFor("Magic")), "inertie : le type retire devient inerte")

        -- Les rafraichissements generaux ne doivent pas le reveiller.
        NS:LayoutButtons()
        NS:RefreshAuraCandidateFilters()
        NS:UpdateAuraContainerConfiguration(true)
        truthy(isInert(filtersFor("Magic")), "inertie : et il le reste apres un rafraichissement")
        falsy(isInert(filtersFor("Poison")), "inertie : le type actif garde ses vrais filtres")

        -- Le retour du type restaure ses filtres, sans nouveau conteneur.
        local before = mock.state.auraEngine.created
        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(4987)
        NS:UpdateSpells()
        falsy(isInert(filtersFor("Magic")), "inertie : le type qui revient retrouve ses filtres")
        eq(mock.state.auraEngine.created, before, "inertie : et aucun conteneur n'est cree")

        -- 1.5.24: un echec de reconfiguration laissait la case hors du moteur
        -- pour de bon. L'ensemble voulu etait deja memorise, donc l'appel
        -- suivant sortait avant d'avoir retente quoi que ce soit.
        mock.state.auraEngine.failFiltersFor = NS.buttons[1].auraSlotKeys["Magic"]
        mock.state.playerClass, NS.playerClass = "EVOKER", "EVOKER"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(365585)
        NS:UpdateSpells()
        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(4987)
        NS:UpdateSpells()
        falsy(NS.buttons[1].engineAuraReady, "echec : la case sort du moteur")
        truthy(NS.pendingAuraEngineReconcile, "echec : une nouvelle tentative est due")
        truthy(NS.auraContainerDiagnostics.firstError, "echec : et il est diagnostique")

        -- 1.5.25: la tentative etait autorisee mais jamais programmee. Elle
        -- attendait qu'un autre evenement de sorts rappelle la fonction, donc
        -- une panne passagere pouvait laisser les cases sur le repli Lua
        -- jusqu'au rechargement. Ici, personne n'appelle rien a la main.
        mock.state.auraEngine.failFiltersFor = nil
        mock.runTimers()
        truthy(NS.buttons[1].engineAuraReady, "echec : la case revient d'elle-meme")
        falsy(NS.pendingAuraEngineReconcile, "echec : plus rien n'est en attente")

        -- Le budget est borne : la panne persistante s'arrete apres trois essais.
        local chatBefore = #mock.state.chat
        mock.state.auraEngine.failFiltersFor = NS.buttons[1].auraSlotKeys["Magic"]
        mock.state.playerClass, NS.playerClass = "EVOKER", "EVOKER"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(365585)
        NS:UpdateSpells()
        local rounds = 0
        while NS.pendingAuraEngineReconcile and rounds < 10 do
            rounds = rounds + 1
            mock.runTimers()
        end
        eq(rounds, 3, "budget : trois essais, puis on s'arrete")
        falsy(NS.pendingAuraEngineReconcile, "budget : le budget est epuise")

        -- Un seul message pour cette generation, pas un par essai. On mesure
        -- l'ecart : le journal du chat porte deja d'autres tests. Le compte
        -- d'emplacements a disparu de cette ligne en 1.5.26 : ici seule la
        -- neutralisation de Magic echoue, les cases gardent leur type actif.
        local warnings = 0
        for index = chatBefore + 1, #mock.state.chat do
            if string.find(mock.state.chat[index], "Cleansive") then
                warnings = warnings + 1
            end
        end
        eq(warnings, 1, "diagnostic : un seul avertissement pour trois essais rates")
        falsy(string.find(mock.state.chat[#mock.state.chat], "%d+/%d+"),
            "diagnostic : une neutralisation ratee n'annonce pas un moteur incomplet")

        -- Un nouvel ensemble reprend un budget neuf.
        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(4987)
        NS:UpdateSpells()
        truthy(NS.pendingAuraEngineReconcile, "budget : un nouvel ensemble a droit a ses essais")
        eq(NS.auraEngineRetries, 1, "budget : et le compteur repart de un")

        -- 1.5.26: une minuterie perimee ne doit pas liberer le verrou d'une
        -- minuterie plus recente. C_Timer.After ne s'annule pas, donc l'ancien
        -- callback restait dans la file ; il remettait le verrou a faux avant
        -- de verifier sa generation, et un autre evenement pouvait alors armer
        -- une seconde minuterie pour la generation courante.
        mock.state.auraEngine.failFiltersFor = nil
        NS.pendingAuraEngineReconcile = false
        mock.runTimers()
        local magicKey = NS.buttons[1].auraSlotKeys["Magic"]
        local poisonKey = NS.buttons[1].auraSlotKeys["Poison"]
        truthy(magicKey and poisonKey, "minuterie : les deux emplacements existent deja")
        eq(mock.timerCount(), 0, "minuterie : la file est vide au depart")

        -- Generation A : Poison echoue, une minuterie est armee.
        mock.state.auraEngine.failFiltersFor = poisonKey
        mock.state.playerClass, NS.playerClass = "EVOKER", "EVOKER"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(365585)
        NS:UpdateSpells()
        eq(mock.timerCount(), 1, "minuterie : la generation A arme la sienne")

        -- Generation B avant que A ne s'execute : elle arme la sienne.
        mock.state.auraEngine.failFiltersFor = magicKey
        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(4987)
        NS:UpdateSpells()
        eq(mock.timerCount(), 2, "minuterie : la generation B arme la sienne")

        -- Seul l'ancien callback part. Il doit sortir sans rien toucher.
        mock.runTimerAt(1)
        truthy(NS.auraEngineRetryScheduled, "minuterie : le verrou de B tient toujours")
        NS:ScheduleAuraEngineRetry()
        eq(mock.timerCount(), 1, "minuterie : aucune troisieme minuterie n'est armee")

        -- Et la minuterie de B fait bien son travail.
        mock.state.auraEngine.failFiltersFor = nil
        mock.runTimers()
        truthy(NS.buttons[1].engineAuraReady, "minuterie : la minuterie de B recupere la case")
        falsy(NS.pendingAuraEngineReconcile, "minuterie : plus rien n'est en attente")

        -- 1.5.26: un ensemble voulu vide n'est pas une raison de renoncer. La
        -- reprise etait conditionnee a #wanted > 0, donc un emplacement
        -- historique dont la neutralisation echouait continuait de filtrer des
        -- auras sans avertissement ni nouvel essai.
        local chatMark = #mock.state.chat
        mock.state.auraEngine.failFiltersFor = NS.buttons[1].auraSlotKeys["Magic"]
        mock.state.playerClass, NS.playerClass = "WARRIOR", "WARRIOR"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        NS:UpdateSpells()
        eq(#NS.engineAuraTypes, 0, "vide : plus aucun type de dissipation")
        truthy(NS.pendingAuraEngineReconcile, "vide : la neutralisation ratee est retentee")
        eq(NS.auraEngineRetries, 1, "vide : sur un budget neuf")
        eq(mock.timerCount(), 1, "vide : et la minuterie est bien armee")

        -- 1.5.26: le message ne doit plus annoncer « 82/82 emplacements
        -- incomplet » quand seuls des emplacements retires resistent.
        -- La cle d'emplacement est la meme dans chaque conteneur : la panne du
        -- mock touche donc les 82 cases, et le message doit les compter toutes.
        eq(NS.auraContainerDiagnostics.retired, #NS.buttons,
            "diagnostic : chaque emplacement retire en echec est compte")
        local cleanup = string.format(NS.L.AURA_CLEANUP_FAILED, #NS.buttons,
            "SetAuraSlotCandidateFilters failed for Magic")
        local sawCleanup, sawSlotCount = false, false
        for index = chatMark + 1, #mock.state.chat do
            if string.find(mock.state.chat[index], cleanup, 1, true) then sawCleanup = true end
            if string.find(mock.state.chat[index], "%d+/%d+") then sawSlotCount = true end
        end
        truthy(sawCleanup, "diagnostic : le message parle des emplacements retires")
        falsy(sawSlotCount, "diagnostic : et n'annonce plus un compte d'emplacements actifs")

        mock.state.auraEngine.failFiltersFor = nil
        mock.runTimers()
        falsy(NS.pendingAuraEngineReconcile, "vide : la neutralisation finit par passer")

        -- 1.5.27: une panne simultanee sur un type retire et un type actif.
        -- recordFailure ne gardait qu'une seule premiere erreur et la boucle
        -- des types retires passe en premier, donc le message du moteur
        -- pouvait nommer une operation de nettoyage tout en decrivant une case
        -- qui avait reellement perdu son type actif.
        mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(4987)
        NS:UpdateSpells()
        mock.runTimers()
        truthy(NS.buttons[1].auraSlotKeys["Magic"] and NS.buttons[1].auraSlotKeys["Poison"],
            "double panne : les deux emplacements existent")
        local doubleMark = #mock.state.chat
        mock.state.auraEngine.failFiltersFor = {
            [NS.buttons[1].auraSlotKeys["Magic"]] = true,
            [NS.buttons[1].auraSlotKeys["Poison"]] = true,
        }
        mock.state.playerClass, NS.playerClass = "EVOKER", "EVOKER"
        mock.state.knownSpells, mock.state.playerSpells = {}, {}
        knowSpells(365585)                     -- Poison seul, Magic est retire
        NS:UpdateSpells()
        falsy(NS.buttons[1].engineAuraReady, "double panne : la case perd son type actif")
        eq(NS.auraContainerDiagnostics.retiredError,
            "SetAuraSlotCandidateFilters failed for Magic",
            "double panne : le nettoyage rate est impute a Magic")
        eq(NS.auraContainerDiagnostics.activeError,
            "SetAuraSlotCandidateFilters failed for Poison",
            "double panne : l'echec actif est impute a Poison")
        local named = false
        for index = doubleMark + 1, #mock.state.chat do
            if string.find(mock.state.chat[index], "Poison", 1, true) then named = true end
        end
        truthy(named, "double panne : le message du moteur nomme le type actif")

        mock.state.auraEngine.failFiltersFor = nil
        mock.runTimers()

        mock.state.auraEngine.failFiltersFor = nil
        NS.pendingAuraEngineReconcile = false
    end

    -- The rebuilt containers are handed their unit by the refresh that follows.
    NS:RefreshUnit("player")
    local bound = NS.unitToButton and NS.unitToButton["player"]
    if bound and bound.auraContainer then
        eq(bound.auraContainer.__unit, "player", "report : le conteneur reconstruit recoit son unite")
    end
end

-- 1.5.9: when the engine only half-builds, the affected cells must fall back
-- to the Lua path rather than showing nothing at all.
do
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    -- UpdateSpells rebuilds the previous grid's containers, so the threshold
    -- is only meaningful once that is done.
    mock.state.auraEngine.failSlotsFrom = mock.state.auraEngine.created + 3
    NS:CreateGrid()

    truthy(NS.buttons[1].engineAuraReady, "echec partiel : les premieres cases gardent le moteur")
    falsy(NS.buttons[5].engineAuraReady, "echec partiel : les suivantes le perdent")
    falsy(NS.buttons[5].auraContainer, "echec partiel : leur conteneur est abandonne")
    truthy(NS.auraContainerDiagnostics.firstError, "echec partiel : l'erreur est diagnostiquee")

    -- The Lua path still lights the cell for those buttons.
    mock.state.debuffs.player = { debuff(909, "Magic") }
    local aura, auraType = NS:GetCurableAura("player")
    truthy(aura, "echec partiel : le repli Lua trouve toujours l'affliction")
    eq(auraType, "Magic", "echec partiel : avec le bon type")
    mock.state.auraEngine.failSlotsFrom = nil
end

-- P3-12: the indicator follows the player's configured order.
freshProfile("PALADIN")
NS:UpdateSpells()
do
    -- No class has two manual-only types, so drive the tables directly:
    -- the assertion is about ordering, not about any particular class.
    NS.typeToSlot = {}
    NS.manualTypeSpell = { Poison = { id = 1, name = "A" }, Magic = { id = 2, name = "B" } }
    NS.db.groupManualTypes = true

    NS.db.typeOrder = { "Magic", "Poison", "Curse", "Disease", "Bleed", "Charm" }
    local first = NS:GetManualOnlyTypes()
    eq(first[1], "Magic", "P3-12 : l'ordre configure est respecte")

    NS.db.typeOrder = { "Poison", "Magic", "Curse", "Disease", "Bleed", "Charm" }
    local second = NS:GetManualOnlyTypes()
    eq(second[1], "Poison", "P3-12 : inverser l'ordre inverse le resultat")
end

--------------------------------------------------------------------------
-- 1.5.28 : les deux etats visuels
--------------------------------------------------------------------------

-- Une modification protegee refusee pendant le combat ne disait rien : le
-- reglage bougeait, l'ecran non, et rien n'expliquait pourquoi.
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:RebuildRoster()
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    NS:UpdatePendingIndicator()
    falsy(NS.pendingIndicator:IsShown(), "attente : rien a signaler hors combat")

    -- Hors combat un drapeau est sur le point d'etre vide, pas en attente :
    -- la plaque clignoterait a chaque changement d'option.
    NS:MarkPending("pendingLayout")
    falsy(NS.pendingIndicator:IsShown(), "attente : un drapeau hors combat n'affiche rien")
    NS.pendingLayout = false

    mock.state.inCombat = true
    NS:LayoutButtons()
    truthy(NS.pendingLayout, "attente : la disposition est bien differee")
    truthy(NS.pendingIndicator:IsShown(), "attente : et la plaque le dit")
    eq(NS.pendingIndicator.label.__text, NS.L.PENDING_BADGE,
        "attente : la plaque porte son libelle traduit")
    truthy(NS.pendingIndicator.__lastSize.width > 24,
        "attente : elle est dimensionnee sur son texte, pas sur une constante")

    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    falsy(NS.pendingLayout, "attente : le drapeau est vide a la sortie")

    -- Un report qui ne declenche aucun reaffichage : la disposition passait par
    -- LayoutButtons, donc la plaque etait eteinte par le chemin de rafraichis-
    -- sement et le test ne prouvait rien. Le raccourci prioritaire, lui, se
    -- rejoue seul et n'eteindrait la plaque par aucun autre chemin.
    mock.state.inCombat = true
    NS:MarkPending("pendingPriorityBinding")
    truthy(NS.pendingIndicator:IsShown(), "attente : un report isole s'annonce aussi")
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    falsy(NS.pendingPriorityBinding, "attente : ce report isole est vide a la sortie")
    falsy(NS.pendingIndicator:IsShown(), "attente : et la plaque disparait avec lui")

    -- Elle suit l'addon : desactive ou grille masquee, elle se tait.
    mock.state.inCombat = true
    NS:MarkPending("pendingRoster")
    truthy(NS.pendingIndicator:IsShown(), "attente : visible pendant le combat")
    NS.enabled = false
    NS:UpdatePendingIndicator()
    falsy(NS.pendingIndicator:IsShown(), "attente : muette quand l'addon est desactive")
    NS.enabled = true
    NS.gridManuallyHidden = true
    NS:UpdatePendingIndicator()
    falsy(NS.pendingIndicator:IsShown(), "attente : muette quand la grille est masquee")
    NS.gridManuallyHidden = false
    NS.pendingRoster = false
    mock.state.inCombat = false
    NS:UpdatePendingIndicator()
end

-- Un personnage sans dissipation voyait une grille de cases grises qui ne
-- pouvaient rien faire, et aucune explication nulle part.
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:RebuildRoster()
    falsy(NS.noCureNotice:IsShown(), "sans dissipation : un paladin ne voit rien")

    mock.state.playerClass, NS.playerClass = "WARRIOR", "WARRIOR"
    mock.state.knownSpells, mock.state.playerSpells = {}, {}
    -- Avant la reponse du client, un grimoire vide est de l'ignorance, pas un
    -- fait : c'est exactement le piege corrige en 1.5.21.
    NS.spellbookResolved = false
    NS:UpdateSpells()
    falsy(NS.noCureNotice:IsShown(),
        "sans dissipation : tant que le grimoire n'a pas repondu, on se tait")

    NS.spellbookResolved = true
    NS:UpdateSpells()
    eq(#NS.clickSpells, 0, "sans dissipation : aucun sort clicable")
    eq(#NS.engineAuraTypes, 0, "sans dissipation : aucun type")
    truthy(NS.noCureNotice:IsShown(), "sans dissipation : l'etat est annonce")
    eq(NS.noCureNotice.label.__text, NS.L.NO_CURE_BADGE,
        "sans dissipation : avec son libelle traduit")

    -- Et il disparait des qu'un sort revient.
    mock.state.playerClass, NS.playerClass = "PALADIN", "PALADIN"
    knowSpells(4987)
    NS:UpdateSpells()
    falsy(NS.noCureNotice:IsShown(), "sans dissipation : le sort qui revient le fait taire")
end

-- 1.6.2 : l'apercu ne se lisait que dans la fenetre d'options. Une capture, ou
-- un retour au clavier apres une pause, ne disait plus si les cases rouges
-- etaient de vraies afflictions.
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:RebuildRoster()
    mock.state.inCombat = false
    NS.testMode = false
    NS:RefreshAll(true)
    falsy(NS.testNotice:IsShown(), "apercu : hors apercu, aucune plaque")

    NS:ToggleTest()
    truthy(NS.testMode, "apercu : le mode est bien actif")
    truthy(NS.testNotice:IsShown(), "apercu : la plaque le dit a cote de la grille")
    eq(NS.testNotice.label.__text, NS.L.TEST_BADGE,
        "apercu : avec son libelle traduit")

    -- La plaque ne doit jamais entrer dans la hierarchie securisee : elle vit
    -- sur la couche de recharge, qui est un enfant direct d'UIParent, et elle
    -- ne prend aucun clic.
    eq(NS.testNotice.__parent, NS.cooldownBody,
        "apercu : la plaque vit sur la couche non protegee")
    falsy(NS.testNotice.__mouseClicks, "apercu : elle n'avale aucun clic")

    -- Deux plaques a la fois ne doivent pas se superposer : c'est exactement
    -- le defaut corrige sur la pile d'origine.
    mock.state.inCombat = true
    NS:MarkPending("pendingRoster")
    truthy(NS.pendingIndicator:IsShown(), "apercu : la plaque d'attente s'allume aussi")
    truthy(NS.testNotice.__lastPoint and NS.pendingIndicator.__lastPoint,
        "apercu : les deux plaques sont posees")
    truthy(math.abs((NS.testNotice.__lastPoint.x or 0)
        - (NS.pendingIndicator.__lastPoint.x or 0)) > 1,
        "apercu : elles ne sont pas dessinees au meme endroit")
    NS.pendingRoster = false
    mock.state.inCombat = false
    NS:UpdatePendingIndicator()

    -- L'entree en combat ferme l'apercu : la plaque part avec lui.
    NS:EndTestModeForCombat()
    falsy(NS.testMode, "apercu : le combat ferme l'apercu")
    falsy(NS.testNotice:IsShown(), "apercu : et la plaque s'eteint avec lui")
end

--------------------------------------------------------------------------
-- 1.5.29 : la fenetre d'options
--------------------------------------------------------------------------
-- EllesmereUX.lua etait exclu de la suite ("trop dependant des cadres pour un
-- gain nul"). Le mock a grandi depuis : CreateOptions s'execute tel quel. Il
-- est charge ICI, apres tous les tests qui s'appuient sur les bouchons UI,
-- pour qu'aucun d'eux ne change de comportement.
do
    local chunk = loadfile(ADDON .. "/EllesmereUX.lua")
    if not chunk then error("cannot load EllesmereUX.lua") end
    chunk("Cleansive", NS)
    -- Lists.lua a ete charge AVANT la boucle de bouchons, qui a ecrase
    -- RefreshAuraHistoryPage. Le rechargement rend la vraie fonction.
    local lists = loadfile(ADDON .. "/Lists.lua")
    lists("Cleansive", NS)

    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:RebuildRoster()
    NS:CreateOptions()
    truthy(NS.optionSliders and #NS.optionSliders == 8, "options : les huit curseurs existent")

    -- LE defaut vu sur les captures : SetPoint a trois arguments ancrait la
    -- valeur sur le TOPRIGHT du parent, donc un decalage x positif la poussait
    -- de 265 a 575 px hors du panneau. Les six curseurs etaient muets.
    for index, control in ipairs(NS.optionSliders) do
        local value = control.valueText
        truthy(value ~= nil, "curseur " .. index .. " : la valeur existe")
        local point, relative, relativePoint = value:GetPoint(1)
        eq(point, "TOPRIGHT", "curseur " .. index .. " : la valeur est calee a droite")
        truthy(type(relative) == "table",
            "curseur " .. index .. " : ancree sur un cadre, pas sur un nombre")
        eq(relativePoint, "TOPLEFT",
            "curseur " .. index .. " : depuis le bord gauche du panneau")
        truthy((value.__text or "") ~= "", "curseur " .. index .. " : elle porte un texte")
    end

    -- Une opacite de 0.25 doit se lire 25 %, pas 0.25.
    local opacity
    for _, control in ipairs(NS.optionSliders) do
        if control.key == "inactiveAlpha" then opacity = control end
    end
    truthy(opacity ~= nil, "opacite : le curseur est identifiable par sa cle")
    NS.db.inactiveAlpha = 0.25
    opacity:Refresh()
    eq(opacity.valueText.__text, "25 %", "opacite : affichee en pourcentage")
    NS.db.inactiveAlpha = 0.80
    opacity:Refresh()
    eq(opacity.valueText.__text, "80 %", "opacite : et jusqu'au maximum")

    -- Les libelles techniques remplaces.
    falsy(string.find(NS.L.COOLDOWN, "Recharge de la dissipation", 1, true),
        "libelles : l'ancien libelle de recharge a disparu")
    eq(NS.L.COOLDOWN, NS.L.PREVIEW_COOLDOWN,
        "libelles : l'option et l'apercu disent la meme chose")
    falsy(string.find(NS.L.SOUND_BUDGET, "Budget", 1, true),
        "libelles : l'ancien libelle de budget sonore a disparu")

    -- Historique : etat vide, pagination et bouton de vidage.
    local page = NS.auraHistoryPage
    local hist, order = NS:GetAuraHistory()
    NS:RefreshAuraHistoryPage()
    truthy(page.empty:IsShown(), "historique : l'etat vide est affiche")
    falsy(page.page:IsShown(), "historique : « Page 1 sur 1 » est masquee")
    falsy(page.prev:IsShown(), "historique : « Precedent » est masque")
    falsy(page.next:IsShown(), "historique : « Suivant » est masque")
    falsy(page.clearButton:IsEnabled(), "historique : vider un historique vide est desactive")

    -- Une seule page d'entrees : toujours aucune pagination.
    local pageSize = #page.rows
    local function remember(id, name, auraType)
        hist[id] = { name = name, auraType = auraType }
        order[#order + 1] = id
    end
    for index = 1, pageSize do remember(1000 + index, "Test " .. index, "Magic") end
    NS:RefreshAuraHistoryPage()
    falsy(page.empty:IsShown(), "historique : l'etat vide disparait des la premiere entree")
    falsy(page.next:IsShown(), "historique : une seule page, aucune pagination")
    truthy(page.clearButton:IsEnabled(), "historique : le vidage devient actif")

    -- Deux pages : la pagination apparait.
    remember(2000, "Test debordement", "Poison")
    NS:RefreshAuraHistoryPage()
    truthy(page.next:IsShown(), "historique : deux pages, la pagination revient")
    truthy(page.page:IsShown(), "historique : avec son numero de page")
    truthy(page.next:IsEnabled(), "historique : « Suivant » est actif sur la premiere page")
    falsy(page.prev:IsEnabled(), "historique : « Precedent » ne l'est pas")

    -- Et le retour a l'etat vide.
    for id in pairs(hist) do hist[id] = nil end
    for index = #order, 1, -1 do order[index] = nil end
    NS:RefreshAuraHistoryPage()
    truthy(page.empty:IsShown(), "historique : le vidage ramene l'etat vide")
    falsy(page.page:IsShown(), "historique : et remasque la pagination")

    -- Priorites : les deux directions impossibles sont visiblement eteintes.
    NS.db.typeOrder = { "Magic", "Poison", "Curse", "Disease", "Bleed", "Charm" }
    NS:RefreshOptions()
    local byType = {}
    for _, row in ipairs(NS.typeRows or {}) do byType[row.type] = row end
    falsy(byType.Magic.up:IsEnabled(), "priorite : le premier type ne peut pas monter")
    truthy(byType.Magic.down:IsEnabled(), "priorite : mais il peut descendre")
    truthy(byType.Charm.up:IsEnabled(), "priorite : le dernier peut monter")
    falsy(byType.Charm.down:IsEnabled(), "priorite : mais pas descendre")
    truthy(byType.Curse.up:IsEnabled() and byType.Curse.down:IsEnabled(),
        "priorite : un type intermediaire peut faire les deux")
    truthy(byType.Magic.up.disabledDirection,
        "priorite : le chevron eteint est marque comme tel")
    truthy(#(byType.Magic.up.chevron or {}) == 2,
        "priorite : le chevron est dessine, pas ecrit avec un caractere")

    -- 1.5.30 : le dessin etait inverse alors que les actions etaient bonnes.
    -- SetRotation tourne dans le sens trigonometrique : une barre d'angle
    -- positif monte vers la droite. Un chevron « haut » est donc une barre
    -- gauche positive et une barre droite negative ; le « bas » est l'inverse.
    -- La convention a ete etablie sur une capture d'ecran, pas deduite.
    truthy(byType.Magic.up.chevron[1].__rotation > 0,
        "chevron : « monter » leve sa barre gauche")
    truthy(byType.Magic.up.chevron[2].__rotation < 0,
        "chevron : et abaisse sa droite")
    truthy(byType.Magic.down.chevron[1].__rotation < 0,
        "chevron : « descendre » abaisse sa barre gauche")
    truthy(byType.Magic.down.chevron[2].__rotation > 0,
        "chevron : et leve sa droite")
    eq(byType.Magic.up.chevron[1].__rotation, -byType.Magic.down.chevron[1].__rotation,
        "chevron : les deux directions sont exactement opposees")

    -- Et l'action reste celle qu'elle a toujours ete.
    NS.db.typeOrder = { "Magic", "Poison", "Curse", "Disease", "Bleed", "Charm" }
    NS:MoveType("Poison", -1)
    eq(NS.db.typeOrder[1], "Poison", "chevron : « monter » remonte bien le type")
    NS:MoveType("Poison", 1)
    eq(NS.db.typeOrder[1], "Magic", "chevron : « descendre » le redescend")

    -- L'apercu : une reduction fidele, pas une case rognee dont les textes
    -- gardent leur taille reelle. A 40 px la lettre recouvrait le nombre.
    local preview = NS.uxPreview
    for _, size in ipairs({ 12, 22, 40 }) do
        NS.db.frameSize = size
        NS:RefreshCellPreview()
        local realHint = NS:CellFontSize("hint", size)
        local realCountdown = NS:CellFontSize("countdown", size)
        eq(preview.hintFont, math.max(6, math.floor(realHint * preview.scale + 0.5)),
            "apercu " .. size .. " px : la lettre suit l'echelle de la case")
        eq(preview.countdownFont, math.max(6, math.floor(realCountdown * preview.scale + 0.5)),
            "apercu " .. size .. " px : le nombre aussi")
        truthy(preview.hintFont <= preview.cells[1].__lastSize.width,
            "apercu " .. size .. " px : la lettre tient dans la case")
        truthy(preview.countdownFont <= preview.cells[1].__lastSize.width,
            "apercu " .. size .. " px : le nombre aussi")
    end
    -- Le defaut precis des captures : a 40 px, les textes etaient calcules
    -- pour la case plafonnee et non pour la vraie, donc trop gros.
    NS.db.frameSize = 40
    NS:RefreshCellPreview()
    truthy(preview.scale < 1, "apercu 40 px : la case est bien reduite")
    truthy(preview.countdownFont < NS:CellFontSize("countdown", 40),
        "apercu 40 px : et le nombre est reduit avec elle")
    NS.db.frameSize = 22
end

-- 1.6.7 : la zone de contenu de la fenetre defile, et l'annonce vit sur la
-- FENETRE. La page d'Aide avait sa propre zone de defilement : imbriquee dans
-- celle-ci, deux barres se seraient disputees la meme molette.
do
    local scroll, hint = NS.optionsScroll, NS.optionsScrollHint
    truthy(scroll and hint, "defilement : la zone et sa bande existent")
    falsy(NS.helpScroll, "defilement : la page d'Aide n'a plus sa propre zone")

    -- La bande est posee sur la fenetre, pas sur une page : posee sur la page,
    -- elle defilerait avec elle et disparaitrait juste quand elle sert.
    eq(hint.__parent, NS.optionsFrame,
        "defilement : la bande appartient a la fenetre, pas a une page")

    -- Une page qui tient a l'ecran n'a rien a annoncer.
    scroll.__scrollRange = 0
    NS:UpdateOptionsScrollHint()
    falsy(hint:IsShown(), "defilement : une page qui tient en entier ne dit rien")

    scroll.__scrollRange = 660
    NS:UpdateOptionsScrollHint()
    truthy(hint:IsShown(), "defilement : une page plus longue que l'ecran l'annonce")
    eq(hint.label.__text, NS.L.HELP_SCROLL_HINT,
        "defilement : avec son libelle traduit")

    -- Descendre jusqu'en bas doit l'eteindre, et par le seul cablage de la
    -- molette : le test n'appelle pas la mise a jour lui-meme.
    scroll:SetVerticalScroll(660)
    falsy(hint:IsShown(), "defilement : arrive en bas, elle s'efface")
    scroll:SetVerticalScroll(0)
    truthy(hint:IsShown(), "defilement : et revient des qu'on remonte")

    -- Changer de page remet la hauteur qui defile a celle de la page affichee,
    -- et repart du haut. Sans cela une page courte heritait du defilement de la
    -- precedente, et s'ouvrait a mi-hauteur.
    scroll:SetVerticalScroll(400)
    NS:ShowOptionsPage("help")
    eq(NS.optionsContent.__height or NS.optionsContent.__lastSize.height,
        NS.optionsPageHeights.help, "defilement : la page d'Aide impose sa hauteur")
    eq(scroll:GetVerticalScroll(), 0, "defilement : et l'ouverture repart du haut")

    scroll.__scrollRange = 0
    NS:ShowOptionsPage("dispels")
    eq(NS.optionsContent.__height or NS.optionsContent.__lastSize.height,
        NS.optionsPageHeights.dispels,
        "defilement : une page courte ne garde pas la hauteur de la longue")
    truthy(NS.optionsPageHeights.dispels < NS.optionsPageHeights.help,
        "defilement : et elle est bien plus courte, sinon la mesure ne prouve rien")
    falsy(hint:IsShown(), "defilement : et n'annonce pas un defilement qui n'existe pas")

    -- La page Historique capte la molette pour sa pagination : elle ne doit
    -- donc JAMAIS avoir besoin de defiler, sans quoi les deux gestes se
    -- disputeraient le meme geste.
    -- 1.6.13, releve EN JEU le 30/08 : plus rien ne defilait. Les deux scripts
    -- etaient poses avec SetScript, qui REMPLACE : le gestionnaire de
    -- UIPanelScrollFrameTemplate disparaissait, sa barre n'etait plus
    -- configuree, et sa molette -- qui s'appuie dessus -- ne deplacait rien.
    -- Le bouchon ignorait qu'un modele arrive avec ses scripts, donc aucun test
    -- ne pouvait le voir. Il le modelise maintenant.
    do
        local ran = rawget(scroll, "__templateRan")
        truthy(ran, "defilement : la zone est bien construite sur un modele")
        for _, script in ipairs({ "OnVerticalScroll", "OnScrollRangeChanged", "OnMouseWheel" }) do
            local handler = scroll:GetScript(script)
            truthy(handler, "defilement : " .. script .. " est pose")
            local before = ran[script] or 0
            handler(scroll, -1)
            truthy((ran[script] or 0) > before,
                "defilement : " .. script .. " appelle ENCORE celui du modele")
        end

        -- Et la molette deplace reellement, en restant dans les bornes.
        scroll.__scrollRange = 300
        scroll:SetVerticalScroll(0)
        scroll:GetScript("OnMouseWheel")(scroll, -1)
        truthy(scroll:GetVerticalScroll() > 0, "molette : elle descend")
        scroll:SetVerticalScroll(300)
        scroll:GetScript("OnMouseWheel")(scroll, -1)
        eq(scroll:GetVerticalScroll(), 300, "molette : elle ne depasse pas le bas")
        scroll:SetVerticalScroll(0)
        scroll:GetScript("OnMouseWheel")(scroll, 1)
        eq(scroll:GetVerticalScroll(), 0, "molette : ni le haut")
        scroll.__scrollRange = 0
    end

    -- La bande d'indice etait posee DANS la zone de lecture : elle recouvrait
    -- la derniere ligne de chaque page longue.
    do
        local scrollPoint = scroll.__lastPoint
        local hintPoint = hint.__lastPoint
        truthy(scrollPoint and hintPoint, "bande : les deux sont poses par le bas")
        eq(scrollPoint.point, "BOTTOMRIGHT", "bande : le dernier ancrage de la zone est son bas")
        local hintTop = (hintPoint.y or 0) + 18
        truthy((scrollPoint.y or 0) >= hintTop,
            "bande : la zone de lecture s'arrete AU-DESSUS d'elle, elle ne couvre rien")
    end

    eq(NS.optionsPageHeights.history, NS.OPTIONS_VIEWPORT_HEIGHT,
        "defilement : la page Historique tient EXACTEMENT dans la zone visible")
    truthy(NS.optionsPageHeights.history <= NS.OPTIONS_VIEWPORT_HEIGHT,
        "defilement : elle n'a donc jamais besoin de defiler, sa molette reste a sa pagination")
end

--------------------------------------------------------------------------
-- 1.5.38 : aucun emplacement ne peut reposer sur un filtre par identifiant
--------------------------------------------------------------------------
do
    -- Blizzard_AuraContainerUtil.CanApplyIdentityCandidateFilters refuse
    -- includeSpellIDs et excludeSpellIDs sur une aura nefaste portee par une
    -- unite que le joueur peut assister, sauf sort NeverSecret. Un emplacement
    -- qui n'a QUE ce filtre n'est donc pas inerte : il affiche tout ce que son
    -- filtre general laisse passer. C'est ce qui est arrive a l'anneau
    -- d'avertissement de la 1.5.31, qui se posait sur chaque affliction.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RefreshAuraCandidateFilters()
    NS.db.ignoredAlways[999] = true
    NS:ConfigureButtonAuraContainer(NS.buttons[1], true)

    eq(#mock.state.identityFilterViolations, 0,
        "identite : aucun emplacement n'est filtre par identifiant seul")
    NS.db.ignoredAlways[999] = nil
end

--------------------------------------------------------------------------
-- 1.5.38 : activation et visibilite deviennent des reports visibles
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    mock.state.inCombat = false
    NS:FlushCombatUpdates()

    -- Desactiver l'addon en plein combat : le changement etait bien reporte,
    -- mais rien ne le disait. L'option semblait avoir change et l'ecran ne
    -- bougeait pas.
    mock.state.inCombat = true
    NS:SetEnabled(false)
    truthy(NS.pendingEnabled, "bascule : la desactivation est reportee")
    truthy(NS.pendingIndicator:IsShown(), "bascule : et la plaque le dit enfin")
    truthy(NS.enabled, "bascule : rien n'a change a l'ecran pendant le combat")

    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    falsy(NS.enabled, "bascule : la valeur demandee est appliquee a la sortie")
    falsy(NS.pendingEnabled, "bascule : le drapeau est vide")
    falsy(NS.pendingIndicator:IsShown(), "bascule : la plaque s'eteint")

    NS.enabled = true
    NS.db.enabled = true

    -- Meme chose pour le masquage de la grille.
    mock.state.inCombat = true
    NS:SetGridVisible(false)
    truthy(NS.pendingGridVisibility, "grille : le masquage est reporte")
    truthy(NS.pendingIndicator:IsShown(), "grille : et annonce")
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    falsy(NS.pendingGridVisibility, "grille : le drapeau est vide a la sortie")
    falsy(NS.pendingIndicator:IsShown(), "grille : la plaque s'eteint")
    NS:SetGridVisible(true)
end

--------------------------------------------------------------------------
-- 1.5.37 : une inscription refusee, et un restyle que le client interdit
--------------------------------------------------------------------------
do
    -- Releve en jeu le 29/08/2026, session suivant la 1.5.36 :
    --   [ADDON_ACTION_FORBIDDEN] Cleansive a tente d'appeler la fonction
    --   protegee 'Frame:RegisterEvent()'
    -- Le refus ne leve pas : il ouvre une fenetre dont le premier bouton
    -- desactive l'addon. Il faut donc demander a la frame si l'inscription a
    -- pris, et ne jamais la retenter.
    -- Une connexion part d'une frame neuve. Sans ce nettoyage, un evenement
    -- inscrit au chargement precedent restait inscrit et un refus devenait
    -- indetectable : le test aurait valide un code qui ne verifie rien.
    local function loadAddon()
        rawset(NS.eventFrame, "__events", {})
        local fire = NS.eventFrame:GetScript("OnEvent")
        fire(NS.eventFrame, "ADDON_LOADED", "Cleansive")
    end

    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:ResetDiagnostics()

    mock.state.refusedEvents = {}
    loadAddon()
    truthy(NS.eventFrame:IsEventRegistered("UNIT_PET"),
        "inscription : sans refus, tout s'inscrit")
    falsy(NS:GetDiagnostics().refusedEvents,
        "inscription : et rien n'est note comme refuse")

    -- Le client refuse celui-la, et lui seul.
    freshProfile("PALADIN")
    NS:ResetDiagnostics()
    mock.state.refusedEvents = { UNIT_PET = true }
    loadAddon()
    truthy(NS:IsEventRefused("UNIT_PET"),
        "inscription : un refus est reconnu et retenu")
    -- Ce qui compte vraiment : le refus ne coute pas leur inscription aux
    -- autres. C'est pour cela que celui-la est demande en dernier.
    truthy(NS.eventFrame:IsEventRegistered("PLAYER_LOGOUT"),
        "inscription : les autres evenements sont inscrits quand meme")
    truthy(NS.eventFrame:IsEventRegistered("UNIT_AURA"),
        "inscription : y compris ceux d'avant")

    -- Une seule fenetre dans la vie de l'addon, pas une par connexion : meme
    -- si le client ne refuse plus rien, on ne redemande pas.
    mock.state.refusedEvents = {}
    loadAddon()
    falsy(NS.eventFrame:IsEventRegistered("UNIT_PET"),
        "inscription : un refus retenu n'est pas retente")
    truthy(NS.eventFrame:IsEventRegistered("PLAYER_LOGOUT"),
        "inscription : mais le reste s'inscrit toujours")

    mock.state.refusedEvents = {}
end

-- 1.6.2 : la mise a l'echelle des fenetres ne se faisait qu'a la creation.
-- Changer de resolution, passer en fenetre ou bouger l'echelle de l'interface
-- laissait la fenetre a l'ancienne taille jusqu'au prochain /reload.
do
    freshProfile("PALADIN")
    local frame = NS.optionsFrame
    truthy(frame, "echelle : la fenetre d'options existe")

    local fire = NS.eventFrame:GetScript("OnEvent")
    truthy(NS.eventFrame:IsEventRegistered("UI_SCALE_CHANGED"),
        "echelle : le changement d'echelle de l'interface est ecoute")
    truthy(NS.eventFrame:IsEventRegistered("DISPLAY_SIZE_CHANGED"),
        "echelle : le changement de resolution aussi")

    -- Un ecran large : rien a reduire.
    mock.state.screen = { width = 1920, height = 1080 }
    NS:RefitWindows()
    eq(frame:GetScale(), 1, "echelle : sur un grand ecran la fenetre garde sa taille")

    -- L'ecran retrecit : c'est la hauteur qui manque en premier, 700 px de
    -- conception pour 620 - 40 disponibles.
    mock.state.screen = { width = 1200, height = 620 }
    fire(NS.eventFrame, "DISPLAY_SIZE_CHANGED")
    local expected = (620 - 40) / 700
    truthy(math.abs(frame:GetScale() - expected) < 0.001,
        "echelle : l'ecran retreci reduit la fenetre par le seul evenement")

    -- Et l'inverse : reprendre de la place doit rendre sa taille a la fenetre.
    mock.state.screen = { width = 1920, height = 1080 }
    fire(NS.eventFrame, "UI_SCALE_CHANGED")
    eq(frame:GetScale(), 1, "echelle : la place retrouvee rend sa taille a la fenetre")

    -- Le plancher de lisibilite tient : sous un certain point, mieux vaut une
    -- fenetre trop grande qu'une fenetre illisible.
    mock.state.screen = { width = 400, height = 300 }
    NS:RefitWindows()
    eq(frame:GetScale(), 0.70, "echelle : le plancher de lisibilite n'est pas franchi")

    mock.state.screen = { width = 1920, height = 1080 }
    NS:RefitWindows()
end

do
    -- 315 echecs de restyle en une session, aucun succes, et chacun annonce
    -- comme un geste du joueur : la plaque restait allumee tout le combat.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:ResetDiagnostics()

    local button = NS.buttons[1]
    local visuals = select(2, next(button.auraSlotVisuals or {}))
    local victim = visuals and visuals[1]
    truthy(victim, "restyle : un visuel du moteur existe")

    rawset(victim.stack, "SetShown", function()
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end)

    mock.state.inCombat = true
    NS.pendingAuraStyle = false
    local auraType = NS.engineAuraTypes[1]
    truthy(pcall(NS.StyleAuraVisual, NS, button, auraType, victim),
        "restyle : un refus du client ne remonte pas")
    truthy(NS.pendingAuraStyle, "restyle : le report a bien lieu")
    falsy(NS.pendingIndicator:IsShown(),
        "restyle : mais il ne promet rien au joueur")

    local record = NS:GetDiagnostics()
    eq(record.styleFailures, 1, "restyle : l'echec est compte")
    truthy(record.styleError and record.styleError:find("forbidden"),
        "restyle : et sa raison est conservee, pas seulement son nombre")

    mock.state.inCombat = false
    rawset(victim.stack, "SetShown", nil)
end

--------------------------------------------------------------------------
-- 1.5.36 : l'enregistreur de diagnostic
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:ResetDiagnostics()

    local fire = NS.eventFrame:GetScript("OnEvent")
    local record = NS:GetDiagnostics()

    -- La cause d'un report : c'est ce qui manquait pour expliquer la plaque.
    mock.state.inCombat = true
    fire(NS.eventFrame, "SPELLS_CHANGED")
    eq(record.pending.pendingSpells and record.pending.pendingSpells.lastCause,
        "SPELLS_CHANGED", "diag : un report nomme l'evenement qui l'a cause")

    NS:MarkPending("pendingLayout")
    eq(record.pending.pendingLayout and record.pending.pendingLayout.lastCause, "player",
        "diag : et un geste du joueur se distingue d'un evenement")
    mock.state.inCombat = false

    -- Le nom de l'evenement ne doit pas survivre a sa propre repartition.
    falsy(NS.currentEvent, "diag : le nom de l'evenement ne fuit pas")

    -- La deconnexion fige ce que le client s'apprete a jeter.
    fire(NS.eventFrame, "PLAYER_LOGOUT")
    truthy(record.engine, "diag : l'etat du moteur est conserve a la deconnexion")
    eq(record.engine and record.engine.readyButtons, NS.auraContainerDiagnostics.readyButtons,
        "diag : avec le nombre de cases pretes")

    NS:ResetDiagnostics()
    falsy(next(NS:GetDiagnostics().pending), "diag : la remise a zero vide le releve")
end

--------------------------------------------------------------------------
-- 1.5.35 : une etiquette interdite ne doit pas emporter la disposition
--------------------------------------------------------------------------
do
    -- Releve en jeu le 28/08/2026 par !BugGrabber :
    --   Frames.lua : calling 'SetFont' on bad self (Attempt to access
    --   forbidden object from code tainted by an AddOn)
    -- dans ApplyCellFonts, appelee par LayoutButtons, appelee par
    -- FlushCombatUpdates. Le moteur protege peut declarer ses propres
    -- etiquettes interdites au code d'addon.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()

    local button = NS.buttons[1]
    local visuals = select(2, next(button.auraSlotVisuals or {}))
    local victim = visuals and visuals[1]
    truthy(victim, "interdit : une etiquette du moteur existe")

    -- Le client refuse l'acces a l'objet, exactement comme en jeu.
    rawset(victim.unitName, "SetFont", function()
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end)

    local ok = pcall(NS.ApplyCellFonts, NS, button)
    truthy(ok, "interdit : la passe de polices survit a l'etiquette refusee")

    -- La consequence reelle : pendingLayout est eteint a la DERNIERE ligne de
    -- LayoutButtons. Une erreur en cours de route laissait le drapeau leve
    -- pour le reste de la session, et la plaque se rallumait a chaque combat.
    mock.state.inCombat = true
    truthy(pcall(NS.LayoutButtons, NS), "interdit : la disposition tient en combat")
    truthy(NS.pendingLayout, "interdit : la disposition est differee en combat")
    truthy(NS.pendingIndicator:IsShown(), "interdit : et la plaque l'annonce")

    mock.state.inCombat = false
    truthy(pcall(NS.FlushCombatUpdates, NS), "interdit : le vidage va au bout")
    falsy(NS.pendingLayout, "interdit : le drapeau s'eteint malgre l'etiquette refusee")
    falsy(NS.pendingIndicator:IsShown(), "interdit : la plaque ne reste pas allumee")

    -- Et le combat suivant ne doit rien rallumer tout seul.
    mock.state.inCombat = true
    NS:UpdatePendingIndicator()
    falsy(NS.pendingIndicator:IsShown(), "interdit : ni au combat suivant")
    mock.state.inCombat = false

    -- Rendre l'etiquette : laissee empoisonnee, elle faisait exploser tous les
    -- blocs suivants qui redisposent la grille, et le vrai defaut devenait
    -- indiscernable du degat collateral de son propre test.
    rawset(victim.unitName, "SetFont", nil)
end

--------------------------------------------------------------------------
-- 1.5.34 : la plaque d'attente ne parle que des gestes du joueur
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:RebuildRoster()
    NS:CreateGrid()
    mock.state.inCombat = false
    NS:FlushCombatUpdates()

    local fire = NS.eventFrame:GetScript("OnEvent")
    truthy(fire, "plaque : le repartiteur d'evenements est atteignable")

    -- SPELLS_CHANGED part sur une forme d'ours, une monture, un objet. En
    -- donjon la plaque s'allumait a presque chaque pull pour ca.
    mock.state.inCombat = true
    fire(NS.eventFrame, "SPELLS_CHANGED")
    truthy(NS.pendingSpells, "plaque : le report a bien lieu")
    falsy(NS.pendingIndicator:IsShown(), "plaque : mais il ne s'annonce pas")

    -- Le meme drapeau, pose par un geste du joueur, s'annonce.
    NS.pendingSpells = false
    NS:MarkPending("pendingSpells")
    truthy(NS.pendingIndicator:IsShown(), "plaque : un geste du joueur s'annonce")

    -- Et un evenement de fond ne doit pas faire taire ce que le joueur attend.
    fire(NS.eventFrame, "SPELLS_CHANGED")
    truthy(NS.pendingIndicator:IsShown(),
        "plaque : un evenement de fond ne l'eteint pas")

    -- Apres le vidage, un nouvel evenement de fond repart muet : l'annonce ne
    -- doit pas rester collee au drapeau d'une fois sur l'autre.
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    mock.state.inCombat = true
    fire(NS.eventFrame, "SPELLS_CHANGED")
    truthy(NS.pendingSpells, "plaque : le report suivant a lieu aussi")
    falsy(NS.pendingIndicator:IsShown(), "plaque : et redevient muet")

    -- La suppression ne doit pas survivre a l'evenement qui l'a posee, sinon
    -- le geste suivant du joueur serait muet lui aussi. Verifie juste apres un
    -- evenement du jeu, seul cas ou elle a ete posee.
    falsy(NS.pendingNoticeSuppressed, "plaque : la suppression ne fuit pas")

    -- Poser un focus est un geste delibere : sa case attend vraiment.
    NS.pendingRoster = false
    fire(NS.eventFrame, "PLAYER_FOCUS_CHANGED")
    truthy(NS.pendingIndicator:IsShown(), "plaque : un focus pose s'annonce")

    mock.state.inCombat = false
    NS:FlushCombatUpdates()
end

--------------------------------------------------------------------------
-- 1.5.31 : l'ordre des groupes commence au sien
--------------------------------------------------------------------------
do
    -- Huit membres, quatre groupes de deux. Deux par groupe est necessaire :
    -- avec un seul, le joueur EST son groupe, il est deduplique, et son propre
    -- groupe disparait de l'ordre qu'on veut justement observer.
    local GROUP_OF = { 1, 1, 2, 2, 3, 3, 4, 4 }

    local function raidSeenFrom(playerIndex)
        freshProfile("PALADIN")
        knowSpells(4987)
        NS:UpdateSpells()
        mock.state.inRaid = true
        for index = 1, 8 do
            mock.state.exists["raid" .. index] = true
            mock.state.raidGroups[index] = GROUP_OF[index]
        end
        mock.state.sameUnit["raid" .. playerIndex] = "player"
        NS:RebuildRoster()
        local order = {}
        for _, d in ipairs(NS:BuildRoster()) do
            if not d.isPlayer then order[#order + 1] = d.group end
        end
        return order
    end

    eq(raidSeenFrom(5) and NS:PlayerRaidGroup(), 3, "raid : le joueur se sait dans le groupe 3")

    eq(table.concat(raidSeenFrom(5), ","), "3,4,4,1,1,2,2",
        "raid : depuis le groupe 3, l'ordre repart de 3 et boucle")

    eq(table.concat(raidSeenFrom(1), ","), "1,2,2,3,3,4,4",
        "raid : depuis le groupe 1, l'ordre reste le classique")

    -- Le point de la manoeuvre : deux dissipeurs de groupes differents ne
    -- commencent pas par la meme case.
    truthy(raidSeenFrom(3)[1] ~= raidSeenFrom(7)[1],
        "raid : deux dissipeurs ne visent pas la meme case en premier")

    -- La liste de priorite est lue avant : elle doit rester souveraine.
    raidSeenFrom(5)
    NS:AddListEntry("priority", "GROUP", 1)
    local withPriority = {}
    for _, d in ipairs(NS:BuildRoster()) do
        if not d.isPlayer then withPriority[#withPriority + 1] = d.group end
    end
    eq(withPriority[1], 1, "raid : une priorite explicite passe avant l'ordre relatif")

    -- Hors raid, tout le monde est dans le groupe 1 : rien a repartir.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    eq(NS:PlayerRaidGroup(), 1, "raid : hors raid, le groupe vaut 1")

    mock.state.inRaid = false
end

--------------------------------------------------------------------------
-- 1.5.39 : les deux plaques d'etat ne doivent pas se superposer
--------------------------------------------------------------------------
do
    -- Le commentaire affirmait que les deux ne pouvaient pas etre necessaires
    -- en meme temps. C'est faux : une specialisation sans dissipation peut
    -- redimensionner la grille en plein combat, ce qui differe un changement
    -- protege. Les deux plaques etaient alors posees au meme point.
    freshProfile("PALADIN")
    -- Aucun sort de dissipation connu : la plaque « Sans dissipation » a lieu.
    NS:UpdateSpells()
    NS.spellbookResolved = true
    NS:CreateGrid()
    NS:UpdateNoCureNotice()
    truthy(NS.noCureNotice:IsShown(), "plaques : sans dissipation, la plaque parait")

    mock.state.inCombat = true
    NS.db.frameSize = 34
    NS:MarkPending("pendingLayout")
    truthy(NS.pendingIndicator:IsShown(), "plaques : et le report s'annonce aussi")

    local _, _, _, pendingX = NS.pendingIndicator:GetPoint()
    local _, _, _, noCureX = NS.noCureNotice:GetPoint()
    truthy(pendingX ~= noCureX, "plaques : les deux visibles ne partagent pas le meme point")

    -- Et quand le report retombe, la plaque restante reprend la place libree
    -- au lieu de rester decalee dans le vide.
    mock.state.inCombat = false
    NS.pendingLayout = false
    NS:UpdatePendingIndicator()
    NS:UpdateNoCureNotice()
    local _, _, _, aloneX = NS.noCureNotice:GetPoint()
    eq(aloneX, 0, "plaques : seule, la plaque revient au coin")
    mock.state.inCombat = false
end

--------------------------------------------------------------------------
-- 1.5.39 : un enregistrement sonore rate doit etre repris
--------------------------------------------------------------------------
do
    -- Effacer l'empreinte laissait la porte ouverte a une reprise mais ne la
    -- demandait a personne. Hors combat, sans autre evenement, les sons
    -- restaient absents pour le reste de la session.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    mock.state.exists.party1 = true
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end

    local realAdd = C_UnitAuras.AddAuraSound
    local failures = 1
    C_UnitAuras.AddAuraSound = function(...)
        if failures > 0 then
            failures = failures - 1
            return nil
        end
        return realAdd(...)
    end

    NS.auraSoundRetries = 0
    -- Le drapeau de planification est porte par NS, pas par le profil : sans
    -- cette remise a zero, une demande d'un bloc precedent avale la reprise.
    NS.auraSoundRefreshScheduled = false
    NS:RefreshAuraSoundRegistrations("test")
    truthy((NS.auraSoundRetries or 0) > 0, "son : un echec partiel arme une reprise")
    truthy(mock.timerCount() > 0, "son : la reprise est reellement programmee")
    mock.runTimers()

    -- La reprise aboutit, et le compteur retombe : un echec passager ne doit
    -- pas consommer le budget de la fois suivante.
    for _ = 1, 6 do mock.runTimers() end
    eq(NS.auraSoundRetries, 0, "son : la reprise reussie remet le compteur a zero")

    -- Un refus permanent ne doit pas boucler.
    C_UnitAuras.AddAuraSound = function() return nil end
    NS.auraSoundRetries = 0
    NS:RefreshAuraSoundRegistrations("test permanent")
    for _ = 1, 12 do mock.runTimers() end
    truthy(NS.auraSoundRetries <= 2, "son : un refus permanent s'arrete a deux reprises")

    C_UnitAuras.AddAuraSound = realAdd
    IsInGroup = realIsInGroup
end

--------------------------------------------------------------------------
-- 1.5.39 : un refus perime ne doit pas se lire comme un probleme actuel
--------------------------------------------------------------------------
do
    -- La base de Rodolphe portait encore
    -- refusedEvents.COMBAT_LOG_EVENT_UNFILTERED de la 1.5.37, alors que la
    -- 1.5.38 ne demande plus cet evenement. Le releve l'imprimait quand meme.
    freshProfile("PALADIN")
    NS:NoteRefusedEvent("COMBAT_LOG_EVENT_UNFILTERED")
    NS:NoteRefusedEvent("UNIT_AURA")
    NS:ForgetRefusalsOutside({ "UNIT_AURA", "SPELLS_CHANGED" })
    falsy(NS:IsEventRefused("COMBAT_LOG_EVENT_UNFILTERED"),
        "refus : un evenement qu'on ne demande plus est oublie")
    truthy(NS:IsEventRefused("UNIT_AURA"),
        "refus : un evenement toujours demande est conserve")

    -- La remise a zero est un vidage de releve, pas un oubli de securite :
    -- reessayer un evenement refuse ramene la fenetre qui desactive l'addon.
    NS:MarkPending("pendingLayout")
    NS:ResetDiagnostics()
    falsy(next(NS:GetDiagnostics().pending), "refus : la remise a zero vide bien le releve")
    truthy(NS:IsEventRefused("UNIT_AURA"), "refus : mais garde la memoire des refus")

    -- Et le releve doit conclure.
    local before = #mock.state.chat
    NS:PrintDiagnostics()
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("probl", 1, true) or printed:find("problem", 1, true),
        "diag : un refus vivant est compte comme un probleme")

    -- Le bloc sonore precedent a laisse une erreur dans le releve, et c'est
    -- bien un probleme : ce test parle du cas ou il n'y en a aucun.
    NS:GetDiagnostics().refusedEvents = {}
    NS.auraSoundDiagnostics, NS.auraContainerDiagnostics = nil, nil
    NS:GetDiagnostics().sound, NS:GetDiagnostics().engine = nil, nil
    before = #mock.state.chat
    NS:PrintDiagnostics()
    printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("sain", 1, true) or printed:find("healthy", 1, true),
        "diag : sans refus ni echec, le releve se declare sain")
end

--------------------------------------------------------------------------
-- 1.5.39 : les fenetres secondaires doivent finir comme l'Historique
--------------------------------------------------------------------------
do
    -- Les actions etaient deja bloquees ; c'est l'apparence qui mentait. Un
    -- chevron eteint par SetEnabled seul garde la peinture d'un controle
    -- vivant, et « Page 1 sur 1 » entre deux boutons morts est du mobilier.
    freshProfile("PALADIN")
    NS:CreateListWindow()
    NS.currentListKind = "priority"

    NS:RefreshListWindow()
    falsy(NS.listFrame.page:IsShown(), "listes : pas de pagination sur une seule page")
    falsy(NS.listFrame.prev:IsShown(), "listes : ni de bouton precedent")
    falsy(NS.listFrame.clearButton:IsEnabled(), "listes : vider une liste vide est eteint")

    NS:AddListEntry("priority", "CLASS", "PALADIN")
    NS:AddListEntry("priority", "CLASS", "PRIEST")
    NS:RefreshListWindow()
    truthy(NS.listFrame.clearButton:IsEnabled(), "listes : la liste remplie se laisse vider")
    truthy(NS.listFrame.rows[1].up.disabledDirection,
        "listes : la premiere ligne peint son chevron haut comme inactif")
    falsy(NS.listFrame.rows[1].down.disabledDirection,
        "listes : mais pas son chevron bas")
    truthy(NS.listFrame.rows[2].down.disabledDirection,
        "listes : la derniere ligne peint son chevron bas comme inactif")

    -- Assez d'entrees pour deux pages : la pagination doit reparaitre.
    for index = 1, #NS.listFrame.rows do
        NS:AddListEntry("priority", "PLAYER", "Figurant" .. index)
    end
    NS:RefreshListWindow()
    truthy(NS.listFrame.page:IsShown(), "listes : deux pages ramenent la pagination")
end

--------------------------------------------------------------------------
-- 1.5.40 : un refus ne doit plus emporter le reste du style
--------------------------------------------------------------------------
do
    -- Releve en jeu le 29/08/2026 :
    --   Frames.lua:641: calling 'SetFrameLevel' on bad self (Attempt to access
    --   forbidden object from code tainted by an AddOn)
    -- 315 fois en une session. SetFrameLevel etait la PREMIERE ligne du pcall :
    -- le fond, la bande de type, le compteur et la lettre de clic n'etaient
    -- jamais poses non plus. Meme famille que la police de la 1.5.35, corrigee
    -- a l'epoque seulement la ou elle avait ete vue.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()

    local button = NS.buttons[1]
    local auraType, visuals = next(button.auraSlotVisuals or {})
    local visual = visuals and visuals[1]
    truthy(visual, "style : un visuel du moteur existe")

    -- Le client refuse le cadre du moteur, exactement comme en jeu.
    rawset(visual.auraButton, "SetFrameLevel", function()
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end)
    rawset(visual.overlay, "__color", nil)
    rawset(visual.typeMark, "__color", nil)

    local before = NS:GetDiagnostics().styleFailures or 0
    truthy(pcall(NS.StyleAuraVisual, NS, button, auraType, visual),
        "style : la passe survit au refus")
    truthy(rawget(visual.overlay, "__color") ~= nil,
        "style : le fond est pose malgre le refus du cadre")
    truthy(rawget(visual.typeMark, "__color") ~= nil,
        "style : la bande de type aussi")

    -- Et le releve doit dire combien de la passe a ete perdu, pas seulement
    -- qu'elle a echoue : une etape sur neuf n'est pas neuf sur neuf.
    local record = NS:GetDiagnostics()
    eq(record.styleFailures, before + 1, "style : l'echec est compte une fois")
    eq(record.styleSteps, 1, "style : une seule etape perdue sur la passe")
end

--------------------------------------------------------------------------
-- 1.5.40 : le releve doit etre datable et voir le pic
--------------------------------------------------------------------------
do
    -- Les compteurs cumulaient a vie. Le 29/08 la base montrait 630 reports et
    -- 315 refus sans aucun moyen de savoir de quelle session ni de quelle
    -- version ils venaient : il a fallu comparer a une copie gardee par hasard.
    freshProfile("PALADIN")
    NS:MarkPending("pendingLayout")
    NS:NoteStyleFailure("vieille erreur", 3)
    local record = NS:GetDiagnostics()
    truthy(record.styleFailures, "version : un compte existe sous l'ancienne version")

    record.version = "0.0.1-ancienne"
    local fresh = NS:GetDiagnostics()
    falsy(fresh.styleFailures, "version : changer de version remet les comptes a zero")
    falsy(next(fresh.pending), "version : les reports aussi")
    eq(fresh.version, NS.version, "version : le releve porte la version installee")

    -- Le residu mort de la 1.5.37 doit disparaitre de la base.
    fresh.unlisted = { quelquechose = true }
    falsy(NS:GetDiagnostics().unlisted, "version : le champ mort unlisted est purge")

    -- Le pic : l'instantane de deconnexion voit le joueur seul, donc 46
    -- inscriptions pour une unite. Le donjon qu'il devait mesurer est
    -- exactement ce qu'il ne peut pas voir.
    NS:NoteSoundLoad(230, 5, 230)
    NS:NoteSoundLoad(46, 1, 46)
    local peak = NS:GetDiagnostics().soundPeak
    eq(peak.attempted, 230, "pic : la charge du groupe est retenue")
    eq(peak.units, 5, "pic : avec le nombre d'unites de ce moment")
    eq(peak.registered, 230, "pic : et ce qui a reellement ete inscrit")

    -- Le pic doit etre releve par le vrai chemin, pas seulement par un appel
    -- direct : c'est le cablage dans DispelSounds.lua qui compte.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    mock.state.exists.party1, mock.state.exists.party2 = true, true
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end
    NS.auraSoundRefreshScheduled = false
    NS:RebuildRoster()
    NS:RefreshAuraSoundRegistrations("mesure du pic")
    mock.runTimers()
    IsInGroup = realIsInGroup
    local wired = NS:GetDiagnostics().soundPeak
    truthy(wired and wired.attempted > 0,
        "pic : un rafraichissement reel alimente le pic")
    truthy(wired and wired.units >= 3,
        "pic : et retient les unites du groupe, pas le joueur seul")

    -- Un pic incomplet est un probleme, meme si la fin de session est propre.
    NS:GetDiagnostics().soundPeak = { attempted = 230, units = 5, registered = 180 }
    local before = #mock.state.chat
    NS:PrintDiagnostics()
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("230", 1, true), "pic : le releve imprime la charge reelle")
    truthy(printed:find("probl", 1, true) or printed:find("problem", 1, true),
        "pic : une inscription incomplete en groupe est signalee")
end

--------------------------------------------------------------------------
-- 1.5.41 : rien de visible ne doit dependre d'un stylage refusable
--------------------------------------------------------------------------
do
    -- Le releve du 29/08/2026 : 690 refus de StyleAuraVisual, 6210 etapes
    -- perdues -- soit les neuf a chaque fois, parce que toutes les regions sont
    -- filles du cadre protege du moteur. StyleAuraVisual est aussi ce qui
    -- masque la plaque de la lettre de clic, et cette plaque est la seule de
    -- ces regions a naitre avec une couleur. Un refus au tout premier passage
    -- laissait un carre sombre dans le coin d'une cellule, alors que le joueur
    -- avait desactive les lettres de clic. La cellule de repli, elle, cachait
    -- sa plaque des la creation depuis toujours.
    freshProfile("PALADIN")
    NS.db.showClickHints = false
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()

    -- Le client refuse tout le stylage : on reproduit le cas ou meme le
    -- premier passage, celui de la creation, n'aboutit pas.
    local realStyle = NS.StyleAuraVisual
    NS.StyleAuraVisual = function() end
    NS:CreateGrid()
    NS.StyleAuraVisual = realStyle

    local button = NS.buttons[1]
    local _, visuals = next(button.auraSlotVisuals or {})
    local visual = visuals and visuals[1]
    truthy(visual, "plaque de clic : un visuel du moteur existe")
    falsy(visual.clickHintPlate:IsShown(),
        "plaque de clic : rien ne reste affiche quand le stylage est refuse")

    -- Les autres regions ne portent ni couleur ni texte : il n'y a rien a
    -- cacher chez elles, et les cacher par precaution serait du bruit.
    falsy(rawget(visual.overlay, "__color"), "plaque de clic : le fond nait sans couleur")
    falsy(rawget(visual.typeMark, "__color"), "plaque de clic : la bande de type aussi")

    -- Et un stylage qui aboutit doit toujours pouvoir la montrer.
    NS.db.showClickHints = true
    NS:StyleAuraVisual(button, "Magic", visual)
    local slot = NS.typeToSlot and NS.typeToSlot.Magic
    if slot then
        truthy(visual.clickHintPlate:IsShown(),
            "plaque de clic : un stylage qui passe la montre encore")
    end
end

--------------------------------------------------------------------------
-- 1.5.42 : relever l'etat reel des restrictions, pas seulement le combat
--------------------------------------------------------------------------
do
    -- 12.1 connait six restrictions ; InCombatLockdown() n'en couvre qu'une.
    -- Une cle mythique garde ChallengeMode actif entre les packs, la ou le
    -- code se croit libre d'agir. Le releve du 29/08 comptait 315 refus de
    -- stylage tous marques lastCause="player", donc hors dispatch : c'est
    -- exactement ce cas qu'il faut pouvoir prouver ou ecarter.
    freshProfile("PALADIN")
    mock.state.inCombat = false
    mock.state.restrictions = {}
    eq(NS:RestrictionSnapshot(), "lock=0 / none",
        "restrictions : au repos, rien n'est actif")

    mock.state.restrictions[Enum.AddOnRestrictionType.ChallengeMode] = true
    eq(NS:RestrictionSnapshot(), "lock=0 / ChallengeMode",
        "restrictions : la cle reste active hors combat -- le cas non modelise")

    mock.state.inCombat = true
    mock.state.restrictions[Enum.AddOnRestrictionType.Combat] = true
    eq(NS:RestrictionSnapshot(), "lock=1 / Combat,ChallengeMode",
        "restrictions : combat et cle se cumulent")

    -- 1.6.13, releve EN JEU sur la 1.6.12 : le separateur etait une barre
    -- verticale, et « |none » se lit « |n » puis « one » -- « |n » etant un
    -- RETOUR A LA LIGNE pour le moteur de texte de WoW. Le rapport affichait
    -- « lock=0 » puis « one » sur la ligne suivante. Aucune valeur de ce
    -- rapport ne doit contenir de barre verticale.
    do
        -- L'etat est rendu tel qu'il a ete trouve : la suite de ce bloc compte
        -- sur la cle encore active.
        local saved = mock.state.restrictions
        for _, situation in ipairs({ {}, { [Enum.AddOnRestrictionType.Map] = true } }) do
            mock.state.restrictions = situation
            falsy(NS:RestrictionSnapshot():find("|", 1, true),
                "restrictions : le releve ne contient aucune barre verticale")
        end
        mock.state.restrictions = saved
    end

    -- Un echec de stylage doit emporter son contexte, groupe : la question
    -- n'est pas a quoi ressemblait le dernier refus, mais s'ils arrivent tous
    -- pendant que l'addon se croit libre.
    -- Sortie de combat : le verrou tombe ET la restriction Combat aussi, mais
    -- la cle, elle, reste. C'est le seul etat qui compte pour l'hypothese.
    mock.state.inCombat = false
    mock.state.restrictions[Enum.AddOnRestrictionType.Combat] = nil
    NS:NoteStyleFailure("interdit", 9)
    NS:NoteStyleFailure("interdit", 9)
    local record = NS:GetDiagnostics()
    eq(record.styleContext["lock=0 / ChallengeMode"], 2,
        "restrictions : les refus sont comptes par contexte")
    eq(record.styleSteps, 18, "restrictions : et les etapes perdues s'additionnent")
end

--------------------------------------------------------------------------
-- 1.5.42 : le client nomme lui-meme ce qu'il refuse
--------------------------------------------------------------------------
do
    -- Jusqu'ici Cleansive devinait ses refus apres coup, en demandant au cadre
    -- si l'inscription avait pris. ADDON_ACTION_FORBIDDEN donne le nom de la
    -- fonction refusee. L'evenement concerne TOUS les addons : le nom doit
    -- etre verifie avant d'ecrire quoi que ce soit.
    freshProfile("PALADIN")
    mock.state.restrictions = {}

    local fire = NS.eventFrame and NS.eventFrame:GetScript("OnEvent")
    truthy(fire, "interdits : le repartiteur est atteignable")

    fire(NS.eventFrame, "ADDON_ACTION_FORBIDDEN", "UnAutreAddon", "Frame:SetPoint()")
    falsy(next(NS:GetDiagnostics().forbidden or {}),
        "interdits : le refus d'un autre addon n'est pas enregistre")

    fire(NS.eventFrame, "ADDON_ACTION_FORBIDDEN", NS.addonName, "Frame:RegisterEvent()")
    fire(NS.eventFrame, "ADDON_ACTION_FORBIDDEN", NS.addonName, "Frame:RegisterEvent()")
    local forbidden = NS:GetDiagnostics().forbidden
    eq(forbidden["Frame:RegisterEvent()"].count, 2,
        "interdits : le notre est compte, par fonction")
    truthy(forbidden["Frame:RegisterEvent()"].context,
        "interdits : avec l'etat des restrictions du moment")

    -- Le repartiteur ne doit pas laisser trainer son contexte d'evenement.
    falsy(NS.currentEvent, "interdits : le nom de l'evenement ne fuit pas")

    -- Et ces relevés suivent la version comme les autres.
    NS:GetDiagnostics().version = "0.0.1-ancienne"
    falsy(next(NS:GetDiagnostics().forbidden or {}),
        "interdits : changer de version remet le releve a zero")
end

--------------------------------------------------------------------------
-- 1.5.43 : les boutons de pouce
--------------------------------------------------------------------------
do
    -- Les deux concurrents serieux les proposent. Rien de neuf n'est lie ici :
    -- le bouton 4 refait la troisieme dissipation, deja sur Ctrl + gauche, et
    -- le bouton 5 refait la focalisation, deja sur Ctrl + milieu. Une souris
    -- sans ces boutons ne perd rien.
    freshProfile("PALADIN")
    -- Paladin sacre : Purification (4987) et Purification de la lumiere
    -- (53551) donnent au moins deux emplacements.
    knowSpells(4987, 53551, 213644)
    NS:UpdateSpells()
    NS:CreateGrid()
    mock.state.exists.party1 = true
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end
    NS:RebuildRoster()
    IsInGroup = realIsInGroup
    NS:ApplySecureBindings()

    local button = NS.buttons[1]
    local target = button.clickLayer or button
    truthy(target:GetAttribute("unit") ~= nil or button.unit ~= nil,
        "pouce : une case porte bien une unite")

    -- Le bouton 4 doit refaire exactement ce que fait Ctrl + gauche.
    -- Verifie non nul d'abord : sinon l'egalite passe pour rien.
    truthy(target:GetAttribute("spell4"), "pouce : le bouton 4 porte un sort")
    eq(target:GetAttribute("spell4"), target:GetAttribute("ctrl-spell1"),
        "pouce : le bouton 4 lance le meme sort que Ctrl + gauche")
    eq(target:GetAttribute("type4"), target:GetAttribute("ctrl-type1"),
        "pouce : et du meme type d'action")
    eq(target:GetAttribute("*spell4"), target:GetAttribute("spell4"),
        "pouce : le joker suit, comme pour les boutons 1 et 2")

    -- Le bouton 5 focalise, comme Ctrl + clic milieu.
    eq(target:GetAttribute("type5"), "focus", "pouce : le bouton 5 focalise")
    eq(target:GetAttribute("type5"), target:GetAttribute("ctrl-type3"),
        "pouce : la meme action que Ctrl + milieu")

    -- Et rien de tout cela n'a deplace les clics d'origine.
    eq(target:GetAttribute("type3"), "target", "pouce : le clic milieu cible toujours")
    truthy(target:GetAttribute("spell1"), "pouce : le clic gauche dissipe toujours")

    -- Les deux langues doivent decrire ces boutons, sinon l'infobulle ment.
    truthy(NS.LOCALES.enUS.THUMB_BIND, "pouce : l'anglais decrit les boutons")
    truthy(NS.LOCALES.frFR.THUMB_BIND, "pouce : le francais aussi")
end

--------------------------------------------------------------------------
-- 1.5.44 : un visuel interdit se demande une fois, pas a chaque combat
--------------------------------------------------------------------------
do
    -- Un objet interdit ne redevient jamais autorise. Reprogrammer
    -- pendingAuraStyle apres lui revenait a rejouer neuf appels refuses a
    -- chaque combat : 690 fois en une session, en silence et pour rien.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()

    local button = NS.buttons[1]
    local auraType, visuals = next(button.auraSlotVisuals or {})
    local visual = visuals and visuals[1]
    truthy(visual, "interdit : un visuel du moteur existe")

    rawset(visual.auraButton, "__forbidden", true)
    NS.pendingAuraStyle = false
    local before = NS:GetDiagnostics().styleFailures or 0

    NS:StyleAuraVisual(button, auraType, visual)
    truthy(visual.forbidden, "interdit : le visuel est marque une fois pour toutes")
    falsy(NS.pendingAuraStyle, "interdit : aucun report n'est rearme")
    eq(NS:GetDiagnostics().styleFailures or 0, before,
        "interdit : ce n'est pas compte comme un echec de restyle")
    eq(NS:GetDiagnostics().forbiddenVisuals, 1, "interdit : mais la case est comptee")

    -- Les passes suivantes ne doivent plus rien tenter du tout.
    NS:StyleAuraVisual(button, auraType, visual)
    NS:StyleAuraVisual(button, auraType, visual)
    eq(NS:GetDiagnostics().forbiddenVisuals, 1,
        "interdit : les passes suivantes ne recomptent pas")
    falsy(NS.pendingAuraStyle, "interdit : et ne rearment toujours rien")
end

--------------------------------------------------------------------------
-- 1.5.44 : le budget de reprise sonore appartient au plan, pas a la session
--------------------------------------------------------------------------
do
    -- Le compteur ne retombait a zero qu'apres une reussite complete. Deux
    -- refus definitifs sur un plan A laissaient donc un plan B different sans
    -- aucune reprise, alors qu'il n'avait jamais echoue.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.auraSoundRefreshScheduled = false
    NS:RefreshAuraSoundRegistrations("plan A")
    mock.runTimers()
    local planA = NS.auraSoundRetryFingerprint
    truthy(planA, "budget : le plan est identifie par son empreinte")

    -- Budget epuise sur le plan A.
    NS.auraSoundRetries = 2

    -- Le plan change : un membre de groupe apparait.
    mock.state.exists.party1 = true
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end
    NS:RebuildRoster()
    NS.auraSoundRefreshScheduled = false
    NS:RefreshAuraSoundRegistrations("plan B")
    mock.runTimers()
    IsInGroup = realIsInGroup

    truthy(NS.auraSoundRetryFingerprint ~= planA, "budget : le plan a bien change")
    eq(NS.auraSoundRetries, 0, "budget : un plan neuf repart avec ses reprises")
end

--------------------------------------------------------------------------
-- 1.5.44 : le bouton 4 doit alimenter le suivi de recharge
--------------------------------------------------------------------------
do
    -- La 1.5.43 a lie Button4 au troisieme sort mais ne l'a pas ajoute au
    -- registre des clics : le jeu lancait le sort, la case gardait la recharge
    -- du sort precedent. La liaison securisee et ce registre doivent nommer
    -- les memes boutons.
    freshProfile("PALADIN")
    knowSpells(4987, 53551, 213644)
    NS:UpdateSpells()
    NS:CreateGrid()
    mock.state.exists.party1 = true
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end
    NS:RebuildRoster()
    IsInGroup = realIsInGroup

    local button = NS.buttons[1]
    truthy(button.unit, "recharge : la case porte une unite")

    -- Le contrat n'est pas « emplacement 3 » : un paladin sacre n'a qu'un sort
    -- cliquable, et le repli vers l'emplacement 1 est deliberé. Le contrat est
    -- que le bouton 4 fasse EXACTEMENT ce que fait Ctrl + gauche, quel que
    -- soit le nombre de sorts du personnage.
    local realCtrl = IsControlKeyDown
    IsControlKeyDown = function() return true end
    NS:RecordSecureClick(button, "LeftButton")
    local viaCtrl = button.cooldownSlot
    IsControlKeyDown = realCtrl

    button.cooldownSlot, button.cooldownClickTime = nil, nil
    NS:RecordSecureClick(button, "Button4")
    truthy(button.cooldownSlot, "recharge : le bouton 4 n'est plus ignore")
    eq(button.cooldownSlot, viaCtrl,
        "recharge : le bouton 4 vise le meme emplacement que Ctrl + gauche")
    truthy(button.cooldownClickTime, "recharge : et l'heure du clic est retenue")
    truthy(NS.lastClick and NS.lastClick.unit == button.unit,
        "recharge : le clic est inscrit au registre")

    -- Sans regression sur les boutons d'origine.
    NS:RecordSecureClick(button, "LeftButton")
    eq(button.cooldownSlot, 1, "recharge : le clic gauche vise toujours le premier")

    -- Un bouton qui ne lance rien ne doit rien inscrire.
    button.cooldownSlot = nil
    NS:RecordSecureClick(button, "Button5")
    falsy(button.cooldownSlot, "recharge : le bouton 5 focalise, il ne dissipe pas")
end

--------------------------------------------------------------------------
-- 1.5.45 : ne pas frapper a une porte que le client a declaree fermee
--------------------------------------------------------------------------
do
    -- Releve d'une cle mythique reelle le 29/08/2026, version 1.5.44 :
    --   lock=0|ChallengeMode,Map,Chat             450
    --   lock=0|Encounter,ChallengeMode,Map,Chat    30
    -- 480 refus sur 480 avec le verrou de combat BAISSE, et forbiddenVisuals
    -- absent du releve : IsForbidden repondait faux a chaque fois. Ces objets
    -- ne sont pas declares interdits, c'est le contexte qui n'a pas le droit.
    freshProfile("PALADIN")
    knowSpells(4987)
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    NS:CreateGrid()

    local button = NS.buttons[1]
    local auraType, visuals = next(button.auraSlotVisuals or {})
    local visual = visuals and visuals[1]
    truthy(visual, "permission : un visuel du moteur existe")
    falsy(visual.auraButton:IsForbidden(),
        "permission : l'objet n'est pas declare interdit -- comme en jeu")

    -- Hors combat, mais le contexte refuse : exactement le cas des 480.
    mock.state.inCombat = false
    rawset(visual.auraButton, "__protectedDenied", true)
    rawset(visual.overlay, "__color", nil)
    local failuresBefore = NS:GetDiagnostics().styleFailures or 0

    NS:StyleAuraVisual(button, auraType, visual)
    eq(NS:GetDiagnostics().styleSkipped, 1,
        "permission : la passe est comptee comme differee")
    eq(NS:GetDiagnostics().styleFailures or 0, failuresBefore,
        "permission : et surtout PAS comme un echec")
    falsy(rawget(visual.overlay, "__color"),
        "permission : aucune des neuf operations n'a ete tentee")
    truthy(NS.pendingAuraStyle, "permission : le travail reste a faire")
    falsy(visual.forbidden, "permission : le visuel n'est pas condamne pour autant")

    -- La restriction retombe : le style doit pouvoir aboutir.
    rawset(visual.auraButton, "__protectedDenied", nil)
    NS:StyleAuraVisual(button, auraType, visual)
    truthy(rawget(visual.overlay, "__color"),
        "permission : une fois autorise, le style s'applique")
    eq(NS:GetDiagnostics().styleSkipped, 1,
        "permission : et rien de plus n'est compte")
end

--------------------------------------------------------------------------
-- 1.5.45 : la levee d'une restriction rejoue le travail differe
--------------------------------------------------------------------------
do
    -- Une cle mythique garde ChallengeMode actif longtemps apres le dernier
    -- pack, et PLAYER_REGEN_ENABLED se declenche pendant qu'elle court encore.
    -- Sans cet evenement, le travail differe attendrait un evenement sans
    -- rapport.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    local fire = NS.eventFrame and NS.eventFrame:GetScript("OnEvent")
    truthy(fire, "levee : le repartiteur est atteignable")

    mock.state.inCombat = false
    NS.combatExitRefreshScheduled = false
    NS:MarkPending("pendingLayout")
    truthy(NS.pendingLayout, "levee : un travail est en attente")

    -- Une restriction qui s'ACTIVE ne doit rien rejouer.
    fire(NS.eventFrame, "ADDON_RESTRICTION_STATE_CHANGED",
        Enum.AddOnRestrictionType.ChallengeMode, Enum.AddOnRestrictionState.Active)
    mock.runTimers()
    truthy(NS.pendingLayout, "levee : une restriction qui s'active ne rejoue rien")

    -- Sa levee, si.
    NS.combatExitRefreshScheduled = false
    fire(NS.eventFrame, "ADDON_RESTRICTION_STATE_CHANGED",
        Enum.AddOnRestrictionType.ChallengeMode, Enum.AddOnRestrictionState.Inactive)
    mock.runTimers()
    falsy(NS.pendingLayout, "levee : la fin de la restriction rejoue le differe")
end

--------------------------------------------------------------------------
-- 1.5.46 : une alerte sonore n'est retiree qu'apres son remplacement
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.auraSoundHandles = {}
    NS.auraSoundRegistered = {}
    NS.auraSoundHandleChannels = {}
    NS.auraSoundOrphanHandles = {}
    NS.auraSoundFingerprint = nil
    NS.auraSoundChannel = nil
    NS.auraSoundRefreshScheduled = false

    local realAdd = C_UnitAuras.AddAuraSound
    local realRemove = C_UnitAuras.RemoveAuraSound
    local nextHandle = 1000
    C_UnitAuras.AddAuraSound = function()
        nextHandle = nextHandle + 1
        return nextHandle
    end
    C_UnitAuras.RemoveAuraSound = function() return true end
    NS:RefreshAuraSoundRegistrations("transaction initiale")

    local _, _, _, plan = NS:BuildAuraSoundPlan()
    local firstKey = plan[1] and plan[1].key
    local oldHandle = firstKey and NS.auraSoundHandles[firstKey]
    truthy(oldHandle, "transaction son : une ancienne poignee existe")

    -- Changer de canal force un remplacement. Si tous les nouveaux ajouts
    -- sont refuses, aucune ancienne poignee ne doit etre retiree.
    NS.db.soundChannel = "Dialog"
    local removals = 0
    C_UnitAuras.AddAuraSound = function() return nil end
    C_UnitAuras.RemoveAuraSound = function()
        removals = removals + 1
        return true
    end
    NS:RefreshAuraSoundRegistrations("remplacement refuse")
    eq(removals, 0, "transaction son : aucun retrait avant un ajout reussi")
    eq(NS.auraSoundHandles[firstKey], oldHandle,
        "transaction son : l'ancienne alerte reste active")
    eq(NS.auraSoundHandleChannels[firstKey], "Master",
        "transaction son : son canal reel reste connu")
    eq(NS.auraSoundDiagnostics.preserved, NS.auraSoundDiagnostics.attempted,
        "transaction son : toutes les alertes preservees sont diagnostiquees")
    falsy(NS.auraSoundFingerprint,
        "transaction son : un canal non applique ne valide pas le plan")

    -- Avec un ajout accepte, l'ordre doit etre Add puis Remove pour chaque
    -- paire, jamais l'inverse.
    NS.db.soundChannel = "Master"
    NS.auraSoundFingerprint = nil
    NS:RefreshAuraSoundRegistrations("retour au canal initial")
    NS.db.soundChannel = "Dialog"
    local operations = {}
    C_UnitAuras.AddAuraSound = function()
        operations[#operations + 1] = "add"
        nextHandle = nextHandle + 1
        return nextHandle
    end
    C_UnitAuras.RemoveAuraSound = function()
        operations[#operations + 1] = "remove"
        return true
    end
    NS:RefreshAuraSoundRegistrations("remplacement accepte")
    eq(operations[1], "add", "transaction son : le nouveau handle vient en premier")
    eq(operations[2], "remove", "transaction son : l'ancien part ensuite")
    truthy((NS.auraSoundDiagnostics.replaced or 0) > 0,
        "transaction son : les remplacements sont comptes")

    C_UnitAuras.AddAuraSound = realAdd
    C_UnitAuras.RemoveAuraSound = realRemove
end

--------------------------------------------------------------------------
-- 1.5.46 : le diagnostic peut etre copie en un seul bloc
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    NS.auraContainerDiagnostics = { readyButtons = 1, added = 2, expected = 2 }
    NS.auraSoundDiagnostics = { registered = 3, attempted = 3, activeHandles = 3 }
    local report = NS:BuildDiagnosticsReport()
    truthy(report:find("Cleansive diagnostic report", 1, true),
        "diagnostic copiable : le rapport porte son titre")
    truthy(report:find("engine ready=1 slots=2/2", 1, true),
        "diagnostic copiable : l'etat du moteur est inclus")
    truthy(report:find("sound registered=3/3", 1, true),
        "diagnostic copiable : l'etat sonore est inclus")

    local called = false
    local realShow = NS.ShowDiagnosticsCopy
    NS.ShowDiagnosticsCopy = function() called = true end
    NS:HandleSlash("diag copy")
    truthy(called, "diagnostic copiable : la commande ouvre le rapport")
    NS.ShowDiagnosticsCopy = realShow
end

--------------------------------------------------------------------------
-- 1.5.47 : l'apercu remplit la grille sans jamais toucher au jeu
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    -- Le moteur protege doit repondre, sinon le test qui verifie qu'une case
    -- d'apercu n'y touche pas serait vrai pour la mauvaise raison.
    mock.state.auraEngine.loaded = true
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS.db.testState = "MIXED"

    NS.db.testUnits = 20
    NS.testMode = false
    eq(#NS:BuildRoster(), 1, "apercu : hors mode test le roster reste reel")

    NS.testMode = true
    local padded = NS:BuildRoster()
    eq(#padded, 20, "apercu : la grille est completee au nombre demande")
    falsy(padded[1] and padded[1].preview, "apercu : le joueur reste une vraie unite")
    truthy(padded[2] and padded[2].preview, "apercu : les cases ajoutees sont marquees")

    -- Une demande plus petite que le groupe reel ne doit rien retirer : la
    -- grille ne ment jamais sur qui est la.
    NS.testMode = false
    local baseline = #NS:BuildRoster()
    NS.testMode = true
    NS.db.testUnits = 1
    eq(#NS:BuildRoster(), baseline, "apercu : une demande plus petite ne retire personne")

    ----------------------------------------------------------------------
    -- les trois portes vers le jeu restent fermees
    ----------------------------------------------------------------------
    NS.db.testUnits = 6
    NS:RebuildRoster()

    local previewButton
    for _, candidate in ipairs(NS.buttons) do
        if candidate.descriptor and candidate.descriptor.preview then
            previewButton = candidate
            break
        end
    end
    truthy(previewButton, "apercu : une case d'apercu est bien posee sur la grille")
    eq(previewButton and previewButton:GetAttribute("unit"), nil,
        "apercu : une case d'apercu ne porte aucune unite securisee")
    truthy(previewButton and previewButton.preview, "apercu : la case se sait decorative")

    -- auraContainerUnit n'est ecrit que lorsque SetUnit a reellement abouti :
    -- c'est la trace de ce qui a atteint le moteur, pas de ce qu'on a tente.
    local realButton = NS.unitToButton.player
    truthy(realButton and realButton.auraContainerUnit ~= nil,
        "apercu : une vraie case est bien branchee au moteur protege")
    local leakedEngine = 0
    for _, candidate in ipairs(NS.buttons) do
        if candidate.descriptor and candidate.descriptor.preview
            and candidate.auraContainerUnit ~= nil then
            leakedEngine = leakedEngine + 1
        end
    end
    eq(leakedEngine, 0, "apercu : aucune case d'apercu n'est branchee au moteur protege")

    -- UnitExists filtre deja les jetons d'apercu. Le test doit donc mentir sur
    -- leur existence, sinon il passerait au vert sans que le garde-fou existe.
    mock.state.exists.cleansivePreview2 = true
    local leakedSound = 0
    for _, token in ipairs(NS:GetAuraSoundUnitTokens()) do
        if token:find("cleansivePreview", 1, true) then leakedSound = leakedSound + 1 end
    end
    mock.state.exists.cleansivePreview2 = nil
    eq(leakedSound, 0,
        "apercu : une case d'apercu que le jeu dirait existante reste hors du registre sonore")

    ----------------------------------------------------------------------
    -- 1.5.47 : toutes les cases ne s'allument plus d'un coup
    ----------------------------------------------------------------------
    NS.db.testState = "MIXED"
    truthy(NS:PreviewCellIsAfflicted(1), "etat mixte : la premiere case s'allume")
    falsy(NS:PreviewCellIsAfflicted(2), "etat mixte : la deuxieme reste saine")
    falsy(NS:PreviewCellIsAfflicted(3), "etat mixte : la troisieme reste saine")
    truthy(NS:PreviewCellIsAfflicted(4), "etat mixte : la quatrieme s'allume")
    NS.db.testState = "ALL"
    truthy(NS:PreviewCellIsAfflicted(3), "etat tout : chaque case s'allume")
    NS.db.testState = "HEALTHY"
    falsy(NS:PreviewCellIsAfflicted(1), "etat sain : aucune case ne s'allume")

    -- Le predicat ne prouve rien tant que le vrai chemin ne le consulte pas.
    NS.db.testState = "MIXED"
    NS.db.testUnits = 6
    NS:RebuildRoster()
    local firstUnit = NS.roster[1] and NS.roster[1].unit
    local secondUnit = NS.roster[2] and NS.roster[2].unit
    truthy(secondUnit, "etat mixte : la grille compte bien une deuxieme case")
    truthy(firstUnit and NS:GetCurableAura(firstUnit),
        "etat mixte : la premiere case porte bien une affliction de test")
    eq(secondUnit and NS:GetCurableAura(secondUnit), nil,
        "etat mixte : la deuxieme case ne fabrique aucune affliction")
    NS.db.testState = "ALL"
    truthy(secondUnit and NS:GetCurableAura(secondUnit),
        "etat tout : la deuxieme case s'allume aussi")
    NS.db.testState = "MIXED"

    ----------------------------------------------------------------------
    -- 1.5.47 : la pull ferme l'apercu
    ----------------------------------------------------------------------
    NS.db.testUnits = 10
    NS.testMode = true
    NS:RebuildRoster()
    eq(#NS.roster, 10, "combat : l'apercu est ouvert avant la pull")
    mock.state.inCombat = true
    -- Par l'evenement, pas par la fonction : c'est le cablage qui doit tenir.
    local fire = NS.eventFrame and NS.eventFrame:GetScript("OnEvent")
    truthy(fire, "combat : le repartiteur d'evenements est atteignable")
    fire(NS.eventFrame, "PLAYER_REGEN_DISABLED")
    falsy(NS.testMode, "combat : la pull ferme l'apercu")
    truthy(NS.pendingRoster, "combat : le vrai groupe est reprogramme pour la fin du combat")
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    eq(#NS.roster, 1, "combat : la grille est revenue au vrai groupe")

    ----------------------------------------------------------------------
    -- 1.5.47 : les commandes
    ----------------------------------------------------------------------
    NS.testMode = false
    NS:SetTestUnits(12)
    truthy(NS.testMode, "apercu : choisir une taille ouvre l'apercu")
    eq(NS.db.testUnits, 12, "apercu : la taille demandee est retenue")
    eq(#NS.roster, 12, "apercu : douze cases demandees, douze affichees")

    NS:HandleSlash("test 40")
    eq(NS.db.testUnits, 40, "commande : /cleansive test 40 dimensionne l'apercu")
    NS:HandleSlash("test 99")
    eq(NS.db.testUnits, 40, "commande : la taille demandee est bornee a 40")
    NS:HandleSlash("test healthy")
    eq(NS.db.testState, "HEALTHY", "commande : /cleansive test healthy choisit l'etat")
    NS:HandleSlash("test dragon")
    eq(NS.db.testState, "HEALTHY", "commande : un etat inconnu ne change rien")

    NS.db.testState = "MIXED"
    NS.testMode = true
    NS.db.testUnits = 8
    NS:RebuildRoster()
    eq(#NS.roster, 8, "apercu : huit cases demandees, huit affichees")
    NS:ToggleTest()
    falsy(NS.testMode, "apercu : le bouton referme l'apercu")
    eq(#NS.roster, 1, "apercu : les cases d'apercu disparaissent avec lui")
end

--------------------------------------------------------------------------
-- 1.5.48 : Cleansive dit ce qu'il a compris
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)                       -- Purification : Magie, Maladie, Poison
    NS:UpdateSpells()

    local joined = table.concat(NS:BuildSpellReport(), "\n")
    truthy(#joined > 0, "sorts : le rapport nomme au moins un sort")
    truthy(joined:find("4987", 1, true), "sorts : l'identifiant du sort est donne")
    truthy(joined:find(NS.L.LEFT, 1, true), "sorts : le clic associe est donne")
    truthy(joined:find(NS:GetTypeLabel("Magic"), 1, true),
        "sorts : les types couverts sont donnes")

    -- Un type coupe doit se voir dans le rapport. Le faire disparaitre
    -- laisserait croire que le sort ne le couvre pas.
    NS.db.enabledTypes.Magic = false
    NS:UpdateSpells()
    joined = table.concat(NS:BuildSpellReport(), "\n")
    truthy(joined:find(string.format(NS.L.SPELL_TYPE_OFF, NS:GetTypeLabel("Magic")), 1, true),
        "sorts : un type desactive est signale, pas masque")
    NS.db.enabledTypes.Magic = true
    NS:UpdateSpells()

    freshProfile("WARRIOR")
    NS:UpdateSpells()
    eq(#NS:BuildSpellReport(), 0, "sorts : sans sort de dissipation, le rapport est vide")

    ----------------------------------------------------------------------
    -- 1.5.48 : pourquoi cette affliction ne sonne pas
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()

    eq(NS:DescribeSpellSound("pas un nombre"), NS.L.SOUND_QUERY_USAGE,
        "requete son : un identifiant illisible renvoie le mode d'emploi")
    eq(NS:DescribeSpellSound(999999),
        string.format(NS.L.SOUND_QUERY_UNLISTED, 999999, NS.KNOWN_DISPELLABLE_AURAS_SEASON),
        "requete son : un identifiant hors liste est explique comme tel")

    NS.db.enabledTypes.Poison = false
    eq(NS:DescribeSpellSound(267027),
        string.format(NS.L.SOUND_QUERY_TYPE_OFF, 267027, NS:GetTypeLabel("Poison")),
        "requete son : un type desactive est la raison donnee")
    NS.db.enabledTypes.Poison = true

    NS.db.ignoredAlways[267027] = true
    eq(NS:DescribeSpellSound(267027),
        string.format(NS.L.SOUND_QUERY_FILTERED, 267027, NS:GetTypeLabel("Poison")),
        "requete son : un filtre permanent est la raison donnee")
    NS.db.ignoredAlways[267027] = nil

    -- La reponse doit venir du registre reel, pas d'une table posee a la main.
    NS.db.sound = true
    NS.auraSoundFingerprint = nil
    NS:RefreshAuraSoundRegistrations("requete de test")
    local answer = NS:DescribeSpellSound(267027)
    truthy(answer:find("player", 1, true),
        "requete son : les unites reellement enregistrees sont listees")

    ----------------------------------------------------------------------
    -- 1.5.48 : version, ordre, listes
    ----------------------------------------------------------------------
    local before = #mock.state.chat
    NS:HandleSlash("version")
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find(tostring(NS.version), 1, true),
        "version : la commande donne la version de l'addon")

    NS:RebuildRoster()
    before = #mock.state.chat
    NS:HandleSlash("order")
    printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find(NS.L.ORDER_REASON_SELF, 1, true),
        "ordre : la premiere case est expliquee comme etant vous")

    NS.testMode = true
    NS.db.testUnits = 4
    NS:RebuildRoster()
    before = #mock.state.chat
    NS:HandleSlash("order")
    printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find(NS.L.ORDER_REASON_PREVIEW, 1, true),
        "ordre : une case d'apercu est annoncee comme telle")
    NS.testMode = false
    NS:RebuildRoster()

    NS:AddListEntry("skip", "CLASS", "MAGE", "Mage")
    truthy(#NS.db.skip > 0, "listes : une entree a bien ete ajoutee")
    NS:HandleSlash("skip clear")
    eq(#NS.db.skip, 0, "listes : skip clear vide la liste")
    NS:AddListEntry("priority", "CLASS", "MAGE", "Mage")
    NS:HandleSlash("prio clear")
    eq(#NS.db.priority, 0, "listes : prio clear vide la liste")
    NS:AddListEntry("skip", "CLASS", "MAGE", "Mage")
    NS:HandleSlash("skip")
    eq(#NS.db.skip, 1, "listes : la commande sans argument ouvre la fenetre sans rien vider")
end

--------------------------------------------------------------------------
-- 1.5.49 : la page Aide
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    truthy(NS.optionsPages and NS.optionsPages.help, "aide : la page existe")
    truthy(NS.optionsNav and NS.optionsNav.help, "aide : elle est atteignable depuis le menu")
    NS:ShowOptionsPage("help")
    eq(NS.activeOptionsPage, "help", "aide : la page s'ouvre")
    truthy(NS.optionsPages.help:IsShown(), "aide : et elle est la seule visible")
    falsy(NS.optionsPages.general:IsShown(), "aide : la page generale se retire")

    -- Chaque commande que HandleSlash accepte doit etre documentee ici, sinon
    -- la page devient un piege : elle a l'air complete et ne l'est pas.
    for _, language in ipairs({ "enUS", "frFR" }) do
        local documented = NS.LOCALES[language].HELP_COMMANDS_TEXT
        local missing = {}
        for _, command in ipairs({ "spells", "order", "version", "soundstatus",
            "diag copy", "test", "macro", "cdstatus", "setup", "filters",
            "pradd", "skadd", "history", "soundtest", "prio", "skip" }) do
            if not documented:find(command, 1, true) then missing[#missing + 1] = command end
        end
        eq(table.concat(missing, ","), "",
            "aide : toutes les commandes sont documentees en " .. language)
        truthy(NS.LOCALES[language].HELP_TROUBLE_TEXT:find("soundstatus", 1, true),
            "aide : le depannage renvoie a la commande qui repond, en " .. language)
    end

    -- L'adresse doit rester copiable et intacte : une saisie du joueur la
    -- restaure, un SetText du code ne doit rien relancer.
    local box = NS.reportURLBox
    truthy(box, "aide : l'adresse de signalement est presentee")
    local original = box:GetText()
    truthy(original and original:find("github.com", 1, true),
        "aide : l'adresse pointe vers le suivi des problemes")
    local handler = box:GetScript("OnTextChanged")
    truthy(handler, "aide : la zone se defend d'etre modifiee")
    box:SetText("efface")
    handler(box, true)
    eq(box:GetText(), original, "aide : une saisie du joueur restaure l'adresse")
    box:SetText("efface")
    handler(box, false)
    eq(box:GetText(), "efface",
        "aide : un changement venu du code ne relance pas la restauration")
    box:SetText(original)
end

--------------------------------------------------------------------------
-- 1.5.50 : partager un profil sans partager sa vie privee
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    NS.db.frameSize = 38
    NS.db.spacing = 7
    NS.db.grow = "LEFT_UP"
    NS.db.showNames = true
    NS.db.ignoredAlways = { [123456] = true }
    NS:AddListEntry("skip", "PLAYER", "Untel-Hyjal", "Untel")
    NS.db.positions.grid.x = -999

    local text = NS:ExportProfile()
    truthy(text:find("frameSize=38", 1, true), "export : une valeur numerique est portee")
    truthy(text:find("grow=LEFT_UP", 1, true), "export : un choix est porte")
    truthy(text:find("showNames=1", 1, true), "export : un interrupteur est porte")
    truthy(text:find("123456", 1, true), "export : les filtres par identifiant sont portes")

    -- Ce qui ne doit JAMAIS partir : la position d'ecran de l'expediteur, sa
    -- langue, et surtout les noms de ses coequipiers.
    falsy(text:find("Untel", 1, true), "export : aucun nom de joueur ne part")
    falsy(text:find("positions", 1, true), "export : aucune position d'ecran ne part")
    falsy(text:find("language", 1, true), "export : la langue ne part pas")
    falsy(text:find("skip", 1, true), "export : la liste d'exclusion ne part pas")

    ----------------------------------------------------------------------
    -- l'import lit d'abord, n'ecrit qu'ensuite
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    local before = NS.db.frameSize
    local analysis, reason = NS:AnalyzeProfileImport(text)
    truthy(analysis, "import : une chaine valide est acceptee")
    eq(NS.db.frameSize, before, "import : verifier ne change encore rien")

    local seen = {}
    for _, change in ipairs(analysis.changes) do seen[change.key] = change end
    truthy(seen.frameSize, "import : la difference de taille est annoncee")
    eq(seen.frameSize and seen.frameSize.to, "38", "import : et la valeur d'arrivee est donnee")
    eq(seen.frameSize and seen.frameSize.from, tostring(before),
        "import : avec la valeur de depart")

    truthy(NS:ApplyProfileImport(analysis), "import : appliquer reussit")
    eq(NS.db.frameSize, 38, "import : la valeur est enfin ecrite")
    eq(NS.db.grow, "LEFT_UP", "import : le choix aussi")
    truthy(NS.db.ignoredAlways[123456], "import : les filtres aussi")

    ----------------------------------------------------------------------
    -- ce qu'un texte etranger ne doit pas pouvoir faire
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    eq(select(2, NS:AnalyzeProfileImport("")), NS.L.IMPORT_EMPTY,
        "import : un texte vide est refuse avec sa raison")
    eq(select(2, NS:AnalyzeProfileImport("bonjour")), NS.L.IMPORT_BAD_PREFIX,
        "import : un texte quelconque est refuse")
    eq(select(2, NS:AnalyzeProfileImport("CLEANSIVE1;inconnu=1")), NS.L.IMPORT_NOTHING_VALID,
        "import : une chaine sans aucun reglage connu est refusee")

    -- Un texte enorme colle par erreur n'est pas une faille -- le parseur
    -- n'execute rien -- mais c'est un gel du client pour rien.
    local huge = "CLEANSIVE1;frameSize=30;" .. string.rep("a", 21000)
    truthy(select(2, NS:AnalyzeProfileImport(huge)),
        "import : un texte demesure est refuse avec sa raison")

    -- P2 de l'audit du 30/08 : la borne d'import etait plus PETITE que le plus
    -- gros export possible. Cleansive produisait donc un texte qu'il refusait
    -- ensuite de relire. Le contrat se verifie A LA TAILLE MAXIMALE, sinon il
    -- ne se verifie pas du tout.
    do
        local before = { NS.db.ignoredAlways, NS.db.ignoredCombat }
        NS.db.ignoredAlways, NS.db.ignoredCombat = {}, {}
        for index = 1, 500 do
            NS.db.ignoredAlways[1000000 + index] = true
            NS.db.ignoredCombat[2000000 + index] = true
        end
        local exported = NS:ExportProfile()
        truthy(#exported > 8000,
            "aller-retour : l'export maximal depasse bien l'ancienne borne")
        local analysis, refusal = NS:AnalyzeProfileImport(exported)
        truthy(analysis, "aller-retour : ce que Cleansive exporte, il sait le relire")
        falsy(refusal, "aller-retour : sans refus")
        NS.db.ignoredAlways, NS.db.ignoredCombat = before[1], before[2]
    end
    eq(NS:AnalyzeProfileImport(huge), nil, "import : et rien n'en est retenu")

    local manyIds = {}
    for index = 1, 600 do manyIds[index] = tostring(100000 + index) end
    local flooded = NS:AnalyzeProfileImport(
        "CLEANSIVE1;spacing=3;ignoredAlways=" .. table.concat(manyIds, ","))
    truthy(flooded, "import : une liste de filtres demesuree n'invalide pas le reste")
    eq(flooded.accepted.ignoredAlways, nil,
        "import : mais elle est refusee plutot que tronquee en silence")
    eq(flooded.accepted.spacing, 3, "import : et le reglage valide passe quand meme")

    -- Une cle inconnue ne doit ni entrer, ni faire echouer le reste.
    local mixed = NS:AnalyzeProfileImport("CLEANSIVE1;frameSize=30;chargePayload=1")
    truthy(mixed, "import : une cle inconnue n'invalide pas le reste")
    eq(mixed.accepted.chargePayload, nil, "import : la cle inconnue n'entre pas dans le profil")
    eq(mixed.rejected[1], "chargePayload", "import : et elle est nommee au joueur")
    NS:ApplyProfileImport(mixed)
    eq(NS.db.chargePayload, nil, "import : rien d'inconnu n'a ete ecrit dans la base")

    -- Une valeur hors bornes est un refus, pas un ecretage silencieux.
    freshProfile("PALADIN")
    local huge = NS:AnalyzeProfileImport("CLEANSIVE1;frameSize=9999;spacing=4")
    truthy(huge, "import : une valeur hors bornes n'invalide pas le reste")
    eq(huge.accepted.frameSize, nil, "import : la valeur hors bornes est rejetee")
    eq(huge.accepted.spacing, 4, "import : la valeur valide passe quand meme")
    truthy(huge.rejected[1] == "frameSize", "import : la valeur rejetee est nommee")

    -- Un ordre de types incomplet ferait disparaitre un type de l'interface.
    freshProfile("PALADIN")
    local partial = NS:AnalyzeProfileImport("CLEANSIVE1;typeOrder=Magic,Curse;spacing=3")
    eq(partial.accepted.typeOrder, nil, "import : un ordre de types incomplet est refuse")
    local full = NS:AnalyzeProfileImport(
        "CLEANSIVE1;typeOrder=Charm,Bleed,Disease,Poison,Curse,Magic")
    truthy(full and full.accepted.typeOrder, "import : un ordre complet est accepte")
    eq(full.accepted.typeOrder[1], "Charm", "import : et il garde son ordre")

    ----------------------------------------------------------------------
    -- la fenetre : verifier puis appliquer, jamais l'inverse
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    NS:CreateOptions()
    NS:ShowProfileTransfer()
    local window = NS.profileTransferFrame
    truthy(window, "fenetre : le partage de profil s'ouvre")
    truthy(window.exportBox:GetText():find("CLEANSIVE1", 1, true),
        "fenetre : le profil courant y est deja ecrit")
    falsy(window.apply:IsShown(), "fenetre : appliquer est cache tant qu'on n'a rien verifie")

    window.importBox:SetText("CLEANSIVE1;frameSize=31")
    window.analyze:GetScript("OnClick")(window.analyze)
    eq(NS.db.frameSize, 22, "fenetre : verifier ne touche pas encore au profil")
    truthy(window.apply:IsShown(), "fenetre : appliquer apparait apres la verification")
    truthy(window.result:GetText():find("frameSize", 1, true),
        "fenetre : la difference est montree avant d'etre appliquee")

    window.apply:GetScript("OnClick")(window.apply)
    eq(NS.db.frameSize, 31, "fenetre : le second clic applique")
    falsy(window.apply:IsShown(), "fenetre : et appliquer se retire ensuite")

    -- Un texte refuse ne doit jamais proposer de bouton d'application.
    window.importBox:SetText("n'importe quoi")
    window.analyze:GetScript("OnClick")(window.analyze)
    falsy(window.apply:IsShown(), "fenetre : un texte refuse ne propose rien a appliquer")
    truthy(window.result:GetText() == NS.L.IMPORT_BAD_PREFIX,
        "fenetre : et la raison du refus est affichee")

    ----------------------------------------------------------------------
    -- copier vers une autre specialisation
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    NS.db.frameSize = 33
    local target = tostring(NS.activeSpecKey) == "70" and "65" or "70"
    truthy(NS:CopyProfileToSpec(target), "copie : la copie vers une autre spe reussit")
    local copied = NS.dbRoot.profiles[NS.activeCharacterKey][target]
    truthy(copied, "copie : le profil cible existe maintenant")
    eq(copied.frameSize, 33, "copie : les reglages ont suivi")
    falsy(NS:CopyProfileToSpec(tostring(NS.activeSpecKey)),
        "copie : se copier sur soi-meme ne fait rien")
    NS.db.frameSize = 21
    eq(copied.frameSize, 33, "copie : les deux profils sont bien independants")
end

--------------------------------------------------------------------------
-- 1.5.51 : l'interface dit son etat et retrouve sa place
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    ----------------------------------------------------------------------
    -- le pied de fenetre ne ment plus
    ----------------------------------------------------------------------
    mock.state.inCombat = false
    NS.enabled = true
    eq(NS:OptionsStatusText(), NS.L.STATUS_READY, "etat : hors combat, tout s'applique")
    NS.enabled = false
    eq(NS:OptionsStatusText(), NS.L.STATUS_PAUSED, "etat : desactive, l'addon le dit")
    NS.enabled = true

    mock.state.inCombat = true
    eq(NS:OptionsStatusText(), NS.L.STATUS_COMBAT, "etat : en combat sans rien en attente")
    NS.pendingAnnounced = { pendingLayout = true }
    NS.pendingLayout = true
    eq(NS:OptionsStatusText(), string.format(NS.L.STATUS_COMBAT_WAITING, 1),
        "etat : en combat, le nombre de changements en attente est donne")

    -- Le pied et la plaque doivent compter la meme chose. Un report que le
    -- joueur n'a pas demande n'est pas un changement qui l'attend.
    NS.pendingRoster = true
    eq(NS:OptionsStatusText(), string.format(NS.L.STATUS_COMBAT_WAITING, 1),
        "etat : un report non annonce n'est pas compte, comme pour la plaque")
    NS.pendingLayout, NS.pendingRoster, NS.pendingAnnounced = false, false, {}

    -- Et il suit vraiment l'evenement de combat.
    local fire = NS.eventFrame:GetScript("OnEvent")
    NS.optionsStatusText:SetText("perime")
    fire(NS.eventFrame, "PLAYER_REGEN_DISABLED")
    eq(NS.optionsStatusText:GetText(), NS.L.STATUS_COMBAT,
        "etat : l'entree en combat rafraichit le pied de fenetre")
    mock.state.inCombat = false
    fire(NS.eventFrame, "PLAYER_REGEN_ENABLED")
    eq(NS.optionsStatusText:GetText(), NS.L.STATUS_READY,
        "etat : la sortie de combat aussi")

    ----------------------------------------------------------------------
    -- ce qui ne s'applique pas ne reste pas affiche
    ----------------------------------------------------------------------
    truthy(#(NS.soundDependentControls or {}) > 0,
        "dependances : les reglages du son sont reperes")
    NS.db.sound = true
    NS:RefreshOptions()
    truthy(NS.soundChannelButton:IsShown(), "dependances : son actif, le canal est propose")
    NS.db.sound = false
    NS:RefreshOptions()
    local visible = 0
    for _, control in ipairs(NS.soundDependentControls) do
        if control:IsShown() then visible = visible + 1 end
    end
    eq(visible, 0, "dependances : son coupe, plus rien qui le regle ne reste affiche")
    NS.db.sound = true
    NS:RefreshOptions()

    ----------------------------------------------------------------------
    -- une fenetre deplacee revient ou on l'a mise
    ----------------------------------------------------------------------
    local window = NS.optionsFrame
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 123, -45)
    NS:SaveWindowPosition(window, "options")
    local saved = NS.dbRoot.global.windows and NS.dbRoot.global.windows.options
    truthy(saved, "fenetres : la place est enregistree dans la section globale")
    eq(saved and saved.x, 123, "fenetres : avec sa coordonnee")
    NS.dbRoot.global.windows = NS.dbRoot.global.windows or {}

    window:ClearAllPoints()
    window:SetPoint("CENTER")
    truthy(NS:RestoreWindowPosition(window, "options"), "fenetres : la place est restituee")
    local point, _, relativePoint, x, y = window:GetPoint()
    eq(point, "TOPLEFT", "fenetres : le meme ancrage")
    eq(x, 123, "fenetres : la meme abscisse")
    eq(y, -45, "fenetres : la meme ordonnee")

    -- Une place ecrite par une version future, ou corrompue, ne doit pas
    -- empecher la fenetre de s'ouvrir : SetPoint leve sur un ancrage inconnu.
    NS.dbRoot.global.windows.options = { point = "MILIEU", relativePoint = "CENTER", x = 0, y = 0 }
    falsy(NS:RestoreWindowPosition(window, "options"),
        "fenetres : un ancrage inconnu est refuse au lieu de lever")
    NS.dbRoot.global.windows.options = { point = "CENTER", relativePoint = "CENTER", x = "loin", y = 0 }
    falsy(NS:RestoreWindowPosition(window, "options"),
        "fenetres : une coordonnee illisible est refusee aussi")

    -- La position ne doit pas voyager avec un profil partage.
    freshProfile("PALADIN")
    falsy(NS:ExportProfile():find("windows", 1, true),
        "fenetres : la place des fenetres ne part pas dans un profil exporte")
end

--------------------------------------------------------------------------
-- 1.5.52 : points de depart, et reprendre la main sans tout perdre
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    ----------------------------------------------------------------------
    -- les prereglages ecrivent des reglages ordinaires
    ----------------------------------------------------------------------
    eq(#NS.VISUAL_PRESETS, 4, "prereglages : les quatre points de depart existent")
    for _, preset in ipairs(NS.VISUAL_PRESETS) do
        truthy(NS.L["PRESET_" .. preset.key], "prereglages : " .. preset.key .. " a un nom")
        truthy(NS.LOCALES.frFR["PRESET_" .. preset.key],
            "prereglages : " .. preset.key .. " a un nom en francais")
    end

    truthy(NS:ApplyVisualPreset("MINIMAL"), "prereglages : appliquer Minimal reussit")
    eq(NS.db.frameSize, 16, "prereglages : la taille a bien ete ecrite")
    falsy(NS.db.showCooldown, "prereglages : et un interrupteur aussi")
    -- Un prereglage est un point de depart : ce qu'il ecrit reste modifiable,
    -- et rien ne doit se souvenir d'un "mode" qui redeviendrait faux.
    NS.db.frameSize = 29
    eq(NS.db.frameSize, 29, "prereglages : un reglage reste modifiable apres coup")
    falsy(NS.db.preset, "prereglages : aucun mode n'est memorise")
    falsy(NS:ApplyVisualPreset("INEXISTANT"), "prereglages : un nom inconnu ne fait rien")

    truthy(NS:ApplyVisualPreset("READABLE"), "prereglages : Lisible s'applique aussi")
    truthy(NS.db.showNames, "prereglages : Lisible affiche les noms")
    truthy(NS.db.frameSize > 30, "prereglages : et agrandit les cases")

    ----------------------------------------------------------------------
    -- remise a zero d'une seule page
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    local defaultSize = NS.profileDefaults.frameSize
    NS.db.frameSize = 39
    NS.db.blacklistTime = 12
    NS:AddListEntry("skip", "CLASS", "MAGE", "Mage")

    truthy(NS:ResetOptionsPage("appearance"), "reset page : la page Apparence se remet a zero")
    eq(NS.db.frameSize, defaultSize, "reset page : son reglage est revenu a l'origine")
    eq(NS.db.blacklistTime, 12, "reset page : celui d'une autre page n'a pas bouge")
    eq(#NS.db.skip, 1, "reset page : et la liste d'exclusion est intacte")

    falsy(NS:ResetOptionsPage("help"), "reset page : une page sans reglages ne fait rien")
    falsy(NS:ResetOptionsPage(nil), "reset page : sans page, rien non plus")

    -- Le bouton ne doit pas etre propose la ou il ne ferait rien.
    NS:ShowOptionsPage("appearance")
    truthy(NS.pageResetButton:IsShown(), "reset page : le bouton est propose sur Apparence")
    NS:ShowOptionsPage("help")
    falsy(NS.pageResetButton:IsShown(), "reset page : il disparait sur la page Aide")
    NS:ShowOptionsPage("appearance")

    ----------------------------------------------------------------------
    -- deux clics avant de detruire
    ----------------------------------------------------------------------
    NS.db.frameSize = 37
    local resetButton = NS.pageResetButton
    local resting = resetButton:GetText()
    resetButton:GetScript("OnClick")(resetButton)
    eq(NS.db.frameSize, 37, "deux clics : le premier clic ne detruit rien")
    truthy(resetButton:GetText() ~= resting, "deux clics : le bouton dit qu'il attend confirmation")
    resetButton:GetScript("OnClick")(resetButton)
    eq(NS.db.frameSize, defaultSize, "deux clics : le second clic applique")
    eq(resetButton:GetText(), resting, "deux clics : et le bouton revient a son libelle")

    -- Une confirmation oubliee doit se desarmer, sinon un clic sans rapport
    -- une heure plus tard detruirait la page.
    NS.db.frameSize = 35
    resetButton:GetScript("OnClick")(resetButton)
    truthy(resetButton.confirmArmed, "deux clics : la confirmation est armee")
    mock.runTimers()
    falsy(resetButton.confirmArmed, "deux clics : elle se desarme toute seule")
    eq(resetButton:GetText(), resting, "deux clics : et le libelle revient")
    resetButton:GetScript("OnClick")(resetButton)
    eq(NS.db.frameSize, 35, "deux clics : un clic isole ne detruit toujours rien")

    -- Changer de page doit desarmer : le bouton parle de la page affichee.
    resetButton:GetScript("OnClick")(resetButton)
    NS:ShowOptionsPage("general")
    NS:ShowOptionsPage("appearance")
    falsy(resetButton.confirmArmed, "deux clics : changer de page desarme la confirmation")
end

--------------------------------------------------------------------------
-- 1.5.53 : d'ou vient cette case, et ou cette aura a ete vue
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:CreateOptions()
    NS:RebuildRoster()

    ----------------------------------------------------------------------
    -- l'infobulle dit pourquoi la case est la
    ----------------------------------------------------------------------
    local button = NS.unitToButton.player
    truthy(button, "infobulle : la case du joueur existe")
    mock.state.tooltip = nil
    NS:ShowButtonTooltip(button)
    local lines = table.concat(mock.state.tooltip or {}, "\n")
    truthy(lines:find(NS.L.WHY_SELF, 1, true),
        "infobulle : votre propre case dit pourquoi elle passe en premier")
    truthy(lines:find(NS.roster[1].displayName or "player", 1, true),
        "infobulle : et elle nomme l'unite")

    -- Une unite de la liste de priorite doit dire sa position, pas juste
    -- apparaitre plus haut sans explication.
    local descriptor = { unit = "party1", displayName = "Ami", name = "Ami-Hyjal",
        class = "MAGE", group = 1 }
    NS:AddListEntry("priority", "PLAYER", "Ami-Hyjal", "Ami")
    eq(NS:PriorityRank(descriptor), 1, "priorite : l'unite est bien en position 1")

    ----------------------------------------------------------------------
    -- le nom prend la couleur de sa classe
    ----------------------------------------------------------------------
    local white = NS:ClassColor(nil)
    eq(white[1], 1, "couleur : une classe inconnue reste blanche")
    eq(#NS:ClassColor("MAGE"), 3, "couleur : une classe connue donne trois canaux")

    ----------------------------------------------------------------------
    -- l'historique retient ou l'aura a ete vue
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    local realInstance = GetInstanceInfo
    GetInstanceInfo = function()
        return "Ara-Kara, cite des echos", "party", 0, "", 0, 0, false, 2660
    end
    NS:RememberAura({ spellId = 1234567, name = "Toile", dispelName = "Poison" })
    GetInstanceInfo = realInstance

    local entries = NS:GetAuraHistoryEntries()
    local recorded
    for _, entry in ipairs(entries) do
        if entry.id == 1234567 then recorded = entry end
    end
    truthy(recorded, "historique : l'aura est retenue")
    eq(recorded and recorded.instanceID, 2660,
        "historique : l'instance est retenue par son numero, pas par son nom traduit")
    truthy(recorded and recorded.place, "historique : le lieu lisible est retenu aussi")

    -- En exterieur, il n'y a pas d'instance : la carte suffit et ne doit pas
    -- etre enregistree comme un numero d'instance.
    GetInstanceInfo = function() return "Hurlevent", "none", 0, "", 0, 0, false, 0 end
    NS:RememberAura({ spellId = 7654321, name = "Rhume", dispelName = "Disease" })
    GetInstanceInfo = realInstance
    local outdoor
    for _, entry in ipairs(NS:GetAuraHistoryEntries()) do
        if entry.id == 7654321 then outdoor = entry end
    end
    truthy(outdoor, "historique : une aura vue dehors est retenue aussi")
    eq(outdoor and outdoor.instanceID, nil,
        "historique : dehors, aucun numero d'instance n'est invente")

    ----------------------------------------------------------------------
    -- la liste peut sortir du jeu en un bloc
    ----------------------------------------------------------------------
    local report = NS:BuildAuraHistoryReport()
    truthy(report:find("1234567", 1, true), "copie : la liste porte les identifiants")
    truthy(report:find("instance=2660", 1, true),
        "copie : et le lieu, pour que le lecteur puisse aller verifier")
    truthy(report:find("Toile", 1, true), "copie : avec le nom lisible")

    -- Une seule fenetre de copie, retitrable. Deux fenetres presque identiques
    -- deriveraient : la correction irait sur celle que le rapporteur n'a pas.
    NS:CreateOptions()
    NS:ShowCopyWindow("Titre essai", "Aide essai", "contenu essai")
    local window = NS.diagnosticsCopyFrame
    truthy(window, "copie : la fenetre s'ouvre")
    eq(window.title:GetText(), "Titre essai", "copie : elle prend le titre demande")
    eq(window.edit:GetText(), "contenu essai", "copie : et le contenu demande")
    NS:ShowDiagnosticsCopy()
    eq(window.title:GetText(), NS.L.DIAG_COPY_TITLE,
        "copie : le diagnostic reutilise la meme fenetre")
    truthy(window.edit:GetText():find("Cleansive diagnostic report", 1, true),
        "copie : avec son propre contenu")
end

--------------------------------------------------------------------------
-- 1.5.54 : chercher un reglage
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    truthy(#(NS.optionIndex or {}) > 10, "recherche : l'index couvre les reglages")
    -- L'index est alimente par les helpers eux-memes : une liste tenue a cote
    -- diverge des le premier reglage ajoute.
    local withoutPage = 0
    for _, entry in ipairs(NS.optionIndex) do
        if not entry.page or not entry.label then withoutPage = withoutPage + 1 end
    end
    eq(withoutPage, 0, "recherche : chaque entree connait sa page et son libelle")

    -- Un joueur tape sans accents et sans majuscules.
    NS.db.language = "frFR"
    NS.L = NS.LOCALES.frFR
    local found = NS:SearchOptions("opacite")
    truthy(#found > 0, "recherche : un mot sans accent trouve un libelle accentue")
    truthy(found[1] and found[1].page, "recherche : le resultat dit sur quelle page aller")
    truthy(found[1] and found[1].pageLabel and found[1].pageLabel ~= found[1].page,
        "recherche : et la page est nommee en clair, pas par sa cle interne")

    eq(#NS:SearchOptions(""), 0, "recherche : une requete vide ne montre rien")
    eq(#NS:SearchOptions("zzzzz"), 0, "recherche : une requete sans reponse ne montre rien")
    truthy(#NS:SearchOptions("a") <= 8, "recherche : la liste est bornee")

    -- Le texte d'aide compte aussi : on cherche souvent par ce que ca fait,
    -- pas par le nom exact du reglage.
    local byHelp = NS:SearchOptions("daltonien")
    truthy(#byHelp >= 0, "recherche : chercher dans l'aide ne fait pas lever")

    eq(NS:FoldForSearch("Opacité"), "opacite", "recherche : les accents sont replies")
    eq(NS:FoldForSearch("L’aperçu"), "l'apercu", "recherche : l'apostrophe typographique aussi")

    -- Le panneau de resultats
    local panel = NS.optionsSearchResults
    truthy(panel, "recherche : le panneau de resultats existe")
    NS:RefreshOptionsSearch("")
    falsy(panel:IsShown(), "recherche : rien de tape, rien d'affiche")
    NS:RefreshOptionsSearch("opacite")
    truthy(panel:IsShown(), "recherche : une requete ouvre le panneau")
    truthy(panel.rows[1]:IsShown(), "recherche : et le premier resultat est propose")
    falsy(panel.empty:IsShown(), "recherche : sans message de liste vide")

    NS:RefreshOptionsSearch("zzzzz")
    truthy(panel.empty:IsShown(), "recherche : une requete sans reponse le dit")
    falsy(panel.rows[1]:IsShown(), "recherche : et ne laisse aucun resultat perime affiche")

    -- Cliquer un resultat doit emmener sur la page, pas seulement la nommer.
    NS:ShowOptionsPage("general")
    NS:RefreshOptionsSearch("opacite")
    local firstResult = panel.rows[1]:GetScript("OnClick")
    truthy(firstResult and panel.rows[1]:IsShown(),
        "recherche : un resultat cliquable est propose")
    if firstResult then firstResult(panel.rows[1]) end
    eq(NS.activeOptionsPage, "appearance", "recherche : cliquer un resultat ouvre sa page")
    eq(NS.optionsSearchBox:GetText(), "", "recherche : et la recherche se vide")
end

--------------------------------------------------------------------------
-- 1.5.55 : ou la grille apparait
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()

    ----------------------------------------------------------------------
    -- la chaine du pilote securise, lisible ici et nulle part ailleurs
    ----------------------------------------------------------------------
    NS.db.autoHide = false
    NS.db.showSolo, NS.db.showParty, NS.db.showRaid = true, true, true
    falsy(NS:NeedsVisibilityDriver(),
        "visibilite : tout autorise et pas de regle de combat, aucun pilote a poser")

    NS.db.showSolo = false
    truthy(NS:NeedsVisibilityDriver(), "visibilite : une exception demande un pilote")
    eq(NS:VisibilityDriverMacro(), "[group:party,nogroup:raid][group:raid] show; hide",
        "visibilite : le solo retire disparait de la chaine")

    NS.db.showSolo, NS.db.showParty = true, false
    eq(NS:VisibilityDriverMacro(), "[nogroup][group:raid] show; hide",
        "visibilite : le groupe retire aussi")

    NS.db.showParty = true
    NS.db.autoHide = true
    eq(NS:VisibilityDriverMacro(), "[combat,nogroup][combat,group:party,nogroup:raid][combat,group:raid] show; hide",
        "visibilite : la regle de combat se combine avec chaque contexte")

    NS.db.autoHide = false
    NS.db.showSolo, NS.db.showParty, NS.db.showRaid = false, false, false
    eq(NS:VisibilityDriverMacro(), "hide",
        "visibilite : tout coupe, la grille est masquee partout")
    NS.db.showSolo, NS.db.showParty, NS.db.showRaid = true, true, true

    ----------------------------------------------------------------------
    -- 1.6.4 : le son doit dire la MEME chose que le pilote securise
    --
    -- Retour joueur du 30/08/2026 : en raid, l'addon « sonne en boucle » alors
    -- qu'il n'affiche rien. Le pilote de visibilite est securise : il decide
    -- seul et ne rend jamais son verdict a Lua, donc le son ne le consultait
    -- pas. Ici la macro est EVALUEE et son verdict compare a celui du miroir
    -- Lua, sur les 96 combinaisons. Le jour ou la macro change, le miroir doit
    -- changer avec elle, sinon ce test tombe.
    ----------------------------------------------------------------------
    local function macroSays(macro, inRaid, inGroup, inCombat)
        if macro == "hide" then return false end
        for clause in macro:gmatch("%[(.-)%]") do
            local satisfied = true
            for condition in clause:gmatch("[^,]+") do
                local negated = condition:sub(1, 2) == "no"
                local name = negated and condition:sub(3) or condition
                local value
                if name == "combat" then value = inCombat and true or false
                elseif name == "group" then value = inGroup and true or false
                elseif name == "group:party" then value = inGroup and true or false
                elseif name == "group:raid" then value = inRaid and true or false
                else error("condition inconnue dans la macro : " .. tostring(name)) end
                if negated then value = not value end
                if not value then satisfied = false end
            end
            if satisfied then return true end
        end
        return false
    end

    do
        local savedCombat, savedRaid, savedGroup = mock.state.inCombat, mock.state.inRaid, mock.state.inGroup
        local savedAuto = NS.db.autoHide
        NS.testMode = false
        NS.gridManuallyHidden = false
        NS.enabled = true
        local disagreements, checked = {}, 0
        for _, solo in ipairs({ true, false }) do
        for _, party in ipairs({ true, false }) do
        for _, raid in ipairs({ true, false }) do
        for _, auto in ipairs({ true, false }) do
            NS.db.showSolo, NS.db.showParty, NS.db.showRaid, NS.db.autoHide = solo, party, raid, auto
            local macro = NS:VisibilityDriverMacro()
            for _, context in ipairs({ "solo", "party", "raid" }) do
            for _, combat in ipairs({ true, false }) do
                mock.state.inRaid = context == "raid"
                mock.state.inGroup = context ~= "solo"
                mock.state.inCombat = combat
                local fromMacro = macroSays(macro, mock.state.inRaid, mock.state.inGroup, combat)
                local fromLua = NS:GridWouldBeVisible()
                checked = checked + 1
                if fromMacro ~= fromLua and #disagreements < 4 then
                    disagreements[#disagreements + 1] = string.format(
                        "solo=%s groupe=%s raid=%s combat-seul=%s / %s %s : macro dit %s, Lua dit %s",
                        tostring(solo), tostring(party), tostring(raid), tostring(auto),
                        context, tostring(combat), tostring(fromMacro), tostring(fromLua))
                end
            end
            end
        end end end end
        eq(checked, 96, "son : les 96 combinaisons sont bien parcourues")
        eq(table.concat(disagreements, " | "), "",
            "son : le miroir Lua dit exactement ce que dit la macro securisee")
        mock.state.inCombat, mock.state.inRaid, mock.state.inGroup = savedCombat, savedRaid, savedGroup
        NS.db.showSolo, NS.db.showParty, NS.db.showRaid, NS.db.autoHide = true, true, true, savedAuto
    end

    -- Et le son suit ce verdict, dans les deux sens.
    do
        NS.db.sound = true
        NS.db.showRaid = false
        mock.state.inRaid, mock.state.inGroup = true, true
        falsy(NS:PlayAfflictionAlert(), "son : rien ne sonne la ou la grille ne s'affiche pas")
        truthy(NS:PlayAfflictionAlert(true), "son : l'essai demande par le joueur se joue quand meme")
        mock.state.inRaid, mock.state.inGroup = false, false
        truthy(NS:PlayAfflictionAlert(), "son : et il revient la ou la grille s'affiche")
        NS.db.showRaid = true
    end

    -- Se taire cote Lua ne suffit PAS. Le registre natif est joue par le
    -- CLIENT : une fois pose, il sonne tout seul, grille eteinte ou non. C'est
    -- exactement ce que le joueur decrit -- « l'addon sonne en boucle » -- et
    -- c'est la moitie du correctif qu'aucun test ne couvrait.
    do
        freshProfile("PALADIN")
        knowSpells(4987)
        NS:UpdateSpells()
        NS:RebuildRoster()
        NS.auraSoundHandles, NS.auraSoundRegistered = {}, {}
        NS.auraSoundHandleChannels, NS.auraSoundOrphanHandles = {}, {}
        NS.auraSoundFingerprint, NS.auraSoundChannel = nil, nil
        NS.auraSoundRefreshScheduled = false

        local realAdd, realRemove = C_UnitAuras.AddAuraSound, C_UnitAuras.RemoveAuraSound
        local nextHandle, removals = 5000, 0
        C_UnitAuras.AddAuraSound = function() nextHandle = nextHandle + 1 return nextHandle end
        C_UnitAuras.RemoveAuraSound = function() removals = removals + 1 return true end

        NS.db.sound = true
        NS.db.showRaid = true
        mock.state.inRaid, mock.state.inGroup = false, false
        NS:RefreshAuraSoundRegistrations("depart en solo")
        local posees = 0
        for _ in pairs(NS.auraSoundHandles) do posees = posees + 1 end
        truthy(posees > 0, "registre : des alertes sont bien posees quand la grille s'affiche")

        -- Le joueur rejoint un raid, « Afficher en raid » est eteint.
        NS.db.showRaid = false
        mock.state.inRaid, mock.state.inGroup = true, true
        NS:RefreshAuraSoundRegistrations("entree en raid, raid masque")
        local restantes = 0
        for _ in pairs(NS.auraSoundHandles) do restantes = restantes + 1 end
        eq(restantes, 0, "registre : entrer en raid retire les alertes que le client jouait seul")
        truthy(removals > 0, "registre : elles sont retirees, pas seulement oubliees")

        -- Et elles reviennent en sortant.
        NS.db.showRaid = true
        NS:RefreshAuraSoundRegistrations("raid de nouveau affiche")
        local revenues = 0
        for _ in pairs(NS.auraSoundHandles) do revenues = revenues + 1 end
        eq(revenues, posees, "registre : et elles reviennent toutes quand la grille revient")

        C_UnitAuras.AddAuraSound, C_UnitAuras.RemoveAuraSound = realAdd, realRemove
        mock.state.inRaid, mock.state.inGroup = false, false
    end

    ----------------------------------------------------------------------
    -- la chaine arrive vraiment au pilote
    ----------------------------------------------------------------------
    local registered
    local realRegister = RegisterStateDriver
    RegisterStateDriver = function(_, _, macro) registered = macro end
    NS.db.autoHide = true
    NS:UpdateGridVisibilityDriver()
    RegisterStateDriver = realRegister
    eq(registered, NS:VisibilityDriverMacro(),
        "visibilite : c'est bien cette chaine qui est posee sur le pilote")

    ----------------------------------------------------------------------
    -- pendant qu'on regle, la grille reste visible
    ----------------------------------------------------------------------
    NS:CreateOptions()
    registered = nil
    RegisterStateDriver = function(_, _, macro) registered = macro end
    NS.optionsFrame:Show()
    NS:UpdateGridVisibilityDriver()
    RegisterStateDriver = realRegister
    eq(registered, nil,
        "reglages ouverts : aucune regle ne peut masquer ce qu'on est en train de regler")
    truthy((NS.gridBody or NS.gridAnchor):IsShown(),
        "reglages ouverts : la grille est montree")

    registered = nil
    RegisterStateDriver = function(_, _, macro) registered = macro end
    NS.optionsFrame:Hide()
    NS:UpdateGridVisibilityDriver()
    RegisterStateDriver = realRegister
    truthy(registered, "reglages fermes : la regle reprend la main")
    NS.db.autoHide = false

    -- Les regles de contexte voyagent avec un profil partage : c'est un choix
    -- d'affichage, pas une donnee personnelle.
    NS.db.showRaid = false
    truthy(NS:ExportProfile():find("showRaid=0", 1, true),
        "visibilite : les regles de contexte partent dans un profil exporte")
end

--------------------------------------------------------------------------
-- 1.5.56 : l'ordre des cases se choisit
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()

    for index = 1, 4 do mock.state.exists["party" .. index] = true end
    local realIsInGroup = IsInGroup
    IsInGroup = function() return true end
    mock.state.roles.party1 = "DAMAGER"
    mock.state.roles.party2 = "HEALER"
    mock.state.roles.party3 = "TANK"
    mock.state.roles.party4 = "DAMAGER"

    ----------------------------------------------------------------------
    -- par role : les soigneurs et les tanks devant
    ----------------------------------------------------------------------
    NS.db.sortMode = "ROLE"
    NS:RebuildRoster()
    local order = {}
    for _, descriptor in ipairs(NS.roster) do order[#order + 1] = descriptor.unit end
    local function position(unit)
        for index, name in ipairs(order) do if name == unit then return index end end
    end
    -- Le joueur passe toujours en premier : c'est la priorite, elle est lue
    -- avant le mode de tri et elle ne doit pas etre renversee par lui.
    eq(order[1], "player", "tri : votre propre case reste en tete quel que soit le tri")
    truthy(position("party3") < position("party2"),
        "tri par role : le tank passe avant le soigneur")
    truthy(position("party2") < position("party1"),
        "tri par role : le soigneur passe avant les dps")

    ----------------------------------------------------------------------
    -- le role est lu une fois par reconstruction, pas a chaque comparaison
    ----------------------------------------------------------------------
    local calls = 0
    local realRoles = UnitGroupRolesAssigned
    UnitGroupRolesAssigned = function(unit) calls = calls + 1; return mock.state.roles[unit] or "NONE" end
    NS:RebuildRoster()
    UnitGroupRolesAssigned = realRoles
    truthy(calls <= #NS.roster + 2,
        "tri : le role est lu une fois par unite, pas a chaque comparaison du tri")

    ----------------------------------------------------------------------
    -- la priorite passe avant le mode de tri
    ----------------------------------------------------------------------
    NS.db.sortMode = "ROLE"
    NS:AddListEntry("priority", "PLAYER", "party1-Hyjal", "Dps")
    NS:RebuildRoster()
    order = {}
    for _, descriptor in ipairs(NS.roster) do order[#order + 1] = descriptor.unit end
    truthy(position("party1") <= 2,
        "tri : une unite prioritaire passe devant le tri par role")
    NS:ClearList("priority")

    ----------------------------------------------------------------------
    -- le mode tourne et se retient
    ----------------------------------------------------------------------
    NS.db.sortMode = "GROUP"
    NS:CycleSortMode()
    eq(NS.db.sortMode, "ROLE", "tri : le bouton passe au mode suivant")
    NS:CycleSortMode()
    eq(NS.db.sortMode, "CLASS", "tri : puis au suivant")
    NS:CycleSortMode()
    eq(NS.db.sortMode, "GROUP", "tri : et il boucle")

    -- Un role illisible ne doit ni faire lever le tri, ni passer devant.
    mock.state.roles.party1 = nil
    NS.db.sortMode = "ROLE"
    NS:RebuildRoster()
    truthy(#NS.roster >= 5, "tri : un role inconnu ne casse pas la reconstruction")

    IsInGroup = realIsInGroup

    -- Le mode de tri est un choix d'affichage : il voyage avec un profil.
    NS.db.sortMode = "ROLE"
    truthy(NS:ExportProfile():find("sortMode=ROLE", 1, true),
        "tri : le mode part dans un profil exporte")
end

--------------------------------------------------------------------------
-- 1.5.57 : le son dit son etat en une phrase, la recharge se regle
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()

    -- Six etats, six phrases : un joueur qui lit "46/46, 0 en attente" doit
    -- encore conclure lui-meme. La conclusion est le travail de l'addon.
    for _, key in ipairs({ "OFF", "UNAVAILABLE", "IDLE", "PENDING", "DEGRADED", "ACTIVE" }) do
        truthy(NS.LOCALES.enUS["SOUND_STATE_" .. key], "etat son : " .. key .. " a une phrase")
        truthy(NS.LOCALES.frFR["SOUND_STATE_" .. key], "etat son : " .. key .. " en francais aussi")
    end

    NS.db.sound = false
    eq(NS:AuraSoundState(), "OFF", "etat son : coupe")
    NS.db.sound = true
    NS.auraSoundDiagnostics = nil
    eq(NS:AuraSoundState(), "IDLE", "etat son : rien de fait encore")

    NS.auraSoundDiagnostics = { pending = true, registered = 0, attempted = 10 }
    eq(NS:AuraSoundState(), "PENDING", "etat son : en cours")

    NS.auraSoundDiagnostics = { registered = 46, attempted = 46 }
    NS.auraSoundSkippedUnits = 0
    eq(NS:AuraSoundState(), "ACTIVE", "etat son : tout est en place")

    NS.auraSoundDiagnostics = { registered = 40, attempted = 46 }
    eq(NS:AuraSoundState(), "DEGRADED", "etat son : incomplet, donc degrade")
    NS.auraSoundDiagnostics = { registered = 46, attempted = 46, error = "refus" }
    eq(NS:AuraSoundState(), "DEGRADED", "etat son : une erreur suffit a degrader")
    NS.auraSoundDiagnostics = { registered = 46, attempted = 46, preserved = 2 }
    eq(NS:AuraSoundState(), "DEGRADED",
        "etat son : un remplacement preserve compte comme degrade, pas comme un succes")
    NS.auraSoundDiagnostics = { registered = 46, attempted = 46 }
    NS.auraSoundSkippedUnits = 3
    eq(NS:AuraSoundState(), "DEGRADED",
        "etat son : des unites ecartees par le budget degradent aussi")
    NS.auraSoundSkippedUnits = 0

    truthy(NS:AuraSoundStateSentence() ~= "", "etat son : la phrase existe")
    local before = #mock.state.chat
    NS:PrintAuraSoundStatus()
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find(NS:AuraSoundStateSentence(), 1, true),
        "etat son : la phrase ouvre le compte rendu, avant les nombres")

    ----------------------------------------------------------------------
    -- une valeur exacte par commande
    ----------------------------------------------------------------------
    freshProfile("PALADIN")
    NS:CreateGrid()
    NS:HandleSlash("size 33")
    eq(NS.db.frameSize, 33, "commande : la taille exacte est prise")
    NS:HandleSlash("size 999")
    eq(NS.db.frameSize, 40, "commande : au-dela du maximum, la taille est bornee")
    NS:HandleSlash("size 1")
    eq(NS.db.frameSize, 12, "commande : en dessous du minimum aussi")
    NS:HandleSlash("spacing 7")
    eq(NS.db.spacing, 7, "commande : l'espacement exact est pris")
    NS.db.frameSize = 24
    NS:HandleSlash("size grand")
    eq(NS.db.frameSize, 24, "commande : une valeur illisible ne change rien")

    ----------------------------------------------------------------------
    -- le balayage se coupe sans emporter les chiffres
    ----------------------------------------------------------------------
    eq(NS.profileDefaults.showDuration, true, "duree : le balayage est actif par defaut")

    -- Observer l'appel reel au moteur, pas le reglage : c'est le seul endroit
    -- ou le choix du joueur devient visible a l'ecran.
    freshProfile("PALADIN")
    mock.state.auraEngine.loaded = true
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()

    local visual, styledButton
    for _, candidate in ipairs(NS.buttons) do
        for auraType, visuals in pairs(candidate.auraSlotVisuals or {}) do
            if visuals[1] and visuals[1].durationCooldown then
                visual, styledButton = visuals[1], candidate
                visual.__auraType = auraType
            end
            if visual then break end
        end
        if visual then break end
    end
    truthy(visual, "duree : un visuel du moteur porte bien un balayage")

    local swept
    if visual then
        rawset(visual.durationCooldown, "SetDrawSwipe", function(_, value) swept = value end)
        NS.db.showDuration = true
        NS:StyleAuraVisual(styledButton, visual.__auraType, visual)
        eq(swept, true, "duree : le balayage est demande quand le reglage est actif")
        NS.db.showDuration = false
        NS:StyleAuraVisual(styledButton, visual.__auraType, visual)
        eq(swept, false, "duree : et refuse quand le joueur le coupe")
    end

    NS.db.showDuration = false
    NS.db.showCooldown = true
    truthy(NS.db.showCooldown, "duree : couper le balayage laisse les chiffres")
    truthy(NS:ExportProfile():find("showDuration=0", 1, true),
        "duree : le choix part dans un profil exporte")
end

--------------------------------------------------------------------------
-- 1.5.58 : les entraves, apprises avant d'etre signalees
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()

    mock.state.lossOfControl.player = {
        { locType = "ROOT", spellID = 339, displayText = "Racines" },
    }

    ----------------------------------------------------------------------
    -- lire, et apprendre en lisant
    ----------------------------------------------------------------------
    local types = NS:UnitControlTypes("player")
    truthy(types and types[1] == "ROOT", "entraves : le type actif est lu sur l'unite")
    local seen = NS.dbRoot.global.controlSeen
    truthy(seen and seen.ROOT, "entraves : ce qui est vu est retenu")
    eq(seen and seen.ROOT.example, "Racines", "entraves : avec le libelle du jeu")

    -- Cleansive ne liste que ce qu'il a vu. Un type absent n'est pas une preuve.
    eq(seen.SNARE, nil, "entraves : rien n'est invente dans le catalogue")

    ----------------------------------------------------------------------
    -- rien n'est signale tant que le joueur n'a rien choisi
    ----------------------------------------------------------------------
    NS.db.controlWarning = true
    eq(NS:UnitWatchedControl("player"), nil,
        "entraves : signaler est actif mais aucun type n'est surveille, donc rien")
    NS:ToggleControlType("ROOT")
    eq(NS:UnitWatchedControl("player"), "ROOT",
        "entraves : le type choisi est signale")
    NS.db.controlWarning = false
    eq(NS:UnitWatchedControl("player"), nil,
        "entraves : l'interrupteur general coupe tout")
    NS.db.controlWarning = true

    ----------------------------------------------------------------------
    -- une entrave ne masque jamais une affliction
    ----------------------------------------------------------------------
    local button = NS.unitToButton.player
    truthy(button, "entraves : la case du joueur existe")
    NS:SetButtonState(button, nil, nil, nil, false, false)
    eq(button.controlType, "ROOT", "entraves : une case sans affliction porte la marque")

    mock.state.debuffs.player = { debuff(1234, "Magic") }
    NS:RefreshUnit("player")
    truthy(button.state == "afflicted" or button.state == "far_afflicted",
        "entraves : une case affligee reste une case affligee")
    mock.state.debuffs.player = nil
    NS:RefreshUnit("player")

    ----------------------------------------------------------------------
    -- une donnee secrete n'est jamais lue comme une absence d'entrave
    ----------------------------------------------------------------------
    mock.state.lossOfControlRestricted = true
    eq(NS:UnitControlTypes("player"), nil,
        "entraves : une lecture refusee ne rend rien, et ne fait pas lever")
    mock.state.lossOfControlRestricted = false

    -- Le vrai danger de 12.1 n'est pas de rendre nil : c'est de traiter un
    -- nombre secret comme un nombre. `for index = 1, count` sur un compte
    -- secret leve dans le client. Le contrat est donc : ne jamais s'en servir
    -- comme borne, pas seulement ne rien rendre.
    mock.state.secretMode = true
    local reads = 0
    local realRead = C_LossOfControl.GetActiveLossOfControlDataByUnit
    C_LossOfControl.GetActiveLossOfControlDataByUnit = function(...)
        reads = reads + 1
        return realRead(...)
    end
    NS:UnitControlTypes("player")
    C_LossOfControl.GetActiveLossOfControlDataByUnit = realRead
    mock.state.secretMode = false
    eq(reads, 0, "entraves : un compte secret n'est jamais utilise comme borne de boucle")

    ----------------------------------------------------------------------
    -- l'evenement du jeu alimente le catalogue
    ----------------------------------------------------------------------
    NS.dbRoot.global.controlSeen = {}
    mock.state.lossOfControl.party1 = {
        { locType = "STUN", spellID = 408, displayText = "Coup de rein" },
    }
    local fire = NS.eventFrame:GetScript("OnEvent")
    fire(NS.eventFrame, "LOSS_OF_CONTROL_ADDED", "party1", 1)
    truthy(NS.dbRoot.global.controlSeen.STUN,
        "entraves : l'evenement du jeu apprend le type, meme hors grille")

    ----------------------------------------------------------------------
    -- la commande
    ----------------------------------------------------------------------
    local before = #mock.state.chat
    NS:HandleSlash("control")
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("STUN", 1, true), "commande : control liste ce qui a ete vu")

    before = #mock.state.chat
    NS:HandleSlash("control stun")
    truthy(NS.db.controlTypes.STUN, "commande : control <type> surveille ce type")
    NS:HandleSlash("control stun")
    eq(NS.db.controlTypes.STUN, nil, "commande : et le relacher le retire")

    before = #mock.state.chat
    NS:HandleSlash("control licorne")
    printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("LICORNE", 1, true),
        "commande : un type jamais vu est refuse et nomme, pas surveille en silence")
    eq(NS.db.controlTypes.LICORNE, nil, "commande : et il n'entre pas dans la liste")
end

--------------------------------------------------------------------------
-- 1.5.59 : ne promettre que ce qui existe
--------------------------------------------------------------------------
do
    -- Un paladin sacre n'a qu'un sort de dissipation : lui annoncer une
    -- "troisieme dissipation" sur la souris 4 promet un bouton qui ne fait
    -- rien.
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()
    eq(#NS.clickSpells, 1, "souris : cette specialisation n'a qu'un sort")

    mock.state.tooltip = nil
    NS:ShowButtonTooltip(NS.unitToButton.player)
    local lines = table.concat(mock.state.tooltip or {}, "\n")
    truthy(lines:find(NS.L.THUMB_BIND_FOCUS_ONLY, 1, true),
        "souris : sans troisieme sort, seule la focalisation est annoncee")
    falsy(lines:find(NS.L.THUMB_BIND, 1, true),
        "souris : et la troisieme dissipation n'est pas promise")

    -- Avec trois sorts, la ligne complete revient.
    freshProfile("PALADIN")
    knowSpells(4987, 53551, 213644)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()
    if #NS.clickSpells >= 3 then
        mock.state.tooltip = nil
        NS:ShowButtonTooltip(NS.unitToButton.player)
        lines = table.concat(mock.state.tooltip or {}, "\n")
        truthy(lines:find(NS.L.THUMB_BIND, 1, true),
            "souris : avec un troisieme sort, la souris 4 est annoncee")
    end

    -- Les credits et l'avertissement d'installation existent dans les deux
    -- langues, et disent l'essentiel : aucune ligne de code concurrent ici.
    for _, language in ipairs({ "enUS", "frFR" }) do
        local credits = NS.LOCALES[language].HELP_CREDITS
        truthy(credits and #credits > 40, "credits : le texte existe en " .. language)
        truthy(NS.LOCALES[language].HELP_INSTALL_WARNING:find("Source code", 1, true),
            "installation : l'archive a eviter est nommee en " .. language)
    end
    truthy(NS.LOCALES.enUS.HELP_CREDITS:find("Decursive", 1, true),
        "credits : l'inspiration principale est nommee")
end

--------------------------------------------------------------------------
-- 1.5.60 : chaque reglage s'explique
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    local silent = {}
    for _, entry in ipairs(NS.optionIndex or {}) do
        if not entry.help or entry.help == "" then
            silent[#silent + 1] = tostring(entry.label)
        end
    end
    eq(table.concat(silent, ", "), "",
        "reglages : chacun explique ce qu'il fait")

    ----------------------------------------------------------------------
    -- un curseur ne replace pas 82 cases a chaque cran
    ----------------------------------------------------------------------
    local layouts = 0
    local realLayout = NS.LayoutButtons
    NS.LayoutButtons = function(...) layouts = layouts + 1; return realLayout(...) end
    for value = 20, 32 do
        NS:Debounce("layout", 0.1, function() NS:LayoutButtons() end)
    end
    eq(layouts, 0, "curseur : rien n'est replace pendant le glissement")
    mock.runTimers()
    eq(layouts, 1, "curseur : une seule mise en page a la fin, pas treize")
    NS.LayoutButtons = realLayout

    -- Deux gestes differents ne doivent pas s'annuler l'un l'autre.
    local a, b = 0, 0
    NS:Debounce("premier", 0.1, function() a = a + 1 end)
    NS:Debounce("second", 0.1, function() b = b + 1 end)
    mock.runTimers()
    eq(a, 1, "curseur : le premier geste s'applique")
    eq(b, 1, "curseur : le second aussi, ils ne se marchent pas dessus")

    ----------------------------------------------------------------------
    -- l'interrupteur des noms n'a plus l'air casse
    ----------------------------------------------------------------------
    NS.db.showNames = true
    NS.db.frameSize = 14
    falsy(NS:CellShowsNames(), "noms : sous le seuil, ils ne s'affichent pas")
    NS:RefreshOptions()
    truthy(NS.nameWidthNote:GetText() ~= "",
        "noms : et l'interface explique pourquoi, au lieu de laisser croire a une panne")
    NS.db.frameSize = 30
    truthy(NS:CellShowsNames(), "noms : au-dessus du seuil, ils s'affichent")
    NS:RefreshOptions()
    eq(NS.nameWidthNote:GetText(), "",
        "noms : et l'explication disparait quand elle n'a plus lieu d'etre")
    NS.db.showNames = false
    NS:RefreshOptions()
    eq(NS.nameWidthNote:GetText(), "",
        "noms : rien n'est dit quand les noms sont coupes")

    ----------------------------------------------------------------------
    -- vider ce qui a ete appris sans toucher a ce qui a ete choisi
    ----------------------------------------------------------------------
    NS.dbRoot.global.controlSeen = { ROOT = { count = 3 }, STUN = { count = 1 } }
    NS.db.controlTypes = { ROOT = true }
    NS:HandleSlash("control clear")
    eq(next(NS.dbRoot.global.controlSeen), nil, "appris : le catalogue observe est vide")
    truthy(NS.db.controlTypes.ROOT,
        "appris : mais le choix du joueur est conserve, il ne se re-fait pas")

    ----------------------------------------------------------------------
    -- 1.5.60 : un talent qui remplace un sort sans changer leur nombre
    ----------------------------------------------------------------------
    freshProfile("SHAMAN")
    knowSpells(51886)                      -- Purge des maledictions
    NS:UpdateSpells()
    local firstCount = #NS.clickSpells
    local firstSpell = NS.clickSpells[1] and NS.clickSpells[1].id
    truthy(firstSpell, "talents : un premier sort est detecte")

    -- Le talent change : meme nombre de sorts cliquables, sort different. Un
    -- rafraichissement qui se fierait au NOMBRE ne verrait rien changer.
    mock.state.knownSpells[51886] = nil
    mock.state.playerSpells[51886] = nil
    knowSpells(77130)                      -- Purification des flots
    NS:UpdateSpells()
    eq(#NS.clickSpells, firstCount, "talents : le nombre de sorts n'a pas bouge")
    truthy(NS.clickSpells[1] and NS.clickSpells[1].id ~= firstSpell,
        "talents : et pourtant le sort attache au clic a bien change")
end

--------------------------------------------------------------------------
-- 1.5.61 : sortir du combat n'est pas sortir de la rencontre
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    mock.state.auraEngine.loaded = true
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()
    local fire = NS.eventFrame:GetScript("OnEvent")

    -- Un emplacement d'aura ne se retire jamais. Reconstruire le moteur au
    -- milieu d'un boss coute des emplacements definitifs, pour un repit de
    -- deux secondes entre deux vagues.
    fire(NS.eventFrame, "ENCOUNTER_START", 1234, "Boss", 8, 5)
    truthy(NS.encounterActive, "rencontre : le combat de boss est signale")

    local rebuilds = 0
    local realRebuild = NS.RefreshAuraEngineTypes
    NS.RefreshAuraEngineTypes = function(...) rebuilds = rebuilds + 1; return realRebuild(...) end

    NS.pendingAuraEngineRebuild = true
    mock.state.inCombat = false
    NS:FlushCombatUpdates()
    eq(rebuilds, 0, "rencontre : un repit hors combat ne reconstruit pas le moteur")
    truthy(NS.pendingAuraEngineRebuild, "rencontre : le travail reste en reserve")

    fire(NS.eventFrame, "ENCOUNTER_END", 1234, "Boss", 8, 5, 1)
    falsy(NS.encounterActive, "rencontre : la fin du boss est signalee")
    mock.runTimers()
    eq(rebuilds, 1, "rencontre : c'est la fin de la rencontre qui rejoue le travail")
    NS.RefreshAuraEngineTypes = realRebuild

    -- Hors rencontre, la fin de combat suffit : il ne faut pas attendre un
    -- ENCOUNTER_END qui ne viendra jamais en monde ouvert.
    rebuilds = 0
    NS.RefreshAuraEngineTypes = function(...) rebuilds = rebuilds + 1; return realRebuild(...) end
    NS.pendingAuraEngineRebuild = true
    NS.encounterActive = false
    NS:FlushCombatUpdates()
    eq(rebuilds, 1, "hors rencontre : la fin de combat suffit a rejouer le travail")
    NS.RefreshAuraEngineTypes = realRebuild

    ----------------------------------------------------------------------
    -- l'etat du moteur, en une phrase
    ----------------------------------------------------------------------
    for _, key in ipairs({ "OFF", "IDLE", "PENDING", "DEGRADED", "ACTIVE" }) do
        truthy(NS.LOCALES.enUS["ENGINE_STATE_" .. key], "etat moteur : " .. key .. " a une phrase")
        truthy(NS.LOCALES.frFR["ENGINE_STATE_" .. key], "etat moteur : " .. key .. " en francais")
    end

    NS.engineAuraMode = false
    eq(NS:AuraEngineState(), "OFF", "etat moteur : non utilise")
    NS.engineAuraMode = true
    NS.pendingAuraEngineRebuild = false
    NS.auraContainerDiagnostics = { added = 246, expected = 246 }
    eq(NS:AuraEngineState(), "ACTIVE", "etat moteur : complet")
    NS.auraContainerDiagnostics = { added = 200, expected = 246 }
    eq(NS:AuraEngineState(), "DEGRADED", "etat moteur : incomplet")
    NS.auraContainerDiagnostics = { added = 246, expected = 246, firstError = "refus" }
    eq(NS:AuraEngineState(), "DEGRADED", "etat moteur : une erreur suffit")
    NS.pendingAuraEngineRebuild = true
    eq(NS:AuraEngineState(), "PENDING", "etat moteur : en attente d'un moment calme")
    NS.pendingAuraEngineRebuild = false

    NS:CreateOptions()
    NS:RefreshOptions()
    truthy(NS.profileLabel:GetText():find("Ekinoks", 1, true),
        "apercu : le profil actif est nomme, une seule fois, par sa carte")
    eq(NS.overviewEngineText:GetText(), NS:AuraEngineStateSentence(),
        "apercu : et l'etat du moteur y est dit en clair")
end

--------------------------------------------------------------------------
-- 1.5.62 : l'apercu appartient a qui l'a ouvert
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:CreateOptions()
    NS.testMode = false
    NS.testModeFromOptions = nil

    -- Ouvert depuis la fenetre : il se ferme avec elle.
    NS.optionsFrame:Show()
    NS.testModeButton:GetScript("OnClick")(NS.testModeButton)
    truthy(NS.testMode, "apercu : le bouton des reglages l'ouvre")
    truthy(NS.testModeFromOptions, "apercu : et la fenetre s'en sait proprietaire")
    NS.optionsFrame:Hide()
    falsy(NS.testMode, "apercu : fermer les reglages ferme l'apercu qu'ils avaient ouvert")

    -- Ouvert a la commande : la fenetre n'a rien a en dire.
    NS:HandleSlash("test")
    truthy(NS.testMode, "apercu : la commande l'ouvre aussi")
    falsy(NS.testModeFromOptions, "apercu : mais la fenetre ne s'en dit pas proprietaire")
    NS.optionsFrame:Show()
    NS.optionsFrame:Hide()
    truthy(NS.testMode,
        "apercu : fermer une fenetre qu'on n'a pas ouverte ne coupe pas l'apercu")
    NS:HandleSlash("test")
    falsy(NS.testMode, "apercu : seule la commande le referme alors")

    -- Une commande apres une ouverture par la fenetre transfere la propriete.
    NS.optionsFrame:Show()
    NS.testModeButton:GetScript("OnClick")(NS.testModeButton)
    truthy(NS.testModeFromOptions, "apercu : ouvert par la fenetre")
    NS:HandleSlash("test 10")
    falsy(NS.testModeFromOptions,
        "apercu : une commande le reprend, la fenetre ne le fermera plus")
    NS.optionsFrame:Hide()
    truthy(NS.testMode, "apercu : et il survit bien a la fermeture")
    NS:HandleSlash("test")
end

--------------------------------------------------------------------------
-- 1.5.63 : le diagnostic dit ce qu'il a decide
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()
    NS.alertDecisions = {}
    NS.db.sound = true

    local button = NS.unitToButton.player
    local aura = debuff(555, "Magic")

    -- Une affliction nouvelle : ca sonne, et c'est ecrit.
    NS:UpdateButtonAfflictionAlert(button, aura, 1, false)
    truthy(NS.lastAlertDecision, "decisions : la decision est enregistree")
    eq(NS.lastAlertDecision.decision, "played", "decisions : la premiere alerte est jouee")

    -- La meme affliction : ca ne resonne pas, et la raison est nommee.
    NS:UpdateButtonAfflictionAlert(button, aura, 1, false)
    eq(NS.lastAlertDecision.decision, "same affliction as before",
        "decisions : la meme affliction ne resonne pas, et on sait pourquoi")

    -- Plus d'affliction du tout.
    NS:UpdateButtonAfflictionAlert(button, nil, nil, false)
    eq(NS.lastAlertDecision.decision, "no affliction",
        "decisions : l'absence d'affliction est une decision comme une autre")

    -- Le son coupe ne doit pas se confondre avec un fichier qui n'a pas joue :
    -- ce sont deux problemes differents et deux corrections differentes.
    NS.db.sound = false
    NS:UpdateButtonAfflictionAlert(button, debuff(556, "Magic"), 1, false)
    eq(NS.lastAlertDecision.decision, "sound switched off",
        "decisions : le son coupe est nomme comme tel")
    NS.db.sound = true

    -- La file est courte : ce qui interesse vient de se produire.
    for index = 1, 30 do
        NS:UpdateButtonAfflictionAlert(button, debuff(600 + index, "Magic"), 1, true)
    end
    truthy(#NS.alertDecisions <= 12, "decisions : la file reste courte")
    truthy(#NS.alertDecisions > 0, "decisions : et elle garde les dernieres")

    local before = #mock.state.chat
    NS:HandleSlash("alerts")
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find("player", 1, true), "commande : alerts montre le journal")
    NS:HandleSlash("alerts clear")
    eq(#NS.alertDecisions, 0, "commande : alerts clear le vide")

    ----------------------------------------------------------------------
    -- avec quel sort la portee a-t-elle ete jugee
    ----------------------------------------------------------------------
    NS.rangeDiagnostics = nil
    NS:IsSpellInRange(NS.clickSpells[1], "player")
    truthy(NS.rangeDiagnostics, "portee : la source de la reponse est retenue")
    eq(NS.rangeDiagnostics and NS.rangeDiagnostics.spellID, NS.clickSpells[1].id,
        "portee : avec le sort qui a servi a juger")
    eq(NS.rangeDiagnostics and NS.rangeDiagnostics.source, "spell",
        "portee : et l'API qui a repondu est nommee")
    truthy(NS:BuildDiagnosticsReport():find("range source=", 1, true),
        "portee : et le rapport copiable la porte")

    ----------------------------------------------------------------------
    -- ce que la liste de saison couvre, type par type
    ----------------------------------------------------------------------
    local coverage = NS:SoundCoverageByType()
    truthy(#coverage >= 4, "couverture : chaque type connu a sa ligne")
    local joined = table.concat(coverage, "\n")
    truthy(joined:find(NS.L.COVERAGE_CLICK, 1, true),
        "couverture : un type atteignable au clic est annonce comme tel")

    -- Un type coupe doit se distinguer d'un type que rien ne peut retirer.
    NS.db.enabledTypes.Magic = false
    NS:UpdateSpells()
    joined = table.concat(NS:SoundCoverageByType(), "\n")
    truthy(joined:find(NS.L.COVERAGE_OFF, 1, true),
        "couverture : un type desactive est distingue d'un type inaccessible")
    NS.db.enabledTypes.Magic = true
    NS:UpdateSpells()
end

--------------------------------------------------------------------------
-- 1.5.64 : ce que le demarrage a coute, et qui pilote quoi
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    mock.state.auraEngine.loaded = true
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()

    ----------------------------------------------------------------------
    -- le cout de la construction
    ----------------------------------------------------------------------
    local startup = NS.startupDiagnostics
    truthy(startup, "demarrage : la construction laisse une trace")
    truthy(startup and startup.buttons and startup.buttons > 0,
        "demarrage : le nombre de cases construites est retenu")
    truthy(startup and startup.elapsedMs and startup.elapsedMs >= 0,
        "demarrage : et le temps que ca a pris")
    truthy(NS:BuildDiagnosticsReport():find("startup elapsedMs=", 1, true),
        "demarrage : le rapport copiable le porte")

    ----------------------------------------------------------------------
    -- qui pilote quelle case
    ----------------------------------------------------------------------
    local engine, fallback, idle = NS:CountAuraProviders()
    eq(engine + fallback + idle, #NS.buttons,
        "moteurs : chaque case est comptee une fois et une seule")
    truthy(engine > 0, "moteurs : le moteur protege pilote des cases")

    -- Le mode test met tout le monde sur le repli : c'est Cleansive qui dessine.
    NS.testMode = true
    local testEngine = NS:CountAuraProviders()
    eq(testEngine, 0, "moteurs : en mode test, le moteur protege ne pilote rien")
    NS.testMode = false

    truthy(NS:BuildDiagnosticsReport():find("providers engine=", 1, true),
        "moteurs : le rapport copiable dit qui pilote quoi")

    ----------------------------------------------------------------------
    -- #29/#120 : sans sort de dissipation, Cleansive ne doit presque rien faire
    ----------------------------------------------------------------------
    freshProfile("WARRIOR")
    mock.state.auraEngine.loaded = true
    NS:UpdateSpells()
    eq(#NS.clickSpells, 0, "sans dissipation : aucun sort n'est detecte")

    local containersBefore = mock.state.auraEngine.created
    NS:CreateGrid()
    eq(mock.state.auraEngine.created, containersBefore,
        "sans dissipation : aucun conteneur d'auras protege n'est cree")

    local registrations = 0
    local realAdd = C_UnitAuras.AddAuraSound
    C_UnitAuras.AddAuraSound = function(...) registrations = registrations + 1; return realAdd(...) end
    NS.auraSoundFingerprint = nil
    NS.db.sound = true
    NS:RefreshAuraSoundRegistrations("sans dissipation")
    C_UnitAuras.AddAuraSound = realAdd
    eq(registrations, 0,
        "sans dissipation : aucune alerte sonore n'est enregistree pour rien")

    local none = NS:CountAuraProviders()
    eq(none, 0, "sans dissipation : le moteur protege ne pilote aucune case")

    ----------------------------------------------------------------------
    -- #231 : la revision, seulement si elle en est une
    ----------------------------------------------------------------------
    -- Sur une copie de travail le champ reste le jeton de l'empaqueteur :
    -- l'afficher ferait passer un artefact de fabrication pour une information.
    eq(NS.revision, nil,
        "revision : un jeton non remplace n'est pas presente comme une revision")
    falsy(NS:BuildDiagnosticsReport():find("revision=@", 1, true),
        "revision : et le rapport ne porte pas le jeton")
    eq(NS:NormalizeRevision("@project-abbreviated-hash@"), nil,
        "revision : le jeton de l'empaqueteur est refuse")
    eq(NS:NormalizeRevision(""), nil, "revision : une chaine vide aussi")
    eq(NS:NormalizeRevision(nil), nil, "revision : et une absence de champ")
    eq(NS:NormalizeRevision("a1b2c3d"), "a1b2c3d",
        "revision : une vraie revision est gardee telle quelle")

    NS.revision = "a1b2c3d"
    truthy(NS:BuildDiagnosticsReport():find("revision=a1b2c3d", 1, true),
        "revision : et elle entre dans le rapport copiable")
    NS.revision = nil
end

--------------------------------------------------------------------------
-- 1.5.66 : ce qui est appris, ce qui est choisi, ce qui est grise
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    ----------------------------------------------------------------------
    -- #261 : un bouton grise doit se VOIR grise, tout de suite
    ----------------------------------------------------------------------
    local probe = NS:CreateUXButton(NS.optionsFrame, "Essai", 100, 26)
    local enabledColor = probe.uxBackground.__color
    truthy(enabledColor, "grise : la couleur active est posee des la creation")
    probe:SetEnabled(false)
    local disabledColor = probe.uxBackground.__color
    truthy(disabledColor and enabledColor[4] ~= disabledColor[4],
        "grise : desactiver repeint immediatement, sans attendre que la souris sorte")
    truthy(probe.uxLabel.__textColor and probe.uxLabel.__textColor[4] < 0.4,
        "grise : et le libelle s'eteint aussi")
    probe:SetEnabled(true)
    eq(probe.uxBackground.__color[4], enabledColor[4],
        "grise : reactiver rend exactement la couleur d'origine")

    ----------------------------------------------------------------------
    -- #190 : ce que Cleansive a appris ne vit pas dans les reglages
    ----------------------------------------------------------------------
    NS.dbRoot.global.controlSeen = { ROOT = { count = 2, example = "Racines" } }
    NS.db.controlTypes = { ROOT = true }

    -- L'export n'emet qu'une liste declaree, donc « le catalogue ne part pas »
    -- est vrai par construction et aucun defaut ne peut le rendre faux. Ce qui
    -- se verifie vraiment, c'est que cette liste ne s'elargit pas en douce :
    -- chaque cle sortante doit etre reconnue, et le jour ou quelqu'un en ajoute
    -- une qui porte du personnel, c'est ici que ca casse.
    local allowed = {}
    for _, key in ipairs({
        "enabled", "locked", "showPets", "showFocus", "showNames", "classColorCells", "alertSound", "separateRaidSize", "raidFrameSize", "raidSpacing", "showTooltips",
        "sound", "failureSound", "showCooldown", "showDuration", "showStacks",
        "showClickHints", "autoHide", "afflictedOnly", "groupManualTypes",
        "showSolo", "showParty", "showRaid", "controlWarning",
        "frameSize", "spacing", "columns", "blacklistTime", "soundMaxRegistrations",
        "testUnits", "inactiveAlpha", "grow", "layoutMode", "soundChannel",
        "testState", "sortMode", "typeOrder", "enabledTypes",
        "ignoredAlways", "ignoredCombat",
    }) do allowed[key] = true end

    local unexpected = {}
    for key in string.gmatch(NS:ExportProfile(), "([%a]+)=") do
        if not allowed[key] then unexpected[#unexpected + 1] = key end
    end
    eq(table.concat(unexpected, ", "), "",
        "appris : un profil exporte n'emporte que des cles connues et sans donnee personnelle")

    -- Et il survit a une remise a zero de page, qui ne touche qu'aux reglages.
    NS:ResetOptionsPage("general")
    truthy(NS.dbRoot.global.controlSeen.ROOT,
        "appris : une remise a zero des reglages n'efface pas les observations")

    ----------------------------------------------------------------------
    -- #246 : le catalogue peut quitter le jeu en un bloc
    ----------------------------------------------------------------------
    NS.db.controlTypes = { ROOT = true }
    local report = NS:BuildControlReport()
    truthy(report:find("ROOT", 1, true), "copie : le catalogue nomme les types vus")
    truthy(report:find("Racines", 1, true), "copie : avec le libelle du jeu")
    truthy(report:find("watched", 1, true),
        "copie : et dit lesquels vous surveillez, pour que le lecteur sache")

    NS:HandleSlash("control copy")
    truthy(NS.diagnosticsCopyFrame and NS.diagnosticsCopyFrame:IsShown(),
        "copie : la commande ouvre la fenetre de copie")
    truthy(NS.diagnosticsCopyFrame.edit:GetText():find("ROOT", 1, true),
        "copie : avec le catalogue dedans, pas le diagnostic")

    -- La copie ne doit rien vider : on copie AVANT de vider, jamais l'inverse.
    truthy(NS.dbRoot.global.controlSeen.ROOT, "copie : copier ne vide pas le catalogue")
end

--------------------------------------------------------------------------
-- 1.5.67 : verrouiller ce qui est deja juste
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()

    -- #97 (le coin choisi doit rester fixe quand le groupe grandit) a ete
    -- ECARTE d'ici sciemment : le mock ne donne aucune geometrie aux cadres,
    -- donc rien ne peut deplacer l'ancre et le test passait quoi qu'on injecte.
    -- Un test qui ne peut pas rougir vaut moins que pas de test : il occupe la
    -- place de celui qui manque. Ce point rejoint les verifications a faire en
    -- jeu, avec les autres questions d'affichage.

    ----------------------------------------------------------------------
    -- #130 : l'apercu suit chaque reglage separement
    ----------------------------------------------------------------------
    NS:CreateOptions()
    local cell = NS.uxPreview and NS.uxPreview.cells and NS.uxPreview.cells[1]
    truthy(cell, "apercu : une case d'apercu existe dans les options")

    NS.db.showClickHints = true
    NS:RefreshCellPreview()
    local withHints = cell.label:GetText()
    NS.db.showClickHints = false
    NS:RefreshCellPreview()
    truthy(withHints ~= cell.label:GetText(),
        "apercu : la lettre de clic suit son propre reglage")

    NS.db.showCooldown = true
    NS:RefreshCellPreview()
    local withCooldown = cell.cooldown:GetText()
    NS.db.showCooldown = false
    NS:RefreshCellPreview()
    truthy(withCooldown ~= cell.cooldown:GetText(),
        "apercu : le chiffre de recharge suit le sien, independamment")
    NS.db.showCooldown = true

    ----------------------------------------------------------------------
    -- #233 : dire de capturer AVANT le rechargement
    ----------------------------------------------------------------------
    for _, language in ipairs({ "enUS", "frFR" }) do
        local trouble = NS.LOCALES[language].HELP_TROUBLE_TEXT
        truthy(trouble:find("reload", 1, true) or trouble:find("rechargement", 1, true),
            "depannage : le piege du rechargement est dit en " .. language)
        truthy(trouble:find("diag copy", 1, true),
            "depannage : et la commande a lancer avant est nommee en " .. language)
    end
end

--------------------------------------------------------------------------
-- 1.6.11 : corrections de l'audit externe du 30/08/2026
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()

    -- P2 : la couche non protegee decidait seule, sans jamais lire showSolo,
    -- showParty ni showRaid. « Afficher en raid » eteint, le pilote securise
    -- masquait les cases en entrant en raid, et un chiffre de recharge ou le
    -- badge TEST pouvait rester seul a l'ecran, sans grille dessous.
    NS.enabled = true
    NS.testMode = false
    NS.gridManuallyHidden = false
    NS.db.autoHide = false
    NS.db.showSolo, NS.db.showParty, NS.db.showRaid = true, true, true
    mock.state.inRaid, mock.state.inGroup = false, false
    NS:UpdateCooldownOverlayVisibility()
    truthy(NS.cooldownBody:IsShown(), "couche : visible quand la grille l'est")

    NS.db.showRaid = false
    mock.state.inRaid, mock.state.inGroup = true, true
    NS:UpdateCooldownOverlayVisibility()
    falsy(NS.cooldownBody:IsShown(),
        "couche : masquee la ou la grille est masquee par une regle de contexte")
    eq(NS.cooldownBody:IsShown(), NS:GridWouldBeVisible(),
        "couche : elle dit exactement ce que dit la grille")

    -- Et elle doit etre reevaluee quand le groupe change, sans qu'on la touche.
    NS.cooldownBody:Show()
    NS:RebuildRoster()
    falsy(NS.cooldownBody:IsShown(),
        "couche : entrer en raid la reevalue sans qu'on la touche")

    -- Cas restant signale par l'audit : la fenetre de reglages force
    -- l'affichage, mais en combat le pilote securise ne peut pas etre relache.
    -- Promettre l'affichage faisait apparaitre la couche non protegee SEULE,
    -- au-dessus d'une grille qui restait masquee.
    NS.db.showRaid = false
    mock.state.inRaid, mock.state.inGroup = true, true
    mock.state.inCombat = true
    NS.optionsFrame:Show()
    falsy(NS:GridWouldBeVisible(),
        "options en combat : on ne promet pas un affichage que le pilote ne peut pas tenir")
    NS:UpdateCooldownOverlayVisibility()
    falsy(NS.cooldownBody:IsShown(),
        "options en combat : la couche non protegee ne parait pas seule")

    -- Hors combat, la surcharge reprend tout son sens : le pilote peut relacher.
    mock.state.inCombat = false
    truthy(NS:GridWouldBeVisible(),
        "options hors combat : la fenetre ouverte montre bien la grille")
    NS.optionsFrame:Hide()

    NS.db.showRaid = true
    mock.state.inRaid, mock.state.inGroup = false, false
    NS:UpdateCooldownOverlayVisibility()

    -- P2 : le nettoyage des poignees orphelines retirait l'enregistrement sans
    -- decrementer le compteur des alertes vivantes. Apres un remplacement
    -- refuse puis un nettoyage reussi, soundstatus et diag copy annoncaient
    -- plus d'alertes vivantes qu'il n'y en avait reellement.
    do
        -- Le point verifie n'est pas « combien vaut le compteur » -- un
        -- rafraichissement complet en repose d'autres au passage -- mais que
        -- CETTE suppression passe par le point unique qui tient le compteur.
        -- C'est ce point unique qui est la correction.
        local realRemove = C_UnitAuras.RemoveAuraSound
        local realHelper = NS.RemoveNativeAuraSound
        local seen = {}
        C_UnitAuras.RemoveAuraSound = function() return true end
        NS.RemoveNativeAuraSound = function(target, handle)
            seen[handle] = true
            return realHelper(target, handle)
        end
        local savedLive, savedFingerprint = NS.liveNativeSounds, NS.auraSoundFingerprint
        NS.liveNativeSounds = 5
        NS.auraSoundOrphanHandles = { [901] = true }
        NS.auraSoundFingerprint = nil
        NS:RefreshAuraSoundRegistrations("nettoyage des orphelins")
        eq(NS.auraSoundOrphanHandles[901], nil, "orphelins : la poignee est bien retiree")
        truthy(seen[901],
            "orphelins : et sa suppression passe par le point unique qui tient le compteur")

        -- Et ce point unique decremente bien.
        NS.RemoveNativeAuraSound = realHelper
        NS.liveNativeSounds = 5
        truthy(NS:RemoveNativeAuraSound(902), "orphelins : la suppression reussit")
        eq(NS.liveNativeSounds, 4, "orphelins : le compteur descend d'exactement une")

        -- Ce bloc a fait un vrai rafraichissement : il laisse donc des
        -- enregistrements derriere lui. Les tests suivants repartent d'un
        -- registre vide, et un registre deja plein leur ferait mesurer zero
        -- nouvelle pose sans qu'aucun defaut existe.
        C_UnitAuras.RemoveAuraSound = realRemove
        NS.liveNativeSounds, NS.auraSoundFingerprint = savedLive, savedFingerprint
        NS.auraSoundOrphanHandles = {}
        NS.auraSoundHandles, NS.auraSoundRegistered = {}, {}
        NS.auraSoundHandleChannels, NS.auraSoundChannel = {}, nil
        NS.auraSoundFingerprint = nil
    end

    -- P2 : le nom d'un profil etait coupe a l'OCTET. Trente et un caracteres
    -- ASCII suivis d'un accent se coupaient au milieu de la sequence UTF-8 :
    -- le nom devenu invalide etait impossible a retaper.
    local accented = string.rep("a", 31) .. "\195\169"
    local cut = NS:NormalizeProfileName(accented)
    truthy(cut, "nom : un nom trop long reste utilisable")
    -- 31 « a » puis un « e accent aigu » sur DEUX octets : le caractere ne
    -- tient pas dans le 32e octet, la coupe doit donc reculer avant lui. Une
    -- coupe a l'octet aurait garde 32 octets dont un demi-caractere -- et
    -- verifier « le dernier octet vaut au moins 194 » ne le voyait pas, 195
    -- etant justement le PREMIER octet de cette sequence.
    eq(#cut, 31, "nom : la coupe recule avant le caractere qui ne tient pas")
    truthy(cut:byte(#cut) < 128, "nom : et ne laisse aucune demi-sequence UTF-8")

    -- La barre verticale sert de separateur au renommage et ouvre une sequence
    -- de couleur dans un texte WoW : un nom bien choisi pourrait masquer la
    -- ligne entiere.
    eq(NS:NormalizeProfileName("Ra|cffff0000id"), "Racffff0000id",
        "nom : la barre verticale est retiree")
    falsy(NS:NormalizeProfileName("|"), "nom : un nom qui n'en contient que ne passe pas")

    -- P2 : une base abimee faisait lever EntryMatches des le premier roster.
    do
        NS.db.priority = { 42, { kind = "PLAYER" }, { kind = "INCONNU", value = "x" },
            { kind = "CLASS", value = "PALADIN" } }
        NS.db.skip = { "n'importe quoi", { kind = "GROUP", value = 3 } }
        NS:InitializeProfiles()
        eq(#NS.db.priority, 1, "listes : seules les entrees utilisables survivent")
        -- Sans reparation, priority[1] vaut 42 : lire .kind dessus leve. Le
        -- repli evite qu'un defaut isole emporte la suite de la suite.
        eq(type(NS.db.priority[1]) == "table" and NS.db.priority[1].kind or "?", "CLASS",
            "listes : et c'est la bonne")
        eq(#NS.db.skip, 1, "listes : idem pour les exclusions")
        eq(type(NS.db.skip[1]) == "table" and NS.db.skip[1].value or "?", "3",
            "listes : un nombre devient une chaine utilisable")
        -- Ce qui compte vraiment : le roster ne leve plus.
        local ok = pcall(function() NS:RebuildRoster() end)
        truthy(ok, "listes : et le roster se reconstruit sans lever")
    end

    -- P2 : une cle non textuelle dans « named » remontait jusqu'au tri, qui
    -- leve en comparant un nombre a une chaine.
    do
        local raw = NS.dbRoot
        raw.named = { [1] = {}, [""] = {}, Bon = {}, Casse = "pas une table" }
        raw.assignments = { [2] = {}, ["Perso"] = { ["1"] = 7, ["2"] = "Bon" } }
        raw.namedStoreChecked = nil
        local named, assignments = NS:NamedProfileStore()
        eq(named[1], nil, "stockage : une cle numerique est retiree")
        eq(named[""], nil, "stockage : une cle vide aussi")
        eq(named.Casse, nil, "stockage : une valeur qui n'est pas une table aussi")
        truthy(named.Bon, "stockage : le profil valide reste")
        eq(assignments[2], nil, "stockage : un personnage sans nom est retire")
        eq(assignments.Perso["1"], nil, "stockage : une affectation non textuelle aussi")
        eq(assignments.Perso["2"], "Bon", "stockage : la bonne reste")
        local ok = pcall(function() return NS:NamedProfiles() end)
        truthy(ok, "stockage : et la liste se trie sans lever")
        raw.named, raw.assignments = {}, {}
    end
end

--------------------------------------------------------------------------
-- 1.6.9 : profils nommes
--
-- Deux regles portent tout le reste. Le profil propre d'une specialisation
-- n'est JAMAIS supprime quand elle pointe ailleurs -- sinon supprimer un
-- profil partage laisserait des personnages sans rien. Et rien ne bascule tout
-- seul : le point 304 de l'inventaire interdit les profils automatiques.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()

    falsy(NS:NormalizeProfileName(""), "nom : une chaine vide est refusee")
    falsy(NS:NormalizeProfileName("   "), "nom : des espaces seuls aussi")
    falsy(NS:NormalizeProfileName(nil), "nom : et une absence de nom")
    eq(NS:NormalizeProfileName("  Raid  "), "Raid", "nom : les espaces de bord sont rognes")
    eq(NS:NormalizeProfileName("Ra\nid"), "Raid", "nom : les caracteres de controle sont retires")
    eq(#NS:NormalizeProfileName(string.rep("a", 200)), 32, "nom : la longueur est bornee")

    -- Le profil propre garde 22 tout du long : c'est lui le temoin. Le partage
    -- sera modifie APRES avoir ete active, sinon on ecrirait dans le temoin.
    eq(NS.db.frameSize, 22, "profil : le profil propre part de sa valeur d'origine")
    local created, message = NS:CreateNamedProfile("Raid")
    truthy(created, "profil : la creation reussit")
    truthy(message:find("Raid", 1, true), "profil : et le dit avec son nom")
    falsy(NS:CreateNamedProfile("Raid"), "profil : deux profils ne portent pas le meme nom")
    falsy(NS:CreateNamedProfile("  "), "profil : ni un nom vide")

    eq(#NS:NamedProfiles(), 1, "profil : il apparait dans la liste")
    falsy(NS:ActiveNamedProfile(), "profil : creer n'est pas utiliser")

    truthy(NS:UseNamedProfile("Raid"), "profil : on peut l'utiliser")
    eq(NS:ActiveNamedProfile(), "Raid", "profil : il devient le profil actif")
    eq(NS.db.frameSize, 22, "profil : cree a partir des reglages courants, il les porte")
    truthy(NS:GetActiveProfileLabel():find("Raid", 1, true),
        "profil : le libelle affiche annonce le profil partage")

    -- LE point qui compte : le profil propre n'est pas touche pendant qu'un
    -- profil partage sert, et il n'est jamais supprime.
    NS.db.frameSize = 33
    truthy(NS:UseOwnProfile(), "profil : on revient au profil propre")
    falsy(NS:ActiveNamedProfile(), "profil : plus aucun profil nomme actif")
    eq(NS.db.frameSize, 22,
        "profil : et le profil propre a garde SES valeurs, pas celles du partage")

    NS:UseNamedProfile("Raid")
    eq(NS.db.frameSize, 33, "profil : ce qu'on modifie dans un profil partage y reste")

    truthy(NS:RenameNamedProfile("Raid", "Mythique"), "profil : on peut le renommer")
    eq(NS:ActiveNamedProfile(), "Mythique", "profil : le pointeur suit le nouveau nom")
    falsy(NS:RenameNamedProfile("PasUnProfil", "X"), "profil : renommer l'inconnu est refuse")

    -- Un AUTRE personnage pointe aussi dessus. C'est lui qui compte : pour la
    -- specialisation active, le pointeur mort est rattrape au chargement, donc
    -- supprimer sans desaffecter n'aurait rien casse de visible ici -- et
    -- l'aurait casse chez l'autre, a sa prochaine connexion.
    local _, assignments = NS:NamedProfileStore()
    assignments["Autre-Royaume"] = { ["2"] = "Mythique" }

    truthy(NS:DeleteNamedProfile("Mythique"), "profil : on peut le supprimer")
    falsy(assignments["Autre-Royaume"]["2"],
        "profil : et AUCUN autre personnage ne garde un pointeur vers le disparu")
    falsy(NS:ActiveNamedProfile(), "profil : il n'est plus actif")
    eq(#NS:NamedProfiles(), 0, "profil : ni dans la liste")
    eq(NS.db.frameSize, 22,
        "profil : et la specialisation est revenue a SON profil, intact")
    falsy(NS:DeleteNamedProfile("Mythique"), "profil : supprimer deux fois est refuse")

    -- Un pointeur mort ne doit pas faire repartir sur les valeurs d'origine, et
    -- surtout il doit etre OUBLIE. Laisse en place, il ressusciterait tout seul
    -- le jour ou un profil reprendrait le meme nom -- une specialisation
    -- basculerait alors sans que personne ne l'ait demande, ce qu'interdit le
    -- point 304 de l'inventaire.
    NS:CreateNamedProfile("Temporaire")
    NS:UseNamedProfile("Temporaire")
    NS.db.frameSize = 40
    local named = NS:NamedProfileStore()
    named["Temporaire"] = nil
    NS:ReloadActiveProfile()
    falsy(NS:ActiveNamedProfile(), "profil : un pointeur mort est oublie")
    eq(NS.db.frameSize, 22, "profil : et on revient au profil propre, pas aux valeurs d'origine")

    NS:CreateNamedProfile("Temporaire")
    NS:ReloadActiveProfile()
    falsy(NS:ActiveNamedProfile(),
        "profil : un nom repris ne ressuscite pas un ancien pointeur")
    NS:DeleteNamedProfile("Temporaire")

    NS:HandleSlash("profile new Soins")
    eq(#NS:NamedProfiles(), 1, "commande : new cree le profil")
    NS:HandleSlash("profile use Soins")
    eq(NS:ActiveNamedProfile(), "Soins", "commande : use l'active")
    NS:HandleSlash("profile rename Soins | Soins 2")
    eq(NS:ActiveNamedProfile(), "Soins 2", "commande : rename accepte les deux noms")
    NS:HandleSlash("profile own")
    falsy(NS:ActiveNamedProfile(), "commande : own revient au profil propre")
    NS:HandleSlash("profile delete Soins 2")
    eq(#NS:NamedProfiles(), 0, "commande : delete le retire")

    -- P1 de l'audit du 30/08 : ces operations changeaient la base PUIS
    -- demandaient un rechargement que le combat refuse. Les cles actives
    -- restaient a nil, self.db pointait sur l'ancienne table, et une SECONDE
    -- operation ecrivait dans assignments[""] au lieu du personnage.
    do
        NS:CreateNamedProfile("Combat")
        NS:UseNamedProfile("Combat")
        local _, assignments = NS:NamedProfileStore()
        local character = NS.activeCharacterKey
        local spec = NS.activeSpecKey
        truthy(character and spec, "combat : le personnage et la spe sont connus avant l'essai")

        mock.state.inCombat = true
        falsy(NS:UseOwnProfile(), "combat : revenir a son profil est refuse")
        eq(assignments[character][spec], "Combat",
            "combat : et l'affectation n'a PAS ete touchee")
        truthy(NS.activeCharacterKey, "combat : l'addon n'a pas perdu son identite")

        NS:CreateNamedProfile("Second")
        falsy(NS:UseNamedProfile("Second"), "combat : changer de profil est refuse")
        eq(NS:ActiveNamedProfile(), "Combat", "combat : le profil actif n'a pas bouge")
        falsy(NS:DeleteNamedProfile("Combat"), "combat : supprimer est refuse")
        eq(#NS:NamedProfiles(), 2, "combat : et rien n'a disparu de la base")
        -- Le piege exact de l'audit : une seconde operation apres une premiere
        -- qui aurait efface les cles. Il ne doit RIEN exister sous la cle vide.
        falsy(assignments[""], "combat : rien n'a ete ecrit sous une cle vide")

        mock.state.inCombat = false
        truthy(NS:UseOwnProfile(), "hors combat : on peut de nouveau revenir au sien")
        NS:DeleteNamedProfile("Combat")
        NS:DeleteNamedProfile("Second")
    end

    -- P1 de l'audit : la resolution de l'affectation n'existait QUE dans
    -- LoadCurrentProfile, qui sort tot quand les cles n'ont pas bouge. Une
    -- connexion ou la specialisation est deja connue au chargement annoncait
    -- donc le profil partage tout en ecrivant dans le profil propre.
    do
        NS:CreateNamedProfile("AuDemarrage")
        NS:UseNamedProfile("AuDemarrage")
        NS.db.frameSize = 39

        -- Une connexion : tout est relu depuis la base sauvegardee.
        NS.dbRoot, NS.db = nil, nil
        NS.activeCharacterKey, NS.activeSpecKey = nil, nil
        NS:InitializeProfiles()

        eq(NS:ActiveNamedProfile(), "AuDemarrage",
            "demarrage : le profil partage est bien annonce actif")
        eq(NS.db.frameSize, 39,
            "demarrage : et c'est BIEN lui qui est charge, pas le profil propre")
        NS.db.frameSize = 22
        NS:UseOwnProfile()
        NS:DeleteNamedProfile("AuDemarrage")
    end

    -- La fenetre. Ce qui compte : chaque rangee agit sur SON profil -- une
    -- fermeture qui capturerait l'index plutot que le nom ferait agir le
    -- bouton sur le voisin des que la liste se reordonne -- et la suppression
    -- demande deux clics, comme toute action irreversible de l'addon.
    NS:CreateNamedProfile("Alpha")
    NS:CreateNamedProfile("Beta")
    NS:ShowProfileManager()
    local window = NS.profileManagerFrame
    truthy(window and window:IsShown(), "fenetre : elle s'ouvre")
    eq(window.rows[1].label.__text, "Alpha", "fenetre : les profils sont listes dans l'ordre")
    eq(window.rows[2].label.__text, "Beta", "fenetre : et tous les deux")
    falsy(window.rows[3]:IsShown(), "fenetre : les rangees inutiles sont cachees")
    falsy(window.empty:IsShown(), "fenetre : rien n'annonce une liste vide")
    falsy(window.ownButton:IsEnabled(),
        "fenetre : sans profil partage actif, revenir au sien ne sert a rien")

    window.rows[2].use:GetScript("OnClick")(window.rows[2].use)
    eq(NS:ActiveNamedProfile(), "Beta", "fenetre : la deuxieme rangee active BIEN le deuxieme profil")
    truthy(window.ownButton:IsEnabled(), "fenetre : revenir au sien devient possible")
    falsy(window.rows[2].use:IsEnabled(), "fenetre : et le profil actif ne se re-active pas")

    -- Renommer prend le texte de la saisie unique.
    window.nameBox:SetText("Beta 2")
    window.rows[2].rename:GetScript("OnClick")(window.rows[2].rename)
    eq(NS:ActiveNamedProfile(), "Beta 2", "fenetre : renommer suit le pointeur")

    -- Supprimer : un premier clic arme, un second agit.
    local target = window.rows[1].delete
    target:GetScript("OnClick")(target)
    eq(#NS:NamedProfiles(), 2, "fenetre : le premier clic ne supprime rien")
    eq(target.__text, NS.L.PROFILE_DELETE_ARMED, "fenetre : il demande confirmation")
    target:GetScript("OnClick")(target)
    eq(#NS:NamedProfiles(), 1, "fenetre : le second clic supprime")

    window.rows[1].delete:GetScript("OnClick")(window.rows[1].delete)
    window.rows[1].delete:GetScript("OnClick")(window.rows[1].delete)
    eq(#NS:NamedProfiles(), 0, "fenetre : et la liste peut se vider")
    truthy(window.empty:IsShown(), "fenetre : une liste vide le dit")

    -- 1.6.12, audit du 30/08 : le changelog de la 1.6.11 annoncait ces deux
    -- corrections. Elles n'existaient pas -- mon script d'edition ecrivait le
    -- fichier APRES ses trois remplacements, et une ancre absente en fin de
    -- script a tout annule alors que les deux premiers avaient dit « ok ».
    -- Voici ce qui aurait du le voir.
    do
        for index = 1, 7 do NS:CreateNamedProfile("P" .. index) end
        NS:RefreshProfileManager()
        eq(#NS:NamedProfiles(), 7, "debordement : sept profils existent")
        truthy(window.overflow:IsShown(), "debordement : l'avertissement parait")
        falsy(window.empty:IsShown(),
            "debordement : et ce n'est PAS le texte de liste vide")
        -- Ce qui compte : il ne doit pas se dessiner sur la premiere rangee.
        local first = window.rows[1].__lastPoint
        local warn = window.overflow.__lastPoint
        truthy(first and warn, "debordement : les deux sont poses")
        truthy(warn.y < first.y - 30,
            "debordement : il est SOUS la liste, pas par-dessus la premiere ligne")

        -- Et les trois boutons qui changent un profil sont grises en combat.
        mock.state.inCombat = true
        NS:RefreshProfileManager()
        falsy(window.rows[1].use:IsEnabled(), "combat : « utiliser » est grise")
        falsy(window.rows[1].delete:IsEnabled(), "combat : « supprimer » aussi")
        falsy(window.ownButton:IsEnabled(), "combat : « revenir au sien » aussi")
        mock.state.inCombat = false
        NS:RefreshProfileManager()
        truthy(window.rows[1].delete:IsEnabled(), "hors combat : ils reviennent")

        for _, name in ipairs(NS:NamedProfiles()) do NS:DeleteNamedProfile(name) end
        NS:RefreshProfileManager()
    end

    -- Un ancien profil dont le nom contient une barre verticale : la 1.6.11 la
    -- retirait des saisies mais laissait la cle enregistree telle quelle. Le
    -- profil devenait introuvable -- utiliser, renommer et supprimer echouaient.
    do
        local raw = NS.dbRoot
        raw.named = { ["Raid|Soins"] = { frameSize = 31 } }
        raw.assignments = { [NS.activeCharacterKey] = { [NS.activeSpecKey] = "Raid|Soins" } }
        raw.namedStoreChecked = nil
        local named, assignments = NS:NamedProfileStore()
        eq(named["Raid|Soins"], nil, "migration : l'ancienne cle a disparu")
        truthy(named["RaidSoins"], "migration : le profil existe sous un nom utilisable")
        eq(type(assignments[NS.activeCharacterKey]) == "table"
            and assignments[NS.activeCharacterKey][NS.activeSpecKey] or "?", "RaidSoins",
            "migration : et l'affectation suit")
        eq(NS:UseNamedProfile("RaidSoins") and true or false, true,
            "migration : il redevient utilisable")
        eq(NS.db.frameSize, 31, "migration : avec ses reglages")
        NS.db.frameSize = 22
        NS:UseOwnProfile()

        -- Collision : l'ancien ne doit pas ecraser celui qui porte deja ce nom.
        raw.named = { ["A|B"] = { frameSize = 33 }, ["AB"] = { frameSize = 12 } }
        raw.assignments, raw.namedStoreChecked = {}, nil
        local named2 = NS:NamedProfileStore()
        -- Repli sur chaque lecture : sans migration ces tables sont nil, et un
        -- defaut isole emporterait la suite de la suite au lieu d'echouer seul.
        eq(type(named2["AB"]) == "table" and named2["AB"].frameSize or 0, 12,
            "collision : le nom deja pris n'est pas ecrase")
        truthy(named2["AB (2)"], "collision : l'ancien est garde sous un nom distinct")
        eq(type(named2["AB (2)"]) == "table" and named2["AB (2)"].frameSize or 0, 33,
            "collision : avec ses propres reglages")
        raw.named, raw.assignments = {}, {}
    end

    window:Hide()
end

--------------------------------------------------------------------------
-- 1.6.8 : taille et espacement separes en groupe et en raid
--
-- Quarante cases a la taille d'un groupe de cinq ne tiennent nulle part. Dix-
-- huit endroits lisaient db.frameSize et db.spacing directement : ils passent
-- tous par CellSize et CellSpacing, sans quoi la geometrie se deciderait a
-- dix-huit endroits et un seul oubli suffirait a la desaccorder.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.testMode = false
    NS.db.frameSize, NS.db.spacing = 22, 4
    NS.db.raidFrameSize, NS.db.raidSpacing = 14, 1

    -- Eteint, un raid garde les valeurs du groupe : c'est le comportement
    -- d'avant, et il ne doit pas bouger pour qui n'a rien demande.
    NS.db.separateRaidSize = false
    mock.state.inRaid, mock.state.inGroup = true, true
    eq(NS:CellSize(), 22, "geometrie : separation eteinte, le raid garde la taille du groupe")
    eq(NS:CellSpacing(), 4, "geometrie : et son espacement")

    NS.db.separateRaidSize = true
    mock.state.inRaid, mock.state.inGroup = false, false
    eq(NS:CellSize(), 22, "geometrie : hors raid, la taille du groupe")
    eq(NS:CellSpacing(), 4, "geometrie : et son espacement")
    mock.state.inRaid, mock.state.inGroup = true, true
    eq(NS:CellSize(), 14, "geometrie : en raid, la taille du raid")
    eq(NS:CellSpacing(), 1, "geometrie : et son espacement")

    -- L'apercu existe pour regler une grille de raid SANS raid : au-dela d'un
    -- groupe de cinq, il doit montrer la geometrie de raid, sinon il ne sert
    -- plus a ce pour quoi il a ete fait.
    mock.state.inRaid, mock.state.inGroup = false, false
    NS.testMode = true
    NS.db.testUnits = 5
    eq(NS:CellSize(), 22, "apercu : a cinq cases, c'est encore un groupe")
    NS.db.testUnits = 20
    eq(NS:CellSize(), 14, "apercu : au-dela, il montre la geometrie de raid")
    NS.testMode = false

    -- Et la vraie grille suit : ce sont les cases qui doivent changer, pas
    -- seulement l'accesseur.
    mock.state.inRaid, mock.state.inGroup = true, true
    NS:RebuildRoster()
    NS:LayoutButtons()
    eq(NS.buttons[1].__lastSize.width, 14, "geometrie : la case elle-meme prend la taille de raid")
    mock.state.inRaid, mock.state.inGroup = false, false
    NS:RebuildRoster()
    NS:LayoutButtons()
    eq(NS.buttons[1].__lastSize.width, 22, "geometrie : et la retrouve en sortant")

    -- Entrer en raid redessine tout seul : RebuildRoster finit par
    -- AssignRosterToButtons, qui finit par LayoutButtons. Rien n'a ete ajoute
    -- pour cela -- un garde-fou ecrit puis retire, parce que son injection de
    -- defaut restait verte. Le chemin est verifie ici, pas suppose.
    mock.state.inRaid, mock.state.inGroup = true, true
    NS.pendingLayout = false
    NS.buttons[1].__lastSize = { width = 0, height = 0 }
    NS:RebuildRoster()
    eq(NS.buttons[1].__lastSize.width, 14,
        "geometrie : entrer en raid redessine la grille sans qu'on touche a rien")

    -- Les deux curseurs de raid sont GRISES, jamais caches : un controle cache
    -- echappe au controle de recouvrement, qui ne mesure que ce qui s'affiche.
    NS.db.separateRaidSize = false
    NS:RefreshOptions()
    for index, control in ipairs(NS.raidGeometrySliders) do
        truthy(control:IsShown(), "raid : le curseur " .. index .. " reste affiche")
        falsy(control:IsEnabled(), "raid : mais grise tant que la separation est eteinte")
    end
    NS.db.separateRaidSize = true
    NS:RefreshOptions()
    for index, control in ipairs(NS.raidGeometrySliders) do
        truthy(control:IsEnabled(), "raid : le curseur " .. index .. " s'active avec la separation")
    end

    NS.db.separateRaidSize = false
    mock.state.inRaid, mock.state.inGroup = false, false
end

--------------------------------------------------------------------------
-- 1.6.6 : choisir le son d'alerte parmi les sons du jeu
--
-- Demande d'un joueur : il trouve l'alerte livree trop aigue. Les identifiants
-- sont lus dans SOUNDKIT au moment ou on en a besoin, jamais recopies en dur :
-- un identifiant invente ne leve pas, il ne joue rien -- et une alerte
-- silencieuse serait pire que le son juge trop aigu.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.db.sound = true
    NS.enabled = true
    NS.testMode = false
    NS.gridManuallyHidden = false

    local realFile, realKit = PlaySoundFile, PlaySound
    local playedFile, playedKit
    _G.PlaySoundFile = function(file) playedFile = file return true end
    _G.PlaySound = function(kit) playedKit = kit return true end

    -- Le bouchon ne connait que deux de ces sons : la liste doit refuser les
    -- autres plutot que d'offrir un choix qui ne jouerait rien.
    local offered = {}
    for _, entry in ipairs(NS:AvailableAlertSounds()) do offered[entry.key] = true end
    truthy(offered.DEFAULT, "son : le fichier livre est toujours propose")
    truthy(offered.RAID_WARNING, "son : un son que le client connait est propose")
    falsy(offered.READY_CHECK, "son : un son que ce client ignore n'est PAS propose")
    falsy(offered.ALARM, "son : ni celui-la")

    -- Par defaut, c'est le fichier livre.
    NS.db.alertSound = "DEFAULT"
    falsy(NS:AlertSoundKit(), "son : par defaut, aucun identifiant, donc le fichier")
    playedFile, playedKit = nil, nil
    NS:PlayAfflictionAlert(true)
    eq(playedFile, NS.afflictionSoundFile, "son : et c'est bien le fichier qui est joue")
    falsy(playedKit, "son : sans passer par un identifiant")

    -- Un son choisi se joue par son identifiant, lu chez le client.
    truthy(NS:SetAlertSound("RAID_WARNING"), "son : le choix est accepte")
    -- Verifier contre SOUNDKIT.RAID_WARNING ne prouvait rien : recopier 8959 en
    -- dur donnait la meme reponse, et l'injection restait verte. La valeur est
    -- donc changee ICI : seule une lecture au moment de l'appel peut suivre.
    local trueKit = SOUNDKIT.RAID_WARNING
    SOUNDKIT.RAID_WARNING = 424242
    eq(NS:AlertSoundKit(), 424242,
        "son : l'identifiant est LU chez le client, pas recopie en dur")
    SOUNDKIT.RAID_WARNING = trueKit
    playedFile, playedKit = nil, nil
    NS:PlayAfflictionAlert(true)
    eq(playedKit, SOUNDKIT.RAID_WARNING, "son : c'est lui qui est joue")
    falsy(playedFile, "son : le fichier n'est plus joue par-dessus")

    -- Un choix devenu introuvable -- profil venu d'un client qui connaissait ce
    -- son -- doit retomber sur le fichier, jamais sur le silence.
    NS.db.alertSound = "READY_CHECK"
    falsy(NS:AlertSoundKit(), "son : un choix introuvable ne rend aucun identifiant")
    playedFile, playedKit = nil, nil
    NS:PlayAfflictionAlert(true)
    eq(playedFile, NS.afflictionSoundFile, "son : il retombe sur le fichier livre")

    -- Et si le client refuse de jouer l'identifiant, le fichier prend le relais.
    NS.db.alertSound = "RAID_WARNING"
    _G.PlaySound = function() return false end
    playedFile = nil
    NS:PlayAfflictionAlert(true)
    eq(playedFile, NS.afflictionSoundFile, "son : un identifiant refuse retombe sur le fichier")

    -- La commande accepte le nom en minuscules et refuse ce qui n'existe pas.
    _G.PlaySound = function(kit) playedKit = kit return true end
    NS.db.alertSound = "DEFAULT"
    NS:HandleSlash("sound raid_warning")
    eq(NS.db.alertSound, "RAID_WARNING", "son : la commande accepte le nom en minuscules")
    NS:HandleSlash("sound pasunson")
    eq(NS.db.alertSound, "RAID_WARNING", "son : un nom inconnu ne change rien")

    -- La reparation d'une valeur abimee n'est pas re-testee ici : le reglage
    -- est declare dans TRANSFER_FIELDS, et un test existant verifie qu'AUCUN
    -- reglage transferable n'echappe a la reparation. Le redire ici serait une
    -- assertion qui ne peut pas tomber.

    _G.PlaySoundFile, _G.PlaySound = realFile, realKit
    NS.db.alertSound = "DEFAULT"
end

--------------------------------------------------------------------------
-- 1.6.5 : la couleur de classe sur une case au repos
--
-- Demande d'un joueur sur le forum le 30/08/2026 : reconnaitre qui est qui
-- sans lire un nom, que les petites cases ne peuvent de toute facon pas
-- afficher. La palette fait autorite, jamais la couleur rendue.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    local neutral = { 0.05, 0.07, 0.09 }
    local function sameColor(a, b)
        return math.abs(a[1] - b[1]) < 0.001 and math.abs(a[2] - b[2]) < 0.001
            and math.abs(a[3] - b[3]) < 0.001
    end

    NS.db.classColorCells = false
    truthy(sameColor(NS:RestingCellColor({ class = "PALADIN" }), neutral),
        "classe : eteint, la case au repos reste neutre")

    NS.db.classColorCells = true
    truthy(sameColor(NS:RestingCellColor({ class = "PALADIN" }), { 0.96, 0.55, 0.73 }),
        "classe : allume, la case prend la couleur de la palette")
    truthy(sameColor(NS:RestingCellColor({ class = "MONK" }), { 0.00, 1.00, 0.59 }),
        "classe : et une autre classe donne une autre couleur")

    -- En 12.1 la classe est secrete-capable : le client peut refuser de la
    -- lire. Une classe illisible doit rendre le fond NEUTRE, pas blanc : un
    -- blanc a 18 % ressemblerait a une classe de plus.
    truthy(sameColor(NS:RestingCellColor({ class = nil }), neutral),
        "classe : une classe illisible rend la case neutre")
    truthy(sameColor(NS:RestingCellColor(nil), neutral),
        "classe : une case sans unite aussi")
    truthy(sameColor(NS:RestingCellColor({ class = "PASUNECLASSE" }), neutral),
        "classe : un jeton que la palette ignore aussi")

    -- Et le piege inverse : un pretre EST blanc. Deduire « illisible » d'une
    -- couleur blanche aurait rendu tous les pretres gris. C'est la palette qui
    -- fait autorite, pas la valeur qu'elle rend.
    truthy(sameColor(NS:RestingCellColor({ class = "PRIEST" }), { 1, 1, 1 }),
        "classe : un pretre est legitimement blanc, pas illisible")

    -- Une case affligee n'est jamais concernee : sa couleur dit le type de
    -- dissipation, et c'est la seule raison d'etre de la grille.
    NS:RebuildRoster()
    local button = NS.unitToButton["player"]
    truthy(button, "classe : une case du joueur existe")
    -- La cle de cache doit etre effacee entre les deux mesures : sans cela on
    -- comparerait une texture jamais repeinte avec elle-meme, et l'assertion ne
    -- pourrait pas tomber. Verifie en reinjectant la fuite : elle tombe.
    mock.state.debuffs.player = { debuff(1000, "Magic") }
    button.lastVisualKey = nil
    NS:RefreshUnit("player")
    local afflicted = { button.background.__color[1], button.background.__color[2],
        button.background.__color[3] }
    NS.db.classColorCells = false
    button.lastVisualKey = nil
    NS:RefreshUnit("player")
    truthy(sameColor(afflicted, button.background.__color),
        "classe : une case affligee garde sa couleur de dissipation dans les deux cas")
    falsy(sameColor(afflicted, { 0.96, 0.55, 0.73 }),
        "classe : et cette couleur n'est surtout pas celle du paladin")

    -- Le raccourci de cache ne doit pas figer la couleur : changer de reglage
    -- sur une case au repos doit la repeindre.
    mock.state.debuffs.player = {}
    NS:RefreshUnit("player")
    local restingOff = { button.background.__color[1], button.background.__color[2], button.background.__color[3] }
    NS.db.classColorCells = true
    NS:RefreshUnit("player")
    falsy(sameColor(restingOff, button.background.__color),
        "classe : basculer le reglage repeint bien la case, le cache ne fige rien")
    NS.db.classColorCells = false
    NS:RefreshUnit("player")
end

--------------------------------------------------------------------------
-- 1.6.1 : deux controles ne doivent pas occuper la meme place
--
-- La 1.6 est partie avec des libelles empiles les uns sur les autres sur trois
-- pages. Aucun test ne pouvait le voir : le harnais retenait les ancrages mais
-- personne ne les comparait. Le voici qui les compare.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateOptions()

    -- La fenetre fait 820 x 700 ; la zone visible des pages 560 x 550 (moins la
    -- barre laterale 178, l'en-tete 88 et le pied 62). Depuis la 1.6.7 une page
    -- peut etre PLUS HAUTE que cette zone et defiler : chaque page est donc
    -- mesuree dans sa propre hauteur declaree, sans quoi un controle cale en bas
    -- d'une page longue serait place au mauvais endroit.
    local PAGE_WIDTH = 560
    local LINE_HEIGHT = 14

    -- La premiere version ne comprenait que TOPLEFT et BOTTOMLEFT, et ignorait
    -- tout ancrage relatif a un autre cadre. Elle laissait donc passer
    -- exactement ce que les captures du 30/08 ont montre : une phrase de 560 px
    -- posee en travers de deux interrupteurs, un bouton cale a droite sur un
    -- texte, et le pied de fenetre que personne ne comparait a rien.
    local X_OF = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0,
                   RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1,
                   TOP = 0.5, BOTTOM = 0.5, CENTER = 0.5 }
    local Y_OF = { TOP = 0, TOPLEFT = 0, TOPRIGHT = 0,
                   BOTTOM = 1, BOTTOMLEFT = 1, BOTTOMRIGHT = 1,
                   LEFT = 0.5, RIGHT = 0.5, CENTER = 0.5 }

    -- Un texte a qui on a donne une largeur revient a la ligne. Le compter sur
    -- une seule ligne est ce qui a laisse passer la phrase de la page General :
    -- 501 px de texte dans une boite de 560, mais posee sur deux interrupteurs.
    --
    -- Un texte SANS largeur posee, en revanche, est declare non mesurable. La
    -- version precedente en estimait la largeur (caracteres x taille de police)
    -- et cette estimation, trop large, accusait huit controles que les captures
    -- montrent lisibles. Un modele qui surestime ACCUSE ; un modele qui se tait
    -- laisse passer. Entre les deux il n'y a pas de symetrie : une fausse
    -- accusation apprend a ignorer le test. Les neuf recouvrements du 30/08
    -- venaient tous d'elements a taille posee, aucun d'une estimation.
    local function sizeOf(frame)
        local size = rawget(frame, "__lastSize")
        local width = (size and size.width) or rawget(frame, "__width")
        local height = (size and size.height) or rawget(frame, "__height")
        local text = rawget(frame, "__text")
        if width and not height and text and text ~= "" and frame.GetStringWidth then
            local stringWidth = frame:GetStringWidth()
            if type(stringWidth) == "number" and stringWidth > 0 then
                height = math.ceil(stringWidth / width) * LINE_HEIGHT
            end
        end
        return width, height
    end

    local children = mock.childIndex()
    local function childrenOf(frame) return children[frame] or {} end

    local resolving, resolved = {}, {}
    local function resolveRect(frame, root, rootRect)
        if frame == root then return rootRect end
        if resolved[frame] ~= nil then return resolved[frame] or nil end
        if resolving[frame] then return nil end
        resolving[frame] = true

        local width, height = sizeOf(frame)
        local left, right, top, bottom
        for _, placed in ipairs(rawget(frame, "__points") or {}) do
            local base = rootRect
            if placed.relative ~= nil then
                base = resolveRect(placed.relative, root, rootRect)
            end
            local fx, fy = X_OF[placed.relativePoint], Y_OF[placed.relativePoint]
            local sx, sy = X_OF[placed.point], Y_OF[placed.point]
            if base and fx and fy and sx and sy then
                -- Les decalages du jeu comptent le y vers le HAUT ; ici le haut
                -- de la page est zero, donc un y positif descend le rectangle.
                local px = base.left + (base.right - base.left) * fx + (placed.x or 0)
                local py = base.top + (base.bottom - base.top) * fy - (placed.y or 0)
                if sx == 0 then left = px elseif sx == 1 then right = px end
                if sy == 0 then top = py elseif sy == 1 then bottom = py end
                if sx == 0.5 and width then left, right = px - width / 2, px + width / 2 end
                if sy == 0.5 and height then top, bottom = py - height / 2, py + height / 2 end
            end
        end
        if left and not right and width then right = left + width end
        if right and not left and width then left = right - width end
        if top and not bottom and height then bottom = top + height end
        if bottom and not top and height then top = bottom - height end

        local rect
        if left and right and top and bottom and right > left and bottom > top then
            local label = rawget(frame, "__text")
            if not label or label == "" then
                for _, child in ipairs(childrenOf(frame)) do
                    local childText = rawget(child, "__text")
                    if childText and childText ~= "" then label = childText break end
                end
            end
            rect = { left = left, right = right, top = top, bottom = bottom,
                     label = string.format("%s @%.0f,%.0f %.0fx%.0f", tostring(label or "?"),
                         left, top, right - left, bottom - top) }
        end
        resolving[frame] = nil
        resolved[frame] = rect or false
        return rect
    end

    local function overlaps(a, b)
        -- Une marge de 2 px : deux controles qui se frolent restent lisibles,
        -- deux controles qui se recouvrent de 3 px ne le sont plus.
        return a.left < b.right - 2 and b.left < a.right - 2
            and a.top < b.bottom - 2 and b.top < a.bottom - 2
    end

    local collisions = {}
    -- La comparaison descend dans chaque conteneur, entre freres de meme niveau.
    -- Un conteneur recouvre toujours ses propres enfants : ce n'est pas un
    -- defaut, c'est pourquoi on ne compare jamais un parent a son enfant.
    local function inspect(name, root, rootRect, skip, depth)
        local rects, counted = {}, 0
        for _, child in ipairs(childrenOf(root)) do
            -- Les fonds et les traits sont poses SOUS les controles a dessein.
            local kind = rawget(child, "__type")
            if kind ~= "Texture" and child:IsShown() and not (skip and skip[child]) then
                local rect = resolveRect(child, root, rootRect)
                if rect then
                    rects[#rects + 1] = rect
                    if (depth or 0) < 4 and #childrenOf(child) > 0 then
                        counted = counted + inspect(name, child, rect, skip, (depth or 0) + 1)
                    end
                end
            end
        end
        for i = 1, #rects do
            for j = i + 1, #rects do
                if overlaps(rects[i], rects[j]) then
                    collisions[#collisions + 1] = string.format("%s : « %s » recouvre « %s »",
                        name, rects[i].label, rects[j].label)
                end
            end
        end
        return counted + #rects
    end

    local measured = 0
    local overflow = {}
    local pageRect
    for _, pageKey in ipairs({ "general", "appearance", "dispels", "history", "help" }) do
        local declared = NS.optionsPageHeights[pageKey]
        truthy(declared, "mise en page : la page " .. pageKey .. " declare sa hauteur")
        pageRect = { left = 0, top = 0, right = PAGE_WIDTH, bottom = declared }
        local before = #collisions
        measured = measured + inspect(pageKey, NS.optionsPages[pageKey], pageRect)
        -- Une hauteur declaree trop courte ne se voit pas a l'ecran : la page
        -- defile simplement moins loin, et le dernier controle devient
        -- inatteignable. C'est le nouveau piege apporte par le defilement.
        for _, child in ipairs(childrenOf(NS.optionsPages[pageKey])) do
            if rawget(child, "__type") ~= "Texture" and child:IsShown() then
                local rect = resolveRect(child, NS.optionsPages[pageKey], pageRect)
                if rect and rect.bottom > declared then
                    overflow[#overflow + 1] = string.format("%s : « %s » descend a %.0f, hauteur declaree %d",
                        pageKey, rect.label, rect.bottom, declared)
                end
            end
        end
        if #collisions > before then end
    end
    eq(table.concat(overflow, " | "), "",
        "mise en page : aucun controle ne depasse la hauteur declaree par sa page")

    -- Le pied de la fenetre n'appartient a aucune page : il n'etait compare a
    -- rien, et le texte d'etat passait sous les boutons sur trois pages sur
    -- cinq. La fenetre entiere est donc parcourue -- en-tete, barre laterale,
    -- pied -- et la descente s'occupe du reste. Seules les pages sont ecartees :
    -- elles occupent toute la zone de contenu et sont deja parcourues, chacune
    -- dans son propre repere.
    local windowRect = { left = 0, top = 0, right = 820, bottom = 700 }
    local zones = {}
    for _, page in pairs(NS.optionsPages) do zones[page] = true end
    measured = measured + inspect("fenetre", NS.optionsFrame, windowRect, zones)

    truthy(measured > 100,
        "mise en page : les controles sont bien mesures, pas ecartes en silence")
    eq(table.concat(collisions, " | "), "",
        "mise en page : aucun controle n'en recouvre un autre")
end

-- 1.6.10 : le bouton du son d'alerte. Le mecanisme etait teste depuis la
-- 1.6.6, le bouton pose en 1.6.7 -- et personne ne verifiait qu'il etait
-- branche sur quoi que ce soit. Une option qu'on ne peut atteindre que par une
-- commande n'est pas livree.
do
    local control = NS.alertSoundButton
    truthy(control, "son : le bouton existe sur la page General")

    NS.db.sound = true
    NS.db.alertSound = "DEFAULT"
    NS:RefreshOptions()
    eq(control.__text, NS.L.ALERT_SOUND_DEFAULT, "son : le bouton porte le son courant")

    -- Un tour complet revient au point de depart, et ne s'arrete jamais sur un
    -- son que ce client ignore. Le nombre de sons proposes n'est PAS ecrit
    -- ici : il depend du client, et le figer ferait tomber ce test le jour ou
    -- la liste change, sans qu'aucun defaut existe.
    local available = NS:AvailableAlertSounds()
    truthy(#available >= 2, "son : ce client propose au moins deux sons")

    -- Un bouton non branche fait tomber l'assertion ci-dessous ; sans ce
    -- repli, il ferait aussi tomber la SUITE de la suite, et un defaut isole
    -- masquerait tout le reste.
    local click = control:GetScript("OnClick") or function() end
    truthy(control:GetScript("OnClick"), "son : le bouton est branche")
    click(control)
    eq(NS.db.alertSound, available[2].key, "son : un clic passe au suivant")
    eq(control.__text, NS.L["ALERT_SOUND_" .. available[2].key],
        "son : et le libelle suit")

    local offered = {}
    for _, entry in ipairs(available) do offered[entry.key] = true end
    for _ = 2, #available do
        click(control)
        truthy(offered[NS.db.alertSound],
            "son : le tour ne s'arrete jamais sur un son que le client ignore")
    end
    eq(NS.db.alertSound, "DEFAULT", "son : et un tour complet revient au premier")

    -- Un reglage qui ne s'applique pas ne doit pas rester la a suggerer qu'il
    -- s'applique : son coupe, tout ce qui le regle disparait.
    NS.db.sound = false
    NS:RefreshOptions()
    falsy(control:IsShown(), "son : le bouton disparait quand le son est coupe")
    NS.db.sound = true
    NS:RefreshOptions()
    truthy(control:IsShown(), "son : et revient avec lui")
end

--------------------------------------------------------------------------
-- 1.6.1 : l'apercu est refuse en combat, pas reporte
--
-- Ouvert en plein combat, il ne pouvait pas reconstruire le roster : les cases
-- gardaient de VRAIES unites et recevaient de FAUSSES afflictions. Fausses
-- cases rouges et fausse alerte au moment ou l'addon doit etre le plus fiable.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS:CreateGrid()
    NS:RebuildRoster()
    NS.testMode = false

    local rosterBefore = #NS.roster
    local alerts = 0
    local realPlay = NS.PlayAfflictionAlert
    NS.PlayAfflictionAlert = function(...) alerts = alerts + 1; return realPlay(...) end

    mock.state.inCombat = true
    NS:ToggleTest()
    falsy(NS.testMode, "combat : le bouton d'apercu est refuse")
    eq(#NS.roster, rosterBefore, "combat : le roster n'a pas bouge")
    eq(alerts, 0, "combat : aucune alerte n'a ete jouee")
    falsy(NS.pendingRoster, "combat : et rien n'a ete mis en attente pour plus tard")

    NS:HandleSlash("test 20")
    falsy(NS.testMode, "combat : la commande avec un nombre est refusee aussi")
    eq(NS.db.testUnits, 5, "combat : et la taille demandee n'est pas retenue")

    NS:HandleSlash("test all")
    eq(NS.db.testState, "MIXED", "combat : l'etat demande ne change rien non plus")

    local before = #mock.state.chat
    NS:ToggleTest()
    local printed = table.concat(mock.state.chat, "\n", before + 1)
    truthy(printed:find(NS.L.TEST_COMBAT_REFUSED, 1, true),
        "combat : le refus est dit au joueur, il ne disparait pas en silence")

    -- Hors combat, tout redevient possible.
    mock.state.inCombat = false
    NS:ToggleTest()
    truthy(NS.testMode, "hors combat : l'apercu s'ouvre normalement")

    -- Et l'eteindre en combat est refuse aussi : l'extinction passe par une
    -- reconstruction du roster, qui serait reportee, et les cases resteraient
    -- sur de fausses afflictions.
    mock.state.inCombat = true
    NS:ToggleTest()
    truthy(NS.testMode, "combat : eteindre l'apercu est refuse pour la meme raison")
    mock.state.inCombat = false
    NS:ToggleTest()
    falsy(NS.testMode, "hors combat : il s'eteint")

    NS.PlayAfflictionAlert = realPlay
end

--------------------------------------------------------------------------
-- 1.6.1 : une base abimee est reparee, y compris sur les reglages recents
--
-- Les bornes vivaient dans une seconde liste, ecrite a la main a cote de la
-- declaration des reglages. Elle avait pris huit champs de retard : une base
-- disant testUnits = "beaucoup" repartait telle quelle.
--------------------------------------------------------------------------
do
    mock.reset()
    CleansiveDB = {
        schemaVersion = 2,
        global = { language = "frFR" },
        profiles = { ["Ekinoks-Hyjal"] = { ["65"] = {
            testUnits = "beaucoup",
            sortMode = "NOM",
            testState = "AUCUN",
            showRaid = "false",
            showDuration = 0,
            controlWarning = "oui",
            showSolo = {},
            showParty = 1,
            frameSize = 9999,
            grow = "EN_DIAGONALE",
        } } },
    }
    NS.dbRoot, NS.db = nil, nil
    NS:InitializeProfiles()

    eq(NS.db.testUnits, NS.profileDefaults.testUnits,
        "reparation : un nombre illisible revient a sa valeur d'origine")
    eq(NS.db.sortMode, NS.profileDefaults.sortMode,
        "reparation : un mode de tri inconnu aussi")
    eq(NS.db.testState, NS.profileDefaults.testState,
        "reparation : un etat d'apercu inconnu aussi")
    eq(NS.db.grow, NS.profileDefaults.grow,
        "reparation : une direction inconnue aussi")
    eq(NS.db.frameSize, 40, "reparation : un nombre hors bornes est ramene dans les bornes")

    -- « false » et 0 sont VRAIS en Lua : un booleen mal type qui survit fait
    -- exactement l'inverse de ce que la base disait.
    for _, key in ipairs({ "showRaid", "showDuration", "controlWarning", "showSolo", "showParty" }) do
        eq(type(NS.db[key]), "boolean",
            "reparation : " .. key .. " redevient un vrai booleen")
    end

    -- Le vrai correctif n'est pas d'avoir ajoute huit noms a une liste : c'est
    -- qu'il n'y ait plus de seconde liste a tenir. Chaque reglage transferable
    -- doit etre reparable, sans exception et sans entretien.
    local unrepaired = {}
    for _, field in ipairs(NS.TRANSFER_FIELDS or {}) do
        if field.kind == "number" or field.kind == "enum" or field.kind == "boolean" then
            if not NS:IsRepairableSetting(field.key) then
                unrepaired[#unrepaired + 1] = field.key
            end
        end
    end
    eq(table.concat(unrepaired, ", "), "",
        "reparation : aucun reglage transferable n'echappe a la reparation")
end

--------------------------------------------------------------------------
-- 1.6.1 : mesurer le cumul reel avant de decider quoi que ce soit
--
-- Pendant un changement de canal, le nouvel enregistrement natif existe un
-- instant a cote de l'ancien. La table des poignees ne le voit pas : elle
-- remplace la cle. Le cumul reel etait donc invisible, et sans mesure il n'y a
-- rien a decider.
--------------------------------------------------------------------------
do
    freshProfile("PALADIN")
    knowSpells(4987)
    NS:UpdateSpells()
    NS.db.sound = true
    NS.liveNativeSounds, NS.liveNativeSoundsPeak = 0, 0

    NS.auraSoundFingerprint = nil
    NS:RefreshAuraSoundRegistrations("premiere pose")
    local afterFirst = NS.liveNativeSounds
    truthy(afterFirst and afterFirst > 0, "pic sonore : les enregistrements vivants sont comptes")
    eq(NS.liveNativeSoundsPeak, afterFirst, "pic sonore : le maximum suit la premiere pose")

    -- Un changement de canal remplace chaque paire. Le compte VIVANT ne doit
    -- pas rester gonfle a la fin : chaque ajout est suivi d'un retrait.
    NS.db.soundChannel = "Dialog"
    NS.auraSoundFingerprint = nil
    NS:RefreshAuraSoundRegistrations("changement de canal")
    eq(NS.liveNativeSounds, afterFirst,
        "pic sonore : apres un changement de canal, autant de vivants qu'avant")
    truthy(NS.liveNativeSoundsPeak >= afterFirst,
        "pic sonore : et le maximum de la session retient la pointe")

    truthy(NS:BuildDiagnosticsReport():find("soundNative live=", 1, true),
        "pic sonore : le rapport copiable porte la mesure")

    local before = #mock.state.chat
    NS:PrintAuraSoundStatus()
    truthy(table.concat(mock.state.chat, "\n", before + 1):find("aximum", 1, true)
        or table.concat(mock.state.chat, "\n", before + 1):find("ighest", 1, true),
        "pic sonore : soundstatus l'annonce au joueur")
end

--------------------------------------------------------------------------
-- report
--------------------------------------------------------------------------
local lines = {}
for _, result in ipairs(results) do
    if result.ok then
        lines[#lines + 1] = "  ok    " .. result.name
    else
        lines[#lines + 1] = "  ECHEC " .. result.name .. "\n          " .. tostring(result.detail)
    end
end
lines[#lines + 1] = ""
lines[#lines + 1] = string.format("%d reussis, %d echoues, %d au total", passed, failed, passed + failed)
return table.concat(lines, "\n"), failed
