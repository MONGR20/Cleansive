local _, NS = ...

NS.DISPEL_TYPES = { "Magic", "Curse", "Poison", "Disease", "Bleed", "Charm" }

-- Single source for the translated type names. They used to live in two
-- tables private to EllesmereUX.lua, out of reach of every other file and
-- out of Locale.lua where the rest of the translations are kept.
-- Types the character can only clear with an area or self-only ability.
-- Painting those on every unit repeats one bit of information N times: the
-- player cannot act on a single ally, so a per-unit cell has nothing to say.
function NS:GetManualOnlyTypes()
    local result = {}
    -- Follow the player's configured order, not the fixed declaration order.
    for _, auraType in ipairs((self.db and self.db.typeOrder) or self.DISPEL_TYPES or {}) do
        if not (self.typeToSlot and self.typeToSlot[auraType])
            and self.manualTypeSpell and self.manualTypeSpell[auraType]
            and self.db and self.db.enabledTypes[auraType] ~= false then
            result[#result + 1] = auraType
        end
    end
    return result
end

function NS:IsTypeGrouped(auraType)
    if not self.db or not self.db.groupManualTypes then return false end
    return not (self.typeToSlot and self.typeToSlot[auraType])
        and self.manualTypeSpell and self.manualTypeSpell[auraType] and true or false
end

function NS:GetTypeLabel(dispelType)
    if type(dispelType) ~= "string" then return tostring(dispelType) end
    return self.L["TYPE_" .. string.upper(dispelType)] or dispelType
end

NS.TYPE_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.62, 0.28, 0.90 },
    Poison  = { 0.12, 0.86, 0.24 },
    Disease = { 0.76, 0.56, 0.16 },
    Bleed   = { 0.85, 0.10, 0.10 },
    Charm   = { 0.20, 0.95, 0.72 },
}

-- This table is deliberately data-driven. Cleansive only activates spells
-- that are actually present in the current player or pet spell book.
NS.SPELL_DEFINITIONS = {
    { id = 475,    class = "MAGE",        types = { "Curse" },                         quality = 3 },
    { id = 30449,  class = "MAGE",        types = { "Charm" }, hostile = true,         quality = 1 },
    { id = 118,    class = "MAGE",        types = { "Charm" }, hostile = true,         quality = 4 },

    { id = 2782,   class = "DRUID",       types = { "Poison", "Curse" },             quality = 2 },
    { id = 88423,  class = "DRUID",       types = { "Magic", "Poison", "Curse" },  quality = 4 },
    { id = 33786,  class = "DRUID",       types = { "Charm" }, hostile = true,         quality = 4 },

    { id = 4987,   class = "PALADIN",     types = { "Magic", "Disease", "Poison" },quality = 4 },
    { id = 213644, class = "PALADIN",     types = { "Disease", "Poison" },           quality = 2 },

    { id = 527,    class = "PRIEST",      types = { "Magic" }, enhancedTypes = { "Magic", "Disease" }, enhancedBySpell = 390632, quality = 4 },
    { id = 213634, class = "PRIEST",      types = { "Disease" },                      quality = 2 },
    { id = 528,    class = "PRIEST",      types = { "Charm" }, hostile = true,         quality = 1 },
    { id = 8122,   class = "PRIEST",      types = { "Charm" }, hostile = true, untargeted = true, quality = 4 },

    { id = 51886,  class = "SHAMAN",      types = { "Curse" }, enhancedTypes = { "Curse", "Magic" }, enhancedSpec = 3, quality = 3 },
    { id = 77130,  class = "SHAMAN",      types = { "Magic" }, enhancedTypes = { "Magic", "Curse" }, enhancedBySpell = 383016, quality = 4 },
    { id = 370,    class = "SHAMAN",      types = { "Charm" }, hostile = true,         quality = 1 },
    { id = 51514,  class = "SHAMAN",      types = { "Charm" }, hostile = true,         quality = 4 },
    { id = 383013, class = "SHAMAN",      types = { "Poison" },                       quality = 1, untargeted = true },

    { id = 115450, class = "MONK",        types = { "Magic" }, enhancedTypes = { "Magic", "Disease", "Poison" }, enhancedBySpell = 388874, quality = 4 },
    { id = 218164, class = "MONK",        types = { "Disease", "Poison" },           quality = 2 },
    { id = 122783, class = "MONK",        types = { "Magic" },                        quality = 1, selfOnly = true },

    { id = 365585, class = "EVOKER",      types = { "Poison" },                       quality = 2 },
    { id = 360823, class = "EVOKER",      types = { "Magic", "Poison" },             quality = 4 },
    { id = 374251, class = "EVOKER",      types = { "Poison", "Curse", "Disease", "Bleed" }, quality = 3 },

    { id = 212640, class = "HUNTER",      types = { "Disease", "Poison" },           quality = 2 },

    { id = 89808,  class = "WARLOCK",     types = { "Magic" }, pet = true,            quality = 3 },
    { id = 212623, class = "WARLOCK",     types = { "Magic" }, pet = true,            quality = 3 },
    { id = 115276, class = "WARLOCK",     types = { "Magic" }, pet = true,            quality = 3 },
    { id = 19505,  class = "WARLOCK",     types = { "Charm" }, pet = true, hostile = true, quality = 1 },
    { id = 171021, class = "WARLOCK",     types = { "Charm" }, pet = true, hostile = true, quality = 1 },
    { id = 5782,   class = "WARLOCK",     types = { "Charm" }, hostile = true,         quality = 4 },

    { id = 205604, class = "DEMONHUNTER", types = { "Magic" }, untargeted = true,     quality = 2 },
    { id = 278326, class = "DEMONHUNTER", types = { "Charm" }, hostile = true,         quality = 1 },
    { id = 217832, class = "DEMONHUNTER", types = { "Charm" }, hostile = true,         quality = 4 },

    -- Will of the Forsaken (7744) was listed here until 1.5.13 and could never
    -- light anything. Cleansive's "Charm" is not a dispel type -- Blizzard's
    -- AuraUtil.DispellableDebuffTypes stops at Magic, Curse, Disease, Poison
    -- and Bleed -- it is the state "this ally is mind-controlled", detected
    -- because you can suddenly attack them, and answered by a crowd-control
    -- spell cast on them. A self-only racial fits none of that: it gets no
    -- click slot, so the detection never runs, and UnitCanAttack is false on
    -- yourself, so your own case never fires either. Listing it only promised
    -- an undead player something the addon cannot deliver.
}

local function getSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
end

local function getSecureSpellName(spellID, fallback)
    local castID = spellID
    if C_Spell and C_Spell.GetBaseSpell then
        local baseID = C_Spell.GetBaseSpell(spellID)
        if type(baseID) == "number" and baseID > 0 then castID = baseID end
    end
    return getSpellName(castID) or fallback
end

-- The documentation promises nil for a spell that is not charge-based, but the
-- live client returns a table for those too, with maxCharges = 1. Testing for
-- nil therefore called every spell charge-based, and 1.5.11 shipped with the
-- defect it meant to fix. maxCharges is documented NeverSecret, so it stays
-- readable where the rest of the cooldown state is protected -- including
-- inside an instance, which is exactly where this matters. Blizzard's own code
-- uses the same test: charge-based means it can bank more than one.
local function spellHasCharges(spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or info == nil then return false end
    local readable, maxCharges = pcall(function() return info.maxCharges end)
    if not readable or type(maxCharges) ~= "number" then return nil end
    return maxCharges > 1
end

local function knownInBank(spellID, bank)
    if not C_SpellBook or not bank then
        return false
    end
    if C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and known then return true end
    end
    if C_SpellBook.IsSpellInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID, bank, true)
        if ok and known then return true end
    end
    return false
end

function NS:IsSpellKnown(def)
    if def.class and def.class ~= self.playerClass then
        return false
    end

    local playerBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local petBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if def.pet then
        if knownInBank(def.id, petBank) then
            return true
        end
    else
        if knownInBank(def.id, playerBank) then
            return true
        end
    end
    return false
end

function NS:GetActiveSpellTypes(def)
    if def.enhancedTypes then
        local playerBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if def.enhancedBySpell and knownInBank(def.enhancedBySpell, playerBank) then
            return def.enhancedTypes
        end
        if def.enhancedSpec and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
            and C_SpecializationInfo.GetSpecialization() == def.enhancedSpec then
            return def.enhancedTypes
        end
    end
    return def.types
end

function NS:UpdateSpells()
    if InCombatLockdown and InCombatLockdown() then
        self.pendingSpells = true
        return
    end

    self.knownSpells = {}
    self.typeToSpell = {}
    -- Types the character can act on but never through a unit cell: area
    -- totems, self-only reflects. They must still light the cell so the
    -- player knows to press the ability manually.
    self.manualTypeSpell = {}

    for _, def in ipairs(self.SPELL_DEFINITIONS) do
        if self:IsSpellKnown(def) then
            local name = getSpellName(def.id)
            if name then
                def.name = name
                def.secureName = getSecureSpellName(def.id, name)
                def.hasCharges = spellHasCharges(def.id)
                def.activeTypes = self:GetActiveSpellTypes(def)
                self.knownSpells[#self.knownSpells + 1] = def
                -- Unit cells must only receive spells that can legally act on
                -- their bound unit. Area/untargeted and self-only abilities
                -- remain known for capability detection, but never become a
                -- secure click or generated mouseover-macro action.
                local clickable = not def.untargeted and not def.selfOnly
                for _, dispelType in ipairs(def.activeTypes) do
                    local target = clickable and self.typeToSpell or self.manualTypeSpell
                    local current = target[dispelType]
                    if not current or (def.quality or 0) > (current.quality or 0) then
                        target[dispelType] = def
                    end
                end
            end
        end
    end

    local orderedTypes = {}
    for index, dispelType in ipairs(self.db.typeOrder) do
        if self.db.enabledTypes[dispelType] ~= false and self.typeToSpell[dispelType] then
            orderedTypes[#orderedTypes + 1] = { type = dispelType, order = index }
        end
    end

    self.clickSpells = {}
    self.typeToSlot = {}
    local byID = {}
    for _, item in ipairs(orderedTypes) do
        local def = self.typeToSpell[item.type]
        local slot = byID[def.id]
        if not slot and #self.clickSpells < 3 then
            slot = #self.clickSpells + 1
            self.clickSpells[slot] = def
            byID[def.id] = slot
        end
        if slot then
            self.typeToSlot[item.type] = slot
        end
    end

    self.pendingSpells = false
    if self.InvalidateGroupedCache then self:InvalidateGroupedCache() end
    if self.deferRefreshes then return end
    if self.RefreshAuraEngineTypes then self:RefreshAuraEngineTypes() end
    if self.ApplySecureBindings then
        self:ApplySecureBindings()
    end
    if self.UpdateAuraContainerConfiguration then
        self:UpdateAuraContainerConfiguration(true)
    end
    if self.RefreshOptions then
        self:RefreshOptions()
    end
    if self.RequestAuraSoundRefresh then
        self:RequestAuraSoundRefresh("spells updated")
    end
end

function NS:IsSpellInRange(def, unit)
    if not def or def.untargeted then
        return true
    end
    if def.selfOnly and not self:IsPlayerUnit(unit) then
        return false
    end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, value = pcall(C_Spell.IsSpellInRange, def.id, unit)
        if ok and self:CanAccess(value) and value ~= nil then
            return value == true or value == 1
        end
    end
    local inRange, checked = UnitInRange(unit)
    if self:CanAccess(checked) and checked == true and self:CanAccess(inRange) then
        return inRange == true
    end
    return true
end
