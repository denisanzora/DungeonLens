-- Focused regression: a beta build change must not reject accepted RFC data.
local ns, fixture, methods, frames, messages = ...
fixture.instanceID, fixture.mapID, fixture.inside, fixture.kind, fixture.build = 389, nil, true, "party", "70124"
function GetBuildInfo() return "1.60.1", fixture.build, "test", 16001 end
function GetInstanceInfo() return fixture.instanceID == 389 and "Ragefire Chasm" or "Unknown instance", fixture.kind, 1, "Normal", 5, 0, nil, fixture.instanceID end
local getInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id) assert(id ~= 389, "InstanceID sent to UiMap API"); return getInfo(id) end
C_Map.GetPlayerMapPosition = function() error("No new player-position feature") end
local function Refresh() ns.Refresh("resolver-regression") end
local function Contains(text, start)
    for index = start or 1, #messages do if messages[index]:find(text, 1, true) then return true end end
    return false
end
local entry = assert(ns.MapRegistry:Get(389))
assert(entry.verifiedBuild == "70124" and entry.verifiedVersion == "1.60.1")
Refresh()
assert(ns.state.renderSource == "blizzard-wmo-minimap" and ns.state.resolution.compatibility == "verified")
assert(ns.state.resolution.registryFound and ns.state.resolution.lookupKey == 389)
fixture.build = "70170"
Refresh()
local decision = ns.state.resolution
assert(decision.registryEntry == entry and decision.registryFound and decision.sourceType == "blizzard-wmo-minimap")
assert(decision.verifiedBuild == "70124" and decision.currentBuild == "70170")
assert(decision.compatibility == "newer-unverified" and decision.buildCompatible and decision.fallbackSelected)
assert(decision.rendererSelected == "blizzard-wmo-minimap")
assert(ns.state.mapEntry == entry and ns.state.mapID == nil and ns.state.uiMapID == nil)
local canonical = ns.state.composition
assert(canonical == ns.Composite:BuildLayout("canonical"))
local debugStart = #messages + 1
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("GetBuildInfo: version=1.60.1 build=70170", debugStart))
assert(Contains("Registry entry: found source=blizzard-wmo-minimap", debugStart))
assert(Contains("Compatibility: newer-unverified allowed=true", debugStart))
assert(Contains("Renderer selected: WMO minimap fallbackSelected=true", debugStart))
assert(Contains("Renderer attempt: not attempted", debugStart))
SlashCmdList.DUNGEONLENS("show 389")
assert(ns.Window.renderer.composition == canonical and not ns.Window.message:IsShown())
assert(ns.state.resolution.renderAttempted and ns.state.resolution.renderSucceeded)
debugStart = #messages + 1
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("Renderer attempt: true accepted=true", debugStart))

-- No growing build allowlist: arbitrary later and older builds remain attempts.
for _, build in ipairs({ "99999", "70009" }) do
    fixture.build = build
    Refresh()
    assert(ns.state.mapEntry == entry and ns.state.renderSource == "blizzard-wmo-minimap")
end
fixture.build = "70170"
fixture.mapID = 101
Refresh()
assert(ns.state.renderSource == "native-uimap" and ns.state.resolution.registryFound)
assert(not ns.state.resolution.fallbackSelected and ns.state.resolution.selectionReason == "native-dungeon-uimap-priority")
fixture.mapID, fixture.instanceID = nil, 42
Refresh()
assert(ns.state.renderSource == "none" and not ns.state.resolution.registryFound)
assert(ns.state.resolution.selectionReason == "registry-entry-not-found")
debugStart = #messages + 1
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("lookupKey=42", debugStart) and Contains("reason=registry-entry-not-found", debugStart))
fixture.instanceID = 389
Refresh()
local count = #frames
SlashCmdList.DUNGEONLENS("scan composite canonical")
assert(ns.Composite.frame:IsShown() and ns.Composite.layout == canonical)
for index, tile in ipairs(canonical.tiles) do
    local texture = ns.Composite.textures[index]
    assert(texture.textureID == tile.fileDataID and type(tile.fileDataID) == "number")
    assert(texture.uv[1] == 0 and texture.uv[2] == 1 and texture.uv[3] == 0 and texture.uv[4] == 1)
end
assert(#frames > count)
assert(Contains("Composite build=70170 verifiedBuild=70124 compatibility=newer-unverified"))
-- Concrete metadata rejection is allowed; numerical build differences are not.
ns.db.candidates = false
local status, allowed, reason = ns.MapRegistry:Compatibility({ verified = false }, "1.60.1", "70170")
assert(status == "incompatible" and not allowed and reason == "registry-transform-not-verified")
status, allowed, reason = ns.MapRegistry:Compatibility({ verified = true, sourceType = "not-implemented" }, "1.60.1", "70170")
assert(status == "incompatible" and not allowed and reason == "registry-source-not-supported")

-- Generated candidates: gated by /dlmap candidates, never conflated with verified entries.
status, allowed, reason = ns.MapRegistry:Compatibility({ verified = false, sourceType = "blizzard-ground-minimap" }, "1.60.1", "70245")
assert(status == "incompatible" and not allowed)
ns.db.candidates = true
status, allowed, reason = ns.MapRegistry:Compatibility({ verified = false, sourceType = "blizzard-ground-minimap" }, "1.60.1", "70245")
assert(status == "candidate-unverified" and allowed and reason == "candidate-pending-visual-verification")
status, allowed, reason = ns.MapRegistry:Compatibility({ verified = false, sourceType = "other" }, "1.60.1", "70245")
assert(status == "incompatible" and not allowed and reason == "registry-source-not-supported")
ns.db.candidates = nil
assert(ns.MapRegistry:Get(389).verified and ns.MapRegistry:Get(389).provenance.rootFileDataID == 109483) -- hand entry wins
assert(ns.MapRegistry:Get(90) and not ns.MapRegistry:Get(90).verified)

-- Actual SetTexture refusal is exposed separately from the resolver selection.
SlashCmdList.DUNGEONLENS("close")
local setTexture = methods.SetTexture
function methods:SetTexture(id)
    if id == 213069 then return false end
    return setTexture(self, id)
end
SlashCmdList.DUNGEONLENS("show 389")
assert(ns.state.resolution.fallbackSelected and ns.state.resolution.renderAttempted and not ns.state.resolution.renderSucceeded)
assert(ns.state.resolution.renderReason:find("FileDataID=213069 status=returned-false", 1, true))
debugStart = #messages + 1
SlashCmdList.DUNGEONLENS("debug")
assert(Contains("Renderer selected: WMO minimap fallbackSelected=true", debugStart))
assert(Contains("FileDataID=213069 status=returned-false", debugStart))
methods.SetTexture = setTexture
for _, object in ipairs(frames) do assert(object.scripts.OnUpdate == nil) end
assert(entry.verifiedBuild == "70124")
print("PASS: matching/newer/other build fallback attempts, unchanged verification provenance, native priority, unknown-instance rejection, runtime-style debug decisions, unchanged canonical geometry/IDs and precise texture-refusal diagnostics.")
