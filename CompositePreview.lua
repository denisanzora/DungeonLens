local _, ns = ...
local Preview = {}
ns.Composite = Preview

-- Diagnostics use the same registry and canonical calculator as production.
function Preview:BuildLayout(mode)
    local entry = ns.MapRegistry:Get(389)
    if mode == "canonical" then return ns.WMOComposition:GetCanonical(entry) end
    return ns.WMOComposition:BuildLayout(entry, mode)
end

local function Label(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text or "")
    return label
end

function Preview:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "DungeonLensCompositePreview", UIParent)
    self.frame, self.textures, self.outlines, self.cellOutlines, self.contentOutlines = frame, {}, {}, {}, {}
    frame:Hide()
    local screenWidth, screenHeight = UIParent:GetSize()
    frame:SetSize(math.min(960, screenWidth - 32), math.min(760, screenHeight - 32))
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.025, 0.035, 0.05, 0.98)
    local title = Label(frame, "GameFontNormalLarge", "Ragefire Chasm - DEVELOPMENT COMPOSITE")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    self.caption = Label(frame, "GameFontHighlightSmall")
    self.caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeText = Label(close, "GameFontNormal", "X")
    closeText:SetPoint("CENTER")
    close:SetScript("OnClick", function() self:Close() end)
    self.area = CreateFrame("Frame", nil, frame)
    self.area:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -68)
    self.area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 36)
    self.canvas = CreateFrame("Frame", nil, self.area)
    -- No opaque per-group fill: native alpha remains visible through overlaps.
    local footer = Label(frame, "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
    self.footer = footer
    self.area:SetScript("OnSizeChanged", function() self:Render() end)
    frame:SetScript("OnHide", function() self.context = nil end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DungeonLensCompositePreview" end
end

local function HideOutlines(pool)
    -- Cropped-content outlines are sparse (only cropped tile indices exist).
    for _, outline in pairs(pool) do
        for _, line in ipairs(outline.edges) do line:Hide() end
        outline.label:Hide()
    end
end

local function DrawOutline(preview, pool, index, x, y, width, height, color, text)
    local outline = pool[index]
    if not outline then
        outline = { edges = {}, label = Label(preview.canvas, "GameFontNormalSmall") }
        for edge = 1, 4 do
            outline.edges[edge] = preview.canvas:CreateTexture(nil, "OVERLAY")
            outline.edges[edge]:SetColorTexture(color[1], color[2], color[3], color[4])
        end
        pool[index] = outline
    end
    local fit = preview.fit
    x, y, width, height = x * fit, y * fit, width * fit, height * fit
    local rectangles = { { x, y, width, 1 }, { x, y + height - 1, width, 1 },
        { x, y, 1, height }, { x + width - 1, y, 1, height } }
    for edge, rectangle in ipairs(rectangles) do
        local line = outline.edges[edge]
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", preview.canvas, "TOPLEFT", rectangle[1], -rectangle[2])
        line:SetSize(rectangle[3], rectangle[4])
        line:Show()
    end
    outline.label:ClearAllPoints()
    outline.label:SetPoint("TOPLEFT", preview.canvas, "TOPLEFT", x + 3, -y - 3)
    outline.label:SetText(text or "")
    if text then outline.label:Show() else outline.label:Hide() end
end

function Preview:Render()
    local layout = self.layout
    if not layout or not self.frame then return end
    local width, height = self.area:GetSize()
    if width <= 0 or height <= 0 then return end
    local fit = math.min(width / layout.width, height / layout.height)
    self.fit = fit
    self.canvas:ClearAllPoints()
    self.canvas:SetPoint("CENTER", self.area, "CENTER", 0, 0)
    self.canvas:SetSize(layout.width * fit, layout.height * fit)
    for index, tile in ipairs(layout.tiles) do
        local texture = self.textures[index]
        if not texture then
            texture = self.canvas:CreateTexture(nil, "ARTWORK")
            ns.WMOComposition:PrepareTexture(texture)
            self.textures[index] = texture
        end
        ns.WMOComposition:PositionTexture(texture, self.canvas, tile, fit)
        local accepted = ns.WMOComposition:LoadTexture(texture, tile.fileDataID)
        texture:Show()
        if not accepted then texture:Hide() end
    end
    HideOutlines(self.outlines)
    HideOutlines(self.cellOutlines)
    HideOutlines(self.contentOutlines)
    if layout.mode == "canonical" then
        for index, tile in ipairs(layout.tiles) do
            DrawOutline(self, self.cellOutlines, index, tile.cellX, tile.cellY, tile.cellWidth, tile.cellHeight,
                { 0.35, 0.8, 1, 0.65 }, string.format("%03d (%d,%d)", tile.groupIndex, tile.localX, tile.localY))
            if tile.width ~= layout.stride or tile.height ~= layout.stride then
                DrawOutline(self, self.contentOutlines, index, tile.x, tile.y, tile.width, tile.height,
                    { 1, 0.85, 0.45, 0.8 })
            end
        end
        self.footer:SetText("Canonical: tile-Y inversion + bottom-left content; UVs unchanged  |  Blue=256 cells, gold=cropped content  |  ESC / X")
    else
        for index, group in ipairs(layout.groups) do
            DrawOutline(self, self.outlines, index, group.x, group.y, group.width, group.height,
                { 0.35, 0.8, 1, 0.75 }, string.format("%03d", group.index))
        end
        self.footer:SetText("Legacy trial: global group-Y only; local Y/UV unchanged  |  /dlmap scan composite [flipy|canonical]  |  ESC / X")
    end
    self.caption:SetText(string.format("TRIAL  |  mode=%s  |  rho=2 px/unit  |  raster=%.9f x %.9f px  |  matches=12/12",
        layout.mode, layout.width, layout.height))
end

function Preview:Close()
    self.context = nil
    if self.frame then self.frame:Hide() end
end

function Preview:HideStale()
    if not self.context or not self.frame:IsShown() then return end
    local inside, instance = ns.Probe(IsInInstance), ns.Probe(GetInstanceInfo)
    if inside.status ~= "ok" or inside.values[1] ~= true or ns.Field(instance.values, 8) ~= 389 then self:Close() end
end

function Preview:Open(mode)
    if not ns.development then ns.Print("Composite preview is development-only."); return end
    local build, inside, instance = ns.Probe(GetBuildInfo), ns.Probe(IsInInstance), ns.Probe(GetInstanceInfo)
    local entry, decision = ns.MapRegistry:GetVerified(ns.Field(instance.values, 8), ns.Field(build.values, 1), ns.Field(build.values, 2))
    if inside.status ~= "ok" or inside.values[1] ~= true or ns.Field(instance.values, 8) ~= 389 or not entry then
        self:Close()
        ns.Print("RFC composite requires InstanceID 389 and a known accepted entry; reason=" .. ns.Text(decision.compatibilityReason))
        return
    end
    if ns.InCombat() then ns.Print("Run the composite command outside combat."); return end
    local layout, reason = self:BuildLayout(mode or "normal")
    if not layout then ns.Print(reason); return end
    if ns.Diagnostics then ns.Diagnostics:ClearTileProbe() end
    self:Create()
    self.layout, self.context = layout, { instanceID = 389 }
    self.frame:Show()
    self.frame:Raise()
    self:Render()
    ns.Print("Composite build=" .. ns.Text(decision.currentBuild) .. " verifiedBuild=" .. ns.Text(decision.verifiedBuild)
        .. " compatibility=" .. ns.Text(decision.compatibility))
    ns.Print(string.format("RFC experimental composite: %s, rho=2, 12/12 raster matches, %.9fx%.9f px; 19 numeric textures.",
        layout.mode, layout.width, layout.height))
    if layout.mode == "canonical" then
        ns.Print("Canonical: logical 256x256 cells, per-tile Y inversion, bottom-left native content, ascending MOGI min-Z; UVs unchanged.")
    else
        ns.Print("Legacy trial: global group-Y placement only; local tile Y and full UVs unchanged.")
    end
end
