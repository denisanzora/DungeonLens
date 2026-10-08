local _, ns = ...
local Composition = {}
ns.WMOComposition = Composition
local canonicalLayouts = {}

local function NextPowerOfTwo(value)
    local power = 1
    while power < value do power = power * 2 end
    return power
end

-- Native stitched-raster edge for a group extent already scaled by rho. BLPs are at
-- least 32 px; up to one 256 px cell they are powers of two; larger groups are whole
-- 256 px cells. Verified on 760/760 tiled groups of all 14 dungeon WMOs (build 70245);
-- RFC satisfies this and the earlier plain next-power-of-two rule identically.
local function RasterEdge(value)
    if value <= 256 then return math.max(32, NextPowerOfTwo(value)) end
    return math.ceil(value / 256 - 1e-9) * 256
end

-- Shared accepted layout. normal/flipy remain diagnostic comparison controls;
-- production calls canonical only. Every result is derived, not registry state.
-- Floor membership: entry.floors = { { floor = n, groups = { MOGI indexes } }, ... } (Blizzard's own
-- floor assignment, transferred by WMOAreaTable group ID). No floors table = one floor with every group.
function Composition:FloorCount(entry)
    return entry and entry.floors and #entry.floors or 1
end

local function FloorGroupSet(entry, floor)
    if not entry.floors then
        if floor == 1 then return nil end
        return false
    end
    for _, record in ipairs(entry.floors) do
        if record.floor == floor then
            local set = {}
            for _, index in ipairs(record.groups) do set[index] = true end
            return set
        end
    end
    return false
end

function Composition:BuildLayout(entry, mode, floor)
    mode = mode or "canonical"
    floor = floor or 1
    if not entry or entry.sourceType ~= "blizzard-wmo-minimap" then return nil, "No WMO map metadata." end
    if mode ~= "normal" and mode ~= "flipy" and mode ~= "canonical" then return nil, "Unknown composite mode." end
    local floorSet = FloorGroupSet(entry, floor)
    if floorSet == false then return nil, "No such floor." end
    local result = { mode = mode, rho = entry.rho, stride = entry.logicalBlockWidth, groups = {}, tiles = {}, matchedGroups = 0,
        floor = floor, floorCount = self:FloorCount(entry),
        minX = math.huge, minY = math.huge, maxX = -math.huge, maxY = -math.huge }
    for _, record in ipairs(entry.groups) do
      if not floorSet or floorSet[record.index] then
        local group = { index = record.index, rawX = record.minimum[1] * result.rho,
            rawY = record.minimum[2] * result.rho,
            minimum = { unpack(record.minimum) }, maximum = { unpack(record.maximum) },
            width = 0, height = 0, logicalWidth = 0, logicalHeight = 0, tiles = {} }
        for _, tuple in ipairs(record.tiles) do
            local tile = { fileDataID = tuple[1], localX = tuple[2], localY = tuple[3], width = tuple[4], height = tuple[5],
                offsetX = tuple[2] * result.stride, offsetY = tuple[3] * result.stride, groupIndex = record.index,
                cellWidth = result.stride, cellHeight = result.stride, zOrder = record.minimum[3] }
            group.width = math.max(group.width, tile.offsetX + tile.width)
            group.height = math.max(group.height, tile.offsetY + tile.height)
            group.logicalWidth = math.max(group.logicalWidth, tile.offsetX + result.stride)
            group.logicalHeight = math.max(group.logicalHeight, tile.offsetY + result.stride)
            group.tiles[#group.tiles + 1] = tile
        end
        if group.width ~= RasterEdge(result.rho * (record.maximum[1] - record.minimum[1]))
            or group.height ~= RasterEdge(result.rho * (record.maximum[2] - record.minimum[2])) then
            return nil, "Native raster evidence mismatch; no map shown."
        end
        result.matchedGroups = result.matchedGroups + 1
        if mode == "canonical" then
            for _, tile in ipairs(group.tiles) do
                tile.absX, tile.absY = group.rawX + tile.offsetX, group.rawY + tile.offsetY
                result.minX, result.minY = math.min(result.minX, tile.absX), math.min(result.minY, tile.absY)
                result.maxX = math.max(result.maxX, tile.absX + result.stride)
                result.maxY = math.max(result.maxY, tile.absY + result.stride)
            end
        else
            result.minX, result.minY = math.min(result.minX, group.rawX), math.min(result.minY, group.rawY)
            result.maxX = math.max(result.maxX, group.rawX + group.width)
            result.maxY = math.max(result.maxY, group.rawY + group.height)
        end
        result.groups[#result.groups + 1] = group
      end
    end
    if #result.groups == 0 then return nil, "Floor has no groups." end
    result.width, result.height = result.maxX - result.minX, result.maxY - result.minY
    table.sort(result.groups, function(a, b)
        if a.minimum[3] == b.minimum[3] then return a.index < b.index end
        return a.minimum[3] < b.minimum[3]
    end)
    for rank, group in ipairs(result.groups) do
        group.x = group.rawX - result.minX
        if mode == "flipy" then group.y = result.maxY - (group.rawY + group.height)
        else group.y = group.rawY - result.minY end
        for _, tile in ipairs(group.tiles) do
            -- SetDrawLayer sublevels span -8..7. Up to 16 groups keep the accepted RFC
            -- one-group-per-sublevel order; larger maps bucket by ascending min-Z and
            -- rely on pool (creation) order inside a bucket, which is also z order.
            if #result.groups <= 16 then tile.drawSubLevel = rank - 9
            else tile.drawSubLevel = -8 + math.floor((rank - 1) * 16 / #result.groups) end
            if mode == "canonical" then
                tile.cellX = tile.absX - result.minX
                tile.cellY = result.maxY - result.stride - tile.absY
                tile.anchorX, tile.anchorY = 0, result.stride - tile.height
                tile.x, tile.y = tile.cellX, tile.cellY + tile.anchorY
            else
                tile.x, tile.y = group.x + tile.offsetX, group.y + tile.offsetY
            end
            result.tiles[#result.tiles + 1] = tile
        end
    end
    return result
end

-- Ground minimap entries: ADT-tile minimaps already drawn north-up by the client
-- (X right, Y down), one square texture per grid cell. No placement math.
function Composition:BuildGroundLayout(entry)
    if not entry or entry.sourceType ~= "blizzard-ground-minimap" then return nil, "No ground minimap metadata." end
    local size = entry.tileSize
    if not ns.IsNumber(size) or size <= 0 or not entry.tiles or #entry.tiles == 0 then
        return nil, "Ground minimap metadata incomplete; no map shown."
    end
    -- Optional crop (grid pixels): the dungeon is only part of a larger terrain map (e.g. the walled city of Ruins of Lordaeron).
    -- Tiles are clipped to the rectangle and drawn with matching UVs; the canvas is the crop size.
    local crop = entry.crop
    local cx, cy, cw, ch = 0, 0, entry.columns * size, entry.rows * size
    if crop then
        if not (ns.IsNumber(crop.x) and ns.IsNumber(crop.y) and ns.IsNumber(crop.width) and ns.IsNumber(crop.height)
            and crop.x >= 0 and crop.y >= 0 and crop.width > 0 and crop.height > 0
            and crop.x + crop.width <= cw and crop.y + crop.height <= ch) then
            return nil, "Ground crop outside declared grid; no map shown."
        end
        cx, cy, cw, ch = crop.x, crop.y, crop.width, crop.height
    end
    local result = { mode = "ground", width = cw, height = ch, tiles = {}, stride = size, matchedGroups = 0, groups = {} }
    for _, tuple in ipairs(entry.tiles) do
        local column, row = tuple[2] - entry.gridMinX, tuple[3] - entry.gridMinY
        if column < 0 or row < 0 or column >= entry.columns or row >= entry.rows then
            return nil, "Ground tile outside declared grid; no map shown."
        end
        local left, top = math.max(column * size, cx), math.max(row * size, cy)
        local right, bottom = math.min((column + 1) * size, cx + cw), math.min((row + 1) * size, cy + ch)
        if right > left and bottom > top then
            result.tiles[#result.tiles + 1] = { fileDataID = tuple[1], x = left - cx, y = top - cy,
                width = right - left, height = bottom - top, drawSubLevel = 0,
                u0 = (left - column * size) / size, u1 = (right - column * size) / size,
                v0 = (top - row * size) / size, v1 = (bottom - row * size) / size }
        end
    end
    if #result.tiles == 0 then return nil, "Ground crop contains no tiles; no map shown." end
    return result
end

function Composition:GetLayout(entry, floor)
    if not entry then return nil, "No map entry." end
    if entry.sourceType == "blizzard-ground-minimap" then
        if floor and floor ~= 1 then return nil, "No such floor." end
        canonicalLayouts[entry] = canonicalLayouts[entry] or {}
        if not canonicalLayouts[entry][1] then
            local layout, reason = self:BuildGroundLayout(entry)
            if not layout then return nil, reason end
            canonicalLayouts[entry][1] = layout
        end
        return canonicalLayouts[entry][1]
    end
    return self:GetCanonical(entry, floor)
end

-- Stable identity of the normalized coordinate space for marker data: markers are
-- authored against exactly this canvas, so a changed layout invalidates them.
function Composition:Signature(entry, layout)
    if not entry or not layout then return nil end
    local text = string.format("%s:%dx%d:%d", entry.sourceType == "blizzard-ground-minimap" and "ground" or "wmo",
        math.floor(layout.width + 0.5), math.floor(layout.height + 0.5), #layout.tiles)
    if self:FloorCount(entry) > 1 then text = text .. ":f" .. (layout.floor or 1) end
    return text
end

function Composition:GetCanonical(entry, floor)
    floor = floor or 1
    canonicalLayouts[entry] = canonicalLayouts[entry] or {}
    if not canonicalLayouts[entry][floor] then
        local layout, reason = self:BuildLayout(entry, "canonical", floor)
        if not layout then return nil, reason end
        canonicalLayouts[entry][floor] = layout
    end
    return canonicalLayouts[entry][floor]
end

function Composition:PrepareTexture(texture)
    texture:SetBlendMode("BLEND")
    -- Documented by the Forever API surface; guard availability. Fractional
    -- origins and uniform fit are retained, not rounded per texture.
    ns.Probe(ns.Field(texture, "SetSnapToPixelGrid"), texture, false)
    ns.Probe(ns.Field(texture, "SetTexelSnappingBias"), texture, 0)
end

function Composition:PositionTexture(texture, canvas, tile, fit)
    texture:SetDrawLayer("ARTWORK", tile.drawSubLevel)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", tile.x * fit, -tile.y * fit)
    texture:SetSize(tile.width * fit, tile.height * fit)
    texture:SetTexCoord(tile.u0 or 0, tile.u1 or 1, tile.v0 or 0, tile.v1 or 1)
end

function Composition:LoadTexture(texture, fileDataID)
    local probe = ns.Probe(ns.Field(texture, "SetTexture"), texture, fileDataID)
    local accepted = probe.status ~= "error" and probe.status ~= "unavailable" and probe.status ~= "restricted"
        and ns.Field(probe.values, 1) ~= false
    return accepted, ns.Field(probe.values, 1) == false and "returned-false" or probe.status
end
