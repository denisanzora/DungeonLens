local _, ns = ...
-- Recommended player level range per dungeon, keyed by instance (map) ID. Hand-maintained: the Forever client carries no LFGDungeons rows
-- for these maps, so the ranges come from foreverdb.net's dungeon list (a Forever-specific database), checked 2026-10-07.
ns.DungeonLevels = {
    [389] = { 13, 18 },   -- Ragefire Chasm
    [43] = { 15, 24 },    -- Wailing Caverns
    [36] = { 17, 26 },    -- Deadmines
    [33] = { 20, 30 },    -- Shadowfang Keep
    [48] = { 24, 32 },    -- Blackfathom Deeps
    [34] = { 24, 32 },    -- Stormwind Stockade
    [90] = { 29, 38 },    -- Gnomeregan
    [47] = { 29, 38 },    -- Razorfen Kraul
    [189] = { 30, 38 },   -- Scarlet Monastery
    [129] = { 37, 46 },   -- Razorfen Downs
    [70] = { 41, 51 },    -- Uldaman
    [3065] = { 13, 20 },  -- The Hall of Thanes
    [2999] = { 15, 22 },  -- Ruins of Lordaeron
    [2998] = { 26, 33 },  -- Excavation Site: Wetlands
}

function ns.LevelText(instanceID)
    local range = ns.DungeonLevels[instanceID]
    return range and ("Lv " .. range[1] .. "-" .. range[2]) or nil
end
