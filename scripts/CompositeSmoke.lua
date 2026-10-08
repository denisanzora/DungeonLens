-- Experimental compositor invariants; synthetic client API, measured geometry.
local ns, fixture, methods, frames = ...
fixture.mapID, fixture.instanceID, fixture.inside, fixture.kind = nil, 389, true, "party"
function GetInstanceInfo() return "Ragefire Chasm", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID end
C_Map.GetMapInfo = function() error("Composite must not infer a UiMap from InstanceID") end
C_Map.GetPlayerMapPosition = function() error("Composite must not query player position") end
local assets, setTexture = {}, methods.SetTexture
function methods:SetTexture(asset)
    if asset ~= nil then assert(type(asset) == "number"); assets[#assets + 1] = asset end
    return setTexture(self, asset)
end
local function Near(actual, expected) assert(math.abs(actual - expected) < 0.000001) end
local function Index(records, key)
    local result = {}
    for _, value in ipairs(records) do result[value[key]] = value end
    return result
end
local expectedGroups = Index(ExpectedRFC.groups, "groupIndex")
local expectedImages = Index(ExpectedRFC.tileDimensions, "fileDataID")
local expectedTiles = Index(ExpectedRFC.minimapTiles, "fileDataID")
local expectedEnvelope = ExpectedRFC.placement.trialEnvelope
ns.Refresh("RFC composite model")
local originalState, geometry = ns.state, ns.db.window
local normal = assert(ns.Composite:BuildLayout("normal"))
local flipped = assert(ns.Composite:BuildLayout("flipy"))
local canonical = assert(ns.Composite:BuildLayout("canonical"))
assert(#normal.groups == 12 and #normal.tiles == 19 and normal.matchedGroups == 12)
assert(ns.Composite:BuildLayout("local-flipy") == nil)
for _, key in ipairs({ "minX", "minY", "maxX", "maxY", "width", "height" }) do Near(normal[key], expectedEnvelope[key]) end
local flippedGroups = Index(flipped.groups, "index")
for _, group in ipairs(normal.groups) do
    local expected = expectedGroups[group.index]
    for axis = 1, 3 do
        assert(group.minimum[axis] == expected.minimum[axis] and group.maximum[axis] == expected.maximum[axis])
    end
    Near(group.rawX, expected.minimum[1] * 2); Near(group.rawY, expected.minimum[2] * 2)
    local counterpart = flippedGroups[group.index]
    Near(group.y + counterpart.y, normal.height - group.height)
    Near(group.x, counterpart.x)
end
local normalTiles, flippedTiles = Index(normal.tiles, "fileDataID"), Index(flipped.tiles, "fileDataID")
for fileID, tile in pairs(normalTiles) do
    local image, localData = expectedImages[fileID], expectedTiles[fileID]
    assert(tile.width == image.width and tile.height == image.height and tile.groupIndex == localData.groupIndex)
    Near(tile.offsetX, localData.localX * 256); Near(tile.offsetY, localData.localY * 256)
    local alternate = flippedTiles[fileID]
    assert(alternate.offsetX == tile.offsetX and alternate.offsetY == tile.offsetY)
    assert(tile.x >= 0 and tile.y >= 0 and tile.x + tile.width <= normal.width + 0.000001
        and tile.y + tile.height <= normal.height + 0.000001)
end
Near(flippedTiles[213058].y - flippedTiles[213057].y, 256) -- no local-Y reversal
Near(normalTiles[213058].y - normalTiles[213057].y, 256)
assert(normalTiles[213057].x % 1 ~= 0) -- fractional origins have not been rounded

-- Canonical is a per-logical-cell transform, not a whole-group reflection.
assert(#canonical.tiles == 19 and #canonical.groups == 12)
local canonicalTiles = Index(canonical.tiles, "fileDataID")
local independentCells = {}
for _, tile in ipairs(ExpectedRFC.minimapTiles) do
    local group = expectedGroups[tile.groupIndex]
    independentCells[#independentCells + 1] = { group.minimum[1] * 2 + tile.localX * 256,
        group.minimum[2] * 2 + tile.localY * 256 }
end
local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
for _, cell in ipairs(independentCells) do
    minX, minY = math.min(minX, cell[1]), math.min(minY, cell[2])
    maxX, maxY = math.max(maxX, cell[1] + 256), math.max(maxY, cell[2] + 256)
end
Near(canonical.minX, minX); Near(canonical.minY, minY)
Near(canonical.maxX, maxX); Near(canonical.maxY, maxY)
Near(canonical.width, maxX - minX); Near(canonical.height, maxY - minY)
for _, pair in ipairs({ { 213057, 213058 }, { 213062, 213063 }, { 213064, 213065 }, { 213066, 213067 } }) do
    assert(canonicalTiles[pair[2]].cellY < canonicalTiles[pair[1]].cellY)
    Near(canonicalTiles[pair[2]].cellY - canonicalTiles[pair[1]].cellY, -256)
end
local offsets = { [213056] = 128, [213069] = 192, [213070] = 192,
    [213071] = 128, [213072] = 192, [213073] = 128 }
for fileID, offset in pairs(offsets) do
    local tile = canonicalTiles[fileID]
    Near(tile.y - tile.cellY, offset); Near(tile.x, tile.cellX)
    assert(tile.width == expectedImages[fileID].width and tile.height == expectedImages[fileID].height)
end
for index, tile in ipairs(canonical.tiles) do
    assert(tile.cellWidth == 256 and tile.cellHeight == 256)
    assert(tile.zOrder == expectedGroups[tile.groupIndex].minimum[3])
    Near(tile.cellX + 256 - tile.cellX, 256); Near(tile.cellY + 256 - tile.cellY, 256)
    assert(tile.x + tile.width <= tile.cellX + 256 + 0.000001)
    Near(tile.y + tile.height, tile.cellY + 256) -- bottom, not top or center
    if index > 1 then assert(canonical.tiles[index - 1].zOrder <= tile.zOrder) end
end
-- Check every actual intersecting content pair, not just the sorted sequence.
local overlaps = 0
for first = 1, #canonical.tiles do
    for second = first + 1, #canonical.tiles do
        local a, b = canonical.tiles[first], canonical.tiles[second]
        if a.groupIndex ~= b.groupIndex and a.x < b.x + b.width and b.x < a.x + a.width
            and a.y < b.y + b.height and b.y < a.y + a.height then
            overlaps = overlaps + 1
            assert(a.zOrder <= b.zOrder and a.drawSubLevel < b.drawSubLevel)
        end
    end
end
assert(overlaps > 0)

SlashCmdList.DUNGEONLENS("scan composite")
assert(ns.Composite.frame:IsShown() and ns.Composite.layout.mode == "normal")
assert(#assets == 19 and #ns.Composite.outlines == 12)
for index, tile in ipairs(ns.Composite.layout.tiles) do
    local texture = ns.Composite.textures[index]
    assert(texture.textureID == tile.fileDataID)
    Near(texture.width, tile.width * ns.Composite.fit); Near(texture.height, tile.height * ns.Composite.fit)
    Near(texture.points.TOPLEFT[4], tile.x * ns.Composite.fit)
    Near(texture.points.TOPLEFT[5], -tile.y * ns.Composite.fit)
    assert(texture.uv[1] == 0 and texture.uv[2] == 1 and texture.uv[3] == 0 and texture.uv[4] == 1)
end
local canvasWidth, canvasHeight = ns.Composite.canvas:GetSize()
Near(canvasWidth / canvasHeight, normal.width / normal.height)
SlashCmdList.DUNGEONLENS("scan composite flipy")
assert(ns.Composite.layout.mode == "flipy" and #assets == 38)
SlashCmdList.DUNGEONLENS("scan composite canonical")
assert(ns.Composite.layout.mode == "canonical" and #assets == 57 and #ns.Composite.cellOutlines == 19)
for index, tile in ipairs(ns.Composite.layout.tiles) do
    local texture = ns.Composite.textures[index]
    assert(texture.drawLayer == "ARTWORK" and texture.drawSubLevel == tile.drawSubLevel)
    Near(texture.width, tile.width * ns.Composite.fit); Near(texture.height, tile.height * ns.Composite.fit)
    Near(texture.points.TOPLEFT[4], tile.cellX * ns.Composite.fit)
    Near(texture.points.TOPLEFT[5], -(tile.cellY + tile.anchorY) * ns.Composite.fit)
    assert(texture.uv[1] == 0 and texture.uv[2] == 1 and texture.uv[3] == 0 and texture.uv[4] == 1)
    local logicalTop = ns.Composite.cellOutlines[index].edges[1]
    Near(logicalTop.width, 256 * ns.Composite.fit)
    if offsets[tile.fileDataID] then
        local content = ns.Composite.contentOutlines[index].edges[1]
        assert(content:IsShown()); Near(content.width, tile.width * ns.Composite.fit)
        Near(content.points.TOPLEFT[5], -(tile.cellY + offsets[tile.fileDataID]) * ns.Composite.fit)
    end
end
local canonicalCanvasWidth, canonicalCanvasHeight = ns.Composite.canvas:GetSize()
Near(canonicalCanvasWidth / canonicalCanvasHeight, canonical.width / canonical.height)
SlashCmdList.DUNGEONLENS("scan composite")
for _, outline in pairs(ns.Composite.contentOutlines) do assert(not outline.edges[1]:IsShown()) end
for _, outline in pairs(ns.Composite.cellOutlines) do assert(not outline.edges[1]:IsShown()) end
assert(ns.state == originalState and ns.db.window == geometry and ns.Window.frame == nil)
assert(DungeonLensMaps == nil)
local beforeGate = #assets
fixture.combat = true
SlashCmdList.DUNGEONLENS("scan composite")
assert(#assets == beforeGate)
fixture.combat = false
ns.development = false
SlashCmdList.DUNGEONLENS("scan composite")
assert(#assets == beforeGate)
ns.development = true
local buildInfo = GetBuildInfo
function GetBuildInfo() return "1.60.1", "70009", "test", 16001 end
SlashCmdList.DUNGEONLENS("scan composite")
assert(#assets == beforeGate + 19 and ns.Composite.frame:IsShown())
beforeGate = #assets
GetBuildInfo = buildInfo
fixture.instanceID = 2999
SlashCmdList.DUNGEONLENS("scan composite")
assert(#assets == beforeGate and not ns.Composite.frame:IsShown())
fixture.instanceID = 389
SlashCmdList.DUNGEONLENS("scan composite")
fixture.instanceID = 42
ns.events.scripts.OnEvent(ns.events, "ZONE_CHANGED_NEW_AREA")
assert(not ns.Composite.frame:IsShown())
fixture.instanceID = 389
SlashCmdList.DUNGEONLENS("scan composite")
SlashCmdList.DUNGEONLENS("scan stop")
assert(not ns.Composite.frame:IsShown())
for _, frame in ipairs(frames) do assert(frame.scripts.OnUpdate == nil) end
print("PASS: canonical local-Y reversal for groups 001/003/004, all six crop anchors, logical-cell envelope, overlapping MOGI min-Z draw sublevels, unchanged UVs, native sizes, outlines, uniform fit and legacy-mode isolation.")
print("PASS: original 12-group/19-tile trials, metadata equality, fractional origins, numeric-only assets, gates and stale cleanup; production selection unchanged.")
