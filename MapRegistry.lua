local _, ns = ...
local Registry = {}
ns.MapRegistry = Registry

-- Static, code-owned metadata: no setters and no SavedVariables copies.
-- Consumers build derived layouts; they never edit these measured facts.
-- IDs are independent namespaces. No UiMapID or texture pathname is inferred.
-- Tile tuples: FileDataID, localX, localY, nativeWidth, nativeHeight;
-- the containing record identifies each tile's WMO group ordinal.
local maps = {
    [389] = {
        instanceID = 389, worldMapID = 389, displayName = "Ragefire Chasm",
        sourceType = "blizzard-wmo-minimap", verifiedVersion = "1.60.1", verifiedBuild = "70124",
        verifiedInterface = 16001,
        verified = true, rho = 2, logicalBlockWidth = 256, logicalBlockHeight = 256,
        tileCount = 19,
        provenance = {
            buildConfig = "dd3dfc2881c407299f46c2aaf34c130b",
            rootFileDataID = 109483, rootMD5 = "18c9698976d1d0935ceb10f1f42674dd",
            wdtFileDataID = 789981, wdtMD5 = "9a430840a3bfbce513ff5a529b0de3b2",
            evidence = "scripts/RFC-WMO-70124.json",
            transform = "canonical", acceptance = "User accepted the in-game canonical composite screenshot on build 70124",
        },
        groups = {
            { index = 0, minimum = { 66.59652709960938, 4.691049098968506, -43.970794677734375 },
                maximum = { 131.3125762939453, 64.364501953125, 15.422064781188965 }, tiles = { { 213056, 0, 0, 256, 128 } } },
            { index = 1, minimum = { 131.2570343017578, -49.16991424560547, -66.19143676757812 },
                maximum = { 317.36114501953125, 108.50059509277344, 8.461996078491211 },
                tiles = { { 213057, 0, 0, 256, 256 }, { 213058, 0, 1, 256, 256 },
                    { 213059, 1, 0, 256, 256 }, { 213060, 1, 1, 256, 256 } } },
            { index = 2, minimum = { 63.38911056518555, -106.85586547851562, -24.365713119506836 },
                maximum = { 166.05641174316406, 7.274646282196045, 17.7731990814209 }, tiles = { { 213061, 0, 0, 256, 256 } } },
            { index = 3, minimum = { 313.2587585449219, -275.3790588378906, -22.692407608032227 },
                maximum = { 416.2859802246094, -126.5262451171875, 32.18679428100586 },
                tiles = { { 213062, 0, 0, 256, 256 }, { 213063, 0, 1, 256, 256 } } },
            { index = 4, minimum = { 161.4136199951172, -266.0632019042969, -39.81938552856445 },
                maximum = { 323.4056396484375, -43.01485824584961, 27.14217758178711 },
                tiles = { { 213064, 0, 0, 256, 256 }, { 213065, 0, 1, 256, 256 },
                    { 213066, 1, 0, 256, 256 }, { 213067, 1, 1, 256, 256 } } },
            { index = 5, minimum = { -88.76231384277344, -62.86724853515625, -12.85830307006836 },
                maximum = { 20.272533416748047, 4.349178791046143, 58.909786224365234 }, tiles = { { 213068, 0, 0, 256, 256 } } },
            { index = 6, minimum = { -63.03799057006836, -188.24867248535156, 26.591840744018555 },
                maximum = { -20.569921493530273, -161.1537322998047, 59.433555603027344 }, tiles = { { 213069, 0, 0, 128, 64 } } },
            { index = 7, minimum = { -26.122661590576172, -186.25442504882812, 21.749601364135742 },
                maximum = { -5.730564117431641, -154.52366638183594, 44.537696838378906 }, tiles = { { 213070, 0, 0, 64, 64 } } },
            { index = 8, minimum = { -97.46189880371094, -159.75418090820312, 3.2021238803863525 },
                maximum = { 12.01396656036377, -108.50076293945312, 56.48995590209961 }, tiles = { { 213071, 0, 0, 256, 128 } } },
            { index = 9, minimum = { -102.9556655883789, -83.68533325195312, -10.798360824584961 },
                maximum = { 21.38006019592285, -55.48188018798828, 57.29317855834961 }, tiles = { { 213072, 0, 0, 256, 64 } } },
            { index = 10, minimum = { -99.32574462890625, -116.60514831542969, -7.869863510131836 },
                maximum = { 16.067955017089844, -82.64429473876953, 52.620765686035156 }, tiles = { { 213073, 0, 0, 256, 128 } } },
            { index = 11, minimum = { -16.71394920349121, -7.885947227478027, -24.95615577697754 },
                maximum = { 67.56114196777344, 78.93363952636719, 17.044885635375977 }, tiles = { { 213074, 0, 0, 256, 256 } } },
        },
    },
}

-- Generated candidate entries (MapData.lua) are merged without ever replacing a
-- hand-verified entry: RFC 389 above is authoritative and untouched.
for instanceID, entry in pairs(ns.GeneratedMaps or {}) do
    if maps[instanceID] == nil then maps[instanceID] = entry end
end

function Registry:Get(instanceID)
    if ns.IsID(instanceID) then return maps[instanceID] end
end

local function BuildNumber(value)
    if not ns.IsReadable(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if ns.IsNumber(value) then return value end
end

function Registry:Compatibility(entry, version, build)
    if not entry then return "unavailable", false, "registry-entry-not-found" end
    local candidate = false
    if not entry.verified then
        -- Generated candidates have complete discovered metadata but no accepted in-game screenshot yet.
        if not (ns.CandidatesEnabled and ns.CandidatesEnabled()) then
            return "incompatible", false, "registry-transform-not-verified"
        end
        candidate = true
    end
    if entry.sourceType ~= "blizzard-wmo-minimap" and entry.sourceType ~= "blizzard-ground-minimap" then
        return "incompatible", false, "registry-source-not-supported"
    end
    if candidate then return "candidate-unverified", true, "candidate-pending-visual-verification" end
    -- A verification build is evidence, not a version allowlist. The client
    -- tries known numeric IDs on other builds and reports actual load failures.
    if version == entry.verifiedVersion and BuildNumber(build) == BuildNumber(entry.verifiedBuild) then
        return "verified", true, "verification-build-match"
    end
    local current, verified = BuildNumber(build), BuildNumber(entry.verifiedBuild)
    if current and verified and current > verified then return "newer-unverified", true, "known-map-on-newer-build" end
    if current and verified and current < verified then return "older-unverified", true, "known-map-on-older-build" end
    return "unverified-current-build", true, "known-map-build-provenance-differs-or-unavailable"
end

function Registry:GetVerified(instanceID, version, build)
    local entry = self:Get(instanceID)
    local compatibility, allowed, reason = self:Compatibility(entry, version, build)
    local decision = {
        lookupKey = instanceID, registryEntry = entry, registryFound = entry ~= nil,
        sourceType = entry and entry.sourceType, verifiedVersion = entry and entry.verifiedVersion,
        verifiedBuild = entry and entry.verifiedBuild, currentVersion = version, currentBuild = build,
        compatibility = compatibility, buildCompatible = allowed, compatibilityReason = reason,
        fallbackSelected = false,
    }
    return allowed and entry or nil, decision
end

-- All registered dungeons, sorted by name (for the browser, /dlmap list and /dlmap show).
function Registry:List()
    local list = {}
    for instanceID, entry in pairs(maps) do
        list[#list + 1] = { instanceID = instanceID, name = entry.displayName, entry = entry, verified = entry.verified == true }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Resolve "389", "ragefire", or "Ragefire Chasm" to registry rows: exact name/ID first, then prefix, then substring.
function Registry:Find(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1")
    if text == "" then return {} end
    local id = tonumber(text)
    if id and maps[id] then return { { instanceID = id, name = maps[id].displayName, entry = maps[id], verified = maps[id].verified == true } } end
    local exact, prefix, contains = {}, {}, {}
    for _, row in ipairs(self:List()) do
        local name = row.name:lower()
        if name == text then exact[#exact + 1] = row
        elseif name:sub(1, #text) == text then prefix[#prefix + 1] = row
        elseif name:find(text, 1, true) then contains[#contains + 1] = row end
    end
    if #exact > 0 then return exact end
    if #prefix > 0 then return prefix end
    return contains
end

function Registry:MaxTileCount()
    local count = 0
    for _, entry in pairs(maps) do count = math.max(count, entry.tileCount) end
    return count
end
