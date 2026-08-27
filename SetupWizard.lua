local _, NS = ...

local function isFrench()
    return NS.db and NS.db.language == "frFR"
end

local function tr(fr, en)
    return isFrench() and fr or en
end

local function addEscapeFrame(name)
    if not UISpecialFrames then return end
    for _, value in ipairs(UISpecialFrames) do if value == name then return end end
    UISpecialFrames[#UISpecialFrames + 1] = name
end

function NS:CreateSetupWizard()
    local frame = CreateFrame("Frame", "CleansiveSetupWizard", UIParent)
    frame:SetSize(600, 470)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    self:SkinUXPanel(frame, 0.995)
    frame:Hide()
    self.setupWizard = frame
    addEscapeFrame("CleansiveSetupWizard")

    local ar, ag, ab = self:GetUXAccent()
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(self:GetUXFont(), 26, "")
    title:SetPoint("TOPLEFT", 30, -28)
    title:SetText("Cleansive")
    title:SetTextColor(1, 1, 1, 1)
    local step = frame:CreateFontString(nil, "OVERLAY")
    step:SetFont(self:GetUXFont(), 11, "")
    step:SetPoint("TOPRIGHT", -30, -35)
    step:SetTextColor(ar, ag, ab, 1)
    frame.step = step

    frame.heading = frame:CreateFontString(nil, "OVERLAY")
    frame.heading:SetFont(self:GetUXFont(), 17, "")
    frame.heading:SetPoint("TOPLEFT", 30, -76)
    frame.heading:SetTextColor(1, 1, 1, 0.94)
    frame.description = frame:CreateFontString(nil, "OVERLAY")
    frame.description:SetFont(self:GetUXFont(), 11, "")
    frame.description:SetPoint("TOPLEFT", 30, -104)
    frame.description:SetWidth(540)
    frame.description:SetJustifyH("LEFT")
    frame.description:SetTextColor(1, 1, 1, 0.55)

    frame.values = {
        language = self.db.language,
        showPets = self.db.showPets,
        showFocus = self.db.showFocus,
        sound = self.db.sound,
        showClickHints = self.db.showClickHints,
        autoHide = self.db.autoHide,
        afflictedOnly = self.db.afflictedOnly,
    }

    local languageLabel = frame:CreateFontString(nil, "OVERLAY")
    languageLabel:SetFont(self:GetUXFont(), 12, "")
    languageLabel:SetPoint("TOPLEFT", 30, -145)
    languageLabel:SetTextColor(1, 1, 1, 0.65)
    frame.languageLabel = languageLabel
    local english = self:CreateUXButton(frame, "English", 116, 28, true)
    english:SetPoint("TOPLEFT", 174, -137)
    local french = self:CreateUXButton(frame, "Français", 116, 28, false)
    french:SetPoint("LEFT", english, "RIGHT", 10, 0)
    frame.englishButton, frame.frenchButton = english, french

    -- Reuse the labels from Locale.lua so the assistant and the settings
    -- pages can never describe the same toggle in two different ways.
    local optionDefinitions = {
        { "showPets", "PETS" },
        { "showFocus", "FOCUS" },
        { "sound", "SOUND" },
        { "showClickHints", "CLICK_HINTS" },
        { "autoHide", "AUTO_HIDE" },
        { "afflictedOnly", "AFFLICTED_ONLY" },
    }
    frame.optionRows = {}
    for index, definition in ipairs(optionDefinitions) do
        local key, localeKey = definition[1], definition[2]
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(260, 38)
        local column = (index - 1) % 2
        local line = math.floor((index - 1) / 2)
        row:SetPoint("TOPLEFT", 30 + column * 280, -188 - line * 46)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.075, 0.113, 0.141, 0.75)
        local activeStrip = row:CreateTexture(nil, "ARTWORK")
        activeStrip:SetPoint("TOPLEFT", 0, 0)
        activeStrip:SetPoint("BOTTOMLEFT", 0, 0)
        activeStrip:SetWidth(3)
        activeStrip:SetColorTexture(ar, ag, ab, 1)
        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFont(self:GetUXFont(), 11, "")
        label:SetPoint("LEFT", 12, 0)
        label:SetTextColor(1, 1, 1, 0.82)
        local value = row:CreateFontString(nil, "OVERLAY")
        value:SetFont(self:GetUXFont(), 10, "")
        value:SetPoint("RIGHT", -12, 0)
        local valueBg = row:CreateTexture(nil, "ARTWORK")
        valueBg:SetPoint("CENTER", value, "CENTER", 0, 0)
        valueBg:SetSize(44, 20)
        function row:Refresh()
            label:SetText(NS.L[localeKey] or localeKey)
            local enabled = frame.values[key]
            value:SetText(enabled and tr("ACTIF", "ON") or tr("INACTIF", "OFF"))
            value:SetTextColor(enabled and ar or 0.58, enabled and ag or 0.58, enabled and ab or 0.58, 1)
            activeStrip:SetShown(enabled)
            if enabled then
                bg:SetColorTexture(ar * 0.18, ag * 0.18, ab * 0.18, 0.92)
                valueBg:SetColorTexture(ar, ag, ab, 0.10)
                label:SetTextColor(1, 1, 1, 0.94)
            else
                bg:SetColorTexture(0.075, 0.113, 0.141, 0.64)
                valueBg:SetColorTexture(1, 1, 1, 0.03)
                label:SetTextColor(1, 1, 1, 0.66)
            end
        end
        row:SetScript("OnClick", function()
            frame.values[key] = not frame.values[key]
            row:Refresh()
        end)
        row:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
        end)
        row:SetScript("OnLeave", function() row:Refresh() end)
        row:Refresh()
        frame.optionRows[#frame.optionRows + 1] = row
    end

    local note = frame:CreateFontString(nil, "OVERLAY")
    note:SetFont(self:GetUXFont(), 10, "")
    note:SetPoint("BOTTOMLEFT", 30, 74)
    note:SetWidth(330)
    note:SetJustifyH("LEFT")
    note:SetTextColor(1, 1, 1, 0.42)
    frame.note = note

    local finish = self:CreateUXButton(frame, "", 128, 30, true)
    finish:SetPoint("BOTTOMRIGHT", -30, 24)
    finish:SetScript("OnClick", function() self:CompleteSetupWizard(false) end)
    local settings = self:CreateUXButton(frame, "", 154, 30, false)
    settings:SetPoint("RIGHT", finish, "LEFT", -10, 0)
    settings:SetScript("OnClick", function() self:CompleteSetupWizard(true) end)
    frame.finishButton, frame.settingsButton = finish, settings

    local function setLanguage(language)
        frame.values.language = language
        self.db.language = language
        if self.dbRoot and self.dbRoot.global then self.dbRoot.global.language = language end
        english.uxAccentButton = language == "enUS"
        french.uxAccentButton = language == "frFR"
        local englishNormal = english:GetScript("OnLeave")
        local frenchNormal = french:GetScript("OnLeave")
        if englishNormal then englishNormal(english) end
        if frenchNormal then frenchNormal(french) end
        self:RefreshSetupWizardText()
    end
    english:SetScript("OnClick", function() setLanguage("enUS") end)
    french:SetScript("OnClick", function() setLanguage("frFR") end)
    self:RefreshSetupWizardText()
end

function NS:RefreshSetupWizardText()
    local frame = self.setupWizard
    if not frame then return end
    frame.step:SetText(tr("CONFIGURATION RAPIDE", "QUICK SETUP"))
    frame.heading:SetText(tr("Première configuration", "First-time setup"))
    frame.description:SetText(tr(
        "Choisissez un point de départ. Chaque réglage reste modifiable ensuite dans /cleansive.",
        "Choose a starting point. Every setting remains editable later in /cleansive."))
    frame.languageLabel:SetText(tr("Langue", "Language"))
    frame.englishButton:SetText(frame.values.language == "enUS" and "English  <" or "English")
    frame.frenchButton:SetText(frame.values.language == "frFR" and "Français  <" or "Français")
    frame.note:SetText(tr(
        "Les profils sont enregistrés séparément pour ce personnage et cette spécialisation.",
        "Profiles are saved separately for this character and specialization."))
    frame.finishButton:SetText(tr("Terminer", "Finish"))
    frame.settingsButton:SetText(tr("Ouvrir les réglages", "Open full settings"))
    for _, row in ipairs(frame.optionRows or {}) do row:Refresh() end
end

function NS:ShowSetupWizardIfNeeded()
    self:ShowSetupWizard(false)
end

function NS:ShowSetupWizard(force)
    local frame = self.setupWizard
    if not frame or not self.dbRoot or not self.dbRoot.global then return end
    if not force and self.dbRoot.global.setupComplete then return end
    frame.values.language = self.db.language
    frame.openLanguage = self.db.language
    for _, key in ipairs({ "showPets", "showFocus", "sound", "showClickHints", "autoHide", "afflictedOnly" }) do
        frame.values[key] = self.db[key] and true or false
    end
    self:RefreshSetupWizardText()
    -- Escape closes the frame through UISpecialFrames. Treat that as "done"
    -- rather than "cancel", otherwise the assistant reopens on every login.
    frame:SetScript("OnHide", function()
        if self.setupWizardClosing then return end
        self:CompleteSetupWizard(false)
    end)
    frame:Show()
end

function NS:CompleteSetupWizard(openSettings)
    local frame = self.setupWizard
    if not frame or self.setupWizardClosing then return end
    self.setupWizardClosing = true
    for _, key in ipairs({ "showPets", "showFocus", "sound", "showClickHints", "autoHide", "afflictedOnly" }) do
        self.db[key] = frame.values[key] and true or false
    end
    self.db.language = frame.values.language == "frFR" and "frFR" or "enUS"
    self.dbRoot.global.language = self.db.language
    self.dbRoot.global.setupComplete = true
    frame:Hide()
    self:RebuildRoster()
    self:UpdateAuraContainerConfiguration(true)
    self:UpdateGridVisibilityDriver()
    self:RequestAuraSoundRefresh("setup complete")
    self:RefreshAll(true)
    self:RefreshOptions()
    if openSettings and self.optionsFrame then self.optionsFrame:Show() end
    -- Switching in either direction needs a reload, not just to French.
    if self.db.language ~= frame.openLanguage then self:Print(self.L.LANGUAGE_RELOAD) end
    self.setupWizardClosing = nil
end
