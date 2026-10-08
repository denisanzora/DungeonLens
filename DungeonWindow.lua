local _, ns = ...
local Window = {}
ns.Window = Window

-- One window, two views:
--   list : every Forever dungeon (click a row)                                  view = "list"
--   map  : the chosen dungeon, floor controls, boss pins, "< Dungeons" to go back   view = "map"
-- /dlmap always opens the list. Nothing here depends on where the character is.

local ROW_HEIGHT, HEADER_HEIGHT = 34, 24

local function Label(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text or "")
    return label
end

local function Button(parent, width, height, text, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    -- Buttons always sit well above sibling mouse-enabled frames (e.g. the drag header).
    button:SetFrameLevel(parent:GetFrameLevel() + 20)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.16, 0.22, 0.3, 1)
    local caption = Label(button, "GameFontNormal", text)
    caption:SetPoint("CENTER")
    button.caption = caption
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function() background:SetColorTexture(0.22, 0.33, 0.45, 1) end)
    button:SetScript("OnLeave", function() background:SetColorTexture(0.16, 0.22, 0.3, 1) end)
    return button
end

local function Bounded(value, default, minimum, maximum)
    if not ns.IsNumber(value) then value = default end
    return math.max(minimum, math.min(maximum, value))
end

function Window:Create()
    if self.frame then return end
    local saved = ns.db.window
    local frame = CreateFrame("Frame", "DungeonLensWindow", UIParent)
    self.frame = frame
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    local screenWidth, screenHeight = UIParent:GetSize()
    local maxWidth, maxHeight = math.max(420, screenWidth - 32), math.max(320, screenHeight - 32)
    frame:SetSize(Bounded(saved.width, 800, 420, maxWidth), Bounded(saved.height, 600, 320, maxHeight))
    local x = Bounded(saved.x, 0, -screenWidth / 2, screenWidth / 2)
    local y = Bounded(saved.y, 0, -screenHeight / 2, screenHeight / 2)
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.035, 0.045, 0.065, 0.97)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, 0)
    header:SetHeight(36)
    header:SetFrameLevel(frame:GetFrameLevel() + 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not ns.InCombat() then
            frame:StartMoving()
            self.interacting = true
        end
    end)
    header:SetScript("OnDragStop", function() self:StopInteraction() end)
    self.header = header
    self.title = Label(frame, "GameFontNormalLarge", "Forever Dungeons")
    local close = Button(frame, 26, 24, "X", function() self:Close() end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    self.closeButton = close

    -- Map view chrome: back button and floor navigation.
    self.backButton = Button(frame, 104, 24, "< Dungeons", function() self:ShowList() end)
    self.backButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    self.floorNext = Button(frame, 24, 24, ">", function() self:SetFloor((self.floor or 1) + 1) end)
    self.floorNext:SetPoint("RIGHT", close, "LEFT", -8, 0)
    self.floorLabel = Label(frame, "GameFontNormal", "")
    self.floorLabel:SetPoint("RIGHT", self.floorNext, "LEFT", -6, 0)
    self.floorLabel:SetWidth(150)
    self.floorLabel:SetJustifyH("CENTER")
    self.floorPrev = Button(frame, 24, 24, "<", function() self:SetFloor((self.floor or 1) - 1) end)
    self.floorPrev:SetPoint("RIGHT", self.floorLabel, "LEFT", -6, 0)

    -- Content: the map canvas and the dungeon list share the same area.
    self.mapArea = CreateFrame("Frame", nil, frame)
    self.mapArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -44)
    self.mapArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 36)
    local mapBackground = self.mapArea:CreateTexture(nil, "BACKGROUND")
    mapBackground:SetAllPoints()
    mapBackground:SetColorTexture(0.015, 0.02, 0.03, 1)
    self.renderer = ns.Renderer:Create(self.mapArea)
    self.message = Label(self.mapArea, "GameFontHighlight", "")
    self.message:SetPoint("CENTER")
    self.message:SetWidth(math.max(320, frame:GetWidth() - 48))
    self.message:SetJustifyH("CENTER")
    self:CreateList()

    -- Use the modern bounds API only when the running client supplies it.
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizable(true)
        frame:SetResizeBounds(420, 320, maxWidth, maxHeight)
        local resize = Button(frame, 58, 20, "Resize", function() end)
        resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
        resize:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and not ns.InCombat() then
                frame:StartSizing("BOTTOMRIGHT")
                self.interacting = true
            end
        end)
        resize:SetScript("OnMouseUp", function() self:StopInteraction() end)
    end
    frame:SetScript("OnSizeChanged", function()
        self.message:SetWidth(math.max(320, frame:GetWidth() - 48))
        self.renderer:Layout()
        self:LayoutList()
        if ns.BossPanel then ns.BossPanel:Layout() end
    end)
    frame:SetScript("OnHide", function()
        self:StopInteraction()
        self:Save()
        self.renderer:Clear()
    end)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "DungeonLensWindow"
    end
end

-- ---------------------------------------------------------------------------------------------
-- Dungeon list
-- ---------------------------------------------------------------------------------------------
function Window:CreateList()
    local scroll = CreateFrame("ScrollFrame", nil, self.frame)
    scroll:SetPoint("TOPLEFT", self.mapArea, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", self.mapArea, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 100)
    scroll:SetScrollChild(child)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.45, 0.55, 0.7, 0.6)
    thumb:SetWidth(4)
    thumb:Hide()
    scroll:SetScript("OnMouseWheel", function(_, delta)
        self:ScrollBy(-delta * ROW_HEIGHT * 1.5)
    end)
    self.listScroll, self.listChild, self.listThumb = scroll, child, thumb
    self.listRows, self.listHeaders = {}, {}
    scroll:Hide()
end

function Window:ScrollBy(amount)
    local scroll, child = self.listScroll, self.listChild
    if not scroll then return end
    local _, viewHeight = scroll:GetSize()
    local maximum = math.max(0, (child:GetHeight() or 0) - (viewHeight or 0))
    local current = scroll:GetVerticalScroll() or 0
    scroll:SetVerticalScroll(math.max(0, math.min(maximum, current + amount)))
    self:UpdateThumb()
end

function Window:UpdateThumb()
    local scroll, child, thumb = self.listScroll, self.listChild, self.listThumb
    local _, viewHeight = scroll:GetSize()
    local total = child:GetHeight() or 0
    if not ns.IsNumber(viewHeight) or viewHeight <= 0 or total <= viewHeight then thumb:Hide(); return end
    local size = math.max(24, viewHeight * viewHeight / total)
    local maximum = total - viewHeight
    local offset = (scroll:GetVerticalScroll() or 0) / maximum * (viewHeight - size)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, -offset)
    thumb:SetHeight(size)
    thumb:Show()
end

-- Rows of the list: optional CURRENT DUNGEON section, then ALL DUNGEONS (registered + unavailable), by name.
function Window:BuildListItems()
    local items, entries = {}, {}
    local build = ns.Probe(GetBuildInfo)
    for _, row in ipairs(ns.MapRegistry:List()) do
        local allowed = ns.MapRegistry:GetVerified(row.instanceID, ns.Field(build.values, 1), ns.Field(build.values, 2))
        local summary = ns.MapMarkers:Summary(row.instanceID)
        local floors = ns.WMOComposition:FloorCount(row.entry)
        entries[#entries + 1] = { name = row.name, instanceID = row.instanceID, disabled = allowed == nil,
            bosses = summary.placed, floors = floors }
    end
    for instanceID, info in pairs(ns.UnavailableMaps or {}) do
        entries[#entries + 1] = { name = info.name, instanceID = instanceID, disabled = true }
    end
    table.sort(entries, function(a, b) return a.name < b.name end)
    local current = ns.state and ns.state.inInstance and ns.state.instanceID
    for _, entry in ipairs(entries) do
        if entry.instanceID == current and not entry.disabled then
            items[#items + 1] = { header = "CURRENT DUNGEON" }
            items[#items + 1] = entry
            items[#items + 1] = { header = "ALL DUNGEONS" }
            break
        end
    end
    for _, entry in ipairs(entries) do items[#items + 1] = entry end
    return items
end

local function MakeRow(self, index)
    local row = CreateFrame("Button", nil, self.listChild)
    row:SetHeight(ROW_HEIGHT)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accent:SetWidth(3)
    row.accent:SetColorTexture(0.35, 0.65, 1, 1)
    row.name = Label(row, "GameFontHighlightLarge", "")
    row.name:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.level = Label(row, "GameFontDisableSmall", "")
    row.level:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.chevron = Label(row, "GameFontNormalLarge", ">")
    row.chevron:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.floors = Label(row, "GameFontNormal", "")
    row.floors:SetPoint("RIGHT", row.chevron, "LEFT", -18, 0)
    row.floors:SetWidth(90)
    row.floors:SetJustifyH("RIGHT")
    row.bosses = Label(row, "GameFontNormal", "")
    row.bosses:SetPoint("RIGHT", row.floors, "LEFT", -12, 0)
    row.bosses:SetWidth(80)
    row.bosses:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function() if not row.data.disabled then row.background:SetColorTexture(0.17, 0.26, 0.38, 1) end end)
    row:SetScript("OnLeave", function() Window:PaintRow(row) end)
    row:SetScript("OnClick", function()
        if row.data and not row.data.disabled then Window:ShowDungeon(row.data.instanceID) end
    end)
    self.listRows[index] = row
    return row
end

function Window:PaintRow(row)
    local data = row.data
    if data.disabled then
        row.background:SetColorTexture(0.07, 0.08, 0.1, 1)
    else
        row.background:SetColorTexture(0.1, 0.14, 0.2, 1)
    end
    if data.instanceID == self.lastDungeon and not data.disabled then row.accent:Show() else row.accent:Hide() end
end

function Window:RefreshList()
    if not self.listScroll then return end
    local items = self:BuildListItems()
    local width = math.max(200, self.frame:GetWidth() - 24)
    self.listChild:SetWidth(width)
    local y, rowIndex, headerIndex = 0, 0, 0
    for _, header in ipairs(self.listHeaders) do header:Hide() end
    for _, item in ipairs(items) do
        if item.header then
            headerIndex = headerIndex + 1
            local label = self.listHeaders[headerIndex]
            if not label then
                label = Label(self.listChild, "GameFontNormalSmall", "")
                label:SetTextColor(0.55, 0.65, 0.8)
                self.listHeaders[headerIndex] = label
            end
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 14, -y - 8)
            label:SetText(item.header)
            label:Show()
            y = y + HEADER_HEIGHT
        else
            rowIndex = rowIndex + 1
            local row = self.listRows[rowIndex] or MakeRow(self, rowIndex)
            row.data = item
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.listChild, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", self.listChild, "TOPRIGHT", 0, -y)
            row.name:SetText(item.name)
            row.level:SetText(ns.LevelText(item.instanceID) or "")
            if item.disabled then
                row.name:SetTextColor(0.5, 0.5, 0.5)
                row.bosses:SetText("")
                row.floors:SetText("Unavailable")
                row.floors:SetTextColor(0.6, 0.45, 0.35)
                row.chevron:Hide()
            else
                row.name:SetTextColor(1, 1, 1)
                row.bosses:SetText(item.bosses > 0 and (item.bosses .. (item.bosses == 1 and " Boss" or " Bosses")) or "")
                row.bosses:SetTextColor(0.75, 0.8, 0.9)
                row.floors:SetText(item.floors > 1 and (item.floors .. " Floors") or "")
                row.floors:SetTextColor(0.75, 0.8, 0.9)
                row.chevron:Show()
            end
            self:PaintRow(row)
            row:Show()
            y = y + ROW_HEIGHT + 4
        end
    end
    for index = rowIndex + 1, #self.listRows do self.listRows[index]:Hide() end
    self.listChild:SetHeight(math.max(y, 10))
    self:ScrollBy(0)
end

function Window:LayoutList()
    if self.view == "list" then self:RefreshList() end
end

-- ---------------------------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------------------------
function Window:ApplyChrome(floorCount)
    local list = self.view ~= "map"
    self.title:ClearAllPoints()
    if list then
        self.title:SetPoint("LEFT", self.frame, "TOPLEFT", 14, -18)
        self.title:SetText("Forever Dungeons")
        self.backButton:Hide()
    else
        self.title:SetPoint("LEFT", self.frame, "TOPLEFT", 124, -18)
        self.backButton:Show()
    end
    self.title:SetPoint("RIGHT", self.frame, "TOPRIGHT", (floorCount or 1) > 1 and -(40 + 24 * 2 + 150 + 34) or -44, -18)
    self.title:SetJustifyH("LEFT")
    local showFloors = not list and (floorCount or 1) > 1
    for _, widget in ipairs({ self.floorPrev, self.floorNext, self.floorLabel }) do
        if showFloors then widget:Show() else widget:Hide() end
    end
end

function Window:ShowList()
    if not ns.db then return end
    self.view, self.dungeonID = "list", nil
    if self.CloseBoss then self:CloseBoss() end
    if not self.frame or not self.frame:IsShown() then return self:Open() end
    self:Update()
end

function Window:ShowDungeon(instanceID, floor)
    if not ns.db or not ns.IsID(instanceID) then return false end
    if self.CloseBoss and self.dungeonID ~= instanceID then self:CloseBoss() end
    self.view, self.dungeonID, self.lastDungeon, self.floor = "map", instanceID, instanceID, floor or 1
    if not self.frame or not self.frame:IsShown() then self:Open(true) else self:Update() end
    return true
end
Window.Preview = Window.ShowDungeon -- compatibility with the older command name

-- Hidden convenience (/dlmap live): jump to the dungeon the character is in, if it has a map.
function Window:Live()
    local state = ns.state
    if state and state.inInstance and state.instanceID and ns.MapRegistry:Get(state.instanceID) then
        return self:ShowDungeon(state.instanceID)
    end
    self:ShowList()
end

function Window:SetFloor(floor)
    local state = self.lastState
    local count = state and state.mapEntry and ns.WMOComposition:FloorCount(state.mapEntry) or 1
    floor = math.max(1, math.min(count, floor or 1))
    if floor == self.floor then return end
    self.floor = floor
    self:Update()
end

local function FloorText(entry, floor, count)
    local record = entry.floors and entry.floors[floor]
    local noun = entry.floorNoun or "Floor"
    if record and record.label then return record.label .. " (" .. floor .. " of " .. count .. ")" end
    return noun .. " " .. floor .. " of " .. count
end

function Window:RenderMap()
    local state = ns.Detector:ForPreview(self.dungeonID, self.floor)
    local entry = state.mapEntry
    local floorCount = entry and ns.WMOComposition:FloorCount(entry) or 1
    self.floor = math.max(1, math.min(floorCount, self.floor or 1))
    if entry and self.floor ~= state.floor then
        local layout = ns.WMOComposition:GetLayout(entry, self.floor)
        if layout then state.composition = layout end
    end
    state.floor, state.floorCount = self.floor, floorCount
    self.lastState = state
    self.title:SetText(ns.Text(state.instanceName or "Dungeon"))
    local rendered, renderReason = false, "no-renderer-selected"
    if state.renderSource == "blizzard-wmo-minimap" or state.renderSource == "blizzard-ground-minimap" then
        rendered, renderReason = self.renderer:ShowWMO(state.mapEntry, state.composition)
    end
    if rendered then
        -- Boss pins use the rendered floor canvas as normalized space; the signature ties them to this exact layout.
        self.renderer.overlay:SetMap(state.instanceID, ns.WMOComposition:Signature(state.mapEntry, state.composition), self.floor)
        self.message:Hide()
    else
        self.renderer:Clear()
        self.message:SetText("This dungeon's map couldn't be displayed.\nPlease try another dungeon.")
        self.message:Show()
    end
    for _, target in ipairs({ state.resolution, ns.state and ns.state.instanceID == state.instanceID and ns.state.resolution or false }) do
        if target then
            target.renderAttempted = state.renderSource ~= "none"
            target.renderSucceeded, target.renderReason = rendered, renderReason
        end
    end
    self:ApplyChrome(rendered and floorCount or 1)
    if rendered and floorCount > 1 then self.floorLabel:SetText(FloorText(entry, self.floor, floorCount)) end
    if self.ValidateBoss then self:ValidateBoss() end -- a boss panel never outlives its floor/dungeon
    if ns.BossList then ns.BossList:Refresh() end
    if ns.EntranceCard then ns.EntranceCard:Refresh() end
end

function Window:Update()
    if not self.frame then return end
    if self.view == "map" and self.dungeonID then
        self.listScroll:Hide()
        self:RenderMap()
    else
        self.view = "list"
        -- Leaving a map releases its textures and pins so nothing stale can show.
        self.renderer:Clear()
        self.message:Hide()
        self.lastState = nil
        if self.CloseBoss then self:CloseBoss() end
        if ns.BossList then ns.BossList:Hide() end
        if ns.EntranceCard then ns.EntranceCard:Hide() end
        self:ApplyChrome(1)
        self.listScroll:Show()
        self:RefreshList()
    end
end

-- /dlmap: always the dungeon browser (unless keepView, used when a map was requested first).
function Window:Open(keepView)
    if not ns.db then return end
    if not self.frame and ns.InCombat() then
        self.pendingOpen = true
        ns.Print("The first map-window creation is queued until combat ends.")
        return
    end
    self.pendingOpen = nil
    -- The normal viewer gets a clean foreground, independent of development UI.
    if ns.Composite then ns.Composite:Close() end
    if ns.Diagnostics then ns.Diagnostics:ClearTileProbe() end
    self:Create()
    if not keepView then self.view, self.dungeonID = "list", nil end
    if not self.view then self.view = "list" end
    ns.Refresh("open")
    self.frame:Show()
    self:Update()
    self.frame:Raise()
    self:Save()
end

function Window:StopInteraction()
    if self.frame and self.interacting then
        self.frame:StopMovingOrSizing()
        self.interacting = false
        self:Save()
    end
end

function Window:Save()
    if not self.frame or not ns.db then return end
    local frame, saved = self.frame, ns.db.window
    saved.width, saved.height = frame:GetSize()
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if ns.IsNumber(x) and ns.IsNumber(y) and ns.IsNumber(parentX) and ns.IsNumber(parentY) then
        saved.point = "CENTER"
        saved.x, saved.y = x - parentX, y - parentY
    end
    saved.shown = frame:IsShown()
end

function Window:Close()
    self.pendingOpen = nil
    if self.frame then self.frame:Hide() end
    if ns.db then ns.db.window.shown = false end
end

function Window:RestoreVisibility()
    if self.restored or not ns.db then return end
    self.restored = true
    if ns.db.window.shown == true then self:Open() end
end

-- Technical status for /dlmap debug only; never shown in the normal UI.
function Window:DebugReport()
    local state = self.lastState
    ns.Print("UI: view=" .. ns.Text(self.view) .. " dungeon=" .. ns.Text(self.dungeonID) .. " floor=" .. ns.Text(self.floor))
    if state and state.mapEntry then
        local entry = state.mapEntry
        local summary = ns.MapMarkers:Summary(state.instanceID)
        ns.Print("  map: " .. ns.Text(entry.displayName) .. " source=" .. ns.Text(entry.sourceType) .. " verified=" .. tostring(entry.verified == true)
            .. " floors=" .. ns.WMOComposition:FloorCount(entry) .. " floorSource=" .. ns.Text(entry.floorSource) .. " signature="
            .. ns.Text(ns.WMOComposition:Signature(entry, state.composition)))
        ns.Print("  bosses: shown=" .. summary.placed .. " approximate-hidden=" .. summary.hidden .. " unplaced=" .. summary.unplaced
            .. (summary.unplaced > 0 and (" (" .. table.concat(summary.unplacedNames, ", ") .. ")") or ""))
        if state.resolution then
            ns.Print("  resolution: " .. ns.Text(state.resolution.compatibility) .. " render=" .. ns.Text(state.resolution.renderReason))
        end
    end
end
