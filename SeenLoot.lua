local _, ns = ...
local Seen = { windowSeconds = 300 }
ns.SeenLoot = Seen

-- "Seen by you": items this character actually looted from a boss kill, stored in DungeonLensDB.seenLoot[encounterID][itemID] = count.
-- Attribution: ENCOUNTER_END(success) carries the same DungeonEncounter ID as BossData.lua/LootData.lua, and a loot slot only counts when
-- its source GUID is one of the boss units seen during that encounter (so trash looted after a boss is never credited to it). If the
-- client exposed no boss units, loot opened within `windowSeconds` of the kill is accepted instead. This is personal observation, not
-- verified data: the panel shows it in a separate section and /dlmap lootexport prints it for review.
local boss = { guids = {} } -- boss unit GUIDs seen during the current/last encounter
local kill -- { id = encounterID, time = GetTime() } of the last successful boss kill
local LOOT_SLOT_ITEM = 1

local function Now()
    local probe = ns.Probe(GetTime)
    return probe.status == "ok" and ns.IsNumber(probe.values[1]) and probe.values[1] or 0
end

local function CaptureBossUnits()
    for index = 1, 8 do
        local probe = ns.Probe(UnitGUID, "boss" .. index)
        local guid = probe.status == "ok" and probe.values[1]
        if type(guid) == "string" then boss.guids[guid] = true end
    end
end

local function ItemID(link)
    local id = type(link) == "string" and link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

function Seen:Store(encounterID, itemID, count)
    if not (ns.db and ns.IsID(encounterID) and ns.IsID(itemID)) then return end
    if type(ns.db.seenLoot) ~= "table" then ns.db.seenLoot = {} end
    local byBoss = ns.db.seenLoot[encounterID]
    if type(byBoss) ~= "table" then byBoss = {}; ns.db.seenLoot[encounterID] = byBoss end
    byBoss[itemID] = (tonumber(byBoss[itemID]) or 0) + (count or 1)
end

-- Items the player has seen drop from this boss that the verified list does not already contain, sorted by itemID.
function Seen:ForBoss(encounterID)
    local result, known = {}, {}
    local verified = ns.BossLoot and ns.BossLoot[encounterID]
    for _, item in ipairs(verified and verified.items or {}) do known[item.itemID] = true end
    local stored = ns.db and type(ns.db.seenLoot) == "table" and ns.db.seenLoot[encounterID]
    if type(stored) == "table" then
        for itemID, count in pairs(stored) do
            if not known[itemID] then result[#result + 1] = { itemID = itemID, count = count, seen = true } end
        end
    end
    table.sort(result, function(a, b) return a.itemID < b.itemID end)
    return result
end

function Seen:OnLootOpened()
    if not kill or Now() - kill.time > self.windowSeconds then return end
    local slots = ns.Probe(GetNumLootItems)
    local total = slots.status == "ok" and ns.IsNumber(slots.values[1]) and slots.values[1] or 0
    local haveGuids = next(boss.guids) ~= nil
    local bossCorpse = false
    for slot = 1, total do
        local accept = not haveGuids
        if haveGuids then
            local source = ns.Probe(GetLootSourceInfo, slot)
            -- returns guid1, quantity1, guid2, quantity2, ... (several corpses when area-looting)
            for index = 1, 10, 2 do
                local guid = source.status == "ok" and source.values[index]
                if type(guid) == "string" and boss.guids[guid] then accept = true; bossCorpse = true end
            end
        end
        local slotType = ns.Probe(GetLootSlotType, slot)
        if accept and slotType.status == "ok" and slotType.values[1] == LOOT_SLOT_ITEM then
            local link = ns.Probe(GetLootSlotLink, slot)
            local info = ns.Probe(GetLootSlotInfo, slot)
            local itemID = link.status == "ok" and ItemID(link.values[1])
            local quantity = info.status == "ok" and ns.IsNumber(info.values[3]) and info.values[3] or 1
            if itemID then self:Store(kill.id, itemID, quantity) end
        end
    end
    -- Standing at the boss's own corpse (loot range) is the most reliable place to learn where it was. Only with a GUID match.
    if bossCorpse and not kill.positioned then
        kill.positioned = true
        self:RecordPosition(kill.id)
    end
end

-- ---- boss positions: raw UnitPosition returns, stored per dungeon and boss; converted to the map only when drawn ----
local MAX_SAMPLES = 5

function Seen:RecordPosition(encounterID)
    local live = ns.state
    local instanceID = live and live.inInstance and live.instanceID
    if not (ns.db and ns.IsID(instanceID) and ns.IsID(encounterID) and ns.PlayerPosition) then return end
    local a, b, z, mapID = ns.PlayerPosition:Sample()
    if not a or (mapID and mapID ~= instanceID) then return end
    if type(ns.db.seenBossPos) ~= "table" then ns.db.seenBossPos = {} end
    local byDungeon = ns.db.seenBossPos[instanceID]
    if type(byDungeon) ~= "table" then byDungeon = {}; ns.db.seenBossPos[instanceID] = byDungeon end
    local record = byDungeon[encounterID]
    if type(record) ~= "table" or type(record.samples) ~= "table" then record = { samples = {} }; byDungeon[encounterID] = record end
    table.insert(record.samples, { a, b, z })
    while #record.samples > MAX_SAMPLES do table.remove(record.samples, 1) end
end

-- Mean of the stored samples (same frame, so averaging raw values is valid), or nil.
function Seen:BossPoint(instanceID, encounterID)
    local record = ns.db and type(ns.db.seenBossPos) == "table" and ns.db.seenBossPos[instanceID]
    record = type(record) == "table" and record[encounterID]
    if type(record) ~= "table" or type(record.samples) ~= "table" or #record.samples == 0 then return nil end
    local a, b, z, n = 0, 0, 0, 0
    for _, sample in ipairs(record.samples) do
        if ns.IsNumber(sample[1]) and ns.IsNumber(sample[2]) and ns.IsNumber(sample[3]) then
            a, b, z, n = a + sample[1], b + sample[2], z + sample[3], n + 1
        end
    end
    if n == 0 then return nil end
    return a / n, b / n, z / n
end

-- Where a boss you have looted sits on this map: floor, normalized x, y (or nil).
function Seen:LocateBoss(entry, instanceID, encounterID)
    local a, b, z = self:BossPoint(instanceID, encounterID)
    if not a or not ns.PlayerPosition then return nil end
    return ns.PlayerPosition:LocateEither(entry, a, b, z)
end

function Seen:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        boss.guids = {}
        CaptureBossUnits()
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        CaptureBossUnits()
    elseif event == "ENCOUNTER_END" then
        local encounterID, _, _, _, success = ...
        CaptureBossUnits()
        if success == 1 and ns.IsID(encounterID) then kill = { id = encounterID, time = Now() } end
    elseif event == "LOOT_OPENED" then
        self:OnLootOpened()
    end
end

-- Developer export: paste into an issue / hand to the maintainer to promote verified IDs into LootData.
function Seen:Export()
    local ids = {}
    for encounterID in pairs(ns.db and type(ns.db.seenLoot) == "table" and ns.db.seenLoot or {}) do ids[#ids + 1] = encounterID end
    table.sort(ids)
    if #ids == 0 then ns.Print("No boss loot recorded yet."); return end
    for _, encounterID in ipairs(ids) do
        local parts = {}
        for _, item in ipairs(self:ForBoss(encounterID)) do parts[#parts + 1] = item.itemID .. (item.count > 1 and ("x" .. item.count) or "") end
        local verified = ns.BossLoot and ns.BossLoot[encounterID] and #ns.BossLoot[encounterID].items or 0
        ns.Print(string.format("encounter %d (%d verified): new items %s", encounterID, verified, #parts > 0 and table.concat(parts, ", ") or "-"))
    end
end

-- Developer export of learned boss positions (raw UnitPosition values: first, second, height).
function Seen:ExportPositions()
    local rows = {}
    for instanceID, bosses in pairs(ns.db and type(ns.db.seenBossPos) == "table" and ns.db.seenBossPos or {}) do
        for encounterID in pairs(bosses) do
            local a, b, z = self:BossPoint(instanceID, encounterID)
            if a then rows[#rows + 1] = { instanceID, encounterID, a, b, z, #bosses[encounterID].samples } end
        end
    end
    table.sort(rows, function(x, y) if x[1] == y[1] then return x[2] < y[2] end return x[1] < y[1] end)
    if #rows == 0 then ns.Print("No boss positions recorded yet."); return end
    for _, row in ipairs(rows) do
        ns.Print(string.format("dungeon %d encounter %d: position %.1f, %.1f, %.1f (%d sample%s)", row[1], row[2], row[3], row[4], row[5],
            row[6], row[6] == 1 and "" or "s"))
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "LOOT_OPENED" }) do
    pcall(frame.RegisterEvent, frame, event) -- an event the client does not have simply never fires
end
frame:SetScript("OnEvent", function(_, event, ...) Seen:OnEvent(event, ...) end)
