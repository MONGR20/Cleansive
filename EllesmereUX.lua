local _, NS = ...

-- Cleansive's interface is original, but follows the same UX principles as
-- Ellesmere UI: a quiet dark canvas, one theme accent, compact typography,
-- immediate feedback, and settings grouped into focused pages.

-- Hauteur visible d'une page : fenetre 700, moins l'en-tete 88 et le pied 62.
-- Une page plus courte ne defile pas ; une page plus haute defile.
-- Hauteur reellement VISIBLE d'une page : fenetre 700, moins l'en-tete 88, le
-- pied 62, et les 22 px reserves a la bande « la page continue plus bas ».
-- Cette bande etait posee DANS la zone de lecture et recouvrait la derniere
-- ligne de chaque page longue -- visible sur les captures en jeu du 30/08.
local VIEWPORT_HEIGHT = 528
-- Expose pour que le test parle de la MEME valeur, plutot que d'en recopier
-- une seconde qui divergerait au premier ajustement.
NS.OPTIONS_VIEWPORT_HEIGHT = VIEWPORT_HEIGHT

local C = {
    panel = { 0.05, 0.07, 0.09 },
    panelDeep = { 0.025, 0.035, 0.045 },
    control = { 0.075, 0.113, 0.141 },
    controlHover = { 0.095, 0.142, 0.176 },
    controlPressed = { 0.045, 0.078, 0.100 },
    rowOdd = { 0, 0, 0, 0.10 },
    rowEven = { 0, 0, 0, 0.20 },
    text = { 1, 1, 1, 0.92 },
    dim = { 1, 1, 1, 0.53 },
    section = { 1, 1, 1, 0.41 },
}

local function localized(fr, en)
    return NS.db and NS.db.language == "frFR" and fr or en
end

local function accent()
    local class = NS.playerClass or NS:SafeUnitClass("player")
    local classColors = _G.CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local classColor = classColors and classColors[class]
    if classColor and classColor.r and classColor.g and classColor.b then
        return classColor.r, classColor.g, classColor.b
    end
    local eui = _G.EllesmereUI
    local color = eui and eui.ELLESMERE_GREEN
    if color and color.r and color.g and color.b then
        return color.r, color.g, color.b
    end
    return 0.05, 0.82, 0.62
end

local function fontPath()
    local eui = _G.EllesmereUI
    if eui then
        if eui.GetFontPath then
            local ok, path = pcall(eui.GetFontPath)
            if ok and type(path) == "string" and path ~= "" then return path end
        end
        if type(eui._font) == "string" and eui._font ~= "" then return eui._font end
        if type(eui.EXPRESSWAY) == "string" and eui.EXPRESSWAY ~= "" then return eui.EXPRESSWAY end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function unsnap(texture)
    if texture and texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

local function solid(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(r, g, b, a or 1)
    unsnap(texture)
    return texture
end

local function border(frame, alpha, r, g, b)
    local edges = {}
    r, g, b = r or 1, g or 1, b or 1
    local points = {
        { "TOPLEFT", "TOPRIGHT", true },
        { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false },
        { "TOPRIGHT", "BOTTOMRIGHT", false },
    }
    for index, spec in ipairs(points) do
        local edge = solid(frame, "BORDER", r, g, b, alpha or 0.08)
        edge:SetPoint(spec[1], frame, spec[1])
        edge:SetPoint(spec[2], frame, spec[2])
        if spec[3] then edge:SetHeight(1) else edge:SetWidth(1) end
        edges[index] = edge
    end
    return edges
end

local function setEdges(edges, r, g, b, a)
    for _, edge in ipairs(edges or {}) do edge:SetColorTexture(r, g, b, a) end
end

local function text(parent, value, size, color, layer)
    local label = parent:CreateFontString(nil, layer or "OVERLAY")
    label:SetFont(fontPath(), size or 13, "")
    label:SetText(value or "")
    local col = color or C.text
    label:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    return label
end

-- La mise a l'echelle ne se faisait qu'une fois, a la creation. Changer de
-- resolution, passer en fenetre, ou bouger l'echelle de l'interface laissait la
-- fenetre a l'ancienne taille : sur un ecran devenu plus petit elle depassait
-- de partout jusqu'au prochain /reload. La taille de conception est retenue sur
-- le cadre pour que le calcul puisse etre rejoue tel quel.
local function fitToScreen(frame, width, height)
    if width then frame.uxDesignWidth = width end
    if height then frame.uxDesignHeight = height end
    width, height = frame.uxDesignWidth, frame.uxDesignHeight
    if not (width and height) then return end
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then return end
    local availableWidth = math.max(1, UIParent:GetWidth() - 40)
    local availableHeight = math.max(1, UIParent:GetHeight() - 40)
    local scale = math.min(1, availableWidth / width, availableHeight / height)
    -- Le plancher est celui de la lisibilite : en dessous, les libelles ne se
    -- lisent plus et une fenetre illisible ne vaut pas mieux qu'une fenetre
    -- trop grande.
    frame:SetScale(math.max(0.70, scale))
    local windows = NS.uxWindows
    if not windows then windows = {} NS.uxWindows = windows end
    for _, known in ipairs(windows) do
        if known == frame then return end
    end
    windows[#windows + 1] = frame
end

-- Rejoue le calcul pour chaque fenetre deja construite. Appele par les deux
-- evenements qui changent la place disponible.
function NS:RefitWindows()
    for _, frame in ipairs(self.uxWindows or {}) do
        fitToScreen(frame)
    end
end

function NS:GetUXAccent()
    return accent()
end

function NS:GetUXFont()
    return fontPath()
end

function NS:SkinUXPanel(frame, alpha)
    local bg = solid(frame, "BACKGROUND", C.panel[1], C.panel[2], C.panel[3], alpha or 0.98)
    bg:SetAllPoints()
    frame.uxBackground = bg
    frame.background = bg
    frame.uxBorder = border(frame, 0.08)
    local ar, ag, ab = accent()
    local line = solid(frame, "BORDER", ar, ag, ab, 0.95)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(2)
    frame.uxAccent = line
end

function NS:CreateUXButton(parent, value, width, height, isAccent)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width or 100, height or 26)
    local ar, ag, ab = accent()
    local function linearChannel(channel)
        if channel <= 0.04045 then return channel / 12.92 end
        return ((channel + 0.055) / 1.055) ^ 2.4
    end
    local luminance = 0.2126 * linearChannel(ar) + 0.7152 * linearChannel(ag) + 0.0722 * linearChannel(ab)
    local accentText = luminance > 0.40 and { 0.015, 0.025, 0.030 } or { 1, 1, 1 }
    local bg = solid(control, "BACKGROUND", C.control[1], C.control[2], C.control[3], 0.90)
    bg:SetAllPoints()
    local edges = border(control, 0.20)
    local label = text(control, value, 12, C.text)
    label:SetPoint("CENTER", 0, 0)
    control:SetFontString(label)
    control.uxBackground, control.uxBorder, control.uxLabel = bg, edges, label
    control.uxAccentButton = isAccent and true or false

    local function normal()
        if not control:IsEnabled() then
            bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.28)
            label:SetTextColor(1, 1, 1, 0.24)
            setEdges(edges, 1, 1, 1, 0.05)
        elseif control.uxAccentButton then
            bg:SetColorTexture(ar, ag, ab, 0.76)
            label:SetTextColor(accentText[1], accentText[2], accentText[3], 1)
            setEdges(edges, ar, ag, ab, 0.95)
        else
            bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.90)
            label:SetTextColor(1, 1, 1, 0.68)
            setEdges(edges, 1, 1, 1, 0.20)
        end
    end

    local function hover()
        if not control:IsEnabled() then return end
        if control.uxAccentButton then
            bg:SetColorTexture(ar, ag, ab, 0.96)
            label:SetTextColor(accentText[1], accentText[2], accentText[3], 1)
        else
            bg:SetColorTexture(C.controlHover[1], C.controlHover[2], C.controlHover[3], 0.98)
            label:SetTextColor(1, 1, 1, 0.90)
            setEdges(edges, 1, 1, 1, 0.32)
        end
    end
    control:SetScript("OnEnter", hover)
    control:SetScript("OnLeave", normal)
    control:SetScript("OnMouseDown", function()
        if not control:IsEnabled() then return end
        if control.uxAccentButton then
            bg:SetColorTexture(ar * 0.78, ag * 0.78, ab * 0.78, 1)
        else
            bg:SetColorTexture(C.controlPressed[1], C.controlPressed[2], C.controlPressed[3], 1)
        end
        label:ClearAllPoints()
        label:SetPoint("CENTER", 0, -1)
    end)
    control:SetScript("OnMouseUp", function()
        label:ClearAllPoints()
        label:SetPoint("CENTER", 0, 0)
        hover()
    end)
    local nativeSetEnabled = control.SetEnabled
    control.SetEnabled = function(self, enabled)
        nativeSetEnabled(self, enabled)
        normal()
    end
    normal()
    return control
end

local function addPanelBackground(frame, alpha)
    NS:SkinUXPanel(frame, alpha)
end

local function title(parent, value, x, y, template)
    local size = 13
    local color = C.text
    if template == "GameFontNormalHuge" then size = 24
    elseif template == "GameFontNormalLarge" then size = 16
    elseif template == "GameFontHighlightSmall" then size, color = 11, C.dim
    elseif template == "GameFontNormal" then size = 13
    end
    local label = text(parent, value, size, color)
    label:SetPoint("TOPLEFT", x, y)
    return label
end

local function button(parent, value, width, height, isAccent)
    return NS:CreateUXButton(parent, value, width, height, isAccent)
end

local function showHelpTooltip(owner, heading, body)
    if not owner or not body or body == "" or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if heading and heading ~= "" then GameTooltip:AddLine(heading, 1, 1, 1) end
    GameTooltip:AddLine(body, 0.78, 0.78, 0.78, true)
    GameTooltip:Show()
end

local function attachHelp(control, heading, body)
    if not control or not body or body == "" then return control end
    control:HookScript("OnEnter", function(self) showHelpTooltip(self, heading, body) end)
    control:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return control
end

-- Les chevrons etaient les caracteres « ^ » et « v » : petits, peu contrastes,
-- et lus comme du texte secondaire plutot que comme des commandes. Deux barres
-- pivotees ne dependent ni de la police ni d'un chemin de texture Blizzard.
local function chevron(control, up)
    local ar, ag, ab = accent()
    control.chevron = {}
    for index = 1, 2 do
        local bar = control:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 1, 1, 1)
        bar:SetSize(9, 2)
        bar:SetPoint("CENTER", (index == 1 and -2.5 or 2.5), 0)
        -- Le signe etait inverse : « Monter » dessinait une descente. Les
        -- actions, elles, ont toujours ete bonnes -- seule la rotation etait
        -- fausse, ce qu'aucun test ne pouvait voir sans la mesurer.
        local angle = (index == 1 and 1 or -1) * (up and 0.6 or -0.6)
        bar:SetRotation(angle)
        control.chevron[index] = bar
    end
    control:HookScript("OnEnter", function(self)
        self.hovered = true
        self:PaintChevron()
    end)
    control:HookScript("OnLeave", function(self)
        self.hovered = false
        self:PaintChevron()
    end)
    -- Repos lisible, survol a la couleur de classe, desactive nettement attenue.
    function control:PaintChevron()
        local alpha = self.disabledDirection and 0.22 or (self.hovered and 1 or 0.85)
        local r, g, b = 1, 1, 1
        if self.hovered and not self.disabledDirection then r, g, b = ar, ag, ab end
        for _, bar in ipairs(self.chevron) do bar:SetColorTexture(r, g, b, alpha) end
    end
    control:PaintChevron()
end

-- Une direction impossible ne doit pas se presenter comme cliquable.
local function setDirectionEnabled(control, enabled)
    if not control then return end
    control.disabledDirection = not enabled
    control:SetEnabled(enabled)
    if control.PaintChevron then control:PaintChevron() end
end

-- The list windows live in Lists.lua and were calling SetEnabled directly, which
-- blocks the click but leaves the chevron painted like a live control.
NS.SetDirectionEnabled = function(_, control, enabled)
    setDirectionEnabled(control, enabled)
end

local function section(parent, value, y)
    local label = text(parent, string.upper(value), 11, C.section)
    label:SetPoint("TOPLEFT", 0, y)
    local divider = solid(parent, "ARTWORK", 1, 1, 1, 0.08)
    divider:SetPoint("LEFT", label, "RIGHT", 12, 0)
    divider:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    divider:SetHeight(1)
    return label
end

local optionRegistry = {}

local function registerOption(control, parent, label, helpText)
    optionRegistry[#optionRegistry + 1] = {
        control = control, parent = parent, label = label, help = helpText,
    }
    return control
end

local function toggle(parent, value, x, y, width, key, callback, helpText)
    local row = CreateFrame("Button", nil, parent)
    registerOption(row, parent, value, helpText)
    row:SetSize(width or 250, 34)
    row:SetPoint("TOPLEFT", x, y)
    row.key = key

    local label = text(row, value, 13, C.text)
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth((width or 250) - 96)
    label:SetJustifyH("LEFT")
    local state = text(row, "", 9, C.dim)
    state:SetPoint("RIGHT", -52, 0)
    state:SetJustifyH("RIGHT")
    local track = CreateFrame("Frame", nil, row)
    track:SetSize(42, 22)
    track:SetPoint("RIGHT", 0, 0)
    local trackBg = solid(track, "BACKGROUND", 0.267, 0.267, 0.267, 0.65)
    trackBg:SetAllPoints()
    local knob = solid(track, "ARTWORK", 1, 1, 1, 0.55)
    knob:SetSize(16, 16)
    local ar, ag, ab = accent()

    function row:Apply(valueOn)
        self.valueOn = valueOn and true or false
        knob:ClearAllPoints()
        if self.valueOn then
            trackBg:SetColorTexture(ar, ag, ab, 0.78)
            knob:SetColorTexture(1, 1, 1, 1)
            knob:SetPoint("RIGHT", track, "RIGHT", -3, 0)
            label:SetTextColor(1, 1, 1, 0.94)
            state:SetText(NS.L.STATE_ON)
            state:SetTextColor(ar, ag, ab, 1)
        else
            trackBg:SetColorTexture(0.267, 0.267, 0.267, 0.65)
            knob:SetColorTexture(1, 1, 1, 0.50)
            knob:SetPoint("LEFT", track, "LEFT", 3, 0)
            label:SetTextColor(1, 1, 1, 0.64)
            state:SetText(NS.L.STATE_OFF)
            state:SetTextColor(1, 1, 1, 0.38)
        end
    end

    row:SetScript("OnClick", function(self)
        NS.db[key] = not self.valueOn
        self:Apply(NS.db[key])
        if callback then callback(NS.db[key]) end
        NS:RefreshOptions()
    end)
    row:SetScript("OnEnter", function(self)
        label:SetTextColor(1, 1, 1, 1)
        showHelpTooltip(self, value, helpText)
    end)
    row:SetScript("OnLeave", function()
        row:Apply(row.valueOn)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:Apply(NS.db and NS.db[key])
    return row
end

local sliderCount = 0
-- `format` s'applique a la valeur brute. `display` la transforme d'abord, pour
-- les reglages dont l'unite affichee n'est pas celle stockee : une opacite de
-- 0.25 se lit 25 %, pas 0.25.
local function slider(parent, value, x, y, width, minValue, maxValue, step, key, format, callback, helpText, display)
    sliderCount = sliderCount + 1
    local control = CreateFrame("Slider", "CleansiveUXSlider" .. sliderCount, parent)
    registerOption(control, parent, value, helpText)
    -- 30 px de cadre pour une barre de 4 et un curseur de 18 : le bas du cadre
    -- descendait sous le libelle du curseur suivant et ne laissait que 9 px
    -- avant « Outils rapides ». 22 garde 2 px de marge autour du curseur et
    -- rend 8 px par reglage a la page.
    control:SetSize(width, 22)
    control:SetPoint("TOPLEFT", x, y - 22)
    control:SetOrientation("HORIZONTAL")
    control:SetMinMaxValues(minValue, maxValue)
    control:SetValueStep(step)
    control:SetObeyStepOnDrag(true)
    control.key, control.format = key, format

    local valueText = text(parent, "", 12, C.text)
    -- La forme a trois arguments ancre TOPRIGHT sur le TOPRIGHT du parent : un
    -- decalage x positif poussait donc la valeur de 265 a 575 px A DROITE du
    -- bord du panneau, hors de l'ecran. Les six curseurs etaient muets.
    valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    valueText:SetJustifyH("RIGHT")
    -- Le libelle s'arrete ou la valeur commence. Sans cette borne, un libelle
    -- francais long passait simplement dessous.
    local label = text(parent, value, 12, C.dim)
    label:SetPoint("TOPLEFT", x, y)
    label:SetPoint("TOPRIGHT", valueText, "TOPLEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local track = solid(control, "BACKGROUND", 1, 1, 1, 0.16)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    local ar, ag, ab = accent()
    local fill = solid(control, "BORDER", ar, ag, ab, 0.82)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(4)
    control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = control:GetThumbTexture()
    if thumb then
        thumb:SetSize(12, 18)
        thumb:SetColorTexture(ar, ag, ab, 1)
        unsnap(thumb)
    end

    local function updateVisual(current)
        local ratio = (current - minValue) / (maxValue - minValue)
        ratio = math.max(0, math.min(1, ratio))
        fill:SetWidth(math.max(1, width * ratio))
        valueText:SetText(string.format(format, display and display(current) or current))
    end

    control:SetScript("OnValueChanged", function(self, current)
        if step >= 1 then current = math.floor(current + 0.5) end
        updateVisual(current)
        if self.refreshing then return end
        NS.db[key] = current
        if callback then
            self.callbackSerial = (self.callbackSerial or 0) + 1
            local serial = self.callbackSerial
            if C_Timer and C_Timer.After then
                C_Timer.After(0.10, function()
                    if self.callbackSerial == serial then callback(NS.db[key]) end
                end)
            else
                callback(current)
            end
        end
    end)

    function control:Refresh()
        self.refreshing = true
        self:SetValue(NS.db[key])
        updateVisual(NS.db[key])
        self.refreshing = false
    end

    -- Exposes pour la suite de tests : la valeur etait invisible depuis un an
    -- et rien ne pouvait le voir, faute d'y avoir acces.
    control.valueText, control.labelText = valueText, label
    attachHelp(control, value, helpText)
    control:Refresh()
    return control
end

local function navButton(parent, value, key, y)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(170, 42)
    control:SetPoint("TOPLEFT", 0, y)
    control.key = key
    local bg = solid(control, "BACKGROUND", 1, 1, 1, 0)
    bg:SetAllPoints()
    local indicator = solid(control, "ARTWORK", accent())
    indicator:SetPoint("TOPLEFT", 0, 0)
    indicator:SetPoint("BOTTOMLEFT", 0, 0)
    indicator:SetWidth(3)
    indicator:Hide()
    local label = text(control, value, 13, C.dim)
    label:SetPoint("LEFT", 18, 0)

    function control:SetActive(active)
        self.active = active
        indicator:SetShown(active)
        if active then
            bg:SetColorTexture(1, 1, 1, 0.055)
            label:SetTextColor(1, 1, 1, 1)
        else
            bg:SetColorTexture(1, 1, 1, 0)
            label:SetTextColor(1, 1, 1, 0.58)
        end
    end
    control:SetScript("OnEnter", function()
        if not control.active then
            bg:SetColorTexture(1, 1, 1, 0.035)
            label:SetTextColor(1, 1, 1, 0.86)
        end
    end)
    control:SetScript("OnLeave", function() control:SetActive(control.active) end)
    return control
end

-- Two clicks rather than a popup: a popup interrupts the gesture and gets
-- confirmed without being read. The second click must land within the delay,
-- otherwise the button goes back to what it said.
local function armConfirm(control, restingLabel, armedLabel, action)
    control.confirmArmed = false
    control:SetText(restingLabel)
    control:SetScript("OnClick", function()
        if control.confirmArmed then
            control.confirmArmed = false
            control:SetText(restingLabel)
            action()
            return
        end
        control.confirmArmed = true
        control:SetText(armedLabel)
        control.confirmGeneration = (control.confirmGeneration or 0) + 1
        local generation = control.confirmGeneration
        if C_Timer and C_Timer.After then
            C_Timer.After(4, function()
                if control.confirmGeneration ~= generation then return end
                control.confirmArmed = false
                control:SetText(restingLabel)
            end)
        end
    end)
    return control
end

local REPORT_URL = "https://github.com/MONGR20/Cleansive/issues"

local CLICK_BADGE_COLORS = {
    [1] = { 0.92, 0.08, 0.08 },
    [2] = { 0.08, 0.38, 0.96 },
    [3] = { 1.00, 0.46, 0.02 },
}

local function getTypeLabel(dispelType)
    return NS:GetTypeLabel(dispelType)
end

local CLASS_LABELS_EN = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "D. Knight", SHAMAN = "Shaman", MAGE = "Mage",
    WARLOCK = "Warlock", MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "D. Hunter",
    EVOKER = "Evoker",
}

local CLASS_LABELS_FR = {
    WARRIOR = "Guerrier", PALADIN = "Paladin", HUNTER = "Chasseur", ROGUE = "Voleur",
    PRIEST = "Prêtre", DEATHKNIGHT = "Chev. mort", SHAMAN = "Chaman", MAGE = "Mage",
    WARLOCK = "Démoniste", MONK = "Moine", DRUID = "Druide", DEMONHUNTER = "Chass. démons",
    EVOKER = "Évocateur",
}

local function getClassLabel(classToken)
    local labels = NS.db and NS.db.language == "frFR" and CLASS_LABELS_FR or CLASS_LABELS_EN
    return labels[classToken] or classToken
end

-- Arrow glyphs render as empty boxes: neither Expressway nor FRIZQT__.TTF
-- carries U+2190..U+2193, so the control was unreadable and the player could
-- not tell which direction was selected. Words instead, and in Locale.lua
-- rather than a private table the rest of the addon cannot reach.
local function growthLabel(growth)
    return NS.L["GROW_" .. tostring(growth)] or growth
end

local function layoutModeLabel(mode)
    if mode == "HORIZONTAL" then return NS.L.LAYOUT_HORIZONTAL end
    if mode == "VERTICAL" then return NS.L.LAYOUT_VERTICAL end
    return NS.L.LAYOUT_GRID
end

-- Une bande allumee au bas d'une page qui ne defile pas serait un mensonge :
-- elle ne parait que tant qu'il reste de la matiere sous le pli. Les 2 px de
-- marge absorbent l'arrondi du client, qui ne rend jamais la portee au pixel
-- pres. Elle vit sur la FENETRE, pas sur la page : posee sur la page, elle
-- defilerait avec elle et disparaitrait juste quand elle sert.
function NS:UpdateOptionsScrollHint()
    local scroll, hint = self.optionsScroll, self.optionsScrollHint
    if not (scroll and hint) then return end
    local range = scroll:GetVerticalScrollRange() or 0
    local position = scroll:GetVerticalScroll() or 0
    hint:SetShown(range > 0 and position < range - 2)
end

function NS:ShowOptionsPage(key)
    key = key or self.activeOptionsPage or "general"
    self.activeOptionsPage = key
    for name, page in pairs(self.optionsPages or {}) do page:SetShown(name == key) end
    -- La hauteur de la zone qui defile est celle de la page affichee : une page
    -- courte ne doit pas heriter du defilement d'une page longue.
    if self.optionsContent and self.optionsScroll then
        local height = (self.optionsPageHeights or {})[key] or VIEWPORT_HEIGHT
        self.optionsContent:SetHeight(math.max(VIEWPORT_HEIGHT, height))
        self.optionsScroll:SetVerticalScroll(0)
        self:UpdateOptionsScrollHint()
    end
    for name, nav in pairs(self.optionsNav or {}) do nav:SetActive(name == key) end
    local metadata = {
        general = { self.L.PAGE_GENERAL_TITLE, self.L.PAGE_GENERAL_DESC },
        appearance = { self.L.PAGE_APPEARANCE_TITLE, self.L.PAGE_APPEARANCE_DESC },
        dispels = { self.L.PAGE_DISPELS_TITLE, self.L.PAGE_DISPELS_DESC },
        history = { self.L.PAGE_HISTORY_TITLE, self.L.PAGE_HISTORY_DESC },
        help = { self.L.PAGE_HELP_TITLE, self.L.PAGE_HELP_DESC },
    }
    local pageInfo = metadata[key] or metadata.general
    if self.optionsHeading then self.optionsHeading:SetText(pageInfo[1]) end
    if self.optionsSubheading then self.optionsSubheading:SetText(pageInfo[2]) end
    if self.pageResetButton then
        self.pageResetButton:SetShown(self.PAGE_RESET_KEYS[key] ~= nil)
        self.pageResetButton.confirmArmed = false
        self.pageResetButton.confirmGeneration = (self.pageResetButton.confirmGeneration or 0) + 1
        self.pageResetButton:SetText(self.L.PAGE_RESET)
    end
    if key == "history" and self.RefreshAuraHistoryPage then self:RefreshAuraHistoryPage() end
end

local function createPreview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    -- 78 -> 70 : les cases font 38 px et sont centrees, la boite garde donc
    -- 16 px de marge. Les huit pixels rendus paient la quatrieme rangee de
    -- reglages sans tasser quoi que ce soit d'autre.
    preview:SetSize(560, 70)
    preview:SetPoint("TOPLEFT", 0, -554)
    local bg = solid(preview, "BACKGROUND", C.panelDeep[1], C.panelDeep[2], C.panelDeep[3], 0.80)
    bg:SetAllPoints()
    border(preview, 0.08)
    preview.cells = {}
    for index = 1, 4 do
        local cell = CreateFrame("Frame", nil, preview)
        cell:SetSize(38, 38)
        cell:SetPoint("LEFT", 14 + ((index - 1) * 46), 0)
        cell.bg = solid(cell, "BACKGROUND", 0.05, 0.07, 0.09, 1)
        cell.bg:SetAllPoints()
        cell.edges = border(cell, 0.16)
        cell.typeMark = solid(cell, "ARTWORK", 1, 1, 1, 0)
        cell.typeMark:SetPoint("BOTTOMLEFT", 1, 1)
        cell.typeMark:SetPoint("BOTTOMRIGHT", -1, 1)
        cell.typeMark:SetHeight(2)
        cell.duration = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
        cell.duration:SetAllPoints()
        cell.duration:SetDrawBling(false)
        cell.duration:SetDrawEdge(false)
        cell.duration:SetDrawSwipe(true)
        cell.duration:SetHideCountdownNumbers(true)
        cell.duration:SetReverse(true)
        cell.duration:SetSwipeColor(C.panelDeep[1], C.panelDeep[2], C.panelDeep[3], 0.94)
        local labels = CreateFrame("Frame", nil, cell)
        labels:SetAllPoints()
        labels:SetFrameLevel(cell.duration:GetFrameLevel() + 2)
        cell.label = text(labels, "", 9, C.text)
        cell.label:SetPoint("TOPLEFT", 3, -2)
        cell.cooldown = text(labels, "", 11, C.text)
        cell.cooldown:SetPoint("CENTER", 1, 0)
        preview.cells[index] = cell
    end
    preview.durationLegend = text(preview, "", 10, C.text)
    preview.durationLegend:SetPoint("TOPLEFT", 210, -13)
    preview.cooldownLegend = text(preview, "", 10, C.text)
    preview.cooldownLegend:SetPoint("TOPLEFT", 210, -31)
    preview.mapping = text(preview, "", 9, C.dim)
    preview.mapping:SetPoint("TOPLEFT", 210, -44)
    preview.mapping:SetWidth(334)
    preview.mapping:SetJustifyH("LEFT")
    return preview
end

function NS:CreateOptions()
    local frame = CreateFrame("Frame", "CleansiveOptionsFrame", UIParent)
    frame:SetSize(820, 700)
    fitToScreen(frame, 820, 700)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    addPanelBackground(frame)
    frame:Hide()
    self.optionsFrame = frame
    self:RestoreWindowPosition(frame, "options")

    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SaveWindowPosition(f, "options")
    end)
    frame:SetScript("OnShow", function()
        self:RefreshOptions()
        self:ShowOptionsPage(self.activeOptionsPage or "general")
        self:UpdateGridVisibilityDriver()
    end)
    frame:SetScript("OnHide", function()
        if self.testMode and self.testModeFromOptions then
            self.testModeFromOptions = nil
            self:ToggleTest()
        end
        self:UpdateGridVisibilityDriver()
    end)

    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 1, -3)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(178)
    local sideBg = solid(sidebar, "BACKGROUND", C.panelDeep[1], C.panelDeep[2], C.panelDeep[3], 0.82)
    sideBg:SetAllPoints()
    local sideLine = solid(sidebar, "BORDER", 1, 1, 1, 0.06)
    sideLine:SetPoint("TOPRIGHT", 0, 0)
    sideLine:SetPoint("BOTTOMRIGHT", 0, 0)
    sideLine:SetWidth(1)

    local brand = text(sidebar, "CLEANSIVE", 18, C.text)
    brand:SetPoint("TOPLEFT", 18, -24)
    local tag = text(sidebar, localized("DISSIPATION INTELLIGENTE", "SMART CLEANSING"), 9, C.section)
    tag:SetPoint("TOPLEFT", 18, -50)

    self.optionsNav = {}
    self.optionsNav.general = navButton(sidebar, localized("Général", "General"), "general", -92)
    self.optionsNav.appearance = navButton(sidebar, localized("Apparence", "Appearance"), "appearance", -136)
    self.optionsNav.dispels = navButton(sidebar, localized("Dissipations", "Dispels"), "dispels", -180)
    self.optionsNav.history = navButton(sidebar, self.L.HISTORY, "history", -224)
    self.optionsNav.help = navButton(sidebar, self.L.PAGE_HELP_TITLE, "help", -268)
    for key, control in pairs(self.optionsNav) do
        local pageKey = key
        control:SetScript("OnClick", function() self:ShowOptionsPage(pageKey) end)
    end

    -- Une zone de recherche dans la barre laterale, au-dessus des pages :
    -- c'est la que le joueur cherche deja quand il ne sait pas ou aller.
    local searchBox = CreateFrame("EditBox", nil, sidebar)
    searchBox:SetSize(152, 24)
    searchBox:SetPoint("TOPLEFT", 18, -66)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(ChatFontNormal)
    searchBox:SetTextInsets(6, 6, 0, 0)
    local searchBg = solid(sidebar, "BACKGROUND", 1, 1, 1, 0.05)
    searchBg:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 0, 0)
    searchBg:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", 0, 0)
    local searchHint = text(sidebar, self.L.SEARCH_PLACEHOLDER, 11, C.dim)
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 7, 0)
    self.optionsSearchBox = searchBox

    local results = CreateFrame("Frame", nil, frame)
    results:SetSize(360, 240)
    results:SetPoint("TOPLEFT", 190, -66)
    results:SetFrameStrata("DIALOG")
    results:SetFrameLevel(frame:GetFrameLevel() + 20)
    addPanelBackground(results, 0.98)
    results:Hide()
    results.rows = {}
    for index = 1, 8 do
        local row = button(results, "", 336, 26)
        row:SetPoint("TOPLEFT", 12, -10 - ((index - 1) * 28))
        results.rows[index] = row
    end
    results.empty = text(results, self.L.SEARCH_NONE, 11, C.dim)
    results.empty:SetPoint("TOPLEFT", 14, -14)
    self.optionsSearchResults = results

    searchBox:SetScript("OnTextChanged", function(box)
        local query = box:GetText()
        searchHint:SetShown(query == "")
        self:RefreshOptionsSearch(query)
    end)
    searchBox:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)

    local version = text(sidebar, "v" .. self.version .. "  -  Retail 12.1", 10, C.dim)
    version:SetPoint("BOTTOMLEFT", 18, 18)

    local heading = text(frame, self.L.PAGE_GENERAL_TITLE, 23, C.text)
    heading:SetPoint("TOPLEFT", 204, -22)
    local subheading = text(frame, self.L.PAGE_GENERAL_DESC, 11, C.dim)
    subheading:SetPoint("TOPLEFT", 205, -51)
    subheading:SetWidth(500)
    subheading:SetJustifyH("LEFT")
    self.optionsHeading = heading
    self.optionsSubheading = subheading

    local close = button(frame, "×", 34, 30)
    close:SetPoint("TOPRIGHT", -14, -13)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Les pages etaient hautes de 550 px et pleines : ajouter un reglage de
    -- plus demandait d'en tasser d'autres, et le choix du son de la 1.6.6 est
    -- reste sans bouton pour cette seule raison. La zone de contenu devient une
    -- zone de DEFILEMENT ; chaque page declare sa hauteur, et un test verifie
    -- qu'aucun controle ne depasse la hauteur declaree par sa page.
    local contentScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT", 205, -88)
    contentScroll:SetPoint("BOTTOMRIGHT", -24, 84)
    self.optionsScroll = contentScroll
    local content = CreateFrame("Frame", nil, contentScroll)
    content:SetSize(560, VIEWPORT_HEIGHT)
    contentScroll:SetScrollChild(content)
    self.optionsContent = content
    -- LE defaut vu en jeu le 30/08 : ces deux scripts etaient poses avec
    -- SetScript, qui REMPLACE. UIPanelScrollFrameTemplate met les siens sur ces
    -- deux evenements pour piloter sa barre -- ses bornes, son curseur, sa
    -- visibilite. En les ecrasant je l'ai prive de tout cela : la barre n'etait
    -- jamais configuree, et la molette du modele, qui s'appuie dessus, ne
    -- deplacait plus rien. Rien dans la suite ne pouvait le voir : le bouchon
    -- n'a pas de modele Blizzard derriere.
    --
    -- On CHAINE : le gestionnaire du modele d'abord, le notre ensuite.
    local function chainScript(target, name, extra)
        local previous = target:GetScript(name)
        target:SetScript(name, function(...)
            if previous then previous(...) end
            extra()
        end)
    end
    chainScript(contentScroll, "OnVerticalScroll", function() self:UpdateOptionsScrollHint() end)
    chainScript(contentScroll, "OnScrollRangeChanged", function() self:UpdateOptionsScrollHint() end)

    -- Et une molette qui ne depend d'aucun modele. Trois lignes qui marchent
    -- valent mieux qu'un heritage dont je ne peux pas verifier le detail hors
    -- du client.
    contentScroll:EnableMouseWheel(true)
    local templateWheel = contentScroll:GetScript("OnMouseWheel")
    contentScroll:SetScript("OnMouseWheel", function(target, delta)
        local range = target:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local before = target:GetVerticalScroll() or 0
        if templateWheel then templateWheel(target, delta) end
        -- Le gestionnaire du modele deplace de scrollBar.scrollStep ou, a
        -- defaut, de LA MOITIE de la hauteur visible. L'appeler puis ajouter
        -- 40 px faisait environ 300 px par cran : la molette marchait, mais
        -- sautait la moitie de la page. Un seul pilote a la fois -- si le
        -- modele a deplace, on n'y touche plus ; s'il n'a rien fait, on
        -- deplace nous-memes. Le repli reste indispensable : c'est lui qui
        -- garantit que la molette fonctionne sans dependre du modele.
        if (target:GetVerticalScroll() or 0) ~= before then return end
        local wanted = before - (delta * 40)
        target:SetVerticalScroll(math.max(0, math.min(range, wanted)))
    end)
    -- Et si la barre du modele est la, on lui donne le meme pas : le geste est
    -- alors identique qu'il passe par elle ou par le repli.
    -- Le type est verifie, pas la simple presence : sur un cadre, tout champ
    -- commencant par une majuscule peut etre une methode. « if frame.ScrollBar »
    -- etait donc vrai meme sans barre.
    if type(contentScroll.ScrollBar) == "table" then
        contentScroll.ScrollBar.scrollStep = 40
    end
    self.optionsPages = {}
    self.optionsPageHeights = {}
    self.optionSliders = {}

    local general = CreateFrame("Frame", nil, content)
    general:SetAllPoints()
    self.optionsPages.general = general
    -- 596 et non 550 : la page defile depuis la 1.6.7, et c'est exactement ce
    -- qui permet au reglage du son d'avoir enfin un bouton plutot qu'une seule
    -- commande. Un test verifie qu'aucun controle ne depasse cette hauteur.
    self.optionsPageHeights.general = 596
    self.optionChecks = {}

    -- Ces deux phrases etaient posees en bas de page, PAR-DESSUS la carte de
    -- profil : quatre textes pour trois lignes de place. La premiere repetait
    -- mot pour mot ce que la carte annonce deja, elle a disparu ; les deux
    -- autres sont maintenant posees au-dessus de la carte, et restent enfants
    -- DIRECTS de la page pour que le controle de recouvrement les voie.
    local overviewEngine = text(general, "", 10, C.dim)
    overviewEngine:SetPoint("TOPLEFT", 0, -518)
    overviewEngine:SetWidth(560)
    -- Hauteur RESERVEE, pas subie : sans elle, une formulation plus longue
    -- reviendrait a la ligne et descendrait dans la carte de profil, et le
    -- controle de recouvrement ne verrait rien -- il mesure le texte du moment.
    overviewEngine:SetHeight(14)
    overviewEngine:SetJustifyH("LEFT")
    self.overviewEngineText = overviewEngine

    section(general, localized("Fonctionnement", "Behavior"), -2)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, localized("Addon actif", "Addon enabled"), 0, -28, 275, "enabled", function(value) self:SetEnabled(value) end, self.L.TIP_ENABLED)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.LOCK, 300, -28, 275, "locked", function()
        self:UpdateGridAnchorAppearance()
    end, self.L.TIP_LOCK)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.PETS, 0, -68, 275, "showPets", function() self:RebuildRoster() end, self.L.TIP_PETS)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.FOCUS, 300, -68, 275, "showFocus", function() self:RebuildRoster() end, self.L.TIP_FOCUS)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.AUTO_HIDE, 300, -108, 275, "autoHide", function()
        self:UpdateGridVisibilityDriver()
    end, self.L.TIP_AUTO_HIDE)

    local languageLabel = text(general, self.L.LANGUAGE, 13, C.text)
    languageLabel:SetPoint("TOPLEFT", 0, -112)
    local language = button(general, "", 150, 28)
    language:SetPoint("TOPLEFT", 130, -105)
    language:SetScript("OnClick", function()
        self:SetLanguage(self.db.language == "frFR" and "enUS" or "frFR")
    end)
    attachHelp(language, self.L.LANGUAGE, self.L.TIP_LANGUAGE)
    self.languageButton = language


    section(general, localized("Retour d’information", "Feedback"), -158)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.TOOLTIPS, 0, -184, 275, "showTooltips", function()
        self:UpdateAuraContainerConfiguration(true)
    end, self.L.TIP_TOOLTIPS)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.SOUND, 300, -184, 275, "sound", function(value)
        self:RequestAuraSoundRefresh("sound option")
        if value then self:PlayAfflictionAlert(true) end
    end, self.L.TIP_SOUND)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.FAIL_SOUND, 0, -224, 275, "failureSound", nil, self.L.TIP_FAILURE_SOUND)
    self.soundDependentControls = {}
    -- Posee a -196, cette phrase de 560 px traversait « Afficher les infobulles »
    -- ET « Alerte sonore d'affliction ». Elle rejoint les lignes d'etat du bas.
    local soundAlertLabel = text(general, self.L.ALERT_SOUND, 12, C.dim)
    soundAlertLabel:SetPoint("TOPLEFT", 0, -478)
    soundAlertLabel:SetWidth(150)
    soundAlertLabel:SetJustifyH("LEFT")
    local soundAlert = button(general, "", 200, 26)
    soundAlert:SetPoint("TOPLEFT", 160, -470)
    soundAlert:SetScript("OnClick", function() self:CycleAlertSound() end)
    attachHelp(soundAlert, self.L.ALERT_SOUND, self.L.TIP_ALERT_SOUND)
    self.alertSoundButton = soundAlert
    self.soundDependentControls[#self.soundDependentControls + 1] = soundAlert
    self.soundDependentControls[#self.soundDependentControls + 1] = soundAlertLabel

    local soundState = text(general, "", 10, C.dim)
    soundState:SetPoint("TOPLEFT", 0, -536)
    soundState:SetWidth(560)
    soundState:SetHeight(14)
    soundState:SetJustifyH("LEFT")
    self.soundStateText = soundState
    local soundTest = button(general, self.L.TEST_SOUND, 115, 26)
    soundTest:SetPoint("TOPLEFT", 300, -220)
    soundTest:SetScript("OnClick", function() self:PlayAfflictionAlert(true) end)
    self.soundDependentControls[#self.soundDependentControls + 1] = soundTest
    local soundStatus = button(general, self.L.SOUND_STATUS_BUTTON, 115, 26)
    soundStatus:SetPoint("LEFT", soundTest, "RIGHT", 10, 0)
    soundStatus:SetScript("OnClick", function() self:PrintAuraSoundStatus() end)
    self.soundDependentControls[#self.soundDependentControls + 1] = soundStatus

    -- Descendu a -386, « Afficher en raid » tombait sur « Filtres » et « Macro ».
    local visibilityLabel = text(general, self.L.SHOW_WHERE, 12, C.dim)
    visibilityLabel:SetPoint("TOPLEFT", 300, -288)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.SHOW_SOLO, 300, -306, 265,
        "showSolo", function() self:UpdateGridVisibilityDriver() end, self.L.TIP_SHOW_CONTEXT)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.SHOW_PARTY, 300, -340, 265,
        "showParty", function() self:UpdateGridVisibilityDriver() end, self.L.TIP_SHOW_CONTEXT)
    self.optionChecks[#self.optionChecks + 1] = toggle(general, self.L.SHOW_RAID, 300, -374, 265,
        "showRaid", function() self:UpdateGridVisibilityDriver() end, self.L.TIP_SHOW_CONTEXT)

    self.optionSliders[#self.optionSliders + 1] = slider(general, self.L.BLACKLIST, 0, -266, 265, 0, 15, 1, "blacklistTime", "%d s", nil, self.L.TIP_BLACKLIST)
    local budgetSlider = slider(general, self.L.SOUND_BUDGET, 0, -318, 265, 500, 8000, 250, "soundMaxRegistrations", "%d",
        function() self:RequestAuraSoundRefresh("sound budget") end, self.L.TIP_SOUND_BUDGET)
    self.optionSliders[#self.optionSliders + 1] = budgetSlider
    self.soundDependentControls[#self.soundDependentControls + 1] = budgetSlider
    local soundChannelLabel = text(general, self.L.SOUND_CHANNEL, 12, C.dim)
    soundChannelLabel:SetPoint("TOPLEFT", 310, -266)
    self.soundDependentControls[#self.soundDependentControls + 1] = soundChannelLabel
    local soundChannel = button(general, "", 135, 26)
    soundChannel:SetPoint("TOPLEFT", 420, -258)
    soundChannel:SetScript("OnClick", function()
        local channels = { "Master", "SFX", "Dialog" }
        local current = 1
        for index, value in ipairs(channels) do
            if value == self.db.soundChannel then current = index break end
        end
        self.db.soundChannel = channels[(current % #channels) + 1]
        self:RequestAuraSoundRefresh("sound channel")
        self:RefreshOptions()
        self:PlayAfflictionAlert(true)
    end)
    attachHelp(soundChannel, self.L.SOUND_CHANNEL, self.L.TIP_SOUND_CHANNEL)
    self.soundChannelButton = soundChannel
    self.soundDependentControls[#self.soundDependentControls + 1] = soundChannel

    section(general, localized("Outils rapides", "Quick tools"), -382)
    local priorities = button(general, self.L.PRIORITY, 130, 28)
    priorities:SetPoint("TOPLEFT", 0, -410)
    priorities:SetScript("OnClick", function() self:ShowList("priority") end)
    local skip = button(general, self.L.SKIP, 130, 28)
    skip:SetPoint("LEFT", priorities, "RIGHT", 10, 0)
    skip:SetScript("OnClick", function() self:ShowList("skip") end)
    local filters = button(general, self.L.FILTERS, 130, 28)
    filters:SetPoint("LEFT", skip, "RIGHT", 10, 0)
    filters:SetScript("OnClick", function() self:ShowFilters() end)
    local macro = button(general, "Macro", 130, 28)
    macro:SetPoint("LEFT", filters, "RIGHT", 10, 0)
    macro:SetScript("OnClick", function() self:CreateMouseoverMacro() end)

    -- « Touche de dissipation au survol » mesure environ 200 px : le bouton
    -- pose a 150 lui passait dessus en francais.
    local priorityKeyLabel = text(general, self.L.PRIORITY_KEY, 12, C.dim)
    priorityKeyLabel:SetPoint("TOPLEFT", 0, -450)
    priorityKeyLabel:SetWidth(205)
    priorityKeyLabel:SetJustifyH("LEFT")
    local priorityKey = button(general, "", 158, 26)
    priorityKey:SetPoint("TOPLEFT", 215, -442)
    priorityKey:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    priorityKey:SetScript("OnClick", function(control, mouseButton)
        if mouseButton == "RightButton" then
            self:SetPriorityDispelKey("")
            return
        end
        control.capturing = true
        control:SetText(self.L.PRIORITY_KEY_PRESS)
        control:EnableKeyboard(true)
        if control.SetPropagateKeyboardInput then control:SetPropagateKeyboardInput(false) end
    end)
    priorityKey:SetScript("OnKeyDown", function(control, key)
        if not control.capturing then return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
            or key == "LALT" or key == "RALT" or key == "UNKNOWN" then return end
        control.capturing = false
        control:EnableKeyboard(false)
        if control.SetPropagateKeyboardInput then control:SetPropagateKeyboardInput(true) end
        if key == "ESCAPE" then
            self:RefreshOptions()
            return
        end
        if key == "BACKSPACE" or key == "DELETE" then
            self:SetPriorityDispelKey("")
            return
        end
        local parts = {}
        -- WoW binding strings are canonically ALT-CTRL-SHIFT-KEY. Any other
        -- order simply never matches when Alt is combined with a modifier.
        if IsAltKeyDown() then parts[#parts + 1] = "ALT" end
        if IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
        if IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
        parts[#parts + 1] = key
        self:SetPriorityDispelKey(table.concat(parts, "-"))
    end)
    attachHelp(priorityKey, self.L.PRIORITY_KEY, self.L.TIP_PRIORITY_KEY)
    self.priorityKeyButton = priorityKey
    local setup = button(general, self.L.SETUP_ASSISTANT, 120, 26)
    setup:SetPoint("LEFT", priorityKey, "RIGHT", 10, 0)
    setup:SetScript("OnClick", function() self:ShowSetupWizard(true) end)
    frame:HookScript("OnHide", function()
        if not priorityKey.capturing then return end
        priorityKey.capturing = false
        priorityKey:EnableKeyboard(false)
        if priorityKey.SetPropagateKeyboardInput then priorityKey:SetPropagateKeyboardInput(true) end
        self:RefreshOptions()
    end)

    local info = CreateFrame("Frame", nil, general)
    info:SetSize(560, 40)
    info:SetPoint("TOPLEFT", 0, -556)
    local infoBg = solid(info, "BACKGROUND", C.control[1], C.control[2], C.control[3], 0.42)
    infoBg:SetAllPoints()
    border(info, 0.08)
    local ar, ag, ab = accent()
    local dot = solid(info, "ARTWORK", ar, ag, ab, 1)
    dot:SetSize(7, 7)
    dot:SetPoint("LEFT", 16, 0)
    local infoTitle = text(info, self.L.ACTIVE_PROFILE, 13, C.text)
    infoTitle:SetPoint("LEFT", dot, "RIGHT", 9, 0)
    -- Le nom du profil passe sur la meme ligne que son titre : la carte tient
    -- alors en une rangee, et les deux phrases d'etat ont la place au-dessus.
    local manage = button(info, self.L.PROFILE_MANAGER, 110, 24)
    manage:SetPoint("RIGHT", -16, 0)
    manage:SetScript("OnClick", function() self:ShowProfileManager() end)
    attachHelp(manage, self.L.PROFILE_MANAGER, self.L.PROFILE_MANAGER_HINT)

    local infoText = text(info, "", 11, C.dim)
    infoText:SetPoint("RIGHT", manage, "LEFT", -12, 0)
    infoText:SetWidth(230)
    infoText:SetJustifyH("RIGHT")
    self.profileLabel = infoText

    local appearance = CreateFrame("Frame", nil, content)
    appearance:SetAllPoints()
    self.optionsPages.appearance = appearance
    self.optionsPageHeights.appearance = 670
    section(appearance, localized("Informations sur les cases", "Cell information"), -2)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.NAMES, 0, -28, 275, "showNames", function()
        self:UpdateAuraContainerConfiguration(true)
        self:RefreshAll(true)
    end, self.L.TIP_NAMES)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.DURATION_SWEEP, 300, -108, 275,
        "showDuration", function() self:RefreshAll(true) end, self.L.TIP_DURATION_SWEEP)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.COOLDOWN, 300, -28, 275, "showCooldown", function()
        self:UpdateAuraContainerConfiguration(true)
        self:RefreshAll(true)
        self:RefreshDispelCooldowns()
    end, self.L.TIP_COOLDOWN)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.CENTER_STACKS, 0, -68, 275, "showStacks", function()
        self:UpdateAuraContainerConfiguration(true)
        self:RefreshAll(true)
    end, self.L.TIP_STACKS)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.CLICK_HINTS, 300, -68, 275, "showClickHints", function()
        self:UpdateAuraContainerConfiguration(true)
        self:RefreshAll(true)
    end, self.L.TIP_CLICK_HINTS)
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.AFFLICTED_ONLY, 0, -108, 275, "afflictedOnly", function()
        self:UpdateAuraContainerConfiguration(true)
        self:RefreshAll(true)
    end, self.L.TIP_AFFLICTED_ONLY)
    -- Demande d'un joueur sur le forum le 30/08/2026 : reconnaitre qui est qui
    -- sans lire un nom, que les petites cases ne peuvent de toute facon pas
    -- afficher. Quatrieme rangee : tout ce qui suit descend d'autant, la place
    -- etant prise sur deux ecarts genereux plutot qu'ajoutee au bas de la page.
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.CLASS_COLOR_CELLS, 0, -148, 275,
        -- Pas de RefreshCellPreview ici : les quatre cases de l'apercu des
        -- options n'ont pas d'unite, donc pas de classe. Elles montrent le
        -- langage d'une case affligee, que ce reglage ne touche jamais.
        "classColorCells", function() self:RefreshAll(true) end,
        self.L.TIP_CLASS_COLOR_CELLS)

    for index, preset in ipairs(self.VISUAL_PRESETS) do
        local presetButton = button(appearance, self.L["PRESET_" .. preset.key], 108, 24)
        presetButton:SetPoint("TOPLEFT", 132 + ((index - 1) * 112), -190)
        presetButton:SetScript("OnClick", function() self:ApplyVisualPreset(preset.key) end)
        attachHelp(presetButton, self.L.PRESETS, self.L.TIP_PRESETS)
    end

    section(appearance, localized("Dimensions", "Dimensions"), -194)
    -- L'apercu des options reste immediat : c'est lui que le joueur regarde
    -- pendant qu'il glisse. Seule la vraie grille attend la fin du geste.
    self.optionSliders[#self.optionSliders + 1] = slider(appearance, self.L.SIZE, 0, -226, 265, 12, 40, 1, "frameSize", "%d px", function()
        self:Debounce("layout", 0.1, function() self:LayoutButtons() end)
        self:RefreshCellPreview()
        self:RefreshOptions()
    end, self.L.TIP_SIZE)
    self.optionSliders[#self.optionSliders + 1] = slider(appearance, self.L.SPACING, 310, -226, 265, 0, 12, 1, "spacing", "%d px",
        function() self:Debounce("layout", 0.1, function() self:LayoutButtons() end) end, self.L.TIP_SPACING)
    self.optionSliders[#self.optionSliders + 1] = slider(appearance, self.L.COLUMNS, 0, -278, 265, 1, 20, 1, "columns", "%d",
        function() self:Debounce("layout", 0.1, function() self:LayoutButtons() end) end, self.L.TIP_COLUMNS)
    self.optionSliders[#self.optionSliders + 1] = slider(appearance, self.L.OPACITY, 310, -278, 265, 0.05, 0.80, 0.05, "inactiveAlpha", "%d %%", function() self:RefreshAll(true) end, self.L.TIP_OPACITY,
        function(current) return math.floor(current * 100 + 0.5) end)

    -- Quarante cases a la taille d'un groupe de cinq ne tiennent nulle part.
    -- Les deux jeux se separent SUR DEMANDE ; par defaut le raid garde ceux du
    -- groupe, donc rien ne bouge pour qui n'y touche pas.
    self.optionChecks[#self.optionChecks + 1] = toggle(appearance, self.L.SEPARATE_RAID, 0, -330, 560,
        "separateRaidSize", function()
            self:RefreshOptions()
            self:LayoutButtons()
        end, self.L.TIP_SEPARATE_RAID)
    -- Grises plutot que caches : un controle qui disparait laisse un trou et
    -- ne dit plus qu'il existe -- et surtout, un controle cache echappe au
    -- controle de recouvrement, qui ne mesure que ce qui est affiche.
    self.raidGeometrySliders = {}
    local raidSize = slider(appearance, self.L.RAID_SIZE, 0, -386, 265, 12, 40, 1, "raidFrameSize", "%d px",
        function() self:Debounce("layout", 0.1, function() self:LayoutButtons() end) end, self.L.TIP_RAID_SIZE)
    local raidSpacing = slider(appearance, self.L.RAID_SPACING, 310, -386, 265, 0, 12, 1, "raidSpacing", "%d px",
        function() self:Debounce("layout", 0.1, function() self:LayoutButtons() end) end, self.L.TIP_RAID_SPACING)
    self.optionSliders[#self.optionSliders + 1] = raidSize
    self.optionSliders[#self.optionSliders + 1] = raidSpacing
    self.raidGeometrySliders[1] = raidSize
    self.raidGeometrySliders[2] = raidSpacing

    local nameNote = text(appearance, "", 10, C.dim)
    nameNote:SetPoint("TOPLEFT", 0, -434)
    nameNote:SetWidth(560)
    nameNote:SetJustifyH("LEFT")
    self.nameWidthNote = nameNote

    local resizeNote = text(appearance, self.L.SIZE_COMBAT_NOTE, 10, C.dim)
    resizeNote:SetPoint("TOPLEFT", 0, -448)
    resizeNote:SetWidth(560)
    resizeNote:SetJustifyH("LEFT")
    section(appearance, localized("Disposition", "Layout"), -482)
    local growLabel = text(appearance, self.L.GROW, 13, C.text)
    growLabel:SetPoint("TOPLEFT", 0, -509)
    local grow = button(appearance, "", 160, 28)
    grow:SetPoint("TOPLEFT", 150, -502)
    grow:SetScript("OnClick", function() self:CycleGrowth() end)
    attachHelp(grow, self.L.GROW, self.L.TIP_GROW)
    self.growButton = grow
    local layoutModeTitle = text(appearance, self.L.LAYOUT_MODE, 13, C.text)
    layoutModeTitle:SetPoint("TOPLEFT", 330, -509)
    local layoutMode = button(appearance, "", 150, 28)
    layoutMode:SetPoint("TOPLEFT", 425, -502)
    layoutMode:SetScript("OnClick", function() self:CycleLayoutMode() end)
    attachHelp(layoutMode, self.L.LAYOUT_MODE, self.L.TIP_LAYOUT_MODE)
    self.layoutModeButton = layoutMode

    section(appearance, localized("Aperçu en direct", "Live preview"), -536)
    self.uxPreview = createPreview(appearance)

    -- The four cells above show the cell language. They cannot show whether a
    -- twenty-man grid still fits the screen, which is the question the player
    -- actually has. These buttons answer it on the real grid.
    local previewLabel = text(appearance, self.L.PREVIEW_GROUP, 13, C.text)
    previewLabel:SetPoint("TOPLEFT", 0, -638)
    self.previewSizeButtons = {}
    for index, count in ipairs({ 1, 5, 10, 20, 40 }) do
        local sizeButton = button(appearance, tostring(count), 42, 26)
        sizeButton:SetPoint("TOPLEFT", 122 + ((index - 1) * 46), -632)
        sizeButton:SetScript("OnClick", function() self:SetTestUnits(count) end)
        attachHelp(sizeButton, self.L.PREVIEW_GROUP, self.L.TIP_PREVIEW_GROUP)
        sizeButton.previewCount = count
        self.previewSizeButtons[index] = sizeButton
    end
    local stateButton = button(appearance, "", 168, 26)
    stateButton:SetPoint("TOPLEFT", 400, -632)
    stateButton:SetScript("OnClick", function() self:CycleTestState() end)
    attachHelp(stateButton, self.L.PREVIEW_STATE, self.L.TIP_PREVIEW_STATE)
    self.previewStateButton = stateButton

    local dispels = CreateFrame("Frame", nil, content)
    dispels:SetAllPoints()
    self.optionsPages.dispels = dispels
    -- Cette page a besoin de ses 550 px : son bouton de tri est cale en bas, et
    -- a 528 il remontait sur « Signaler racines et etourdissements ». Elle
    -- defile donc de 22 px, ce qui ne gene rien -- sa molette est libre.
    self.optionsPageHeights.dispels = 550
    self.optionChecks[#self.optionChecks + 1] = toggle(dispels, self.L.GROUP_MANUAL, 0, -430, 560,
        "groupManualTypes", function()
            self:UpdateSpells()
            self:RefreshAll(true)
        end, self.L.TIP_GROUP_MANUAL)
    self.optionChecks[#self.optionChecks + 1] = toggle(dispels, self.L.CONTROL_WARNING, 0, -466, 560,
        "controlWarning", function() self:RefreshAll(true) end, self.L.TIP_CONTROL_WARNING)

    local sortLabel = text(dispels, self.L.SORT_MODE, 13, C.text)
    sortLabel:SetPoint("BOTTOMLEFT", 0, 14)
    local sortButton = button(dispels, "", 190, 28)
    sortButton:SetPoint("BOTTOMLEFT", 150, 8)
    sortButton:SetScript("OnClick", function() self:CycleSortMode() end)
    attachHelp(sortButton, self.L.SORT_MODE, self.L.TIP_SORT_MODE)
    self.sortModeButton = sortButton

    section(dispels, self.L.CURE_ORDER, -2)
    local explanation = text(dispels, localized("La couleur indique le clic à utiliser. Réorganisez les types pour changer l’affectation.", "The color indicates which click to use. Reorder types to change the assignment."), 11, C.dim)
    explanation:SetPoint("TOPLEFT", 0, -28)
    explanation:SetWidth(560)
    explanation:SetJustifyH("LEFT")

    self.typeRows = {}
    for index, dispelType in ipairs(self.DISPEL_TYPES) do
        local auraType = dispelType
        local rowEven = index % 2 == 0
        local row = CreateFrame("Frame", nil, dispels)
        row:SetSize(560, 46)
        row:SetPoint("TOPLEFT", 0, -58 - ((index - 1) * 50))
        local rowBg = solid(row, "BACKGROUND", 0, 0, 0, rowEven and 0.20 or 0.10)
        rowBg:SetAllPoints()

        local check = CreateFrame("CheckButton", nil, row)
        check:SetSize(170, 46)
        check:SetPoint("LEFT", 0, 0)
        check.track = solid(check, "BACKGROUND", 0.267, 0.267, 0.267, 0.65)
        check.track:SetSize(42, 22)
        check.track:SetPoint("LEFT", 12, 0)
        check.knob = solid(check, "ARTWORK", 1, 1, 1, 0.55)
        check.knob:SetSize(16, 16)
        function check:Apply()
            local checked = self:GetChecked()
            self.knob:ClearAllPoints()
            if checked then
                self.track:SetColorTexture(ar, ag, ab, 0.78)
                self.knob:SetColorTexture(1, 1, 1, 1)
                self.knob:SetPoint("RIGHT", self.track, "RIGHT", -3, 0)
                rowBg:SetColorTexture(0, 0, 0, rowEven and 0.20 or 0.10)
            else
                self.track:SetColorTexture(0.267, 0.267, 0.267, 0.65)
                self.knob:SetColorTexture(1, 1, 1, 0.50)
                self.knob:SetPoint("LEFT", self.track, "LEFT", 3, 0)
                rowBg:SetColorTexture(0, 0, 0, 0.34)
            end
        end
        check:SetScript("OnClick", function(control)
            self.db.enabledTypes[auraType] = control:GetChecked() and true or false
            control:Apply()
            self:UpdateSpells()
            self:RefreshAll(true)
        end)

        local color = self.TYPE_COLORS[auraType]
        local typeLabel = text(check, getTypeLabel(auraType), 13, { color[1], color[2], color[3], 1 })
        typeLabel:SetPoint("LEFT", 66, 0)
        typeLabel:SetWidth(100)
        typeLabel:SetJustifyH("LEFT")
        attachHelp(check, getTypeLabel(auraType), string.format(self.L.TIP_DISPEL_TYPE, getTypeLabel(auraType)))
        local clickBadge = CreateFrame("Frame", nil, row)
        clickBadge:SetSize(36, 24)
        clickBadge:SetPoint("LEFT", 178, 0)
        clickBadge.bg = solid(clickBadge, "BACKGROUND", C.control[1], C.control[2], C.control[3], 0.80)
        clickBadge.bg:SetAllPoints()
        clickBadge.edges = border(clickBadge, 0.14)
        clickBadge.label = text(clickBadge, "—", 10, C.text)
        clickBadge.label:SetPoint("CENTER")
        local mapping = text(row, "", 11, C.dim)
        mapping:SetPoint("LEFT", 225, 0)
        mapping:SetWidth(245)
        mapping:SetJustifyH("LEFT")
        -- No arrow glyphs in the UI font: these rendered as empty boxes. Two
        -- rotated bars need neither a font nor a Blizzard texture path.
        local up = button(row, "", 36, 28)
        up:SetPoint("RIGHT", -48, 0)
        up:SetScript("OnClick", function() self:MoveType(auraType, -1) end)
        chevron(up, true)
        attachHelp(up, self.L.MOVE_UP, self.L.MOVE_UP)
        local down = button(row, "", 36, 28)
        down:SetPoint("RIGHT", -8, 0)
        down:SetScript("OnClick", function() self:MoveType(auraType, 1) end)
        chevron(down, false)
        attachHelp(down, self.L.MOVE_DOWN, self.L.MOVE_DOWN)
        self.typeRows[#self.typeRows + 1] = { frame = row, check = check, label = typeLabel, badge = clickBadge, mapping = mapping, up = up, down = down, type = auraType }
    end

    -- Cette legende nommait les trois gestes d'origine, en dur, dans les deux
    -- langues. Elle est ecrite au rafraichissement, comme tout le reste.
    self.dispelClickLegend = text(dispels, "", 11, C.dim)
    self.dispelClickLegend:SetPoint("TOPLEFT", 0, -372)
    self.dispelClickLegend:SetWidth(540)
    self.dispelClickLegend:SetJustifyH("LEFT")

    local configureClicks = button(dispels, self.L.CLICK_WINDOW, 200, 28)
    configureClicks:SetPoint("TOPLEFT", 0, -398)
    configureClicks:SetScript("OnClick", function() self:ShowClickBindings() end)

    local history = CreateFrame("Frame", nil, content)
    history:SetAllPoints()
    history:EnableMouseWheel(true)
    self.optionsPages.history = history
    -- La molette de cette page sert a sa pagination : elle ne doit donc JAMAIS
    -- avoir besoin de defiler, sans quoi les deux gestes se disputeraient la
    -- meme molette. Un test tient cette contrainte.
    self.optionsPageHeights.history = VIEWPORT_HEIGHT
    self.auraHistoryPage = history
    section(history, self.L.HISTORY, -2)
    -- Posee a -28 sur 420 px de large, cette phrase passait sous le bouton
    -- « Copier cette liste ». Elle descend sous la rangee de boutons, ou elle
    -- dispose de toute la largeur.
    local historyInfo = text(history, self.L.HISTORY_HELP, 11, C.dim)
    historyInfo:SetPoint("TOPLEFT", 0, -56)
    historyInfo:SetWidth(560)
    historyInfo:SetJustifyH("LEFT")
    local clearHistory = button(history, self.L.HISTORY_CLEAR, 116, 26)
    clearHistory:SetPoint("TOPRIGHT", 0, -22)
    clearHistory:SetScript("OnClick", function() self:ConfirmClearAuraHistory() end)
    local copyHistory = button(history, self.L.HISTORY_COPY, 132, 26)
    copyHistory:SetPoint("TOPRIGHT", clearHistory, "TOPLEFT", -10, 0)
    copyHistory:SetScript("OnClick", function()
        self:ShowCopyWindow(self.L.HISTORY_COPY, self.L.HISTORY_COPY_HINT,
            self:BuildAuraHistoryReport())
    end)
    self.historyCopyButton = copyHistory
    history.rows = {}
    for index = 1, 11 do
        local row = CreateFrame("Frame", nil, history)
        row:SetSize(560, 32)
        row:SetPoint("TOPLEFT", 0, -96 - ((index - 1) * 35))
        local rowBg = solid(row, "BACKGROUND", 0, 0, 0, index % 2 == 0 and 0.20 or 0.10)
        rowBg:SetAllPoints()
        row.label = text(row, "", 11, C.text)
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetWidth(418)
        row.label:SetJustifyH("LEFT")
        row.action = button(row, "", 112, 22)
        row.action:SetPoint("RIGHT", -6, 0)
        history.rows[index] = row
    end
    -- Une seule phrase en haut d'une zone vide de 400 px se lisait comme une
    -- page qui n'avait pas fini de charger. Un vrai etat vide, centre.
    local emptyState = CreateFrame("Frame", nil, history)
    emptyState:SetPoint("TOPLEFT", 0, -136)
    emptyState:SetPoint("TOPRIGHT", 0, -136)
    emptyState:SetHeight(120)
    local ar, ag, ab = accent()
    local emptyMark = solid(emptyState, "ARTWORK", ar, ag, ab, 1)
    emptyMark:SetSize(7, 7)
    emptyMark:SetPoint("TOP", 0, 0)
    local emptyTitle = text(emptyState, self.L.HISTORY_EMPTY_TITLE, 15, C.text)
    emptyTitle:SetPoint("TOP", emptyMark, "BOTTOM", 0, -14)
    local emptyDesc = text(emptyState, self.L.HISTORY_EMPTY_DESC, 11, C.dim)
    emptyDesc:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -10)
    emptyDesc:SetWidth(380)
    emptyDesc:SetJustifyH("CENTER")
    history.empty = emptyState
    history.clearButton = clearHistory
    history.page = text(history, "", 10, C.dim)
    history.page:SetPoint("BOTTOM", 0, 12)
    history.prev = button(history, self.L.PREVIOUS, 92, 24)
    history.prev:SetPoint("BOTTOMLEFT", 94, 5)
    history.prev:SetScript("OnClick", function()
        history.listOffset = math.max(0, (history.listOffset or 0) - #history.rows)
        self:RefreshAuraHistoryPage()
    end)
    history.next = button(history, self.L.NEXT, 92, 24)
    history.next:SetPoint("BOTTOMRIGHT", -94, 5)
    history.next:SetScript("OnClick", function()
        history.listOffset = math.max(0, (history.listOffset or 0) + #history.rows)
        self:RefreshAuraHistoryPage()
    end)
    history:SetScript("OnMouseWheel", function(_, delta)
        local pageSize = #history.rows
        history.listOffset = math.max(0, (history.listOffset or 0) + (delta < 0 and pageSize or -pageSize))
        self:RefreshAuraHistoryPage()
    end)

    local scrollHint = CreateFrame("Frame", nil, frame)
    scrollHint:SetPoint("BOTTOMLEFT", 205, 64)
    scrollHint:SetPoint("BOTTOMRIGHT", -44, 64)
    scrollHint:SetHeight(18)
    solid(scrollHint, "BACKGROUND", C.panelDeep[1], C.panelDeep[2], C.panelDeep[3], 0.92)
    scrollHint.label = text(scrollHint, self.L.HELP_SCROLL_HINT, 10, C.dim)
    scrollHint.label:SetPoint("LEFT", 4, 0)
    scrollHint:Hide()
    self.optionsScrollHint = scrollHint

    local footerLine = solid(frame, "BORDER", 1, 1, 1, 0.06)
    footerLine:SetPoint("BOTTOMLEFT", 179, 62)
    footerLine:SetPoint("BOTTOMRIGHT", -1, 62)
    footerLine:SetHeight(1)
    -- Sur la meme rangee que les boutons, cette phrase passait sous
    -- « Reinitialiser cette page » et « Mode test » : trois pages sur cinq.
    -- Elle prend la ligne libre au-dessus d'eux.
    local footerText = text(frame, self.L.STATUS_READY, 10, C.dim)
    footerText:SetPoint("BOTTOMLEFT", 205, 46)
    footerText:SetWidth(420)
    footerText:SetJustifyH("LEFT")
    self.optionsStatusText = footerText
    local test = button(frame, localized("Mode test", "Test mode"), 126, 28, false)
    -- 156 pour le bouton + 20 de marge droite + 12 d'ecart entre les deux.
    test:SetPoint("BOTTOMRIGHT", -188, 14)
    test:SetScript("OnClick", function()
        self:ToggleTest()
        self.testModeFromOptions = self.testMode and true or nil
    end)
    self.testModeButton = test
    local reset = button(frame, self.L.RESET_POSITIONS, 156, 28)
    reset:SetPoint("BOTTOMRIGHT", -20, 14)
    reset:SetScript("OnClick", function() self:ResetPositions() end)
    local pageReset = button(frame, self.L.PAGE_RESET, 176, 28)
    pageReset:SetPoint("BOTTOMRIGHT", -350, 14)
    armConfirm(pageReset, self.L.PAGE_RESET, self.L.PAGE_RESET_ARMED, function()
        self:ResetOptionsPage(self.activeOptionsPage)
    end)
    attachHelp(pageReset, self.L.PAGE_RESET, self.L.TIP_PAGE_RESET)
    self.pageResetButton = pageReset

    -- Une seule zone de defilement pleine hauteur : deux barres sur la meme
    -- page se disputent la molette et on ne sait jamais laquelle repond.
    local help = CreateFrame("Frame", nil, content)
    help:SetAllPoints()
    self.optionsPages.help = help
    self.optionsPageHeights.help = 1320

    -- Cette page avait SA propre zone de defilement, imbriquee dans celle de
    -- la fenetre depuis que le contenu defile : deux barres se disputaient la
    -- meme molette. Elle n'en a plus. Le corps est un simple cadre, et c'est le
    -- defilement de la fenetre qui s'en occupe.
    local helpBody = CreateFrame("Frame", nil, help)
    helpBody:SetPoint("TOPLEFT", 0, -2)
    helpBody:SetSize(540, 1290)

    local function helpBlock(heading, body, y)
        local title = text(helpBody, heading, 12, C.section)
        title:SetPoint("TOPLEFT", 0, y)
        local line = solid(helpBody, "ARTWORK", 1, 1, 1, 0.07)
        line:SetPoint("TOPLEFT", 0, y - 18)
        line:SetWidth(540)
        line:SetHeight(1)
        local content = text(helpBody, body, 11, C.text)
        content:SetPoint("TOPLEFT", 0, y - 30)
        content:SetWidth(540)
        content:SetJustifyH("LEFT")
        content:SetSpacing(3)
        return content
    end

    helpBlock(self.L.HELP_SECTION_COMMANDS, self.L.HELP_COMMANDS_TEXT, 0)
    -- Neuf commandes de plus dans le bloc du haut : le depannage descend
    -- d'autant, sinon les deux blocs se recouvrent. Une liste sans hauteur
    -- posee n'est mesuree par aucun test -- elle se compte a la main.
    helpBlock(self.L.HELP_SECTION_TROUBLE, self.L.HELP_TROUBLE_TEXT, -600)

    local aboutTitle = text(helpBody, self.L.HELP_SECTION_ABOUT, 12, C.section)
    aboutTitle:SetPoint("TOPLEFT", 0, -990)
    local aboutLine = solid(helpBody, "ARTWORK", 1, 1, 1, 0.07)
    aboutLine:SetPoint("TOPLEFT", 0, -1008)
    aboutLine:SetWidth(540)
    aboutLine:SetHeight(1)
    local aboutVersion = text(helpBody, "Cleansive v" .. self.version .. "  -  Retail 12.1  -  "
        .. self.L.HELP_LICENSE, 11, C.text)
    aboutVersion:SetPoint("TOPLEFT", 0, -1020)
    local credits = text(helpBody, self.L.HELP_CREDITS, 11, C.dim)
    credits:SetPoint("TOPLEFT", 0, -1164)
    credits:SetWidth(540)
    credits:SetJustifyH("LEFT")
    credits:SetSpacing(3)
    local installWarning = text(helpBody, self.L.HELP_INSTALL_WARNING, 11, C.dim)
    installWarning:SetPoint("TOPLEFT", 0, -1224)
    installWarning:SetWidth(540)
    installWarning:SetJustifyH("LEFT")
    installWarning:SetSpacing(3)
    local reportLabel = text(helpBody, self.L.HELP_REPORT, 11, C.dim)
    reportLabel:SetPoint("TOPLEFT", 0, -1046)
    reportLabel:SetWidth(540)
    reportLabel:SetJustifyH("LEFT")

    -- Un addon ne peut pas ouvrir un navigateur. La seule chose honnete est de
    -- rendre l'adresse selectionnable pour que le joueur la copie.
    local reportBox = CreateFrame("EditBox", nil, helpBody)
    reportBox:SetSize(540, 24)
    reportBox:SetPoint("TOPLEFT", 0, -1086)
    reportBox:SetAutoFocus(false)
    reportBox:SetFontObject(ChatFontNormal)
    reportBox:SetTextInsets(6, 6, 0, 0)
    reportBox:SetText(REPORT_URL)
    reportBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    reportBox:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
    -- Ne restaurer que sur une saisie du joueur. Sans le test sur userInput, le
    -- SetText de restauration declenche a son tour OnTextChanged et le client
    -- part en boucle.
    reportBox:SetScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        box:SetText(REPORT_URL)
        box:HighlightText()
    end)
    self.reportURLBox = reportBox
    local reportBg = solid(helpBody, "BACKGROUND", C.panelDeep[1], C.panelDeep[2], C.panelDeep[3], 0.80)
    reportBg:SetPoint("TOPLEFT", reportBox, "TOPLEFT", 0, 0)
    reportBg:SetPoint("BOTTOMRIGHT", reportBox, "BOTTOMRIGHT", 0, 0)

    local diagButton = button(helpBody, self.L.HELP_DIAG_BUTTON, 190, 28)
    diagButton:SetPoint("TOPLEFT", 0, -1124)
    diagButton:SetScript("OnClick", function() self:ShowDiagnosticsCopy() end)

    local transferButton = button(helpBody, self.L.PROFILE_TRANSFER, 190, 28)
    transferButton:SetPoint("TOPLEFT", 204, -1124)
    transferButton:SetScript("OnClick", function() self:ShowProfileTransfer() end)

    self.optionIndex = {}
    for _, entry in ipairs(optionRegistry) do
        for pageKey, page in pairs(self.optionsPages) do
            if entry.parent == page then
                self.optionIndex[#self.optionIndex + 1] = {
                    page = pageKey, label = entry.label, help = entry.help,
                }
            end
        end
    end

    self:CreateListWindow()
    self:CreateFilterWindow()
    self:RefreshOptions()
    self:ShowOptionsPage("general")
end

function NS:ToggleOptions()
    if not self.optionsFrame then return end
    if self.optionsFrame:IsShown() then
        self.optionsFrame:Hide()
    else
        self.optionsFrame:Show()
    end
end

function NS:RefreshCellPreview()
    local preview = self.uxPreview
    if not preview then return end
    local colors = { { 0.92, 0.08, 0.08 }, { 0.08, 0.38, 0.96 }, { 1.00, 0.46, 0.02 } }
    local labels = {}
    for slot = 1, 3 do
        local _, _, short = self:ClickDescription(slot)
        labels[slot] = short or "—"
    end
    labels[4] = "—"
    local layoutMode = self.db.layoutMode or "GRID"
    -- Each mode caps the preview so the box cannot overflow, but the cap has
    -- to stay above the slider's lower half or the control looks broken:
    -- the vertical mode used to be pinned at 20 px and never moved at all.
    local cap = 30
    if layoutMode == "HORIZONTAL" then cap = 38
    elseif layoutMode == "VERTICAL" then cap = 26 end
    local previewSize = math.max(12, math.min(self:CellSize(), cap))
    local verticalStep = previewSize + 3
    -- The preview box is 78 px tall with a 5 px margin. Three cells at the
    -- vertical cap ran 11 px past the bottom, and nothing clips them: show only
    -- what fits, and let the labels follow the same rule as a real cell so the
    -- preview stops promising a layout the game will not draw.
    local previewRoom = 78 - 5
    local verticalFits = math.max(1, math.floor((previewRoom - previewSize) / verticalStep) + 1)
    local font = self.GetUXFont and self:GetUXFont()
    -- La case etait plafonnee mais ses textes etaient dimensionnes POUR le
    -- plafond : a 40 px reglés, une lettre calculee pour une case de 26
    -- recouvrait le nombre. L'apercu est une reduction de la vraie case, donc
    -- tout son contenu subit la meme echelle.
    local realSize = math.max(1, self:CellSize())
    local previewScale = previewSize / realSize
    local function scaled(role)
        local real = self:CellFontSize(role, realSize)
        return math.max(6, math.floor(real * previewScale + 0.5))
    end
    local inset = math.max(1, math.floor(3 * previewScale + 0.5))
    preview.scale, preview.hintFont, preview.countdownFont =
        previewScale, scaled("hint"), scaled("countdown")
    for index, cell in ipairs(preview.cells) do
        cell:ClearAllPoints()
        if font and cell.label and cell.label.SetFont then
            cell.label:SetFont(font, preview.hintFont, "")
            cell.cooldown:SetFont(font, preview.countdownFont, "")
            cell.label:ClearAllPoints()
            cell.label:SetPoint("TOPLEFT", inset, -inset)
        end
        if layoutMode == "VERTICAL" then
            cell:SetPoint("TOPLEFT", 24, -5 - ((index - 1) * verticalStep))
            cell:SetShown(index <= math.min(3, verticalFits))
        elseif layoutMode == "HORIZONTAL" then
            cell:SetPoint("LEFT", 14 + ((index - 1) * (previewSize + 7)), 0)
            cell:Show()
        else
            local col = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            cell:SetPoint("TOPLEFT", 28 + col * (previewSize + 8), -6 - row * (previewSize + 7))
            cell:Show()
        end
        if colors[index] then
            cell.bg:SetColorTexture(colors[index][1], colors[index][2], colors[index][3], 0.90)
            setEdges(cell.edges, colors[index][1], colors[index][2], colors[index][3], 1)
            cell.typeMark:SetColorTexture(colors[index][1], colors[index][2], colors[index][3], 1)
            cell.cooldown:SetText((self.db.showCooldown and index == 1) and "4.2" or "")
            if cell.duration and cell.duration.SetCooldown then
                local drawn = pcall(cell.duration.SetCooldown, cell.duration,
                    GetTime() - (index * 2), 18, 1)
                -- Un balayage a moitie pose est pire qu'aucun : il fait croire
                -- a un reglage qui ne marche pas.
                cell.duration:SetShown(drawn and true or false)
            end
        else
            cell.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], self.db.afflictedOnly and 0 or self.db.inactiveAlpha)
            setEdges(cell.edges, 1, 1, 1, self.db.afflictedOnly and 0 or 0.12)
            cell.typeMark:SetColorTexture(0, 0, 0, 0)
            cell.cooldown:SetText("")
            if cell.duration then cell.duration:Clear() end
        end
        cell:SetSize(previewSize, previewSize)
        cell.label:SetText(self.db.showClickHints and labels[index] or "")
    end
    local maps = {}
    for index = 1, 3 do
        local def = self.clickSpells and self.clickSpells[index]
        if def then
            local _, click = self:ClickDescription(index)
            maps[#maps + 1] = (click or "?") .. " : " .. def.name
        end
    end
    preview.durationLegend:SetText(self.L.PREVIEW_DURATION)
    preview.cooldownLegend:SetText("4.2  " .. self.L.PREVIEW_COOLDOWN)
    preview.mapping:SetText(#maps > 0 and table.concat(maps, "\n") or self.L.NO_CURE)
end

function NS:RefreshOptions()
    if not self.optionsFrame then return end
    if self.UpdateGridAnchorAppearance then self:UpdateGridAnchorAppearance() end
    for _, control in ipairs(self.optionChecks or {}) do control:Apply(self.db[control.key]) end
    for _, control in ipairs(self.optionSliders or {}) do control:Refresh() end
    if self.languageButton then
        self.languageButton:SetText(self.db.language == "frFR" and "Français" or "English")
    end
    if self.soundChannelButton then
        local channelLabels = {
            Master = self.L.SOUND_CHANNEL_MASTER,
            SFX = self.L.SOUND_CHANNEL_SFX,
            Dialog = self.L.SOUND_CHANNEL_DIALOG,
        }
        self.soundChannelButton:SetText(channelLabels[self.db.soundChannel] or self.db.soundChannel or "Master")
    end
    if self.growButton then self.growButton:SetText(growthLabel(self.db.grow)) end
    if self.layoutModeButton then self.layoutModeButton:SetText(layoutModeLabel(self.db.layoutMode)) end
    if self.profileLabel and self.GetActiveProfileLabel then self.profileLabel:SetText(self:GetActiveProfileLabel()) end
    if self.priorityKeyButton and not self.priorityKeyButton.capturing then
        self.priorityKeyButton:SetText(self.db.priorityKey ~= "" and self.db.priorityKey or self.L.NOT_BOUND)
    end
    if self.sortModeButton then
        self.sortModeButton:SetText(self.L["SORT_" .. tostring(self.db.sortMode or "GROUP")]
            or self.L.SORT_GROUP)
    end
    if self.nameWidthNote then
        local wanted = self.db.showNames and not self:CellShowsNames()
        self.nameWidthNote:SetText(wanted and string.format(self.L.NAME_TOO_SMALL, 16) or "")
    end
    if self.overviewEngineText then
        self.overviewEngineText:SetText(self:AuraEngineStateSentence())
    end
    if self.soundStateText then
        self.soundStateText:SetText(self:AuraSoundStateSentence())
    end
    if self.optionsStatusText then
        self.optionsStatusText:SetText(self:OptionsStatusText())
    end
    -- Un reglage qui ne s'applique pas ne doit pas rester la a suggerer qu'il
    -- s'applique. Le son coupe, tout ce qui le regle disparait.
    local soundOn = self.db and self.db.sound and true or false
    for _, control in ipairs(self.soundDependentControls or {}) do
        control:SetShown(soundOn)
    end
    for _, control in ipairs(self.raidGeometrySliders or {}) do
        control:SetEnabled(self.db and self.db.separateRaidSize and true or false)
    end
    if self.alertSoundButton then
        local chosen = self.db and self.db.alertSound or "DEFAULT"
        self.alertSoundButton:SetText(self.L["ALERT_SOUND_" .. chosen] or chosen)
    end
    if self.previewStateButton then
        self.previewStateButton:SetText(self:TestStateLabel())
    end
    for _, sizeButton in ipairs(self.previewSizeButtons or {}) do
        local selected = self.testMode and self.db.testUnits == sizeButton.previewCount
        sizeButton.uxAccentButton = selected and true or false
        local refreshStyle = sizeButton:GetScript("OnLeave")
        if refreshStyle then refreshStyle(sizeButton) end
    end
    if self.testModeButton then
        self.testModeButton.uxAccentButton = self.testMode and true or false
        self.testModeButton:SetText(self.testMode and self.L.TEST_MODE_ON or self.L.TEST_MODE_OFF)
        local refreshStyle = self.testModeButton:GetScript("OnLeave")
        if refreshStyle then refreshStyle(self.testModeButton) end
    end

    local orderIndex = {}
    for position, auraType in ipairs(self.db.typeOrder or {}) do orderIndex[auraType] = position end
    for index, row in ipairs(self.typeRows or {}) do
        local position = orderIndex[row.type] or index
        if row.frame then
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", 0, -58 - ((position - 1) * 50))
        end
        local typeEnabled = self.db.enabledTypes[row.type] ~= false
        row.check:SetChecked(typeEnabled)
        row.check:Apply()
        row.label:SetAlpha(typeEnabled and 1 or 0.42)
        local slot = self.typeToSlot and self.typeToSlot[row.type]
        local def = slot and self.clickSpells and self.clickSpells[slot]
        local manual = not def and self.manualTypeSpell and self.manualTypeSpell[row.type]
        local _, click, short = self:ClickDescription(slot)
        click = click or "—"
        local clickColor = CLICK_BADGE_COLORS[slot]
        local shortClick = short or (manual and "!" or "—")
        if row.badge then
            if clickColor and def then
                row.badge.bg:SetColorTexture(clickColor[1], clickColor[2], clickColor[3], 0.88)
                setEdges(row.badge.edges, clickColor[1], clickColor[2], clickColor[3], 1)
            else
                row.badge.bg:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.50)
                setEdges(row.badge.edges, 1, 1, 1, 0.08)
            end
            row.badge.label:SetText(shortClick)
        end
        row.mapping:SetText(def and (click .. "  -  " .. def.name)
            or (manual and string.format(self.L.MANUAL_ONLY, manual.name) or "—"))
        row.mapping:SetTextColor(1, 1, 1, (def or manual) and 0.72 or 0.34)
        setDirectionEnabled(row.up, position > 1)
        setDirectionEnabled(row.down, position < #self.typeRows)
    end

    if self.dispelClickLegend then
        local _, first = self:ClickDescription(1)
        local _, second = self:ClickDescription(2)
        local _, third = self:ClickDescription(3)
        self.dispelClickLegend:SetText(string.format(self.L.CLICK_LEGEND,
            first or "—", second or "—", third or "—"))
    end
    self:RefreshCellPreview()
    if self.RefreshClickBindings then self:RefreshClickBindings() end
    if self.RefreshAuraHistoryPage then self:RefreshAuraHistoryPage() end
end

function NS:CreateListWindow()
    local frame = CreateFrame("Frame", "CleansiveListFrame", UIParent)
    frame:SetSize(660, 590)
    fitToScreen(frame, 660, 590)
    frame:SetPoint("CENTER", 30, 0)
    self:RestoreWindowPosition(frame, "list")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouseWheel(true)
    addPanelBackground(frame)
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SaveWindowPosition(f, "list")
    end)
    frame:SetScript("OnMouseWheel", function(f, delta)
        local pageSize = #(f.rows or {})
        f.listOffset = math.max(0, (f.listOffset or 0) + (delta < 0 and pageSize or -pageSize))
        self:RefreshListWindow()
    end)
    frame:Hide()
    self.listFrame = frame

    frame.heading = title(frame, "", 22, -22, "GameFontNormalHuge")
    local close = button(frame, "×", 30, 26)
    close:SetPoint("TOPRIGHT", -14, -15)
    close:SetScript("OnClick", function() frame:Hide() end)

    local addTarget = button(frame, self.L.TARGET_ADD, 132, 28, true)
    addTarget:SetPoint("TOPLEFT", 22, -64)
    addTarget:SetScript("OnClick", function() self:AddTargetToList(self.currentListKind) end)
    local clear = button(frame, self.L.CLEAR, 90, 28)
    clear:SetPoint("LEFT", addTarget, "RIGHT", 10, 0)
    clear:SetScript("OnClick", function() self:ConfirmClearList(self.currentListKind) end)
    frame.clearButton = clear

    frame.help = text(frame, "", 11, C.dim)
    frame.help:SetPoint("TOPLEFT", 22, -103)
    frame.help:SetWidth(610)
    frame.help:SetJustifyH("LEFT")

    title(frame, string.upper(self.L.CLASS), 22, -132, "GameFontHighlightSmall")
    local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
    for index, class in ipairs(classes) do
        local classToken = class
        local label = getClassLabel(classToken)
        local control = button(frame, label, 82, 22)
        local col, rowIndex = (index - 1) % 7, math.floor((index - 1) / 7)
        control:SetPoint("TOPLEFT", 22 + col * 88, -152 - rowIndex * 26)
        control:SetScript("OnClick", function() self:AddListEntry(self.currentListKind, "CLASS", classToken, label) end)
    end

    title(frame, string.upper(self.L.GROUP), 22, -212, "GameFontHighlightSmall")
    for group = 1, 8 do
        local groupNumber = group
        local control = button(frame, tostring(groupNumber), 42, 22)
        control:SetPoint("TOPLEFT", 96 + (groupNumber - 1) * 48, -208)
        control:SetScript("OnClick", function() self:AddListEntry(self.currentListKind, "GROUP", groupNumber, self.L.GROUP .. " " .. groupNumber) end)
    end

    frame.rows = {}
    for index = 1, 10 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(616, 28)
        row:SetPoint("TOPLEFT", 22, -244 - (index - 1) * 29)
        local bg = solid(row, "BACKGROUND", 0, 0, 0, index % 2 == 0 and 0.20 or 0.10)
        bg:SetAllPoints()
        row.text = text(row, "", 12, C.text)
        row.text:SetPoint("LEFT", 10, 0)
        -- Les boutons sont passes de 32 a 36 de large : les decalages suivent,
        -- sinon « monter » recouvrait « descendre ».
        row.up = button(row, "", 36, 28)
        row.up:SetPoint("RIGHT", -86, 0)
        chevron(row.up, true)
        attachHelp(row.up, self.L.MOVE_UP, self.L.MOVE_UP)
        row.down = button(row, "", 36, 28)
        row.down:SetPoint("RIGHT", -46, 0)
        chevron(row.down, false)
        attachHelp(row.down, self.L.MOVE_DOWN, self.L.MOVE_DOWN)
        row.remove = button(row, "×", 32, 22)
        row.remove:SetPoint("RIGHT", -8, 0)
        attachHelp(row.remove, self.L.REMOVE, self.L.REMOVE)
        frame.rows[index] = row
    end
    frame.empty = title(frame, self.L.EMPTY, 30, -260, "GameFontHighlight")
    frame.empty:SetTextColor(1, 1, 1, 0.42)
    frame.page = text(frame, "", 10, C.dim)
    frame.page:SetPoint("BOTTOM", 0, 14)
    frame.prev = button(frame, self.L.PREVIOUS, 92, 24)
    frame.prev:SetPoint("BOTTOMLEFT", 190, 7)
    frame.prev:SetScript("OnClick", function()
        frame.listOffset = math.max(0, (frame.listOffset or 0) - #frame.rows)
        self:RefreshListWindow()
    end)
    frame.next = button(frame, self.L.NEXT, 92, 24)
    frame.next:SetPoint("BOTTOMRIGHT", -190, 7)
    frame.next:SetScript("OnClick", function()
        frame.listOffset = math.max(0, (frame.listOffset or 0) + #frame.rows)
        self:RefreshListWindow()
    end)
end

function NS:CreateFilterWindow()
    local frame = CreateFrame("Frame", "CleansiveFilterFrame", UIParent)
    frame:SetSize(560, 560)
    fitToScreen(frame, 560, 560)
    frame:SetPoint("CENTER", 60, 0)
    self:RestoreWindowPosition(frame, "filter")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouseWheel(true)
    addPanelBackground(frame)
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SaveWindowPosition(f, "filter")
    end)
    frame:SetScript("OnMouseWheel", function(f, delta)
        local pageSize = #(f.rows or {})
        f.listOffset = math.max(0, (f.listOffset or 0) + (delta < 0 and pageSize or -pageSize))
        self:RefreshFilterWindow()
    end)
    frame:Hide()
    self.filterFrame = frame

    title(frame, self.L.FILTERS, 22, -22, "GameFontNormalHuge")
    local close = button(frame, "×", 30, 26)
    close:SetPoint("TOPRIGHT", -14, -15)
    close:SetScript("OnClick", function() frame:Hide() end)

    local filterHelp = text(frame, self.L.FILTER_HELP, 11, C.dim)
    filterHelp:SetPoint("TOPLEFT", 22, -62)
    filterHelp:SetWidth(500)
    filterHelp:SetJustifyH("LEFT")
    title(frame, string.upper(self.L.FILTER_ID), 22, -94, "GameFontHighlightSmall")
    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(110, 26)
    edit:SetPoint("TOPLEFT", 22, -112)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetFont(fontPath(), 13, "")
    frame.edit = edit

    frame.combatOnly = false
    local mode = button(frame, self.L.FILTER_ALWAYS, 150, 26)
    mode:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    mode:SetScript("OnClick", function(control)
        frame.combatOnly = not frame.combatOnly
        control:SetText(frame.combatOnly and self.L.FILTER_COMBAT or self.L.FILTER_ALWAYS)
    end)
    local add = button(frame, self.L.FILTER_ADD, 126, 26, true)
    add:SetPoint("LEFT", mode, "RIGHT", 10, 0)
    add:SetScript("OnClick", function()
        self:AddFilter(tonumber(edit:GetText()), frame.combatOnly)
        edit:SetText("")
    end)
    edit:SetScript("OnEnterPressed", function()
        self:AddFilter(tonumber(edit:GetText()), frame.combatOnly)
        edit:SetText("")
        edit:ClearFocus()
    end)

    local targetAura = button(frame, self.L.FILTER_TARGET, 188, 26)
    targetAura:SetPoint("TOPLEFT", 22, -154)
    targetAura:SetScript("OnClick", function()
        local id = self:GetTargetDebuffID()
        if id then self:AddFilter(id, frame.combatOnly) else self:Print(self.L.FILTER_NONE) end
    end)

    frame.rows = {}
    for index = 1, 10 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(516, 28)
        row:SetPoint("TOPLEFT", 22, -200 - (index - 1) * 29)
        local bg = solid(row, "BACKGROUND", 0, 0, 0, index % 2 == 0 and 0.20 or 0.10)
        bg:SetAllPoints()
        row.text = text(row, "", 12, C.text)
        row.text:SetPoint("LEFT", 10, 0)
        row.remove = button(row, self.L.REMOVE, 76, 22)
        row.remove:SetPoint("RIGHT", -6, 0)
        frame.rows[index] = row
    end
    frame.empty = title(frame, self.L.EMPTY, 30, -216, "GameFontHighlight")
    frame.empty:SetTextColor(1, 1, 1, 0.42)
    frame.page = text(frame, "", 10, C.dim)
    frame.page:SetPoint("BOTTOM", 0, 14)
    frame.prev = button(frame, self.L.PREVIOUS, 92, 24)
    frame.prev:SetPoint("BOTTOMLEFT", 140, 7)
    frame.prev:SetScript("OnClick", function()
        frame.listOffset = math.max(0, (frame.listOffset or 0) - #frame.rows)
        self:RefreshFilterWindow()
    end)
    frame.next = button(frame, self.L.NEXT, 92, 24)
    frame.next:SetPoint("BOTTOMRIGHT", -140, 7)
    frame.next:SetScript("OnClick", function()
        frame.listOffset = math.max(0, (frame.listOffset or 0) + #frame.rows)
        self:RefreshFilterWindow()
    end)
end

-- Le remappage des clics n'avait AUCUN controle graphique : il fallait
-- connaitre « /cleansive clicks 3 SHIFT-2 », donc avoir lu le changelog. Une
-- fonction qu'aucun ecran ne montre n'est pas livree.
--
-- Et plutot qu'une liste deroulante de combinaisons, la case ecoute le geste :
-- le joueur presse ce qu'il veut poser, avec ses modificateurs. C'est le meme
-- chemin que le clic reel -- ClickBindingFromMouse -- donc ce qu'il capture
-- est exactement ce qui partira.
function NS:ShowClickBindings()
    local frame = self.clickBindingFrame
    if not frame then
        frame = CreateFrame("Frame", "CleansiveClickBindingFrame", UIParent)
        frame:SetSize(480, 290)
        frame:SetPoint("CENTER")
        self:RestoreWindowPosition(frame, "clicks")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(moved)
            moved:StopMovingOrSizing()
            self:SaveWindowPosition(moved, "clicks")
        end)
        addPanelBackground(frame)

        local accentBar = solid(frame, "BORDER", accent())
        accentBar:SetPoint("TOPLEFT")
        accentBar:SetPoint("TOPRIGHT")
        accentBar:SetHeight(2)

        frame.title = text(frame, self.L.CLICK_WINDOW_TITLE, 17, C.text)
        frame.title:SetPoint("TOPLEFT", 22, -20)
        local close = button(frame, "×", 34, 30)
        close:SetPoint("TOPRIGHT", -14, -13)
        close:SetScript("OnClick", function() frame:Hide() end)

        frame.hint = text(frame, self.L.CLICK_WINDOW_HINT, 11, C.dim)
        frame.hint:SetPoint("TOPLEFT", 22, -52)
        frame.hint:SetWidth(436)
        frame.hint:SetHeight(56)
        frame.hint:SetJustifyH("LEFT")

        frame.rows = {}
        for slot = 1, 3 do
            local row = CreateFrame("Frame", nil, frame)
            row:SetSize(436, 30)
            row:SetPoint("TOPLEFT", 22, -120 - ((slot - 1) * 36))
            solid(row, "BACKGROUND", 0, 0, 0, slot % 2 == 0 and 0.20 or 0.10):SetAllPoints()
            row.label = text(row, string.format(self.L.CLICK_SLOT_LABEL, slot), 12, C.text)
            row.label:SetPoint("LEFT", 10, 0)
            row.label:SetWidth(110)
            row.label:SetJustifyH("LEFT")
            row.current = text(row, "", 12, C.text)
            row.current:SetPoint("LEFT", 128, 0)
            row.current:SetWidth(150)
            row.current:SetJustifyH("LEFT")

            local capture = button(row, self.L.CLICK_CAPTURE, 140, 26)
            capture:SetPoint("RIGHT", -8, 0)
            -- « AnyUp » pour que le bouton reponde AUSSI au clic droit et aux
            -- boutons de pouce : un bouton ordinaire n'entend que le gauche,
            -- et deux tiers des combinaisons seraient restees inatteignables.
            if capture.RegisterForClicks then capture:RegisterForClicks("AnyUp") end
            capture:SetScript("OnClick", function(_, mouseButton)
                local binding = self:ClickBindingFromMouse(mouseButton)
                if not binding then return end
                local _, message = self:SetClickBinding(slot, binding)
                if message then self:Print(message) end
                self:RefreshClickBindings()
            end)
            row.capture = capture
            frame.rows[slot] = row
        end

        frame.reset = button(frame, self.L.CLICK_RESET, 240, 28)
        frame.reset:SetPoint("BOTTOMLEFT", 22, 20)
        frame.reset:SetScript("OnClick", function()
            local _, message = self:ResetClickBindings()
            if message then self:Print(message) end
            self:RefreshClickBindings()
        end)

        fitToScreen(frame, 480, 290)
        if type(UISpecialFrames) == "table" then
            UISpecialFrames[#UISpecialFrames + 1] = "CleansiveClickBindingFrame"
        end
        self.clickBindingFrame = frame
    end
    self:RefreshClickBindings()
    frame:Show()
end

function NS:RefreshClickBindings()
    local frame = self.clickBindingFrame
    if not frame then return end
    local fighting = InCombatLockdown and InCombatLockdown() and true or false
    for slot, row in ipairs(frame.rows) do
        local _, described, short = self:ClickDescription(slot)
        row.current:SetText(described and (short .. "   " .. described) or "—")
        row.capture:SetEnabled(not fighting)
    end
    frame.reset:SetEnabled(not fighting)
end

-- Read, show, then ask again. An import that lands on the first click is a
-- configuration lost with no way back, and the string usually comes from
-- someone else.
-- Une fenetre a part plutot qu'une section de plus dans les reglages : ces
-- boutons touchent des reglages PARTAGES entre personnages, et ce n'est pas le
-- meme geste que deplacer un curseur. La suppression est armee en deux clics,
-- comme les autres actions irreversibles de l'addon.
function NS:ShowProfileManager()
    local frame = self.profileManagerFrame
    if not frame then
        frame = CreateFrame("Frame", "CleansiveProfileManagerFrame", UIParent)
        frame:SetSize(520, 520)
        frame:SetPoint("CENTER")
        self:RestoreWindowPosition(frame, "profiles")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(moved)
            moved:StopMovingOrSizing()
            self:SaveWindowPosition(moved, "profiles")
        end)
        addPanelBackground(frame)

        local accentBar = solid(frame, "BORDER", accent())
        accentBar:SetPoint("TOPLEFT")
        accentBar:SetPoint("TOPRIGHT")
        accentBar:SetHeight(2)

        frame.title = text(frame, self.L.PROFILE_MANAGER, 17, C.text)
        frame.title:SetPoint("TOPLEFT", 22, -20)
        local close = button(frame, "×", 34, 30)
        close:SetPoint("TOPRIGHT", -14, -13)
        close:SetScript("OnClick", function() frame:Hide() end)

        frame.hint = text(frame, self.L.PROFILE_MANAGER_HINT, 11, C.dim)
        frame.hint:SetPoint("TOPLEFT", 22, -52)
        frame.hint:SetWidth(476)
        frame.hint:SetHeight(42)
        frame.hint:SetJustifyH("LEFT")

        -- Deux lignes, parce qu'il y a deux choses. Le profil CHARGE ici peut
        -- venir d'une surcharge de lieu ; le profil HABITUEL de la
        -- specialisation est celui que les boutons ci-dessous modifient. Une
        -- seule ligne melangeait les deux, et le chevron designait l'autre.
        frame.active = text(frame, "", 12, C.text)
        frame.active:SetPoint("TOPLEFT", 22, -102)
        frame.active:SetWidth(476)
        frame.active:SetHeight(14)
        frame.active:SetJustifyH("LEFT")

        frame.usual = text(frame, "", 11, C.dim)
        frame.usual:SetPoint("TOPLEFT", 22, -118)
        frame.usual:SetWidth(476)
        frame.usual:SetHeight(14)
        frame.usual:SetJustifyH("LEFT")

        -- Une saisie unique sert a creer ET a renommer : deux champs pour deux
        -- verbes qui prennent le meme argument auraient double la surface sans
        -- rien clarifier.
        -- Le fond de cette saisie etait PLUS SOMBRE que le panneau, et la case
        -- etait vide : elle etait donc litteralement invisible. Le texte d'a
        -- cote disait « saisissez un nom ci-dessus » en montrant du vide, et
        -- tout le reste de la fenetre attend qu'un profil existe -- donc rien
        -- ne repondait a rien. Meme motif que la zone de recherche de la barre
        -- laterale : un fond CLAIR, un cadre, et un texte d'invite.
        local nameHolder = CreateFrame("Frame", nil, frame)
        nameHolder:SetPoint("TOPLEFT", 22, -140)
        nameHolder:SetSize(300, 26)
        solid(nameHolder, "BACKGROUND", 1, 1, 1, 0.05):SetAllPoints()
        border(nameHolder, 0.18)
        frame.nameBox = CreateFrame("EditBox", nil, nameHolder)
        frame.nameBox:SetAllPoints()
        frame.nameBox:SetAutoFocus(false)
        frame.nameBox:SetFontObject(ChatFontNormal)
        frame.nameBox:SetTextInsets(6, 6, 0, 0)
        frame.nameBox:SetMaxLetters(32)
        frame.nameBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        frame.namePlaceholder = text(nameHolder, self.L.PROFILE_NAME_PLACEHOLDER, 12, C.dim)
        frame.namePlaceholder:SetPoint("LEFT", 7, 0)
        frame.nameBox:SetScript("OnTextChanged", function(box)
            frame.namePlaceholder:SetShown((box:GetText() or "") == "")
        end)

        local create = button(frame, self.L.PROFILE_CREATE, 140, 26)
        create:SetPoint("TOPLEFT", 332, -140)
        create:SetScript("OnClick", function()
            local ok, message = self:CreateNamedProfile(frame.nameBox:GetText())
            self:Print(message)
            if ok then frame.nameBox:SetText("") end
            self:RefreshProfileManager()
        end)
        frame.createButton = create

        frame.rows = {}
        for index = 1, 6 do
            local row = CreateFrame("Frame", nil, frame)
            row:SetSize(476, 30)
            row:SetPoint("TOPLEFT", 22, -180 - ((index - 1) * 34))
            solid(row, "BACKGROUND", 0, 0, 0, index % 2 == 0 and 0.20 or 0.10):SetAllPoints()
            row.label = text(row, "", 12, C.text)
            row.label:SetPoint("LEFT", 10, 0)
            row.label:SetWidth(210)
            row.label:SetJustifyH("LEFT")
            row.use = button(row, self.L.PROFILE_USE, 80, 22)
            row.use:SetPoint("LEFT", 226, 0)
            row.rename = button(row, self.L.PROFILE_RENAME, 90, 22)
            row.rename:SetPoint("LEFT", 312, 0)
            row.delete = button(row, self.L.PROFILE_DELETE, 68, 22)
            row.delete:SetPoint("LEFT", 408, 0)
            frame.rows[index] = row
        end

        -- Deux messages, deux places. Celui-ci remplace une liste vide et
        -- s'affiche donc a la place de la premiere rangee.
        frame.empty = text(frame, self.L.PROFILE_NONE, 11, C.dim)
        frame.empty:SetPoint("TOPLEFT", 22, -186)
        frame.empty:SetWidth(476)
        frame.empty:SetHeight(28)
        frame.empty:SetJustifyH("LEFT")

        -- Celui-la parle des profils qui ne tiennent pas dans la liste : il
        -- doit se poser SOUS la sixieme rangee. Reutiliser le meme texte le
        -- dessinait par-dessus le premier profil, exactement quand la liste est
        -- la plus chargee.
        frame.overflow = text(frame, "", 11, C.dim)
        frame.overflow:SetPoint("TOPLEFT", 22, -180 - (6 * 34) - 6)
        frame.overflow:SetWidth(476)
        frame.overflow:SetHeight(14)
        frame.overflow:SetJustifyH("LEFT")
        frame.overflow:Hide()

        -- Les surcharges de lieu et leur verrou n'existaient que par la
        -- commande « /cleansive profile env ». Une fonction qu'aucun ecran ne
        -- montre n'est pas livree : un joueur qui n'a pas lu le changelog ne
        -- pouvait pas la trouver. Un bouton par lieu, qui fait le tour des
        -- profils comme celui du son d'alerte fait le tour des sons.
        frame.environmentTitle = text(frame, self.L.PROFILE_ENVIRONMENT_TITLE, 11, C.section)
        frame.environmentTitle:SetPoint("TOPLEFT", 22, -400)
        frame.environmentTitle:SetWidth(476)
        frame.environmentTitle:SetHeight(14)
        frame.environmentTitle:SetJustifyH("LEFT")

        -- Quatre boutons grises sans un mot d'explication : le joueur essaie,
        -- rien ne repond, et rien ne dit pourquoi. Cette ligne le dit.
        frame.environmentNote = text(frame, "", 11, C.dim)
        frame.environmentNote:SetPoint("TOPLEFT", 22, -414)
        frame.environmentNote:SetWidth(476)
        frame.environmentNote:SetHeight(14)
        frame.environmentNote:SetJustifyH("LEFT")

        frame.environmentButtons = {}
        for index, place in ipairs(self.ENVIRONMENTS) do
            local control = button(frame, "", 112, 26)
            control:SetPoint("TOPLEFT", 22 + ((index - 1) * 118), -432)
            control:SetScript("OnClick", function()
                local _, message = self:CycleEnvironmentProfile(place)
                if message then self:Print(message) end
                self:RefreshProfileManager()
            end)
            frame.environmentButtons[place] = control
        end

        frame.lockButton = button(frame, "", 220, 28)
        frame.lockButton:SetPoint("BOTTOMLEFT", 254, 20)
        frame.lockButton:SetScript("OnClick", function()
            local ok, refusal = self:SetEnvironmentLocked(not self:EnvironmentLocked())
            if not ok and refusal then self:Print(refusal) end
            self:RefreshProfileManager()
        end)

        local own = button(frame, self.L.PROFILE_USE_OWN, 220, 28)
        own:SetPoint("BOTTOMLEFT", 22, 20)
        own:SetScript("OnClick", function()
            local _, message = self:UseOwnProfile()
            self:Print(message)
            self:RefreshProfileManager()
        end)
        frame.ownButton = own

        -- P3 de l'audit : ces deux fenetres n'etaient pas inscrites au systeme
        -- de mise a l'echelle. SetClampedToScreen borne la position, pas la
        -- taille : sur un petit espace logique elles depassaient sans se
        -- reduire, et ne reagissaient a aucun changement de resolution.
        fitToScreen(frame, 520, 520)
        if type(UISpecialFrames) == "table" then
            UISpecialFrames[#UISpecialFrames + 1] = "CleansiveProfileManagerFrame"
        end
        self.profileManagerFrame = frame
    end
    self:RefreshProfileManager()
    frame:Show()
end

function NS:RefreshProfileManager()
    local frame = self.profileManagerFrame
    if not frame then return end
    -- Trois choses distinctes, et deux d'entre elles portaient le meme nom.
    -- « Charge ici » tient compte du lieu ; « habituel » est ce que le chevron
    -- designe et ce que les boutons de cette fenetre modifient. Les confondre
    -- faisait repondre « X est maintenant utilise » a un clic qui ne changeait
    -- rien de ce que le joueur avait sous les yeux.
    frame.active:SetText(string.format(self.L.PROFILE_ACTIVE_HERE, self:GetActiveProfileLabel()))
    local names = self:NamedProfiles()
    local active = self:ActiveNamedProfile()
    frame.usual:SetText(string.format(self.L.PROFILE_USUAL, active or self.L.PROFILE_OWN_NAME))
    frame.empty:SetShown(#names == 0)
    for index, row in ipairs(frame.rows) do
        local name = names[index]
        row:SetShown(name ~= nil)
        if name then
            row.label:SetText((name == active and "> " or "") .. name)
            row.use:SetEnabled(name ~= active)
            row.use:SetScript("OnClick", function()
                local _, message = self:UseNamedProfile(name)
                self:Print(message)
                self:RefreshProfileManager()
            end)
            row.rename:SetScript("OnClick", function()
                local _, message = self:RenameNamedProfile(name, frame.nameBox:GetText())
                self:Print(message)
                self:RefreshProfileManager()
            end)
            armConfirm(row.delete, self.L.PROFILE_DELETE, self.L.PROFILE_DELETE_ARMED, function()
                local _, message = self:DeleteNamedProfile(name)
                self:Print(message)
                self:RefreshProfileManager()
            end)
        end
    end
    -- Ces trois boutons changent un profil, ce que le combat refuse. La logique
    -- metier refuse deja, donc la base ne peut pas etre abimee -- mais laisser
    -- un bouton actif qui repond par un refus est une promesse non tenue.
    local fighting = InCombatLockdown and InCombatLockdown() and true or false
    frame.ownButton:SetEnabled(active ~= nil and not fighting)
    for index, row in ipairs(frame.rows) do
        if names[index] then
            row.use:SetEnabled(names[index] ~= active and not fighting)
            row.delete:SetEnabled(not fighting)
        end
    end

    -- Les lieux : chaque bouton porte le profil que SON lieu chargera, et le
    -- verrou dit ce qu'il fera au prochain clic, pas ce qu'il a fait.
    for _, place in ipairs(self.ENVIRONMENTS) do
        local control = frame.environmentButtons[place]
        if control then
            local assigned = self:EnvironmentOverride(place)
            control:SetText((self.L["ENVIRONMENT_" .. string.upper(place)] or place)
                .. " : " .. (assigned or self.L.PROFILE_ENVIRONMENT_NONE))
            control:SetEnabled(#names > 0 and not fighting)
        end
    end
    frame.lockButton:SetText(self:EnvironmentLocked()
        and self.L.PROFILE_UNLOCK_PLACES or self.L.PROFILE_LOCK_PLACES)
    frame.lockButton:SetEnabled(not fighting)

    -- Un bouton dit ce que le PROCHAIN clic fera, pas l'etat courant : lu seul,
    -- « Deverrouiller les lieux » ne dit pas que les lieux sont verrouilles.
    -- Et quatre boutons grises sans explication ne se distinguent pas d'une
    -- fenetre en panne.
    if #names == 0 then
        frame.environmentNote:SetText(self.L.PROFILE_ENVIRONMENT_NEEDS)
    elseif self:EnvironmentLocked() then
        frame.environmentNote:SetText(self.L.PROFILE_ENVIRONMENT_IS_LOCKED)
    else
        frame.environmentNote:SetText("")
    end
    if frame.namePlaceholder then
        frame.namePlaceholder:SetShown((frame.nameBox:GetText() or "") == "")
    end

    -- Plus de six profils est un cas que la liste ne montre pas. Le dire plutot
    -- que de laisser croire qu'il n'y en a que six -- et le dire SOUS la liste.
    if #names > #frame.rows then
        frame.overflow:SetText(string.format(self.L.PROFILE_TOO_MANY, #names - #frame.rows))
    end
    frame.overflow:SetShown(#names > #frame.rows)
end

function NS:ShowProfileTransfer()
    local frame = self.profileTransferFrame
    if not frame then
        frame = CreateFrame("Frame", "CleansiveProfileTransferFrame", UIParent)
        frame:SetSize(700, 520)
        frame:SetPoint("CENTER")
        self:RestoreWindowPosition(frame, "transfer")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(moved)
            moved:StopMovingOrSizing()
            self:SaveWindowPosition(moved, "transfer")
        end)
        addPanelBackground(frame)

        local accentBar = solid(frame, "BORDER", accent())
        accentBar:SetPoint("TOPLEFT")
        accentBar:SetPoint("TOPRIGHT")
        accentBar:SetHeight(2)

        frame.title = text(frame, self.L.PROFILE_TRANSFER, 17, C.text)
        frame.title:SetPoint("TOPLEFT", 22, -20)
        local close = button(frame, "×", 34, 30)
        close:SetPoint("TOPRIGHT", -14, -13)
        close:SetScript("OnClick", function() frame:Hide() end)

        frame.exportHint = text(frame, self.L.PROFILE_EXPORT_HINT, 11, C.dim)
        frame.exportHint:SetPoint("TOPLEFT", 22, -52)
        frame.exportHint:SetWidth(650)
        frame.exportHint:SetJustifyH("LEFT")

        local exportScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        exportScroll:SetPoint("TOPLEFT", 22, -90)
        exportScroll:SetSize(628, 92)
        frame.exportBox = CreateFrame("EditBox", nil, exportScroll)
        frame.exportBox:SetMultiLine(true)
        frame.exportBox:SetAutoFocus(false)
        frame.exportBox:SetFontObject(ChatFontNormal)
        frame.exportBox:SetWidth(608)
        frame.exportBox:SetHeight(400)
        frame.exportBox:SetTextInsets(8, 8, 8, 8)
        frame.exportBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        exportScroll:SetScrollChild(frame.exportBox)

        frame.importHint = text(frame, self.L.PROFILE_IMPORT_HINT, 11, C.dim)
        frame.importHint:SetPoint("TOPLEFT", 22, -196)
        frame.importHint:SetWidth(650)
        frame.importHint:SetJustifyH("LEFT")

        local importScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        importScroll:SetPoint("TOPLEFT", 22, -228)
        importScroll:SetSize(628, 92)
        frame.importBox = CreateFrame("EditBox", nil, importScroll)
        frame.importBox:SetMultiLine(true)
        frame.importBox:SetAutoFocus(false)
        frame.importBox:SetFontObject(ChatFontNormal)
        frame.importBox:SetWidth(608)
        frame.importBox:SetHeight(400)
        frame.importBox:SetTextInsets(8, 8, 8, 8)
        frame.importBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        importScroll:SetScrollChild(frame.importBox)

        frame.result = text(frame, "", 11, C.text)
        frame.result:SetPoint("TOPLEFT", 22, -336)
        frame.result:SetWidth(650)
        frame.result:SetJustifyH("LEFT")
        frame.result:SetSpacing(2)

        frame.analyze = button(frame, self.L.IMPORT_ANALYZE, 190, 28)
        frame.analyze:SetPoint("BOTTOMLEFT", 22, 18)
        frame.apply = button(frame, self.L.IMPORT_CONFIRM, 220, 28, true)
        frame.apply:SetPoint("BOTTOMLEFT", 224, 18)
        -- Griser sans rien dire laisse chercher la panne. Trois mots suffisent.
        frame.applyHint = text(frame, self.L.IMPORT_COMBAT_HINT, 11, C.dim)
        frame.applyHint:SetPoint("LEFT", frame.apply, "RIGHT", 10, 0)
        frame.applyHint:Hide()

        frame.analyze:SetScript("OnClick", function()
            local analysis, reason = self:AnalyzeProfileImport(frame.importBox:GetText())
            frame.pendingImport = analysis
            if not analysis then
                frame.result:SetText(reason or "")
                frame.apply:Hide()
                return
            end
            -- P2 de l'audit du 30/08 : un import qui change presque tout
            -- produisait des dizaines de lignes dans un texte sans hauteur
            -- bornee. Il traversait les boutons de confirmation puis sortait
            -- de la fenetre. Huit lignes et un compte : le joueur doit pouvoir
            -- juger, pas tout relire -- et le bouton Appliquer doit rester
            -- visible, c'est lui qui engage.
            -- Borner le NOMBRE de lignes ne suffisait pas : un seul changement
            -- de filtre porte jusqu'a 500 identifiants de chaque cote, donc
            -- plusieurs milliers de caracteres sur une seule ligne logique.
            -- Le texte revenait a la ligne autant de fois qu'il fallait et
            -- repassait sous les boutons. Chaque valeur est donc rognee, et la
            -- liste des rejets aussi.
            local MAX_LINES, MAX_VALUE, MAX_REJECTED = 8, 60, 12
            local function short(value)
                value = tostring(value)
                if #value <= MAX_VALUE then return value end
                return value:sub(1, MAX_VALUE) .. self.L.IMPORT_TRUNCATED
            end
            local lines = {}
            for index, change in ipairs(analysis.changes) do
                if index > MAX_LINES then break end
                lines[#lines + 1] = string.format(self.L.IMPORT_CHANGE_LINE,
                    change.key, short(change.from), short(change.to))
            end
            if #analysis.changes > MAX_LINES then
                lines[#lines + 1] = string.format(self.L.IMPORT_MORE_CHANGES,
                    #analysis.changes - MAX_LINES)
            end
            if #lines == 0 then lines[1] = self.L.IMPORT_NO_CHANGE end
            if #analysis.rejected > 0 then
                local shown = {}
                for index, key in ipairs(analysis.rejected) do
                    if index > MAX_REJECTED then break end
                    -- Une SEULE cle inconnue peut peser plusieurs milliers de
                    -- caracteres : borner leur nombre ne suffisait pas.
                    shown[#shown + 1] = short(key)
                end
                local text = table.concat(shown, ", ")
                if #analysis.rejected > MAX_REJECTED then
                    text = text .. string.format(self.L.IMPORT_MORE_REJECTED,
                        #analysis.rejected - MAX_REJECTED)
                end
                lines[#lines + 1] = string.format(self.L.IMPORT_REJECTED, text)
            end
            frame.result:SetText(table.concat(lines, "\n"))
            frame.apply:SetShown(#analysis.changes > 0)
            self:RefreshProfileTransferState()
        end)

        frame.apply:SetScript("OnClick", function()
            if not frame.pendingImport then return end
            if not self:ApplyProfileImport(frame.pendingImport) then
                -- Refuse en combat : l'apercu RESTE, avec son bouton grise.
                -- L'effacer obligerait a recoller le texte apres le combat.
                self:RefreshProfileTransferState()
                return
            end
            frame.pendingImport = nil
            frame.apply:Hide()
            frame.exportBox:SetText(self:ExportProfile())
            frame.result:SetText("")
        end)

        fitToScreen(frame, 700, 520)
        if type(UISpecialFrames) == "table" then
            UISpecialFrames[#UISpecialFrames + 1] = "CleansiveProfileTransferFrame"
        end
        self.profileTransferFrame = frame
    end

    frame.exportBox:SetText(self:ExportProfile())
    frame.importBox:SetText("")
    frame.result:SetText("")
    frame.pendingImport = nil
    frame.apply:Hide()
    frame:Show()
    frame.exportBox:HighlightText()
end

function NS:RefreshOptionsStatus()
    if self.optionsStatusText then
        self.optionsStatusText:SetText(self:OptionsStatusText())
    end
    -- Le gestionnaire de profils grise ses boutons en combat, mais rien ne le
    -- rafraichissait a l'entree : ouvert avant le pull, il gardait des boutons
    -- actifs qui repondaient ensuite par un refus. Il est reveille ici, avec la
    -- ligne d'etat, par les deux evenements de combat.
    if self.profileManagerFrame and self.profileManagerFrame:IsShown() then
        self:RefreshProfileManager()
    end
    self:RefreshProfileTransferState()
end

-- Le bouton Appliquer d'un import suit le combat comme les boutons du
-- gestionnaire : la logique refuse deja, mais un bouton actif qui ne repond
-- que par un refus est une promesse non tenue. Analyser reste possible.
function NS:RefreshProfileTransferState()
    local frame = self.profileTransferFrame
    if not frame or not frame.apply then return end
    local fighting = InCombatLockdown and InCombatLockdown() and true or false
    frame.apply:SetEnabled(not fighting)
    if frame.applyHint then frame.applyHint:SetShown(fighting) end
end

-- Accent-insensitive, because a player types "reglage" and the label says
-- "réglage". Lua has no case folding for accents, so the pairs are listed.
local SEARCH_FOLD = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
    ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u",
    ["û"] = "u", ["ü"] = "u", ["ç"] = "c", ["’"] = "'",
}

function NS:FoldForSearch(value)
    value = string.lower(tostring(value or ""))
    for accented, plain in pairs(SEARCH_FOLD) do
        value = string.gsub(value, accented, plain)
    end
    return value
end

-- A result without its page is a dead end: the player finds the name and still
-- does not know where to go.
function NS:SearchOptions(query)
    local needle = self:FoldForSearch(query)
    if needle == "" then return {} end
    local results = {}
    for _, entry in ipairs(self.optionIndex or {}) do
        local haystack = self:FoldForSearch(entry.label) .. " " .. self:FoldForSearch(entry.help)
        if string.find(haystack, needle, 1, true) then
            results[#results + 1] = {
                page = entry.page,
                label = entry.label,
                pageLabel = self.L["PAGE_" .. string.upper(entry.page) .. "_SHORT"] or entry.page,
            }
        end
        if #results >= 8 then break end
    end
    return results
end

function NS:RefreshOptionsSearch(query)
    local panel = self.optionsSearchResults
    if not panel then return end
    if not query or query == "" then
        panel:Hide()
        return
    end
    local found = self:SearchOptions(query)
    panel.empty:SetShown(#found == 0)
    for index, row in ipairs(panel.rows) do
        local entry = found[index]
        if entry then
            row:SetText(string.format(self.L.SEARCH_RESULT, entry.pageLabel, entry.label))
            row:SetScript("OnClick", function()
                self:ShowOptionsPage(entry.page)
                if self.optionsSearchBox then
                    self.optionsSearchBox:SetText("")
                    self.optionsSearchBox:ClearFocus()
                end
            end)
            row:Show()
        else
            row:Hide()
        end
    end
    panel:Show()
end
