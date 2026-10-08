-- Dumps every registered layout (every floor) computed by the REAL addon code into the globals
-- LayoutReport / BossReport so scripts/Verify-Layout.py and scripts/Build-Previews.py consume exactly what
-- the addon would draw (no second implementation of the composition in the QA path).
local ns = ...
LayoutReport, BossReport, EntryReport = {}, {}, {}
for _, row in ipairs(ns.MapRegistry:List()) do
    local entry = row.entry
    EntryReport[row.instanceID] = { name = entry.displayName, verified = entry.verified == true, sourceType = entry.sourceType,
        floors = ns.WMOComposition:FloorCount(entry), stackDepth = entry.stackDepth or 1, floorSource = entry.floorSource or "n/a",
        tileCount = entry.tileCount }
    for floor = 1, ns.WMOComposition:FloorCount(entry) do
        local layout = assert(ns.WMOComposition:GetLayout(entry, floor))
        local tiles = {}
        for index, tile in ipairs(layout.tiles) do
            tiles[index] = { tile.fileDataID, tile.x, tile.y, tile.width, tile.height, tile.drawSubLevel,
                tile.u0 or 0, tile.v0 or 0, tile.u1 or 1, tile.v1 or 1 }
        end
        LayoutReport[#LayoutReport + 1] = { id = row.instanceID, floor = floor, signature = ns.WMOComposition:Signature(entry, layout),
            width = layout.width, height = layout.height, tiles = tiles, kind = entry.sourceType }
    end
    local data = ns.MapMarkers:Get(row.instanceID)
    if data then
        local bosses = {}
        for index, boss in ipairs(data.bosses or {}) do
            bosses[index] = { id = boss.id, name = boss.name, status = boss.status or "verified-client", confidence = boss.confidence,
                floor = boss.floor, x = boss.x, y = boss.y, layout = data.layouts and data.layouts[boss.floor or 1] }
        end
        BossReport[row.instanceID] = bosses
    end
end
