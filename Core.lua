local addonName, ns = ...

ns.name = addonName
ns.version = "0.2.0"
ns.development = true

-- Forever belongs to the Mainline API family. Do not inspect or calculate
-- with restricted values if the current client exposes secret-value checks.
function ns.IsReadable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

function ns.IsNumber(value)
    return ns.IsReadable(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

function ns.IsID(value)
    return ns.IsNumber(value) and value > 0 and value == math.floor(value)
end

function ns.Field(object, key)
    if not ns.IsReadable(object) then return nil end
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok and ns.IsReadable(value) then return value end
end

function ns.Text(value)
    if not ns.IsReadable(value) then return "<restricted>" end
    if value == nil then return "nil" end
    if type(value) == "string" then return (value:gsub("|", "||")) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    return "<" .. type(value) .. ">"
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

-- Keep API availability/errors visible in diagnostics without emitting Lua
-- errors during normal operation. Preserve nil holes in multi-return APIs.
function ns.Probe(func, ...)
    if type(func) ~= "function" then return { status = "unavailable", values = {} } end
    local results = Pack(pcall(func, ...))
    if not results[1] then return { status = "error", values = {} } end
    local values = { n = results.n - 1 }
    for index = 2, results.n do values[index - 1] = results[index] end
    local status = "ok"
    if not ns.IsReadable(values[1]) then
        status = "restricted"
    elseif values[1] == nil then
        status = "nil"
    end
    return { status = status, values = values }
end

function ns.MapProbe(method, ...)
    return ns.Probe(ns.Field(C_Map, method), ...)
end

-- Unverified generated map entries are shown only while explicitly enabled
-- (default: shown). /dlmap candidates on|off overrides.
function ns.CandidatesEnabled()
    if ns.db and type(ns.db.candidates) == "boolean" then return ns.db.candidates end
    return true -- generated maps are browsable by default; /dlmap candidates off hides unverified ones
end

function ns.Print(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c7ffDungeonLens:|r " .. message)
    elseif type(print) == "function" then
        print("DungeonLens: " .. message)
    end
end

function ns.InCombat()
    local probe = ns.Probe(InCombatLockdown)
    -- If combat status is unavailable, conservatively disable dragging.
    return probe.status ~= "ok" or probe.values[1] ~= false
end

local events = CreateFrame("Frame")
ns.events = events
ns.registeredEvents = {}

function ns.RegisterEvent(event)
    local ok = pcall(events.RegisterEvent, events, event)
    ns.registeredEvents[event] = ok
end

-- /dlmap list: every registered dungeon with status, floors and boss counts.
function ns.ListDungeons()
    ns.Print("Registered dungeons (* = candidate map, not yet visually verified):")
    for _, row in ipairs(ns.MapRegistry:List()) do
        local summary = ns.MapMarkers:Summary(row.instanceID)
        local floors = ns.WMOComposition:FloorCount(row.entry)
        ns.Print(string.format("  %d  %s%s  [%s]  floors=%d  bosses shown=%d/%d", row.instanceID, row.name, row.verified and "" or " *",
            row.entry.sourceType == "blizzard-ground-minimap" and "ground" or "wmo", floors, summary.placed, summary.total))
    end
    for instanceID, info in pairs(ns.UnavailableMaps or {}) do
        ns.Print(string.format("  %d  %s  - not generated yet (%s)", instanceID, info.name, info.reason))
    end
    ns.Print("Open one from anywhere: /dlmap show <id or name>, e.g. /dlmap show 389 or /dlmap show \"Stormwind Stockade\".")
end

function ns.ShowDungeon(text)
    local matches = ns.MapRegistry:Find(text)
    if #matches == 0 then
        local query = (text or ""):lower()
        for instanceID, info in pairs(ns.UnavailableMaps or {}) do
            if tostring(instanceID) == query or info.name:lower():find(query, 1, true) then
                ns.Print(info.name .. " (" .. instanceID .. ") has no generated map yet: " .. info.reason)
                return
            end
        end
        ns.Print("No registered dungeon matches '" .. (text or "") .. "'. Try /dlmap list.")
    elseif #matches > 1 then
        ns.Print("Several dungeons match; be more specific:")
        for _, row in ipairs(matches) do ns.Print("  " .. row.instanceID .. "  " .. row.name) end
    elseif ns.Window then
        ns.Window:Preview(matches[1].instanceID)
    end
end

function ns.SetFloorCommand(argument)
    if not ns.Window or not ns.Window.frame then ns.Print("Open a map first."); return end
    local current = ns.Window.floor or 1
    if argument == "next" or argument == "down" then ns.Window:SetFloor(current + 1)
    elseif argument == "prev" or argument == "up" then ns.Window:SetFloor(current - 1)
    elseif tonumber(argument) then ns.Window:SetFloor(tonumber(argument))
    else ns.Print("Usage: /dlmap floor <number|next|prev>") end
    ns.Print("Floor " .. (ns.Window.floor or 1) .. "/" .. ns.WMOComposition:FloorCount(ns.Window.lastState and ns.Window.lastState.mapEntry))
end

function ns.Refresh(reason)
    if not ns.db or not ns.Detector then return end
    ns.state = ns.Detector:Detect(reason)
    if ns.Window and ns.Window.frame and ns.Window.frame:IsShown() then
        ns.Window:Update(ns.state)
    end
end

events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        if type(DungeonLensDB) ~= "table" then DungeonLensDB = {} end
        ns.db = DungeonLensDB
        if type(ns.db.window) ~= "table" then ns.db.window = {} end
        if ns.MinimapButton then ns.MinimapButton:Init() end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGOUT" then
        if ns.Window then ns.Window:Save() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.Window then ns.Window:StopInteraction() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.BossPanel then ns.BossPanel:OnItemInfo(...) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.Window and ns.Window.pendingOpen then ns.Window:Open() end
    else
        if ns.Diagnostics then ns.Diagnostics:HideStaleTileProbe() end
        ns.Refresh(event)
        if event == "PLAYER_ENTERING_WORLD" and ns.Window then ns.Window:RestoreVisibility() end
        if event == "PLAYER_ENTERING_WORLD" and ns.PlayerPosition then ns.PlayerPosition:Restore() end
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "PLAYER_MAP_CHANGED", "NEW_WMO_CHUNK", "PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }) do
    ns.RegisterEvent(event)
end

SLASH_DUNGEONLENS1 = "/dlmap"
SlashCmdList.DUNGEONLENS = function(input)
    local raw = (input or ""):match("^%s*(.-)%s*$")
    local command = raw:lower()
    if command == "debug" then
        if ns.Diagnostics then ns.Diagnostics:Report() end
        if ns.Window then ns.Window:DebugReport() end
    elseif command == "scan" then
        if ns.Diagnostics then ns.Diagnostics:Scan() end
    elseif command == "scan tiles" then
        if ns.Diagnostics then ns.Diagnostics:ProbeTiles() end
    elseif command == "scan composite" then
        if ns.Composite then ns.Composite:Open("normal") end
    elseif command == "scan composite flipy" then
        if ns.Composite then ns.Composite:Open("flipy") end
    elseif command == "scan composite canonical" then
        if ns.Composite then ns.Composite:Open("canonical") end
    elseif command == "scan stop" then
        if ns.Diagnostics then ns.Diagnostics:StopScan() end
    elseif command == "candidates on" or command == "candidates off" then
        if ns.db then ns.db.candidates = command == "candidates on" end
        ns.Print("Unverified candidate maps " .. (ns.CandidatesEnabled() and "enabled" or "disabled") .. ".")
        ns.Refresh("candidates")
    elseif command == "author" or command:match("^author ") then
        if ns.Authoring then ns.Authoring:Command(raw:match("^%a+%s*(.*)$")) end -- raw case keeps boss names
    elseif command == "player" or command:match("^player ") then
        if ns.PlayerPosition then ns.PlayerPosition:Command(command:match("^player%s*(.*)$")) end
    elseif command == "probe" or command == "probe position" then
        if ns.PositionProbe then ns.PositionProbe:Run() end
    elseif command == "list" then
        ns.ListDungeons()
    elseif command == "show" or command:match("^show ") then
        ns.ShowDungeon(raw:match("^%a+%s*(.*)$"))
    elseif command == "minimap" or command:match("^minimap ") then
        if ns.MinimapButton then ns.MinimapButton:Command(command:match("^minimap%s*(.*)$")) end
    elseif command == "lootexport" then
        if ns.SeenLoot then ns.SeenLoot:Export(); ns.SeenLoot:ExportPositions() end
    elseif command == "live" then
        if ns.Window then ns.Window:Live() end
    elseif command == "floor" or command:match("^floor ") then
        ns.SetFloorCommand(command:match("^floor%s*(.*)$"))
    elseif command == "approximate on" or command == "approximate off" then
        if ns.db then ns.db.approximate = command == "approximate on" end
        ns.Print("Approximate boss markers " .. (ns.MapMarkers:ShowApproximate() and "shown" or "hidden") .. ".")
        if ns.Window and ns.Window.frame and ns.Window.frame:IsShown() then ns.Window:Update(ns.state) end
    elseif command == "close" then
        if ns.Window then ns.Window:Close() end
    elseif command == "" then
        if ns.Window then
            ns.Window:Open()
        else
            ns.Print("Map window is not loaded yet; use /dlmap debug.")
        end
    else
        ns.Print("Commands: /dlmap, /dlmap minimap on|off|reset, /dlmap show <name|id>, /dlmap list, /dlmap floor <n>, /dlmap live, /dlmap debug, /dlmap close; developer: /dlmap lootexport, /dlmap candidates on|off, /dlmap approximate on|off, /dlmap author help, /dlmap probe, /dlmap scan, /dlmap scan tiles, /dlmap scan composite [flipy|canonical], /dlmap scan stop")
    end
end
