local _, ns = ...
local Renderer = {}
ns.Renderer = Renderer

function Renderer:Create(parent)
    local renderer = setmetatable({ tiles = {} }, { __index = self })
    renderer.canvas = CreateFrame("Frame", nil, parent)
    renderer.overlay = ns.Overlay:Create(renderer.canvas)
    parent:SetScript("OnSizeChanged", function() renderer:Layout() end)
    renderer.parent = parent
    -- Allocate the known WMO pool while the window is created outside combat.
    -- Reopening/transitioning an existing viewer only reuses these regions.
    for index = 1, ns.MapRegistry:MaxTileCount() do
        local texture = renderer.canvas:CreateTexture(nil, "ARTWORK")
        ns.WMOComposition:PrepareTexture(texture)
        texture:Hide()
        renderer.tiles[index] = texture
    end
    return renderer
end

function Renderer:Clear()
    self.layer = nil
    self.composition, self.mapEntry = nil, nil
    for _, tile in ipairs(self.tiles) do
        tile:Hide()
        tile:SetTexture(nil)
    end
    self.canvas:Hide()
    self.overlay:Clear()
end

function Renderer:ShowWMO(entry, composition)
    if not entry or not composition or (composition.mode ~= "canonical" and composition.mode ~= "ground") then
        self:Clear(); return false, "wmo-layout-missing-or-not-canonical"
    end
    if self.mapEntry == entry and self.composition == composition then
        self.canvas:Show()
        self:Layout()
        return true, "existing-wmo-texture-requests-reused"
    end
    self:Clear()
    self.mapEntry, self.composition = entry, composition
    for index, tile in ipairs(composition.tiles) do
        local texture = self.tiles[index]
        -- The registered pool is preallocated; do not rebuild a frame/texture
        -- hierarchy in combat or on every zone event.
        if not texture then
            self:Clear()
            return false, "wmo-texture-pool-missing: FileDataID=" .. tile.fileDataID
        end
        local accepted, status = ns.WMOComposition:LoadTexture(texture, tile.fileDataID)
        if not accepted then
            self:Clear()
            return false, "wmo-SetTexture-rejected: FileDataID=" .. tile.fileDataID .. " status=" .. ns.Text(status)
        end
        texture:Show()
    end
    self.canvas:Show()
    self:Layout()
    return true, "wmo-texture-requests-accepted; visual-load-not-proven"
end

function Renderer:ShowArt(art)
    self:Clear()
    if not art or not art.usable or not art.layer then return false end
    self.layer = art.layer
    local count = self.layer.columns * self.layer.rows
    for index = 1, count do
        local tile = self.tiles[index]
        if not tile then
            tile = self.canvas:CreateTexture(nil, "ARTWORK")
            self.tiles[index] = tile
        end
        tile:SetDrawLayer("ARTWORK", 0)
        local ok, accepted = pcall(tile.SetTexture, tile, self.layer.textures[index])
        if not ok or accepted == false then
            self:Clear()
            return false
        end
        tile:Show()
    end
    self.canvas:Show()
    self:Layout()
    return true
end

function Renderer:Layout()
    if self.composition then
        local width, height = self.parent:GetSize()
        if not ns.IsNumber(width) or not ns.IsNumber(height) or width <= 0 or height <= 0 then return end
        local scale = math.min(width / self.composition.width, height / self.composition.height)
        self.fit = scale
        self.canvas:ClearAllPoints()
        self.canvas:SetPoint("CENTER", self.parent, "CENTER", 0, 0)
        self.canvas:SetSize(self.composition.width * scale, self.composition.height * scale)
        for index, tile in ipairs(self.composition.tiles) do
            ns.WMOComposition:PositionTexture(self.tiles[index], self.canvas, tile, scale)
        end
        self.overlay:Layout()
        return
    end
    local layer = self.layer
    if not layer then return end
    local width, height = self.parent:GetSize()
    if not ns.IsNumber(width) or not ns.IsNumber(height) or width <= 0 or height <= 0 then return end
    local scale = math.min(width / layer.width, height / layer.height)
    self.canvas:ClearAllPoints()
    self.canvas:SetPoint("CENTER", self.parent, "CENTER", 0, 0)
    self.canvas:SetSize(layer.width * scale, layer.height * scale)
    for index = 1, layer.columns * layer.rows do
        -- Native client IDs are row-major (left to right, then next row).
        local column = (index - 1) % layer.columns
        local row = math.floor((index - 1) / layer.columns)
        local nativeX, nativeY = column * layer.tileWidth, row * layer.tileHeight
        local visibleWidth = math.min(layer.tileWidth, layer.width - nativeX)
        local visibleHeight = math.min(layer.tileHeight, layer.height - nativeY)
        local tile = self.tiles[index]
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", nativeX * scale, -nativeY * scale)
        tile:SetSize(visibleWidth * scale, visibleHeight * scale)
        -- Partial edge tiles contain padding. Crop their UVs rather than
        -- squeezing a full tile into a narrower rectangle.
        tile:SetTexCoord(0, visibleWidth / layer.tileWidth, 0, visibleHeight / layer.tileHeight)
    end
    self.overlay:Layout()
end
