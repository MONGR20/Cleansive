local _, NS = ...

local MAX_BUTTONS = 82
-- An affliction the character can clear, but never by clicking the cell.
-- Forward declaration: SetButtonState needs this before the file gets to
-- its definition, and a plain reference there would resolve to a global.
local usesAuraEngine

local DETECT_COLOR = { 0.58, 0.58, 0.62 }
local CLICK_COLORS = {
    [1] = { 0.92, 0.08, 0.08 },
    [2] = { 0.08, 0.38, 0.96 },
    [3] = { 1.00, 0.46, 0.02 },
}

local function clickHint(slot)
    if slot == 1 then return NS.L.CLICK_SHORT_LEFT end
    if slot == 2 then return NS.L.CLICK_SHORT_RIGHT end
    if slot == 3 then return NS.L.CLICK_SHORT_CTRL end
    return ""
end

-- Since Retail 12.1, aura data can become secret in combat. These types are
-- therefore also represented by Blizzard-owned AuraSlot frames. Their
-- visibility is decided by the game engine; Cleansive never branches on a
-- protected aura value to decide whether a secure unit button is clickable.
local AURA_DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local AURA_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"

local function getPotentialAuraTypes()
    local supported = {}
    for _, def in ipairs(NS.SPELL_DEFINITIONS or {}) do
        -- Include area/self-only abilities: their types must still be drawn
        -- so the player sees the affliction and casts the ability manually.
        -- Every def of the class used to count, known or not, so a class whose
        -- definitions span five types reserved an AuraSlot for all five on all
        -- 82 buttons -- 410 protected frames for a character who may know one
        -- cleanse. Only spells actually in the spellbook count now.
        -- UpdateSpells runs before CreateFrames, so knownSpells is populated by
        -- then; the class-wide set stays as a boot fallback in case it is not,
        -- and RefreshAuraEngineTypes narrows it on the next spell update.
        -- An explicit state, not the contents of the table. Testing for
        -- non-nil made the fallback unreachable (UpdateSpells clears the table
        -- on entry); testing for non-empty then kept the cautious class-wide
        -- set forever for a character who genuinely knows no cleanse. The
        -- client confirms readiness on PLAYER_ENTERING_WORLD or SPELLS_CHANGED,
        -- and an empty answer after that is a real answer.
        local resolved = NS.spellbookResolved
            or (NS.knownSpells and #NS.knownSpells > 0) or false
        if (resolved and NS:IsSpellKnown(def)) or (not resolved and def.class == NS.playerClass)
            or (not def.class and NS:IsSpellKnown(def)) then
            -- Only the types the spell can currently clear. Merging
            -- enhancedTypes unconditionally reserved a slot for an upgrade the
            -- character may not have taken: a priest without 390632 paid for
            -- Disease, a monk without 388874 for Disease and Poison.
            local types = def.activeTypes
            if not types and resolved then types = NS:GetActiveSpellTypes(def) end
            for _, auraType in ipairs(types or def.types or {}) do supported[auraType] = true end
            if not resolved then
                -- Boot fallback: nothing is resolved, so stay generous.
                for _, auraType in ipairs(def.enhancedTypes or {}) do supported[auraType] = true end
            end
        end
    end
    local result = {}
    for _, auraType in ipairs(AURA_DISPEL_TYPES) do
        -- Grouped types keep their engine slot. It is the only thing that can
        -- signal an aura Lua may not read, and 1.5.4 removed it: an unreadable
        -- affliction whose spell was outside the seasonal sound list produced
        -- no cell, no indicator and no sound at all. The wall of cells is
        -- toned down in StyleAuraVisual instead of being deleted.
        if supported[auraType] then
            result[#result + 1] = auraType
        end
    end
    return result
end

local function tryCall(method, owner, ...)
    if not method then return false end
    return pcall(method, owner, ...)
end

-- Every label carried a fixed size tuned for the default 22 px cell. At 12 px
-- the click plate covered most of the cell and the labels overlapped; at 40 px
-- the same labels floated in empty space. Sizes scale from the cell now,
-- calibrated so 22 px is byte-for-byte unchanged, and clamped at both ends.
local FONT_RULES = {
    name      = { base = 10, min = 7, max = 14 },
    stack     = { base = 10, min = 8, max = 14 },
    hint      = { base =  9, min = 7, max = 12 },
    countdown = { base = 12, min = 9, max = 16 },
    plate     = { base = 11, min = 8, max = 15 },
}

-- A name in a 12 px cell shows a letter or two. Below this, hide it rather
-- than draw mush over the rest of the cell.
local NAME_MIN_CELL = 16

function NS:CellFontSize(role, size)
    local rule = FONT_RULES[role]
    if not rule then return nil end
    local cell = tonumber(size) or tonumber(self.db and self.db.frameSize) or 22
    local scaled = math.floor(rule.base * cell / 22 + 0.5)
    return math.max(rule.min, math.min(rule.max, scaled))
end

-- One hint, always in the same corner. Each aura type used to get its own,
-- shifted sideways so two visuals on a cell would not print over each other --
-- but three plates need 46 px with their margin and the largest cell is 40, so
-- the third letter could never be drawn at all. Since the aura level already
-- encodes the type priority (CreateAuraContainer raises it for the more urgent
-- type), stacking every hint in the same corner puts the winning letter on top
-- by construction, with no offset and nothing pushed outside.
-- Returns the offset, or nil if even a single plate cannot fit.
function NS:ClickHintOffset(slot, size)
    local cell = tonumber(size) or tonumber(self.db and self.db.frameSize) or 22
    -- The plate is anchored at 1 px, so that pixel counts.
    if 1 + self:CellFontSize("plate", cell) > cell then return nil end
    return 0
end

function NS:CellShowsNames()
    if not self.db or not self.db.showNames then return false end
    return (tonumber(self.db.frameSize) or 22) >= NAME_MIN_CELL
end

function NS:ApplyCellFonts(button)
    if not button then return end
    local font = self.GetUXFont and self:GetUXFont()
    if not font then return end
    local size = self.db and self.db.frameSize
    local plate = self:CellFontSize("plate", size)
    -- Half of these regions belong to the protected engine, and in 12.1 the
    -- client can declare them forbidden to addon code: SetFont then raises.
    -- Unguarded, that aborted the whole of LayoutButtons -- and pendingLayout
    -- is cleared on its last line, so the flag stayed raised for the rest of
    -- the session and the pending plate lit up on every subsequent fight.
    -- A cosmetic font must never be able to take the layout down with it. When
    -- the client refuses, the engine's copy simply keeps the size it was built
    -- with; that is a smaller loss than a grid that never lays out again.
    local function setFont(region, role, flags)
        if region and region.SetFont then
            tryCall(region.SetFont, region, font, self:CellFontSize(role, size), flags or "")
        end
    end
    local function setPlate(region)
        if region and region.SetSize then tryCall(region.SetSize, region, plate, plate) end
    end
    setFont(button.nameText, "name")
    setFont(button.center, "stack")
    setFont(button.clickHint, "hint", "OUTLINE")
    setPlate(button.clickHintPlate)
    local cooldown = button.cooldown
    if cooldown and cooldown.GetCountdownFontString then
        setFont(cooldown:GetCountdownFontString(), "countdown", "OUTLINE")
    end
    -- The protected engine draws its own copy of every label.
    for _, visuals in pairs(button.auraSlotVisuals or {}) do
        for _, visual in ipairs(visuals) do
            setFont(visual.unitName, "name")
            setFont(visual.stack, "stack")
            setFont(visual.clickHint, "hint", "OUTLINE")
            setPlate(visual.clickHintPlate)
        end
    end
end

local function createBorder(frame)
    frame.border = {}
    for index = 1, 4 do
        local texture = frame:CreateTexture(nil, "BORDER")
        texture:SetColorTexture(1, 1, 1, 0.10)
        frame.border[index] = texture
    end
    frame.border[1]:SetPoint("TOPLEFT", -1, 1)
    frame.border[1]:SetPoint("TOPRIGHT", 1, 1)
    frame.border[1]:SetHeight(1)
    frame.border[2]:SetPoint("BOTTOMLEFT", -1, -1)
    frame.border[2]:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border[2]:SetHeight(1)
    frame.border[3]:SetPoint("TOPLEFT", -1, 1)
    frame.border[3]:SetPoint("BOTTOMLEFT", -1, -1)
    frame.border[3]:SetWidth(1)
    frame.border[4]:SetPoint("TOPRIGHT", 1, 1)
    frame.border[4]:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border[4]:SetWidth(1)
end

-- Both status notices are plates, not cells: a filled block of colour is what
-- an afflicted unit looks like, and neither of these is a unit. They also live
-- on the unprotected cooldownBody, which is the whole point of the first one --
-- it has to be able to appear while the player is in combat.
local function createStatusPlate(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(24, 16)
    frame:EnableMouse(true)
    frame:SetMouseClickEnabled(false)
    frame:SetMouseMotionEnabled(true)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(0.02, 0.03, 0.04, 0.88)
    createBorder(frame)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("CENTER")
    frame:SetScript("OnLeave", GameTooltip_Hide)
    frame:Hide()
    return frame
end


local function setBorderColor(frame, r, g, b, a)
    for _, texture in ipairs(frame.border) do
        texture:SetColorTexture(r, g, b, a or 1)
    end
end

function NS:UpdateGridAnchorAppearance()
    local anchor = self.gridAnchor
    if not anchor then return end
    local shown = not (self.db and self.db.locked)
    -- EnableMouse is protected on this secure anchor. Apply it immediately
    -- out of combat and defer only that protected operation when necessary.
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingAnchorAppearance")
    else
        anchor:EnableMouse(shown)
        self.pendingAnchorAppearance = false
    end
    if anchor.handle then anchor.handle:SetShown(shown) end
    if anchor.mark then anchor.mark:SetShown(shown) end
    if anchor.accentLine then anchor.accentLine:SetShown(shown) end
    if not shown and GameTooltip then GameTooltip:Hide() end
end

function NS:CreateGrid()
    local anchor = CreateFrame("Frame", "CleansiveGridAnchor", UIParent, "SecureHandlerStateTemplate")
    anchor:SetSize(24, 14)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    self:RestorePosition(anchor, "grid")

    local handle = anchor:CreateTexture(nil, "BACKGROUND")
    handle:SetAllPoints()
    local ar, ag, ab = 0.05, 0.82, 0.62
    if self.GetUXAccent then ar, ag, ab = self:GetUXAccent() end
    handle:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    local accentLine = anchor:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("TOPLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", 0, 0)
    accentLine:SetHeight(2)
    accentLine:SetColorTexture(ar, ag, ab, 1)
    local mark = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetPoint("CENTER")
    mark:SetText("C")
    mark:SetTextColor(ar, ag, ab, 1)
    if self.GetUXFont then mark:SetFont(self:GetUXFont(), self:CellFontSize("stack"), "") end
    anchor.handle, anchor.mark, anchor.accentLine = handle, mark, accentLine

    anchor:SetScript("OnDragStart", function(f)
        if self.db.locked or (InCombatLockdown and InCombatLockdown()) then return end
        f:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SavePosition(f, "grid")
        -- Since 1.5.17 the cell count depends on where the anchor sits, so a
        -- move that does not recount leaves the grid sized for the old
        -- position: a run computed at the centre walks off the edge as soon as
        -- the anchor is dragged towards it.
        self:LayoutButtons()
    end)
    anchor:SetScript("OnMouseUp", function(_, button)
        if IsControlKeyDown() and button == "LeftButton" then
            self:ShowList("priority")
        elseif IsShiftKeyDown() and button == "RightButton" then
            self:ShowList("skip")
        elseif IsAltKeyDown() and button == "RightButton" then
            self:ToggleOptions()
        end
    end)
    anchor:SetScript("OnEnter", function()
        if self.db.locked then return end
        GameTooltip:SetOwner(anchor, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Cleansive", ar, ag, ab)
        GameTooltip:AddLine(self.L.DRAG_MOVE, 1, 1, 1)
        GameTooltip:AddLine(self.L.PRIORITY_BIND, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(self.L.SKIP_BIND, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(self.L.OPTIONS_BIND, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", GameTooltip_Hide)

    self.gridAnchor = anchor
    self:UpdateGridAnchorAppearance()

    -- The cells live in a child container. The visibility state driver acts on
    -- that container only, so auto-hide never takes the drag handle and its
    -- context menus with it -- otherwise the grid could never be moved again.
    local body = CreateFrame("Frame", "CleansiveGridBody", anchor, "SecureHandlerStateTemplate")
    body:SetSize(1, 1)
    body:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    self.gridBody = body

    -- Spell cooldown numbers must remain writable by addon code during
    -- combat. They therefore live in a normal UIParent layer, never below a
    -- SecureActionButton or SecureHandlerStateTemplate. Its position mirrors
    -- the protected grid without anchoring to it.
    local cooldownBody = CreateFrame("Frame", "CleansiveCooldownBody", UIParent)
    cooldownBody:SetSize(24, 14)
    cooldownBody:SetFrameStrata("HIGH")
    cooldownBody:EnableMouse(false)
    self.cooldownBody = cooldownBody
    self:RestorePosition(cooldownBody, "grid")

    -- One indicator for every type the character can only clear with an area
    -- or self-only ability. It rides the unprotected layer, so it can be
    -- written during combat and it follows the grid for free.
    -- A plain Frame, not a Button: nothing here can be clicked, and a Button
    -- that answers to nothing is a promise the addon cannot keep. Motion stays
    -- enabled for the tooltip while clicks pass straight through to whatever
    -- is underneath, so the badge never swallows one.
    local manualIndicator = CreateFrame("Frame", "CleansiveManualIndicator", cooldownBody)
    manualIndicator:SetSize(24, 24)
    manualIndicator:EnableMouse(true)
    manualIndicator:SetMouseClickEnabled(false)
    manualIndicator:SetMouseMotionEnabled(true)
    -- Cells are filled blocks of colour. The badge is a dark plate with a
    -- coloured outline, so the two never read as the same kind of object.
    manualIndicator.background = manualIndicator:CreateTexture(nil, "BACKGROUND")
    manualIndicator.background:SetAllPoints()
    manualIndicator.background:SetColorTexture(0.02, 0.03, 0.04, 0.88)
    createBorder(manualIndicator)
    -- Same reasoning as the L/R/C click letters: colour alone is not a
    -- readable signal. "!" says "you press this yourself" without hue.
    manualIndicator.mark = manualIndicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manualIndicator.mark:SetPoint("TOPLEFT", 2, -1)
    manualIndicator.mark:SetText("!")
    manualIndicator.mark:SetTextColor(1, 1, 1, 1)
    manualIndicator.count = manualIndicator:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    manualIndicator.count:SetPoint("CENTER")
    manualIndicator:SetScript("OnEnter", function(frame) self:ShowManualIndicatorTooltip(frame) end)
    manualIndicator:SetScript("OnLeave", GameTooltip_Hide)
    manualIndicator:Hide()
    self.manualIndicator = manualIndicator
    -- Anchoring lived in two places: here, hardcoded above the grid, and in
    -- LayoutManualIndicator which honours the growth direction. Until the
    -- second ran, the indicator sat on the first cell in the upward layouts.
    self:LayoutManualIndicator()

    -- A protected change asked for during combat used to be silent: the option
    -- moved, nothing happened, and nothing said why. The plate is written from
    -- the unprotected layer, so it can appear at the moment the deferral is
    -- decided rather than after the fight.
    self.pendingIndicator = createStatusPlate("CleansivePendingIndicator", cooldownBody)
    self.pendingIndicator:SetScript("OnEnter", function(frame)
        if not self.db.showTooltips then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.L.PENDING_TITLE, 1, 0.82, 0.30)
        GameTooltip:AddLine(self.L.PENDING_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    -- A character with no cleanse saw a grid of grey cells that could never do
    -- anything, and no explanation anywhere on screen. This says which of the
    -- two it is: the addon is fine, this specialization simply has nothing to
    -- dispel with.
    self.noCureNotice = createStatusPlate("CleansiveNoCureNotice", cooldownBody)
    self.noCureNotice:SetScript("OnEnter", function(frame)
        if not self.db.showTooltips then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.L.NO_CURE_TITLE, 1, 0.82, 0.30)
        GameTooltip:AddLine(self.L.NO_CURE_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    self.buttons = {}
    self.engineAuraTypes = getPotentialAuraTypes()
    self.auraContainerDiagnostics = {
        expected = MAX_BUTTONS * #self.engineAuraTypes,
        added = 0,
        readyButtons = 0,
        firstError = nil,
    }
    for index = 1, MAX_BUTTONS do
        self.buttons[index] = self:CreateUnitButton(index)
        if self.buttons[index].engineAuraReady then
            self.auraContainerDiagnostics.readyButtons = self.auraContainerDiagnostics.readyButtons + 1
        end
    end
    self.engineAuraMode = #self.engineAuraTypes > 0 and self.auraContainerDiagnostics.readyButtons > 0
    if #self.engineAuraTypes > 0 and self.auraContainerDiagnostics.readyButtons < MAX_BUTTONS then
        self:Print(self.L.AURA_ENGINE_FAILED,
            self.auraContainerDiagnostics.added,
            self.auraContainerDiagnostics.expected,
            self.auraContainerDiagnostics.firstError or self.L.UNKNOWN)
    end
end

function NS:CreatePriorityDispelButton()
    local owner = CreateFrame("Frame", "CleansivePriorityBindingOwner", UIParent)
    local action = CreateFrame("Button", "CleansivePriorityDispelButton", UIParent, "SecureActionButtonTemplate")
    action:SetSize(1, 1)
    action:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
    action:SetAlpha(0)
    action:EnableMouse(false)
    action:RegisterForClicks("AnyUp")
    action:Show()
    self.priorityBindingOwner = owner
    self.priorityDispelButton = action
end

function NS:BuildPriorityDispelMacro()
    local def = self.clickSpells and self.clickSpells[1]
    local name = def and (def.secureName or def.name)
    if not name then return nil end
    if def.hostile then
        return "/cast [@mouseover,harm,nodead][@target,harm,nodead] " .. name
    end
    return "/cast [@mouseover,help,nodead][@target,help,nodead][@player] " .. name
end

function NS:ConfigurePriorityDispelButton()
    if not self.priorityDispelButton then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingPriorityBinding")
        return
    end
    local macro = self:BuildPriorityDispelMacro()
    self.priorityDispelButton:SetAttribute("type1", macro and "macro" or "none")
    self.priorityDispelButton:SetAttribute("macrotext1", macro)
end

function NS:ApplyPriorityDispelBinding(skipConfigure)
    -- Sans proprietaire de binding il n'y a rien a rejouer, et le report reste
    -- pose pour la session : inoffensif tant que rien ne le lisait, mais la
    -- plaque « en attente » resterait allumee sans que rien puisse l'eteindre.
    if not self.priorityBindingOwner then
        self.pendingPriorityBinding = false
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingPriorityBinding")
        return
    end
    if not skipConfigure then self:ConfigurePriorityDispelButton() end
    if ClearOverrideBindings then ClearOverrideBindings(self.priorityBindingOwner) end
    local key = self.db and self.db.priorityKey
    -- Never take the player's key hostage for a button that casts nothing:
    -- an override binding wins over their own, and would simply do nothing.
    local hasMacro = self:BuildPriorityDispelMacro() ~= nil
    if self.enabled and hasMacro and key and key ~= "" and SetOverrideBindingClick then
        SetOverrideBindingClick(self.priorityBindingOwner, true, key, "CleansivePriorityDispelButton", "LeftButton")
    end
    self.pendingPriorityBinding = false
end

function NS:SetPriorityDispelKey(key)
    key = type(key) == "string" and key or ""
    self.db.priorityKey = key
    self:ApplyPriorityDispelBinding()
    if self.RefreshOptions then self:RefreshOptions() end
    if key ~= "" and not self:BuildPriorityDispelMacro() then
        self:Print(self.L.NO_CURE)
    elseif InCombatLockdown and InCombatLockdown() then
        self:Print(self.L.COMBAT_LOCKED)
    else
        self:Print(key ~= "" and self.L.PRIORITY_KEY_SET or self.L.PRIORITY_KEY_CLEARED, key)
    end
end

function NS:CreateUnitButton(index)
    local button = CreateFrame("Button", "CleansiveMUF" .. index, self.gridBody, "SecureActionButtonTemplate")
    button:SetSize(self.db.frameSize, self.db.frameSize)
    button:RegisterForClicks("AnyUp")
    button.index = index

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.07, 0.09, self.db.inactiveAlpha)
    button.background = background
    createBorder(button)

    local typeMark = button:CreateTexture(nil, "ARTWORK")
    typeMark:SetPoint("BOTTOMLEFT", 1, 1)
    typeMark:SetPoint("BOTTOMRIGHT", -1, 1)
    typeMark:SetHeight(3)
    typeMark:SetColorTexture(0, 0, 0, 0)
    button.typeMark = typeMark

    local labelLayer = CreateFrame("Frame", nil, button)
    labelLayer:SetAllPoints(button)
    labelLayer:SetFrameLevel(button:GetFrameLevel() + 30)
    labelLayer:EnableMouse(false)
    if labelLayer.SetClipsChildren then labelLayer:SetClipsChildren(true) end
    button.labelLayer = labelLayer

    local charm = labelLayer:CreateTexture(nil, "OVERLAY")
    charm:SetPoint("CENTER")
    charm:SetSize(5, 5)
    charm:SetColorTexture(0.12, 1, 0.30, 1)
    charm:Hide()
    button.charm = charm

    local center = labelLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    center:SetPoint("TOPRIGHT", labelLayer, "TOPRIGHT", -1, -1)
    center:SetText("")
    if self.GetUXFont then center:SetFont(self:GetUXFont(), self:CellFontSize("stack"), "") end
    button.center = center

    local name = labelLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("BOTTOM", labelLayer, "BOTTOM", 0, 3)
    name:SetWidth(math.max(8, self.db.frameSize - 4))
    name:SetJustifyH("CENTER")
    if name.SetWordWrap then name:SetWordWrap(false) end
    if name.SetMaxLines then name:SetMaxLines(1) end
    if self.GetUXFont then name:SetFont(self:GetUXFont(), self:CellFontSize("name"), "") end
    name:Hide()
    button.nameText = name

    local hintPlate = labelLayer:CreateTexture(nil, "ARTWORK")
    hintPlate:SetPoint("TOPLEFT", 1, -1)
    hintPlate:SetSize(self:CellFontSize("plate"), self:CellFontSize("plate"))
    hintPlate:SetColorTexture(0.015, 0.025, 0.030, 0.78)
    hintPlate:Hide()
    local hint = labelLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 2, -1)
    hint:SetTextColor(1, 1, 1, 1)
    hint:SetShadowColor(0, 0, 0, 1)
    hint:SetShadowOffset(1, -1)
    if self.GetUXFont then hint:SetFont(self:GetUXFont(), self:CellFontSize("hint"), "OUTLINE") end
    hint:Hide()
    button.clickHint = hint
    button.clickHintPlate = hintPlate

    local auraDurationCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    auraDurationCooldown:SetAllPoints()
    auraDurationCooldown:SetDrawBling(false)
    auraDurationCooldown:SetDrawEdge(false)
    auraDurationCooldown:SetDrawSwipe(true)
    auraDurationCooldown:SetHideCountdownNumbers(true)
    auraDurationCooldown:SetReverse(true)
    auraDurationCooldown:SetSwipeColor(0.025, 0.035, 0.045, 0.98)
    local auraCountdown = auraDurationCooldown.GetCountdownFontString and auraDurationCooldown:GetCountdownFontString()
    if auraCountdown then auraCountdown:SetAlpha(0) end
    auraDurationCooldown:Show()
    button.auraDurationCooldown = auraDurationCooldown

    local cooldown = CreateFrame("Cooldown", "CleansiveMUFSpellCooldown" .. index,
        self.cooldownBody, "CooldownFrameTemplate")
    cooldown:SetSize(self.db.frameSize, self.db.frameSize)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetMinimumCountdownDuration(0)
    cooldown:SetFrameStrata("HIGH")
    cooldown:SetAlpha(1)
    -- Keep the numeric spell cooldown above the protected aura visuals. This
    -- frame belongs to the separate unprotected overlay, so Retail can update
    -- it in combat after the secure click has selected the exact spell.
    cooldown:SetFrameLevel(button:GetFrameLevel() + 200)
    cooldown:Hide()
    local countdown = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
    if countdown then
        countdown:SetAlpha(1)
        countdown:SetTextColor(1, 1, 1, 1)
        if self.GetUXFont then countdown:SetFont(self:GetUXFont(), self:CellFontSize("countdown"), "OUTLINE") end
    end
    button.cooldown = cooldown

    button:SetScript("PostClick", function(clicked, mouseButton)
        self:RecordSecureClick(clicked, mouseButton)
    end)
    button:SetScript("OnEnter", function(hovered)
        self:ShowButtonTooltip(hovered)
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    self:CreateAuraContainer(button)

    -- AuraSlot buttons are engine-owned in 12.1. Keep a real secure unit
    -- button above them: SecureUnitButtonTemplate is what Blizzard-compatible
    -- raid frames use to resolve the protected unit for click-cast actions.
    local clickLayer = CreateFrame("Button", "CleansiveMUFClick" .. index, button, "SecureUnitButtonTemplate")
    clickLayer:SetAllPoints(button)
    clickLayer:SetFrameLevel(button:GetFrameLevel() + 100)
    clickLayer:EnableMouse(true)
    clickLayer:EnableMouseMotion(true)
    clickLayer:RegisterForClicks("AnyUp")
    local hover = clickLayer:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    clickLayer.hoverTexture = hover
    clickLayer:SetScript("PostClick", function(_, mouseButton)
        self:RecordSecureClick(button, mouseButton)
    end)
    clickLayer:SetScript("OnEnter", function()
        self:ShowButtonTooltip(button)
    end)
    clickLayer:SetScript("OnLeave", GameTooltip_Hide)
    button.clickLayer = clickLayer

    button:Hide()
    return button
end

function NS:BuildAuraCandidateFilters(auraType)
    local filters = { includeDispelTypes = { [auraType] = true } }
    local excluded = {}
    for id, enabled in pairs(self.db.ignoredAlways or {}) do
        if enabled then excluded[tonumber(id) or id] = true end
    end
    if InCombatLockdown and InCombatLockdown() then
        for id, enabled in pairs(self.db.ignoredCombat or {}) do
            if enabled then excluded[tonumber(id) or id] = true end
        end
    end
    if next(excluded) then filters.excludeSpellIDs = excluded end
    return filters
end

function NS:StyleAuraVisual(button, auraType, visual)
    local slot = self.typeToSlot and self.typeToSlot[auraType]
    local manual = not slot and self.manualTypeSpell and self.manualTypeSpell[auraType]
    local enabled = (slot or manual) and self.db.enabledTypes[auraType] ~= false
    local grouped = self:IsTypeGrouped(auraType)
    local clickColor = slot and CLICK_COLORS[slot] or DETECT_COLOR
    local typeColor = self.TYPE_COLORS[auraType] or { 1, 1, 1 }
    local priority = self:GetTypePriority(auraType)
    -- AuraSlot owns mouse motion and its protected tooltip. It sits above the
    -- secure click layer while explicitly passing click buttons through to it.
    local level = button:GetFrameLevel() + 110 + (math.max(0, 10 - priority) * 4)
    -- A grouped cell keeps its type stripe but loses the filled background:
    -- the count next to the grid carries the message, the cell only proves
    -- the engine still sees something here.
    local alpha = enabled and (grouped and 0 or 0.92) or 0

    -- The engine can declare its own AuraSlot forbidden to addon code. That is
    -- a different mechanism from a protected function: it raises an ordinary
    -- Lua error, caught by the guards below, and never reaches
    -- ADDON_ACTION_FORBIDDEN or the dialog that offers to disable the addon --
    -- five recorded sessions confirm it. What it does do is never change back
    -- for this object, so re-arming pendingAuraStyle after it meant retrying
    -- nine refused calls on every combat for the rest of the session: 690 of
    -- them in one run, silent and pointless. Asked once, remembered, dropped.
    if visual.forbidden then return end
    local auraButton = visual.auraButton
    if auraButton and auraButton.IsForbidden then
        local known, forbidden = pcall(auraButton.IsForbidden, auraButton)
        if known and forbidden then
            visual.forbidden = true
            if self.NoteForbiddenVisual then self:NoteForbiddenVisual() end
            return
        end
    end

    -- IsForbidden above answers whether the object was DECLARED forbidden. It
    -- returned false on all 480 refusals of a recorded key: these objects are
    -- not declared anything, the calling context simply has no permission to
    -- touch them -- "from code tainted by an AddOn", as the error itself says.
    -- That is the question this asks. silent = true so the check cannot signal
    -- a blocked action of its own.
    --
    -- The recorded contexts were lock=0|ChallengeMode,Map,Chat (450) and
    -- lock=0|Encounter,ChallengeMode,Map,Chat (30): every single refusal
    -- happened while InCombatLockdown() said the addon was free to act. That
    -- is why nine calls were fired and refused 480 times over one dungeon.
    local api = C_RestrictedActions
    if auraButton and api and api.CheckAllowProtectedFunctions then
        local known, permitted = pcall(api.CheckAllowProtectedFunctions, auraButton, true)
        if known and not permitted then
            -- Deferred, not abandoned: the restriction lifts at the end of the
            -- run and the visual must be styled then. One check replaces nine
            -- refused calls, and it is not an error -- counting it as one was
            -- what made the diagnostics look like a fault.
            self:MarkPending("pendingAuraStyle", true)
            if self.NoteStyleSkipped then self:NoteStyleSkipped() end
            return
        end
    end

    local hintOffset = self:ClickHintOffset(slot, self.db.frameSize)
    local hintShown = enabled and (slot ~= nil or manual ~= nil)
        and self.db.showClickHints and hintOffset ~= nil

    -- One refusal used to take the whole block with it. SetFrameLevel was the
    -- first line, and a real session on 29/08/2026 had it forbidden 315 times:
    -- the overlay, the type stripe, the stack and the click letter were never
    -- applied either, because the client had declined an unrelated call above
    -- them. This is the font bug of 1.5.35 in another place -- that one was
    -- fixed only where it had been observed, which is why this one survived.
    -- Each step now stands on its own: what the client allows is applied.
    local failures, firstError = 0, nil
    local function step(fn)
        local ok, err = pcall(fn)
        if not ok then
            failures = failures + 1
            firstError = firstError or err
        end
    end

    -- The engine's own frame: the one that was refused in the field.
    step(function()
        visual.auraButton:SetFrameLevel(level)
        if visual.auraButton.SetMouseMotionEnabled then
            visual.auraButton:SetMouseMotionEnabled(enabled and self.db.showTooltips)
        end
    end)
    step(function()
        visual.overlay:SetColorTexture(clickColor[1], clickColor[2], clickColor[3], alpha)
    end)
    step(function()
        visual.typeMark:SetColorTexture(typeColor[1], typeColor[2], typeColor[3], enabled and 1 or 0)
    end)
    step(function()
        visual.stack:ClearAllPoints()
        if slot == 2 then
            visual.stack:SetPoint("RIGHT", button, "RIGHT", -1, 0)
        elseif slot == 3 then
            visual.stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 3)
        else
            visual.stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
        end
        visual.stack:SetShown(enabled and self.db.showStacks and not self:CellShowsNames())
    end)
    if visual.unitName then
        step(function()
            visual.unitName:SetWidth(math.max(8, self.db.frameSize - 4))
            visual.unitName:SetText(button.descriptor and button.descriptor.displayName or button.unit or "")
            visual.unitName:SetShown(enabled and self:CellShowsNames())
        end)
    end
    if visual.clickHint then
        step(function()
            visual.clickHint:ClearAllPoints()
            visual.clickHint:SetPoint("TOPLEFT", button, "TOPLEFT", 2 + (hintOffset or 0), -1)
            visual.clickHint:SetText(slot and clickHint(slot) or (manual and "!" or ""))
            -- Manual abilities use an exclamation mark, never a click letter.
            visual.clickHint:SetShown(hintShown)
        end)
    end
    if visual.clickHintPlate then
        step(function()
            visual.clickHintPlate:ClearAllPoints()
            visual.clickHintPlate:SetPoint("TOPLEFT", button, "TOPLEFT", 1 + (hintOffset or 0), -1)
            visual.clickHintPlate:SetShown(hintShown)
        end)
    end
    if visual.durationCooldown then
        step(function()
            visual.durationCooldown:SetFrameLevel(level + 1)
            visual.durationCooldown:SetDrawSwipe(enabled and true or false)
        end)
    end
    if visual.labelLayer then
        step(function() visual.labelLayer:SetFrameLevel(level + 3) end)
    end
    -- Silent, and deliberately so. This restyles labels the protected engine
    -- owns, and 12.1 can declare them forbidden to addon code: a real session
    -- failed here 315 times without one attempt ever succeeding. Announcing it
    -- lit the pending plate for the whole of every fight, about an operation
    -- the player did not ask for and no amount of waiting will complete.
    -- The flag still replays; only the promise is withdrawn, and the reason is
    -- written down where it can be read afterwards.
    if failures > 0 then
        self:MarkPending("pendingAuraStyle", true)
        if self.NoteStyleFailure then self:NoteStyleFailure(firstError, failures) end
    end
end

function NS:UpdateButtonAfflictionAlert(button, aura, slot, silent)
    local afflicted = aura and true or false
    local alertKey
    if afflicted then
        local auraInstanceID = aura.auraInstanceID
        local spellID = aura.spellId
        if self:CanAccess(auraInstanceID) and auraInstanceID then
            alertKey = "aura:" .. tostring(auraInstanceID)
        elseif self:CanAccess(spellID) and spellID then
            alertKey = "spell:" .. tostring(spellID)
        else
            alertKey = true
        end
    end
    if alertKey and alertKey ~= button.alertAuraKey and not silent then
        self:PlayAfflictionAlert()
    end
    button.alertAuraKey = alertKey
end

function NS:UpdateReadableAfflictionAlert(button, unit, silent)
    if not self.db or not self.db.sound or not self.enabled then
        button.alertAuraKey = nil
        return
    end
    local ok, aura, auraType, slot, _, charmed = pcall(self.GetCurableAura, self, unit, true)
    if not ok then
        button.alertAuraKey = nil
        return
    end

    if charmed and auraType ~= "Charm" and self.typeToSlot.Charm then
        aura = { name = self.L.STATUS_CHARMED, dispelName = "Charm", applications = 0 }
        auraType, slot = "Charm", self.typeToSlot.Charm
    end

    if aura and auraType ~= "Charm" then
        local spellID = aura.spellId
        if not self:CanAccess(spellID) then
            -- Native registrations remain authoritative when the spell ID is
            -- protected; guessing here could play the same alert twice.
            self:UpdateButtonAfflictionAlert(button, nil, nil, true)
            return
        end
        local soundUnit = self.GetDisplayUnit and self:GetDisplayUnit(unit) or unit
        if spellID and self.IsAuraSoundRegistered and self:IsAuraSoundRegistered(soundUnit, spellID) then
            self:UpdateButtonAfflictionAlert(button, nil, nil, true)
            return
        end
    end
    self:UpdateButtonAfflictionAlert(button, aura, slot, silent)
end

-- One protected slot for one dispel type. Extracted from CreateAuraContainer
-- so that a container can gain a type later instead of being thrown away and
-- rebuilt: Blizzard exposes AddAuraSlot to addons but keeps UnregisterAuraSlot
-- and ClearAuraSlots on its private mixins, so slots are added, never removed.
function NS:AddAuraSlotForType(button, auraType)
    local container = button.auraContainer
    if not container then return false end
    local diagnostics = self.auraContainerDiagnostics
    local function recordFailure(reason)
        if not diagnostics then return end
        if not diagnostics.firstError then diagnostics.firstError = tostring(reason) end
        diagnostics.activeError = diagnostics.activeError or tostring(reason)
    end
    local addedForButton = 0
    local slotKey = "cleansive_" .. string.lower(auraType)
    button.auraSlotKeys[auraType] = slotKey
    button.auraSlotVisuals[auraType] = {}
    local candidateFilters = self:BuildAuraCandidateFilters(auraType)

    local added, auraSlotOrError = pcall(container.AddAuraSlot, container, slotKey, AURA_FILTER, {
        candidateFilters = candidateFilters,
        initializeFrame = function(auraButton)
            -- The protected aura slot inherits the secure cell's rectangle.
            -- Resizing the cell therefore also resizes every engine-owned
            -- affliction visual without mutating its protected layout later.
            auraButton:ClearAllPoints()
            auraButton:SetAllPoints(button)
            local auraPriority = self:GetTypePriority(auraType)
            local auraLevel = button:GetFrameLevel() + 110 + (math.max(0, 10 - auraPriority) * 4)
            auraButton:SetFrameLevel(auraLevel)
            tryCall(auraButton.SetMouseClickEnabled, auraButton, false)
            tryCall(auraButton.SetMouseMotionEnabled, auraButton, self.db.showTooltips)
            tryCall(auraButton.SetPassThroughButtons, auraButton,
                "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5")
            tryCall(auraButton.SetTooltipAnchorPoint, auraButton, "ANCHOR_RIGHT")

            local auraHover = auraButton:CreateTexture(nil, "HIGHLIGHT")
            auraHover:SetAllPoints(button)
            auraHover:SetColorTexture(1, 1, 1, 0.08)

            local overlay = auraButton:CreateTexture(nil, "ARTWORK", nil, 1)
            overlay:SetAllPoints(button)

            local labelLayer = CreateFrame("Frame", nil, auraButton)
            labelLayer:SetAllPoints(auraButton)
            labelLayer:SetFrameLevel(auraLevel + 3)
            labelLayer:EnableMouse(false)

            local typeMark = labelLayer:CreateTexture(nil, "OVERLAY", nil, 3)
            typeMark:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
            typeMark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            typeMark:SetHeight(3)

            local stack = labelLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
            if auraButton.SetApplicationCount then
                tryCall(auraButton.SetApplicationCount, auraButton, stack, {})
            end

            local durationCooldown
            if auraButton.SetDurationCooldown then
                local created, candidate = pcall(CreateFrame, "Cooldown", nil, auraButton, "CooldownFrameTemplate")
                if created and candidate then
                    local configured = pcall(function()
                        candidate:SetAllPoints(auraButton)
                        candidate:SetFrameLevel(auraLevel + 1)
                        candidate:SetDrawBling(false)
                        candidate:SetDrawEdge(false)
                        candidate:SetDrawSwipe(true)
                        candidate:SetHideCountdownNumbers(true)
                        candidate:SetReverse(true)
                        candidate:SetSwipeColor(0.025, 0.035, 0.045, 0.98)
                        local countdown = candidate.GetCountdownFontString and candidate:GetCountdownFontString()
                        if countdown then countdown:SetAlpha(0) end
                        candidate:Show()
                        auraButton:SetDurationCooldown(candidate)
                    end)
                    if configured then
                        durationCooldown = candidate
                    else
                        candidate:Hide()
                    end
                end
            end

            local hintPlate = labelLayer:CreateTexture(nil, "ARTWORK", nil, 2)
            hintPlate:SetSize(9, 11)
            hintPlate:SetColorTexture(0.015, 0.025, 0.030, 0.78)
            -- Cachee des la creation. C'est StyleAuraVisual qui decide de la
            -- montrer, et ce stylage peut etre refuse par le client : le releve
            -- du 29/08/2026 en compte 690 refus en une session. De toutes ces
            -- regions, la plaque est la seule a naitre avec une couleur -- les
            -- autres n'ont ni teinte ni texte et ne se voient pas. Un refus au
            -- tout premier passage laissait donc un carre sombre dans le coin
            -- d'une cellule, sur une option que le joueur avait desactivee.
            -- La cellule de repli fait deja cela depuis toujours (CreateButton).
            hintPlate:Hide()
            local hint = labelLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hint:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
            hint:SetTextColor(1, 1, 1, 1)
            hint:SetShadowColor(0, 0, 0, 1)
            hint:SetShadowOffset(1, -1)
            if self.GetUXFont then hint:SetFont(self:GetUXFont(), self:CellFontSize("hint"), "OUTLINE") end

            local unitName = labelLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            unitName:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
            unitName:SetWidth(math.max(8, self.db.frameSize - 4))
            unitName:SetJustifyH("CENTER")
            if unitName.SetWordWrap then unitName:SetWordWrap(false) end
            if unitName.SetMaxLines then unitName:SetMaxLines(1) end
            if self.GetUXFont then unitName:SetFont(self:GetUXFont(), self:CellFontSize("name"), "") end

            local visual = {
                auraButton = auraButton,
                overlay = overlay,
                typeMark = typeMark,
                stack = stack,
                durationCooldown = durationCooldown,
                clickHint = hint,
                clickHintPlate = hintPlate,
                unitName = unitName,
                labelLayer = labelLayer,
                auraHover = auraHover,
            }
            local visuals = button.auraSlotVisuals[auraType]
            visuals[#visuals + 1] = visual
            self:StyleAuraVisual(button, auraType, visual)
        end,
    })
    if added then
        addedForButton = addedForButton + 1
    else
        recordFailure(auraSlotOrError or "AddAuraSlot failed")
        button.auraSlotKeys[auraType] = nil
        button.auraSlotVisuals[auraType] = nil
    end
    return addedForButton > 0
end

function NS:CreateAuraContainer(button)
    local diagnostics = self.auraContainerDiagnostics
    button.engineAuraReady = false
    local function recordFailure(reason)
        if diagnostics and not diagnostics.firstError then diagnostics.firstError = tostring(reason) end
    end

    if not self.engineAuraTypes or #self.engineAuraTypes == 0 then return end
    if not C_AddOns or not C_AddOns.LoadAddOn or not C_AddOns.IsAddOnLoaded then
        recordFailure("Blizzard_AuraContainer loader unavailable")
        return
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local loaded, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        if not loaded then
            recordFailure(reason or "Blizzard_AuraContainer could not be loaded")
            return
        end
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, button, "CustomAuraContainerTemplate")
    if not ok or not container or not container.AddAuraSlot then
        recordFailure(container or "CustomAuraContainerTemplate unavailable")
        return
    end
    container:SetPoint("CENTER", button, "CENTER")
    container:SetSize(1, 1)
    button.auraContainer = container
    button.auraSlotVisuals = {}
    button.auraSlotKeys = {}
    local addedForButton = 0

    for index = 1, #self.engineAuraTypes do
        if self:AddAuraSlotForType(button, self.engineAuraTypes[index]) then
            addedForButton = addedForButton + 1
        end
    end

    button.engineAuraReady = addedForButton == #self.engineAuraTypes
    if button.engineAuraReady then
        if diagnostics then diagnostics.added = diagnostics.added + addedForButton end
    else
        container:Hide()
        button.auraContainer = nil
    end
end

function NS:ConfigureButtonAuraContainer(button, restyle)
    -- A preview cell has no unit the game can answer for. Asking the protected
    -- container about it is the one thing this whole feature must never do, so
    -- the refusal lives here rather than at each call site.
    if button and button.preview then return end
    local container = button and button.auraContainer
    if not container then return end

    if restyle then
        for auraType, visuals in pairs(button.auraSlotVisuals or {}) do
            for _, visual in ipairs(visuals) do
                self:StyleAuraVisual(button, auraType, visual)
            end
        end
    end

    if container.SetAuraSlotCandidateFilters then
        -- Slots accumulate over a session, so this list also holds types the
        -- character can no longer clear. Handing them real filters here undid
        -- the neutralisation ReconcileAuraSlots had just applied, and this runs
        -- on every layout, roster assignment and filter edit.
        local active = self.engineAuraTypeSet
        for auraType, slotKey in pairs(button.auraSlotKeys or {}) do
            local filters = (not active or active[auraType])
                and self:BuildAuraCandidateFilters(auraType)
                or { includeDispelTypes = {} }
            local ok = pcall(container.SetAuraSlotCandidateFilters, container, slotKey, filters)
            if not ok then self:MarkPending("pendingAuraFilters") end
        end
    end

    if button.unit then
        local containerUnit = self.GetDisplayUnit and self:GetDisplayUnit(button.unit) or button.unit
        local ok = pcall(container.SetUnit, container, containerUnit)
        if ok then button.auraContainerUnit = containerUnit end
    end
end

function NS:UpdateAuraContainerConfiguration(restyle)
    if not self.buttons then return end
    for _, button in ipairs(self.buttons) do
        if button.unit then self:ConfigureButtonAuraContainer(button, restyle) end
    end
end

function NS:RefreshAuraCandidateFilters()
    -- A filter edit changes what a scan means while the grouped set stays
    -- identical, so the signature never notices. Forget explicitly.
    if self.InvalidateGroupedCache then self:InvalidateGroupedCache() end
    self.pendingAuraFilters = false
    self:UpdateAuraContainerConfiguration(false)
    -- Combat-only filters change meaning on PLAYER_REGEN_DISABLED without
    -- necessarily producing another UNIT_AURA. Repaint the readable grouped
    -- badge now instead of leaving its pre-combat count on screen.
    if self.RequestManualIndicatorUpdate then self:RequestManualIndicatorUpdate() end
end

function NS:CreateFrames()
    self:CreateGrid()
    self:CreatePriorityDispelButton()
    -- AuraContainer reacts to UNIT_AURA inside Blizzard's secure engine. A
    -- polling scanner is unnecessary and unsafe on 12.1 because range and
    -- aura results can be secret values. All Lua-side refreshes are now
    -- event-driven, including the graceful fallback path.
end

function NS:ApplySecureBindings()
    if not self.buttons then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingSpells")
        return
    end
    local one = self.clickSpells and self.clickSpells[1]
    local two = self.clickSpells and (self.clickSpells[2] or one)
    local three = self.clickSpells and (self.clickSpells[3] or one)
    for _, button in ipairs(self.buttons) do
        if button.unit then
        local target = button.clickLayer or button
        local oneName = one and (one.secureName or one.name)
        local twoName = two and (two.secureName or two.name)
        local threeName = three and (three.secureName or three.name)

        -- Replace both the exact and wildcard defaults supplied by the unit
        -- template so Retail 12.1 cannot fall back to target/menu behavior.
        target:SetAttribute("type1", oneName and "spell" or "none")
        target:SetAttribute("spell1", oneName)
        target:SetAttribute("*type1", oneName and "spell" or "none")
        target:SetAttribute("*spell1", oneName)

        target:SetAttribute("type2", twoName and "spell" or "none")
        target:SetAttribute("spell2", twoName)
        target:SetAttribute("*type2", twoName and "spell" or "none")
        target:SetAttribute("*spell2", twoName)

        target:SetAttribute("ctrl-type1", threeName and "spell" or "none")
        target:SetAttribute("ctrl-spell1", threeName)
        target:SetAttribute("type3", "target")
        target:SetAttribute("ctrl-type3", "focus")

        -- The two awkward combinations, mirrored onto the thumb buttons for
        -- players whose mouse has them. Nothing new is bound: button 4 is the
        -- third cleanse, already on Ctrl + left, and button 5 sets focus,
        -- already on Ctrl + middle. A mouse without them loses nothing.
        -- The wildcards are set for the same reason as buttons 1 and 2 above:
        -- the unit template can supply its own default and 12.1 would fall
        -- back to it.
        target:SetAttribute("type4", threeName and "spell" or "none")
        target:SetAttribute("spell4", threeName)
        target:SetAttribute("*type4", threeName and "spell" or "none")
        target:SetAttribute("*spell4", threeName)

        target:SetAttribute("type5", "focus")
        target:SetAttribute("*type5", "focus")
        end
    end
    self:ConfigurePriorityDispelButton()
    self:ApplyPriorityDispelBinding(true)
end

function NS:AssignRosterToButtons()
    if not self.buttons then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingRoster")
        return
    end
    wipe(self.unitToButton)
    for index, button in ipairs(self.buttons) do
        local descriptor = self.roster[index]
        if descriptor then
            local previousGUID = button.descriptor and button.descriptor.guid
            if previousGUID ~= descriptor.guid then
                button.cooldownSlot = nil
                button.cooldownClickTime = nil
                if button.cooldown and button.cooldown.Clear then button.cooldown:Clear() end
            end
            button.unit = descriptor.unit
            button.descriptor = descriptor
            -- A preview cell is decoration. Giving it a secure unit would arm a
            -- click on a unit that cannot exist, and the attribute could not be
            -- taken back once combat starts.
            button.preview = descriptor.preview and true or nil
            local secureUnit = not descriptor.preview and descriptor.unit or nil
            button:SetAttribute("unit", secureUnit)
            if button.clickLayer then
                button.clickLayer.unit = secureUnit
                button.clickLayer:SetAttribute("unit", secureUnit)
                self:ApplyVehicleDriver(button.clickLayer, secureUnit)
            end
            button.center:SetText("")
            button.nameText:SetText(descriptor.displayName or descriptor.unit)
            button:Show()
            button.cooldown:Show()
            if not self.deferRefreshes then self:ConfigureButtonAuraContainer(button, true) end
            self.unitToButton[descriptor.unit] = button
        else
            button.cooldownSlot = nil
            button.cooldownClickTime = nil
            if button.cooldown and button.cooldown.Clear then button.cooldown:Clear() end
            button.unit = nil
            button.descriptor = nil
            button:SetAttribute("unit", nil)
            if button.clickLayer then
                self:ApplyVehicleDriver(button.clickLayer, nil)
                button.clickLayer.unit = nil
                button.clickLayer:SetAttribute("unit", nil)
            end
            button:Hide()
            button.cooldown:Hide()
        end
    end
    if not self.deferRefreshes then
        self:ApplySecureBindings()
        self:LayoutButtons()
    end
end

-- SetClampedToScreen only holds the little anchor in place, so a strict run of
-- 82 cells walks off the screen on its own. Cap a run at what actually fits;
-- nil means the screen size is unknown and nothing is capped.
-- Exact rather than approximate: the run costs (n-1) steps plus one whole cell
-- plus the layout's own margin. Dividing the extent by the step alone allowed
-- one cell too many, which showed up as a single row hanging off the edge.
function NS:MaxCellsPerRun(size, spacing, extent, margin)
    if type(extent) ~= "number" or extent <= 0 then return nil end
    local cell = tonumber(size) or 0
    local step = cell + (tonumber(spacing) or 0)
    if step <= 0 then return nil end
    local usable = extent - (tonumber(margin) or 0) - cell
    if usable < 0 then return 1 end
    return math.max(1, math.min(MAX_BUTTONS, math.floor(usable / step) + 1))
end

local function edgeOf(frame, getter)
    if not frame or not frame[getter] then return nil end
    local ok, value = pcall(frame[getter], frame)
    if not ok or type(value) ~= "number" then return nil end
    return value
end

-- Space from the anchor's own edge to the screen edge, in the direction the
-- grid actually grows. 1.5.15 used the full screen size instead, which is only
-- correct when the anchor happens to sit against the opposite edge: from a
-- centred anchor it allowed roughly twice the cells that fit, and the far half
-- of a raid was drawn off screen. A nil result means the frames are not placed
-- yet and nothing is capped.
function NS:AvailableExtent(horizontal, towardPositive)
    local anchor = self.gridAnchor
    if not anchor or not UIParent then return nil end
    if horizontal then
        if towardPositive then
            local left, right = edgeOf(anchor, "GetLeft"), edgeOf(UIParent, "GetRight")
            if not left or not right then return nil end
            return right - left
        end
        local right, left = edgeOf(anchor, "GetRight"), edgeOf(UIParent, "GetLeft")
        if not right or not left then return nil end
        return right - left
    end
    -- The run starts at the anchor edge it is attached to, not the opposite
    -- one: growing down, cells hang from the anchor's bottom; growing up, they
    -- stack from its top. Measuring from the far edge gave a few pixels too
    -- many and the last row hung off the screen.
    if towardPositive then
        local anchorTop, screenTop = edgeOf(anchor, "GetTop"), edgeOf(UIParent, "GetTop")
        if not anchorTop or not screenTop then return nil end
        return screenTop - anchorTop
    end
    local anchorBottom, screenBottom = edgeOf(anchor, "GetBottom"), edgeOf(UIParent, "GetBottom")
    if not anchorBottom or not screenBottom then return nil end
    return anchorBottom - screenBottom
end

-- When the anchor sits against the edge the grid grows towards, no wrap can
-- fit: the space there is worth about thirty cells and a raid needs eighty.
-- Rather than draw half a raid off screen, slide the anchor back until the
-- rectangle fits. The saved position is deliberately left alone -- this is a
-- display-time correction, so the grid returns to the chosen spot by itself
-- once the cells shrink or the group does.
-- `behind` is the space the grid needs on the far side of the anchor: the
-- grouped badge is anchored opposite the growth direction, so a grid that fits
-- perfectly going down can still push its badge off the top edge.
function NS:NudgeGridOnScreen(neededAcross, neededDown, growRight, growDown, behind)
    local anchor = self.gridAnchor
    if not anchor or not UIParent then return end
    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    if not point or type(x) ~= "number" or type(y) ~= "number" then return end

    local roomAcross = self:AvailableExtent(true, growRight)
    local roomDown = self:AvailableExtent(false, not growDown)
    local dx, dy = 0, 0
    if roomAcross and neededAcross > roomAcross then
        local excess = neededAcross - roomAcross
        dx = growRight and -excess or excess
    end
    if roomDown and neededDown > roomDown then
        local excess = neededDown - roomDown
        dy = growDown and excess or -excess
    end
    -- The far side, where the badge lives.
    local roomBehind = self:AvailableExtent(false, growDown)
    if behind and behind > 0 and roomBehind and behind > roomBehind then
        local excess = behind - roomBehind
        dy = dy + (growDown and -excess or excess)
    end
    if dx == 0 and dy == 0 then return end

    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relativePoint or "CENTER", x + dx, y + dy)
    if self.cooldownBody then
        self.cooldownBody:ClearAllPoints()
        self.cooldownBody:SetPoint(point, UIParent, relativePoint or "CENTER", x + dx, y + dy)
    end
end

function NS:LayoutButtons()
    if not self.buttons then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingLayout")
        return
    end
    local size, spacing, columns = self.db.frameSize, self.db.spacing, self.db.columns
    local layoutMode = self.db.layoutMode or "GRID"
    -- A run that leaves the screen shows nothing, so it wraps instead. The
    -- shape the player asked for is kept: horizontal still fills a row before
    -- starting another, vertical still fills a column.
    -- Start from the position the player chose, not from wherever the last
    -- correction left the anchor. Without this the nudge was one-way: the grid
    -- never came back once a raid had pushed it, contrary to what 1.5.18
    -- claimed. OnDragStop saves before relaying out, so a drag is not lost.
    if self.RestorePosition and self.db.positions then
        self:RestorePosition(self.gridAnchor, "grid")
    end
    -- Resize the anchor before reading its edges: measuring first and resizing
    -- afterwards computed the space from the previous rectangle, so a size
    -- change near a screen edge lost up to a cell.
    self.gridAnchor:SetSize(size, math.max(12, math.floor(size * 0.55)))
    local growRightEarly = self.db.grow == "RIGHT_DOWN" or self.db.grow == "RIGHT_UP"
    local growDownEarly = self.db.grow == "RIGHT_DOWN" or self.db.grow == "LEFT_DOWN"
    -- Both axes, not just the run. A capped row still wraps downwards and a
    -- capped column still wraps sideways, so bounding only the primary axis
    -- left the fold free to walk off the other edge -- which is what happens
    -- when the anchor sits near the edge the grid grows towards.
    -- Fold on the cells the player actually sees. Buttons past the roster are
    -- hidden by AssignRosterToButtons, so folding on the full pool of 82 shrank
    -- a five-man grid as if it had to hold a raid.
    local shown = math.max(1, math.min(MAX_BUTTONS, #(self.roster or {})))
    if not self.roster or #self.roster == 0 then shown = MAX_BUTTONS end
    -- The grouped badge sits a full cell plus 4 px behind the anchor. Reserving
    -- it only at the final nudge was too late: the rows were already chosen
    -- against the whole height, so sliding the grid down to save the badge
    -- pushed the last row out by exactly as much. Work out here how much the
    -- correction will steal, and choose the rows against what is left.
    local behind = 0
    if self.db.groupManualTypes and self.GetManualOnlyTypes and #self:GetManualOnlyTypes() > 0 then
        behind = size + 4
    end
    local roomBehind = self:AvailableExtent(false, growDownEarly)
    local stolen = 0
    if behind > 0 and roomBehind and behind > roomBehind then
        stolen = behind - roomBehind
    end

    local maxAcross = self:MaxCellsPerRun(size, spacing, self:AvailableExtent(true, growRightEarly))
    local forwardRoom = self:AvailableExtent(false, not growDownEarly)
    local maxDown = self:MaxCellsPerRun(size, spacing, forwardRoom and (forwardRoom - stolen), 3)
    local rows
    if layoutMode == "HORIZONTAL" then
        columns = maxAcross or MAX_BUTTONS
        -- Widen the row so the fold needs no more rows than fit.
        if maxDown and maxAcross then
            columns = math.min(maxAcross, math.max(columns, math.ceil(shown / maxDown)))
        end
    elseif layoutMode == "VERTICAL" then
        rows = maxDown or MAX_BUTTONS
        if maxAcross and maxDown then
            rows = math.min(maxDown, math.max(rows, math.ceil(shown / maxAcross)))
        end
        columns = 1
    else
        if maxAcross then columns = math.min(columns, maxAcross) end
        if maxDown and maxAcross then
            columns = math.min(maxAcross, math.max(columns, math.ceil(shown / maxDown)))
        end
    end
    local growRight = self.db.grow == "RIGHT_DOWN" or self.db.grow == "RIGHT_UP"
    local growDown = self.db.grow == "RIGHT_DOWN" or self.db.grow == "LEFT_DOWN"
    for index, button in ipairs(self.buttons) do
        button:SetSize(size, size)
        button.cooldown:SetSize(size, size)
        button.nameText:SetWidth(math.max(8, size - 4))
        self:ApplyCellFonts(button)
        button:ClearAllPoints()
        button.cooldown:ClearAllPoints()
        local col, row
        if rows then
            -- Vertical fills a column before moving to the next one.
            row = (index - 1) % rows
            col = math.floor((index - 1) / rows)
        else
            col = (index - 1) % columns
            row = math.floor((index - 1) / columns)
        end
        local x = (growRight and 1 or -1) * col * (size + spacing)
        local y = (growDown and -1 or 1) * (row * (size + spacing) + 3)
        local point = growRight and (growDown and "TOPLEFT" or "BOTTOMLEFT") or (growDown and "TOPRIGHT" or "BOTTOMRIGHT")
        local relative = growRight and (growDown and "BOTTOMLEFT" or "TOPLEFT") or (growDown and "BOTTOMRIGHT" or "TOPRIGHT")
        button:SetPoint(point, self.gridAnchor, relative, x, y)
        button.cooldown:SetPoint(point, self.cooldownBody, relative, x, y)
    end
    -- The rectangle the placed cells actually occupy.
    local across = rows and math.ceil(shown / rows) or math.min(shown, columns)
    local down = rows and math.min(shown, rows) or math.ceil(shown / columns)
    local step = size + spacing
    self:NudgeGridOnScreen((across - 1) * step + size, (down - 1) * step + size + 3,
        growRightEarly, growDownEarly, behind)
    self:LayoutManualIndicator()
    self:LayoutStatusNotices()
    self.cooldownBody:SetSize(size, math.max(12, math.floor(size * 0.55)))
    self.pendingLayout = false
    self:UpdateAuraContainerConfiguration(true)
end

function NS:GetTypePriority(dispelType)
    for index, value in ipairs(self.db.typeOrder) do
        if value == dispelType then return index end
    end
    return 999
end

function NS:IsAuraIgnored(aura)
    local id = aura and aura.spellId
    if not self:CanAccess(id) or not id then return false end
    return self.db.ignoredAlways[id] or self.db.ignoredAlways[tostring(id)] or
        (InCombatLockdown and InCombatLockdown() and (self.db.ignoredCombat[id] or self.db.ignoredCombat[tostring(id)]))
end

function NS:RememberAura(aura)
    if not aura then return end
    local id, name = aura.spellId, aura.name
    if aura.test or not self:CanAccess(id) or not id or id == 0 then return end
    id = tonumber(id) or id
    local history, order = self:GetAuraHistory()

    -- This runs for every aura of every unit on every UNIT_AURA. When the
    -- spell is already the most recent entry there is nothing to move, which
    -- is by far the common case during a fight.
    if order[#order] == id and history[id] then return end

    for index = #order, 1, -1 do
        if order[index] == id then table.remove(order, index) break end
    end
    order[#order + 1] = id
    if #order > 100 then
        local oldest = table.remove(order, 1)
        history[oldest] = nil
        history[tostring(oldest)] = nil
    end
    local auraType = aura.dispelName
    history[id] = {
        name = self:CanAccess(name) and name or (self.L.UNKNOWN .. " " .. id),
        auraType = self:CanAccess(auraType) and auraType or nil,
    }
    if self.RefreshAuraHistoryPage and self.optionsFrame and self.optionsFrame:IsShown() then
        if not self.auraHistoryRefreshScheduled then
            self.auraHistoryRefreshScheduled = true
            local function refresh()
                self.auraHistoryRefreshScheduled = false
                self:RefreshAuraHistoryPage()
            end
            if C_Timer and C_Timer.After then C_Timer.After(0, refresh) else refresh() end
        end
    end
end

function NS:RecordReadableAuraHistory(unit)
    unit = self.GetDisplayUnit and self:GetDisplayUnit(unit) or unit
    for index = 1, 40 do
        local aura = self:GetAuraByIndex(unit, index)
        if not aura then break end
        self:RememberAura(aura)
    end
end

function NS:GetAuraByIndex(unit, index)
    if not C_UnitAuras or not C_UnitAuras.GetDebuffDataByIndex then return nil end
    local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index, "RAID_PLAYER_DISPELLABLE")
    if ok then return aura end
    return nil
end

-- Colouring every cell at once reads as an emergency, not as a layout. The
-- default lights the first cell and then every fourth one, so the preview
-- shows both states at every group size -- including a group of one.
function NS:PreviewCellIsAfflicted(index)
    local state = self.db and self.db.testState or "MIXED"
    if state == "HEALTHY" then return false end
    if state == "ALL" then return true end
    index = tonumber(index) or 1
    return index == 1 or (index % 4) == 0
end

function NS:GetCurableAura(unit, includeGrouped)
    if self.testMode then
        local cell = self.unitToButton[unit]
        if not self:PreviewCellIsAfflicted(cell and cell.index or 1) then return nil end
        local slot = ((cell and cell.index or 1) - 1) % math.max(1, #self.clickSpells) + 1
        local def = self.clickSpells[slot] or self.clickSpells[1]
        local auraType = def and (def.activeTypes or def.types)[1] or "Magic"
        return {
            name = self.L.TEST_AFFLICTION,
            dispelName = auraType,
            applications = 3,
            spellId = 0,
            duration = 30,
            expirationTime = GetTime() + 24,
            test = true,
        }, auraType, slot, false
    end

    -- A passenger's afflictions live on the vehicle token, not on their own.
    unit = self.GetDisplayUnit and self:GetDisplayUnit(unit) or unit

    local bestAura, bestType, bestSlot, bestPriority, secret = nil, nil, nil, 999, false
    for index = 1, 40 do
        local aura = self:GetAuraByIndex(unit, index)
        if not aura then break end
        self:RememberAura(aura)
        if not self:IsAuraIgnored(aura) then
            local dispelName = aura.dispelName
            local accessible = self:CanAccess(dispelName)
            if accessible and dispelName and self.db.enabledTypes[dispelName] ~= false then
                local slot = self.typeToSlot[dispelName]
                -- Grouped types are deliberately invisible to the per-unit
                -- cell, but the readable sound fallback must still find them:
                -- without this a grouped affliction was silent whenever the
                -- native registration did not cover its spell.
                local manual = not slot
                    and (includeGrouped or not self:IsTypeGrouped(dispelName))
                    and self.manualTypeSpell and self.manualTypeSpell[dispelName]
                local priority = self:GetTypePriority(dispelName)
                if (slot or manual) and priority < bestPriority then
                    bestAura, bestType, bestSlot, bestPriority, secret = aura, dispelName, slot, priority, false
                end
            elseif accessible and not dispelName then
                local spellID = aura.spellId
                local knownType = self:CanAccess(spellID) and self.GetKnownDispelType
                    and self:GetKnownDispelType(spellID) or nil
                -- RAID_PLAYER_DISPELLABLE auras with an accessible nil
                -- dispel name are Bleeds. Prefer the seasonal ID map when it
                -- knows the spell, then keep a generic Bleed fallback so new
                -- encounter IDs are not silently missed.
                if not knownType and self.typeToSlot and self.typeToSlot.Bleed
                    and self.db.enabledTypes.Bleed ~= false then
                    knownType = "Bleed"
                end
                local knownSlot = knownType and self.typeToSlot[knownType]
                local priority = knownType and self:GetTypePriority(knownType) or 999
                if knownSlot and self.db.enabledTypes[knownType] ~= false and priority < bestPriority then
                    bestAura, bestType, bestSlot, bestPriority, secret = aura, knownType, knownSlot, priority, false
                end
            elseif not accessible and self.clickSpells[1] and 998 < bestPriority then
                local primaryTypes = self.clickSpells[1].activeTypes or self.clickSpells[1].types
                bestAura, bestType, bestSlot, bestPriority, secret = aura, primaryTypes[1], 1, 998, true
            end
        end
    end

    local hostile = UnitCanAttack("player", unit)
    if self:CanAccess(hostile) and hostile == true and self.typeToSlot.Charm and self.db.enabledTypes.Charm ~= false then
        if not bestAura then
            bestAura = { name = self.L.STATUS_CHARMED, dispelName = "Charm", applications = 0 }
            bestType, bestSlot = "Charm", self.typeToSlot.Charm
        end
        return bestAura, bestType, bestSlot, secret, true
    end
    return bestAura, bestType, bestSlot, secret, false
end

function NS:ApplySpellCooldown(cooldown, def, durationCache)
    if not cooldown then return nil end
    local function clearCooldown()
        if cooldown.Clear then pcall(cooldown.Clear, cooldown) end
    end
    if not self.db.showCooldown or not def or not C_Spell or not C_Spell.GetSpellCooldownDuration
        or not cooldown.SetCooldownFromDurationObject then
        clearCooldown()
        return false
    end

    -- Retail 12.1 exposes duration objects specifically designed for Cooldown
    -- frames. GetSpellChargeDuration returns only an active recharge and must
    -- be queried even when the regular duration's IsZero result is secret.
    local function inspectDuration(duration)
        if not duration then return nil end
        if duration.IsZero then
            local checked, zero = pcall(duration.IsZero, duration)
            -- IsZero returns a SECRET boolean in protected combat. Negating a
            -- secret raises, and this runs on every cooldown refresh: without
            -- the guard it floods the error log until WoW disables the addon.
            -- Unreadable means unknown, so fall through and let the caller
            -- apply the duration object without claiming to know its state.
            if checked and self:CanAccess(zero) then return not zero end
        end
        return nil
    end

    -- SpellChargeInfo.isActive and SpellCooldownInfo.isActive are documented
    -- NeverSecret: they stay readable exactly where IsZero does not. Asking
    -- them first replaces the guessing that cost 1.5.11 and 1.5.12, where an
    -- unreadable IsZero had to be interpreted as "maybe running".
    local function readActivity(getter, spellID)
        if not getter then return nil end
        local ok, info = pcall(getter, spellID)
        if not ok or info == nil then return nil end
        local readable, active = pcall(function() return info.isActive end)
        if not readable or type(active) ~= "boolean" then return nil end
        return active
    end

    local function readDurationEntry()
        local cooldownOK, cooldownDuration = pcall(C_Spell.GetSpellCooldownDuration, def.id, true)
        if not cooldownOK then cooldownDuration = nil end
        local cooldownActive = inspectDuration(cooldownDuration)

        local chargeDuration, chargeActive
        if C_Spell.GetSpellChargeDuration then
            local chargeOK, value = pcall(C_Spell.GetSpellChargeDuration, def.id)
            if chargeOK then
                chargeDuration = value
                chargeActive = inspectDuration(chargeDuration)
            end
        end

        -- An unreadable charge duration is still the most specific object:
        -- the API documents it as the spell's active recharge time. A
        -- readable zero is the only result that can safely reject it.
        -- But a spell with no charges at all always yields an empty object,
        -- and in restricted combat its IsZero is secret, so "not readably
        -- zero" used to promote it over the real cooldown. clearIfZero then
        -- wiped the frame: the number disappeared while the affliction sweep,
        -- drawn elsewhere, stayed. Known-chargeless spells never qualify.
        -- The readable flags decide first, and they settle the case the older
        -- logic could not: a spell whose charges are all banked while a school
        -- lockout runs its normal cooldown. The empty charge object used to win
        -- there and clearIfZero wiped the number off an unavailable spell.
        local chargeRunning = readActivity(C_Spell.GetSpellCharges, def.id)
        local cooldownRunning = readActivity(C_Spell.GetSpellCooldown, def.id)
        if chargeDuration and def.hasCharges ~= false and chargeRunning == true then
            return { duration = chargeDuration, active = true, source = "charge" }
        end
        if cooldownDuration and cooldownRunning == true then
            return { duration = cooldownDuration, active = true, source = "cooldown" }
        end
        if chargeRunning == false and cooldownRunning == false then
            -- Both readably idle: the spell is available. Report that rather
            -- than "no entry", because the stale-slot cleanup in
            -- RefreshDispelCooldowns keys on a readable `active == false` --
            -- returning nothing here would strand a click slot on the cell
            -- until combat ended. The duration object is still handed over so
            -- clearIfZero empties the frame.
            if cooldownDuration then
                return { duration = cooldownDuration, active = false, source = "cooldown" }
            end
            return false
        end

        -- No readable flag on this client: fall back to the IsZero reading.
        if chargeDuration and def.hasCharges ~= false and chargeActive ~= false then
            return { duration = chargeDuration, active = chargeActive, source = "charge" }
        elseif cooldownDuration then
            return { duration = cooldownDuration, active = cooldownActive, source = "cooldown" }
        end
        return false
    end

    local entry
    if durationCache then
        local cached = durationCache[def.id]
        if cached == nil then
            cached = readDurationEntry()
            durationCache[def.id] = cached
        end
        if cached ~= false then entry = cached end
    else
        local value = readDurationEntry()
        if value ~= false then entry = value end
    end
    if entry and entry.duration then
        local applied, failure = pcall(cooldown.SetCooldownFromDurationObject, cooldown, entry.duration, true)
        self.cooldownDiagnostics = {
            spellID = def.id,
            source = entry.source,
            active = entry.active,
            applied = applied,
            error = applied and nil or tostring(failure),
        }
        if applied then return entry.active == nil and true or entry.active end
    end
    clearCooldown()
    self.cooldownDiagnostics = { spellID = def.id, active = false, applied = false, error = "no duration" }
    return nil
end

function NS:SetCooldown(button, def, durationCache)
    -- On the protected path Lua cannot know the aura type. Never substitute a
    -- primary spell: that drew a plausible but wrong number on healthy cells
    -- and on afflictions mapped to another click. Only a readable aura or the
    -- spell actually used by a secure click may select this cooldown.
    return self:ApplySpellCooldown(button.cooldown, def, durationCache)
end

function NS:ApplyAuraDurationCooldown(cooldown, unit, aura)
    if not cooldown or not aura then
        if cooldown then cooldown:Clear() end
        return
    end

    if aura.test then
        local duration, expirationTime = aura.duration, aura.expirationTime
        if self:CanAccess(duration) and self:CanAccess(expirationTime)
            and duration and expirationTime and duration > 0 then
            local ok = pcall(cooldown.SetCooldown, cooldown, expirationTime - duration, duration, 1)
            if ok then return end
        end
    else
        local auraInstanceID = aura.auraInstanceID
        if self:CanAccess(auraInstanceID) and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration
            and cooldown.SetCooldownFromDurationObject then
            local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
            if ok and duration then
                local applied = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
                if applied then return end
            end
        end
    end
    cooldown:Clear()
end

function NS:RefreshDispelCooldowns()
    if not self.buttons then return end
    local durationCache = {}
    for _, button in ipairs(self.buttons) do
        if button.unit then
            local slot = button.currentSlot or button.cooldownSlot
            local def = slot and self.clickSpells and self.clickSpells[slot]
            local active = self:SetCooldown(button, def, durationCache)
            local clickAge = button.cooldownClickTime and (GetTime() - button.cooldownClickTime)
            if not button.currentSlot and button.cooldownSlot and active == false
                and (not clickAge or clickAge >= 0.75) then
                button.cooldownSlot = nil
                button.cooldownClickTime = nil
            end
        end
    end
end

function NS:SetButtonState(button, aura, auraType, slot, secret, charmed)
    local unit = self.GetDisplayUnit and self:GetDisplayUnit(button.unit) or button.unit
    button.currentAura = aura
    button.currentAuraType = auraType
    button.currentSlot = slot
    button.secretAura = secret
    self:ApplyAuraDurationCooldown(button.auraDurationCooldown, unit, aura)

    local charmShown = charmed and true or false
    if button.lastCharmShown ~= charmShown then
        button.lastCharmShown = charmShown
        button.charm:SetShown(charmShown)
    end

    button.center:SetText("")
    local hintShown = self.db.showClickHints and aura and slot and true or false -- no slot, no letter
    local hintText = hintShown and clickHint(slot) or ""
    if button.lastClickHintShown ~= hintShown or button.lastClickHintText ~= hintText then
        button.lastClickHintShown = hintShown
        button.lastClickHintText = hintText
        button.clickHint:SetText(hintText)
        button.clickHint:SetShown(hintShown)
        if button.clickHintPlate then button.clickHintPlate:SetShown(hintShown) end
    end

    local connected = UnitIsConnected(unit)
    local dead = UnitIsDeadOrGhost(unit)
    local unavailable = (self:CanAccess(connected) and connected == false)
        or (self:CanAccess(dead) and dead == true)

    local hiddenBase = self.db.afflictedOnly and true or false

    -- Afflicted-only is a visual mode. Hide Cleansive's own hover texture and
    -- tooltip over the transparent base, but keep the secure click layer: the
    -- protected AuraSlot passes clicks to it and Lua cannot read AuraSlot
    -- visibility to toggle that hitbox safely. See README.md for the tradeoff.
    local emptyCell = hiddenBase and not aura
    if button.lastEmptyCell ~= emptyCell then
        button.lastEmptyCell = emptyCell
        button.baseHidden = emptyCell
        if button.clickLayer and button.clickLayer.hoverTexture then
            button.clickLayer.hoverTexture:SetAlpha(emptyCell and 0 or 1)
        end
    end

    if unavailable then
        button.cooldownSlot = nil
        button.cooldownClickTime = nil
        button.state = "absent"
        local visualKey = "absent:" .. (hiddenBase and "hidden" or "shown")
        if button.lastVisualKey ~= visualKey then
            button.lastVisualKey = visualKey
            button.background:SetColorTexture(0.24, 0.24, 0.24, hiddenBase and 0 or 0.34)
            button.typeMark:SetColorTexture(0, 0, 0, 0)
            setBorderColor(button, 0.15, 0.15, 0.15, hiddenBase and 0 or 0.8)
            self:SetCooldown(button, nil)
        end
    elseif self:IsBlacklisted(unit) then
        button.cooldownSlot = nil
        button.cooldownClickTime = nil
        button.state = "blacklist"
        local visualKey = "blacklist:" .. (hiddenBase and "hidden" or "shown")
        if button.lastVisualKey ~= visualKey then
            button.lastVisualKey = visualKey
            button.background:SetColorTexture(0.01, 0.01, 0.01, hiddenBase and 0 or 0.95)
            button.typeMark:SetColorTexture(0, 0, 0, 0)
            setBorderColor(button, 0.28, 0.28, 0.28, hiddenBase and 0 or 1)
            self:SetCooldown(button, nil)
        end
    elseif aura and not slot then
        button.cooldownSlot = nil
        button.cooldownClickTime = nil
        -- Detected, but the only ability that clears it cannot be aimed at a
        -- unit. Paint it neutrally: no click colour, no letter, no cooldown.
        button.state = "detected"
        local typeColor = self.TYPE_COLORS[auraType] or { 1, 1, 1 }
        local visualKey = "detected:" .. tostring(auraType) .. ":" .. (hiddenBase and "h" or "s")
        if button.lastVisualKey ~= visualKey then
            button.lastVisualKey = visualKey
            button.background:SetColorTexture(DETECT_COLOR[1], DETECT_COLOR[2], DETECT_COLOR[3], 0.72)
            button.typeMark:SetColorTexture(typeColor[1], typeColor[2], typeColor[3], 1)
            setBorderColor(button, typeColor[1], typeColor[2], typeColor[3], 1)
            self:SetCooldown(button, nil)
        end
    elseif aura and slot then
        local def = self.clickSpells[slot]
        local inRange = self:IsSpellInRange(def, unit)
        local color = CLICK_COLORS[slot] or CLICK_COLORS[1]
        button.state = inRange and "afflicted" or "far_afflicted"
        local typeColor = self.TYPE_COLORS[auraType] or { 1, 1, 1 }
        local visualKey = table.concat({ "afflicted", tostring(slot), tostring(auraType), inRange and "1" or "0" }, ":")
        if button.lastVisualKey ~= visualKey then
            button.lastVisualKey = visualKey
            button.background:SetColorTexture(color[1], color[2], color[3], inRange and 0.96 or 0.30)
            button.typeMark:SetColorTexture(typeColor[1], typeColor[2], typeColor[3], 1)
            setBorderColor(button, typeColor[1], typeColor[2], typeColor[3], 1)
        end
        self:SetCooldown(button, def)

        if self.db.showStacks and aura then
            local count = aura.applications
            if self:CanAccess(count) and count and count > 1 then
                button.center:SetText(count)
            else
                local auraInstanceID = aura.auraInstanceID
                if self:CanAccess(auraInstanceID) and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                    button.center:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 1))
                end
            end
        end
    else
        -- UnitInRange's values are secret in Retail 12.1. The engine-owned
        -- aura overlay remains authoritative, so the resting cell does not
        -- branch on those protected booleans.
        button.state = "normal"
        -- Keep the last secure click mapping long enough for the delayed
        -- cooldown probes to observe the real spell cooldown after the aura
        -- disappears. RefreshDispelCooldowns clears it once a readable zero
        -- has survived the 750 ms race window.
        local visualKey = "normal:" .. tostring(self.db.inactiveAlpha) .. ":" .. (hiddenBase and "hidden" or "shown")
        if button.lastVisualKey ~= visualKey then
            button.lastVisualKey = visualKey
            button.background:SetColorTexture(0.05, 0.07, 0.09, hiddenBase and 0 or self.db.inactiveAlpha)
            button.typeMark:SetColorTexture(0, 0, 0, 0)
            setBorderColor(button, 1, 1, 1, hiddenBase and 0 or 0.10)
            self:SetCooldown(button, nil)
        end
    end

    -- A readable manual-only affliction has an aura but no secure click slot.
    -- It is still a visible afflicted cell and must keep its unit name.
    local showNames = self:CellShowsNames() and (not self.db.afflictedOnly or aura ~= nil) and true or false
    if button.lastShowNames ~= showNames then
        button.lastShowNames = showNames
        if showNames then
            button.center:Hide()
            button.nameText:Show()
        else
            button.center:Show()
            button.nameText:Hide()
        end
    end
end

function usesAuraEngine(self, button)
    return self.engineAuraMode and not self.testMode and button
        and button.engineAuraReady and button.auraContainer
end

function NS:RefreshUnit(unit)
    if not self.unitToButton then return end
    local button = self.unitToButton[unit]
    if not button then
        -- A vehicle token fires its own UNIT_AURA. Route it back to the cell
        -- that owns the passenger.
        local owner = self.vehicleOwner and self.vehicleOwner[unit]
        button = owner and self.unitToButton[owner]
        if not button then return end
        unit = owner
    end
    local aura, auraType, slot, secret, charmed
    local engineManaged = usesAuraEngine(self, button)
    if engineManaged then
        local hostile = UnitCanAttack("player", unit)
        charmed = self:CanAccess(hostile) and hostile == true and self.typeToSlot.Charm
            and self.db.enabledTypes.Charm ~= false
        if charmed then
            aura = { name = self.L.STATUS_CHARMED, dispelName = "Charm", applications = 0 }
            auraType, slot = "Charm", self.typeToSlot.Charm
        end
    else
        aura, auraType, slot, secret, charmed = self:GetCurableAura(unit)
    end
    self:SetButtonState(button, aura, auraType, slot, secret, charmed)
    if engineManaged then
        if not self.db.sound then
            button.alertAuraKey = nil
            self:RecordReadableAuraHistory(unit)
        elseif charmed then
            self:UpdateButtonAfflictionAlert(button, aura, slot, false)
        else
            self:UpdateReadableAfflictionAlert(button, unit, false)
        end
    else
        self:UpdateButtonAfflictionAlert(button, aura, slot, false)
    end
    -- The container handles UNIT_AURA itself, incrementally. Forcing a full
    -- rebuild on every event throws that work away. Only re-sync when the
    -- unit it is bound to has actually changed, typically on a vehicle swap.
    local container = button.auraContainer
    if container then
        local wanted = self.GetDisplayUnit and self:GetDisplayUnit(button.unit) or button.unit
        if button.auraContainerUnit ~= wanted then
            if pcall(container.SetUnit, container, wanted) then
                -- SetUnit already calls UpdateAllAuras when the token changes.
                button.auraContainerUnit = wanted
            end
        end
    end
    self:RequestManualIndicatorUpdate(unit)
end

function NS:RefreshAll(force)
    if not self.enabled or not self.buttons or not self.roster then return end
    for _, descriptor in ipairs(self.roster) do
        local button = self.unitToButton[descriptor.unit]
        if button then
            local aura, auraType, slot, secret, charmed
            local engineManaged = usesAuraEngine(self, button)
            if engineManaged then
                local hostile = UnitCanAttack("player", descriptor.unit)
                charmed = self:CanAccess(hostile) and hostile == true and self.typeToSlot.Charm
                    and self.db.enabledTypes.Charm ~= false
                if charmed then
                    aura = { name = self.L.STATUS_CHARMED, dispelName = "Charm", applications = 0 }
                    auraType, slot = "Charm", self.typeToSlot.Charm
                end
            else
                aura, auraType, slot, secret, charmed = self:GetCurableAura(descriptor.unit)
            end
            self:SetButtonState(button, aura, auraType, slot, secret, charmed)
            if engineManaged then
                if not self.db.sound then
                    button.alertAuraKey = nil
                elseif charmed then
                    self:UpdateButtonAfflictionAlert(button, aura, slot, force)
                else
                    self:UpdateReadableAfflictionAlert(button, descriptor.unit, force)
                end
            else
                self:UpdateButtonAfflictionAlert(button, aura, slot, force)
            end
        end
    end
    self:UpdateManualIndicator()
    self:UpdatePendingIndicator()
    self:UpdateNoCureNotice()
end

function NS:ShowButtonTooltip(button)
    if not self.db.showTooltips or not button.unit then return end
    if button.baseHidden then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local descriptor = button.descriptor
    GameTooltip:AddLine(descriptor and descriptor.displayName or button.unit, 1, 1, 1)
    if button.state == "blacklist" then
        GameTooltip:AddLine(self.L.STATUS_BLACKLIST, 0.6, 0.6, 0.6)
    elseif button.state == "absent" then
        GameTooltip:AddLine(self.L.STATUS_UNAVAILABLE, 0.6, 0.6, 0.6)
    elseif button.currentAura and not button.currentSlot then
        local auraType = button.currentAuraType
        local color = self.TYPE_COLORS[auraType] or { 1, 1, 1 }
        local name = button.currentAura.name
        if button.secretAura or not self:CanAccess(name) then name = self.L.SECRET_AURA end
        GameTooltip:AddLine(name or self.L.STATUS_AFFLICTED, color[1], color[2], color[3])
        local manual = self.manualTypeSpell and self.manualTypeSpell[auraType]
        if manual and manual.name then
            GameTooltip:AddLine(string.format(self.L.MANUAL_ONLY, manual.name), 0.75, 0.90, 1)
        end
    elseif button.currentAura then
        local name = button.currentAura.name
        if button.secretAura or not self:CanAccess(name) then name = self.L.SECRET_AURA end
        local color = self.TYPE_COLORS[button.currentAuraType] or { 1, 1, 1 }
        GameTooltip:AddLine(name or self.L.STATUS_AFFLICTED, color[1], color[2], color[3])
        if button.state == "far_afflicted" then
            GameTooltip:AddLine(self.L.STATUS_FAR, 0.75, 0.42, 0.9)
        end
    elseif usesAuraEngine(self, button) then
        GameTooltip:AddLine(self.L.STATUS_SECURE, 0.55, 0.72, 0.82)
    else
        GameTooltip:AddLine(self.L.STATUS_NORMAL, 0.35, 0.8, 0.45)
    end
    for slot, def in ipairs(self.clickSpells or {}) do
        local binding = slot == 1 and self.L.LEFT or (slot == 2 and self.L.RIGHT or self.L.CTRL_LEFT)
        GameTooltip:AddLine(binding .. " : " .. def.name, 0.75, 0.90, 1)
    end

    -- On the protected path Lua never learns which aura is on the unit, so the
    -- tooltip cannot name the ability for *this* affliction. Listing the types
    -- that have no click at all is the honest substitute: it tells the player
    -- what they must press themselves, without pretending to know more.
    if not (button.currentAura and not button.currentSlot) then
        local shown = {}
        for _, auraType in ipairs(self.DISPEL_TYPES or {}) do
            local clickable = self.typeToSlot and self.typeToSlot[auraType]
            local manual = not clickable and self.manualTypeSpell and self.manualTypeSpell[auraType]
            if manual and manual.name and self.db.enabledTypes[auraType] ~= false and not shown[manual.id] then
                shown[manual.id] = true
                GameTooltip:AddLine(string.format(self.L.MANUAL_AVAILABLE,
                    self:GetTypeLabel(auraType), manual.name), 0.75, 0.90, 1)
            end
        end
    end
    GameTooltip:AddLine(self.L.TARGET, 0.65, 0.65, 0.65)
    GameTooltip:AddLine(self.L.FOCUS_BIND, 0.65, 0.65, 0.65)
    GameTooltip:AddLine(self.L.THUMB_BIND, 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

-- Attribute drivers are evaluated by the secure engine, so the click target
-- follows a passenger into and out of a vehicle even during combat, which a
-- plain SetAttribute could not.
function NS:ApplyVehicleDriver(frame, unit)
    if not frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingRoster")
        return
    end
    self.vehicleOwner = self.vehicleOwner or {}
    if frame.vehicleToken then
        self.vehicleOwner[frame.vehicleToken] = nil
        frame.vehicleToken = nil
    end
    if UnregisterAttributeDriver then
        pcall(UnregisterAttributeDriver, frame, "unit")
    end
    if not unit then return end

    local vehicle = self:GetVehicleUnit(unit)
    if not vehicle or not RegisterAttributeDriver then
        frame:SetAttribute("unit", unit)
        return
    end
    self.vehicleOwner[vehicle] = unit
    frame.vehicleToken = vehicle
    local ok = pcall(RegisterAttributeDriver, frame, "unit",
        string.format("[@%s,vehicleui] %s; %s", unit, vehicle, unit))
    if not ok then frame:SetAttribute("unit", unit) end
end

-- Readable-only by design. In restricted combat Lua cannot see the aura, so
-- the count under-reports rather than guessing; the native sound alert still
-- covers those cases and the tooltip says so.
-- With `wanted`, answers whether the unit carries that one type. Without it,
-- returns the highest-priority grouped type present -- the player's configured
-- order, not the order WoW happens to return auras in. Scanning aura-first
-- meant the indicator took its colour from whichever affliction was listed
-- first, so the same two afflictions could paint either colour.
-- Without a unit, forgets everything; with one, marks just that unit for a
-- rescan. Before 1.5.9 every UNIT_AURA re-read the whole roster: up to 82
-- units times 40 auras, ten times a second in the worst case, to answer a
-- question only one unit had changed the answer to.
function NS:InvalidateGroupedCache(unit)
    self.groupedCache = self.groupedCache or {}
    self.groupedDirty = self.groupedDirty or {}
    if unit then
        self.groupedDirty[unit] = true
    else
        wipe(self.groupedCache)
        wipe(self.groupedDirty)
    end
end

-- The unit's highest-priority grouped type that the player can actually act
-- on, or false for "scanned, nothing there" -- which is a cacheable answer,
-- unlike nil.
function NS:ResolveGroupedType(unit, grouped)
    local present = self.groupedPresent or {}
    self.groupedPresent = present
    self:ScanGroupedTypes(unit, present)
    local isPlayer = self:IsPlayerUnit(unit)
    for _, auraType in ipairs(grouped) do
        local spell = self.manualTypeSpell and self.manualTypeSpell[auraType]
        if present[auraType] and (isPlayer or not (spell and spell.selfOnly)) then
            return auraType
        end
    end
    return false
end

-- Fills `into[type] = true` for every grouped type carried by the unit, in a
-- single pass over its auras whatever the number of grouped types. Callers
-- apply priority and scope themselves: the aura order WoW returns says
-- nothing about which type the player wants to see first.
-- The type colour lives on the outline and the glyphs, never on the fill: a
-- filled block is what a cell looks like, and the badge is not one.
function NS:PaintManualIndicator(frame, color)
    frame.background:SetColorTexture(0.02, 0.03, 0.04, 0.88)
    if frame.border then setBorderColor(frame, color[1], color[2], color[3], 1) end
    frame.mark:Show()
    frame.mark:SetTextColor(color[1], color[2], color[3], 1)
    frame.count:SetTextColor(1, 1, 1, 1)
end

function NS:PaintInactiveManualIndicator(frame)
    frame.background:SetColorTexture(0.05, 0.07, 0.09, self.db.inactiveAlpha)
    if frame.border then setBorderColor(frame, 1, 1, 1, 0.10) end
    frame.mark:SetTextColor(1, 1, 1, 0)
    frame.mark:Hide()
    frame.count:SetTextColor(1, 1, 1, 0)
    frame.count:SetText("")
end

function NS:ScanGroupedTypes(unit, into)
    wipe(into)
    if not self.groupedTypes or #self.groupedTypes == 0 then return into end
    for index = 1, 40 do
        local aura = self:GetAuraByIndex(unit, index)
        if not aura then break end
        local dispelName = aura.dispelName
        if self:CanAccess(dispelName) and dispelName and not self:IsAuraIgnored(aura) then
            for _, auraType in ipairs(self.groupedTypes) do
                if dispelName == auraType then into[auraType] = true end
            end
        end
    end
    return into
end


-- UNIT_AURA fires constantly. Recomputing the indicator on each one would
-- rescan the whole roster, so coalesce them into a single pass.
function NS:RequestManualIndicatorUpdate(unit)
    if unit then self:InvalidateGroupedCache(unit) end
    if not self.manualIndicator or self.manualIndicatorScheduled then return end
    if not (C_Timer and C_Timer.After) then return self:UpdateManualIndicator() end
    self.manualIndicatorScheduled = true
    C_Timer.After(0.1, function()
        self.manualIndicatorScheduled = false
        self:UpdateManualIndicator()
    end)
end

function NS:UpdateManualIndicator()
    local frame = self.manualIndicator
    if not frame then return end
    self.groupedTypes = self:GetManualOnlyTypes()
    local grouped = {}
    for _, auraType in ipairs(self.groupedTypes) do
        if self:IsTypeGrouped(auraType) then grouped[#grouped + 1] = auraType end
    end
    self.groupedTypes = grouped

    if not self.enabled or #grouped == 0 or self.gridManuallyHidden then
        frame:Hide()
        return
    end

    -- Test mode exists so the player can place and size everything without an
    -- affliction. The indicator was the one piece it never showed.
    if self.testMode then
        frame.activeCount, frame.activeType = 2, grouped[1]
        self:LayoutManualIndicator()
        local color = self.TYPE_COLORS[grouped[1]] or { 1, 1, 1 }
        self:PaintManualIndicator(frame, color)
        frame.count:SetText(2)
        frame:Show()
        return
    end

    -- The grouped set and the configured order both change what a cached
    -- answer means, so a move there forgets everything.
    local signature = table.concat(grouped, ",")
    if signature ~= self.groupedSignature then
        self.groupedSignature = signature
        self:InvalidateGroupedCache()
    end

    local rank = {}
    for position, auraType in ipairs(grouped) do rank[auraType] = position end

    self.groupedCache = self.groupedCache or {}
    self.groupedDirty = self.groupedDirty or {}
    local cache, dirty = self.groupedCache, self.groupedDirty
    local counted, count, bestRank, firstType = {}, 0, nil, nil
    for _, descriptor in ipairs(self.roster or {}) do
        local token = descriptor.unit
        local unit = self:GetDisplayUnit(token)
        if unit then
            -- Never `or` a raw UnitGUID and never use it as a table key: it
            -- is unreadable under identity restrictions, and this runs on the
            -- UNIT_AURA path, in combat, once per roster unit.
            local guid = self:SafeUnitGUID(unit)
            local identity = guid or token
            local entry = cache[token]
            -- A token gets recycled onto somebody else the moment the group
            -- changes, so an entry is only trusted while its GUID holds. With
            -- no readable GUID there is nothing to hold, so nothing is trusted
            -- and the unit is rescanned every pass.
            if not guid or not entry or entry.guid ~= guid or dirty[token] then
                entry = entry or {}
                entry.guid = guid
                entry.type = self:ResolveGroupedType(unit, grouped)
                cache[token] = entry
            end
            if entry.type then
                -- One unit hit by two grouped types is still one unit.
                if not counted[identity] then
                    counted[identity] = true
                    count = count + 1
                end
                -- Priority is global: the colour is the most urgent type in
                -- the group, not the best type of whichever unit came first.
                local position = rank[entry.type]
                if position and (not bestRank or position < bestRank) then
                    bestRank, firstType = position, entry.type
                end
            end
        end
    end
    wipe(dirty)

    frame.activeCount, frame.activeType = count, firstType
    self:LayoutManualIndicator()
    if count > 0 then
        local color = self.TYPE_COLORS[firstType] or { 1, 1, 1 }
        self:PaintManualIndicator(frame, color)
        frame.count:SetText(count)
        frame:Show()
    elseif self.db.afflictedOnly then
        frame:Hide()
    else
        self:PaintInactiveManualIndicator(frame)
        frame:Show()
    end
end

function NS:ShowManualIndicatorTooltip(frame)
    if not self.db.showTooltips then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    -- The badge looks like part of the grid, so it says outright that it is
    -- not one before it says anything else.
    GameTooltip:AddLine(self.L.MANUAL_BADGE_TITLE, 1, 0.82, 0.30)
    for _, auraType in ipairs(self.groupedTypes or {}) do
        local manual = self.manualTypeSpell and self.manualTypeSpell[auraType]
        local color = self.TYPE_COLORS[auraType] or { 1, 1, 1 }
        GameTooltip:AddLine(self:GetTypeLabel(auraType), color[1], color[2], color[3])
        if manual and manual.name then
            GameTooltip:AddLine(string.format(self.L.MANUAL_ONLY, manual.name), 0.75, 0.90, 1)
        end
    end
    if (frame.activeCount or 0) > 0 then
        GameTooltip:AddLine(string.format(self.L.MANUAL_COUNT, frame.activeCount), 1, 1, 1)
    else
        GameTooltip:AddLine(self.L.STATUS_NORMAL, 0.35, 0.8, 0.45)
    end
    GameTooltip:AddLine(self.L.MANUAL_READABLE_ONLY, 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

-- Anchored opposite the growth direction: sitting above the grid would put it
-- straight on top of the first cell in the RIGHT_UP and LEFT_UP layouts.
function NS:LayoutManualIndicator()
    local frame = self.manualIndicator
    if not frame or not self.cooldownBody then return end
    local size = self.db.frameSize
    frame:SetSize(size, size)
    -- The badge follows the cell size, so its labels follow it too.
    local font = self.GetUXFont and self:GetUXFont()
    if font then
        local labelSize = self:CellFontSize("stack", size)
        if frame.mark then frame.mark:SetFont(font, labelSize, "") end
        if frame.count then frame.count:SetFont(font, labelSize, "") end
    end
    frame:ClearAllPoints()
    local grow = self.db.grow or "RIGHT_DOWN"
    local up = grow == "RIGHT_UP" or grow == "LEFT_UP"
    local left = grow == "RIGHT_DOWN" or grow == "RIGHT_UP"
    local corner = (up and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT")
    local anchor = (up and "BOTTOM" or "TOP") .. (left and "LEFT" or "RIGHT")
    frame:SetPoint(corner, self.cooldownBody, anchor, 0, up and -4 or 4)
end

-- The plates share the manual badge's corner. The previous version asserted the
-- two could never be needed at once and drew both at the same point; a
-- character with no cleanse can still resize the grid mid-fight, which defers a
-- protected change and lights the pending plate on top of the other one.
-- Whatever is actually visible is stacked instead, in a fixed order.
function NS:LayoutStatusNotices()
    if not self.cooldownBody then return end
    local size = self.db.frameSize
    local grow = self.db.grow or "RIGHT_DOWN"
    local up = grow == "RIGHT_UP" or grow == "LEFT_UP"
    local left = grow == "RIGHT_DOWN" or grow == "RIGHT_UP"
    local corner = (up and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT")
    local anchorPoint = (up and "BOTTOM" or "TOP") .. (left and "LEFT" or "RIGHT")
    local font = self.GetUXFont and self:GetUXFont()
    local labelSize = self:CellFontSize("stack", size)
    local height = math.max(16, math.floor(size * 0.7))
    local manualShown = self.manualIndicator and self.manualIndicator:IsShown()

    local offset = manualShown and (size + 4) or 0

    for _, entry in ipairs({
        { frame = self.pendingIndicator, text = self.L.PENDING_BADGE },
        { frame = self.noCureNotice, text = self.L.NO_CURE_BADGE },
    }) do
        local frame = entry.frame
        if frame then
            if font then frame.label:SetFont(font, labelSize, "") end
            frame.label:SetText(entry.text)
            local width = math.max(24, math.ceil(frame.label:GetStringWidth()) + 10)
            frame:SetSize(width, height)
            frame:ClearAllPoints()
            frame:SetPoint(corner, self.cooldownBody, anchorPoint,
                left and offset or -offset, up and -4 or 4)
            -- Measured here rather than read back: the width was just set, and
            -- a hidden plate must not reserve a place in the row.
            if frame:IsShown() then offset = offset + width + 4 end
        end
    end
end

-- Every deferral goes through here so the plate can never disagree with the
-- flags: setting one directly was how the previous silent state happened.
-- Not every deferral is worth announcing. SPELLS_CHANGED fires on a shapeshift
-- or a temporary ability, UNIT_PET and GROUP_ROSTER_UPDATE fire on their own:
-- those are the game talking to itself, and the player can neither act on them
-- nor understand them. Announcing them lit the plate on nearly every pull and
-- turned it into weather. The work is still deferred and still replayed; only
-- the announcement is withheld. The plate exists for a change the player asked
-- for and cannot see land.
function NS:MarkPending(flag, silent)
    local announced = self.pendingAnnounced or {}
    self.pendingAnnounced = announced
    -- A fresh flag starts unannounced; one already raised keeps its status, so
    -- a background event cannot silence a change the player is waiting on.
    if not self[flag] then announced[flag] = false end
    if not (silent or self.pendingNoticeSuppressed) then announced[flag] = true end
    self[flag] = true
    -- Diagnosing the plate meant auditing eleven flags against every event that
    -- can raise one. Recording the cause here makes that a one-line answer.
    if self.NotePendingFlag then self:NotePendingFlag(flag, self.currentEvent) end
    self:UpdatePendingIndicator()
end

local PENDING_FLAGS = {
    "pendingLayout", "pendingProfileSwitch", "pendingPositionReset",
    "pendingVisibilityDriver", "pendingAnchorAppearance", "pendingAuraStyle",
    "pendingAuraFilters", "pendingSpells", "pendingRoster",
    "pendingAuraEngineRebuild", "pendingPriorityBinding",
    "pendingEnabled", "pendingGridVisibility",
}
-- The options footer counts the same flags as the plate next to the grid. Two
-- different answers to "is something waiting?" would be worse than none.
NS.PENDING_FLAGS = PENDING_FLAGS

function NS:UpdatePendingIndicator()
    local frame = self.pendingIndicator
    if not frame then return end
    local waiting = false
    local announced = self.pendingAnnounced or {}
    for _, flag in ipairs(PENDING_FLAGS) do
        if self[flag] and announced[flag] then waiting = true break end
    end
    -- Out of combat a pending flag is about to be flushed, not waiting on
    -- anything the player can see. Showing it there would be a plate that
    -- blinks for one frame on every option change.
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not (waiting and inCombat and self.enabled and not self.gridManuallyHidden) then
        frame:Hide()
        self:LayoutStatusNotices()
        return
    end
    frame:Show()
    self:LayoutStatusNotices()
end

function NS:UpdateNoCureNotice()
    local frame = self.noCureNotice
    if not frame then return end
    -- Only once the client has actually answered. Before that an empty
    -- spellbook is ignorance, not a fact about the character.
    local resolved = self.spellbookResolved
    local none = resolved and #(self.clickSpells or {}) == 0
        and #(self.engineAuraTypes or {}) == 0
    if not (none and self.enabled and not self.gridManuallyHidden) then
        frame:Hide()
        self:LayoutStatusNotices()
        return
    end
    frame:Show()
    self:LayoutStatusNotices()
end

-- engineAuraTypes is decided once, when the grid is built. A specialization
-- or talent change can alter it, and reconfiguring existing slots cannot add
-- a type that was never created. Rebuild rather than leave a stale set.
-- Bring an existing container in line with the wanted set instead of replacing
-- it. A slot cannot be removed -- UnregisterAuraSlot and ClearAuraSlots are on
-- Blizzard's private mixins -- but an empty includeDispelTypes table is not nil
-- and matches no aura at all, so an unwanted slot can be made inert. The visual
-- side already handles it: StyleAuraVisual reads typeToSlot and manualTypeSpell,
-- so a type the character can no longer clear is styled invisible anyway.
-- Slots therefore accumulate to the union of types seen this session, at most
-- five, instead of 82 fresh containers per change.
function NS:ReconcileAuraSlots(button, wanted, wantedSet)
    local container = button.auraContainer
    if not container then return false end
    button.auraSlotKeys = button.auraSlotKeys or {}
    button.auraSlotVisuals = button.auraSlotVisuals or {}

    local diagnostics = self.auraContainerDiagnostics
    -- The retired types are walked first, so a single shared firstError meant
    -- the engine message could name a cleanup operation while describing a
    -- cell that had really lost an active type. Each side keeps its own.
    local function recordFailure(reason, active)
        if not diagnostics then return end
        if not diagnostics.firstError then diagnostics.firstError = tostring(reason) end
        if active then diagnostics.activeError = diagnostics.activeError or tostring(reason) end
    end

    -- Two separate outcomes. Whether the cell can use the engine depends only
    -- on the wanted types; whether the pass is worth retrying also depends on
    -- retiring the historical ones, which was recorded but never acted on.
    local retiredOK = true
    for auraType, slotKey in pairs(button.auraSlotKeys) do
        if not wantedSet[auraType] then
            if not tryCall(container.SetAuraSlotCandidateFilters, container, slotKey,
                { includeDispelTypes = {} }) then
                recordFailure("SetAuraSlotCandidateFilters failed for " .. tostring(auraType))
                if diagnostics then
                    diagnostics.retired = (diagnostics.retired or 0) + 1
                    diagnostics.retiredError = diagnostics.retiredError
                        or ("SetAuraSlotCandidateFilters failed for " .. tostring(auraType))
                end
                retiredOK = false
            end
        end
    end

    local live = 0
    for _, auraType in ipairs(wanted) do
        local slotKey = button.auraSlotKeys[auraType]
        if slotKey then
            -- Present already, possibly made inert by an earlier pass: hand its
            -- real filters back.
            if tryCall(container.SetAuraSlotCandidateFilters, container, slotKey,
                self:BuildAuraCandidateFilters(auraType)) then
                live = live + 1
            else
                recordFailure("SetAuraSlotCandidateFilters failed for " .. tostring(auraType), true)
            end
        elseif self:AddAuraSlotForType(button, auraType) then
            live = live + 1
        end
    end

    button.engineAuraReady = live == #wanted
    -- Count every slot that was actually configured. Counting only whole ready
    -- buttons reported 0/246 while 164 slots were live.
    if diagnostics then diagnostics.added = diagnostics.added + live end
    return button.engineAuraReady, button.engineAuraReady and retiredOK
end

-- The retry was allowed but never scheduled: it waited for some other spell
-- event to call RefreshAuraEngineTypes again. A single transient failure could
-- therefore leave cells on the Lua fallback for the rest of the session. One
-- live timer at a time, guarded by the generation so a set change cancels it.
function NS:ScheduleAuraEngineRetry()
    if not (C_Timer and C_Timer.After) then return end
    if self.auraEngineRetryScheduled then return end
    local generation = self.auraEngineGeneration or 0
    -- C_Timer.After cannot be cancelled, so a superseded callback stays in the
    -- queue. The token says which timer owns the guard: without it the stale
    -- one released a slot the newer timer was already holding, and a third
    -- could then be armed for the same generation.
    local token = (self.auraEngineRetryToken or 0) + 1
    self.auraEngineRetryToken = token
    self.auraEngineRetryScheduled = true
    C_Timer.After(0.5 * (self.auraEngineRetries or 1), function()
        if token ~= self.auraEngineRetryToken then return end
        self.auraEngineRetryScheduled = false
        if generation ~= (self.auraEngineGeneration or 0) then return end
        if not self.pendingAuraEngineReconcile then return end
        if InCombatLockdown and InCombatLockdown() then
            -- PLAYER_REGEN_ENABLED already replays this flag.
            self:MarkPending("pendingAuraEngineRebuild")
            return
        end
        self:RefreshAuraEngineTypes()
    end)
end

function NS:RefreshAuraEngineTypes()
    if not self.buttons or not self.gridBody then return end
    local wanted = getPotentialAuraTypes()
    local current = self.engineAuraTypes or {}
    local same = #wanted == #current
    if same then
        for index = 1, #wanted do
            if wanted[index] ~= current[index] then same = false break end
        end
    end
    -- A retry is owed when a previous pass left cells behind: the wanted set is
    -- already stored by then, so an early return would strand them until the
    -- next real change or a reload.
    if same and not self.pendingAuraEngineReconcile then return false end

    if InCombatLockdown and InCombatLockdown() then
        self:MarkPending("pendingAuraEngineRebuild")
        return false
    end
    self.pendingAuraEngineRebuild = false
    -- A new set gets its own budget. Carrying the previous one over meant a
    -- later change could inherit an exhausted counter and get no attempt.
    if not same then
        self.auraEngineRetries, self.auraEngineWarned = 0, false
        self.auraEngineGeneration = (self.auraEngineGeneration or 0) + 1
        -- Release the single-timer guard too: the pending timer belongs to the
        -- old generation and will now no-op, so holding the slot would block
        -- the new set from ever arming one.
        self.auraEngineRetryScheduled = false
    end

    self.engineAuraTypes = wanted
    local wantedSet = {}
    for _, auraType in ipairs(wanted) do wantedSet[auraType] = true end
    self.engineAuraTypeSet = wantedSet
    local fullyConfigured = true
    self.auraContainerDiagnostics = {
        expected = MAX_BUTTONS * #wanted, added = 0, readyButtons = 0, firstError = nil,
        retired = 0, retiredError = nil, activeError = nil,
    }
    for _, button in ipairs(self.buttons) do
        -- Reuse whatever is already there. Hiding a container does not destroy
        -- it -- WoW keeps every frame for the session -- so the old code left a
        -- fresh generation of 82 containers behind on every talent change.
        if button.auraContainer then
            local _, complete = self:ReconcileAuraSlots(button, wanted, wantedSet)
            if not complete then fullyConfigured = false end
        else
            button.auraSlotKeys, button.auraSlotVisuals = nil, nil
            button.engineAuraReady = false
            self:CreateAuraContainer(button)
        end
        if button.engineAuraReady then
            self.auraContainerDiagnostics.readyButtons = self.auraContainerDiagnostics.readyButtons + 1
        end
    end
    local ready = self.auraContainerDiagnostics.readyButtons
    self.engineAuraMode = #wanted > 0 and ready > 0
    -- Retry when containers exist but some are not covered: the engine is there
    -- and the failure is worth another pass. No container at all means the
    -- engine is unavailable here, and retrying on every spell event would be a
    -- loop rather than a recovery. Counting ready cells alone was not enough --
    -- a filter that fails for one slot fails it on all 82. The retry is bounded.
    local withContainer = 0
    for _, button in ipairs(self.buttons) do
        if button.auraContainer then withContainer = withContainer + 1 end
    end
    -- Losing every dispel type is a real transition, not a reason to stop
    -- retrying: the historical slots still have to be neutralized, and gating
    -- this on a non-empty set left them filtering auras forever. An empty set
    -- reports every cell ready, so this can only fire on a cleanup failure.
    local incomplete = withContainer > 0 and (ready < withContainer or not fullyConfigured)
    if incomplete then
        self.auraEngineRetries = (self.auraEngineRetries or 0) + 1
        self.pendingAuraEngineReconcile = self.auraEngineRetries <= 3
        -- One message per generation, not one per attempt: four identical lines
        -- in the chat frame is noise, and the changelog promised one.
        if self.auraContainerDiagnostics.firstError and not self.auraEngineWarned then
            self.auraEngineWarned = true
            if ready < withContainer then
                self:Print(self.L.AURA_ENGINE_FAILED, self.auraContainerDiagnostics.added,
                    self.auraContainerDiagnostics.expected,
                    self.auraContainerDiagnostics.activeError
                        or self.auraContainerDiagnostics.firstError)
            else
                -- Every wanted type is live on every cell; only the retired
                -- ones resisted. Announcing "incomplete (82/82 slots)" and a
                -- fallback nobody fell back to was a contradiction.
                self:Print(self.L.AURA_CLEANUP_FAILED, self.auraContainerDiagnostics.retired,
                    self.auraContainerDiagnostics.retiredError
                        or self.auraContainerDiagnostics.firstError)
            end
        end
        if self.pendingAuraEngineReconcile then self:ScheduleAuraEngineRetry() end
    else
        self.auraEngineRetries, self.pendingAuraEngineReconcile = 0, false
    end
    return true
end
