local addonName, NS = ...

NS.addonName = addonName
NS.version = "1.5.7"
NS.playerClass = select(2, UnitClass("player"))
NS.blacklist = {}
NS.testMode = false
NS.enabled = true
NS.pendingRoster = false
NS.pendingLayout = false
NS.pendingSpells = false
NS.pendingEnabled = nil
NS.pendingPositionReset = false
NS.pendingGridVisibility = nil
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
    showTooltips = true,
    sound = true,
    soundChannel = "Master",
    soundMaxRegistrations = 4500,
    failureSound = true,
    showCooldown = true,
    showStacks = true,
    showClickHints = true,
    autoHide = false,
    afflictedOnly = false,
    groupManualTypes = false,
    priorityKey = "",
    frameSize = 22,
    spacing = 2,
    columns = 10,
    inactiveAlpha = 0.18,
    blacklistTime = 5,
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

function NS:CanAccess(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
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
        self.pendingPositionReset = true
        self:Print(self.L.COMBAT_LOCKED)
        return
    end
    if self.gridAnchor then self:RestorePosition(self.gridAnchor, "grid") end
    self:Print(self.L.RESET_DONE)
end

function NS:SetEnabled(enabled, silent)
    self.db.enabled = enabled and true or false
    if InCombatLockdown and InCombatLockdown() then
        self.pendingEnabled = self.db.enabled
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
        self.pendingGridVisibility = visible
        self:Print(self.L.COMBAT_LOCKED)
        return
    end
    self.gridManuallyHidden = not visible
    self.pendingGridVisibility = nil
    self:UpdateGridVisibilityDriver()
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

function NS:ToggleTest()
    self.testMode = not self.testMode
    self:RefreshAll(true)
    self:UpdateGridVisibilityDriver()
    if self.RefreshOptions then self:RefreshOptions() end
    if self.testMode then self:PlayAfflictionAlert(true) end
    self:Print(self.testMode and self.L.TEST_ON or self.L.TEST_OFF)
end

function NS:UpdateGridVisibilityDriver()
    if not self.gridAnchor then return end
    if self.UpdateCooldownOverlayVisibility then self:UpdateCooldownOverlayVisibility() end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingVisibilityDriver = true
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

    if self.testMode then
        body:Show()
    elseif self.gridManuallyHidden then
        body:Hide()
    elseif self.db.autoHide and RegisterStateDriver then
        RegisterStateDriver(body, "visibility", "[combat] show; hide")
    else
        body:Show()
    end
end

function NS:UpdateCooldownOverlayVisibility(combatOverride)
    local overlay = self.cooldownBody
    if not overlay then return end
    local autoHideActive = self.db.autoHide and RegisterStateDriver
    local inCombat = combatOverride
    if inCombat == nil then inCombat = InCombatLockdown and InCombatLockdown() end
    local visible = self.enabled and not self.gridManuallyHidden
        and (self.testMode or not autoHideActive or inCombat)
    overlay:SetShown(visible and true or false)
end

function NS:PlayAfflictionAlert(preview)
    if not self.db or not self.db.sound or not self.enabled then return false end

    -- Several party members can receive the same effect in one combat event.
    -- Merge those near-simultaneous notifications into one clear alert.
    local now = GetTime and GetTime() or 0
    if not preview and self.lastAfflictionSound and now - self.lastAfflictionSound < 0.20 then return true end
    self.lastAfflictionSound = now

    local played = false
    if PlaySoundFile then
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
    if mouseButton and mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
    local slot = 1
    if mouseButton == "RightButton" then
        slot = 2
    elseif mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown() then
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
        guid = UnitGUID(button.unit),
        time = GetTime(),
        slot = slot,
    }

    local unit, guid = button.unit, UnitGUID(button.unit)
    local function refreshClickedCooldown()
        if button.unit ~= unit or (guid and UnitGUID(unit) ~= guid) then return end
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
            if unit and UnitExists(unit) and (not guid or UnitGUID(unit) == guid) then
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
    local key = UnitGUID(unit) or unit
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
    self.playerClass = select(2, UnitClass("player"))
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
    if self.pendingAuraEngineRebuild and self.RefreshAuraEngineTypes then
        self:RefreshAuraEngineTypes()
    end
    self.pendingAuraFilters = false
    self.pendingAuraStyle = false
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
    if self.pendingEnabled ~= nil then self:SetEnabled(self.pendingEnabled) end
    if self.pendingGridVisibility ~= nil then self:SetGridVisible(self.pendingGridVisibility) end
    if profileChanged and self.gridAnchor then self:RestorePosition(self.gridAnchor, "grid") end
    if self.pendingVisibilityDriver or profileChanged then self:UpdateGridVisibilityDriver() end
    if self.pendingAnchorAppearance and self.UpdateGridAnchorAppearance then
        self:UpdateGridAnchorAppearance()
    end
    if self.pendingPriorityBinding then self:ApplyPriorityDispelBinding() end
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("combat ended") end
    self:RefreshAll(true)
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
        self:ToggleTest()
    elseif command == "macro" then
        self:CreateMouseoverMacro()
    elseif command == "prio" or command == "priority" then
        self:ShowList("priority")
    elseif command == "pradd" then
        self:AddTargetToList("priority")
    elseif command == "skip" then
        self:ShowList("skip")
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
    elseif command == "soundstatus" then
        self:PrintAuraSoundStatus()
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
    elseif command == "help" then
        self:Print(self.L.HELP)
    elseif command == "ignore" then
        local id = tonumber(rest)
        if id then self:AddFilter(id, false) else self:ShowFilters() end
    else
        self:Print(self.L.HELP)
    end
end

local events = CreateFrame("Frame")
NS.eventFrame = events
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end
        events:UnregisterEvent("ADDON_LOADED")
        NS:Initialize()
        for _, name in ipairs({
            "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_PET",
            "UNIT_CONNECTION", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_FOCUS_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
            "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE",
        }) do
            events:RegisterEvent(name)
        end
        return
    end

    if event == "UNIT_AURA" or event == "UNIT_FLAGS" or event == "UNIT_FACTION" or event == "UNIT_CONNECTION" then
        local unit = ...
        NS:RefreshUnit(unit)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FOCUS_CHANGED" then
        local profileChanged = false
        if event == "PLAYER_ENTERING_WORLD" then
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
        NS:UpdateSpells()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        NS:RefreshDispelCooldowns()
    elseif event == "PLAYER_REGEN_DISABLED" then
        NS:UpdateCooldownOverlayVisibility(true)
        NS:RefreshAuraCandidateFilters()
        NS:RequestAuraSoundRefresh("combat started")
    elseif event == "PLAYER_REGEN_ENABLED" then
        NS:UpdateCooldownOverlayVisibility(false)
        NS:OnCombatEnded()
    elseif event == "UI_ERROR_MESSAGE" then
        NS:OnUIError(...)
    end
end)

local function isDecursiveEnabled()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Decursive") then
        return true
    end
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        -- Retail 12.1 expects (addonName, characterGUID), matching
        -- AddOnUtil.IsAddOnEnabledForCurrentCharacter in Blizzard's UI.
        local characterGUID = UnitGUID and UnitGUID("player") or nil
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
