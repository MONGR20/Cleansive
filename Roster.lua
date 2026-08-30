local _, NS = ...

local RAID_GROUPS = 8
local PREVIEW_MAX = 40

-- Ordre produit : tank, puis soigneur, puis dps. Le tank passe devant parce
-- qu'une affliction sur lui tue le groupe le plus vite ; le soigneur suit parce
-- que sa perte est la seule irremplacable. L'ordre par groupe reste le defaut,
-- parce que lui repartit le travail entre plusieurs dissipeurs.
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

-- Names and classes are secret-capable in Retail 12.1, so both go through the
-- guards. An unreadable name falls back to the unit token for display and
-- counts as "no match" for the priority and skip lists: the unit stays in the
-- roster either way.
local function fullUnitName(unit)
    return NS:SafeUnitFullName(unit)
end

local function displayUnitName(unit)
    return NS:SafeUnitName(unit) or unit
end

-- When a group member takes a vehicle, their afflictions move to the pet
-- slot that carries it. Both halves matter: Lua reads the vehicle token to
-- display the right auras, and a secure attribute driver swaps the click
-- target, because the swap can happen mid-combat when Lua may not.
local VEHICLE_TOKEN = {}
VEHICLE_TOKEN.player = "pet"
for index = 1, 4 do VEHICLE_TOKEN["party" .. index] = "partypet" .. index end
for index = 1, 40 do VEHICLE_TOKEN["raid" .. index] = "raidpet" .. index end

function NS:GetVehicleUnit(unit)
    return unit and VEHICLE_TOKEN[unit] or nil
end

-- The token whose auras should be read right now.
function NS:GetDisplayUnit(unit)
    local vehicle = self:GetVehicleUnit(unit)
    if not vehicle then return unit end
    if UnitHasVehicleUI and UnitHasVehicleUI(unit) and UnitExists(vehicle) then
        return vehicle
    end
    return unit
end

function NS:GetUnitDescriptor(unit)
    local name = fullUnitName(unit)
    local class = NS:SafeUnitClass(unit)
    local group = 1
    local raidIndex = string.match(unit, "^raid(%d+)$") or string.match(unit, "^raidpet(%d+)$")
    if raidIndex then
        group = select(3, GetRaidRosterInfo(tonumber(raidIndex))) or 1
    end
    return {
        unit = unit,
        guid = self:SafeUnitGUID(unit),
        name = name,
        displayName = displayUnitName(unit),
        class = class,
        group = group,
        isPlayer = self:IsPlayerUnit(unit),
        isPet = string.find(unit, "pet", 1, true) ~= nil,
        role = NS:SafeUnitRole(unit),
    }
end

function NS:EntryMatches(entry, descriptor)
    if not entry or not descriptor then return false end
    if entry.kind == "PLAYER" then
        if not descriptor.name then return false end
        if entry.value == descriptor.name then return true end
        -- A realm-qualified entry identifies one exact player. Falling back
        -- to short names here made Alice-RealmA also match Alice-RealmB.
        -- Keep the short comparison only for legacy entries saved without a
        -- realm, which remain useful until the player records them again.
        if type(entry.value) ~= "string" or string.find(entry.value, "-", 1, true) then return false end
        local shortEntry = Ambiguate and Ambiguate(entry.value, "short") or entry.value
        local shortName = Ambiguate and Ambiguate(descriptor.name, "short") or descriptor.name
        return shortEntry == shortName
    elseif entry.kind == "CLASS" then
        return entry.value == descriptor.class
    elseif entry.kind == "GROUP" then
        return tonumber(entry.value) == tonumber(descriptor.group)
    end
    return false
end

function NS:IsSkipped(descriptor)
    if descriptor.isPlayer then return false end
    for _, entry in ipairs(self.db.skip) do
        if self:EntryMatches(entry, descriptor) then return true end
    end
    return false
end

function NS:PriorityRank(descriptor)
    if descriptor.isPlayer then return -1000 end
    for index, entry in ipairs(self.db.priority) do
        if self:EntryMatches(entry, descriptor) then return index end
    end
    return 1000
end

local function addDescriptor(list, seen, unit)
    if not UnitExists(unit) then return end
    -- The owner's visible/clickable unit becomes the pet token while they are
    -- in a vehicle. Deduplicate on that resolved token so showPets cannot add
    -- the very same vehicle a second time after its owner.
    local displayUnit = NS:GetDisplayUnit(unit) or unit
    local guid = NS:SafeUnitGUID(displayUnit) or NS:SafeUnitGUID(unit)
    if guid and seen[guid] then return end
    local descriptor = NS:GetUnitDescriptor(unit)
    if NS:IsSkipped(descriptor) then return end
    list[#list + 1] = descriptor
    if guid then seen[guid] = true end
end

-- GetUnitDescriptor reads the subgroup out of the unit token, and "player"
-- carries no raid index: the owner's own group always came back as 1. Ask the
-- roster instead, by identity rather than by name -- two servers can share a
-- name, and IsPlayerUnit cannot be fooled by one. It is also the only place
-- allowed to touch UnitIsUnit, whose result is secret under comparison
-- restriction.
function NS:PlayerRaidGroup()
    if not IsInRaid or not IsInRaid() then return 1 end
    for index = 1, MAX_RAID_MEMBERS or 40 do
        local unit = "raid" .. index
        if UnitExists(unit) and self:IsPlayerUnit(unit) then
            return select(3, GetRaidRosterInfo(index)) or 1
        end
    end
    return 1
end

function NS:BuildRoster()
    local descriptors, seen = {}, {}
    addDescriptor(descriptors, seen, "player")

    if IsInRaid() then
        for index = 1, MAX_RAID_MEMBERS or 40 do
            addDescriptor(descriptors, seen, "raid" .. index)
        end
        if self.db.showPets then
            for index = 1, MAX_RAID_MEMBERS or 40 do
                addDescriptor(descriptors, seen, "raidpet" .. index)
            end
        end
    elseif IsInGroup() then
        for index = 1, MAX_PARTY_MEMBERS or 4 do
            addDescriptor(descriptors, seen, "party" .. index)
        end
        if self.db.showPets then
            addDescriptor(descriptors, seen, "pet")
            for index = 1, MAX_PARTY_MEMBERS or 4 do
                addDescriptor(descriptors, seen, "partypet" .. index)
            end
        end
    elseif self.db.showPets then
        addDescriptor(descriptors, seen, "pet")
    end

    if self.db.showFocus and UnitIsPlayer("focus") then
        local friendly = UnitIsFriend("player", "focus")
        if self:CanAccess(friendly) and friendly == true then
            addDescriptor(descriptors, seen, "focus")
        end
    end

    -- Sorting groups 1 to 8 the same way for everyone means every dispeller in
    -- the raid reaches for the same cell first, and most of them arrive to find
    -- the work already done. Starting from your own group and wrapping around
    -- spreads it with nothing to agree on beforehand: the order is just as
    -- stable, it only begins somewhere else for each player. The priority list
    -- still wins -- it is read before this.
    local myGroup = self:PlayerRaidGroup()
    local function groupRank(group)
        local offset = (tonumber(group) or 1) - myGroup
        if offset < 0 then offset = offset + RAID_GROUPS end
        return offset
    end
    local sortMode = self.db.sortMode or "GROUP"
    table.sort(descriptors, function(a, b)
        local ar, br = self:PriorityRank(a), self:PriorityRank(b)
        if ar ~= br then return ar < br end
        if a.isPet ~= b.isPet then return not a.isPet end
        if sortMode == "ROLE" then
            local arole = ROLE_RANK[a.role] or ROLE_RANK.NONE
            local brole = ROLE_RANK[b.role] or ROLE_RANK.NONE
            if arole ~= brole then return arole < brole end
        elseif sortMode == "CLASS" then
            -- Une classe illisible part a la fin plutot que de se ranger avant
            -- les classes connues, ce que ferait la chaine vide.
            local ac, bc = a.class or "\255", b.class or "\255"
            if ac ~= bc then return ac < bc end
        end
        if a.group ~= b.group then return groupRank(a.group) < groupRank(b.group) end
        return (a.displayName or a.unit) < (b.displayName or b.unit)
    end)

    -- The preview pads the roster with inert cells so a raid layout can be
    -- tuned -- and screenshotted -- without a raid. It only ever adds: a real
    -- unit is never displaced by a fake one. These descriptors carry a token
    -- no unit can answer to, and the three places that would hand it to the
    -- game (the secure attribute, the protected aura container and the native
    -- sound registry) all refuse it on sight.
    if self.testMode then
        local wanted = math.max(1, math.min(PREVIEW_MAX, tonumber(self.db.testUnits) or 1))
        for index = #descriptors + 1, wanted do
            descriptors[#descriptors + 1] = {
                unit = "cleansivePreview" .. index,
                guid = "cleansive-preview-" .. index,
                displayName = string.format(self.L.TEST_UNIT, index),
                isPet = false,
                preview = true,
            }
        end
    end
    return descriptors
end

function NS:RebuildRoster()
    if not self.db then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingRoster")
        return
    end
    self.roster = self:BuildRoster()
    if self.InvalidateGroupedCache then self:InvalidateGroupedCache() end
    self.unitToButton = {}
    self:AssignRosterToButtons()
    self.pendingRoster = false
    -- Entrer ou sortir d'un raid change le verdict de visibilite. Le pilote
    -- securise le voit tout seul ; la couche non protegee ne recevait aucun
    -- appel a ce moment-la et restait affichee au-dessus d'une grille masquee.
    if self.UpdateCooldownOverlayVisibility then self:UpdateCooldownOverlayVisibility() end
    if self.deferRefreshes then return end
    self:RefreshAll(true)
    if self.RequestAuraSoundRefresh then
        self:RequestAuraSoundRefresh("roster updated")
    end
end

function NS:AddListEntry(kind, entryKind, value, label)
    local list = self.db[kind]
    if not list then return end
    for _, entry in ipairs(list) do
        if entry.kind == entryKind and entry.value == value then return end
    end
    list[#list + 1] = { kind = entryKind, value = value, label = label or value }
    self:Print(self.L.ADDED, label or value)
    self:RebuildRoster()
    if self.RefreshListWindow then self:RefreshListWindow() end
end

function NS:AddTargetToList(kind)
    if not UnitExists("target") or not UnitIsPlayer("target") then
        self:Print(self.L.TARGET_NEEDED)
        return
    end
    local name = fullUnitName("target")
    -- Recording an entry that can never match again is worse than refusing.
    if not name then
        self:Print(self.L.TARGET_NEEDED)
        return
    end
    self:AddListEntry(kind, "PLAYER", name, Ambiguate and Ambiguate(name, "short") or name)
end

function NS:RemoveListEntry(kind, index)
    local list = self.db[kind]
    local entry = list and list[index]
    if not entry then return end
    table.remove(list, index)
    self:Print(self.L.REMOVED, entry.label or entry.value)
    self:RebuildRoster()
    if self.RefreshListWindow then self:RefreshListWindow() end
end

function NS:MoveListEntry(kind, index, direction)
    local list = self.db[kind]
    local other = index + direction
    if not list or not list[index] or not list[other] then return end
    list[index], list[other] = list[other], list[index]
    self:RebuildRoster()
    if self.RefreshListWindow then self:RefreshListWindow() end
end

function NS:ClearList(kind)
    if not self.db or not self.db[kind] then return end
    wipe(self.db[kind])
    self:Print(self.L.CLEARED)
    self:RebuildRoster()
    if self.RefreshListWindow then self:RefreshListWindow() end
end
