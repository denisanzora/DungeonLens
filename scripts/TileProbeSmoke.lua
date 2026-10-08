-- Focused diagnostic regression checks using the existing small API/UI stubs.
local ns, fixture, methods, frames, messages = ...
local pending, requested = {}, 0
fixture.mapID, fixture.instanceID, fixture.inside, fixture.kind = nil, 389, true, "party"
function GetInstanceInfo()
    local names = { [389] = "Ragefire Chasm", [2999] = "Ruins of Lordaeron" }
    return names[fixture.instanceID] or "Unknown", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID
end
C_Minimap = { GetUiMapID = function() return nil end }
C_Map.GetMapInfo = function() error("Tile probe must not pass InstanceID into UiMap lookup") end
C_Map.GetPlayerMapPosition = function() error("Tile probe must not request player positioning") end
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local setTexture = methods.SetTexture
function methods:SetTexture(asset)
    if asset ~= nil then requested = requested + 1 end
    return setTexture(self, asset)
end
function methods:IsObjectLoaded() return true end
function methods:GetTextureFileID()
    if type(self.textureID) == "number" then return self.textureID end
    if self.textureID and self.textureID:find("lavadungeon_001_00_00", 1, true) then return 213057 end
    return 7255736
end
local function Drain()
    local count = 0
    while #pending > 0 do
        count = count + 1
        assert(count < 10, "Probe introduced repeated polling")
        table.remove(pending, 1)()
    end
end
local function Cell(fileDataID)
    for _, cell in ipairs(ns.Diagnostics.activeTileCells) do
        if cell.metadata.fileDataID == fileDataID then return cell end
    end
    error("Expected probe file not found: " .. fileDataID)
end
local function Near(actual, expected) assert(math.abs(actual - expected) < 0.00001) end
ns.Refresh("RFC probe model")
local originalState, originalGeometry = ns.state, ns.db.window
SlashCmdList.DUNGEONLENS("scan tiles")
assert(ns.Diagnostics.tileContext.instanceID == 389 and #ns.Diagnostics.activeTileCells == 20)
assert(requested == 20 and ns.Diagnostics.tileFrame.scale <= 1)
assert(ns.Diagnostics.tileTitle.text:find("Ragefire Chasm", 1, true))
local origin = Cell(213057).texture.points.TOPLEFT
local right = Cell(213059).texture.points.TOPLEFT
local below = Cell(213058).texture.points.TOPLEFT
Near(right[4] - origin[4], 112); Near(right[5], origin[5])
Near(below[4], origin[4]); Near(below[5] - origin[5], -112)
assert(Cell(213056).texture.points.TOPLEFT[4] ~= origin[4]) -- repeated X/Y remain in different WMO panels
assert(Cell(213074).metadata.wmoGroup == 11)
Drain()
local rfcReport = ns.db.diagnostics.lastTileProbe
assert(rfcReport.context.instanceID == 389 and rfcReport.layoutKind == "wmo-group-local" and #rfcReport.results == 20)
assert(rfcReport.results[20].pathControlFileDataID == 213057 and rfcReport.results[20].reportedFileDataID == 213057)
assert(ns.state == originalState and ns.db.window == originalGeometry and ns.Window.frame == nil)

-- Superseded callbacks and spare pooled cells must not show the other dungeon.
SlashCmdList.DUNGEONLENS("scan tiles")
fixture.instanceID = 2999
SlashCmdList.DUNGEONLENS("scan tiles")
Drain()
local ruinsReport = ns.db.diagnostics.lastTileProbe
assert(ruinsReport.context.instanceID == 2999 and #ruinsReport.results == 10)
assert(Cell(7255712).metadata.tileX == 30 and Cell(7255712).metadata.tileY == 27)
assert(Cell(7255760).metadata.tileX == 32 and Cell(7255760).metadata.tileY == 29)
assert(ruinsReport.results[10].pathControlFileDataID == 7255736)
assert(#ns.Diagnostics.activeTileCells == 10)
for index = 11, #ns.Diagnostics.tileCells do
    local cell = ns.Diagnostics.tileCells[index]
    assert(not cell.texture:IsShown() and cell.texture.textureID == nil and not cell.label:IsShown())
end
fixture.instanceID = 42
SlashCmdList.DUNGEONLENS("scan tiles")
assert(not ns.Diagnostics.tileFrame:IsShown() and #ns.Diagnostics.activeTileCells == 0)
assert(messages[#messages]:find("No tile probe metadata is registered for InstanceID 42.", 1, true))

fixture.instanceID = 389
SlashCmdList.DUNGEONLENS("scan tiles")
fixture.instanceID = 42
ns.events.scripts.OnEvent(ns.events, "ZONE_CHANGED_NEW_AREA")
Drain()
assert(not ns.Diagnostics.tileFrame:IsShown() and ns.db.diagnostics.lastTileProbe == ruinsReport)
fixture.instanceID, fixture.combat = 389, true
local beforeGate = requested
SlashCmdList.DUNGEONLENS("scan tiles")
assert(requested == beforeGate)
fixture.combat = false
local buildInfo = GetBuildInfo
function GetBuildInfo() return "1.60.1", "70009", "test", 16001 end
SlashCmdList.DUNGEONLENS("scan tiles")
assert(requested == beforeGate + 20)
beforeGate = requested
GetBuildInfo = buildInfo
ns.development = false
SlashCmdList.DUNGEONLENS("scan tiles")
assert(requested == beforeGate)
ns.development = true
methods.IsObjectLoaded, methods.GetTextureFileID = nil, nil
SlashCmdList.DUNGEONLENS("scan tiles")
Drain()
assert(ns.db.diagnostics.lastTileProbe.results[1].loadedStatus == "unavailable")
SlashCmdList.DUNGEONLENS("scan stop")
assert(not ns.Diagnostics.tileFrame:IsShown())
for _, frame in ipairs(frames) do assert(frame.scripts.OnUpdate == nil) end
assert(DungeonLensMaps == nil)
print("PASS: RFC auto-selection, all 19 WMO tile requests, raw X/Y panel layout, unchanged 2999 identifiers, path controls, stale/cross-instance cleanup and probe-only API guards.")
