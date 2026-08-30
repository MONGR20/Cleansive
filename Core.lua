local addonName, NS = ...

NS.addonName = addonName

-- Retail 12.1 marks five unit APIs secret-capable: UnitGUID and UnitClass and
-- UnitFullName under SecretWhenUnitIdentityRestricted, UnitName under
-- SecretWhenUnitNameIdentityRestricted, UnitIsUnit under
-- SecretWhenUnitComparisonRestricted. An unreadable value cannot be used in
-- `or`, in a comparison, in a concatenation, or as a table key. 1.5.14 guarded
-- the first two and stopped there; the rest are guarded here.
function NS:CanAccess(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

function NS:SafeUnitGUID(unit)
    if not unit or not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not self:CanAccess(guid) then return nil end
    return guid
end

function NS:IsPlayerUnit(unit)
    -- Two literal tokens compare without ever asking the client.
    if unit == "player" then return true end
    if not unit or not UnitIsUnit then return false end
    local ok, same = pcall(UnitIsUnit, unit, "player")
    if not ok or not self:CanAccess(same) then return false end
    return same == true
end

function NS:SafeUnitName(unit)
    if not unit or not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok or not self:CanAccess(name) or type(name) ~= "string" then return nil end
    return name
end

-- GetUnitName is not an escape hatch: Blizzard's own implementation calls
-- UnitName, tests the realm and concatenates the two, so a secret is evaluated
-- before this addon ever sees it. Build the qualified name here instead.
function NS:SafeUnitFullName(unit)
    local name = self:SafeUnitName(unit)
    if not name then return nil end
    if UnitFullName then
        local ok, _, realm = pcall(UnitFullName, unit)
        if ok and self:CanAccess(realm) and type(realm) == "string" and realm ~= "" then
            return name .. "-" .. realm
        end
    end
    return name
end

function NS:SafeUnitRole(unit)
    if not unit or not UnitGroupRolesAssigned then return "NONE" end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or not self:CanAccess(role) or type(role) ~= "string" then return "NONE" end
    return role
end

function NS:SafeUnitClass(unit)
    if not unit or not UnitClass then return nil end
    local ok, _, token = pcall(UnitClass, unit)
    if not ok or not self:CanAccess(token) or type(token) ~= "string" then return nil end
    return token
end

-- The .toc is the single source of truth for the version. This used to be a
-- second literal and it drifted: 1.5.8 shipped with the sidebar still saying
-- v1.5.7, because bumping the .toc does not touch a copy kept here.
NS.version = (C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "dev"

-- Le champ est remplace par l'empaqueteur. Sur une copie de travail il reste
-- le jeton tel quel : l'afficher ferait passer un artefact de fabrication pour
-- une information. La regle vit dans une fonction pour pouvoir etre eprouvee
-- des deux cotes, la valeur ne se calculant qu'une fois au chargement.
function NS:NormalizeRevision(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    if string.find(raw, "@", 1, true) then return nil end
    return raw
end

NS.revision = NS:NormalizeRevision(C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(addonName, "X-Revision"))
NS.playerClass = NS:SafeUnitClass("player")
NS.blacklist = {}
NS.testMode = false
NS.enabled = true
NS.pendingRoster = false
NS.pendingLayout = false
NS.pendingSpells = false
NS.pendingEnabled = false
NS.pendingEnabledValue = nil
NS.pendingPositionReset = false
NS.pendingGridVisibility = false
NS.pendingGridVisibilityValue = nil
NS.pendingVisibilityDriver = false
NS.pendingAnchorAppearance = false
NS.pendingProfileSwitch = false
NS.pendingPriorityBinding = false
NS.gridManuallyHidden = false
NS.afflictionSoundFile = "Interface\\AddOns\\Cleansive\\Sounds\\Dispel.wav"

local defaults = {
    language = "enUS",
    enabled = true,
    locked = false,
    showPets = true,
    showFocus = true,
    showNames = false,
    classColorCells = false,
    alertSound = "DEFAULT",
    separateRaidSize = false,
    raidFrameSize = 18,
    raidSpacing = 2,
    showTooltips = true,
    sound = true,
    soundChannel = "Master",
    soundMaxRegistrations = 4500,
    failureSound = true,
    showCooldown = true,
    showDuration = true,
    showStacks = false,
    showClickHints = false,
    autoHide = false,
    afflictedOnly = false,
    groupManualTypes = false,
    priorityKey = "",
    frameSize = 22,
    spacing = 2,
    columns = 10,
    inactiveAlpha = 0.18,
    blacklistTime = 5,
    sortMode = "GROUP",
    controlWarning = false,
    controlTypes = {},
    showSolo = true,
    showParty = true,
    showRaid = true,
    testUnits = 5,
    testState = "MIXED",
    grow = "RIGHT_DOWN",
    layoutMode = "GRID",
    typeOrder = { "Magic", "Curse", "Poison", "Disease", "Bleed", "Charm" },
    enabledTypes = {
        Magic = true, Curse = true, Poison = true, Disease = true, Bleed = true, Charm = true,
    },
    priority = {},
    skip = {},
    ignoredAlways = {},
    ignoredCombat = {},
    positions = {
        grid = { point = "CENTER", relativePoint = "CENTER", x = -180, y = -120 },
    },
}
NS.profileDefaults = defaults

local function copyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            copyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

function NS:Print(message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    local classColors = _G.CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local classColor = classColors and classColors[self.playerClass]
    local colorCode = classColor and classColor.colorStr
    if not colorCode and classColor then
        colorCode = string.format("ff%02x%02x%02x",
            math.floor((classColor.r or 1) * 255 + 0.5),
            math.floor((classColor.g or 1) * 255 + 0.5),
            math.floor((classColor.b or 1) * 255 + 0.5))
    end
    colorCode = colorCode or "ff58d7ff"
    if #colorCode == 6 then colorCode = "ff" .. colorCode end
    DEFAULT_CHAT_FRAME:AddMessage("|c" .. colorCode .. "Cleansive:|r " .. tostring(message))
end

function NS:SetLanguage(language)
    if language ~= "frFR" then language = "enUS" end
    if self.db.language == language then return end
    self.db.language = language
    if self.dbRoot and self.dbRoot.global then self.dbRoot.global.language = language end
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(self.L.LANGUAGE_RELOAD)
end

function NS:SavePosition(frame, key)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    self.db.positions[key] = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
    if key == "grid" and frame == self.gridAnchor and self.cooldownBody then
        self:RestorePosition(self.cooldownBody, "grid")
    end
end

function NS:RestorePosition(frame, key)
    local pos = self.db.positions[key] or defaults.positions[key]
    -- Normalisation repairs a saved position at load, but this runs on every
    -- restore and SetPoint raises on a bad anchor. A grid that cannot be placed
    -- must not stop the addon from starting.
    if type(pos) ~= "table" or type(pos.point) ~= "string"
        or type(pos.relativePoint) ~= "string"
        or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
        pos = defaults.positions[key]
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    if key == "grid" and frame == self.gridAnchor and self.cooldownBody then
        self.cooldownBody:ClearAllPoints()
        self.cooldownBody:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    end
end

function NS:ResetPositions()
    self.db.positions.grid = { point = "CENTER", relativePoint = "CENTER", x = -180, y = -120 }
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingPositionReset")
        -- The wrap depends on where the anchor sits, so replaying the position
        -- after combat is not enough: without this the grid keeps the wrap it
        -- computed for the old corner and can end up off screen once centred.
        self:MarkPending("pendingLayout")
        self:Print(self.L.COMBAT_LOCKED)
        return
    end
    if self.gridAnchor then
        self:RestorePosition(self.gridAnchor, "grid")
        -- Same reason as OnDragStop: the cell count depends on the anchor.
        if self.LayoutButtons then self:LayoutButtons() end
    end
    self:Print(self.L.RESET_DONE)
end

function NS:SetEnabled(enabled, silent)
    self.db.enabled = enabled and true or false
    if InCombatLockdown and InCombatLockdown() then
        self.pendingEnabledValue = self.db.enabled
        self:MarkPending("pendingEnabled")
        self:Print(self.L.COMBAT_LOCKED)
        return
    end
    self.enabled = self.db.enabled
    if self.enabled then self.gridManuallyHidden = false end
    self:UpdateGridVisibilityDriver()
    if self.ApplyPriorityDispelBinding then self:ApplyPriorityDispelBinding() end
    self.pendingEnabled = nil
    if self.RequestAuraSoundRefresh then
        self:RequestAuraSoundRefresh("addon enabled state")
    end
    if not silent then self:Print(enabled and self.L.ENABLED or self.L.DISABLED) end
end

function NS:SetGridVisible(visible, silent)
    visible = visible and true or false
    if InCombatLockdown and InCombatLockdown() then
        self.pendingGridVisibilityValue = visible
        self:MarkPending("pendingGridVisibility")
        self:Print(self.L.COMBAT_LOCKED)
        return
    end
    self.gridManuallyHidden = not visible
    self.pendingGridVisibility = nil
    self:UpdateGridVisibilityDriver()
    self:RequestAuraSoundRefresh("grid visibility")
    if not silent then
        if visible and not self.enabled then
            self:Print(self.L.DISABLED)
        else
            self:Print(visible and self.L.GRID_SHOWN or self.L.GRID_HIDDEN)
        end
    end
end

function NS:ToggleGridVisibility()
    if not self.enabled then
        self:SetEnabled(true)
    else
        self:SetGridVisible(self.gridManuallyHidden)
    end
end

local TEST_STATES = { "MIXED", "ALL", "HEALTHY" }

function NS:TestModeBlockedByCombat()
    if not (InCombatLockdown and InCombatLockdown()) then return false end
    self:Print(self.L.TEST_COMBAT_REFUSED)
    return true
end

function NS:ToggleTest()
    -- Refuser aussi l'extinction : elle passe par RebuildRoster, qui serait
    -- reporte, et les cases resteraient sur de fausses afflictions.
    if self:TestModeBlockedByCombat() then return end
    self.testMode = not self.testMode
    if not self.testMode then self.testModeFromOptions = nil end
    -- The preview cells live in the roster, so the roster is what changes.
    self:RebuildRoster()
    self:RefreshAll(true)
    self:UpdateGridVisibilityDriver()
    if self.RefreshOptions then self:RefreshOptions() end
    if self.testMode then self:PlayAfflictionAlert(true) end
    self:Print(self.testMode and self.L.TEST_ON or self.L.TEST_OFF)
end

-- Leaving the preview up into a pull would show fake afflictions over a real
-- fight, and the secure attributes could no longer be rewritten. Close it at
-- the pull: the cells that remain until combat ends are inert and quiet.
function NS:EndTestModeForCombat()
    if not self.testMode then return end
    self.testMode = false
    self:RebuildRoster()
    self:RefreshAll(true)
    self:UpdateGridVisibilityDriver()
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(self.L.TEST_OFF_COMBAT)
end

function NS:SetTestUnits(count)
    if self:TestModeBlockedByCombat() then return end
    count = math.max(1, math.min(40, math.floor(tonumber(count) or 1)))
    self.db.testUnits = count
    if not self.testMode then
        self:ToggleTest()
    else
        self:RebuildRoster()
        self:RefreshAll(true)
        if self.RefreshOptions then self:RefreshOptions() end
    end
    self:Print(self.L.TEST_UNITS_SET, count)
end

function NS:SetTestState(state)
    local wanted
    for _, candidate in ipairs(TEST_STATES) do
        if candidate == state then wanted = candidate end
    end
    if not wanted then return false end
    self.db.testState = wanted
    if self.testMode then self:RefreshAll(true) end
    if self.RefreshOptions then self:RefreshOptions() end
    return true
end

function NS:CycleTestState()
    local current = self.db.testState or "MIXED"
    local index = 1
    for position, candidate in ipairs(TEST_STATES) do
        if candidate == current then index = position end
    end
    self:SetTestState(TEST_STATES[(index % #TEST_STATES) + 1])
end

function NS:TestStateLabel()
    local state = self.db and self.db.testState or "MIXED"
    if state == "ALL" then return self.L.TEST_STATE_ALL end
    if state == "HEALTHY" then return self.L.TEST_STATE_HEALTHY end
    return self.L.TEST_STATE_MIXED
end

function NS:VisibilityDriverMacro()
    local contexts = {}
    if self.db.showSolo ~= false then contexts[#contexts + 1] = "nogroup" end
    -- « nogroup:raid » n'est pas une precaution decorative. Selon la lecture que
    -- le client fait de « group:party », un raid est OU N'EST PAS un groupe :
    -- dans la premiere, « Afficher en raid » eteint ne servait a rien -- la
    -- clause de groupe rallumait la grille en raid, et le son avec elle.
    -- Impossible de trancher hors du client : la macro est donc ecrite pour
    -- dire la meme chose dans les deux lectures.
    if self.db.showParty ~= false then contexts[#contexts + 1] = "group:party,nogroup:raid" end
    if self.db.showRaid ~= false then contexts[#contexts + 1] = "group:raid" end
    if #contexts == 0 then return "hide" end
    local prefix = self.db.autoHide and "combat," or ""
    local parts = {}
    for index, context in ipairs(contexts) do
        parts[index] = "[" .. prefix .. context .. "]"
    end
    return table.concat(parts) .. " show; hide"
end

-- Le pilote de visibilite est SECURISE : il decide seul, et ne rend jamais son
-- verdict a Lua. Le son, lui, est pose depuis Lua. Les deux ne se parlaient pas :
-- « Afficher en raid » eteint, la grille disparaissait et l'alerte continuait de
-- sonner. Retour joueur du 30/08/2026 : en raid, l'addon « sonne en boucle »
-- alors qu'il n'affiche rien, et la seule sortie etait de couper le son a la main.
-- Ceci rejoue la meme regle en Lua. Un test compare les deux verdicts sur toutes
-- les combinaisons : le jour ou la macro change, le miroir doit changer avec elle.
-- combatOverride existe parce que PLAYER_REGEN_DISABLED arrive avant que
-- InCombatLockdown ne bascule : l'appelant sait, la fonction non.
function NS:GridWouldBeVisible(combatOverride)
    if not self.enabled then return false end
    -- L'apercu et la fenetre de reglages forcent l'affichage : ce que le joueur
    -- regarde doit s'entendre.
    if self.testMode then return true end
    if self.optionsFrame and self.optionsFrame:IsShown() then return true end
    if self.gridManuallyHidden then return false end
    if not self:NeedsVisibilityDriver() then return true end
    local allowed
    if IsInRaid and IsInRaid() then allowed = self.db.showRaid ~= false
    elseif IsInGroup and IsInGroup() then allowed = self.db.showParty ~= false
    else allowed = self.db.showSolo ~= false end
    if not allowed then return false end
    local inCombat = combatOverride
    if inCombat == nil then inCombat = InCombatLockdown and InCombatLockdown() end
    if self.db.autoHide and not inCombat then return false end
    return true
end

-- Every context allowed and no combat rule means "always": registering a
-- driver that can only ever say show would put the grid under a secure rule
-- for nothing, and a secure rule cannot be lifted during combat.
function NS:NeedsVisibilityDriver()
    if self.db.autoHide then return true end
    return self.db.showSolo == false or self.db.showParty == false
        or self.db.showRaid == false
end

-- Une grille de raid n'a pas les memes contraintes qu'une grille de groupe :
-- quarante cases a la taille d'un groupe de cinq ne tiennent nulle part. Les
-- deux jeux de valeurs sont separes SUR DEMANDE ; par defaut le raid utilise
-- ceux du groupe, donc rien ne bouge pour qui n'y touche pas.
--
-- Dix-huit endroits lisaient db.frameSize et db.spacing directement. Ils
-- passent tous par ici : c'est la seule facon que la geometrie ne se decide
-- qu'a un seul endroit.
function NS:UsesRaidGeometry()
    if not (self.db and self.db.separateRaidSize) then return false end
    -- L'apercu existe pour regler une grille de raid SANS raid. Au-dela de la
    -- taille d'un groupe, c'est donc la geometrie de raid qu'il doit montrer,
    -- sinon il ne sert plus a ce pour quoi il a ete fait.
    if self.testMode then return (tonumber(self.db.testUnits) or 1) > 5 end
    return IsInRaid and IsInRaid() and true or false
end

function NS:CellSize()
    local base = tonumber(self.db and self.db.frameSize) or 22
    if not self:UsesRaidGeometry() then return base end
    return tonumber(self.db.raidFrameSize) or base
end

function NS:CellSpacing()
    local base = tonumber(self.db and self.db.spacing) or 4
    if not self:UsesRaidGeometry() then return base end
    return tonumber(self.db.raidSpacing) or base
end

-- Entrer ou sortir d'un raid redessine deja : AssignRosterToButtons termine par
-- LayoutButtons, et RebuildRoster passe par lui. J'avais ajoute un garde-fou
-- pour ce cas ; l'injection de defaut est restee VERTE, ce qui voulait dire
-- qu'il ne servait a rien. Il est parti. Lister les appelants avant d'ajouter
-- une garde, pas apres.

function NS:UpdateGridVisibilityDriver()
    if not self.gridAnchor then return end
    if self.UpdateCooldownOverlayVisibility then self:UpdateCooldownOverlayVisibility() end
    -- Un seul endroit : toute bascule de visibilite passe par ici, donc le
    -- registre sonore est reevalue quel que soit l'appelant.
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("visibility rules") end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingVisibilityDriver")
        return
    end
    local body = self.gridBody or self.gridAnchor
    if UnregisterStateDriver then
        UnregisterStateDriver(self.gridAnchor, "visibility")
        if body ~= self.gridAnchor then UnregisterStateDriver(body, "visibility") end
    end
    self.pendingVisibilityDriver = false

    -- The anchor carries the drag handle and its Ctrl/Shift/Alt menus, so it
    -- only follows the enabled state. Everything else drives the cell body.
    if not self.enabled then
        self.gridAnchor:Hide()
        body:Hide()
        return
    end
    self.gridAnchor:Show()

    -- The settings window is open: the player is placing and sizing the grid,
    -- and a rule that hides it now would hide the thing being configured.
    local configuring = self.optionsFrame and self.optionsFrame:IsShown()
    if self.testMode or configuring then
        body:Show()
    elseif self.gridManuallyHidden then
        body:Hide()
    elseif self:NeedsVisibilityDriver() and RegisterStateDriver then
        RegisterStateDriver(body, "visibility", self:VisibilityDriverMacro())
    else
        body:Show()
    end
end

-- P2 de l'audit du 30/08 : cette couche decidait seule, sans jamais lire
-- showSolo, showParty ni showRaid. « Afficher en raid » eteint, le pilote
-- securise masquait les cases en entrant en raid -- et un chiffre de recharge,
-- le badge TEST, la plaque d'attente ou l'indicateur manuel pouvaient rester
-- seuls a l'ecran, sans grille dessous.
--
-- Elle pose maintenant exactement la meme question que la grille. C'est le
-- troisieme consommateur de ce verdict apres le pilote et le registre sonore :
-- il n'y a plus qu'un seul endroit ou il se calcule.
function NS:UpdateCooldownOverlayVisibility(combatOverride)
    local overlay = self.cooldownBody
    if not overlay then return end
    overlay:SetShown(self:GridWouldBeVisible(combatOverride) and true or false)
end

-- Les sons integres sont lus dans SOUNDKIT AU MOMENT ou on en a besoin, jamais
-- recopies en dur. Un identifiant invente ne leve pas : il ne joue rien. Une
-- alerte silencieuse serait pire que le son juge trop aigu, qui est la demande
-- d'origine. Un son que ce client ne connait pas disparait donc de la liste.
NS.ALERT_SOUNDS = {
    { key = "DEFAULT" },
    { key = "RAID_WARNING", kit = "RAID_WARNING" },
    { key = "READY_CHECK", kit = "READY_CHECK" },
    { key = "QUEST_FAILED", kit = "IG_QUEST_FAILED" },
    { key = "ALARM", kit = "ALARM_CLOCK_WARNING_3" },
}

function NS:AvailableAlertSounds()
    local list = {}
    for _, entry in ipairs(self.ALERT_SOUNDS) do
        if not entry.kit then
            list[#list + 1] = entry
        elseif type(SOUNDKIT) == "table" and type(SOUNDKIT[entry.kit]) == "number" then
            list[#list + 1] = entry
        end
    end
    return list
end

-- nil signifie « le fichier livre ». Un choix devenu introuvable -- profil
-- importe d'un client qui connaissait ce son, ou nom retire par Blizzard --
-- retombe sur ce fichier plutot que de se taire.
function NS:AlertSoundKit()
    local chosen = self.db and self.db.alertSound
    if not chosen or chosen == "DEFAULT" then return nil end
    for _, entry in ipairs(self:AvailableAlertSounds()) do
        if entry.key == chosen and entry.kit then return SOUNDKIT[entry.kit] end
    end
    return nil
end

function NS:SetAlertSound(key)
    for _, entry in ipairs(self:AvailableAlertSounds()) do
        if entry.key == key then
            self.db.alertSound = key
            self:Print(self.L.ALERT_SOUND_SET, self.L["ALERT_SOUND_" .. key] or key)
            -- Le registre natif ne prend qu'un NOM DE FICHIER : un son integre
            -- s'adresse par identifiant et ne peut pas y entrer. Les afflictions
            -- que Blizzard protege gardent donc le son livre, et il vaut mieux
            -- le dire une fois que de laisser decouvrir deux sons differents.
            if key ~= "DEFAULT" and self:IsNativeAuraSoundAvailable() then
                self:Print(self.L.ALERT_SOUND_NATIVE_NOTE)
            end
            self:PlayAfflictionAlert(true)
            if self.RefreshOptions then self:RefreshOptions() end
            return true
        end
    end
    return false
end

-- Le bouton fait tourner la liste. Une liste deroulante pour quatre entrees
-- serait un menu de plus a ouvrir pour un choix qui se fait a l'oreille.
function NS:CycleAlertSound()
    local list = self:AvailableAlertSounds()
    local current, index = self.db and self.db.alertSound or "DEFAULT", 1
    for position, entry in ipairs(list) do
        if entry.key == current then index = position end
    end
    local nextEntry = list[(index % #list) + 1]
    if nextEntry then self:SetAlertSound(nextEntry.key) end
end

function NS:PrintAlertSounds()
    local current = self.db and self.db.alertSound or "DEFAULT"
    for _, entry in ipairs(self:AvailableAlertSounds()) do
        local name = self.L["ALERT_SOUND_" .. entry.key] or entry.key
        self:Print(string.format("%s%s  -  /cleansive sound %s",
            entry.key == current and "> " or "   ", name, string.lower(entry.key)))
    end
end

-- Un seul verbe par ligne, et le resultat dit ce qui s'est passe : ces
-- operations touchent des reglages partages entre personnages, et un silence
-- apres « supprimer » serait la pire des reponses.
function NS:HandleProfileCommand(rest)
    local verb, argument = rest:match("^(%S*)%s*(.-)$")
    verb = string.lower(verb or "")

    if verb == "" or verb == "list" then
        local active = self:ActiveNamedProfile()
        self:Print(string.format(self.L.PROFILE_ACTIVE, self:GetActiveProfileLabel()))
        for _, name in ipairs(self:NamedProfiles()) do
            self:Print((name == active and "> " or "   ") .. name)
        end
        self:Print(self.L.PROFILE_COMMAND_HINT)
        return
    end

    local ok, message
    if verb == "new" then
        ok, message = self:CreateNamedProfile(argument)
    elseif verb == "use" then
        ok, message = self:UseNamedProfile(argument)
    elseif verb == "own" then
        ok, message = self:UseOwnProfile()
    elseif verb == "delete" then
        ok, message = self:DeleteNamedProfile(argument)
    elseif verb == "rename" then
        -- Deux noms sur une ligne : le separateur est une barre verticale, un
        -- caractere qu'un nom ne peut pas contenir puisqu'il sert deja de
        -- separateur dans l'export.
        local from, to = argument:match("^(.-)%s*|%s*(.-)$")
        if not from or from == "" then
            self:Print(self.L.PROFILE_RENAME_HINT)
            return
        end
        ok, message = self:RenameNamedProfile(from, to)
    else
        self:Print(self.L.PROFILE_COMMAND_HINT)
        return
    end
    self:Print(message)
    if ok and self.RefreshOptions then self:RefreshOptions() end
end

function NS:PlayAfflictionAlert(preview)
    if not self.db or not self.db.sound or not self.enabled then return false end
    -- Une alerte d'essai est un geste du joueur : elle se joue toujours. Une
    -- vraie alerte parle d'une case, et se tait si cette case n'est pas la.
    if not preview and not self:GridWouldBeVisible() then return false end

    -- Several party members can receive the same effect in one combat event.
    -- Merge those near-simultaneous notifications into one clear alert.
    local now = GetTime and GetTime() or 0
    if not preview and self.lastAfflictionSound and now - self.lastAfflictionSound < 0.20 then return true end
    self.lastAfflictionSound = now

    local played = false
    local kit = self:AlertSoundKit()
    if kit and PlaySound then
        local ok, willPlay = pcall(PlaySound, kit, self.db.soundChannel or "Master")
        played = ok and willPlay ~= false
    end
    if not played and PlaySoundFile then
        local ok, willPlay = pcall(PlaySoundFile, self.afflictionSoundFile, self.db.soundChannel or "Master")
        played = ok and willPlay ~= false
    end
    if not played and PlaySound then
        local ok, willPlay = pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, self.db.soundChannel or "Master")
        played = ok and willPlay ~= false
    end
    if preview and not played then self:Print(self.L.SOUND_PLAYBACK_FAILED) end
    return played
end

local function spellName(def)
    return def and (def.secureName or def.name) or nil
end

local function mouseoverClause(def, modifier)
    local name = spellName(def)
    if not name then return nil end
    local conditions = {}
    if modifier then conditions[#conditions + 1] = modifier end
    conditions[#conditions + 1] = "@mouseover"
    conditions[#conditions + 1] = def.hostile and "harm" or "help"
    conditions[#conditions + 1] = "nodead"
    return "[" .. table.concat(conditions, ",") .. "] " .. name
end

function NS:BuildMacroBody()
    local one = spellName(self.clickSpells and self.clickSpells[1])
    local two = spellName(self.clickSpells and self.clickSpells[2])
    local three = spellName(self.clickSpells and self.clickSpells[3])
    if not one then return nil end

    -- Let WoW resolve the icon from the active /cast branch. Keeping the
    -- tooltip line compact leaves enough room for localized spell names.
    local show = "#showtooltip"
    local cast = "/cast " .. mouseoverClause(self.clickSpells[1])
    if two then
        cast = "/cast " .. mouseoverClause(self.clickSpells[2], "mod:shift") .. "; " .. mouseoverClause(self.clickSpells[1])
    end
    if three then
        cast = "/cast " .. mouseoverClause(self.clickSpells[3], "mod:ctrl") .. "; "
            .. mouseoverClause(self.clickSpells[2] or self.clickSpells[1], "mod:shift") .. "; "
            .. mouseoverClause(self.clickSpells[1])
    end
    return show .. "\n" .. cast
end

function NS:CreateMouseoverMacro()
    if InCombatLockdown and InCombatLockdown() then
        self:Print(self.L.MACRO_COMBAT)
        return
    end
    local body = self:BuildMacroBody()
    if not body then
        self:Print(self.L.NO_CURE)
        return
    end
    if #body > 255 then
        self:Print(self.L.MACRO_TOO_LONG, #body)
        return
    end
    local index = GetMacroIndexByName and GetMacroIndexByName("Cleansive") or 0
    if index and index > 0 then
        local ok, edited = pcall(EditMacro, index, "Cleansive", 135894, body, false)
        if not ok or not edited then
            self:Print(self.L.MACRO_FAILED)
            return
        end
    else
        local created = CreateMacro and CreateMacro("Cleansive", 135894, body, false)
        if not created then
            self:Print(self.L.MACRO_FULL)
            return
        end
    end
    self:Print(self.L.MACRO_CREATED)
end

function NS:RecordSecureClick(button, mouseButton)
    if not button or not button.unit then return end
    -- Button4 casts the third cleanse (1.5.43) but was not listed here, so the
    -- click was performed by the game and never recorded: the cell kept the
    -- previous spell's cooldown, or none. The secure binding and this ledger
    -- have to name the same buttons.
    if mouseButton and mouseButton ~= "LeftButton" and mouseButton ~= "RightButton"
        and mouseButton ~= "Button4" then
        return
    end
    local slot = 1
    if mouseButton == "RightButton" then
        slot = 2
    elseif mouseButton == "Button4"
        or (mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown()) then
        slot = 3
    end
    if not (self.clickSpells and self.clickSpells[slot]) then slot = 1 end
    if not (self.clickSpells and self.clickSpells[slot]) then slot = nil end

    -- Remember the secure action actually used. This is the only truthful
    -- spell choice available when the AuraSlot itself is protected.
    button.cooldownSlot = slot
    button.cooldownClickTime = GetTime()
    self.lastClick = {
        unit = button.unit,
        guid = self:SafeUnitGUID(button.unit),
        time = GetTime(),
        slot = slot,
    }

    local unit, guid = button.unit, self:SafeUnitGUID(button.unit)
    local function refreshClickedCooldown()
        if button.unit ~= unit or (guid and self:SafeUnitGUID(unit) ~= guid) then return end
        local def = slot and self.clickSpells and self.clickSpells[slot]
        if self.SetCooldown then self:SetCooldown(button, def) end
    end
    if C_Timer and C_Timer.After then
        -- The first cooldown event can be the GCD and arrive before the spell
        -- cooldown/charge object is populated. Recheck across that short
        -- window instead of forgetting the secure click on the first zero.
        C_Timer.After(0, refreshClickedCooldown)
        C_Timer.After(0.06, refreshClickedCooldown)
        C_Timer.After(0.20, refreshClickedCooldown)
        C_Timer.After(0.75, function()
            refreshClickedCooldown()
            if self.RefreshDispelCooldowns then self:RefreshDispelCooldowns() end
        end)
    else
        refreshClickedCooldown()
    end
end

function NS:IsBlacklistError(errorType, message)
    local enum = Enum and Enum.UIErrorMessage
    if enum then
        if errorType == enum.SpellFailedLineOfSight or errorType == enum.SpellFailedOutOfRange or errorType == enum.SpellFailedBadTargets then
            return true
        end
    end
    return message == SPELL_FAILED_LINE_OF_SIGHT or message == SPELL_FAILED_OUT_OF_RANGE or message == ERR_OUT_OF_RANGE
end

function NS:OnUIError(errorType, message)
    if not self.lastClick or GetTime() - self.lastClick.time > 0.8 then return end
    if not self:IsBlacklistError(errorType, message) then return end
    local unit = self.lastClick.unit
    local guid = self.lastClick.guid
    local key = guid or unit
    local duration = math.max(0, tonumber(self.db.blacklistTime) or 0)
    self.blacklist[key] = GetTime() + duration
    if duration > 0 and C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.05, function()
            local expires = self.blacklist[key]
            if not expires or expires > GetTime() then return end
            self.blacklist[key] = nil
            if unit and UnitExists(unit) and (not guid or self:SafeUnitGUID(unit) == guid) then
                self:RefreshUnit(unit)
            end
        end)
    end
    if self.db.failureSound and SOUNDKIT then
        PlaySound(SOUNDKIT.IG_QUEST_FAILED or 847, self.db.soundChannel or "Master")
    end
    self:RefreshAll(true)
end

local function addEscapeFrame(frameName)
    if not UISpecialFrames then return end
    for index = 1, #UISpecialFrames do
        if UISpecialFrames[index] == frameName then return end
    end
    UISpecialFrames[#UISpecialFrames + 1] = frameName
end

function NS:RegisterBlizzardSettings()
    addEscapeFrame("CleansiveOptionsFrame")
    addEscapeFrame("CleansiveListFrame")
    addEscapeFrame("CleansiveFilterFrame")

    if self.settingsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory
        or not Settings.RegisterAddOnCategory then return end

    local panel = CreateFrame("Frame")
    panel.name = "Cleansive"
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(220, 30)
    button:SetPoint("CENTER")
    button:SetText(self.L.OPEN_CLEANSIVE)
    button:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
            HideUIPanel(SettingsPanel)
        end
        local function openOptions()
            if self.optionsFrame then self.optionsFrame:Show() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, openOptions) else openOptions() end
    end)
    self.settingsPanel = panel
    self.settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Cleansive")
    Settings.RegisterAddOnCategory(self.settingsCategory)
end

function NS:IsBlacklisted(unit)
    local key = self:SafeUnitGUID(unit) or unit
    local expires = self.blacklist[key]
    if not expires then return false end
    if expires <= GetTime() then
        self.blacklist[key] = nil
        return false
    end
    return true
end

function NS:Initialize()
    CleansiveDB = CleansiveDB or {}
    if self.InitializeProfiles then
        self:InitializeProfiles()
    else
        copyDefaults(defaults, CleansiveDB)
        self.db = CleansiveDB
    end
    self.enabled = self.db.enabled
    self.playerClass = self:SafeUnitClass("player")
    self:RefreshBindingLabels()

    -- Resolve the click mapping before the 12.1 engine-owned aura slots are
    -- created, so their first protected styling pass is already correct.
    self:UpdateSpells()
    self:CreateFrames()
    self:CreateOptions()
    if self.CreateSetupWizard then self:CreateSetupWizard() end
    self:RegisterBlizzardSettings()
    self:RebuildRoster()
    self:SetEnabled(self.db.enabled, true)
    self:RefreshAll(true)
    if self.ShowSetupWizardIfNeeded then self:ShowSetupWizardIfNeeded() end
    self:Print(self.L.READY)
end

function NS:FlushCombatUpdates()
    self.combatExitRefreshScheduled = false
    if InCombatLockdown and InCombatLockdown() then return end

    local profileChanged = false
    if self.pendingProfileSwitch and self.LoadCurrentProfile then
        self.pendingProfileSwitch = false
        profileChanged = self:LoadCurrentProfile(true)
    end
    local needsSpells = profileChanged or (self.pendingSpells and true or false)
    local needsRoster = profileChanged or (self.pendingRoster and true or false)
    local needsLayout = profileChanged or (self.pendingLayout and true or false)
    local needsAuraStyle = profileChanged or (self.pendingAuraStyle and true or false)

    if self.pendingPositionReset then
        self.pendingPositionReset = false
        if self.gridAnchor then self:RestorePosition(self.gridAnchor, "grid") end
    end

    self.deferRefreshes = true
    if needsSpells then self:UpdateSpells() end
    if needsRoster then self:RebuildRoster() end
    self.deferRefreshes = false

    if needsSpells or needsRoster then self:ApplySecureBindings() end
    -- A specialization change during combat cannot rebuild the engine
    -- slots; replay it now so the type set is not left stale.
    if self.pendingAuraEngineRebuild and self.RefreshAuraEngineTypes
        and not self.encounterActive then
        self:RefreshAuraEngineTypes()
    end
    self.pendingAuraFilters = false
    self.pendingAuraStyle = false
    -- A profile's position has to be in place before its grid is computed:
    -- LayoutButtons reads the anchor's edges, and restoring afterwards sized
    -- the new profile from the old profile's position.
    if profileChanged and self.gridAnchor then self:RestorePosition(self.gridAnchor, "grid") end
    local configured = false
    if needsRoster or needsLayout then
        self:LayoutButtons()
        configured = true
    elseif needsSpells or needsAuraStyle then
        self:UpdateAuraContainerConfiguration(true)
        configured = true
    end

    -- A layout/style pass also reapplies the candidate filters. Without such
    -- a pass, refresh them explicitly so combat-only exclusions expire now.
    if not configured then self:RefreshAuraCandidateFilters() end
    if self.RefreshOptions then self:RefreshOptions() end
    -- The flag says a change is waiting; the value says which. Keeping them in
    -- one field meant the plate could not see the deferral at all, because a
    -- business boolean is not the literal true the static check looks for.
    if self.pendingEnabled then
        self.pendingEnabled = false
        self:SetEnabled(self.pendingEnabledValue)
        self.pendingEnabledValue = nil
    end
    if self.pendingGridVisibility then
        self.pendingGridVisibility = false
        self:SetGridVisible(self.pendingGridVisibilityValue)
        self.pendingGridVisibilityValue = nil
    end
    if self.pendingVisibilityDriver or profileChanged then self:UpdateGridVisibilityDriver() end
    if self.pendingAnchorAppearance and self.UpdateGridAnchorAppearance then
        self:UpdateGridAnchorAppearance()
    end
    if self.pendingPriorityBinding then self:ApplyPriorityDispelBinding() end
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("combat ended") end
    self:RefreshAll(true)
    -- The plate went out because some refresh path happened to re-evaluate it,
    -- never because the flags were cleared. Disabling the addon in combat took
    -- a path that did not, and the plate survived its own reason.
    self:UpdatePendingIndicator()
end

function NS:OnCombatEnded()
    if self.combatExitRefreshScheduled then return end
    self.combatExitRefreshScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() self:FlushCombatUpdates() end)
    else
        self:FlushCombatUpdates()
    end
end

function NS:HandleSlash(message)
    local command, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "" or command == "options" or command == "config" then
        self:ToggleOptions()
    elseif command == "show" then
        self:SetGridVisible(true)
    elseif command == "hide" then
        self:SetGridVisible(false)
    elseif command == "reset" then
        self:ResetPositions()
    elseif command == "test" then
        -- Refuser la commande ENTIERE, pas seulement son effet visible : garder
        -- l'etat demande sans ouvrir l'apercu serait une commande a moitie
        -- appliquee qui se declare reussie.
        if self:TestModeBlockedByCombat() then return end
        -- Demande a la main : l'apercu appartient au joueur, plus a la fenetre.
        self.testModeFromOptions = nil
        local count = tonumber(rest)
        if count then
            self:SetTestUnits(count)
        elseif rest ~= "" and self:SetTestState(string.upper(rest)) then
            if not self.testMode then self:ToggleTest() end
        else
            self:ToggleTest()
        end
    elseif command == "macro" then
        self:CreateMouseoverMacro()
    elseif command == "control" then
        if rest == "copy" then
            self:ShowCopyWindow(self.L.CONTROL_SEEN_TITLE, self.L.HISTORY_COPY_HINT,
                self:BuildControlReport())
        elseif rest == "clear" then
            local global = self.dbRoot and self.dbRoot.global
            if global then global.controlSeen = {} end
            self:Print(self.L.CONTROL_CLEARED)
        elseif rest == "" then
            self:PrintControlStatus()
        else
            local locType = string.upper(rest)
            local seen = self.dbRoot and self.dbRoot.global and self.dbRoot.global.controlSeen
            if type(seen) ~= "table" or not seen[locType] then
                self:Print(string.format(self.L.CONTROL_UNKNOWN, locType, locType))
            else
                self:ToggleControlType(locType)
                self:Print(string.format(self.L.CONTROL_TOGGLED, locType,
                    self.db.controlTypes[locType] and self.L.CONTROL_WATCHED or self.L.CONTROL_IGNORED))
            end
        end
    elseif command == "size" or command == "spacing" then
        local value = tonumber(rest)
        if not value then
            self:Print(self.L.HELP)
        elseif command == "size" then
            self.db.frameSize = math.max(12, math.min(40, math.floor(value)))
            self:LayoutButtons()
            if self.RefreshOptions then self:RefreshOptions() end
            self:Print(string.format(self.L.SIZE_SET, self.db.frameSize))
        else
            self.db.spacing = math.max(0, math.min(12, math.floor(value)))
            self:LayoutButtons()
            if self.RefreshOptions then self:RefreshOptions() end
            self:Print(string.format(self.L.SPACING_SET, self.db.spacing))
        end
    elseif command == "spells" then
        self:PrintSpellReport()
    elseif command == "version" then
        self:Print(string.format(self.L.VERSION_LINE, tostring(self.version),
            tostring(GetLocale and GetLocale() or "?"),
            tostring(self.playerClass or "?")))
    elseif command == "order" then
        self:PrintProcessingOrder()
    elseif command == "prio" or command == "priority" then
        if rest == "clear" then self:ClearList("priority") else self:ShowList("priority") end
    elseif command == "pradd" then
        self:AddTargetToList("priority")
    elseif command == "skip" then
        if rest == "clear" then self:ClearList("skip") else self:ShowList("skip") end
    elseif command == "skadd" then
        self:AddTargetToList("skip")
    elseif command == "filters" or command == "filter" then
        self:ShowFilters()
    elseif command == "history" then
        if self.optionsFrame then self.optionsFrame:Show() end
        if self.ShowOptionsPage then self:ShowOptionsPage("history") end
    elseif command == "setup" then
        if self.ShowSetupWizard then self:ShowSetupWizard(true) end
    elseif command == "enable" then
        self:SetEnabled(true)
    elseif command == "disable" then
        self:SetEnabled(false)
    elseif command == "soundtest" then
        self:PlayAfflictionAlert(true)
    elseif command == "profile" then
        self:HandleProfileCommand(rest)
    elseif command == "sound" then
        if rest == "" or not self:SetAlertSound(string.upper(rest)) then
            self:PrintAlertSounds()
        end
    elseif command == "alerts" then
        if rest == "clear" then self:ClearAlertDecisions() else self:PrintAlertDecisions() end
    elseif command == "coverage" then
        for _, line in ipairs(self:SoundCoverageByType()) do self:Print(line) end
    elseif command == "soundstatus" then
        if rest ~= "" then
            self:Print(self:DescribeSpellSound(rest))
        else
            self:PrintAuraSoundStatus()
        end
    elseif command == "cdstatus" then
        local status = self.cooldownDiagnostics
        if not status then
            self:Print(self.L.COOLDOWN_STATUS_NONE)
        else
            local suffix = status.error and (" | " .. status.error) or ""
            self:Print(self.L.COOLDOWN_STATUS,
                tostring(status.spellID or "-"), tostring(status.source or "-"),
                tostring(status.active), tostring(status.applied), suffix)
        end
    elseif command == "diag" then
        if rest == "reset" then
            NS:ResetDiagnostics()
        elseif rest == "copy" then
            NS:ShowDiagnosticsCopy()
        else
            NS:PrintDiagnostics()
        end
    elseif command == "help" then
        self:Print(self.L.HELP)
    elseif command == "ignore" then
        local id = tonumber(rest)
        if id then self:AddFilter(id, false) else self:ShowFilters() end
    else
        self:Print(self.L.HELP)
    end
end

-- Events the game raises on its own. A deferral caused by one of these is
-- bookkeeping, not a change the player is waiting for. PLAYER_FOCUS_CHANGED is
-- deliberately absent: setting a focus is a deliberate act, and its cell really
-- does wait for the end of the fight.
local GAME_DRIVEN_EVENTS = {
    PLAYER_ENTERING_WORLD = true, GROUP_ROSTER_UPDATE = true, UNIT_PET = true,
    SPELLS_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
    UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true,
    UNIT_AURA = true, UNIT_FLAGS = true, UNIT_FACTION = true, UNIT_CONNECTION = true,
}

local EVENT_NAMES = {
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_PET",
    "UNIT_CONNECTION", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_FOCUS_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
    "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "PLAYER_LOGOUT",
    -- La place disponible a l'ecran change sans prevenir : resolution, passage
    -- en fenetre, echelle de l'interface. Sans ces deux-la, les fenetres de
    -- l'addon gardaient l'echelle calculee a la connexion.
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    -- Purely observational. The client names the function it refused; until
    -- now Cleansive had to infer its refusals afterwards. Neither event is
    -- marked HasRestrictions, and the static check verifies that against
    -- Blizzard's own definitions rather than against this comment.
    "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
    "ENCOUNTER_START", "ENCOUNTER_END",
    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    -- The only signal that a restriction has lifted. Without it, work deferred
    -- because the client refused permission would wait for an unrelated event:
    -- a mythic key keeps ChallengeMode active long after the last pull, and
    -- PLAYER_REGEN_ENABLED fires while it is still on.
    "ADDON_RESTRICTION_STATE_CHANGED",
}

local events = CreateFrame("Frame")
NS.eventFrame = events
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end
        events:UnregisterEvent("ADDON_LOADED")
        NS:Initialize()
        -- A refusal recorded for an event this version no longer asks for is
        -- history, not a fact about the client: 1.5.37 asked for the combat
        -- log, 1.5.38 does not, and the refusal outlived it in every saved
        -- database. Drop what is no longer on the list before printing it.
        NS:ForgetRefusalsOutside(EVENT_NAMES)
        for _, name in ipairs(EVENT_NAMES) do
            -- A refusal does not raise: it shows the player a dialog whose
            -- first button disables this addon. Nothing can be done in advance
            -- to know, so the attempt is made once, the frame is asked whether
            -- it took, and a refusal is remembered rather than repeated at
            -- every login.
            if not NS:IsEventRefused(name) then
                events:RegisterEvent(name)
                if events.IsEventRegistered and not events:IsEventRegistered(name) then
                    NS:NoteRefusedEvent(name)
                end
            end
        end
        return
    end

    NS.pendingNoticeSuppressed = GAME_DRIVEN_EVENTS[event] or nil
    NS.currentEvent = event

    -- These fire for every addon, so the name is checked before recording.
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local culprit, func = ...
        if NS.NoteForbiddenAction then NS:NoteForbiddenAction(culprit, func) end
        NS.pendingNoticeSuppressed, NS.currentEvent = nil, nil
        return
    end

    if event == "ENCOUNTER_START" then
        NS.encounterActive = true
        NS.pendingNoticeSuppressed, NS.currentEvent = nil, nil
        return
    elseif event == "ENCOUNTER_END" then
        NS.encounterActive = false
        -- La rencontre est finie : c'est maintenant que le travail garde en
        -- reserve peut etre rejoue sans rien casser au milieu d'un combat.
        NS:OnCombatEnded()
        NS.pendingNoticeSuppressed, NS.currentEvent = nil, nil
        return
    end

    if event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
        local unit = ...
        -- Le jeton peut etre celui d'une unite hors grille : la lecture est
        -- faite quand meme, car c'est ainsi que le catalogue s'apprend.
        if type(unit) == "string" then
            NS:UnitControlTypes(unit)
            NS:RefreshUnit(unit)
        end
        NS.pendingNoticeSuppressed, NS.currentEvent = nil, nil
        return
    end

    if event == "UNIT_AURA" or event == "UNIT_FLAGS" or event == "UNIT_FACTION" or event == "UNIT_CONNECTION" then
        local unit = ...
        NS:RefreshUnit(unit)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FOCUS_CHANGED" then
        local profileChanged = false
        if event == "PLAYER_ENTERING_WORLD" then
            NS.spellbookResolved = true
            NS:RegisterCompatibilitySlashAliases()
            profileChanged = NS:QueueProfileSwitch()
        end
        if not profileChanged then NS:RebuildRoster() end
    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        NS:RefreshUnit(...)
        NS:RequestAuraSoundRefresh("vehicle changed")
    elseif event == "UNIT_PET" then
        local unit = ...
        NS:RebuildRoster()
        NS:RequestAuraSoundRefresh("unit pet changed")
        if unit == "player" then NS:UpdateSpells() end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if not unit or unit == "player" then NS:QueueProfileSwitch() end
    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        -- The client has spoken about the spellbook: an empty result is now a
        -- real answer, not a sign that it was not ready.
        NS.spellbookResolved = true
        NS:UpdateSpells()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        NS:RefreshDispelCooldowns()
    elseif event == "PLAYER_REGEN_DISABLED" then
        NS:EndTestModeForCombat()
        NS:UpdateCooldownOverlayVisibility(true)
        if NS.RefreshOptionsStatus then NS:RefreshOptionsStatus() end
        NS:RefreshAuraCandidateFilters()
        NS:RequestAuraSoundRefresh("combat started")
    elseif event == "PLAYER_REGEN_ENABLED" then
        NS:UpdateCooldownOverlayVisibility(false)
        NS:OnCombatEnded()
        if NS.RefreshOptionsStatus then NS:RefreshOptionsStatus() end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Replay the deferred work only once something is actually released.
        -- Activating and Active mean the door is closing or shut.
        local _, state = ...
        local inactive = Enum and Enum.AddOnRestrictionState
            and Enum.AddOnRestrictionState.Inactive
        if state == inactive and not (InCombatLockdown and InCombatLockdown()) then
            NS:OnCombatEnded()
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if NS.RefitWindows then NS:RefitWindows() end
    elseif event == "UI_ERROR_MESSAGE" then
        NS:OnUIError(...)
    elseif event == "PLAYER_LOGOUT" then
        NS:SnapshotDiagnostics()
    end

    NS.pendingNoticeSuppressed = nil
    NS.currentEvent = nil
end)

local function isDecursiveEnabled()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Decursive") then
        return true
    end
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        -- Retail 12.1 expects (addonName, characterGUID), matching
        -- AddOnUtil.IsAddOnEnabledForCurrentCharacter in Blizzard's UI.
        local characterGUID = NS:SafeUnitGUID("player")
        local ok, state
        if characterGUID then
            ok, state = pcall(C_AddOns.GetAddOnEnableState, "Decursive", characterGUID)
        else
            ok, state = pcall(C_AddOns.GetAddOnEnableState, "Decursive")
        end
        if ok and type(state) == "number" and state > 0 then
            return true
        end
    end
    return false
end

function NS:RegisterCompatibilitySlashAliases()
    if self.compatibilitySlashAliasesChecked then return end
    self.compatibilitySlashAliasesChecked = true
    if isDecursiveEnabled() then return end
    SLASH_CLEANSIVE3 = "/dcr"
    SLASH_CLEANSIVE4 = "/decursive"
    -- PLAYER_ENTERING_WORLD can run after ChatFrameUtil imported the original
    -- aliases into its hash. Reassigning the existing callback queues one
    -- more import, so the late compatibility aliases are not silently lost.
    if SlashCmdList and SlashCmdList.CLEANSIVE then
        SlashCmdList.CLEANSIVE = SlashCmdList.CLEANSIVE
    end
end

SLASH_CLEANSIVE1 = "/cleansive"
SLASH_CLEANSIVE2 = "/cls"
SlashCmdList.CLEANSIVE = function(message) NS:HandleSlash(message) end

function NS:RefreshBindingLabels()
    local labels = self.L or {}
    BINDING_HEADER_CLEANSIVE = "Cleansive"
    BINDING_NAME_CLEANSIVE_OPTIONS = labels.BINDING_OPTIONS or "Open Cleansive options"
    BINDING_NAME_CLEANSIVE_TOGGLE = labels.BINDING_TOGGLE or "Show or hide the Cleansive grid"
    BINDING_NAME_CLEANSIVE_PRIORITY = labels.BINDING_PRIORITY or "Open the Cleansive priority list"
    BINDING_NAME_CLEANSIVE_SKIP = labels.BINDING_SKIP or "Open the Cleansive skip list"
end

NS:RefreshBindingLabels()

function Cleansive_ToggleOptions() if NS.db then NS:ToggleOptions() end end
function Cleansive_Toggle()
    if not NS.db then return end
    NS:ToggleGridVisibility()
end
function Cleansive_ShowPriority() if NS.db then NS:ShowList("priority") end end
function Cleansive_ShowSkip() if NS.db then NS:ShowList("skip") end end

function Cleansive_AddonCompartmentClick(_, mouseButton)
    if not NS.db then return end
    if mouseButton == "RightButton" then
        NS:SetEnabled(not NS.db.enabled)
    else
        NS:ToggleOptions()
    end
end

function Cleansive_AddonCompartmentOnEnter(_, button)
    if not button or not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Cleansive")
    GameTooltip:AddLine(NS.L.COMPARTMENT_LEFT, 1, 1, 1)
    GameTooltip:AddLine(NS.L.COMPARTMENT_RIGHT, 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

function Cleansive_AddonCompartmentOnLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function NS:PrintProcessingOrder()
    local roster = self.roster or {}
    if #roster == 0 then
        self:Print(self.L.ORDER_EMPTY)
        return
    end
    self:Print(self.L.ORDER_TITLE)
    for index, descriptor in ipairs(roster) do
        local reason = self.L.ORDER_REASON_GROUP
        if descriptor.preview then
            reason = self.L.ORDER_REASON_PREVIEW
        elseif descriptor.isPlayer then
            reason = self.L.ORDER_REASON_SELF
        elseif self:PriorityRank(descriptor) < 1000 then
            reason = self.L.ORDER_REASON_PRIORITY
        end
        self:Print(string.format(self.L.ORDER_LINE, index,
            tostring(descriptor.displayName or descriptor.unit), reason))
    end
end

local WINDOW_ANCHORS = { CENTER = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true, TOP = true, BOTTOM = true,
    LEFT = true, RIGHT = true }

function NS:SaveWindowPosition(frame, key)
    local global = self.dbRoot and self.dbRoot.global
    if not global or not frame then return end
    global.windows = type(global.windows) == "table" and global.windows or {}
    local point, _, relativePoint, x, y = frame:GetPoint()
    if not WINDOW_ANCHORS[point] or not WINDOW_ANCHORS[relativePoint] then return end
    global.windows[key] = {
        point = point, relativePoint = relativePoint,
        x = math.floor(tonumber(x) or 0), y = math.floor(tonumber(y) or 0),
    }
end

function NS:RestoreWindowPosition(frame, key)
    local global = self.dbRoot and self.dbRoot.global
    local saved = global and type(global.windows) == "table" and global.windows[key]
    -- A saved anchor is read back from disk and SetPoint raises on a bad one.
    -- A window that cannot be placed must not stop the addon.
    if type(saved) ~= "table" or not WINDOW_ANCHORS[saved.point]
        or not WINDOW_ANCHORS[saved.relativePoint]
        or type(saved.x) ~= "number" or type(saved.y) ~= "number" then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    return true
end

-- #213/#214 : le pied de la fenetre disait toujours la meme chose. En combat
-- c'etait faux, et le joueur n'avait aucune explication au reglage qui ne
-- bougeait pas.
function NS:OptionsStatusText()
    if InCombatLockdown and InCombatLockdown() then
        local waiting = 0
        local announced = self.pendingAnnounced or {}
        for _, flag in ipairs(self.PENDING_FLAGS or {}) do
            if self[flag] and announced[flag] then waiting = waiting + 1 end
        end
        if waiting > 0 then
            return string.format(self.L.STATUS_COMBAT_WAITING, waiting)
        end
        return self.L.STATUS_COMBAT
    end
    if not self.enabled then return self.L.STATUS_PAUSED end
    return self.L.STATUS_READY
end

local SORT_MODES = { "GROUP", "ROLE", "CLASS" }

function NS:CycleSortMode()
    local current, index = self.db.sortMode or "GROUP", 1
    for position, mode in ipairs(SORT_MODES) do
        if mode == current then index = position end
    end
    self.db.sortMode = SORT_MODES[(index % #SORT_MODES) + 1]
    self:RebuildRoster()
    if self.RefreshOptions then self:RefreshOptions() end
end

function NS:Debounce(key, delay, action)
    self.debounced = self.debounced or {}
    local generation = (self.debounced[key] or 0) + 1
    self.debounced[key] = generation
    if not (C_Timer and C_Timer.After) then
        action()
        return
    end
    C_Timer.After(delay, function()
        -- Un appel plus recent a pris la main : celui-ci n'a plus rien a dire.
        if self.debounced[key] ~= generation then return end
        action()
    end)
end
