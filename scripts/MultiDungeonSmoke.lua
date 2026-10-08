-- Generated-registry / ground renderer / overlay / authoring regressions (Lua 5.1, stubbed client).
local ns, fixture, methods, frames, messages, LoadAddon = ...
fixture.instanceID, fixture.mapID, fixture.inside, fixture.kind = 389, nil, true, "party"
function GetInstanceInfo() return "Test", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID end
local function Event(event) ns.events.scripts.OnEvent(ns.events, event) end
local function Near(a, b, eps) assert(math.abs(a - b) < (eps or 1e-6), tostring(a) .. " ~= " .. tostring(b)) end
local function Enter(id)
    fixture.instanceID = id
    Event("PLAYER_ENTERING_WORLD")
end
local function Shown()
    local count = 0
    for _, tile in ipairs(ns.Window.renderer.tiles) do if tile:IsShown() and tile.textureID then count = count + 1 end end
    return count
end

local function Click(button) button.scripts.OnClick(button) end
function Row(id) -- first shown list row for a dungeon
    for _, row in ipairs(ns.Window.listRows) do
        if row:IsShown() and row.data and row.data.instanceID == id then return row end
    end
    error("no list row for " .. tostring(id))
end
local function OpenCurrent() -- the UI flow: /dlmap, then click the dungeon's row
    SlashCmdList.DUNGEONLENS("")
    Click(Row(fixture.instanceID))
end

-- Every listed dungeon (available or not) has a sane recommended-level range, and the browser row shows it.
SlashCmdList.DUNGEONLENS("")
local listed = 0
for _, row in ipairs(ns.Window.listRows) do
    if row:IsShown() and row.data then
        local range = ns.DungeonLevels[row.data.instanceID]
        assert(range and range[1] >= 1 and range[1] <= range[2] and range[2] <= 60, "no level range for " .. row.data.name)
        assert(row.level.text == "Lv " .. range[1] .. "-" .. range[2], "list row level text for " .. row.data.name)
        listed = listed + 1
    end
end
assert(listed >= 14, "all dungeons listed with levels")
ns.Window:Close()

-- Pool must cover the largest generated entry (Gnomeregan has 94 tiles).
assert(ns.MapRegistry:MaxTileCount() >= 94)
ns.db.candidates = true

-- RFC is still the hand-verified entry and its sublevels are the accepted rank-9 sequence.
Enter(389)
assert(ns.state.mapEntry.verified and ns.state.mapEntry.provenance.rootFileDataID == 109483)
local rfc = ns.state.composition
local minSub, maxSub = 99, -99
for _, tile in ipairs(rfc.tiles) do minSub, maxSub = math.min(minSub, tile.drawSubLevel), math.max(maxSub, tile.drawSubLevel) end
assert(minSub == -8 and maxSub == 3, "RFC sublevels changed")

-- Candidate WMO dungeon (Stockade): reuses the canonical renderer, flagged unverified.
Enter(34)
assert(ns.state.renderSource == "blizzard-wmo-minimap" and ns.state.hasMap and not ns.state.mapEntry.verified)
assert(ns.state.resolution.compatibility == "candidate-unverified")
OpenCurrent()
assert(Shown() == 26 and ns.Window.renderer.canvas:IsShown())
local signature = ns.WMOComposition:Signature(ns.state.mapEntry, ns.state.composition)
assert(signature:match("^wmo:%d+x%d+:26$"), signature)

-- Large stacked dungeon (Gnomeregan, 73 groups): every sublevel in range and z-ordered.
Enter(90)
assert(ns.state.renderSource == "blizzard-wmo-minimap" and ns.state.composition.mode == "canonical")
local last = -99
for _, tile in ipairs(ns.state.composition.tiles) do
    assert(tile.drawSubLevel >= -8 and tile.drawSubLevel <= 7, "sublevel out of range")
    assert(tile.drawSubLevel >= last, "sublevel order broke z order")
    last = tile.drawSubLevel
end
assert(ns.WMOComposition:FloorCount(ns.state.mapEntry) == 4)
local total = 0 -- floors partition-with-overlap the 94 tiles: connector groups appear on two floors
for floor = 1, 4 do total = total + #assert(ns.WMOComposition:GetLayout(ns.state.mapEntry, floor)).tiles end
assert(total >= 94 and #ns.state.composition.tiles < 94)
OpenCurrent()
assert(Shown() == #ns.state.composition.tiles)
for _, tile in ipairs(ns.Window.renderer.tiles) do
    if tile:IsShown() then assert(tile.drawSubLevel >= -8 and tile.drawSubLevel <= 7) end
end

-- Hall of Thanes is a WMO dungeon (its terrain-tile map had a blank cell and a grey backdrop): one floor, no pins (no coordinate source).
Enter(3065)
assert(ns.state.renderSource == "blizzard-wmo-minimap" and ns.state.composition.mode ~= "ground")
OpenCurrent()
assert(Shown() == #ns.state.composition.tiles and Shown() > 0)

-- Ground-tile renderer coverage: a second addon instance with a synthetic ground entry (the former Hall of Thanes terrain-tile data),
-- since no shipped dungeon uses ground tiles any more. The slash handler of the main instance is restored afterwards.
do
    local realSource, savedSlash = AddonSources["MapData.lua"], SlashCmdList.DUNGEONLENS
    AddonSources["MapData.lua"] = realSource .. [[
ns.GeneratedMaps[90065] = {
    instanceID = 90065, worldMapID = 90065, displayName = "Ground Fixture",
    sourceType = "blizzard-ground-minimap", verified = false, status = "candidate",
    tileSize = 512, gridMinX = 31, gridMinY = 30, columns = 2, rows = 3, tileCount = 5,
    provenance = { discoveredBuild = "1.60.1.70245", note = "test fixture" },
    tiles = { { 7726092, 32, 30 }, { 7726140, 31, 31 }, { 7726146, 32, 31 }, { 7726194, 31, 32 }, { 7726200, 32, 32 } },
}
]]
    local g = LoadAddon()
    AddonSources["MapData.lua"] = realSource
    fixture.instanceID = 90065
    g.events.scripts.OnEvent(g.events, "PLAYER_ENTERING_WORLD")
    assert(g.state.renderSource == "blizzard-ground-minimap" and g.state.composition.mode == "ground")
    local entry, ground = g.state.mapEntry, g.state.composition
    Near(ground.width, entry.columns * entry.tileSize); Near(ground.height, entry.rows * entry.tileSize)
    for _, tile in ipairs(ground.tiles) do
        assert(tile.width == 512 and tile.x % 512 == 0 and tile.y % 512 == 0 and tile.drawSubLevel == 0)
    end
    SlashCmdList.DUNGEONLENS("")
    for _, row in ipairs(g.Window.listRows) do
        if row:IsShown() and row.data and row.data.instanceID == 90065 then Click(row) end
    end
    assert(g.Window.view == "map")
    local count = 0
    for _, tile in ipairs(g.Window.renderer.tiles) do if tile:IsShown() and tile.textureID then count = count + 1 end end
    assert(count == entry.tileCount and not g.Window.floorNext:IsShown())
    SlashCmdList.DUNGEONLENS = savedSlash
    fixture.instanceID = 3065
end

-- Ground crop: the canvas is the crop rectangle, tiles are clipped to it with matching UVs, bad rectangles are rejected.
do
    local function entry(crop)
        return { sourceType = "blizzard-ground-minimap", tileSize = 512, gridMinX = 31, gridMinY = 30, columns = 2, rows = 3, crop = crop,
            tiles = { { 1, 32, 30 }, { 2, 31, 31 }, { 3, 32, 31 }, { 4, 31, 32 }, { 5, 32, 32 } } }
    end
    local layout = assert(ns.WMOComposition:BuildGroundLayout(entry({ x = 100, y = 200, width = 700, height = 800 })))
    assert(layout.width == 700 and layout.height == 800 and #layout.tiles == 3, "crop keeps only intersecting tiles")
    for _, tile in ipairs(layout.tiles) do
        assert(tile.x >= 0 and tile.y >= 0 and tile.x + tile.width <= 700 and tile.y + tile.height <= 800, "tile inside canvas")
        assert(tile.u0 >= 0 and tile.u1 <= 1 and tile.u1 > tile.u0 and tile.v1 > tile.v0, "valid UVs")
        Near(tile.width, (tile.u1 - tile.u0) * 512); Near(tile.height, (tile.v1 - tile.v0) * 512)
    end
    local full = assert(ns.WMOComposition:BuildGroundLayout(entry(nil)))
    assert(full.width == 1024 and full.height == 1536 and #full.tiles == 5 and full.tiles[1].u0 == 0 and full.tiles[1].u1 == 1)
    assert(not ns.WMOComposition:BuildGroundLayout(entry({ x = 900, y = 0, width = 400, height = 100 })), "crop outside grid rejected")
    assert(not ns.WMOComposition:BuildGroundLayout(entry({ x = 0, y = 0, width = 0, height = 10 })), "empty crop rejected")
end

-- Candidates disabled: generated entries vanish, RFC stays.
ns.db.candidates = false
Enter(90)
assert(ns.state.renderSource == "none" and not ns.state.hasMap and ns.state.resolution.compatibility == "incompatible")
Enter(389)
assert(ns.state.renderSource == "blizzard-wmo-minimap")
ns.db.candidates = true

-- Overlay + authoring: normalized coordinates survive resizing.
Enter(34)
OpenCurrent()
local renderer, canvas = ns.Window.renderer, ns.Window.renderer.canvas
function methods:GetLeft() return 100 end
function methods:GetTop() return 700 end
local cursor = { 0, 0 }
function GetCursorPosition() return cursor[1], cursor[2] end
SlashCmdList.DUNGEONLENS("author on")
assert(ns.Authoring.enabled)
local width, height = canvas:GetSize()
cursor = { 100 + 0.25 * width, 700 - 0.5 * height }
SlashCmdList.DUNGEONLENS("Author Boss Test Boss")
ns.Authoring.catcher.scripts.OnMouseUp(ns.Authoring.catcher, "LeftButton")
local store = ns.db.authoring[34][signature]
assert(store and #store.items == 1)
Near(store.items[1].x, 0.25, 1e-4); Near(store.items[1].y, 0.5, 1e-4)
local marker
for _, candidate in ipairs(renderer.overlay.pool) do
    if candidate:IsShown() and candidate.title == "Test Boss" then marker = candidate end
end
assert(marker, "authoring marker missing")
assert(marker:IsShown() and marker.title == "Test Boss")
Near(marker.points.CENTER[4], 0.25 * width, 1e-3); Near(marker.points.CENTER[5], -0.5 * height, 1e-3)
ns.Window.frame:SetSize(1100, 640) -- resize: canvas rescales, marker stays at the same fraction
local width2, height2 = canvas:GetSize()
assert(math.abs(width2 - width) > 1 or math.abs(height2 - height) > 1, "canvas did not resize")
Near(marker.points.CENTER[4], 0.25 * width2, 1e-3); Near(marker.points.CENTER[5], -0.5 * height2, 1e-3)
-- Click outside the canvas is rejected.
cursor = { 5, 5 }
ns.Authoring.catcher.scripts.OnMouseUp(ns.Authoring.catcher, "LeftButton")
assert(#store.items == 1)
-- Authored points are bound to the layout: another dungeon never shows them.
Enter(90)
OpenCurrent()
local function ShownTitled(title)
    for _, candidate in ipairs(renderer.overlay.pool) do
        if candidate:IsShown() and candidate.title == title then return true end
    end
    return false
end
assert(not ShownTitled("Test Boss"))
Enter(34)
OpenCurrent()
assert(ShownTitled("Test Boss"))
SlashCmdList.DUNGEONLENS("author undo")
assert(#ns.db.authoring[34][signature].items == 0 and not ShownTitled("Test Boss"))
SlashCmdList.DUNGEONLENS("author off")
assert(not ns.Authoring.enabled)

-- Click-through UI with the character NOT inside any instance: /dlmap -> list -> map -> back.
fixture.inside, fixture.kind = false, "none"
Event("PLAYER_ENTERING_WORLD")
local function Titled(title)
    for _, candidate in ipairs(renderer.overlay.pool) do
        if candidate:IsShown() and candidate.title == title then return true end
    end
    return false
end
local function Click(button) button.scripts.OnClick(button) end
local function Said(text)
    for _, message in ipairs(messages) do if message:find(text, 1, true) then return true end end
    return false
end
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.view == "list" and ns.Window.title.text == "Forever Dungeons" and not ns.Window.backButton:IsShown())
local listed, disabled = {}, {}
for _, row in ipairs(ns.Window.listRows) do
    if row:IsShown() then
        listed[#listed + 1] = row.data.name
        if row.data.disabled then disabled[#disabled + 1] = row.data.name end
    end
end
assert(#listed == 14, "listed dungeons: " .. #listed)
assert(#disabled == 1 and disabled[1] == "Excavation Site: Wetlands", "only Excavation Site is unavailable")
for _, header in ipairs(ns.Window.listHeaders) do assert(not header:IsShown(), "no CURRENT DUNGEON section outside an instance") end
assert(Row(389).bosses.text == "4 Bosses" and Row(90).floors.text == "4 Floors" and Row(33).floors.text == "7 Floors")
assert(Row(2998).floors.text == "Unavailable" and not Row(2998).chevron:IsShown())
Click(Row(2998)) -- disabled row: nothing happens, nothing crashes
assert(ns.Window.view == "list")
-- Normal text carries no development vocabulary.
for _, row in ipairs(ns.Window.listRows) do
    if row:IsShown() then
        for _, text in ipairs({ row.name.text, row.bosses.text, row.floors.text }) do
            assert(not text:lower():find("candidate") and not text:lower():find("wmo") and not text:lower():find("rho"), text)
        end
    end
end

Click(Row(34))
assert(ns.Window.view == "map" and ns.Window.title.text == "Stormwind Stockade" and ns.Window.backButton:IsShown())
assert(Shown() == 26 and Titled("Targorr the Dread") and not ns.Window.floorNext:IsShown())
assert(not ns.Window.message:IsShown())
Click(ns.Window.backButton)
assert(ns.Window.view == "list" and Shown() == 0 and not Titled("Targorr the Dread"), "back must release art and pins")
assert(Row(34).accent:IsShown(), "last opened dungeon is marked in the list")

Click(Row(389))
assert(ns.Window.title.text == "Ragefire Chasm" and Shown() == 19 and Titled("Bazzalan"))
Click(ns.Window.backButton)

-- Multi-floor dungeon: floor controls are buttons, and the bosses follow the floor.
Click(Row(90))
assert(ns.Window.floorNext:IsShown() and ns.Window.floorPrev:IsShown() and ns.Window.floorLabel.text == "Floor 1 of 4")
local floorOne = Shown()
Click(ns.Window.floorNext)
assert(ns.Window.floor == 2 and ns.Window.floorLabel.text == "Floor 2 of 4" and Shown() ~= floorOne)
assert(Titled("Electrocutioner 6000") and not Titled("Mekgineer Thermaplugg"), "bosses must follow their floor")
Click(ns.Window.floorNext); Click(ns.Window.floorNext)
assert(ns.Window.floor == 4 and Titled("Mekgineer Thermaplugg") and not Titled("Electrocutioner 6000"))
Click(ns.Window.floorNext) -- clamped at the last floor
assert(ns.Window.floor == 4)
Click(ns.Window.floorPrev); Click(ns.Window.floorPrev)
assert(ns.Window.floor == 2)
-- Approximate pins are hidden unless explicitly enabled.
assert(not Titled("Viscous Fallout"), "approximate pins hidden by default")
SlashCmdList.DUNGEONLENS("approximate on")
assert(Titled("Viscous Fallout"))
SlashCmdList.DUNGEONLENS("approximate off")
assert(not Titled("Viscous Fallout"))
Click(ns.Window.backButton)
Click(Row(90)) -- reopening starts at floor 1
assert(ns.Window.floor == 1)
Click(ns.Window.backButton)
-- Page-style dungeon: floors carry meaningful names.
Click(Row(189))
assert(ns.Window.floorLabel.text == "Graveyard (1 of 4)" and Titled("Interrogator Vishas"))
Click(ns.Window.floorNext)
assert(ns.Window.floorLabel.text == "Library (2 of 4)" and Titled("Arcanist Doan"))
Click(ns.Window.backButton)
-- Dungeon with no floors and no pins (no coordinate source) still opens.
Click(Row(3065))
assert(Shown() > 0 and not ns.Window.floorNext:IsShown())
Click(ns.Window.backButton)

-- Unverified candidates can be hidden; the hand-verified RFC remains.
ns.db.candidates = false
SlashCmdList.DUNGEONLENS("")
assert(Row(34).data.disabled and Row(34).floors.text == "Unavailable" and not Row(389).data.disabled)
Click(Row(34))
assert(ns.Window.view == "list")
ns.db.candidates = true
SlashCmdList.DUNGEONLENS("")
assert(not Row(34).data.disabled)
-- A map that fails to render says so in plain language and leaves the list reachable.
fixture.rejectTexture = true
Click(Row(34))
assert(ns.Window.message:IsShown() and ns.Window.message.text:find("couldn't be displayed", 1, true) and Shown() == 0)
fixture.rejectTexture = false
Click(ns.Window.backButton)

-- Repeated navigation neither leaks frames nor leaves stale textures.
Click(Row(90)); Click(ns.Window.backButton)
local settled = #frames
for _ = 1, 8 do
    for _, id in ipairs({ 389, 90, 33, 3065 }) do
        Click(Row(id))
        assert(ns.Window.view == "map" and Shown() > 0)
        Click(ns.Window.backButton)
        assert(Shown() == 0 and not renderer.canvas:IsShown())
        for _, tile in ipairs(renderer.tiles) do assert(not tile:IsShown() and tile.textureID == nil) end
    end
end
assert(#frames <= settled + 40, "frames grew during navigation: " .. (#frames - settled)) -- only lazily created pin frames
-- Resize in both views.
ns.Window.frame:SetSize(600, 500)
assert(ns.Window.listChild:GetWidth() == 600 - 24)
Click(Row(389))
ns.Window.frame:SetSize(1000, 450)
local cw, ch = renderer.canvas:GetSize()
Near(cw / ch, ns.state and ns.Window.lastState.composition.width / ns.Window.lastState.composition.height, 1e-6)
Click(ns.Window.backButton)
-- Current dungeon convenience section appears (only) when inside a supported dungeon; /dlmap still opens the list.
fixture.inside, fixture.kind = true, "party"
Enter(70)
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.view == "list" and ns.Window.listHeaders[1]:IsShown() and ns.Window.listHeaders[1].text == "CURRENT DUNGEON")
assert(ns.Window.listHeaders[2].text == "ALL DUNGEONS" and ns.Window.listRows[1].data.instanceID == 70)
-- Hidden conveniences still work but are not needed.
SlashCmdList.DUNGEONLENS("show 34")
assert(ns.Window.view == "map" and ns.Window.title.text == "Stormwind Stockade")
SlashCmdList.DUNGEONLENS("show excavation")
assert(Said("Excavation Site: Wetlands (2998) has no generated map yet") and ns.Window.title.text == "Stormwind Stockade")
SlashCmdList.DUNGEONLENS("list")
SlashCmdList.DUNGEONLENS("live")
assert(ns.Window.view == "map" and ns.Window.title.text == "Uldaman")
-- X closes; the window can reopen to the list.
Click(ns.Window.closeButton)
assert(not ns.Window.frame:IsShown() and ns.db.window.shown == false)
SlashCmdList.DUNGEONLENS("")
assert(ns.Window.frame:IsShown() and ns.Window.view == "list")

-- ---- Boss loot panel ----------------------------------------------------------------------------------
fixture.inside, fixture.kind = false, "none"
Event("PLAYER_ENTERING_WORLD")
local function Pin(title)
    for _, candidate in ipairs(renderer.overlay.pool) do
        if candidate:IsShown() and candidate.title == title then return candidate end
    end
    error("no pin for " .. title)
end
local function ClickPin(title) local pin = Pin(title); pin.scripts.OnMouseUp(pin, "LeftButton") end
local function LootRows()
    local rows = {}
    for _, row in ipairs(ns.BossPanel.rows) do if row:IsShown() then rows[#rows + 1] = row end end
    return rows
end
local panel = function() return ns.BossPanel.frame and ns.BossPanel.frame:IsShown() end

-- Data contract: keyed by the SAME encounter ID BossData uses; every item has a numeric itemID; no invented drop rates.
for bossID, data in pairs(ns.BossLoot) do
    assert(type(bossID) == "number" and #data.items > 0)
    for _, item in ipairs(data.items) do
        assert(type(item.itemID) == "number" and item.itemID > 0 and item.confidence:find("forever", 1, true) and item.dropRate == nil)
    end
end
local knownBoss = {}
for _, dungeon in pairs(ns.GeneratedBosses) do for _, boss in ipairs(dungeon.bosses) do knownBoss[boss.id] = true end end
for bossID in pairs(ns.BossLoot) do assert(knownBoss[bossID], "loot keyed by an unknown encounter ID " .. bossID) end

-- RFC acceptance: Taragaman and Jergosh have different, correct Forever item IDs.
SlashCmdList.DUNGEONLENS("")
Click(Row(389))
assert(not panel(), "no panel until a boss is clicked")
fixture.itemCache, fixture.requestedItems, fixture.tooltip = {}, {}, {}
ClickPin("Taragaman the Hungerer")
assert(panel() and ns.BossPanel.title.text == "Taragaman the Hungerer" and ns.Window.view == "map")
local ids = {}
for _, row in ipairs(LootRows()) do ids[#ids + 1] = row.itemID end
assert(table.concat(ids, ",") == "14145,14148,14149", table.concat(ids, ","))
-- Uncached: dataset name + static icon immediately, item data requested, nothing errors or shows nil.
local rows = LootRows()
assert(rows[1].name.text == "Cursed Felblade" and rows[1].icon.textureID == 133770 and rows[1].detail.text:find("Wrist", 1, true))
for _, id in ipairs({ 14145, 14148, 14149 }) do assert(fixture.requestedItems[id], "item data not requested: " .. id) end
-- The client answers: the row updates in place with the real name, icon and quality colour.
fixture.itemCache[14145] = { name = "Cursed Felblade", quality = 3, icon = 4242 }
ns.events.scripts.OnEvent(ns.events, "GET_ITEM_INFO_RECEIVED", 14145, true)
assert(rows[1].icon.textureID == 4242 and rows[1].name.color and rows[1].name.color[3] > 0.8 and rows[1].name.color[1] == 0)
assert(rows[2].icon.textureID == 133770, "other rows untouched")
-- A failed lookup (success=false, item still uncached) keeps the fallback instead of erroring.
ns.events.scripts.OnEvent(ns.events, "GET_ITEM_INFO_RECEIVED", 14148, false)
assert(rows[2].name.text == "Crystalline Cuffs")
-- Real Blizzard tooltip for the hovered item.
rows[1].scripts.OnEnter(rows[1])
assert(fixture.tooltip.itemByID == 14145 and fixture.tooltip.shown and fixture.tooltip.owner == rows[1])
rows[1].scripts.OnLeave(rows[1])
assert(not fixture.tooltip.shown)
-- Hover on the pin: boss name + "Click to view loot".
local pin = Pin("Jergosh the Invoker")
pin.scripts.OnEnter(pin)
assert(fixture.tooltip.title == "Jergosh the Invoker" and fixture.tooltip.lines[#fixture.tooltip.lines] == "Click to view loot")
pin.scripts.OnLeave(pin)
-- Another boss replaces the content (different loot), the map stays.
ClickPin("Jergosh the Invoker")
ids = {}
for _, row in ipairs(LootRows()) do ids[#ids + 1] = row.itemID end
assert(table.concat(ids, ",") == "14147,14150,14151" and ns.BossPanel.title.text == "Jergosh the Invoker")
-- A boss with no verified loot says so; nothing is invented.
ClickPin("Oggleflint")
assert(#LootRows() == 0 and ns.BossPanel.message.text == "No verified loot yet")
-- "Seen by you": a boss kill + loot window records items for that encounter, only from boss-unit corpses, and the panel lists them
-- separately from verified loot (never duplicating a verified item).
do
    local now, bossGUID = 1000, "Creature-0-0-0-0-1-0000000001"
    function GetTime() return now end
    function UnitGUID(unit) return unit == "boss1" and bossGUID or nil end
    local loot = { { link = "|cff0070dd|Hitem:9999|h[Test Scepter]|h|r", guid = bossGUID, qty = 1 },
                   { link = "|cff0070dd|Hitem:8888|h[Trash Drop]|h|r", guid = "Creature-0-0-0-0-2-0000000002", qty = 1 } }
    function GetNumLootItems() return #loot end
    function GetLootSlotType() return 1 end
    function GetLootSlotLink(slot) return loot[slot].link end
    function GetLootSlotInfo(slot) return nil, nil, loot[slot].qty end
    function GetLootSourceInfo(slot) return loot[slot].guid, loot[slot].qty end
    ns.SeenLoot:OnEvent("ENCOUNTER_START", 2732)
    ns.SeenLoot:OnEvent("ENCOUNTER_END", 2732, "Oggleflint", 1, 5, 1)
    ns.SeenLoot:OnEvent("LOOT_OPENED")
    local seen = ns.SeenLoot:ForBoss(2732)
    assert(#seen == 1 and seen[1].itemID == 9999 and seen[1].count == 1, "only the boss corpse's item is recorded")
    now = now + 1000 -- window expired: later loot is not credited
    loot[1].link = "|Hitem:7777|h[Late]|h"
    ns.SeenLoot:OnEvent("LOOT_OPENED")
    assert(#ns.SeenLoot:ForBoss(2732) == 1)
    ClickPin("Oggleflint")
    local rows = LootRows()
    assert(#rows == 2 and rows[1].name.text == "SEEN BY YOU" and rows[2].itemID == 9999 and ns.BossPanel.message.text == "")
    -- A verified item the player also looted is not repeated in the seen section.
    ns.SeenLoot:Store(2734, 14147)
    assert(#ns.SeenLoot:ForBoss(2734) == 0)
    ns.Window:CloseBoss()
    ns.db.seenLoot = nil
end
-- Close returns to the map (not the list); clicking empty map also closes.
local closeButton
for _, child in ipairs(frames) do if child.parent == ns.BossPanel.frame and child.kind == "Button" then closeButton = child end end
Click(closeButton)
assert(not panel() and ns.Window.view == "map" and ns.Window.selectedBoss == nil)
ClickPin("Bazzalan")
assert(panel())
ns.BossPanel.catcher.scripts.OnMouseUp(ns.BossPanel.catcher)
assert(not panel() and ns.Window.view == "map")
-- Item event while the panel is closed or an unknown item is received: harmless.
ns.events.scripts.OnEvent(ns.events, "GET_ITEM_INFO_RECEIVED", 14145, true)
ns.events.scripts.OnEvent(ns.events, "GET_ITEM_INFO_RECEIVED", 999999999, true)
ns.events.scripts.OnEvent(ns.events, "GET_ITEM_INFO_RECEIVED")
-- Back to the list / another dungeon closes the panel.
ClickPin("Taragaman the Hungerer")
Click(ns.Window.backButton)
assert(not panel() and ns.Window.selectedBoss == nil)
Click(Row(389)); ClickPin("Taragaman the Hungerer")
Click(ns.Window.backButton); Click(Row(34))
assert(not panel())
Click(ns.Window.backButton)
-- Floors: the panel closes when the boss is not on the newly shown floor.
Click(Row(90))
Click(ns.Window.floorNext)
assert(ns.Window.floor == 2)
ClickPin("Electrocutioner 6000")
assert(panel() and ns.BossPanel.title.text == "Electrocutioner 6000")
local loot = ns.BossLoot[ns.Window.selectedBoss.id]
assert(loot and #loot.items >= 1)
Click(ns.Window.floorNext)
assert(ns.Window.floor == 3 and not panel() and ns.Window.selectedBoss == nil)
Click(ns.Window.floorPrev)
ClickPin("Electrocutioner 6000")
Click(ns.Window.floorPrev)
assert(ns.Window.floor == 1 and not panel())
-- Stale selection: a boss that no longer exists closes on the next render (a listed boss whose pin is merely hidden stays openable).
Click(ns.Window.floorNext)
SlashCmdList.DUNGEONLENS("approximate on")
ClickPin("Viscous Fallout")
assert(panel())
SlashCmdList.DUNGEONLENS("approximate off")
assert(panel() and ns.Window.selectedBoss, "a boss listed in the boss table stays open when only its pin is hidden")
ns.Window:CloseBoss()
ns.Window.selectedBoss = { id = 987654, dungeonID = 90 }
ns.Window:ValidateBoss()
assert(ns.Window.selectedBoss == nil)
ns.Window:SelectBoss(555, "Nobody") -- unknown loot id from a stray call: unavailable, not an error
assert(ns.BossPanel.message.text == "No verified loot yet")
ns.Window:CloseBoss()
-- Partial lists say so; no drop rates anywhere in the UI.
local partial
for bossID, data in pairs(ns.BossLoot) do if data.partial then partial = bossID end end
ns.Window.view, ns.Window.dungeonID = "map", 90
ns.Window:SelectBoss(partial, "x")
assert(ns.BossPanel.note.text:find("not yet verified", 1, true))
for _, row in ipairs(LootRows()) do assert(not row.detail.text:find("%%") and not row.name.text:find("%%")) end
ns.Window:CloseBoss()
Click(ns.Window.backButton)
-- Other dungeon: click one of its bosses.
Click(Row(70))
Click(ns.Window.floorNext) -- Archaedas is on the lower floor
ClickPin("Archaedas")
assert(panel() and ns.BossPanel.title.text == "Archaedas")
Click(ns.Window.backButton)
-- Leave the harness in a neutral state for the sections that follow.
fixture.itemCache, fixture.requestedItems, fixture.tooltip = nil, nil, nil

-- Marker data contract.
assert(ns.MapMarkers:ValidPoint({ x = 0, y = 1 }) and not ns.MapMarkers:ValidPoint({ x = 1.2, y = 0.5 }))
assert(not ns.MapMarkers:ValidPoint({ x = 0.5 }) and not ns.MapMarkers:ValidPoint(nil))

-- Player-position projection: the Lua arithmetic must reproduce, for EVERY placed boss, the normalized
-- coordinates the offline pipeline computed from its world position (floors, yaw-rotated frames, pages).
local checked, swapped = 0, 0
for _, vector in ipairs(ProjectionVectors) do
    if vector.status == "verified-source-registration" then
        local entry = assert(ns.MapRegistry:Get(vector.map), vector.map)
        local floor, x, y = ns.PlayerPosition:Locate(entry, vector.world[1], vector.world[2], vector.world[3])
        assert(floor == vector.floor and math.abs(x - vector.x) < 2e-4 and math.abs(y - vector.y) < 2e-4,
            vector.name .. ": floor " .. tostring(floor) .. " x " .. tostring(x) .. " y " .. tostring(y))
        -- UnitPosition's axis order is not assumed: swapped arguments must resolve to the same point.
        local rf, rx, ry, how = ns.PlayerPosition:Resolve(entry, vector.world[2], vector.world[1], vector.world[3])
        if rf then -- unambiguous: must be exactly right; ambiguous positions (both orders inside) must refuse, never guess
            assert(rf == vector.floor and how == "first-return-is-Y" and math.abs(rx - vector.x) < 2e-4, vector.name .. " swapped")
            swapped = swapped + 1
        else
            assert(how == "ambiguous-axis-order" or how == "outside-map", vector.name .. " swapped: " .. tostring(how))
        end
        checked = checked + 1
    end
end
assert(checked >= 50 and swapped >= 0.6 * checked, "too few projection vectors checked: " .. checked .. "/" .. swapped)

-- Gated live marker: needs the dev switch, readable numbers, the right instance and a live (non-preview) view.
fixture.inside, fixture.kind = true, "party"
Enter(70)
OpenCurrent()
local uldaman = ns.MapRegistry:Get(70)
local archaedas
for _, vector in ipairs(ProjectionVectors) do if vector.map == 70 and vector.name == "Archaedas" then archaedas = vector end end
local position = { archaedas.world[1], archaedas.world[2], archaedas.world[3], 70 }
function UnitPosition() return unpack(position) end
local overlay = ns.Window.renderer.overlay
ns.PlayerPosition:Update()
assert(not overlay.playerPoint and not ns.PlayerPosition.available, "marker must be off by default")
SlashCmdList.DUNGEONLENS("player on")
ns.PlayerPosition:Update()
assert(overlay.playerPoint and ns.PlayerPosition.available and ns.Window.floor == archaedas.floor, "marker/floor follow")
assert(math.abs(overlay.playerPoint.x - archaedas.x) < 2e-4 and math.abs(overlay.playerPoint.y - archaedas.y) < 2e-4)
assert(overlay.playerMarker:IsShown())
position = { archaedas.world[1], archaedas.world[2], archaedas.world[3], 389 } -- another instance
ns.PlayerPosition:Update()
assert(not overlay.playerPoint and ns.PlayerPosition.reason == "position-is-for-another-instance")
position = { 99999, 99999, 0, 70 } -- outside the dungeon: no marker, no guess
ns.PlayerPosition:Update()
assert(not overlay.playerPoint and ns.PlayerPosition.reason == "outside-map")
function UnitPosition() return nil end -- restricted/nil: nothing drawn
ns.PlayerPosition:Update()
assert(not overlay.playerPoint)
function UnitPosition() return setmetatable({}, { __tostring = function() error("secret inspected") end }) end
ns.PlayerPosition:Update() -- non-number values are ignored without error
assert(not overlay.playerPoint)
position = { archaedas.world[1], archaedas.world[2], archaedas.world[3], 70 }
function UnitPosition() return unpack(position) end
-- Learning the axis order: three unambiguous, well-separated samples fix it for the session.
ns.PlayerPosition.order, ns.PlayerPosition.votes, ns.PlayerPosition.lastVote = nil, nil, nil
local function SwappedSample(vector) position = { vector.world[2], vector.world[1], vector.world[3], 70 }; ns.PlayerPosition:Update() end
local learned = 0
for _, vector in ipairs(ProjectionVectors) do
    if vector.map == 70 and learned < 3 then
        local f = ns.PlayerPosition:Resolve(uldaman, vector.world[2], vector.world[1], vector.world[3])
        if f then SwappedSample(vector); learned = learned + 1 end
    end
end
assert(learned == 3 and ns.PlayerPosition.order == "first-return-is-Y", "axis order not learned")
Click(ns.Window.backButton) -- list view: nothing is drawn, nothing guessed
ns.PlayerPosition:Update()
assert(not overlay.playerPoint and ns.PlayerPosition.reason == "no-live-map-shown")
Click(Row(34)) -- viewing a different dungeon than the one the character is in
ns.PlayerPosition:Update()
assert(not overlay.playerPoint and ns.PlayerPosition.reason == "no-live-map-shown")
SlashCmdList.DUNGEONLENS("player off")
assert(not overlay.playerPoint and not ns.PlayerPosition.enabled)
for _, object in ipairs(frames) do assert(object.scripts.OnUpdate == nil, "no polling while the marker is off") end
UnitPosition = nil

-- Player position: probe runs safely, never enables a marker, never reads a restricted value.
ns.state = ns.state
SlashCmdList.DUNGEONLENS("probe")
assert(ns.PlayerPosition.available == false)
assert(#ns.db.positionProbe >= 1)
-- Learned boss positions: a boss looted at its own corpse gets a "seen" pin (tinted, never mistaken for a verified one) where the map has none.
do
    local PP = ns.PlayerPosition
    PP.order, PP.votes, PP.lastVote = nil, nil, nil
    -- Ground map conversion, anchored on the Undercity WMO placement (world 1647.7, 239.8), which is the centre of the walled city.
    local ruins = ns.MapRegistry:Get(2999)
    local floor, x, y = PP:Locate(ruins, 1647.7168, 239.8301, 0)
    assert(floor == 1 and x > 0.3 and x < 0.7 and y > 0.3 and y < 0.7, "ground conversion puts the city centre mid-crop")
    local swapped, _, _, how = PP:Resolve(ruins, 239.8301, 1647.7168, 0)
    assert(swapped == 1 and how == "first-return-is-Y", "axis order is detected for ground maps")
    assert(not PP:Locate(ruins, 0, 0, 0) and not PP:Locate(ruins, 5000, 5000, 0), "positions outside the crop are rejected")

    -- Hall of Thanes (WMO): a world position inside one of its group volumes, built by inverting the registered frame.
    Enter(3065)
    OpenCurrent()
    local entry, frame = ns.MapRegistry:Get(3065), ns.MapRegistry:Get(3065).frame
    local function rot(dx, dy, degrees)
        local r = math.rad(degrees)
        return math.cos(r) * dx - math.sin(r) * dy, math.sin(r) * dx + math.cos(r) * dy
    end
    local wx, wy, wz
    for _, group in ipairs(entry.groups) do
        local lx, ly = (group.minimum[1] + group.maximum[1]) / 2, (group.minimum[2] + group.maximum[2]) / 2
        local dx, dy = rot(lx, ly, -(180 - frame.yaw))
        local cx, cy, cz = frame.originX + dx, frame.originY + dy, (group.minimum[3] + group.maximum[3]) / 2 + frame.zOffset
        if PP:Resolve(entry, cx, cy, cz) then wx, wy, wz = cx, cy, cz; break end
    end
    assert(wx, "found an unambiguous world position inside the dungeon")

    local now, bossGUID = 5000, "Creature-0-0-0-0-3-0000000003"
    function GetTime() return now end
    function UnitGUID(unit) return unit == "boss1" and bossGUID or nil end
    function UnitPosition() return wx, wy, wz, 3065 end
    function GetNumLootItems() return 1 end
    function GetLootSlotType() return 1 end
    function GetLootSlotLink() return "|Hitem:9999|h[Test]|h" end
    function GetLootSlotInfo() return nil, nil, 1 end
    function GetLootSourceInfo() return bossGUID, 1 end
    assert(not Titled("Faldrim Anvilmar"), "unresolved boss has no pin before it is looted")
    ns.SeenLoot:OnEvent("ENCOUNTER_START", 3493)
    ns.SeenLoot:OnEvent("ENCOUNTER_END", 3493, "Faldrim Anvilmar", 1, 5, 1)
    ns.SeenLoot:OnEvent("LOOT_OPENED")
    ns.SeenLoot:OnEvent("LOOT_OPENED") -- a second window for the same kill adds no second sample
    assert(#ns.db.seenBossPos[3065][3493].samples == 1)
    renderer.overlay:Refresh()
    assert(Titled("Faldrim Anvilmar"), "looted boss gets a seen pin")
    local seen
    for _, item in ipairs(renderer.overlay.items) do if item.id == 3493 then seen = item end end
    assert(seen and seen.status == "seen" and seen.x >= 0 and seen.x <= 1 and seen.y >= 0 and seen.y <= 1)
    ClickPin("Faldrim Anvilmar")
    assert(panel() and ns.BossPanel.title.text == "Faldrim Anvilmar")
    ns.Window:ValidateBoss()
    assert(panel(), "a seen pin keeps its loot panel open")
    SlashCmdList.DUNGEONLENS("lootexport")
    assert(Said("encounter 3065") == false and Said("dungeon 3065 encounter 3493"), "positions are exported")
    -- Positions never override a verified pin, and clearing the data removes the pin.
    ns.Window:CloseBoss()
    ns.db.seenBossPos, ns.db.seenLoot = nil, nil
    renderer.overlay:Refresh()
    assert(not Titled("Faldrim Anvilmar"))
    PP.order, PP.votes, PP.lastVote = nil, nil, nil
    GetTime, UnitGUID, UnitPosition = nil, nil, nil
end

-- Boss table (top-right of an open dungeon map): every boss listed, click for loot, "< Bosses" returns, hidden outside a dungeon map.
do
    local function TableRows()
        local rows = {}
        if ns.BossList.frame and ns.BossList.frame:IsShown() then
            for _, row in ipairs(ns.BossList.rows) do if row:IsShown() then rows[#rows + 1] = row end end
        end
        return rows
    end
    local function TableRow(name)
        for _, row in ipairs(TableRows()) do if row.name.text == name then return row end end
        error("no boss table row for " .. name)
    end
    local function Back()
        for _, child in ipairs(frames) do if child.parent == ns.BossPanel.frame and child.kind == "Button" then Click(child); return end end
        error("no back button")
    end
    SlashCmdList.DUNGEONLENS("")
    assert(#TableRows() == 0, "no boss table in the dungeon browser")

    -- Ragefire Chasm: all four bosses, with loot counts; a click opens that boss's loot, the back button returns to the table.
    Click(Row(389))
    local rows = TableRows()
    assert(#rows == 4 and rows[1].name.text == "Oggleflint" and rows[2].name.text == "Taragaman the Hungerer", "all bosses, in order")
    assert(TableRow("Taragaman the Hungerer").loot.text == "3 items" and TableRow("Oggleflint").loot.text == "no loot yet")
    Click(TableRow("Jergosh the Invoker"))
    assert(panel() and ns.BossPanel.title.text == "Jergosh the Invoker" and #TableRows() == 0, "table gives way to the loot panel")
    Back()
    assert(not panel() and #TableRows() == 4 and ns.Window.view == "map", "back returns to the table, the map stays")
    Click(TableRow("Oggleflint"))
    assert(panel() and ns.BossPanel.message.text == "No verified loot yet")
    Back()

    -- Hall of Thanes has no placed bosses at all: the table is the only way in, and it must not close itself.
    Click(ns.Window.backButton)
    assert(#TableRows() == 0, "leaving the map hides the table")
    Click(Row(3065))
    assert(#TableRows() == 4)
    Click(TableRow("Durgen Dirgehammer"))
    local ids = {}
    for _, lootRow in ipairs(LootRows()) do ids[#ids + 1] = lootRow.itemID end
    assert(panel() and ns.BossPanel.title.text == "Durgen Dirgehammer" and ids[1] == 270256, "unplaced boss opens its loot")
    ns.Window:ValidateBoss()
    assert(panel(), "an unplaced boss has no pin to lose")
    Back()
    Click(ns.Window.backButton)

    -- A boss placed on another floor takes the map to that floor first (Gnomeregan: Electrocutioner 6000 is on floor 2).
    Click(Row(90))
    assert(ns.Window.floor == 1)
    Click(TableRow("Electrocutioner 6000"))
    assert(ns.Window.floor == 2 and panel() and ns.BossPanel.title.text == "Electrocutioner 6000", "table click follows the boss's floor")
    Back()
    Click(ns.Window.backButton)
    assert(#TableRows() == 0)
end

-- Entrance card (top-left of an open dungeon map): zone + coordinates + "Show on world map" (opens the zone, places the standard pin).
do
    -- Every dungeon with a map has an entrance record: a zone UiMapID, and a normalized position when the exact spot is known.
    for _, row in ipairs(ns.MapRegistry:List()) do
        local data = ns.DungeonEntrances[row.instanceID]
        assert(data and ns.IsID(data.uiMapID) and type(data.zone) == "string", "entrance data for " .. row.name)
        if data.x then assert(data.x >= 0 and data.x <= 1 and data.y >= 0 and data.y <= 1, "entrance position for " .. row.name) end
    end
    local calls = {}
    local savedMap, savedPoint, savedTrack = C_Map, UiMapPoint, C_SuperTrack
    C_Map = setmetatable({
        OpenWorldMap = function(id) calls[#calls + 1] = { "open", id } end,
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point) calls[#calls + 1] = { "pin", point.uiMapID, point.x, point.y } end,
    }, { __index = savedMap })
    UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) calls[#calls + 1] = { "track", on } end }
    local function CardButton()
        for _, child in ipairs(frames) do if child.parent == ns.EntranceCard.frame and child.kind == "Button" then return child end end
        error("no entrance button")
    end

    SlashCmdList.DUNGEONLENS("")
    assert(not (ns.EntranceCard.frame and ns.EntranceCard.frame:IsShown()), "no entrance card in the dungeon browser")
    Click(Row(389))
    assert(ns.EntranceCard.frame:IsShown() and ns.EntranceCard.zone.text == "Orgrimmar  53.0, 48.9", ns.EntranceCard.zone.text)
    assert(ns.EntranceCard.note.text:find("Cleft of Shadow", 1, true))
    Click(CardButton())
    assert(#calls == 3 and calls[1][1] == "open" and calls[1][2] == 1454, "opens the zone map first")
    assert(calls[2][1] == "pin" and calls[2][2] == 1454 and math.abs(calls[2][3] - 0.5296) < 1e-3 and math.abs(calls[2][4] - 0.4887) < 1e-3)
    assert(calls[3][1] == "track" and calls[3][3] == nil and calls[3][2] == true)
    assert(ns.EntranceCard.lastResult.opened and ns.EntranceCard.lastResult.pinned)

    -- Zone-only entrance (Hall of Thanes): the zone map opens, no pin is invented.
    Click(ns.Window.backButton)
    assert(not ns.EntranceCard.frame:IsShown())
    Click(Row(3065))
    assert(ns.EntranceCard.zone.text == "Ironforge" and ns.EntranceCard.note.text:find("not known yet", 1, true))
    calls = {}
    Click(CardButton())
    assert(#calls == 1 and calls[1][1] == "open" and calls[1][2] == 1455, "zone-only entrance opens the map without a pin")

    -- Missing or refusing APIs never error: the zone and coordinates are printed instead.
    Click(ns.Window.backButton)
    Click(Row(2999))
    assert(ns.EntranceCard.zone.text:find("Tirisfal Glades", 1, true))
    C_Map, UiMapPoint, C_SuperTrack = savedMap, nil, nil
    Click(CardButton())
    assert(ns.EntranceCard.lastResult.pinned == false and Said("Entrance: Tirisfal Glades"), "falls back to chat text")
    C_Map = setmetatable({ OpenWorldMap = function() error("blocked") end }, { __index = savedMap })
    Click(CardButton())
    assert(ns.EntranceCard.lastResult.opened == false)
    C_Map, UiMapPoint, C_SuperTrack = savedMap, savedPoint, savedTrack
    Click(ns.Window.backButton)
end

-- Minimap button: placed on the rim, draggable (polls only while dragging), left toggles the browser, right opens the live dungeon,
-- position/visibility saved, /dlmap minimap on|off|reset, safe without a Minimap.
do
    ns.db.minimap = nil
    ns.MinimapButton:Init() -- no Minimap in this client yet: nothing happens, nothing errors
    assert(not ns.MinimapButton.frame, "no button without a minimap")
    Minimap = CreateFrame("Frame", "Minimap")
    Minimap:SetSize(140, 140)
    ns.MinimapButton:Init()
    local button = ns.MinimapButton.frame
    assert(button and DungeonLensMinimapButton == button and button.parent == Minimap and button:IsShown())
    local default = button.points.CENTER
    assert(default[2] == Minimap and math.abs(default[4] - 75 * math.cos(math.rad(215))) < 1e-6, "default spot on the rim (radius 75)")

    -- Drag: the cursor angle is followed, saved, and the per-frame update is removed again when the drag stops.
    assert(button.scripts.OnUpdate == nil, "no polling while idle")
    button.scripts.OnDragStart(button)
    assert(button.scripts.OnUpdate, "polls while dragging")
    function GetCursorPosition() return 640 + 100, 450 end -- right of the minimap centre (stub centre is 640, 450)
    button.scripts.OnUpdate(button)
    assert(math.abs(ns.db.minimap.angle) < 1e-6 and math.abs(button.points.CENTER[4] - 75) < 1e-6 and math.abs(button.points.CENTER[5]) < 1e-6)
    function GetCursorPosition() return 640, 450 + 60 end -- straight above
    button.scripts.OnUpdate(button)
    assert(math.abs(ns.db.minimap.angle - 90) < 1e-6 and math.abs(button.points.CENTER[5] - 75) < 1e-6)
    button.scripts.OnDragStop(button)
    assert(button.scripts.OnUpdate == nil and not ns.MinimapButton.dragging, "polling stops with the drag")

    -- A square minimap clamps the button to its edge instead of a circle.
    function GetMinimapShape() return "SQUARE" end
    ns.db.minimap.angle = 45
    ns.MinimapButton:Init()
    assert(math.abs(button.points.CENTER[4] - 75) < 1e-6 and math.abs(button.points.CENTER[5] - 75) < 1e-6, "square minimap corner")
    GetMinimapShape = nil
    ns.MinimapButton:Init()

    -- Clicks: left toggles the dungeon browser, right opens the live dungeon (here: the browser, since we are outside).
    SlashCmdList.DUNGEONLENS("close")
    assert(not ns.Window.frame:IsShown())
    button.scripts.OnClick(button, "LeftButton")
    assert(ns.Window.frame:IsShown() and ns.Window.view == "list")
    button.scripts.OnClick(button, "LeftButton")
    assert(not ns.Window.frame:IsShown(), "second left-click closes it")
    fixture.inside, fixture.kind = false, "none"
    Event("PLAYER_ENTERING_WORLD")
    button.scripts.OnClick(button, "RightButton")
    assert(ns.Window.frame:IsShown() and ns.Window.view == "list", "outside a dungeon, right-click opens the browser")
    SlashCmdList.DUNGEONLENS("close")
    fixture.inside, fixture.kind = true, "party"
    Enter(389)
    button.scripts.OnClick(button, "RightButton")
    assert(ns.Window.frame:IsShown() and ns.Window.view == "map" and ns.Window.dungeonID == 389, "inside a dungeon, right-click opens its map")
    button.scripts.OnEnter(button)
    assert(fixture.tooltip and fixture.tooltip.title == "DungeonLens")
    button.scripts.OnLeave(button)

    -- Hide / show / reset persist in the saved variables.
    SlashCmdList.DUNGEONLENS("minimap off")
    assert(not button:IsShown() and ns.db.minimap.hidden == true and Said("Minimap button hidden"))
    SlashCmdList.DUNGEONLENS("minimap on")
    assert(button:IsShown() and ns.db.minimap.hidden == false)
    ns.db.minimap.angle = 10
    SlashCmdList.DUNGEONLENS("minimap reset")
    assert(ns.db.minimap.angle == nil and math.abs(button.points.CENTER[4] - 75 * math.cos(math.rad(215))) < 1e-6)
    SlashCmdList.DUNGEONLENS("minimap")
    assert(Said("Minimap button is shown"))
    SlashCmdList.DUNGEONLENS("close")
    GetCursorPosition, Minimap = nil, nil
end

print("PASS: boss loot panel (lookup, uncached items, tooltip, lifecycle, floors, stale selection), click-through browser (list/map/back/floors/pins), generated WMO + ground candidates, 73-group sublevel range, candidate gating, RFC unchanged, resize-stable normalized overlay, authoring capture/undo/layout-binding, safe position probe.")
