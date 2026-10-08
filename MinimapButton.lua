local _, ns = ...
local Button = {}
ns.MinimapButton = Button

-- Minimap button (no libraries): left-click opens/closes the dungeon browser, right-click opens the map of the dungeon you are in,
-- drag moves it around the minimap rim. Position and visibility are saved in DungeonLensDB.minimap; /dlmap minimap on|off|reset.
-- The button only polls the cursor while it is being dragged.
local ICON = "Interface/Icons/INV_Misc_Map_01"
local BORDER = "Interface/Minimap/MiniMap-TrackingBorder"
local BACKGROUND = "Interface/Minimap/UI-Minimap-Background"
local HIGHLIGHT = "Interface/Minimap/UI-Minimap-ZoomButton-Highlight"
local DEFAULT_ANGLE = 215 -- degrees, counter-clockwise from the minimap's right edge (lower left, clear of the tracking icons)
local SIZE = 31

local function Settings()
    if not ns.db then return nil end
    if type(ns.db.minimap) ~= "table" then ns.db.minimap = {} end
    return ns.db.minimap
end

local function IsSquare()
    local shape = ns.Probe(_G.GetMinimapShape)
    return shape.status == "ok" and type(shape.values[1]) == "string" and shape.values[1]:find("SQUARE", 1, true) ~= nil
end

-- Put the button on the minimap rim at `angle` degrees (round minimap) or clamped to the edge (square minimap).
function Button:Place(angle)
    local button, minimap = self.frame, _G.Minimap
    if not (button and minimap) then return end
    local width = minimap:GetWidth()
    local radius = (ns.IsNumber(width) and width > 0 and width / 2 or 70) + 5
    local radians = math.rad(angle)
    local x, y = math.cos(radians) * radius, math.sin(radians) * radius
    if IsSquare() then
        x = math.max(-radius, math.min(radius, x * math.sqrt(2)))
        y = math.max(-radius, math.min(radius, y * math.sqrt(2)))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

function Button:Angle()
    local settings = Settings()
    local angle = settings and settings.angle
    return ns.IsNumber(angle) and angle or DEFAULT_ANGLE
end

-- Cursor -> angle around the minimap centre (only while dragging).
function Button:FollowCursor()
    local minimap = _G.Minimap
    local centerX, centerY = minimap:GetCenter()
    local cursor = ns.Probe(_G.GetCursorPosition)
    local scale = ns.Probe(minimap.GetEffectiveScale, minimap)
    local factor = scale.status == "ok" and ns.IsNumber(scale.values[1]) and scale.values[1] > 0 and scale.values[1] or 1
    local cx, cy = cursor.values[1], cursor.values[2]
    if not (ns.IsNumber(centerX) and ns.IsNumber(centerY) and ns.IsNumber(cx) and ns.IsNumber(cy)) then return end
    local angle = math.deg(math.atan2(cy / factor - centerY, cx / factor - centerX))
    local settings = Settings()
    if settings then settings.angle = angle end
    self:Place(angle)
end

function Button:Toggle()
    local window = ns.Window
    if not window then return end
    if window.frame and window.frame:IsShown() then window:Close() else window:Open() end
end

function Button:Tooltip()
    local tooltip = _G.GameTooltip
    if not (tooltip and self.frame) then return end
    tooltip:SetOwner(self.frame, "ANCHOR_LEFT")
    tooltip:SetText("DungeonLens")
    tooltip:AddLine("Left-click: open / close the dungeon browser", 0.8, 0.8, 0.8)
    tooltip:AddLine("Right-click: map of the dungeon you are in", 0.8, 0.8, 0.8)
    tooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
    tooltip:Show()
end

function Button:Create()
    if self.frame or not _G.Minimap then return end
    local button = CreateFrame("Button", "DungeonLensMinimapButton", _G.Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(_G.Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(BACKGROUND)
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(HIGHLIGHT)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if ns.Window then ns.Window:Live() end
        else
            Button:Toggle()
        end
    end)
    button:SetScript("OnEnter", function() Button:Tooltip() end)
    button:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function(self)
        Button.dragging = true
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        self:SetScript("OnUpdate", function() Button:FollowCursor() end)
    end)
    button:SetScript("OnDragStop", function(self)
        Button.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    self.frame = button
end

-- Create (once) and apply the saved position and visibility. Safe to call again; does nothing without a minimap or saved settings.
function Button:Init()
    local settings = Settings()
    if not settings then return end
    self:Create()
    if not self.frame then return end
    self:Place(self:Angle())
    if settings.hidden == true then self.frame:Hide() else self.frame:Show() end
end

function Button:SetHidden(hidden)
    local settings = Settings()
    if settings then settings.hidden = hidden == true end
    self:Init()
end

function Button:Command(argument)
    argument = (argument or ""):lower()
    local settings = Settings()
    if not settings then return end
    if argument == "on" or argument == "show" then
        self:SetHidden(false)
        ns.Print("Minimap button shown.")
    elseif argument == "off" or argument == "hide" then
        self:SetHidden(true)
        ns.Print("Minimap button hidden. Type /dlmap minimap on to bring it back.")
    elseif argument == "reset" then
        settings.angle = nil
        self:SetHidden(false)
        ns.Print("Minimap button moved back to its default spot.")
    else
        ns.Print("Minimap button is " .. (settings.hidden == true and "hidden" or "shown") .. ". Usage: /dlmap minimap on|off|reset")
    end
end
