local _, NS = ...

local GROW_VALUES = { "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP" }
local LAYOUT_VALUES = { "GRID", "HORIZONTAL", "VERTICAL" }

function NS:CycleGrowth()
    local current = 1
    for index, value in ipairs(GROW_VALUES) do
        if value == self.db.grow then current = index break end
    end
    self.db.grow = GROW_VALUES[(current % #GROW_VALUES) + 1]
    self:LayoutButtons()
    self:RefreshOptions()
end

function NS:CycleLayoutMode()
    local current = 1
    for index, value in ipairs(LAYOUT_VALUES) do
        if value == self.db.layoutMode then current = index break end
    end
    self.db.layoutMode = LAYOUT_VALUES[(current % #LAYOUT_VALUES) + 1]
    self:LayoutButtons()
    self:RefreshOptions()
end

function NS:MoveType(dispelType, direction)
    local index
    for position, value in ipairs(self.db.typeOrder) do
        if value == dispelType then index = position break end
    end
    if not index then return end
    local other = index + direction
    if not self.db.typeOrder[other] then return end
    self.db.typeOrder[index], self.db.typeOrder[other] = self.db.typeOrder[other], self.db.typeOrder[index]
    self:UpdateSpells()
    self:RefreshAll(true)
end

function NS:ShowList(kind)
    if not self.listFrame then return end
    local nextKind = kind == "skip" and "skip" or "priority"
    if self.currentListKind ~= nextKind then self.listFrame.listOffset = 0 end
    self.currentListKind = nextKind
    self:RefreshListWindow()
    self.listFrame:Show()
end

function NS:ConfirmClearList(kind)
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:ClearList(kind)
        return
    end
    local key = "CLEANSIVE_CONFIRM_CLEAR"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = "%s",
            button1 = ACCEPT,
            button2 = CANCEL,
            OnAccept = function(_, data)
                if data and data.kind then NS:ClearList(data.kind) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    local label = kind == "skip" and self.L.SKIP or self.L.PRIORITY
    StaticPopup_Show(key, string.format(self.L.CONFIRM_CLEAR, label), nil, { kind = kind })
end

function NS:RefreshListWindow()
    if not self.listFrame or not self.currentListKind then return end
    local list = self.db[self.currentListKind]
    local pageSize = #self.listFrame.rows
    local pages = math.max(1, math.ceil(#list / math.max(1, pageSize)))
    local maxOffset = (pages - 1) * pageSize
    self.listFrame.listOffset = math.max(0, math.min(self.listFrame.listOffset or 0, maxOffset))
    local offset = self.listFrame.listOffset
    self.listFrame.heading:SetText(self.currentListKind == "skip" and self.L.SKIP or self.L.PRIORITY)
    if self.listFrame.help then
        self.listFrame.help:SetText(self.currentListKind == "skip" and self.L.LIST_SKIP_HELP or self.L.LIST_PRIORITY_HELP)
    end
    self.listFrame.empty:SetShown(#list == 0)
    for index, row in ipairs(self.listFrame.rows) do
        local rowIndex = offset + index
        local entry = list[rowIndex]
        if entry then
            local prefix = entry.kind == "CLASS" and self.L.CLASS or (entry.kind == "GROUP" and self.L.GROUP or self.L.PLAYER)
            row.text:SetText(rowIndex .. ".  " .. prefix .. " — " .. tostring(entry.label or entry.value))
            row.up:SetScript("OnClick", function() self:MoveListEntry(self.currentListKind, rowIndex, -1) end)
            row.down:SetScript("OnClick", function() self:MoveListEntry(self.currentListKind, rowIndex, 1) end)
            row.remove:SetScript("OnClick", function() self:RemoveListEntry(self.currentListKind, rowIndex) end)
            self:SetDirectionEnabled(row.up, rowIndex > 1)
            self:SetDirectionEnabled(row.down, rowIndex < #list)
            row:Show()
        else
            row:Hide()
        end
    end
    -- Meme regle que l'historique : une pagination d'une seule page est du
    -- mobilier, et vider une liste vide ne fait rien.
    local paged = pages > 1
    if self.listFrame.page then
        local page = math.floor(offset / pageSize) + 1
        self.listFrame.page:SetText(string.format(self.L.PAGE, page, pages))
        self.listFrame.page:SetShown(paged)
    end
    if self.listFrame.prev then
        self.listFrame.prev:SetShown(paged)
        self.listFrame.prev:SetEnabled(offset > 0)
    end
    if self.listFrame.next then
        self.listFrame.next:SetShown(paged)
        self.listFrame.next:SetEnabled(offset < maxOffset)
    end
    if self.listFrame.clearButton then self.listFrame.clearButton:SetEnabled(#list > 0) end
end

function NS:AddFilter(spellID, combatOnly)
    spellID = tonumber(spellID)
    if not spellID then return end
    if combatOnly then
        self.db.ignoredCombat[spellID] = true
        self.db.ignoredAlways[spellID] = nil
    else
        self.db.ignoredAlways[spellID] = true
        self.db.ignoredCombat[spellID] = nil
    end
    self:Print(self.L.FILTER_ADDED, spellID, combatOnly and self.L.FILTER_COMBAT or self.L.FILTER_ALWAYS)
    self:RefreshFilterWindow()
    self:RefreshAuraCandidateFilters()
    self:RefreshAll(true)
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("filters updated") end
    if self.RefreshAuraHistoryPage then self:RefreshAuraHistoryPage() end
end

function NS:RemoveFilter(spellID)
    self.db.ignoredAlways[spellID] = nil
    self.db.ignoredAlways[tostring(spellID)] = nil
    self.db.ignoredCombat[spellID] = nil
    self.db.ignoredCombat[tostring(spellID)] = nil
    self:Print(self.L.FILTER_REMOVED, spellID)
    self:RefreshFilterWindow()
    self:RefreshAuraCandidateFilters()
    self:RefreshAll(true)
    if self.RequestAuraSoundRefresh then self:RequestAuraSoundRefresh("filters updated") end
    if self.RefreshAuraHistoryPage then self:RefreshAuraHistoryPage() end
end

function NS:GetAuraHistoryEntries()
    local entries = {}
    local history, order = self:GetAuraHistory()
    for index = #order, 1, -1 do
        local id = order[index]
        local record = history[id] or history[tostring(id)]
        if record then
            if type(record) == "string" then record = { name = record } end
            entries[#entries + 1] = {
                id = tonumber(id) or id,
                name = record.name,
                auraType = record.auraType,
                place = record.place,
                instanceID = record.instanceID,
            }
        end
    end
    return entries
end

function NS:ToggleHistoryFilter(spellID)
    if self.db.ignoredAlways[spellID] or self.db.ignoredAlways[tostring(spellID)]
        or self.db.ignoredCombat[spellID] or self.db.ignoredCombat[tostring(spellID)] then
        self:RemoveFilter(spellID)
    else
        self:AddFilter(spellID, false)
    end
end

function NS:ClearAuraHistory()
    local history, order = self:GetAuraHistory()
    wipe(history)
    wipe(order)
    self:RefreshAuraHistoryPage()
    self:Print(self.L.HISTORY_CLEARED)
end

function NS:ConfirmClearAuraHistory()
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:ClearAuraHistory()
        return
    end
    local key = "CLEANSIVE_CONFIRM_CLEAR_HISTORY"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = "%s",
            button1 = ACCEPT,
            button2 = CANCEL,
            OnAccept = function() NS:ClearAuraHistory() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show(key, self.L.HISTORY_CONFIRM_CLEAR)
end

function NS:RefreshAuraHistoryPage()
    local page = self.auraHistoryPage
    if not page then return end
    local entries = self:GetAuraHistoryEntries()
    local pageSize = #(page.rows or {})
    local pages = math.max(1, math.ceil(#entries / math.max(1, pageSize)))
    local maxOffset = (pages - 1) * pageSize
    page.listOffset = math.max(0, math.min(page.listOffset or 0, maxOffset))
    local offset = page.listOffset
    page.empty:SetShown(#entries == 0)
    for index, row in ipairs(page.rows or {}) do
        local entry = entries[offset + index]
        if entry then
            local id = entry.id
            local ignored = self.db.ignoredAlways[id] or self.db.ignoredAlways[tostring(id)]
                or self.db.ignoredCombat[id] or self.db.ignoredCombat[tostring(id)]
            local typeLabel = entry.auraType and ("  -  " .. tostring(self:GetTypeLabel(entry.auraType))) or ""
            local placeLabel = entry.place and ("  -  " .. string.format(self.L.HISTORY_PLACE, tostring(entry.place))) or ""
            row.label:SetText(tostring(entry.name or self.L.UNKNOWN) .. "  -  " .. tostring(id)
                .. typeLabel .. placeLabel)
            row.action:SetText(ignored and self.L.HISTORY_UNIGNORE or self.L.HISTORY_IGNORE)
            row.action:SetScript("OnClick", function() self:ToggleHistoryFilter(id) end)
            row:Show()
        else
            row:Hide()
        end
    end
    -- « Page 1 sur 1 » entre deux boutons eteints n'est pas une pagination,
    -- c'est du mobilier. Elle n'apparait qu'a partir de deux pages.
    local paged = pages > 1
    if page.page then
        local current = math.floor(offset / math.max(1, pageSize)) + 1
        page.page:SetText(string.format(self.L.PAGE, current, pages))
        page.page:SetShown(paged)
    end
    if page.prev then
        page.prev:SetShown(paged)
        page.prev:SetEnabled(offset > 0)
    end
    if page.next then
        page.next:SetShown(paged)
        page.next:SetEnabled(offset < maxOffset)
    end
    -- Vider un historique vide ne fait rien : le bouton ne doit pas se
    -- presenter comme actif.
    if page.clearButton then page.clearButton:SetEnabled(#entries > 0) end
end

function NS:GetTargetDebuffID()
    if not UnitExists("target") or not C_UnitAuras or not C_UnitAuras.GetDebuffDataByIndex then return nil end
    for index = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, "target", index, "HARMFUL")
        if not ok or not aura then break end
        local spellID = aura.spellId
        if self:CanAccess(spellID) and spellID then return spellID end
    end
end

function NS:ShowFilters()
    if not self.filterFrame then return end
    self:RefreshFilterWindow()
    self.filterFrame:Show()
end

function NS:RefreshFilterWindow()
    if not self.filterFrame then return end
    local filters = {}
    for id in pairs(self.db.ignoredAlways) do
        filters[#filters + 1] = { id = tonumber(id) or id, mode = self.L.FILTER_ALWAYS }
    end
    for id in pairs(self.db.ignoredCombat) do
        filters[#filters + 1] = { id = tonumber(id) or id, mode = self.L.FILTER_COMBAT }
    end
    table.sort(filters, function(a, b)
        local aNumber, bNumber = tonumber(a.id), tonumber(b.id)
        if aNumber and bNumber and aNumber ~= bNumber then return aNumber < bNumber end
        if aNumber and not bNumber then return true end
        if bNumber and not aNumber then return false end
        return tostring(a.id) < tostring(b.id)
    end)
    local pageSize = #self.filterFrame.rows
    local pages = math.max(1, math.ceil(#filters / math.max(1, pageSize)))
    local maxOffset = (pages - 1) * pageSize
    self.filterFrame.listOffset = math.max(0, math.min(self.filterFrame.listOffset or 0, maxOffset))
    local offset = self.filterFrame.listOffset
    for index, row in ipairs(self.filterFrame.rows) do
        local filter = filters[offset + index]
        if filter then
            local filterID = filter.id
            local history = self:GetAuraHistory()
            local record = history[filter.id] or history[tostring(filter.id)]
            local name = type(record) == "table" and record.name or record
            if not name and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(filter.id) end
            row.text:SetText(tostring(filter.id) .. "  —  " .. tostring(name or self.L.UNKNOWN) .. "  (" .. filter.mode .. ")")
            row.remove:SetScript("OnClick", function() self:RemoveFilter(filterID) end)
            row:Show()
        else
            row:Hide()
        end
    end
    local paged = pages > 1
    if self.filterFrame.page then
        local page = math.floor(offset / pageSize) + 1
        self.filterFrame.page:SetText(string.format(self.L.PAGE, page, pages))
        self.filterFrame.page:SetShown(paged)
    end
    if self.filterFrame.empty then self.filterFrame.empty:SetShown(#filters == 0) end
    if self.filterFrame.prev then
        self.filterFrame.prev:SetShown(paged)
        self.filterFrame.prev:SetEnabled(offset > 0)
    end
    if self.filterFrame.next then
        self.filterFrame.next:SetShown(paged)
        self.filterFrame.next:SetEnabled(offset < maxOffset)
    end
end

-- #196 : a list of a hundred lines is unusable as a bug report unless it can
-- leave the game in one block. Same shape as the diagnostic report, and the
-- place travels with the ID so the reader can go and look.
function NS:BuildAuraHistoryReport()
    local lines = { "Cleansive affliction history" }
    for _, entry in ipairs(self:GetAuraHistoryEntries()) do
        local parts = { tostring(entry.id), tostring(entry.name or "?") }
        if entry.auraType then parts[#parts + 1] = tostring(entry.auraType) end
        if entry.instanceID then
            parts[#parts + 1] = "instance=" .. tostring(entry.instanceID)
        elseif entry.place then
            parts[#parts + 1] = "place=" .. tostring(entry.place)
        end
        lines[#lines + 1] = table.concat(parts, " | ")
    end
    return table.concat(lines, "\n")
end
