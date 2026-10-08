local _, ns = ...
local Overlay = {}
ns.Overlay = Overlay

-- Generic marker layer, independent of how the map is drawn. It lives on the
-- renderer's canvas and works only in NORMALIZED map space:
--   (0,0) = canvas top-left, (1,1) = canvas bottom-right, whatever the canvas size.
-- Renderer:Layout() resizes the canvas and calls Overlay:Layout(), so markers
-- stay correct through window resizes. Marker size is fixed in screen pixels.
local MARKER_SIZE = 16
local COLORS = {
    boss = { 0.82, 0.12, 0.12 },
    entrance = { 0.15, 0.72, 0.30 },
    authoring = { 0.95, 0.78, 0.10 },
}
local KIND_LABEL = { boss = "Boss", entrance = "Entrance", authoring = "Authoring point" }
-- Built-in raid-target skull (Blizzard art, referenced by path - nothing is bundled). If the client
-- refuses it, bosses fall back to a numbered red square.
local SKULL = "Interface/TargetingFrame/UI-RaidTargetingIcon_8"
-- Hover shows just the name; only approximate pins (development) add a caveat.
local STATUS_TEXT = {
    ["approximate"] = "Approximate location",
    ["seen"] = "Where you looted it (not verified)",
}

function Overlay:Create(canvas)
    local overlay = setmetatable({ canvas = canvas, pool = {}, active = 0 }, { __index = self })
    overlay.frame = CreateFrame("Frame", nil, canvas)
    overlay.frame:SetAllPoints(canvas)
    overlay.frame:SetFrameLevel(canvas:GetFrameLevel() + 20)
    return overlay
end

local function AcquireMarker(self, index)
    local marker = self.pool[index]
    if marker then return marker end
    marker = CreateFrame("Frame", nil, self.frame)
    marker:SetSize(MARKER_SIZE, MARKER_SIZE)
    marker:EnableMouse(true)
    marker.background = marker:CreateTexture(nil, "OVERLAY", nil, 1)
    marker.background:SetAllPoints()
    marker.icon = marker:CreateTexture(nil, "OVERLAY", nil, 2)
    marker.icon:SetAllPoints()
    marker.label = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    marker.label:SetPoint("CENTER")
    marker:SetScript("OnEnter", function(frame)
        if GameTooltip and frame.title then
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(frame.title)
            if frame.detail then GameTooltip:AddLine(frame.detail, 0.7, 0.7, 0.7) end
            if frame.hint then GameTooltip:AddLine(frame.hint, 0.55, 0.75, 1) end
            GameTooltip:Show()
        end
    end)
    marker:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    marker:SetScript("OnMouseUp", function(frame, button)
        if button == "LeftButton" and frame.bossID and ns.Window and ns.Window.SelectBoss then
            ns.Window:SelectBoss(frame.bossID, frame.title)
        end
    end)
    self.pool[index] = marker
    return marker
end

-- Collect what should be drawn for the current map and floor. Anything whose recorded layout
-- signature differs from the live layout is dropped, never approximated.
function Overlay:Collect()
    local items = {}
    local id, signature, floor = self.instanceID, self.signature, self.floor or 1
    if not id or not signature then return items end
    local data = ns.MapMarkers and ns.MapMarkers:Get(id)
    if data and data.layouts and data.layouts[floor] == signature then
        local entrance = data.entrance
        if entrance and (entrance.floor or 1) == floor and ns.MapMarkers:Visible(entrance) then
            items[#items + 1] = { kind = "entrance", name = entrance.name or "Entrance", x = entrance.x, y = entrance.y,
                status = entrance.status or "verified-client" }
        end
        for index, boss in ipairs(data.bosses or {}) do
            if (boss.floor or 1) == floor and ns.MapMarkers:Visible(boss) then
                items[#items + 1] = { kind = "boss", id = boss.id, name = boss.name, x = boss.x, y = boss.y, number = index,
                    status = boss.status or "verified-client", confidence = boss.confidence }
            end
        end
    end
    -- Learned positions (SeenLoot): fill in bosses that have no drawable verified pin, from where this character looted them.
    local entry = data and ns.MapRegistry and ns.MapRegistry:Get(id)
    if entry and ns.SeenLoot then
        for index, boss in ipairs(data.bosses or {}) do
            if not (ns.MapMarkers:ValidPoint(boss) and ns.MapMarkers:Visible(boss)) then
                local seenFloor, x, y = ns.SeenLoot:LocateBoss(entry, id, boss.id)
                if seenFloor == floor and ns.MapMarkers:ValidPoint({ x = x, y = y }) then
                    items[#items + 1] = { kind = "boss", id = boss.id, name = boss.name, x = x, y = y, number = index, status = "seen" }
                end
            end
        end
    end
    local authored = ns.db and ns.db.authoring and ns.db.authoring[id] and ns.db.authoring[id][signature]
    if authored then
        for index, point in ipairs(authored.items or {}) do
            if ns.MapMarkers:ValidPoint(point) then
                items[#items + 1] = { kind = "authoring", name = point.name or ("Point " .. index), x = point.x, y = point.y,
                    number = index, detail = "Authoring point (SavedVariables only)" }
            end
        end
    end
    return items
end

function Overlay:HasBoss(bossID)
    for _, item in ipairs(self.items or {}) do
        if item.kind == "boss" and item.id == bossID then return true end
    end
    return false
end

function Overlay:SetMap(instanceID, signature, floor)
    self.instanceID, self.signature, self.floor = instanceID, signature, floor or 1
    self:Refresh()
end

function Overlay:Refresh()
    self.items = self:Collect()
    self:Layout()
end

function Overlay:Layout()
    local items = self.items or {}
    local width, height = self.canvas:GetSize()
    local valid = ns.IsNumber(width) and ns.IsNumber(height) and width > 0 and height > 0
    for index, item in ipairs(items) do
        local marker = AcquireMarker(self, index)
        local color = COLORS[item.kind] or COLORS.boss
        local skull = false
        if item.kind == "boss" then
            local ok, accepted = pcall(marker.icon.SetTexture, marker.icon, SKULL)
            skull = ok and accepted ~= false
        end
        if skull then
            marker.background:SetColorTexture(0, 0, 0, 0)
            marker.icon:Show()
            marker.label:SetText("")
            if marker.icon.SetDesaturated then marker.icon:SetDesaturated(item.status == "approximate") end
            if marker.icon.SetVertexColor then -- learned positions are tinted blue so they are never mistaken for verified pins
                if item.status == "seen" then marker.icon:SetVertexColor(0.55, 0.75, 1, 1) else marker.icon:SetVertexColor(1, 1, 1, 1) end
            end
            marker.icon:SetAlpha(item.status == "approximate" and 0.65 or 1)
        else
            marker.icon:Hide()
            marker.background:SetColorTexture(color[1], color[2], color[3], item.status == "approximate" and 0.55 or 0.92)
            marker.label:SetText(item.number and tostring(item.number) or "E")
        end
        marker.title = item.name
        marker.bossID = item.kind == "boss" and item.id or nil
        local status = STATUS_TEXT[item.status or ""]
        marker.detail = item.detail or status
        marker.hint = item.kind == "boss" and "Click to view loot" or nil
        if valid then
            marker:ClearAllPoints()
            marker:SetPoint("CENTER", self.frame, "TOPLEFT", item.x * width, -item.y * height)
            marker:Show()
        else
            marker:Hide()
        end
    end
    for index = #items + 1, #self.pool do self.pool[index]:Hide() end
    local player = self.playerPoint
    if player and valid and self.playerMarker then
        self.playerMarker:ClearAllPoints()
        self.playerMarker:SetPoint("CENTER", self.frame, "TOPLEFT", player.x * width, -player.y * height)
        self.playerMarker:Show()
    elseif self.playerMarker then
        self.playerMarker:Hide()
    end
end

function Overlay:Clear()
    self.items, self.instanceID, self.signature = nil, nil, nil
    for _, marker in ipairs(self.pool) do marker:Hide() end
    self:ClearPlayer()
end

-- Player marker: drawn only when PositionProbe.lua supplies a position that passed every gate
-- (readable UnitPosition, exactly one axis order inside the dungeon). Never estimated.
function Overlay:SetPlayer(x, y)
    self.playerPoint = { x = x, y = y }
    if not self.playerMarker then
        local marker = CreateFrame("Frame", nil, self.frame)
        marker:SetSize(14, 14)
        marker:SetFrameLevel(self.frame:GetFrameLevel() + 5)
        marker.ring = marker:CreateTexture(nil, "OVERLAY", nil, 3)
        marker.ring:SetAllPoints()
        marker.ring:SetColorTexture(1, 1, 1, 1)
        marker.dot = marker:CreateTexture(nil, "OVERLAY", nil, 4)
        marker.dot:SetPoint("TOPLEFT", marker, "TOPLEFT", 2, -2)
        marker.dot:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", -2, 2)
        marker.dot:SetColorTexture(0.1, 0.55, 1, 1)
        self.playerMarker = marker
    end
    self:Layout()
end

function Overlay:ClearPlayer()
    self.playerPoint = nil
    if self.playerMarker then self.playerMarker:Hide() end
end

-- Convert the current cursor position to normalized canvas space, or nil when
-- the cursor is outside the canvas. Used by the authoring mode.
function Overlay:CursorToNormalized()
    local frame = self.canvas
    if type(GetCursorPosition) ~= "function" then return nil end
    local cursorX, cursorY = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    local width, height = frame:GetSize()
    if not (ns.IsNumber(cursorX) and ns.IsNumber(cursorY) and ns.IsNumber(scale) and scale > 0
        and ns.IsNumber(left) and ns.IsNumber(top) and ns.IsNumber(width) and ns.IsNumber(height)
        and width > 0 and height > 0) then return nil end
    local x, y = (cursorX / scale - left) / width, (top - cursorY / scale) / height
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000
end
