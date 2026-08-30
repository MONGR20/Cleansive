-- Minimal World of Warcraft API stand-in, sufficient to load Cleansive's
-- non-UI files and drive their logic. Anything a test does not assert on is
-- a permissive no-op rather than a faithful reimplementation.

local M = {}

-- Widget methods are CamelCase; the fields an addon stores on a frame are
-- lowercase. Answering every unknown key with a function made data fields
-- look like functions, which blew up the moment the addon indexed one, and
-- made existence checks such as `if button.auraContainer then` always true.
-- Stands in for a value the client refuses to expose. canaccessvalue reports
-- false for it, so a caller that guards properly never touches it.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- Declaree ici parce que newFrame en a besoin : les frames doivent pouvoir
-- consulter l'etat que les tests pilotent, et il est defini plus bas.
local state

local frameMeta
frameMeta = {
    __index = function(self, key)
        if type(key) ~= "string" or not key:match("^%u") then return nil end
        local fn = function(...) return nil end
        rawset(self, key, fn)
        return fn
    end,
}

-- Tous les cadres crees, pour qu'un test puisse parcourir les enfants d'une
-- page. Sans registre, il n'y a aucun moyen de savoir ce qu'une page contient.
local created = {}

local function newFrame(name)
    local f = setmetatable({ __frameName = name, __shown = true }, frameMeta)
    created[#created + 1] = f
    -- Show et Hide declenchaient l'etat sans declencher les scripts : un
    -- OnShow ou un OnHide pose par l'addon n'etait execute par aucun test, et
    -- tout ce qu'il fait passait donc pour verifie sans l'etre.
    local function setShown(s, value)
        value = value and true or false
        local was = rawget(s, "__shown")
        rawset(s, "__shown", value)
        if was == value then return end
        local handler = rawget(s, "__scripts_" .. (value and "OnShow" or "OnHide"))
        if handler then handler(s) end
    end
    rawset(f, "Show", function(s) setShown(s, true) end)
    rawset(f, "Hide", function(s) setShown(s, false) end)
    rawset(f, "IsShown", function(s) return rawget(s, "__shown") end)
    rawset(f, "SetShown", function(s, v) setShown(s, v) end)
    -- Sans ces deux-la, SetEnabled etait un no-op et IsEnabled rendait nil :
    -- un bouton grise et un bouton actif etaient indiscernables pour un test.
    rawset(f, "SetEnabled", function(s, v) rawset(s, "__enabled", v and true or false) end)
    rawset(f, "IsEnabled", function(s)
        local v = rawget(s, "__enabled")
        if v == nil then return true end
        return v
    end)
    rawset(f, "SetColorTexture", function(s, ...) rawset(s, "__color", { ... }) end)
    rawset(f, "SetTextColor", function(s, ...) rawset(s, "__textColor", { ... }) end)
    -- SetText ne declenchait rien. En jeu il declenche OnTextChanged, avec
    -- userInput a faux : une case dont l'invite ne s'efface qu'a cet evenement
    -- passait donc pour reglee sans l'etre. Septieme mensonge du bouchon.
    rawset(f, "SetText", function(s, v)
        rawset(s, "__text", v)
        local handler = rawget(s, "__scripts_OnTextChanged")
        if handler then handler(s, false) end
    end)
    rawset(f, "GetText", function(s) return rawget(s, "__text") end)
    -- Ce reglage tombait dans le stub generique : un bouton qui n'ecoute que
    -- le clic gauche et un bouton qui ecoute les cinq rendaient exactement la
    -- meme chose. La case qui capture une combinaison depend entierement de
    -- lui -- sans « AnyUp », deux tiers des combinaisons sont inatteignables.
    rawset(f, "RegisterForClicks", function(s, ...) rawset(s, "__clicks", { ... }) end)
    rawset(f, "SetAlpha", function(s, v) rawset(s, "__alpha", v) end)
    -- Un libelle qui rogne et un libelle qui passe a la ligne rendaient la
    -- meme chose : le bouchon avalait ce reglage sans le retenir. Huitieme
    -- mensonge -- et c'est celui qui separe un nom de profil borne d'un nom
    -- de profil qui deborde sur le bouton voisin.
    rawset(f, "SetWordWrap", function(s, v) rawset(s, "__wordWrap", v and true or false) end)
    -- SetScale tombait dans le stub generique : une fenetre remise a l'echelle
    -- et une fenetre oubliee rendaient exactement la meme chose.
    rawset(f, "SetScale", function(s, v) rawset(s, "__scale", tonumber(v) or 1) end)
    rawset(f, "GetScale", function(s) return rawget(s, "__scale") or 1 end)
    rawset(f, "SetMouseClickEnabled", function(s, v) rawset(s, "__mouseClicks", v and true or false) end)
    rawset(f, "SetMouseMotionEnabled", function(s, v) rawset(s, "__mouseMotion", v and true or false) end)
    rawset(f, "SetScript", function(s, k, v) rawset(s, "__scripts_" .. k, v) end)
    rawset(f, "GetScript", function(s, k) return rawget(s, "__scripts_" .. k) end)
    rawset(f, "SetAttribute", function(s, k, v) rawset(s, "__attr_" .. tostring(k), v) end)
    rawset(f, "GetAttribute", function(s, k) return rawget(s, "__attr_" .. tostring(k)) end)
    -- L'orientation d'un chevron ne se voit que par son angle : sans cela un
    -- dessin inverse passait tous les tests.
    rawset(f, "SetRotation", function(s, angle) rawset(s, "__rotation", angle) end)
    -- RegisterEvent tombait dans le stub generique et IsEventRegistered rendait
    -- nil : un code qui verifie que son inscription a bien pris aurait conclu
    -- que TOUS les evenements etaient refuses. state.refusedEvents reproduit un
    -- refus du client, qui ne leve pas mais n'inscrit rien.
    rawset(f, "RegisterEvent", function(s, name)
        if state.refusedEvents[name] then return end
        local events = rawget(s, "__events")
        if not events then events = {} rawset(s, "__events", events) end
        events[name] = true
    end)
    rawset(f, "UnregisterEvent", function(s, name)
        local events = rawget(s, "__events")
        if events then events[name] = nil end
    end)
    rawset(f, "IsEventRegistered", function(s, name)
        local events = rawget(s, "__events")
        return events and events[name] or false
    end)
    rawset(f, "SetSize", function(s, width, height)
        rawset(s, "__lastSize", { width = width, height = height })
    end)
    -- SetHeight et SetWidth tombaient dans le stub generique : un trait dessine
    -- a la mauvaise epaisseur, ou pas dessine du tout, etait indetectable.
    rawset(f, "SetHeight", function(s, v) rawset(s, "__height", v) end)
    rawset(f, "SetWidth", function(s, v) rawset(s, "__width", v) end)
    -- SetFrameLevel tombait dans le stub generique et GetFrameLevel rendait
    -- toujours 1 : impossible de verifier qu'une couche se place par rapport a
    -- une autre. Tout l'empilement de l'addon etait donc invisible aux tests.
    rawset(f, "SetFrameLevel", function(s, value) rawset(s, "__level", tonumber(value) or 0) end)
    rawset(f, "GetFrameLevel", function(s) return rawget(s, "__level") or 1 end)
    -- Coordonnees ecran : nil tant que le test n a pas pose de rectangle,
    -- ce qui reproduit un cadre non encore place.
    rawset(f, "GetLeft", function(s) local r = rawget(s, "__rect") return r and r.left end)
    rawset(f, "GetRight", function(s) local r = rawget(s, "__rect") return r and r.right end)
    rawset(f, "GetTop", function(s) local r = rawget(s, "__rect") return r and r.top end)
    rawset(f, "GetBottom", function(s) local r = rawget(s, "__rect") return r and r.bottom end)
    -- Rendre l ancrage reellement pose : sans cela un code qui lit GetPoint pour
    -- le decaler travaillait toujours sur (0, 0).
    rawset(f, "GetPoint", function(s)
        local p = rawget(s, "__lastPoint")
        if p then return p.point, p.relative, p.relativePoint, p.x, p.y end
        return "CENTER", nil, "CENTER", 0, 0
    end)
    -- Garder le dernier ancrage pose : c est la seule facon de verifier une
    -- mise en page calculee sans moteur de rendu.
    -- SetPoint accepte deux formes : (point, x, y) et
    -- (point, cadre, pointDuCadre, x, y). Le stub ne comprenait que la longue,
    -- donc pour la courte il rangeait x dans le champ « cadre de reference » et
    -- laissait les coordonnees vides. Toute la mise en page de l'addon utilise
    -- la forme courte : sa geometrie etait donc invisible aux tests, et c'est
    -- ainsi que la 1.6 est partie avec des libelles empiles.
    rawset(f, "SetPoint", function(s, point, a, b, c, d)
        local relative, relativePoint, x, y
        if type(a) == "number" or a == nil then
            relative, relativePoint, x, y = nil, point, a, b
        else
            relative, relativePoint, x, y = a, b, c, d
        end
        local placed = { point = point, relative = relative,
            relativePoint = relativePoint, x = x, y = y }
        rawset(s, "__lastPoint", placed)
        -- Un cadre epingle par deux coins n'a qu'une seule des deux poses dans
        -- __lastPoint : sa largeur reelle vient de la paire. Les garder toutes
        -- est la seule facon de reconstituer un rectangle.
        local points = rawget(s, "__points")
        if not points then points = {} rawset(s, "__points", points) end
        points[#points + 1] = placed
    end)
    rawset(f, "ClearAllPoints", function(s)
        rawset(s, "__points", {})
        rawset(s, "__lastPoint", nil)
    end)
    -- Un objet interdit n'est pas une fonction protegee : toute methode
    -- appelee dessus leve une erreur Lua ordinaire, sans ADDON_ACTION_*.
    rawset(f, "IsForbidden", function(s) return rawget(s, "__forbidden") == true end)
    rawset(f, "GetName", function(s) return rawget(s, "__frameName") end)
    rawset(f, "CreateTexture", function(owner)
        local texture = newFrame("texture")
        texture.__parent = owner
        texture.__type = "Texture"
        return texture
    end)
    rawset(f, "CreateFontString", function(owner)
        local fs = newFrame("fontstring")
        -- Le parent d'un texte n'etait pas retenu : impossible de savoir a
        -- quelle page il appartient, donc impossible de voir deux libelles se
        -- recouvrir. C'est exactement ce qui est arrive en 1.6.
        fs.__parent = owner
        fs.__type = "FontString"
        -- Garder la derniere police posee : les tailles sont calculees,
        -- donc verifiables sans moteur de rendu.
        rawset(fs, "SetFont", function(s, path, height, flags)
            rawset(s, "__font", { path = path, height = height, flags = flags })
        end)
        -- Pas de moteur de rendu ici : une largeur proportionnelle au texte et
        -- a la taille de police suffit a verifier qu'une plaque est dimensionnee
        -- sur son libelle plutot que sur une constante.
        rawset(fs, "GetStringWidth", function(s)
            local text = rawget(s, "__text") or ""
            local font = rawget(s, "__font")
            return #text * ((font and font.height or 10) * 0.55)
        end)
        return fs
    end)
    -- Une zone de defilement tombait dans le stub generique : GetVerticalScroll
    -- et GetVerticalScrollRange rendaient nil, donc tout code qui decide
    -- quelque chose a partir de la position de la barre etait invisible aux
    -- tests. __scrollRange est pose par le test : le client, lui, le calcule.
    rawset(f, "SetVerticalScroll", function(s, value)
        rawset(s, "__scroll", tonumber(value) or 0)
        local handler = rawget(s, "__scripts_OnVerticalScroll")
        if handler then handler(s, rawget(s, "__scroll")) end
    end)
    rawset(f, "GetVerticalScroll", function(s) return rawget(s, "__scroll") or 0 end)
    rawset(f, "GetVerticalScrollRange", function(s) return rawget(s, "__scrollRange") or 0 end)
    rawset(f, "GetThumbTexture", function() return newFrame("thumb") end)
    return f
end
M.newFrame = newFrame
M.SECRET = SECRET

-- Mutable state the tests drive.
state = {
    inCombat = false,
    secretMode = false,
    identityRestricted = false,     -- UnitGUID, UnitClass, UnitFullName illisibles
    nameRestricted = false,         -- UnitName illisible (drapeau distinct chez Blizzard)
    comparisonRestricted = false,   -- UnitIsUnit rend une valeur illisible
    playerClass = "PALADIN",
    specIndex = 1,
    specID = 65,
    specName = "Holy",
    knownSpells = {},        -- [spellID] = true
    chargeSpells = {},       -- [spellID] = true : le sort est a charges
    -- [spellID] = { charge = bool, cooldown = bool } : les drapeaux isActive,
    -- documentes NeverSecret. Absent = le client ne les expose pas.
    spellActivity = {},
    playerSpells = {},       -- [spellID] = true (IsPlayerSpell)
    debuffs = {},            -- [unit] = { auraTable, ... }
    friendly = {},           -- [unit] = boolean, for UnitIsFriend
    inVehicle = {},          -- [unit] = boolean, for UnitHasVehicleUI
    attackable = {},         -- [unit] = boolean, for UnitCanAttack
    exists = { player = true },
    -- IsInRaid et GetRaidRosterInfo etaient cables en dur sur "non" et nil :
    -- aucun test ne pouvait mettre le joueur dans un groupe de raid, donc
    -- l'ordre des cases en raid n'etait verifie nulle part.
    inRaid = false,
    combatLogEvent = nil,   -- la ligne que C_CombatLog.GetCurrentEventInfo rendra
    refusedEvents = {},     -- inscriptions que le client refuse en silence
    identityFilterViolations = {},  -- emplacements filtres par identifiant seul
    inGroup = false,
    raidGroups = {},         -- [index] = numero de sous-groupe
    sameUnit = {},           -- [jeton] = jeton, pour UnitIsUnit
    time = 1000,
    locale = "frFR",
    tocVersion = TOC_VERSION,   -- injectee par run.js depuis le .toc
    chat = {},
    tooltip = {},
    screen = { width = 1920, height = 1080 },
    -- Protected aura engine. `loaded` decides whether Blizzard_AuraContainer
    -- answers; `failSlotsFrom` makes AddAuraSlot raise from the Nth container
    -- on, which is how a partial failure is reproduced.
    auraEngine = { loaded = false, created = 0, failSlotsFrom = nil, failFiltersFor = nil },
    roles = {},
    lossOfControl = {},
    lossOfControlRestricted = false,
    tocRevision = "@project-abbreviated-hash@",
    instanceType = "none",
    modifiers = {},
    timers = {},
}
M.state = state

function M.install(_G)
    _G.unpack = _G.unpack or table.unpack

    _G.UIParent = newFrame("UIParent")
    rawset(_G.UIParent, "GetWidth", function() return state.screen.width end)
    rawset(_G.UIParent, "GetHeight", function() return state.screen.height end)
    rawset(_G.UIParent, "GetLeft", function() return 0 end)
    rawset(_G.UIParent, "GetBottom", function() return 0 end)
    rawset(_G.UIParent, "GetRight", function() return state.screen.width end)
    rawset(_G.UIParent, "GetTop", function() return state.screen.height end)
    _G.CreateFrame = function(frameType, name, parent, template)
        local frame = newFrame(name)
        frame.__type = frameType
        frame.__parent = parent
        frame.__template = template
        -- Un modele Blizzard arrive AVEC ses scripts deja poses. Le bouchon les
        -- ignorait : un SetScript de l'addon sur le meme evenement passait donc
        -- pour anodin, alors qu'il ECRASE le gestionnaire du modele. C'est
        -- exactement ce qui est arrive en 1.6.7 -- la barre de defilement de
        -- UIPanelScrollFrameTemplate n'etait plus jamais configuree, et plus
        -- rien ne defilait en jeu. Aucun test ne pouvait le voir.
        -- Ces marqueurs ne font rien d'utile : ils existent pour qu'un test
        -- puisse verifier qu'ils sont encore appeles.
        if type(template) == "string" and template:find("ScrollFrame", 1, true) then
            rawset(frame, "__templateRan", {})
            for _, script in ipairs({ "OnVerticalScroll", "OnScrollRangeChanged" }) do
                rawset(frame, "__scripts_" .. script, function(target)
                    local ran = rawget(target, "__templateRan")
                    if ran then ran[script] = (ran[script] or 0) + 1 end
                end)
            end
            -- La molette du modele DEPLACE : scrollStep, ou a defaut la moitie
            -- de la hauteur visible. Un marqueur qui ne bougeait pas laissait
            -- croire qu'appeler le modele puis ajouter 40 px etait sans
            -- consequence -- alors qu'un cran faisait environ 300 px en jeu.
            -- __templateScrollStep vaut 0 par defaut : le modele ne bouge pas,
            -- ce qui est le cas ou le repli de l'addon doit prendre le relais.
            rawset(frame, "__scripts_OnMouseWheel", function(target, delta)
                local ran = rawget(target, "__templateRan")
                if ran then ran.OnMouseWheel = (ran.OnMouseWheel or 0) + 1 end
                local step = rawget(target, "__templateScrollStep") or 0
                if step == 0 then return end
                local range = rawget(target, "__scrollRange") or 0
                local wanted = (rawget(target, "__scroll") or 0) - ((delta or 0) * step)
                rawset(target, "__scroll", math.max(0, math.min(range, wanted)))
            end)
        end
        if frameType == "AuraContainer" then
            state.auraEngine.created = state.auraEngine.created + 1
            local ordinal = state.auraEngine.created
            rawset(frame, "__ordinal", ordinal)
            rawset(frame, "__slots", {})
            rawset(frame, "AddAuraSlot", function(container, key, _, options)
                local failFrom = state.auraEngine.failSlotsFrom
                if failFrom and ordinal >= failFrom then error("AddAuraSlot failed") end
                rawget(container, "__slots")[key] = options
                -- Regle reelle de Blizzard, absente jusqu'ici du mock :
                -- CanApplyIdentityCandidateFilters refuse includeSpellIDs et
                -- excludeSpellIDs sur une aura NEFASTE portee par une unite que
                -- le joueur peut assister, sauf si le sort est NeverSecret. Un
                -- filtre par identifiant pose la-dessus est donc ignore, et
                -- l'emplacement affiche TOUT ce que son filtre general laisse
                -- passer. Sans cette regle, un emplacement dangereux qui
                -- s'allumait sur chaque affliction passait tous les tests.
                local filters = type(options) == "table" and options.candidateFilters
                -- Consigner, pas lever : le code enveloppe AddAuraSlot dans un
                -- pcall, donc une erreur ici serait avalee et le defaut
                -- resterait invisible. La suite verifie la liste a la fin.
                if type(filters) == "table" and (filters.includeSpellIDs or filters.excludeSpellIDs)
                    and not filters.includeDispelTypes then
                    local v = state.identityFilterViolations
                    v[#v + 1] = tostring(key)
                end
                -- Le vrai moteur appelle initializeFrame pour construire les
                -- visuels de l emplacement. Sans cet appel, tout le dessin du
                -- moteur protege -- anneaux, lettres, minuteries -- n etait
                -- execute par aucun test.
                if type(options) == "table" and type(options.initializeFrame) == "function" then
                    local auraButton = newFrame("AuraSlot:" .. tostring(key))
                    rawset(container, "__auraButtons", rawget(container, "__auraButtons") or {})
                    rawget(container, "__auraButtons")[key] = auraButton
                    options.initializeFrame(auraButton)
                end
                return {}
            end)
            rawset(frame, "SetUnit", function(container, unit) rawset(container, "__unit", unit) end)
            -- Enregistrer les filtres poses : sans cela le stub generique les
            -- avalait et les tests ne voyaient ni la neutralisation d un type
            -- retire ni sa reactivation par un rafraichissement general.
            rawset(frame, "SetAuraSlotCandidateFilters", function(container, key, filters)
                -- Une seule cle ne suffisait pas : une panne simultanee sur un
                -- type retire et un type actif est justement le cas ou le
                -- diagnostic pouvait nommer le mauvais type.
                local fail = state.auraEngine.failFiltersFor
                if fail == key or (type(fail) == "table" and fail[key]) then
                    error("SetAuraSlotCandidateFilters failed")
                end
                local slots = rawget(container, "__slots")
                slots[key] = slots[key] or {}
                slots[key].candidateFilters = filters
            end)
        end
        return frame
    end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.STANDARD_TEXT_FONT = "font.ttf"
    _G.MAX_RAID_MEMBERS, _G.MAX_PARTY_MEMBERS = 40, 4

    _G.InCombatLockdown = function() return state.inCombat end
    _G.GetTime = function() return state.time end
    _G.debugprofilestop = function() return state.time * 1000 end
    _G.GetLocale = function() return state.locale end
    _G.GetRealmName = function() return "Hyjal" end
    _G.GetNormalizedRealmName = function() return "Hyjal" end
    _G.Ambiguate = function(name) return (string.gsub(name, "%-.*", "")) end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.tinsert = table.insert
    -- Protected combat hands back values Lua may not read. Flip
    -- state.secretMode to reproduce that: any negation or arithmetic on
    -- such a value raises in the real client.
    _G.canaccessvalue = function(value)
        if value == SECRET then return false end
        return not state.secretMode
    end
    _G.ReloadUI = function() end

    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) state.chat[#state.chat + 1] = msg end }
    -- La table repondait « blanc » a TOUTE cle, y compris a une classe qui
    -- n'existe pas : impossible de distinguer une classe connue d'une classe
    -- illisible, et tout code qui interroge la palette pour savoir si elle
    -- connait un jeton passait pour verifie sans l'etre. Une vraie palette,
    -- partielle mais sans reponse universelle : une cle inconnue rend nil,
    -- comme chez Blizzard. Un pretre est reellement blanc -- c'est ce qui
    -- interdit de deduire « illisible » d'une couleur blanche.
    _G.RAID_CLASS_COLORS = {
        PALADIN = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
        PRIEST  = { r = 1.00, g = 1.00, b = 1.00, colorStr = "ffffffff" },
        DRUID   = { r = 1.00, g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
        MAGE    = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff40c7eb" },
        MONK    = { r = 0.00, g = 1.00, b = 0.59, colorStr = "ff00ff96" },
        SHAMAN  = { r = 0.00, g = 0.44, b = 0.87, colorStr = "ff0070dd" },
    }

    _G.UnitClass = function()
        if state.identityRestricted then return SECRET, SECRET end
        return state.playerClass, state.playerClass
    end
    _G.UnitName = function(unit)
        -- En jeu, UnitName et UnitFullName rendent le meme nom court pour le
        -- joueur. Le stub rendait le jeton, ce qui masquait toute confusion
        -- entre les deux dans le calcul de la clef de profil.
        if state.nameRestricted then return SECRET end
        if unit == "player" then return "Ekinoks", "Hyjal" end
        return unit, "Hyjal"
    end
    _G.UnitFullName = function()
        if state.identityRestricted then return SECRET, SECRET end
        return "Ekinoks", "Hyjal"
    end
    _G.GetUnitName = function(unit)
        if state.nameRestricted or state.identityRestricted then return SECRET end
        return unit .. "-Hyjal"
    end
    _G.UnitGUID = function(unit)
        if state.identityRestricted then return SECRET end
        if not unit then return nil end
        -- Un meme personnage vu par deux jetons (player et raid3) porte un
        -- seul GUID. Sans cela le joueur entrait deux fois dans le roster et
        -- la deduplication n'etait jamais exercee.
        return "GUID-" .. (state.sameUnit[unit] or unit)
    end
    _G.UnitExists = function(unit) return state.exists[unit] and true or false end
    _G.UnitIsUnit = function(a, b)
        if state.comparisonRestricted then return SECRET end
        if a == b then return true end
        return state.sameUnit[a] == b or state.sameUnit[b] == a
    end
    _G.UnitIsPlayer = function() return true end
    _G.UnitIsFriend = function(_, unit) return state.friendly[unit] ~= false end
    _G.UnitCanAttack = function(_, unit) return state.attackable[unit] and true or false end
    _G.UnitIsConnected = function() return true end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitInRange = function() return true, true end
    _G.UnitHasVehicleUI = function(unit) return state.inVehicle[unit] and true or false end
    _G.RegisterAttributeDriver, _G.UnregisterAttributeDriver = function() end, function() end
    _G.C_CombatLog = {
        GetCurrentEventInfo = function()
            local e = state.combatLogEvent
            if not e then return end
            return unpack(e)
        end,
    }
    _G.UnitGroupRolesAssigned = function(unit) return state.roles[unit] or "NONE" end
    -- C_LossOfControl : les donnees peuvent etre secretes sous restriction, ce
    -- que state.lossOfControlRestricted reproduit.
    _G.C_LossOfControl = {
        GetActiveLossOfControlDataCountByUnit = function(unit)
            if state.lossOfControlRestricted then return SECRET end
            return #(state.lossOfControl[unit] or {})
        end,
        GetActiveLossOfControlDataByUnit = function(unit, index)
            if state.lossOfControlRestricted then return SECRET end
            return (state.lossOfControl[unit] or {})[index]
        end,
        GetActiveLossOfControlData = function() return nil end,
        GetActiveLossOfControlDataCount = function() return 0 end,
    }
    _G.IsInRaid = function() return state.inRaid and true or false end
    _G.IsInGroup = function() return (state.inRaid or state.inGroup) and true or false end
    _G.GetRaidRosterInfo = function(index)
        local group = state.raidGroups[index]
        if not group then return nil end
        return "Raider" .. tostring(index), nil, group
    end

    _G.IsPlayerSpell = function(id) return state.playerSpells[id] and true or false end
    _G.IsSpellKnown = function(id) return state.knownSpells[id] and true or false end
    _G.Enum = {
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        UnitAuraSoundTrigger = { Added = 0 },
        UIErrorMessage = {},
        -- Les six types de 12.1. InCombatLockdown ne repond que pour le
        -- premier : une cle mythique garde ChallengeMode actif entre les packs,
        -- la ou l'addon se croit libre.
        AddOnRestrictionType = {
            Combat = 0, Encounter = 1, ChallengeMode = 2,
            PvPMatch = 3, Map = 4, Chat = 5,
        },
        AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
    }
    _G.C_RestrictedActions = {
        IsAddOnRestrictionActive = function(value)
            return state.restrictions[value] and true or false
        end,
        -- IsForbidden dit si l'objet a ete DECLARE interdit ; ceci dit si le
        -- contexte d'appel a le droit d'y toucher. Les 480 refus du 29/08
        -- avaient IsForbidden faux et cette permission refusee.
        CheckAllowProtectedFunctions = function(object, _)
            if rawget(object, "__protectedDenied") then return false end
            return state.protectedAllowed ~= false
        end,
    }
    _G.C_SpellBook = { IsSpellInSpellBook = function(id) return state.knownSpells[id] and true or false end }
    _G.C_Spell = {
        GetSpellName = function(id) return "Spell" .. tostring(id) end,
        GetBaseSpell = function(id) return id end,
        GetSpellCooldown = function(id)
            local activity = state.spellActivity[id]
            return { startTime = 0, duration = 0, isEnabled = true, modRate = 1,
                isActive = activity and activity.cooldown }
        end,
        -- The doc says nil for a spell that is not charge-based, but the live
        -- client hands back a table for those too, with maxCharges = 1. The
        -- mock used to return nil, which is why a test could pass while the
        -- game failed. maxCharges is documented NeverSecret.
        GetSpellCharges = function(id)
            local activity = state.spellActivity[id]
            return { currentCharges = 1, isActive = activity and activity.charge,
                maxCharges = state.chargeSpells[id] and 2 or 1 }
        end,
        IsSpellInRange = function() return true end,
    }
    _G.C_SpecializationInfo = {
        GetSpecialization = function() return state.specIndex end,
        GetSpecializationInfo = function() return state.specID, state.specName end,
    }
    _G.C_UnitAuras = {
        GetDebuffDataByIndex = function(unit, index) return (state.debuffs[unit] or {})[index] end,
        GetAuraApplicationDisplayCount = function() return 1 end,
        AddAuraSound = function() return math.random(1, 1e6) end,
        RemoveAuraSound = function() return true end,
    }
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, key)
            if key == "Version" then return state.tocVersion end
            -- Le champ existe dans le .toc et vaut le jeton de l'empaqueteur
            -- tant qu'aucune archive n'a ete fabriquee. Rendre nil ici cachait
            -- ce cas au lieu de le reproduire.
            if key == "X-Revision" then return state.tocRevision end
            return nil
        end,
        IsAddOnLoaded = function(name)
            if name == "Blizzard_AuraContainer" then return state.auraEngine.loaded end
            return false
        end,
        LoadAddOn = function(name)
            if name == "Blizzard_AuraContainer" then return state.auraEngine.loaded end
            return false
        end,
        GetAddOnEnableState = function() return 0 end,
    }
    -- Timers run immediately: the tests assert on outcomes, not on scheduling.
    _G.C_Timer = { After = function(_, fn) state.timers[#state.timers + 1] = fn end }

    _G.PlaySoundFile, _G.PlaySound = function() end, function() end
    _G.SOUNDKIT = { IG_QUEST_FAILED = 847, RAID_WARNING = 8959 }
    _G.GameTooltip = newFrame("GameTooltip")
    -- Record what is written so a test can read the tooltip back.
    rawset(_G.GameTooltip, "SetOwner", function() state.tooltip = {} end)
    rawset(_G.GameTooltip, "AddLine", function(_, text)
        state.tooltip = state.tooltip or {}
        state.tooltip[#state.tooltip + 1] = tostring(text)
    end)
    _G.GameTooltip_Hide = function() end
    _G.CooldownFrame_Set = function() end
    _G.RegisterStateDriver, _G.UnregisterStateDriver = function() end, function() end
    _G.SetOverrideBindingClick, _G.ClearOverrideBindings = function() end, function() end
    _G.GetMacroIndexByName, _G.CreateMacro, _G.EditMacro = function() return 0 end, function() return 1 end, function() end
    _G.StaticPopupDialogs, _G.StaticPopup_Show = {}, function() end
    _G.Settings, _G.SettingsPanel, _G.HideUIPanel = nil, nil, function() end
    -- Cable en dur sur « nulle part » : tout code qui decide selon le lieu
    -- passait pour verifie sans l'etre.
    _G.IsInInstance = function()
        local kind = state.instanceType or "none"
        return kind ~= "none", kind
    end
    _G.GetInstanceInfo = function() return "Royaumes de l'Est", "none", 0, "", 0, 0, false, 0 end
    -- Cables en dur sur « relache » : tout code qui lit un modificateur passait
    -- pour verifie sans l'etre, et c'est exactement ce qui a laisse le registre
    -- des clics attribuer le mauvais sort apres un remappage.
    _G.IsControlKeyDown = function() return state.modifiers.CTRL and true or false end
    _G.IsShiftKeyDown = function() return state.modifiers.SHIFT and true or false end
    _G.IsAltKeyDown = function() return state.modifiers.ALT and true or false end
end

function M.childrenOf(parent)
    local list = {}
    for _, frame in ipairs(created) do
        if rawget(frame, "__parent") == parent then list[#list + 1] = frame end
    end
    return list
end

-- childrenOf reparcourt TOUS les cadres crees. Un appel isole ne coute rien ;
-- un parcours recursif d'une fenetre entiere en fait un cout quadratique, et le
-- test a fini par depasser deux minutes. L'index se construit en une passe.
function M.childIndex()
    local index = {}
    for _, frame in ipairs(created) do
        local parent = rawget(frame, "__parent")
        if parent ~= nil then
            local list = index[parent]
            if not list then list = {} index[parent] = list end
            list[#list + 1] = frame
        end
    end
    return index
end

function M.reset()
    state.inCombat = false
    state.secretMode = false
    state.identityRestricted, state.comparisonRestricted = false, false
    state.nameRestricted = false
    state.playerClass = "PALADIN"
    state.specIndex, state.specID, state.specName = 1, 65, "Holy"
    state.knownSpells, state.playerSpells, state.chargeSpells = {}, {}, {}
    state.spellActivity = {}
    state.debuffs, state.friendly, state.attackable = {}, {}, {}
    state.inVehicle = {}
    state.exists = { player = true }
    state.inRaid, state.inGroup = false, false
    state.combatLogEvent = nil
    state.refusedEvents = {}
    state.restrictions = {}
    state.protectedAllowed = true
    state.identityFilterViolations = {}
    state.raidGroups, state.sameUnit = {}, {}
    state.time = 1000
    state.chat, state.timers, state.tooltip = {}, {}, {}
    state.screen = { width = 1920, height = 1080 }
    state.auraEngine = { loaded = false, created = 0, failSlotsFrom = nil, failFiltersFor = nil }
    state.roles = {}
    state.lossOfControl = {}
    state.lossOfControlRestricted = false
    state.tocRevision = "@project-abbreviated-hash@"
end

function M.runTimers()
    local pending = state.timers
    state.timers = {}
    for _, fn in ipairs(pending) do fn() end
end

function M.timerCount()
    return #state.timers
end

-- Draining the queue in one batch hid the interleaving that matters: a stale
-- callback firing after a newer one was already armed.
function M.runTimerAt(index)
    local fn = table.remove(state.timers, index or 1)
    if fn then fn() end
    return fn ~= nil
end

return M
