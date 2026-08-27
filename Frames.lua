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
        if def.class == NS.playerClass or (not def.class and NS:IsSpellKnown(def)) then
            for _, list in ipairs({ def.types, def.enhancedTypes }) do
                for _, auraType in ipairs(list or {}) do supported[auraType] = true end
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

-- Each aura type gets its own hint, shifted so two visuals on one cell do not
-- print on top of each other. The shift was a flat 7 px whatever the cell, so
-- on a 12 px cell the third slot started at 16 px -- entirely outside. It
-- follows the cell now, and a hint that still would not fit is not drawn at
-- all rather than spilling onto the neighbour. Returns nil when it does not fit.
function NS:ClickHintOffset(slot, size)
    local cell = tonumber(size) or tonumber(self.db and self.db.frameSize) or 22
    local step = math.max(3, math.floor(7 * cell / 22 + 0.5))
    local x = math.max(1, slot or 1) - 1
    local offset = x * step
    if offset + self:CellFontSize("plate", cell) > cell then return nil end
    return offset
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
    local function setFont(region, role, flags)
        if region and region.SetFont then region:SetFont(font, self:CellFontSize(role, size), flags or "") end
    end
    local function setPlate(region)
        if region and region.SetSize then region:SetSize(plate, plate) end
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
        self.pendingAnchorAppearance = true
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
        self.pendingPriorityBinding = true
        return
    end
    local macro = self:BuildPriorityDispelMacro()
    self.priorityDispelButton:SetAttribute("type1", macro and "macro" or "none")
    self.priorityDispelButton:SetAttribute("macrotext1", macro)
end

function NS:ApplyPriorityDispelBinding(skipConfigure)
    if not self.priorityBindingOwner then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingPriorityBinding = true
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

    local ok = pcall(function()
        visual.auraButton:SetFrameLevel(level)
        if visual.auraButton.SetMouseMotionEnabled then
            visual.auraButton:SetMouseMotionEnabled(enabled and self.db.showTooltips)
        end
        visual.overlay:SetColorTexture(clickColor[1], clickColor[2], clickColor[3], alpha)
        visual.typeMark:SetColorTexture(typeColor[1], typeColor[2], typeColor[3], enabled and 1 or 0)
        visual.stack:ClearAllPoints()
        if slot == 2 then
            visual.stack:SetPoint("RIGHT", button, "RIGHT", -1, 0)
        elseif slot == 3 then
            visual.stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 3)
        else
            visual.stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
        end
        visual.stack:SetShown(enabled and self.db.showStacks and not self:CellShowsNames())
        if visual.unitName then
            visual.unitName:SetWidth(math.max(8, self.db.frameSize - 4))
            visual.unitName:SetText(button.descriptor and button.descriptor.displayName or button.unit or "")
            visual.unitName:SetShown(enabled and self:CellShowsNames())
        end
        local hintOffset = self:ClickHintOffset(slot, self.db.frameSize)
        local hintShown = enabled and (slot ~= nil or manual ~= nil)
            and self.db.showClickHints and hintOffset ~= nil
        if visual.clickHint then
            visual.clickHint:ClearAllPoints()
            visual.clickHint:SetPoint("TOPLEFT", button, "TOPLEFT", 2 + (hintOffset or 0), -1)
            visual.clickHint:SetText(slot and clickHint(slot) or (manual and "!" or ""))
            -- Manual abilities use an exclamation mark, never a click letter.
            visual.clickHint:SetShown(hintShown)
        end
        if visual.clickHintPlate then
            visual.clickHintPlate:ClearAllPoints()
            visual.clickHintPlate:SetPoint("TOPLEFT", button, "TOPLEFT", 1 + (hintOffset or 0), -1)
            visual.clickHintPlate:SetShown(hintShown)
        end
        if visual.durationCooldown then
            visual.durationCooldown:SetFrameLevel(level + 1)
            visual.durationCooldown:SetDrawSwipe(enabled and true or false)
        end
        if visual.labelLayer then visual.labelLayer:SetFrameLevel(level + 3) end
    end)
    if not ok then self.pendingAuraStyle = true end
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
        local auraType = self.engineAuraTypes[index]
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
        for auraType, slotKey in pairs(button.auraSlotKeys or {}) do
            local ok = pcall(container.SetAuraSlotCandidateFilters, container, slotKey, self:BuildAuraCandidateFilters(auraType))
            if not ok then self.pendingAuraFilters = true end
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
        self.pendingSpells = true
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
        end
    end
    self:ConfigurePriorityDispelButton()
    self:ApplyPriorityDispelBinding(true)
end

function NS:AssignRosterToButtons()
    if not self.buttons then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRoster = true
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
            button:SetAttribute("unit", descriptor.unit)
            if button.clickLayer then
                button.clickLayer.unit = descriptor.unit
                button.clickLayer:SetAttribute("unit", descriptor.unit)
                self:ApplyVehicleDriver(button.clickLayer, descriptor.unit)
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

function NS:LayoutButtons()
    if not self.buttons then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingLayout = true
        return
    end
    local size, spacing, columns = self.db.frameSize, self.db.spacing, self.db.columns
    local layoutMode = self.db.layoutMode or "GRID"
    -- A run that leaves the screen shows nothing, so it wraps instead. The
    -- shape the player asked for is kept: horizontal still fills a row before
    -- starting another, vertical still fills a column.
    local growRightEarly = self.db.grow == "RIGHT_DOWN" or self.db.grow == "RIGHT_UP"
    local growDownEarly = self.db.grow == "RIGHT_DOWN" or self.db.grow == "LEFT_DOWN"
    local rows
    if layoutMode == "HORIZONTAL" then
        columns = self:MaxCellsPerRun(size, spacing, self:AvailableExtent(true, growRightEarly)) or MAX_BUTTONS
    elseif layoutMode == "VERTICAL" then
        -- The vertical run carries the layout's 3 px margin.
        rows = self:MaxCellsPerRun(size, spacing, self:AvailableExtent(false, not growDownEarly), 3) or MAX_BUTTONS
        columns = 1
    else
        local widest = self:MaxCellsPerRun(size, spacing, self:AvailableExtent(true, growRightEarly))
        if widest then columns = math.min(columns, widest) end
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
    self.gridAnchor:SetSize(size, math.max(12, math.floor(size * 0.55)))
    self:LayoutManualIndicator()
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

function NS:GetCurableAura(unit, includeGrouped)
    if self.testMode then
        local slot = ((self.unitToButton[unit] and self.unitToButton[unit].index or 1) - 1) % math.max(1, #self.clickSpells) + 1
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
    GameTooltip:Show()
end

-- Attribute drivers are evaluated by the secure engine, so the click target
-- follows a passenger into and out of a vehicle even during combat, which a
-- plain SetAttribute could not.
function NS:ApplyVehicleDriver(frame, unit)
    if not frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRoster = true
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

-- engineAuraTypes is decided once, when the grid is built. A specialization
-- or talent change can alter it, and reconfiguring existing slots cannot add
-- a type that was never created. Rebuild rather than leave a stale set.
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
    if same then return false end

    if InCombatLockdown and InCombatLockdown() then
        self.pendingAuraEngineRebuild = true
        return false
    end
    self.pendingAuraEngineRebuild = false

    self.engineAuraTypes = wanted
    self.auraContainerDiagnostics = {
        expected = MAX_BUTTONS * #wanted, added = 0, readyButtons = 0, firstError = nil,
    }
    for _, button in ipairs(self.buttons) do
        if button.auraContainer then
            pcall(button.auraContainer.Hide, button.auraContainer)
            button.auraContainer = nil
        end
        button.auraSlotKeys, button.auraSlotVisuals = nil, nil
        button.engineAuraReady = false
        self:CreateAuraContainer(button)
        if button.engineAuraReady then
            self.auraContainerDiagnostics.readyButtons = self.auraContainerDiagnostics.readyButtons + 1
        end
    end
    self.engineAuraMode = #wanted > 0 and self.auraContainerDiagnostics.readyButtons > 0
    return true
end
