local _, ns = ...
local Window = ns.Window
local List = {}
ns.BossList = List

-- Boss table, top-right of an open dungeon map: every boss of that dungeon (placed on the map or not), in encounter order, with how many
-- loot items are known. Clicking a row opens that boss's loot panel (BossPanel.lua); the panel's "< Bosses" button comes back here.
-- Hidden while the loot panel is shown and whenever the window is not showing a dungeon map.
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 28
local WIDTH = 230

local function Label(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text or "")
    return label
end

function List:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", nil, Window.mapArea)
    frame:SetPoint("TOPRIGHT", Window.mapArea, "TOPRIGHT", -8, -8)
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEADER_HEIGHT)
    frame:SetFrameLevel(Window.mapArea:GetFrameLevel() + 50)
    frame:EnableMouse(true) -- clicks on the table never fall through to the map
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.04, 0.055, 0.08, 0.92)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edge:SetHeight(1)
    edge:SetColorTexture(0.3, 0.4, 0.55, 1)
    self.header = Label(frame, "GameFontNormalSmall", "BOSSES")
    self.header:SetTextColor(0.55, 0.65, 0.8)
    self.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    self.hint = Label(frame, "GameFontDisableSmall", "click for loot")
    self.hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    self.rows = {}
    self.frame = frame
    frame:Hide()
end

local function MakeRow(self, index)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetHeight(ROW_HEIGHT)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.background:SetColorTexture(0.08, 0.11, 0.16, 1)
    row.number = Label(row, "GameFontNormalSmall", "")
    row.number:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.number:SetWidth(16)
    row.number:SetJustifyH("LEFT")
    row.loot = Label(row, "GameFontDisableSmall", "")
    row.loot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.loot:SetJustifyH("RIGHT")
    row.name = Label(row, "GameFontHighlight", "")
    row.name:SetPoint("LEFT", row.number, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.loot, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function() row.background:SetColorTexture(0.15, 0.22, 0.32, 1) end)
    row:SetScript("OnLeave", function() row.background:SetColorTexture(0.08, 0.11, 0.16, 1) end)
    row:SetScript("OnClick", function()
        if row.boss and Window.SelectBossFromList then Window:SelectBossFromList(row.boss) end
    end)
    self.rows[index] = row
    return row
end

-- Number of loot items known for a boss (verified + ones this character has seen).
function List:ItemCount(bossID)
    local verified = ns.BossLoot and ns.BossLoot[bossID]
    local count = verified and #verified.items or 0
    if ns.SeenLoot then count = count + #ns.SeenLoot:ForBoss(bossID) end
    return count
end

function List:Refresh()
    local panelShown = ns.BossPanel and ns.BossPanel.frame and ns.BossPanel.frame:IsShown()
    local data = Window.view == "map" and Window.dungeonID and ns.MapMarkers:Get(Window.dungeonID)
    local bosses = data and data.bosses
    if not Window.mapArea or panelShown or not bosses or #bosses == 0 then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Create()
    for index, boss in ipairs(bosses) do
        local row = self.rows[index] or MakeRow(self, index)
        row.boss = boss
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -(HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + 2)))
        row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -(HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + 2)))
        row.number:SetText(tostring(index))
        row.number:SetTextColor(0.55, 0.65, 0.8)
        row.name:SetText(boss.name or ("Boss " .. index))
        local count = self:ItemCount(boss.id)
        row.loot:SetText(count > 0 and (count .. (count == 1 and " item" or " items")) or "no loot yet")
        row.loot:SetTextColor(count > 0 and 0.75 or 0.5, count > 0 and 0.8 or 0.5, count > 0 and 0.9 or 0.5)
        row:Show()
    end
    for index = #bosses + 1, #self.rows do self.rows[index]:Hide() end
    self.frame:SetHeight(HEADER_HEIGHT + #bosses * (ROW_HEIGHT + 2) + 6)
    self.frame:Show()
end

function List:Hide()
    if self.frame then self.frame:Hide() end
end

-- Open a boss's loot from its row. A boss placed on another floor takes the map to that floor first; an unplaced boss just opens.
function Window:SelectBossFromList(boss)
    if not (self.view == "map" and self.dungeonID and ns.IsID(boss.id)) then return end
    local placed = ns.MapMarkers:ValidPoint(boss) and ns.MapMarkers:Visible(boss)
    if placed and (boss.floor or 1) ~= self.floor then self:SetFloor(boss.floor or 1) end
    self:SelectBoss(boss.id, boss.name)
end
