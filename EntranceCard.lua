local _, ns = ...
local Window = ns.Window
local Card = {}
ns.EntranceCard = Card

-- "How to get here" card, top-left of an open dungeon map: the zone the entrance is in, its coordinates, a short hint, and a button that
-- opens the world map on that zone and drops the standard map pin (C_Map user waypoint, which also shows on the minimap). Data:
-- DungeonEntrances.lua (zone UiMapID + normalized position; zone-only where the exact spot is not known).
local WIDTH = 236
local PADDING = 12

local function Label(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text or "")
    return label
end

function Card:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", nil, Window.mapArea)
    frame:SetPoint("TOPLEFT", Window.mapArea, "TOPLEFT", 8, -8)
    frame:SetWidth(WIDTH)
    frame:SetFrameLevel(Window.mapArea:GetFrameLevel() + 50)
    frame:EnableMouse(true) -- clicks on the card never fall through to the map
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.04, 0.055, 0.08, 0.92)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edge:SetHeight(1)
    edge:SetColorTexture(0.3, 0.4, 0.55, 1)
    self.header = Label(frame, "GameFontNormalSmall", "ENTRANCE")
    self.header:SetTextColor(0.55, 0.65, 0.8)
    self.header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -10)
    self.zone = Label(frame, "GameFontHighlight", "")
    self.zone:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -28)
    self.zone:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -28)
    self.zone:SetJustifyH("LEFT")
    self.note = Label(frame, "GameFontDisableSmall", "")
    self.note:SetPoint("TOPLEFT", self.zone, "BOTTOMLEFT", 0, -4)
    self.note:SetWidth(WIDTH - 2 * PADDING)
    self.note:SetJustifyH("LEFT")
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(WIDTH - 2 * PADDING, 24)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, 10)
    local buttonBackground = button:CreateTexture(nil, "BACKGROUND")
    buttonBackground:SetAllPoints()
    buttonBackground:SetColorTexture(0.16, 0.22, 0.3, 1)
    local buttonLabel = Label(button, "GameFontNormalSmall", "Show on world map")
    buttonLabel:SetPoint("CENTER")
    button:SetScript("OnEnter", function()
        buttonBackground:SetColorTexture(0.22, 0.33, 0.45, 1)
        local tooltip = _G.GameTooltip
        if tooltip and Card.data then
            tooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
            tooltip:SetText("Show on world map")
            tooltip:AddLine(Card.data.x and "Opens the zone map and places a map pin at the entrance." or "Opens the zone map.", 0.7, 0.7, 0.7)
            tooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        buttonBackground:SetColorTexture(0.16, 0.22, 0.3, 1)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function() Card:ShowOnWorldMap() end)
    self.button, self.frame = button, frame
    frame:Hide()
end

function Card:Position(data)
    if not data or not data.x then return nil end
    return string.format("%.1f, %.1f", data.x * 100, data.y * 100)
end

function Card:Refresh()
    local id = Window.view == "map" and Window.dungeonID
    local data = id and ns.DungeonEntrances and ns.DungeonEntrances[id]
    self.data, self.instanceID = data, data and id or nil
    if not (data and Window.mapArea) then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Create()
    local position = self:Position(data)
    self.zone:SetText(data.zone .. (position and ("  " .. position) or ""))
    self.note:SetText(data.note or "")
    self.frame:SetHeight(data.note and 112 or 78)
    self.frame:Show()
end

function Card:Hide()
    if self.frame then self.frame:Hide() end
end

-- Opens the world map on the entrance's zone and (when the exact spot is known) sets the standard map waypoint. Every API is optional:
-- if the client lacks one, the zone and coordinates are printed so the entrance can still be found.
function Card:ShowOnWorldMap()
    local data = self.data
    if not data then return end
    local cMap = _G.C_Map
    local opened = false
    local open = ns.Field(cMap, "OpenWorldMap")
    if type(open) == "function" then opened = pcall(open, data.uiMapID) end
    local pinned = false
    if data.x then
        local can = ns.Field(cMap, "CanSetUserWaypointOnMap")
        local allowed = true
        if type(can) == "function" then
            local ok, result = pcall(can, data.uiMapID)
            allowed = ok and result ~= false
        end
        local set, point = ns.Field(cMap, "SetUserWaypoint"), ns.Field(_G.UiMapPoint, "CreateFromCoordinates")
        if allowed and type(set) == "function" and type(point) == "function" then
            local ok, made = pcall(point, data.uiMapID, data.x, data.y)
            if ok and made then pinned = pcall(set, made) end
        end
        if pinned then
            local track = ns.Field(_G.C_SuperTrack, "SetSuperTrackedUserWaypoint")
            if type(track) == "function" then pcall(track, true) end
        end
    end
    if not opened or (data.x and not pinned) then
        local position = self:Position(data)
        ns.Print("Entrance: " .. data.zone .. (position and (" " .. position) or "") .. (data.note and (" - " .. data.note) or ""))
    end
    self.lastResult = { opened = opened, pinned = pinned }
end
