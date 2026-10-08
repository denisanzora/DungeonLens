local _, ns = ...
local Probe = {}
ns.PositionProbe = Probe

-- ---------------------------------------------------------------------------------------------
-- Player position. DungeonLens never infers, estimates or fakes a position: no keyboard/movement
-- inference, no dead reckoning, no memory access, no restricted-API workaround. The ONLY source is
-- UnitPosition("player") read through the normal API, and only if it returns plain readable numbers.
--
-- What is proven offline (scripts/FRAME-FIT.md): positions in the instance world frame map onto a
-- dungeon canvas by
--     local = Rot(180 - yaw) * (world - origin)         canvas = (local.x*rho - minX, maxY - local.y*rho)
-- using each WMO's placement (entry.frame / floor.frame). What is NOT known without the client is whether
-- UnitPosition returns usable values inside Forever instances and in which axis order, so:
--   * the marker is a development switch (/dlmap player on), off by default;
--   * both axis orders are tested against the map's own group volumes (xy + height); the marker is
--     drawn only if EXACTLY ONE order lands inside the dungeon, otherwise nothing is drawn;
--   * it is shown only in the live view of the instance the character is actually in.
-- ---------------------------------------------------------------------------------------------
local PP = { available = false, enabled = false, reason = "disabled; run /dlmap probe inside a dungeon, then /dlmap player on" }
ns.PlayerPosition = PP

local ZERO_FRAME = { originX = 0, originY = 0, yaw = 0, zOffset = 0 } -- global-WMO dungeons (e.g. Ragefire Chasm)
local groupCache = setmetatable({}, { __mode = "k" })

local function Rotate(dx, dy, degrees)
    local radians = math.rad(degrees)
    local c, s = math.cos(radians), math.sin(radians)
    return c * dx - s * dy, s * dx + c * dy
end

local function GroupsByIndex(entry)
    local cached = groupCache[entry]
    if not cached then
        cached = {}
        for _, record in ipairs(entry.groups or {}) do cached[record.index] = record end
        groupCache[entry] = cached
    end
    return cached
end

function PP:FrameFor(entry, floor)
    local record = entry.floors and entry.floors[floor]
    return (record and record.frame) or entry.frame or ZERO_FRAME
end

-- World position -> (floor, normalized x, normalized y) on that floor's canvas, or nil + reason.
-- Pure math over registry data; the same arithmetic scripts/Build-Bosses.py used for the boss pins
-- (checked against every placed boss in MultiDungeonSmoke.lua).
-- Ground (ADT terrain) maps: the client's minimap tiles are 1600/3-yard ADT tiles drawn north-up, tile (tx, ty) at column tx / row ty.
-- World X (north) = (32 - ty) * 1600/3 and world Y (west) = (32 - tx) * 1600/3, so tile coordinates are continuous in the world.
-- Anchor check (MultiDungeonSmoke): Ruins of Lordaeron's Undercity WMO is placed at world (1647.7, 239.8), the centre of the walled city.
local ADT_TILE = 1600 / 3

function PP:LocateGround(entry, wx, wy)
    if not (ns.IsNumber(wx) and ns.IsNumber(wy)) then return nil, "not-numbers" end
    local size = entry.tileSize
    if not (ns.IsNumber(size) and ns.IsNumber(entry.gridMinX) and ns.IsNumber(entry.gridMinY)) then return nil, "no-ground-grid" end
    local crop = entry.crop
    local cx, cy = crop and crop.x or 0, crop and crop.y or 0
    local width, height = crop and crop.width or entry.columns * size, crop and crop.height or entry.rows * size
    local px = (32 - wy / ADT_TILE - entry.gridMinX) * size - cx
    local py = (32 - wx / ADT_TILE - entry.gridMinY) * size - cy
    if px < 0 or py < 0 or px > width or py > height then return nil, "outside-map" end
    return 1, px / width, py / height
end

function PP:Locate(entry, wx, wy, wz)
    if entry and entry.sourceType == "blizzard-ground-minimap" then return self:LocateGround(entry, wx, wy) end
    if not entry or entry.sourceType ~= "blizzard-wmo-minimap" then return nil, "unsupported-source" end
    if not (ns.IsNumber(wx) and ns.IsNumber(wy) and ns.IsNumber(wz)) then return nil, "not-numbers" end
    local byIndex, candidates = GroupsByIndex(entry), {}
    for floor = 1, ns.WMOComposition:FloorCount(entry) do
        local frame = self:FrameFor(entry, floor)
        local lx, ly = Rotate(wx - frame.originX, wy - frame.originY, 180 - frame.yaw)
        local zl = wz - frame.zOffset
        local indexes = entry.floors and entry.floors[floor].groups
        local best
        for position = 1, indexes and #indexes or #entry.groups do
            local record = indexes and byIndex[indexes[position]] or entry.groups[position]
            if record and lx >= record.minimum[1] - 2 and lx <= record.maximum[1] + 2
                and ly >= record.minimum[2] - 2 and ly <= record.maximum[2] + 2
                and zl >= record.minimum[3] - 6 and zl <= record.maximum[3] + 6 then
                local distance = math.abs(zl - (record.minimum[3] + record.maximum[3]) / 2)
                if not best or distance < best then best = distance end
            end
        end
        if best then candidates[#candidates + 1] = { distance = best, floor = floor, lx = lx, ly = ly } end
    end
    if #candidates == 0 then return nil, "outside-map" end
    table.sort(candidates, function(a, b)
        if a.distance == b.distance then return a.floor < b.floor end
        return a.distance < b.distance
    end)
    if #candidates > 1 and candidates[2].distance - candidates[1].distance < 3 then return nil, "ambiguous-floor" end
    local chosen = candidates[1]
    local layout = ns.WMOComposition:GetLayout(entry, chosen.floor)
    if not layout or not layout.minX or not layout.maxY then return nil, "no-layout" end
    local px, py = chosen.lx * entry.rho - layout.minX, layout.maxY - chosen.ly * entry.rho
    return chosen.floor, px / layout.width, py / layout.height
end

-- UnitPosition's axis order is not assumed: test both against the dungeon's own volumes.
function PP:Resolve(entry, a, b, z)
    local floorA, xA, yA = self:Locate(entry, a, b, z)
    local floorB, xB, yB = self:Locate(entry, b, a, z)
    if floorA and not floorB then return floorA, xA, yA, "first-return-is-X" end
    if floorB and not floorA then return floorB, xB, yB, "first-return-is-Y" end
    return nil, nil, nil, floorA and "ambiguous-axis-order" or "outside-map"
end

-- Same as Resolve, but honours the axis order once it has been learned this session.
function PP:LocateEither(entry, a, b, z)
    if self.order == "first-return-is-X" then return self:Locate(entry, a, b, z) end
    if self.order == "first-return-is-Y" then return self:Locate(entry, b, a, z) end
    local floor, x, y = self:Resolve(entry, a, b, z)
    return floor, x, y
end

-- The axis order is a property of the API, not of where the character stands. After three
-- unambiguous samples (>= 8 yd apart) that all agree, and none disagreeing, it is remembered for
-- this session so ambiguous positions resolve consistently instead of flickering.
function PP:Learn(how, a, b)
    local last = self.lastVote
    if last and math.abs(a - last[1]) + math.abs(b - last[2]) < 8 then return end
    self.lastVote = { a, b }
    self.votes = self.votes or {}
    self.votes[how] = (self.votes[how] or 0) + 1
    local other = how == "first-return-is-X" and "first-return-is-Y" or "first-return-is-X"
    if self.votes[how] >= 3 and (self.votes[other] or 0) == 0 then self.order = how end
end

-- Readable plain numbers only (no secret values, no nils, no non-finite numbers).
function PP:Sample()
    local probe = ns.Probe(UnitPosition, "player")
    if probe.status ~= "ok" then return nil, probe.status end
    local values = probe.values
    if not (ns.IsNumber(values[1]) and ns.IsNumber(values[2]) and ns.IsNumber(values[3])) then return nil, "not-readable-numbers" end
    return values[1], values[2], values[3], ns.IsNumber(values[4]) and values[4] or nil
end

function PP:Hide()
    local overlay = ns.Window and ns.Window.renderer and ns.Window.renderer.overlay
    if overlay then overlay:ClearPlayer() end
    self.available = false
end

function PP:Update()
    if not self.enabled then return self:Hide() end -- development switch: off unless /dlmap player on
    local window = ns.Window
    local state = window and window.lastState
    -- Only while the shown map is the dungeon the character is actually in.
    local live = ns.state
    if not (window and window.frame and window.frame:IsShown()) or window.view ~= "map" or not state or not state.mapEntry
        or not (live and live.inInstance and live.instanceID == state.instanceID) then
        self.reason = "no-live-map-shown"
        return self:Hide()
    end
    local a, b, z, mapID = self:Sample()
    if not a then
        self.reason = b
        return self:Hide()
    end
    if mapID and state.instanceID and mapID ~= state.instanceID then
        self.reason = "position-is-for-another-instance"
        return self:Hide()
    end
    local floor, x, y, how
    if self.order then
        if self.order == "first-return-is-X" then floor, x, y = self:Locate(state.mapEntry, a, b, z)
        else floor, x, y = self:Locate(state.mapEntry, b, a, z) end
        how = floor and self.order or "outside-map"
    else
        floor, x, y, how = self:Resolve(state.mapEntry, a, b, z)
        if floor then self:Learn(how, a, b) end
    end
    if not floor then
        self.reason = how
        return self:Hide()
    end
    self.available, self.reason, self.axisOrder = true, how, how
    if floor ~= window.floor then window:SetFloor(floor) end -- follow the character between floors
    window.renderer.overlay:SetPlayer(x, y)
end

local ticker
function PP:SetEnabled(on)
    self.enabled = on == true
    if ns.db then ns.db.playerMarker = self.enabled end
    if self.enabled then
        ticker = ticker or CreateFrame("Frame")
        local elapsedTotal = 0
        ticker:SetScript("OnUpdate", function(_, elapsed)
            elapsedTotal = elapsedTotal + (elapsed or 0)
            if elapsedTotal >= 0.25 then
                elapsedTotal = 0
                PP:Update()
            end
        end)
        self.reason = "enabled; waiting for a readable position"
    else
        if ticker then ticker:SetScript("OnUpdate", nil) end
        self.reason = "disabled"
        self:Hide()
    end
end

function PP:Restore()
    if ns.db and ns.db.playerMarker == true and not self.enabled then self:SetEnabled(true) end
end

function PP:Command(argument)
    argument = (argument or ""):lower()
    if argument == "on" then
        self:SetEnabled(true)
        ns.Print("Player marker ON (development). It appears only if UnitPosition returns readable values inside this dungeon "
            .. "and exactly one axis order lands on the map. Check /dlmap player status.")
    elseif argument == "off" then
        self:SetEnabled(false)
        ns.Print("Player marker OFF.")
    else
        ns.Print("Player marker: " .. (self.enabled and "enabled" or "disabled") .. ", showing=" .. tostring(self.available)
            .. ", last result: " .. ns.Text(self.reason) .. ". Usage: /dlmap player on|off")
    end
end

-- /dlmap probe: run INSIDE a dungeon and again OUTSIDE (for a baseline). Every candidate is called
-- through pcall and checked with issecretvalue before any inspection. Results are printed and appended
-- to DungeonLensDB.positionProbe for later review.
local function Describe(values)
    if values.status ~= "ok" then return values.status end
    local parts = {}
    for index = 1, math.max(values.values.n or 0, 1) do
        local value = values.values[index]
        if not ns.IsReadable(value) then parts[#parts + 1] = "<secret>"
        elseif type(value) == "number" then parts[#parts + 1] = string.format("%.4f", value)
        elseif type(value) == "table" or type(value) == "userdata" then
            local x, y = ns.Field(value, "x"), ns.Field(value, "y")
            if ns.IsNumber(x) and ns.IsNumber(y) then
                parts[#parts + 1] = string.format("vec(%.4f,%.4f)", x, y)
            else
                local get = ns.Probe(ns.Field(value, "GetXY"), value)
                if get.status == "ok" and ns.IsNumber(get.values[1]) and ns.IsNumber(get.values[2]) then
                    parts[#parts + 1] = string.format("vec(%.4f,%.4f)", get.values[1], get.values[2])
                else parts[#parts + 1] = "<" .. type(value) .. ">" end
            end
        else parts[#parts + 1] = ns.Text(value) end
    end
    return table.concat(parts, ", ")
end

function Probe:Run()
    local inside = ns.Probe(IsInInstance)
    local build = ns.Probe(GetBuildInfo)
    local record = { context = (inside.values[1] == true) and "instance" or "outside", rows = {} }
    record.build = ns.Text(ns.Field(build.values, 2))
    local function row(label, probe)
        local text = Describe(probe)
        record.rows[#record.rows + 1] = label .. " -> " .. text
        ns.Print("  " .. label .. " -> " .. text)
    end
    ns.Print("Position probe (" .. record.context .. ", build " .. record.build .. "); informational only, no marker is drawn.")
    row("UnitPosition(player)", ns.Probe(UnitPosition, "player"))
    local best = ns.MapProbe("GetBestMapForUnit", "player")
    row("C_Map.GetBestMapForUnit(player)", best)
    local minimapMap = ns.Probe(ns.Field(C_Minimap, "GetUiMapID"))
    row("C_Minimap.GetUiMapID()", minimapMap)
    row("C_Minimap.GetViewRadius()", ns.Probe(ns.Field(C_Minimap, "GetViewRadius")))
    local seen = {}
    for _, source in ipairs({ best, minimapMap }) do
        local mapID = source.values[1]
        if ns.IsID(mapID) and not seen[mapID] then
            seen[mapID] = true
            row("C_Map.GetPlayerMapPosition(" .. mapID .. ", player)", ns.MapProbe("GetPlayerMapPosition", mapID, "player"))
        end
    end
    row("GetPlayerMapPosition(player) [legacy global]", ns.Probe(_G.GetPlayerMapPosition, "player"))
    row("GetPlayerFacing() [heading only, not a position]", ns.Probe(GetPlayerFacing))
    row("C_Map.GetUserWaypoint()", ns.MapProbe("GetUserWaypoint"))
    local frame = ns.Probe(CreateFrame, "UnitPositionFrame")
    local frameOk = frame.status == "ok" or frame.status == "nil"
    record.rows[#record.rows + 1] = "CreateFrame(UnitPositionFrame) -> " .. frame.status
    ns.Print("  CreateFrame(UnitPositionFrame) -> " .. frame.status .. (frameOk and " (needs a UiMapID; dungeons here have none)" or ""))
    -- Does the proven world->canvas transform apply? (Only if UnitPosition gave readable numbers.)
    local state = ns.Window and ns.Window.lastState or ns.state
    local entry = state and state.mapEntry
    local a, b, z, mapID = PP:Sample()
    if a and entry then
        local floor, x, y, how = PP:Resolve(entry, a, b, z)
        local text = floor and string.format("floor %d, x=%.4f y=%.4f (%s)", floor, x, y, how) or ("no projection: " .. ns.Text(how))
        record.rows[#record.rows + 1] = "projection -> " .. text .. (mapID and (" mapID=" .. mapID) or "")
        ns.Print("  projection onto the displayed dungeon -> " .. text)
    else
        ns.Print("  projection -> not attempted (" .. (a and "no live dungeon map shown" or ns.Text(b)) .. ")")
    end
    if ns.db then
        ns.db.positionProbe = ns.db.positionProbe or {}
        local log = ns.db.positionProbe
        log[#log + 1] = record
        while #log > 20 do table.remove(log, 1) end
    end
    ns.Print("Saved to SavedVariables. Run once inside and once outside an instance and compare.")
end
