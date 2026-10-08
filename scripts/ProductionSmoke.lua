-- Focused normal-viewer regressions using measured RFC metadata and Lua 5.1.
local ns, fixture, methods, frames, messages, LoadAddon = ...
fixture.instanceID, fixture.mapID, fixture.inside, fixture.kind = 389, nil, true, "party"
function GetInstanceInfo()
    local names = { [389] = "Ragefire Chasm", [2999] = "Ruins of Lordaeron", [42] = "Unknown dungeon" }
    return names[fixture.instanceID] or "World", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID
end
C_Map.GetPlayerMapPosition = function() error("Production renderer must not request player position") end
local getMapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(uiMapID)
    assert(uiMapID ~= 389 and uiMapID ~= 2999, "InstanceID conflated with UiMapID")
    return getMapInfo(uiMapID)
end
local requests, setTexture = {}, methods.SetTexture
function methods:SetTexture(asset)
    if type(asset) == "number" then requests[#requests + 1] = asset end -- FileDataID tile requests only (not marker icon paths)
    return setTexture(self, asset)
end
local function Event(event) ns.events.scripts.OnEvent(ns.events, event) end
local function Near(actual, expected) assert(math.abs(actual - expected) < 0.000001) end
local function ByID(records)
    local result = {}
    for _, record in ipairs(records) do result[record.fileDataID] = record end
    return result
end
local function AssertCleared()
    assert(ns.Window.renderer.composition == nil and ns.Window.renderer.mapEntry == nil)
    assert(not ns.Window.renderer.canvas:IsShown())
    for _, texture in ipairs(ns.Window.renderer.tiles) do assert(texture.textureID == nil and not texture:IsShown()) end
end

local entry = assert(ns.MapRegistry:Get(389))
assert(entry.instanceID == 389 and entry.worldMapID == 389 and entry.sourceType == "blizzard-wmo-minimap")
assert(entry.displayName == "Ragefire Chasm" and entry.verified and entry.rho == 2)
assert(entry.logicalBlockWidth == 256 and entry.logicalBlockHeight == 256 and entry.tileCount == 19)
assert(ns.MapRegistry:Get(2999) ~= nil and not ns.MapRegistry:Get(2999).verified and ns.MapRegistry:Get(42) == nil) -- 2999: generated candidate
for _, group in ipairs(entry.groups) do
    for _, tile in ipairs(group.tiles) do assert(type(tile[1]) == "number" and tile[1] > 0) end
end
Event("PLAYER_ENTERING_WORLD")
assert(ns.state.instanceID == 389 and ns.state.uiMapID == nil and ns.state.mapID == nil)
assert(ns.state.renderSource == "blizzard-wmo-minimap" and ns.state.hasMap and not ns.state.hasNativeArt)
assert(ns.state.mapEntry == entry)
local canonical = assert(ns.Composite:BuildLayout("canonical"))
assert(ns.state.composition == canonical) -- identical cached shared calculation
local expectedImages = ByID(ExpectedRFC.tileDimensions)
local expectedTiles = ByID(ExpectedRFC.minimapTiles)
local offsets = { [213056] = 128, [213069] = 192, [213070] = 192,
    [213071] = 128, [213072] = 192, [213073] = 128 }
for index, tile in ipairs(canonical.tiles) do
    local expected = expectedImages[tile.fileDataID]
    assert(tile.width == expected.width and tile.height == expected.height)
    assert(tile.groupIndex == expectedTiles[tile.fileDataID].groupIndex)
    Near(tile.x, tile.cellX); Near(tile.y - tile.cellY, offsets[tile.fileDataID] or 0)
    if index > 1 then assert(canonical.tiles[index - 1].zOrder <= tile.zOrder) end
end
Near(canonical.width, 1088.4288482666016); Near(canonical.height, 964.4182891845703)
-- Normal viewer under the browser UI: /dlmap -> dungeon list -> click RFC -> map + pins -> back -> list.
local function FindRow(instanceID)
    for _, row in ipairs(ns.Window.listRows) do
        if row:IsShown() and row.data and row.data.instanceID == instanceID then return row end
    end
end
local function Click(button) button.scripts.OnClick(button) end
local beforeOpen = #frames
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.frame:IsShown() and ns.Window.view == "list" and ns.Window.title.text == "Forever Dungeons")
assert(not ns.Window.renderer.canvas:IsShown() and #requests == 0 and not ns.Window.backButton:IsShown())
assert(ns.Composite.frame == nil and ns.Diagnostics.tileFrame == nil)
Click(assert(FindRow(389)))
assert(ns.Window.view == "map" and ns.Window.title.text == "Ragefire Chasm" and ns.Window.backButton:IsShown())
assert(not ns.Window.message:IsShown())
assert(ns.Window.renderer.composition == canonical and #requests == 19)
-- The production map subtree contains only ordinary Frames and texture regions.
-- All overlay/font creation stays outside that subtree in the window chrome.
for index = beforeOpen + 1, #frames do
    local object, parent = frames[index], frames[index].parent
    local inOverlay = false
    while parent do
        if parent == ns.Window.renderer.overlay.frame then inOverlay = true end -- boss markers are the one allowed exception
        if parent == ns.Window.renderer.canvas and not inOverlay then
            assert(object.kind ~= "FontString" and object.kind ~= "Button")
            assert(object.drawLayer ~= "OVERLAY")
            break
        end
        parent = parent.parent
    end
end
for index, tile in ipairs(canonical.tiles) do
    local texture = ns.Window.renderer.tiles[index]
    assert(texture.textureID == tile.fileDataID and type(texture.textureID) == "number")
    assert(texture.drawSubLevel == tile.drawSubLevel and texture.drawLayer == "ARTWORK")
    assert(texture.snapToPixelGrid == false and texture.texelSnappingBias == 0)
    Near(texture.width, tile.width * ns.Window.renderer.fit)
    Near(texture.height, tile.height * ns.Window.renderer.fit)
    assert(texture.uv[1] == 0 and texture.uv[2] == 1 and texture.uv[3] == 0 and texture.uv[4] == 1)
end
local initialPoolSize, initialRequests = #frames, #requests
-- Repeated list -> map -> list navigation reuses the same frames/textures and never leaves stale art behind.
for _ = 1, 5 do
    Click(ns.Window.backButton)
    assert(ns.Window.view == "list" and not ns.Window.renderer.canvas:IsShown())
    AssertCleared()
    Click(assert(FindRow(389)))
    assert(ns.Window.renderer.composition == canonical)
end
assert(#frames == initialPoolSize) -- no frame/texture reconstruction while navigating
ns.Window.frame:SetSize(1100, 400)
local width, height = ns.Window.renderer.canvas:GetSize()
Near(width / height, canonical.width / canonical.height)
ns.Window.frame:SetSize(450, 800)
width, height = ns.Window.renderer.canvas:GetSize()
Near(width / height, canonical.width / canonical.height)
assert(ns.Window.renderer.canvas.points.CENTER[2] == ns.Window.mapArea)
-- RFC shows its four boss pins automatically (no development flag, no authoring mode).
local shownPins = {}
for _, marker in ipairs(ns.Window.renderer.overlay.pool) do if marker:IsShown() then shownPins[#shownPins + 1] = marker.title end end
assert(#shownPins == 4, "RFC pins: " .. #shownPins)

-- Back preserves the window position/size; the list resizes with the window.
Click(ns.Window.backButton)
ns.Window.frame:SetSize(700, 500)
ns.Window.frame:ClearAllPoints()
ns.Window.frame:SetPoint("CENTER", UIParent, "CENTER", 55, -25)
ns.Window:Save()
assert(ns.db.window.shown and ns.db.window.width == 700 and ns.db.window.height == 500)
assert(ns.Window.listChild:GetWidth() == 700 - 24)
ns = LoadAddon() -- same SavedVariables; no fake in-game API evidence
Event("PLAYER_ENTERING_WORLD")
assert(ns.Window.frame:IsShown() and ns.Window.view == "list")
assert(ns.Window.frame:GetWidth() == 700 and ns.db.window.x == 55 and ns.db.window.y == -25)

-- Combat: an existing window keeps working; first creation is deferred.
local beforeCombat = #frames
fixture.combat = true
Event("PLAYER_REGEN_DISABLED")
SlashCmdList.DUNGEONLENS("close")
AssertCleared()
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.frame:IsShown() and #frames == beforeCombat)
Click(assert(FindRow(389)))
assert(ns.Window.renderer.composition ~= nil) -- pin frames are plain (non-secure) and created lazily; the texture pool is preallocated
fixture.combat = false
Event("PLAYER_REGEN_ENABLED")
SlashCmdList.DUNGEONLENS("close")
assert(not ns.db.window.shown); AssertCleared()
ns = LoadAddon()
fixture.combat = true
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.pendingOpen and ns.Window.frame == nil)
fixture.combat = false
Event("PLAYER_REGEN_ENABLED")
assert(ns.Window.frame:IsShown() and ns.Window.view == "list")

-- Development diagnostics operate separately; normal open clears their foreground.
SlashCmdList.DUNGEONLENS("scan composite canonical")
assert(ns.Composite.frame:IsShown())
SlashCmdList.DUNGEONLENS("")
assert(not ns.Composite.frame:IsShown() and ns.Window.view == "list")
-- Optional snapping APIs may be absent; the measured layout remains identical.
methods.SetSnapToPixelGrid, methods.SetTexelSnappingBias = nil, nil
Click(assert(FindRow(389)))
assert(ns.Window.renderer.composition ~= nil)
-- ESC list registration and no polling.
local escapable = false
for _, name in ipairs(UISpecialFrames) do if name == "DungeonLensWindow" then escapable = true end end
assert(escapable)
for _, object in ipairs(frames) do assert(object.scripts.OnUpdate == nil) end
print("PASS: RFC-only hand registry, shared canonical object/math, list -> map -> back navigation without stale textures, boss pins, resize, SavedVariables, combat-safe pool reuse.")
