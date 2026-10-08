local _, ns = ...
local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function Value(probe, index)
    if probe.status ~= "ok" and probe.status ~= "nil" then return probe.status end
    return ns.Text(probe.values[index or 1])
end

local function MapSummary(info)
    return "id=" .. ns.Text(ns.Field(info, "mapID"))
        .. " name=" .. ns.Text(ns.Field(info, "name"))
        .. " type=" .. ns.Text(ns.Field(info, "mapType"))
        .. " parent=" .. ns.Text(ns.Field(info, "parentMapID"))
end

function Diagnostics:ReportMap(mapID, label)
    if not ns.IsID(mapID) then
        ns.Print(label .. ": no readable UiMapID")
        return
    end
    local info = ns.MapProbe("GetMapInfo", mapID)
    ns.Print(label .. " " .. ns.Text(mapID) .. ": GetMapInfo=" .. info.status
        .. " " .. MapSummary(info.values[1]))
    ns.Print("  GetMapArtID=" .. Value(ns.MapProbe("GetMapArtID", mapID)))
    local layers = ns.MapProbe("GetMapArtLayers", mapID)
    local layerCount = 0
    for index = 1, 16 do
        if ns.Field(layers.values[1], index) == nil then break end
        layerCount = layerCount + 1
    end
    ns.Print("  GetMapArtLayers=" .. layers.status .. " count=" .. layerCount)
    for index = 1, 16 do
        local layer = ns.Field(layers.values[1], index)
        if not layer then break end
        local textures = ns.MapProbe("GetMapArtLayerTextures", mapID, index)
        local count, actualIDs, samples = 0, 0, {}
        for tile = 1, 512 do
            local textureID = ns.Field(textures.values[1], tile)
            if textureID == nil then break end
            count = count + 1
            if ns.IsID(textureID) then actualIDs = actualIDs + 1 end
            if tile <= 4 then samples[#samples + 1] = ns.Text(textureID) end
        end
        ns.Print("  layer " .. index .. ": " .. ns.Text(ns.Field(layer, "layerWidth"))
            .. "x" .. ns.Text(ns.Field(layer, "layerHeight"))
            .. " tiles=" .. ns.Text(ns.Field(layer, "tileWidth"))
            .. "x" .. ns.Text(ns.Field(layer, "tileHeight"))
            .. " scale=" .. ns.Text(ns.Field(layer, "minScale"))
            .. ".." .. ns.Text(ns.Field(layer, "maxScale")))
        ns.Print("    GetMapArtLayerTextures=" .. textures.status .. " count=" .. count .. " positiveFileIDs=" .. actualIDs
            .. " sample=" .. table.concat(samples, ","))
    end
end

-- Diagnostic-only discovery. An InstanceID is never converted into a UiMapID.
-- Range discovery also covers orphan UiMaps absent from the world hierarchy.
-- Its finite 1..4096 scope covers every ID in the published 70124 UiMap table.
local SCAN_LIMIT, SCAN_BATCH = 4096, 50
local REFERENCE_MAPS = {
    [908] = "other-client name collision; not a verified Forever dungeon",
    [1420] = "Tirisfal outdoor context; not a dungeon assignment",
    [1458] = "Undercity city context; not a dungeon assignment",
}

local function Primitive(value)
    if not ns.IsReadable(value) then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then return value end
    if ns.IsNumber(value) then return value end
end

local function ScanContext()
    local build, instance = ns.Probe(GetBuildInfo), ns.Probe(GetInstanceInfo)
    local best = ns.MapProbe("GetBestMapForUnit", "player")
    local minimap = ns.Probe(ns.Field(C_Minimap, "GetUiMapID"))
    local inside = ns.Probe(IsInInstance)
    return {
        version = Primitive(build.values[1]), build = Primitive(build.values[2]),
        interface = Primitive(build.values[4]), locale = Primitive(ns.Probe(GetLocale).values[1]),
        instanceID = Primitive(instance.values[8]), name = Primitive(instance.values[1]),
        instanceType = Primitive(instance.values[2]), inside = Primitive(inside.values[1]),
        bestUiMapID = Primitive(best.values[1]), bestStatus = best.status,
        minimapUiMapID = Primitive(minimap.values[1]), minimapStatus = minimap.status,
    }
end

function Diagnostics:InspectScanMap(job, uiMapID)
    if not ns.IsID(uiMapID) or job.visited[uiMapID] then return end
    job.visited[uiMapID] = true
    -- A hierarchy/API may independently prove that this number is a UiMapID.
    -- Otherwise skip the numeric collision with the current InstanceID.
    if uiMapID == job.context.instanceID and not job.apiUiMaps[uiMapID] then
        job.skippedInstanceID = true
        return
    end
    local probe = ns.MapProbe("GetMapInfo", uiMapID)
    job.tested = job.tested + 1
    job.statuses[probe.status] = (job.statuses[probe.status] or 0) + 1
    local raw = probe.values[1]
    local returnedID = ns.Field(raw, "mapID")
    local info
    if ns.IsID(returnedID) then
        info = { mapID = returnedID, name = Primitive(ns.Field(raw, "name")),
            mapType = Primitive(ns.Field(raw, "mapType")), parentMapID = Primitive(ns.Field(raw, "parentMapID")) }
        job.maps[uiMapID] = info
        job.valid = job.valid + 1
    end
    local reason = job.context.instanceID == 2999 and REFERENCE_MAPS[uiMapID] or nil
    if info then
        if job.dungeonType and info.mapType == job.dungeonType then reason = "Dungeon type; identity still unproven" end
        if type(info.name) == "string" and (info.name == job.context.name or info.name:lower():find("lordaeron", 1, true)) then
            reason = (reason and reason .. "; " or "") .. "name match only; not identity proof"
        end
        if uiMapID == job.context.bestUiMapID or uiMapID == job.context.minimapUiMapID then
            reason = (reason and reason .. "; " or "") .. "current player/minimap API candidate"
        end
    end
    if not reason then return end
    ns.Print("Scan candidate UiMapID=" .. uiMapID .. " (" .. reason .. ")")
    self:ReportMap(uiMapID, "  Candidate")
    local candidate = { uiMapID = uiMapID, infoStatus = probe.status, info = info, reason = reason }
    if info then
        candidate.art = ns.Detector:GetArt(uiMapID)
        -- This samples the candidate map's center, NOT the player's location.
        -- 'continentID' is the world Map/InstanceID namespace and may be 0.
        local center = ns.Probe(CreateVector2D, 0.5, 0.5)
        local world = { status = center.status, values = {} }
        if center.status == "ok" then world = ns.MapProbe("GetWorldPosFromMapPos", uiMapID, center.values[1]) end
        candidate.worldStatus = world.status
        candidate.worldMapID = Primitive(world.values[1])
        ns.Print("  Center world MapID=" .. ns.Text(candidate.worldMapID) .. " status=" .. world.status
            .. "; running InstanceID=" .. ns.Text(job.context.instanceID) .. "; never auto-selected")
    end
    job.candidates[#job.candidates + 1] = candidate
end

function Diagnostics:FinishScan(job, status)
    if self.scanJob ~= job then return end
    self.scanJob = nil
    job.status = status
    -- Retain one plain diagnostic snapshot; this is NOT a render registry.
    job.visited, job.apiUiMaps = nil, nil
    if ns.db then
        if type(ns.db.diagnostics) ~= "table" then ns.db.diagnostics = {} end
        ns.db.diagnostics.lastScan = job
    end
    ns.Print("Scan " .. status .. ": scope=UiMapID 1.." .. SCAN_LIMIT .. " plus API hierarchy; tested=" .. job.tested
        .. " records=" .. job.valid .. " candidates=" .. #job.candidates
        .. " nil=" .. (job.statuses["nil"] or 0) .. " errors=" .. (job.statuses.error or 0)
        .. " restricted=" .. (job.statuses.restricted or 0) .. " unavailable=" .. (job.statuses.unavailable or 0))
    if job.skippedInstanceID then ns.Print("Skipped numeric InstanceID collision; no evidence it is a UiMapID.") end
    if #job.candidates == 0 then ns.Print("No candidates in this scan scope; absence beyond this scope is not proven.") end
    ns.Print("Scan is diagnostic only. A matching name or positive texture ID is not proof of the correct drawable dungeon map.")
end

function Diagnostics:Scan()
    if not ns.development then ns.Print("UiMap scanning is development-only."); return end
    if type(ns.Field(C_Map, "GetMapInfo")) ~= "function" then ns.Print("Scan unavailable: C_Map.GetMapInfo is missing."); return end
    if type(ns.Field(C_Timer, "After")) ~= "function" then ns.Print("Scan unavailable: C_Timer.After is missing; no synchronous bulk scan attempted."); return end
    if self.scanJob then self:FinishScan(self.scanJob, "replaced") end
    local context = ScanContext()
    local job = { context = context, nextID = 1, tested = 0, valid = 0,
        visited = {}, apiUiMaps = {}, maps = {}, candidates = {}, statuses = {}, hierarchy = {} }
    job.dungeonType = ns.Field(ns.Field(Enum, "UIMapType"), "Dungeon")
    if not ns.IsNumber(job.dungeonType) then job.dungeonType = nil end
    self.scanJob = job
    ns.Print("Developer scan: build=" .. ns.Text(context.build) .. " instanceID=" .. ns.Text(context.instanceID)
        .. " name=" .. ns.Text(context.name) .. " (InstanceID is not UiMapID)")
    ns.Print("Best UiMap=" .. ns.Text(context.bestUiMapID) .. " (" .. context.bestStatus .. ")"
        .. "; C_Minimap.GetUiMapID=" .. ns.Text(context.minimapUiMapID) .. " (" .. context.minimapStatus .. ")")
    local fallback = ns.MapProbe("GetFallbackWorldMapID")
    for _, root in pairs({ context.bestUiMapID, context.minimapUiMapID, Primitive(fallback.values[1]) }) do
        if ns.IsID(root) and not job.apiUiMaps[root] then
            job.apiUiMaps[root] = true
            self:InspectScanMap(job, root)
            local children = ns.MapProbe("GetMapChildrenInfo", root, nil, true)
            job.hierarchy[#job.hierarchy + 1] = { root = root, status = children.status }
            ns.Print("Hierarchy root=" .. root .. " allDescendants=true status=" .. children.status)
            for index = 1, SCAN_LIMIT do
                local childID = ns.Field(ns.Field(children.values[1], index), "mapID")
                if not ns.IsID(childID) then break end
                job.apiUiMaps[childID] = true
            end
        end
    end
    local function Batch()
        if self.scanJob ~= job then return end
        local current = ns.Probe(GetInstanceInfo)
        if Primitive(current.values[8]) ~= context.instanceID then self:FinishScan(job, "cancelled-instance-changed"); return end
        for _ = 1, SCAN_BATCH do
            if job.nextID > SCAN_LIMIT then
                for uiMapID in pairs(job.apiUiMaps) do self:InspectScanMap(job, uiMapID) end
                self:FinishScan(job, "complete")
                return
            end
            self:InspectScanMap(job, job.nextID)
            job.nextID = job.nextID + 1
        end
        local scheduled = ns.Probe(ns.Field(C_Timer, "After"), 0.02, Batch)
        if scheduled.status == "error" or scheduled.status == "unavailable" then self:FinishScan(job, "timer-failed") end
    end
    Batch()
end

function Diagnostics:StopScan()
    if self.scanJob then self:FinishScan(self.scanJob, "cancelled") end
    self:ClearTileProbe()
    if ns.Composite then ns.Composite:Close() end
end

-- These identifiers come from public Blizzard-file metadata, not another
-- creator's map. See scripts/MAP-DATA-2999.md for exact URLs and limitations.
-- This is a contact-sheet probe, NOT a fallback registry or a finished map.
local RUINS_TILE_PROBES = {
    { fileDataID = 7255712, tileX = 30, tileY = 27 },
    { fileDataID = 7255718, tileX = 31, tileY = 27 },
    { fileDataID = 7255724, tileX = 32, tileY = 27 },
    { fileDataID = 7255730, tileX = 30, tileY = 28 },
    { fileDataID = 7255736, tileX = 31, tileY = 28 },
    { fileDataID = 7255742, tileX = 32, tileY = 28 },
    { fileDataID = 7255748, tileX = 30, tileY = 29 },
    { fileDataID = 7255754, tileX = 31, tileY = 29 },
    { fileDataID = 7255760, tileX = 32, tileY = 29 },
    { path = "world\\minimaps\\2999\\map31_28.blp", tileX = 31, tileY = 28 },
}

-- DEVELOPMENT ONLY: catalog-confirmed native identifiers, not render support.
-- WMO X/Y are local to each numbered group; never collapse groups together.
local TileProbeMaps = {
    [2999] = {
        name = "Ruins of Lordaeron", version = "1.60.1", build = "70124",
        layoutKind = "ground-grid", tiles = RUINS_TILE_PROBES, pathControlFileDataID = 7255736,
    },
    [389] = {
        name = "Ragefire Chasm", version = "1.60.1", build = "70124",
        layoutKind = "wmo-group-local", pathControlFileDataID = 213057,
        -- Full provenance and current-build limits: scripts/MAP-DATA-389.md.
        tiles = {
            { fileDataID = 213056, wmoGroup = 0, tileX = 0, tileY = 0 },
            { fileDataID = 213057, wmoGroup = 1, tileX = 0, tileY = 0 },
            { fileDataID = 213058, wmoGroup = 1, tileX = 0, tileY = 1 },
            { fileDataID = 213059, wmoGroup = 1, tileX = 1, tileY = 0 },
            { fileDataID = 213060, wmoGroup = 1, tileX = 1, tileY = 1 },
            { fileDataID = 213061, wmoGroup = 2, tileX = 0, tileY = 0 },
            { fileDataID = 213062, wmoGroup = 3, tileX = 0, tileY = 0 },
            { fileDataID = 213063, wmoGroup = 3, tileX = 0, tileY = 1 },
            { fileDataID = 213064, wmoGroup = 4, tileX = 0, tileY = 0 },
            { fileDataID = 213065, wmoGroup = 4, tileX = 0, tileY = 1 },
            { fileDataID = 213066, wmoGroup = 4, tileX = 1, tileY = 0 },
            { fileDataID = 213067, wmoGroup = 4, tileX = 1, tileY = 1 },
            { fileDataID = 213068, wmoGroup = 5, tileX = 0, tileY = 0 },
            { fileDataID = 213069, wmoGroup = 6, tileX = 0, tileY = 0 },
            { fileDataID = 213070, wmoGroup = 7, tileX = 0, tileY = 0 },
            { fileDataID = 213071, wmoGroup = 8, tileX = 0, tileY = 0 },
            { fileDataID = 213072, wmoGroup = 9, tileX = 0, tileY = 0 },
            { fileDataID = 213073, wmoGroup = 10, tileX = 0, tileY = 0 },
            { fileDataID = 213074, wmoGroup = 11, tileX = 0, tileY = 0 },
            { path = "world\\minimaps\\wmo\\dungeon\\kl_orgrimmarlavadungeon\\lavadungeon_001_00_00.blp",
                wmoGroup = 1, tileX = 0, tileY = 0 },
        },
    },
}

function Diagnostics:ClearTileProbe()
    self.tileProbeToken = (self.tileProbeToken or 0) + 1
    self.tileContext = nil
    if self.tileFrame then self.tileFrame:Hide() end
    for _, cell in ipairs(self.tileCells or {}) do
        ns.Probe(ns.Field(cell.texture, "SetTexture"), cell.texture, nil)
        cell.texture:Hide()
        cell.label:Hide()
        for _, background in ipairs(cell.checker) do background:Hide() end
    end
    for _, label in ipairs(self.tileGroupLabels or {}) do label:Hide() end
    self.activeTileCells = {}
end

function Diagnostics:HideStaleTileProbe()
    if ns.Composite then ns.Composite:HideStale() end
    if not self.tileContext or not self.tileFrame:IsShown() then return end
    local instance, inside = ns.Probe(GetInstanceInfo), ns.Probe(IsInInstance)
    if Primitive(instance.values[8]) ~= self.tileContext.instanceID or Primitive(inside.values[1]) ~= true then
        self:ClearTileProbe()
    end
end

function Diagnostics:LayoutTileProbe(probe)
    local groups, order, controls = {}, {}, {}
    for _, metadata in ipairs(probe.tiles) do
        if metadata.path then
            controls[#controls + 1] = metadata
        else
            local key = metadata.wmoGroup or -1
            if not groups[key] then
                groups[key] = { key = key, minX = metadata.tileX, maxX = metadata.tileX,
                    minY = metadata.tileY, maxY = metadata.tileY, tiles = {} }
                order[#order + 1] = key
            end
            local group = groups[key]
            group.minX, group.maxX = math.min(group.minX, metadata.tileX), math.max(group.maxX, metadata.tileX)
            group.minY, group.maxY = math.min(group.minY, metadata.tileY), math.max(group.maxY, metadata.tileY)
            group.tiles[#group.tiles + 1] = metadata
        end
    end
    table.sort(order)
    local maxColumns, maxRows = 1, 1
    for _, key in ipairs(order) do
        local group = groups[key]
        maxColumns = math.max(maxColumns, group.maxX - group.minX + 1)
        maxRows = math.max(maxRows, group.maxY - group.minY + 1)
    end
    local pitch, previewSize = 112, 80 -- UI preview sizes, not native BLP dimensions
    local panelWidth, panelHeight = maxColumns * pitch + 16, maxRows * pitch + 28
    local panelColumns = math.min(4, #order)
    local controlTop = 62 + math.ceil(#order / panelColumns) * panelHeight
    local width = math.max(480, 24 + panelColumns * panelWidth)
    local height = controlTop + 140
    self.tileFrame:SetSize(width, height)
    local screenWidth, screenHeight = UIParent:GetSize()
    self.tileFrame:SetScale(math.min(1, math.max(0.1, (screenWidth - 32) / width), math.max(0.1, (screenHeight - 32) / height)))

    local function Place(metadata, x, y)
        local index = #self.activeTileCells + 1
        local cell = self.tileCells[index]
        if not cell then
            cell = { checker = {} }
            cell.texture = self.tileFrame:CreateTexture(nil, "ARTWORK")
            cell.label = self.tileFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            -- A plain-color checkerboard makes transparency visible; no image asset.
            for quadrant = 1, 4 do
                local background = self.tileFrame:CreateTexture(nil, "BACKGROUND")
                local shade = (quadrant == 1 or quadrant == 4) and 0.24 or 0.12
                background:SetColorTexture(shade, shade, shade, 1)
                cell.checker[quadrant] = background
            end
            self.tileCells[index] = cell
        end
        cell.metadata = metadata
        cell.texture:ClearAllPoints()
        cell.texture:SetPoint("TOPLEFT", self.tileFrame, "TOPLEFT", x, -y)
        cell.texture:SetSize(previewSize, previewSize)
        cell.texture:SetTexCoord(0, 1, 0, 1) -- full image; no invented crop/flip/rotation
        for quadrant, background in ipairs(cell.checker) do
            background:ClearAllPoints()
            background:SetPoint("TOPLEFT", cell.texture, "TOPLEFT", ((quadrant - 1) % 2) * previewSize / 2,
                -math.floor((quadrant - 1) / 2) * previewSize / 2)
            background:SetSize(previewSize / 2, previewSize / 2)
            background:Show()
        end
        cell.label:ClearAllPoints()
        cell.label:SetPoint("TOPLEFT", cell.texture, "BOTTOMLEFT", 0, -3)
        cell.label:SetText("X=" .. metadata.tileX .. " Y=" .. metadata.tileY .. "\n"
            .. (metadata.fileDataID and tostring(metadata.fileDataID) or "path vs " .. probe.pathControlFileDataID))
        cell.label:Show()
        cell.texture:Show()
        self.activeTileCells[index] = cell
    end
    for panelIndex, key in ipairs(order) do
        local group = groups[key]
        local x = 12 + ((panelIndex - 1) % panelColumns) * panelWidth
        local y = 62 + math.floor((panelIndex - 1) / panelColumns) * panelHeight
        local label = self.tileGroupLabels[panelIndex]
        if not label then
            label = self.tileFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            self.tileGroupLabels[panelIndex] = label
        end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self.tileFrame, "TOPLEFT", x, -y)
        label:SetText(key == -1 and "Terrain grid" or string.format("WMO group %03d (local X/Y)", key))
        label:Show()
        for _, metadata in ipairs(group.tiles) do
            Place(metadata, x + (metadata.tileX - group.minX) * pitch, y + 24 + (metadata.tileY - group.minY) * pitch)
        end
    end
    for _, metadata in ipairs(controls) do Place(metadata, 12, controlTop + 12) end
end

function Diagnostics:ProbeTiles()
    if not ns.development then ns.Print("Native tile probing is development-only."); return end
    if ns.Composite then ns.Composite:Close() end
    self:ClearTileProbe()
    local context = ScanContext()
    local probe = TileProbeMaps[context.instanceID]
    if not probe then
        ns.Print("No tile probe metadata is registered for InstanceID " .. ns.Text(context.instanceID) .. ".")
        return
    end
    local buildAllowed = context.build == probe.build and context.version == probe.version
    if context.instanceID == 389 then
        buildAllowed = ns.MapRegistry:GetVerified(389, context.version, context.build) ~= nil
    end
    if not buildAllowed or context.inside ~= true then
        ns.Print("This tile probe requires build " .. probe.version .. "." .. probe.build .. " inside its registered instance.")
        return
    end
    if ns.InCombat() then ns.Print("Run /dlmap scan tiles outside combat."); return end
    if not self.tileFrame then
        local frame = CreateFrame("Frame", "DungeonLensTileProbe", UIParent)
        self.tileFrame, self.tileCells, self.tileGroupLabels = frame, {}, {}
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.035, 0.045, 0.065, 1)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
        self.tileTitle = title
        local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
        self.tileCaption = caption
        local close = CreateFrame("Button", nil, frame)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
        local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        closeText:SetPoint("CENTER")
        closeText:SetText("X")
        close:SetScript("OnClick", function() frame:Hide() end)
        local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
        footer:SetText("Report visible/green/blank tiles; X, ESC or /dlmap scan stop closes.")
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DungeonLensTileProbe" end
    end
    self.tileTitle:SetText("Tile probe - " .. probe.name)
    self.tileCaption:SetText(probe.layoutKind == "wmo-group-local"
        and "WMO panels are separate groups, not a continuous dungeon map."
        or "Raw terrain-coordinate contact sheet; not a registered dungeon map.")
    self:LayoutTileProbe(probe)
    self.tileContext = context
    local token = self.tileProbeToken
    for _, cell in ipairs(self.activeTileCells) do
        local asset = cell.metadata.fileDataID or cell.metadata.path
        cell.request = ns.Probe(ns.Field(cell.texture, "SetTexture"), cell.texture, asset)
    end
    self.tileFrame:Show()
    ns.Print("Tile probe: " .. probe.name .. " InstanceID=" .. context.instanceID .. " layout=" .. probe.layoutKind
        .. " requested=" .. (#self.activeTileCells - 1) .. " native FileDataIDs + one path control.")
    ns.Print("Trial layout: X increases right, Y increases down within each panel. WMO group positions are not inferred.")
    ns.Print("SetTexture success is not a loading guarantee. Visually check all tiles; native pixel dimensions and orientation remain unverified.")
    local function ReportLoads()
        self:HideStaleTileProbe()
        if token ~= self.tileProbeToken or not self.tileFrame:IsShown() then return end
        local report = { context = context, probeName = probe.name, layoutKind = probe.layoutKind, results = {} }
        for _, cell in ipairs(self.activeTileCells) do
            local loaded = ns.Probe(ns.Field(cell.texture, "IsObjectLoaded"), cell.texture)
            local identifier = ns.Probe(ns.Field(cell.texture, "GetTextureFileID"), cell.texture)
            local metadata = cell.metadata
            report.results[#report.results + 1] = {
                fileDataID = metadata.fileDataID, path = metadata.path, tileX = metadata.tileX, tileY = metadata.tileY,
                wmoGroup = metadata.wmoGroup, pathControlFileDataID = metadata.path and probe.pathControlFileDataID or nil,
                requestStatus = cell.request.status, requestReturn = Primitive(cell.request.values[1]),
                loadedStatus = loaded.status, loaded = Primitive(loaded.values[1]),
                reportedFileDataID = Primitive(identifier.values[1]),
            }
            ns.Print("Tile group=" .. ns.Text(metadata.wmoGroup) .. " X=" .. metadata.tileX .. " Y=" .. metadata.tileY
                .. " asset=" .. ns.Text(metadata.fileDataID or metadata.path)
                .. " SetTexture=" .. Value(cell.request) .. " IsObjectLoaded=" .. Value(loaded)
                .. " GetTextureFileID=" .. Value(identifier))
        end
        if ns.db then
            if type(ns.db.diagnostics) ~= "table" then ns.db.diagnostics = {} end
            ns.db.diagnostics.lastTileProbe = report
        end
        ns.Print("One-shot tile samples finished; report actual visible artwork as well as the API values.")
    end
    local scheduled = ns.Probe(ns.Field(C_Timer, "After"), 2, ReportLoads)
    if scheduled.status == "error" or scheduled.status == "unavailable" then ReportLoads() end
end

function Diagnostics:ReportResolution(state)
    local decision = state.resolution
    if not decision then ns.Print("Resolver decision: not recorded"); return end
    ns.Print("Native UiMap: " .. (state.hasNativeArt and "usable" or "unavailable")
        .. " best=" .. ns.Text(state.uiMapID) .. " status=" .. ns.Text(state.bestMapStatus))
    ns.Print("Instance fallback: " .. ns.Text(state.instanceID) .. " / "
        .. ns.Text(decision.registryEntry and decision.registryEntry.displayName or state.instanceName)
        .. " lookupKey=" .. ns.Text(decision.lookupKey))
    ns.Print("Registry entry: " .. (decision.registryFound and "found" or "not found")
        .. " source=" .. ns.Text(decision.sourceType))
    ns.Print("Verified build: " .. ns.Text(decision.verifiedVersion) .. "." .. ns.Text(decision.verifiedBuild)
        .. " Current build: " .. ns.Text(decision.currentVersion) .. "." .. ns.Text(decision.currentBuild)
        .. " interface=" .. ns.Text(decision.currentInterface))
    ns.Print("Compatibility: " .. ns.Text(decision.compatibility) .. " allowed=" .. tostring(decision.buildCompatible)
        .. " reason=" .. ns.Text(decision.compatibilityReason))
    local rendererName = state.renderSource == "blizzard-wmo-minimap" and "WMO minimap"
        or state.renderSource == "native-uimap" and "native Dungeon UiMap" or "none"
    ns.Print("Renderer selected: " .. rendererName .. " fallbackSelected=" .. tostring(decision.fallbackSelected)
        .. " reason=" .. ns.Text(decision.selectionReason))
    if decision.renderAttempted == nil then
        ns.Print("Renderer attempt: not attempted (normal window closed/not created)")
    else
        ns.Print("Renderer attempt: " .. tostring(decision.renderAttempted) .. " accepted=" .. tostring(decision.renderSucceeded)
            .. " reason=" .. ns.Text(decision.renderReason))
    end
end

function Diagnostics:ReportPosition(mapID)
    if not ns.IsID(mapID) then return end
    local probe = ns.MapProbe("GetPlayerMapPosition", mapID, "player")
    local position = probe.values[1]
    if probe.status ~= "ok" then
        ns.Print("GetPlayerMapPosition(" .. mapID .. ")=" .. probe.status .. "; marker disabled")
        return
    end
    local coordinates = ns.Probe(ns.Field(position, "GetXY"), position)
    local x, y = coordinates.values[1], coordinates.values[2]
    if coordinates.status == "unavailable" or coordinates.status == "error" then
        x, y = ns.Field(position, "x"), ns.Field(position, "y")
    end
    local normalized = ns.IsNumber(x) and ns.IsNumber(y)
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
    ns.Print("GetPlayerMapPosition(" .. mapID .. ") x=" .. ns.Text(x) .. " y=" .. ns.Text(y)
        .. " normalized=" .. tostring(normalized) .. "; marker disabled pending runtime validation")
end

function Diagnostics:Report()
    ns.Refresh("debug")
    ns.Print("v" .. ns.version .. " diagnostics (development=" .. tostring(ns.development) .. ")")
    local build = ns.Probe(GetBuildInfo)
    ns.Print("GetBuildInfo: version=" .. Value(build, 1) .. " build=" .. Value(build, 2)
        .. " date=" .. Value(build, 3) .. " interface=" .. Value(build, 4))
    local inside = ns.Probe(IsInInstance)
    ns.Print("IsInInstance: inside=" .. Value(inside, 1) .. " type=" .. Value(inside, 2))
    local instance = ns.Probe(GetInstanceInfo)
    ns.Print("GetInstanceInfo: name=" .. Value(instance, 1) .. " type=" .. Value(instance, 2)
        .. " difficultyID=" .. Value(instance, 3) .. " difficulty=" .. Value(instance, 4)
        .. " maxPlayers=" .. Value(instance, 5) .. " instanceID=" .. Value(instance, 8))
    local best = ns.MapProbe("GetBestMapForUnit", "player")
    ns.Print("GetBestMapForUnit(player)=" .. Value(best)
        .. " Enum.UIMapType.Dungeon=" .. ns.Text(ns.Field(ns.Field(Enum, "UIMapType"), "Dungeon")))
    self:ReportMap(best.values[1], "Current map")
    if ns.state then
        local state = ns.state
        self:ReportResolution(state)
        ns.Print("Detection: dungeon=" .. tostring(state.currentIsDungeon)
            .. " renderMap=" .. ns.Text(state.mapID) .. " usable=" .. tostring(state.hasNativeArt)
            .. " reason=" .. ns.Text(state.reason))
        ns.Print("Resolved source=" .. ns.Text(state.renderSource) .. " hasMap=" .. tostring(state.hasMap)
            .. " registry InstanceID=" .. ns.Text(state.mapEntry and state.mapEntry.instanceID))
        ns.Print("Current-map native tiles usable=" .. tostring(state.currentArt.usable)
            .. " reason=" .. ns.Text(state.currentArt.reason))
        if state.mapID and state.mapID ~= state.uiMapID then self:ReportMap(state.mapID, "Dungeon ancestor") end
        for index, parent in ipairs(state.parents or {}) do
            if index > 4 then ns.Print("Parents: additional ancestors omitted"); break end
            ns.Print("Parent: " .. MapSummary(parent))
        end
        ns.Print("GetMapChildrenInfo=" .. ns.Text(state.childrenStatus)
            .. " possibleDungeonChildren=" .. #(state.children or {}) .. " (navigation disabled)")
        for index, child in ipairs(state.children or {}) do
            if index > 8 then ns.Print("Children: additional candidates omitted"); break end
            ns.Print("Child: " .. MapSummary(child))
        end
        ns.Print("Map group=" .. ns.Text(state.groupID) .. " members=" .. #(state.groupMembers or {}))
        for index, member in ipairs(state.groupMembers or {}) do
            if index > 8 then ns.Print("Group: additional members omitted"); break end
            ns.Print("Group member: id=" .. ns.Text(member.mapID) .. " name=" .. ns.Text(member.name)
                .. " relativeHeightIndex=" .. ns.Text(member.relativeHeightIndex))
        end
        self:ReportPosition(state.mapID or state.uiMapID)
    end
    local unavailable = {}
    for event, registered in pairs(ns.registeredEvents) do
        if not registered then unavailable[#unavailable + 1] = event end
    end
    table.sort(unavailable)
    if #unavailable > 0 then ns.Print("Unavailable events: " .. table.concat(unavailable, ", ")) end
    local geometry = ns.db and ns.db.window or {}
    ns.Print("Saved window: " .. ns.Text(geometry.width) .. "x" .. ns.Text(geometry.height)
        .. " " .. ns.Text(geometry.point) .. " x=" .. ns.Text(geometry.x) .. " y=" .. ns.Text(geometry.y)
        .. " open=" .. ns.Text(geometry.shown))
    ns.Print("M-key integration=disabled; /dlmap opens DungeonLens; Blizzard map bindings are unchanged.")
end
