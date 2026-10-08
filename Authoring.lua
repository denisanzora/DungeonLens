local _, ns = ...
local Authoring = {}
ns.Authoring = Authoring

-- Development tool: click the DungeonLens map to record normalized X/Y. Points are
-- kept in SavedVariables (DungeonLensDB.authoring[instanceID]) and echoed to chat as a
-- paste-ready MarkerData.lua line. They are tagged with the live layout signature;
-- if the map layout changes, stale points are discarded rather than mis-drawn.
local HELP = {
    "/dlmap author on|off      - toggle click capture on the map (opens the window)",
    "/dlmap author boss <name> - the next click records a boss with that name",
    "/dlmap author entrance    - the next click records the entrance",
    "/dlmap author list|export - print recorded points as MarkerData.lua lines",
    "/dlmap author undo|clear  - remove the last point / all points for this dungeon",
    "Plain clicks (no pending boss/entrance) record 'Point N'.",
}

-- Points live in ns.db.authoring[instanceID][layoutSignature]; every floor has its own signature,
-- so points can never leak between floors or survive a layout change.
local function Store()
    local state = ns.Window and ns.Window.lastState
    local id = state and state.instanceID
    if not id or not ns.db then return nil end
    ns.db.authoring = ns.db.authoring or {}
    local overlay = ns.Window.renderer and ns.Window.renderer.overlay
    local signature = overlay and overlay.signature
    if not signature then return nil end
    ns.db.authoring[id] = ns.db.authoring[id] or {}
    local store = ns.db.authoring[id][signature]
    if not store then
        store = { items = {} }
        ns.db.authoring[id][signature] = store
    end
    return store, id, signature
end

local function Line(point, index)
    local kind = point.kind == "entrance" and "entrance = { " or "{ id = " .. index .. ", "
    return string.format("%sname = %q, floor = %d, x = %.4f, y = %.4f }%s", kind, point.name or ("Point " .. index),
        point.floor or 1, point.x, point.y, point.kind == "entrance" and "," or ",")
end

function Authoring:EnsureCatcher()
    local renderer = ns.Window and ns.Window.renderer
    if not renderer or self.catcher then return self.catcher end
    local catcher = CreateFrame("Frame", nil, renderer.canvas)
    catcher:SetAllPoints(renderer.canvas)
    catcher:SetFrameLevel(renderer.canvas:GetFrameLevel() + 5) -- below markers so they keep tooltips
    catcher:EnableMouse(false)
    catcher:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then self:Click() end
    end)
    self.catcher = catcher
    return catcher
end

function Authoring:Click()
    local overlay = ns.Window and ns.Window.renderer and ns.Window.renderer.overlay
    local x, y
    if overlay then x, y = overlay:CursorToNormalized() end
    local store, id, signature = Store()
    if not x or not store then ns.Print("Click ignored: no map under the cursor."); return end
    local pending = self.pending or {}
    self.pending = nil
    local point = { x = x, y = y, floor = overlay.floor or 1, kind = pending.kind or "boss" }
    point.name = pending.name or (point.kind == "entrance" and "Entrance" or ("Point " .. (#store.items + 1)))
    if point.kind == "entrance" then
        for index = #store.items, 1, -1 do
            if store.items[index].kind == "entrance" then table.remove(store.items, index) end
        end
    end
    store.items[#store.items + 1] = point
    overlay:Refresh()
    ns.Print(string.format("Instance %d  floor %d  layout %s  x=%.4f y=%.4f", id, overlay.floor or 1, signature, x, y))
    ns.Print("  " .. Line(point, #store.items))
end

function Authoring:SetEnabled(enabled)
    if enabled and ns.Window then ns.Window:Open(true) end -- keep the current view (author needs a map open)
    local catcher = self:EnsureCatcher()
    if not catcher then ns.Print("Open the map window first (/dlmap) inside a supported dungeon."); return end
    catcher:EnableMouse(enabled)
    self.enabled = enabled
    ns.Print("Authoring click capture " .. (enabled and "ON: click the map to record normalized X/Y." or "OFF."))
    if enabled then
        local _, id, signature = Store()
        if id then ns.Print("Instance " .. id .. " layout signature: " .. signature) end
    end
end

function Authoring:Command(argument)
    argument = argument or ""
    local verb, rest = argument:match("^(%S*)%s*(.-)$")
    verb = verb:lower() -- the argument keeps its case so boss names are not mangled
    if verb == "on" then self:SetEnabled(true)
    elseif verb == "off" then self:SetEnabled(false)
    elseif verb == "boss" then
        self.pending = { kind = "boss", name = rest ~= "" and rest or nil }
        ns.Print("Next click records boss: " .. (rest ~= "" and rest or "(unnamed)"))
    elseif verb == "entrance" then
        self.pending = { kind = "entrance", name = rest ~= "" and rest or "Entrance" }
        ns.Print("Next click records the entrance.")
    elseif verb == "list" or verb == "export" then
        local store, id, signature = Store()
        if not store or #store.items == 0 then ns.Print("No authoring points for this dungeon."); return end
        ns.Print(string.format("[%d] floor %d, layout = %q  (%d points)", id, ns.Window.renderer.overlay.floor or 1, signature, #store.items))
        for index, point in ipairs(store.items) do ns.Print("  " .. Line(point, index)) end
    elseif verb == "undo" then
        local store = Store()
        if store and #store.items > 0 then
            table.remove(store.items)
            ns.Window.renderer.overlay:Refresh()
            ns.Print("Removed the last authoring point.")
        end
    elseif verb == "clear" then
        local store = Store()
        if store then store.items = {}; ns.Window.renderer.overlay:Refresh(); ns.Print("Cleared authoring points.") end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end
