local _, ns = ...
local Window = ns.Window
local Panel = {}
ns.BossPanel = Panel

-- Right-side boss panel inside the map view: click a boss pin -> that boss's loot. Items are keyed by numeric
-- itemID (LootData.lua). Icons/names/quality come from the client's own item APIs; the hover tooltip is Blizzard's
-- GameTooltip, so stats are never re-typed here. Uncached items are requested and the row updates when the client
-- answers (GET_ITEM_INFO_RECEIVED); until then the row shows the dataset name and a static icon.
local ROW_HEIGHT = 38
local PLACEHOLDER_ICON = "Interface/Icons/INV_Misc_QuestionMark"
local QUALITY_RGB = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }

local function Label(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text or "")
    return label
end

-- ---- item data (guarded; never errors if an API is missing or the item is uncached) ----
local function ItemAPI(name)
    return ns.Field(C_Item, name) or _G[name]
end

-- Static item data (works for any valid itemID even when not cached): icon, equip slot, subtype.
function Panel:Instant(itemID)
    local probe = ns.Probe(ItemAPI("GetItemInfoInstant"), itemID)
    local values = probe.values
    if probe.status ~= "ok" then return {} end
    return { subType = ns.IsReadable(values[3]) and type(values[3]) == "string" and values[3] or nil,
        equipLoc = ns.IsReadable(values[4]) and type(values[4]) == "string" and values[4] or nil,
        icon = ns.IsReadable(values[5]) and values[5] or nil }
end

-- Cached item data: name and quality, or nil when the client has not loaded it yet.
function Panel:Cached(itemID)
    local probe = ns.Probe(ItemAPI("GetItemInfo"), itemID)
    local values = probe.values
    if probe.status ~= "ok" or type(values[1]) ~= "string" then return nil end
    return { name = values[1], quality = ns.IsNumber(values[3]) and values[3] or nil,
        icon = ns.IsReadable(values[10]) and values[10] or nil }
end

function Panel:Request(itemID)
    self.requested = self.requested or {}
    if self.requested[itemID] then return end
    self.requested[itemID] = true
    ns.Probe(ItemAPI("RequestLoadItemDataByID"), itemID)
end

local function EquipText(instant)
    local text = instant.equipLoc and instant.equipLoc ~= "" and _G[instant.equipLoc] or nil
    if type(text) ~= "string" then text = nil end
    if text and instant.subType and instant.subType ~= "" and instant.subType ~= text then return text .. " - " .. instant.subType end
    return text or instant.subType or ""
end

-- ---- frame ----
function Panel:Create()
    if self.frame then return end
    local window = ns.Window
    local panel = CreateFrame("Frame", nil, window.mapArea)
    panel:SetPoint("TOPRIGHT", window.mapArea, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", window.mapArea, "BOTTOMRIGHT", 0, 0)
    panel:SetWidth(280)
    panel:SetFrameLevel(window.mapArea:GetFrameLevel() + 60)
    panel:EnableMouse(true) -- clicks on the panel never fall through to the map
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.04, 0.055, 0.08, 0.96)
    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    edge:SetWidth(1)
    edge:SetColorTexture(0.3, 0.4, 0.55, 1)
    self.title = Label(panel, "GameFontNormalLarge", "")
    self.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    self.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -70, -12)
    self.title:SetJustifyH("LEFT")
    self.subtitle = Label(panel, "GameFontDisableSmall", "")
    self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
    self.subtitle:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, panel)
    close:SetSize(64, 22)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -10)
    close:SetFrameLevel(panel:GetFrameLevel() + 20)
    local closeBackground = close:CreateTexture(nil, "BACKGROUND")
    closeBackground:SetAllPoints()
    closeBackground:SetColorTexture(0.16, 0.22, 0.3, 1)
    local closeLabel = Label(close, "GameFontNormalSmall", "< Bosses")
    closeLabel:SetPoint("CENTER")
    close:SetScript("OnClick", function() window:CloseBoss() end)
    close:SetScript("OnEnter", function() closeBackground:SetColorTexture(0.22, 0.33, 0.45, 1) end)
    close:SetScript("OnLeave", function() closeBackground:SetColorTexture(0.16, 0.22, 0.3, 1) end)
    self.header = Label(panel, "GameFontNormalSmall", "LOOT")
    self.header:SetTextColor(0.55, 0.65, 0.8)
    self.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -56)
    self.message = Label(panel, "GameFontHighlight", "")
    self.message:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -80)
    self.message:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -80)
    self.message:SetJustifyH("LEFT")
    self.note = Label(panel, "GameFontDisableSmall", "")
    self.note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 10)
    self.note:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    self.note:SetJustifyH("LEFT")
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -76)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 30)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(260, 100)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(_, delta) self:ScrollBy(-delta * ROW_HEIGHT) end)
    self.scroll, self.child, self.rows = scroll, child, {}
    -- Clicking empty map closes the panel (sits above the map tiles, below the pins).
    local catcher = CreateFrame("Frame", nil, window.renderer.canvas)
    catcher:SetAllPoints(window.renderer.canvas)
    catcher:SetFrameLevel(window.renderer.canvas:GetFrameLevel() + 4)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseUp", function() window:CloseBoss() end)
    catcher:Hide()
    self.catcher = catcher
    self.frame = panel
    panel:Hide()
end

function Panel:ScrollBy(amount)
    local _, viewHeight = self.scroll:GetSize()
    local maximum = math.max(0, (self.child:GetHeight() or 0) - (viewHeight or 0))
    self.scroll:SetVerticalScroll(math.max(0, math.min(maximum, (self.scroll:GetVerticalScroll() or 0) + amount)))
end

function Panel:Layout()
    if not self.frame then return end
    local width = ns.Window.mapArea:GetWidth()
    width = ns.IsNumber(width) and math.max(220, math.min(300, width * 0.4)) or 280
    self.frame:SetWidth(width)
    self.child:SetWidth(math.max(120, width - 12))
end

local function MakeRow(self, index)
    local row = CreateFrame("Button", nil, self.child)
    row:SetHeight(ROW_HEIGHT)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.background:SetColorTexture(0.08, 0.11, 0.16, 1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = Label(row, "GameFontHighlight", "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.detail = Label(row, "GameFontDisableSmall", "")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function()
        row.background:SetColorTexture(0.15, 0.22, 0.32, 1)
        local tooltip = _G.GameTooltip
        if tooltip and row.itemID then
            tooltip:SetOwner(row, "ANCHOR_LEFT")
            -- Blizzard's own item tooltip (stats, binding, level...) - not re-created by the addon.
            if type(tooltip.SetItemByID) == "function" then tooltip:SetItemByID(row.itemID)
            elseif type(tooltip.SetHyperlink) == "function" then tooltip:SetHyperlink("item:" .. row.itemID) end
            tooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        row.background:SetColorTexture(0.08, 0.11, 0.16, 1)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    self.rows[index] = row
    return row
end

-- Fill one row from whatever the client knows right now.
function Panel:FillRow(row)
    local item = row.item
    if item.header then -- section label row (no item, no tooltip)
        row.itemID = nil
        row.icon:SetTexture(nil)
        row.name:SetText(item.header)
        row.name:SetTextColor(0.55, 0.65, 0.8)
        row.detail:SetText(item.sub or "")
        return
    end
    local instant, cached = self:Instant(item.itemID), self:Cached(item.itemID)
    if not cached then self:Request(item.itemID) end
    row.itemID = item.itemID
    row.icon:SetTexture((cached and cached.icon) or instant.icon or PLACEHOLDER_ICON)
    row.name:SetText((cached and cached.name) or item.name or ("Item " .. item.itemID))
    local color = cached and cached.quality and QUALITY_RGB[cached.quality] or { 0.7, 0.7, 0.7 }
    row.name:SetTextColor(color[1], color[2], color[3])
    row.detail:SetText(EquipText(instant))
end

function Panel:Show(bossID, name, dungeon)
    self:Create()
    self:Layout()
    local data = ns.BossLoot and ns.BossLoot[bossID]
    self.bossID = bossID
    self.title:SetText(name or "Boss")
    self.subtitle:SetText(dungeon or "")
    for _, row in ipairs(self.rows) do row:Hide() end
    local entries = {}
    for _, item in ipairs(data and data.items or {}) do entries[#entries + 1] = item end
    local seen = ns.SeenLoot and ns.SeenLoot:ForBoss(bossID) or {}
    if #seen > 0 then
        entries[#entries + 1] = { header = "SEEN BY YOU", sub = "Looted by this character; not verified" }
        for _, item in ipairs(seen) do entries[#entries + 1] = item end
    end
    if #entries > 0 then
        self.message:SetText("")
        for index, item in ipairs(entries) do
            local row = self.rows[index] or MakeRow(self, index)
            row.item = item
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 4))
            row:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", 0, -(index - 1) * (ROW_HEIGHT + 4))
            self:FillRow(row)
            row:Show()
        end
        self.child:SetHeight(#entries * (ROW_HEIGHT + 4))
        self.note:SetText(data and data.partial and "Additional drops are not yet verified." or "")
        self.scroll:Show()
        self.scroll:SetVerticalScroll(0)
    else
        self.message:SetText("No verified loot yet")
        self.message:SetTextColor(0.7, 0.7, 0.7)
        self.note:SetText("Items you loot from this boss will appear here.")
        self.scroll:Hide()
    end
    self.frame:Show()
    self.catcher:Show()
    if ns.BossList then ns.BossList:Refresh() end -- the boss table gives way to the loot panel
end

function Panel:Hide()
    if not self.frame then return end
    self.frame:Hide()
    self.catcher:Hide()
    self.bossID = nil
    if _G.GameTooltip then _G.GameTooltip:Hide() end
    if ns.BossList then ns.BossList:Refresh() end -- back to the boss table (only when a dungeon map is showing)
end

-- GET_ITEM_INFO_RECEIVED: refresh the rows for that item (success may be false for invalid items; rows keep their fallback).
function Panel:OnItemInfo(itemID)
    if not self.frame or not self.frame:IsShown() then return end
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.item and not row.item.header and (itemID == nil or row.item.itemID == itemID) then self:FillRow(row) end
    end
end

-- ---- Window integration ----
function Window:SelectBoss(bossID, name)
    if not (self.view == "map" and self.dungeonID and ns.IsID(bossID)) then return end
    self.selectedBoss = { id = bossID, dungeonID = self.dungeonID }
    local state = self.lastState
    Panel:Show(bossID, name, state and state.instanceName)
end

function Window:CloseBoss()
    self.selectedBoss = nil
    Panel:Hide()
end

-- Called after every map render: a selection never outlives its dungeon, floor or visibility.
function Window:ValidateBoss()
    local selected = self.selectedBoss
    if not selected then return end
    local keep = false
    if self.view == "map" and selected.dungeonID == self.dungeonID then
        local data = ns.MapMarkers:Get(self.dungeonID)
        if self.renderer and self.renderer.overlay and self.renderer.overlay:HasBoss(selected.id) then keep = true end
        for _, boss in ipairs(data and data.bosses or {}) do
            -- opened from the boss table: a boss that is not placed on any floor has no pin to lose, so it stays
            if boss.id == selected.id and not (ns.MapMarkers:ValidPoint(boss) and ns.MapMarkers:Visible(boss)) then keep = true end
            if boss.id == selected.id and (boss.floor or 1) == self.floor and ns.MapMarkers:Visible(boss)
                and data.layouts and data.layouts[boss.floor or 1] == ns.WMOComposition:Signature(
                    self.lastState and self.lastState.mapEntry, self.lastState and self.lastState.composition) then
                keep = true
            end
        end
    end
    if not keep then self:CloseBoss() end
end
