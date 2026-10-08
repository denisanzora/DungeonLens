-- Small, deterministic UI/API stubs for failure-path and tile-geometry checks.
-- This file is development-only and is never loaded or packaged as addon code.
local messages, frames = {}, {}
local secret = setmetatable({}, { __tostring = function() error("secret inspected") end })
local fixture = { inside = true, kind = "party", mapID = 101, combat = false }
local methods = {}
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:RegisterEvent(event)
    if event == "NEW_WMO_CHUNK" then error("unavailable event fixture") end
    self.events[event] = true
end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:SetSize(width, height)
    self.width, self.height = width, height
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, width, height) end
end
function methods:GetSize()
    if self.width and self.height then return self.width, self.height end
    local first, last = self.points.TOPLEFT, self.points.BOTTOMRIGHT
    if first and last and first[2] == last[2] then
        local width, height = first[2]:GetSize()
        return width + last[4] - first[4], height + first[5] - last[5]
    end
    return self.width or 800, self.height or 600
end
function methods:GetWidth() local width = self:GetSize(); return width end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:SetScale(scale) self.scale = scale end
function methods:SetPoint(point, relative, relativePoint, x, y)
    self.points[point] = { point, relative, relativePoint, x or 0, y or 0 }
end
function methods:ClearAllPoints() self.points = {} end
function methods:GetCenter()
    local anchor = self.points.CENTER
    return 640 + (anchor and anchor[4] or 0), 450 + (anchor and anchor[5] or 0)
end
function methods:Show() self.shown = true end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:SetText(text) self.text = text end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:SetTexCoord(...) self.uv = { ... } end
function methods:SetDrawLayer(layer, sublevel) self.drawLayer, self.drawSubLevel = layer, sublevel end
function methods:SetSnapToPixelGrid(value) self.snapToPixelGrid = value end
function methods:SetTexelSnappingBias(value) self.texelSnappingBias = value end
function methods:SetTexture(textureID)
    if fixture.rejectTexture and textureID then return false end
    self.textureID = textureID
    return true
end
function methods:StartMoving() self.moving = true end
function methods:StartSizing() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
local function NoOp() end
for _, name in ipairs({ "SetFrameStrata", "SetClampedToScreen", "EnableMouse",
    "SetMovable", "RegisterForDrag", "SetAllPoints", "SetColorTexture", "SetJustifyH",
    "SetResizable", "SetResizeBounds", "RegisterForClicks", "Raise", "SetBlendMode", "SetFrameLevel", "SetAlpha", "SetDesaturated", "EnableMouseWheel" }) do methods[name] = NoOp end
function methods:GetFrameLevel() return 1 end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:GetHeight() local _, height = self:GetSize(); return height end
function methods:GetEffectiveScale() return 1 end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ scripts = {}, events = {}, points = {}, shown = true,
        parent = parent, kind = kind }, { __index = methods })
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function methods:CreateTexture() return CreateFrame("Texture", nil, self) end
function methods:CreateFontString() return CreateFrame("FontString", nil, self) end
UIParent = CreateFrame("Frame")
UIParent:SetSize(1280, 900)
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
function issecretvalue(value) return rawequal(value, secret) end
function InCombatLockdown() return fixture.combat end
function GetBuildInfo() return "1.60.1", "70124", "test", 16001 end
function IsInInstance() return fixture.inside, fixture.kind end
function GetInstanceInfo() return "Test Vault", fixture.kind, 1, "Normal", 5, 0, nil, 9001 end
-- Item APIs and tooltip (loot panel). fixture.itemCache = { [itemID] = { name, quality, icon } }: items the client "has cached".
C_Item = {
    GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "INVTYPE_WRIST", 133770, 4, 1 end,
    GetItemInfo = function(id)
        local row = fixture.itemCache and fixture.itemCache[id]
        if not row then return nil end
        return row.name, "|cff0070dd|Hitem:" .. id .. "|h[" .. row.name .. "]|h|r", row.quality, 18, 13, "Armor", "Cloth", 1, "INVTYPE_WRIST", row.icon
    end,
    RequestLoadItemDataByID = function(id) if fixture.requestedItems then fixture.requestedItems[id] = true end end,
}
INVTYPE_WRIST = "Wrist"
GameTooltip = {
    SetOwner = function(self, owner) fixture.tooltip = fixture.tooltip or {}; fixture.tooltip.owner = owner; fixture.tooltip.lines = {} end,
    SetItemByID = function(self, id) fixture.tooltip.itemByID = id end,
    SetText = function(self, text) fixture.tooltip.title = text end,
    AddLine = function(self, text) fixture.tooltip.lines = fixture.tooltip.lines or {}; table.insert(fixture.tooltip.lines, text) end,
    Show = function() fixture.tooltip.shown = true end,
    Hide = function() if fixture.tooltip then fixture.tooltip.shown = false end end,
}
Enum = { UIMapType = { Dungeon = 4, Zone = 3, Micro = 5 } }
local maps = {
    [101] = { mapID = 101, name = "Test Vault", mapType = 4, parentMapID = 200 },
    [102] = { mapID = 102, name = "Second floor", mapType = 4, parentMapID = 101 },
    [103] = { mapID = 103, name = "Room", mapType = 5, parentMapID = 101 },
    [200] = { mapID = 200, name = "Outdoor Zone", mapType = 3, parentMapID = 0 },
    [201] = { mapID = 201, name = "Different Dungeon", mapType = 4, parentMapID = 200 },
}
local layer = { layerWidth = 600, layerHeight = 300, tileWidth = 256, tileHeight = 256,
    minScale = 0, maxScale = 100 }
local tiles = { 20001, 20002, 20003, 20004, 20005, 20006 }
C_Map = {
    GetBestMapForUnit = function() return fixture.mapID end,
    GetMapInfo = function(mapID) return maps[mapID] end,
    GetMapArtID = function() return 77 end,
    GetMapArtLayers = function() return { layer } end,
    GetMapArtLayerTextures = function() return tiles end,
    GetMapChildrenInfo = function(mapID) return mapID == 200 and { maps[201] } or { maps[102] } end,
    GetMapGroupID = function() return 88 end,
    GetMapGroupMembersInfo = function() return { { mapID = 101, name = "Vault", relativeHeightIndex = 0 },
        { mapID = 102, name = "Second floor", relativeHeightIndex = 1 } } end,
    GetPlayerMapPosition = function() return fixture.position end,
}
local function LoadAddon()
    local ns = {}
    for _, name in ipairs(AddonFiles) do
        assert(loadstring(AddonSources[name], "@" .. name))("DungeonLens", ns)
    end
    ns.events.scripts.OnEvent(ns.events, "ADDON_LOADED", "DungeonLens")
    return ns
end
local function Event(ns, event) ns.events.scripts.OnEvent(ns.events, event) end
local function Near(actual, expected) assert(math.abs(actual - expected) < 0.00001) end
local function Contains(needle)
    for _, message in ipairs(messages) do if message:find(needle, 1, true) then return true end end
    return false
end

if ValidationFocus == "tiles" then
    assert(loadstring(TileProbeSmokeSource, "@TileProbeSmoke.lua"))(LoadAddon(), fixture, methods, frames, messages)
    return
end
if ValidationFocus == "composite" then
    assert(loadstring(CompositeSmokeSource, "@CompositeSmoke.lua"))(LoadAddon(), fixture, methods, frames, messages)
    return
end
if ValidationFocus == "production" then
    assert(loadstring(ProductionSmokeSource, "@ProductionSmoke.lua"))(LoadAddon(), fixture, methods, frames, messages, LoadAddon)
    return
end
if ValidationFocus == "layout" then
    assert(loadstring(LayoutSmokeSource, "@LayoutSmoke.lua"))(LoadAddon())
    return
end
if ValidationFocus == "layout" then
    assert(loadstring(LayoutSmokeSource, "@LayoutSmoke.lua"))(LoadAddon())
    return
end
if ValidationFocus == "multi" then
    assert(loadstring(MultiSmokeSource, "@MultiDungeonSmoke.lua"))(LoadAddon(), fixture, methods, frames, messages, LoadAddon)
    return
end
if ValidationFocus == "resolver" then
    assert(loadstring(ResolverSmokeSource, "@ResolverSmoke.lua"))(LoadAddon(), fixture, methods, frames, messages)
    return
end

-- Repeated diagnostic failures must be contained rather than logged as errors.
DungeonLensDB = { retained = "user value" }
local ns = LoadAddon()
assert(DungeonLensDB.retained == "user value")
local multiple = ns.Probe(GetInstanceInfo)
assert(multiple.values.n == 8 and multiple.values[7] == nil and multiple.values[8] == 9001)
Event(ns, "PLAYER_ENTERING_WORLD")
assert(ns.state.hasNativeArt and ns.state.mapID == 101 and ns.state.instanceID == 9001)
assert(ns.state.currentIsDungeon and #ns.state.groupMembers == 2)

fixture.mapID = 103
ns.Refresh("test micro")
assert(not ns.state.currentIsDungeon and ns.state.mapID == 101 and ns.state.hasNativeArt)
fixture.mapID = 200
ns.Refresh("test zone fallback")
assert(ns.state.mapID == nil and not ns.state.hasNativeArt and #ns.state.children == 1)
fixture.mapID = secret
ns.Refresh("test secret map")
assert(ns.state.uiMapID == nil and not ns.state.hasNativeArt)
fixture.mapID = nil
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("no readable UiMapID"))

fixture.mapID = 101
local getLayers = C_Map.GetMapArtLayers
C_Map.GetMapArtLayers = nil
SlashCmdList.DUNGEONLENS("debug")
assert(not ns.state.hasNativeArt and Contains("GetMapArtLayers=unavailable"))
C_Map.GetMapArtLayers = function() error("fixture API exception") end
SlashCmdList.DUNGEONLENS("debug")
assert(not ns.state.hasNativeArt and Contains("GetMapArtLayers=error"))
C_Map.GetMapArtLayers = getLayers
C_Map.GetMapArtLayers = function() return {} end
ns.Refresh("empty layer array")
assert(not ns.state.hasNativeArt)
C_Map.GetMapArtLayers = getLayers
tiles[6] = nil
ns.Refresh("incomplete art")
assert(not ns.state.hasNativeArt)
tiles[6] = 20006
layer.layerWidth = 0
ns.Refresh("invalid dimensions")
assert(not ns.state.hasNativeArt)
layer.layerWidth = 600
local parentID = maps[200].parentMapID
maps[200].parentMapID = 101
ns.Refresh("cycle")
assert(#ns.state.parents == 1)
maps[200].parentMapID = parentID
print("PASS: instance/map identity, micro ancestors, no zone-child guessing, nil/missing/error/secret APIs, incomplete tiles and cycles.")

local container = CreateFrame("Frame", nil, UIParent)
container:SetSize(800, 200)
local renderer = ns.Renderer:Create(container)
assert(renderer:ShowArt(ns.Detector:GetArt(101)))
Near(renderer.canvas:GetWidth(), 400)
local width, height = renderer.canvas:GetSize()
Near(width / height, 2)
assert(renderer.tiles[4].textureID == 20004)
Near(renderer.tiles[4].points.TOPLEFT[4], 0)
Near(renderer.tiles[4].points.TOPLEFT[5], -256 * (2 / 3))
Near(renderer.tiles[6].width, 88 * (2 / 3))
Near(renderer.tiles[6].height, 44 * (2 / 3))
Near(renderer.tiles[6].uv[2], 88 / 256)
Near(renderer.tiles[6].uv[4], 44 / 256)
container:SetSize(300, 800)
Near(renderer.canvas:GetWidth(), 300)
Near(renderer.canvas.height, 150)
fixture.rejectTexture = true
assert(not renderer:ShowArt(ns.Detector:GetArt(101)) and not renderer.canvas:IsShown())
fixture.rejectTexture = false
print("PASS: native row-major tile order, wide/tall aspect fitting, partial-edge UV cropping, rejected-texture fallback.")

fixture.inside = false
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.frame:IsShown() and ns.Window.view == "list" and ns.Window.title.text == "Forever Dungeons")
assert(UISpecialFrames[1] == "DungeonLensWindow")
fixture.inside = true
fixture.kind = "raid"
Event(ns, "ZONE_CHANGED_NEW_AREA")
assert(ns.state.hasNativeArt and ns.state.renderSource == "native-uimap") -- detector still prefers native Dungeon UiMaps
fixture.kind = "pvp"
ns.Refresh("unsupported instance")
assert(not ns.state.hasNativeArt)
fixture.kind = "party"
ns.Window.frame:SetSize(700, 500)
ns.Window.frame:ClearAllPoints()
ns.Window.frame:SetPoint("CENTER", UIParent, "CENTER", 50, -30)
ns.Window:Save()
assert(ns.db.window.width == 700 and ns.db.window.height == 500 and ns.db.window.x == 50 and ns.db.window.y == -30)
assert(ns.db.window.shown)
ns = LoadAddon()
Event(ns, "PLAYER_ENTERING_WORLD")
assert(ns.Window.frame:IsShown() and ns.Window.frame:GetWidth() == 700)
ns.Window.interacting = true
ns.Window.frame:StartMoving()
fixture.combat = true
Event(ns, "PLAYER_REGEN_DISABLED")
assert(not ns.Window.interacting and not ns.Window.frame.moving)
SlashCmdList.DUNGEONLENS("close")
assert(not ns.Window.frame:IsShown() and ns.db.window.shown == false)
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.frame:IsShown()) -- existing unprotected window can open in combat
SlashCmdList.DUNGEONLENS("close")
ns = LoadAddon()
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.pendingOpen and not ns.Window.frame)
SlashCmdList.DUNGEONLENS("close")
assert(not ns.Window.pendingOpen)
SlashCmdList.DUNGEONLENS("")
fixture.combat = false
Event(ns, "PLAYER_REGEN_ENABLED")
assert(ns.Window.frame:IsShown() and not ns.Window.pendingOpen)
fixture.position = { GetXY = function() return 0.25, 0.75 end }
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("normalized=true") and Contains("marker disabled pending runtime validation"))
fixture.position = { GetXY = function() return secret, secret end }
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("<restricted>") and Contains("Unavailable events: NEW_WMO_CHUNK"))
for _, frame in ipairs(frames) do assert(frame.scripts.OnUpdate == nil) end
print("PASS: slash commands, live transitions, ESC registration, SavedVariables/reload model, combat/deferred-open paths and position diagnostics; no polling.")

-- Investigation probes must not change viewer selection or confuse IDs.
fixture.mapID, fixture.inside, fixture.kind = nil, true, "party"
fixture.instanceID = 2999
function GetInstanceInfo() return "Ruins of Lordaeron", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID end
function GetLocale() return "enUS" end
function CreateVector2D(x, y) return { x = x, y = y } end
maps[947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 }
maps[908] = { mapID = 908, name = "Ruins of Lordaeron", mapType = 6, parentMapID = 13 }
maps[1420] = { mapID = 1420, name = "Tirisfal Glades", mapType = 3, parentMapID = 1415 }
maps[1458] = { mapID = 1458, name = "Undercity", mapType = 3, parentMapID = 1415 }
maps[5000] = { mapID = 5000, name = "Unproven dungeon outside range", mapType = 4, parentMapID = 947 }
local queried, queryCount = {}, 0
C_Map.GetMapInfo = function(uiMapID)
    assert(uiMapID ~= 2999, "InstanceID was sent to GetMapInfo without UiMap evidence")
    queried[uiMapID], queryCount = true, queryCount + 1
    if uiMapID == 1 then error("synthetic record error") end
    if uiMapID == 2 then return secret end
    return maps[uiMapID]
end
C_Map.GetFallbackWorldMapID = function() return 947 end
C_Map.GetMapChildrenInfo = function(_, mapType, allDescendants)
    assert(mapType == nil and allDescendants == true)
    return { maps[1420], maps[1458], maps[5000] }
end
C_Map.GetWorldPosFromMapPos = function(uiMapID, center)
    assert(uiMapID ~= 2999 and center.x == 0.5 and center.y == 0.5)
    if uiMapID == 908 then return 1760, {} end
    if uiMapID == 5000 then return 2999, {} end
    return 0, {}
end
C_Minimap = { GetUiMapID = function() return nil end }
local pending = {}
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local function DrainTimers()
    local count = 0
    while #pending > 0 do
        count = count + 1
        assert(count < 200, "unbounded scan/polling")
        table.remove(pending, 1)()
    end
end
ns.Refresh("Ruins runtime model")
local previousState, previousFrame = ns.state, ns.Window.frame
local savedWidth, savedShown = ns.db.window.width, ns.db.window.shown
SlashCmdList.DUNGEONLENS("scan")
assert(ns.Diagnostics.scanJob and ns.Diagnostics.scanJob.nextID == 51)
DrainTimers()
local scan = ns.db.diagnostics.lastScan
assert(scan.status == "complete" and scan.context.instanceID == 2999 and scan.skippedInstanceID)
assert(queried[5000] and not queried[2999])
assert(scan.statuses.error == 1 and scan.statuses.restricted == 1)
assert(scan.maps[908].name == "Ruins of Lordaeron")
local foundLegacy, foundOutdoor = false, false
for _, candidate in ipairs(scan.candidates) do
    if candidate.uiMapID == 908 then assert(candidate.worldMapID == 1760); foundLegacy = true end
    if candidate.uiMapID == 1420 then assert(candidate.worldMapID == 0); foundOutdoor = true end
end
assert(foundLegacy and foundOutdoor)
assert(ns.state == previousState and ns.state.mapID == nil and not ns.state.hasNativeArt)
assert(ns.Window.frame == previousFrame and ns.db.window.width == savedWidth and ns.db.window.shown == savedShown)
SlashCmdList.DUNGEONLENS("scan")
local beforeStop = queryCount
SlashCmdList.DUNGEONLENS("scan stop")
DrainTimers()
assert(queryCount == beforeStop and ns.db.diagnostics.lastScan.status == "cancelled")
SlashCmdList.DUNGEONLENS("scan")
fixture.instanceID = 42
DrainTimers()
assert(ns.db.diagnostics.lastScan.status == "cancelled-instance-changed")
local timerAPI = C_Timer
C_Timer = nil
SlashCmdList.DUNGEONLENS("scan")
assert(ns.Diagnostics.scanJob == nil)
C_Timer = timerAPI
print("PASS: bounded/chunked UiMap scan, hierarchy-only out-of-range records, ID separation, name-collision non-selection, world MapID 0 and cancellation/error paths.")

SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileFrame == nil) -- wrong instance
fixture.instanceID, fixture.combat = 2999, true
SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileFrame == nil) -- combat
fixture.combat = false
ns.development = false
SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileFrame == nil) -- development gate
ns.development = true
local getBuild = GetBuildInfo
function GetBuildInfo() return "1.60.1", "70009", "test", 16001 end
SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileFrame == nil) -- wrong build
GetBuildInfo = getBuild
function methods:GetTextureFileID() return type(self.textureID) == "number" and self.textureID or 7255736 end
function methods:IsObjectLoaded() return true end
SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileFrame:IsShown() and #ns.Diagnostics.tileCells == 10)
DrainTimers()
assert(#ns.db.diagnostics.lastTileProbe.results == 10)
assert(ns.state == previousState and ns.Window.frame == previousFrame and DungeonLensMaps == nil)
SlashCmdList.DUNGEONLENS("scan stop")
assert(not ns.Diagnostics.tileFrame:IsShown())
for _, frame in ipairs(frames) do assert(frame.scripts.OnUpdate == nil) end
print("PASS: build/instance/combat/development-gated native texture contact sheet, finite load sampling and unchanged map-viewer behavior.")
