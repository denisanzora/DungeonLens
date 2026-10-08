local _, ns = ...
local Detector = {}
ns.Detector = Detector

local function PlainString(value)
    if ns.IsReadable(value) and type(value) == "string" then return value end
end

local function MapDetails(info)
    local mapID = ns.Field(info, "mapID")
    if not ns.IsID(mapID) then return nil end
    return {
        mapID = mapID,
        name = PlainString(ns.Field(info, "name")),
        mapType = ns.Field(info, "mapType"),
        parentMapID = ns.Field(info, "parentMapID"),
    }
end

function Detector:GetMap(mapID)
    if not ns.IsID(mapID) then return nil end
    local probe = ns.MapProbe("GetMapInfo", mapID)
    return MapDetails(probe.values[1])
end

local function Dimension(value)
    return ns.IsNumber(value) and value > 0 and value <= 65536
end

-- Art layers are zoom-level alternatives, not dungeon floors. Select one
-- complete native layer for our fit-to-window view, never overlay all layers.
function Detector:GetArt(mapID)
    local art = { usable = false, layers = {}, reason = "no-map" }
    if not ns.IsID(mapID) then return art end
    local idProbe = ns.MapProbe("GetMapArtID", mapID)
    if ns.IsID(idProbe.values[1]) then art.artID = idProbe.values[1] end
    art.artIDStatus = idProbe.status
    local layersProbe = ns.MapProbe("GetMapArtLayers", mapID)
    art.layersStatus = layersProbe.status
    art.reason = "no-native-layers"
    for layerIndex = 1, 16 do
        local raw = ns.Field(layersProbe.values[1], layerIndex)
        if not raw then break end
        local layer = {
            index = layerIndex,
            width = ns.Field(raw, "layerWidth"), height = ns.Field(raw, "layerHeight"),
            tileWidth = ns.Field(raw, "tileWidth"), tileHeight = ns.Field(raw, "tileHeight"),
            minScale = ns.Field(raw, "minScale"), maxScale = ns.Field(raw, "maxScale"),
        }
        art.layers[#art.layers + 1] = layer
        if Dimension(layer.width) and Dimension(layer.height)
            and Dimension(layer.tileWidth) and Dimension(layer.tileHeight) then
            layer.columns = math.ceil(layer.width / layer.tileWidth)
            layer.rows = math.ceil(layer.height / layer.tileHeight)
            local count = layer.columns * layer.rows
            if count <= 512 then
                local textures = ns.MapProbe("GetMapArtLayerTextures", mapID, layerIndex)
                layer.texturesStatus = textures.status
                layer.textures = {}
                layer.usable = true
                for index = 1, count do
                    local textureID = ns.Field(textures.values[1], index)
                    if not ns.IsID(textureID) then
                        layer.usable = false
                        break
                    end
                    layer.textures[index] = textureID
                end
                if layer.usable and not art.layer then
                    art.layer = layer
                    art.usable = true
                    art.reason = "native-tile-ids"
                elseif not layer.usable and not art.usable then
                    art.reason = "incomplete-native-tiles"
                end
            else
                layer.usable = false
                if not art.usable then art.reason = "unsupported-tile-count" end
            end
        elseif not art.usable then
            art.reason = "invalid-layer-dimensions"
        end
    end
    return art
end

function Detector:CollectRelations(state, dungeonType)
    local relationMapID = state.mapID or state.uiMapID
    if not relationMapID then return end
    -- Immediate children only. A zone's children are diagnostic candidates,
    -- never evidence that an arbitrary child is this player's instance.
    local probe = ns.MapProbe("GetMapChildrenInfo", relationMapID, dungeonType, false)
    state.childrenStatus = probe.status
    for index = 1, 128 do
        local raw = ns.Field(probe.values[1], index)
        if not raw then break end
        local child = MapDetails(raw)
        if child and dungeonType ~= nil and child.mapType == dungeonType then
            state.children[#state.children + 1] = child
        end
    end
    local group = ns.MapProbe("GetMapGroupID", relationMapID)
    if not ns.IsID(group.values[1]) then return end
    state.groupID = group.values[1]
    local members = ns.MapProbe("GetMapGroupMembersInfo", state.groupID)
    state.groupStatus = members.status
    for index = 1, 128 do
        local raw = ns.Field(members.values[1], index)
        if not raw then break end
        local mapID = ns.Field(raw, "mapID")
        if ns.IsID(mapID) then
            state.groupMembers[#state.groupMembers + 1] = {
                mapID = mapID, name = PlainString(ns.Field(raw, "name")),
                relativeHeightIndex = ns.Field(raw, "relativeHeightIndex"),
            }
        end
    end
end

function Detector:Detect(source)
    local state = {
        source = source, inInstance = nil, instanceType = nil, instanceName = nil,
        instanceID = nil, uiMapID = nil, currentIsDungeon = false, mapID = nil,
        parents = {}, children = {}, groupMembers = {}, hasNativeArt = false,
        supportedInstance = false, renderSource = "none", hasMap = false, reason = "instance-status-unavailable",
    }
    local inside = ns.Probe(IsInInstance)
    if inside.status == "ok" and type(inside.values[1]) == "boolean" then
        state.inInstance = inside.values[1]
        state.instanceType = PlainString(inside.values[2])
    end
    local instance = ns.Probe(GetInstanceInfo)
    state.instanceName = PlainString(instance.values[1])
    state.instanceType = state.instanceType or PlainString(instance.values[2])
    if ns.IsID(instance.values[8]) then state.instanceID = instance.values[8] end
    state.supportedInstance = state.inInstance == true
        and (state.instanceType == "party" or state.instanceType == "raid")

    local best = ns.MapProbe("GetBestMapForUnit", "player")
    state.bestMapStatus = best.status
    if ns.IsID(best.values[1]) then state.uiMapID = best.values[1] end
    state.mapInfo = self:GetMap(state.uiMapID)
    local dungeonType = ns.Field(ns.Field(Enum, "UIMapType"), "Dungeon")
    if not ns.IsNumber(dungeonType) then dungeonType = nil end
    state.currentIsDungeon = dungeonType ~= nil and state.mapInfo ~= nil
        and state.mapInfo.mapType == dungeonType

    local info, visited = state.mapInfo, {}
    for depth = 1, 8 do
        if not info or visited[info.mapID] then break end
        visited[info.mapID] = true
        if depth > 1 then state.parents[#state.parents + 1] = info end
        if state.supportedInstance and dungeonType ~= nil
            and info.mapType == dungeonType and not state.mapID then
            state.mapID = info.mapID
            state.dungeonMapInfo = info
        end
        info = self:GetMap(info.parentMapID)
    end
    self:CollectRelations(state, dungeonType)
    -- Current-map artwork is recorded even if the best map is a zone. The UI
    -- must never label that outdoor zone artwork as the player's dungeon.
    state.currentArt = self:GetArt(state.uiMapID)
    if state.mapID == state.uiMapID then
        state.art = state.currentArt
    else
        state.art = self:GetArt(state.mapID)
    end
    state.hasNativeArt = state.supportedInstance and state.mapID ~= nil and state.art.usable
    if state.inInstance == nil then
        state.reason = "instance-status-unavailable"
    elseif state.inInstance == false then
        state.reason = "outside-instance"
    elseif state.inInstance == true and not state.supportedInstance then
        state.reason = "not-dungeon-or-raid"
    elseif not state.uiMapID then
        state.reason = "no-current-uimapid"
    elseif dungeonType == nil then
        state.reason = "dungeon-enum-unavailable"
    elseif not state.mapID then
        state.reason = "no-dungeon-map-in-current-ancestry"
    else
        state.reason = state.art.reason
    end
    -- Capture the actual runtime decision, including an entry rejected before
    -- rendering. Native map priority does not hide registry lookup diagnostics.
    local build = ns.Probe(GetBuildInfo)
    local entry, decision = ns.MapRegistry:GetVerified(state.instanceID, ns.Field(build.values, 1), ns.Field(build.values, 2))
    state.resolution = decision
    decision.currentInterface = ns.Field(build.values, 4)
    decision.nativeUiMap = state.hasNativeArt
    -- Keep world InstanceID, UiMapID and FileDataID separate. A real current
    -- Dungeon UiMap/ancestor wins; the registry is consulted only on fallback.
    if state.hasNativeArt then
        state.renderSource, state.hasMap = "native-uimap", true
        decision.selectionReason = "native-dungeon-uimap-priority"
    elseif state.supportedInstance and state.instanceID then
        if entry then
            local layout, reason = ns.WMOComposition:GetLayout(entry)
            if layout then
                state.mapEntry, state.composition = entry, layout
                state.renderSource, state.hasMap = entry.sourceType, true
                state.reason = entry.verified and "verified-" or "candidate-"
                state.reason = state.reason .. (entry.sourceType == "blizzard-ground-minimap" and "ground-minimap" or "wmo-minimap")
                decision.fallbackSelected, decision.selectionReason = true, "known-instance-fallback-selected"
            else
                state.reason = reason
                decision.selectionReason = "wmo-layout-rejected: " .. ns.Text(reason)
            end
        else
            state.reason = decision.compatibilityReason
            decision.selectionReason = decision.compatibilityReason
        end
    else
        decision.selectionReason = state.reason
    end
    decision.rendererSelected = state.renderSource
    return state
end

-- Browser/preview: resolve a REGISTERED dungeon without requiring the character to be inside it.
-- Registry compatibility and layout validation are unchanged; only the instance gate is bypassed,
-- and the state is marked `preview` so nothing pretends the player is there.
function Detector:ForPreview(instanceID, floor)
    local build = ns.Probe(GetBuildInfo)
    local raw = ns.MapRegistry:Get(instanceID)
    local entry, decision = ns.MapRegistry:GetVerified(instanceID, ns.Field(build.values, 1), ns.Field(build.values, 2))
    local state = { preview = true, instanceID = instanceID, instanceName = raw and raw.displayName,
        inInstance = nil, supportedInstance = true, renderSource = "none", hasMap = false, reason = "preview",
        parents = {}, children = {}, groupMembers = {}, resolution = decision, floor = 1, floorCount = 1 }
    decision.selectionReason = "preview-browser"
    decision.nativeUiMap = false
    if not entry then
        state.reason = decision.compatibilityReason
        decision.rendererSelected = "none"
        return state
    end
    local count = ns.WMOComposition:FloorCount(entry)
    floor = math.max(1, math.min(count, floor or 1))
    local layout, reason = ns.WMOComposition:GetLayout(entry, floor)
    if layout then
        state.mapEntry, state.composition = entry, layout
        state.renderSource, state.hasMap = entry.sourceType, true
        state.floor, state.floorCount = floor, count
        state.reason = (entry.verified and "verified-" or "candidate-")
            .. (entry.sourceType == "blizzard-ground-minimap" and "ground-minimap" or "wmo-minimap")
        decision.fallbackSelected = true
    else
        state.reason = reason
        decision.selectionReason = "wmo-layout-rejected: " .. ns.Text(reason)
    end
    decision.rendererSelected = state.renderSource
    return state
end
