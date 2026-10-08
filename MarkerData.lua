local _, ns = ...
local Markers = {}
ns.MapMarkers = Markers

-- Boss / entrance facts, keyed by InstanceID, in NORMALIZED map space: (0,0) is the top-left of the
-- rendered canvas of ONE floor, (1,1) its bottom-right. Two layers merge here:
--   ns.GeneratedBosses (BossData.lua)  - produced offline with full provenance (scripts/BOSS-PROVENANCE.md)
--   `handwritten` below                - verified in-game with /dlmap author (status "verified-client");
--                                        replaces the generated record for a boss with the same id.
-- A point is drawn only if the entry's layout signature for that floor equals the live layout's
-- signature (WMOComposition:Signature), so a changed map can never mis-place a marker.
--
-- Statuses: verified-client | verified-source-registration | approximate | unresolved (no x/y).
-- Normal play draws verified-* only; `approximate` needs /dlmap approximate on.
--
-- Schema (handwritten entries):
--   [instanceID] = {
--       layouts = { [1] = "wmo:1088x964:19" },          -- signature per floor (printed by /dlmap author)
--       source = "in-game authoring, <who>, <date>", verifiedBuild = "1.60.1.70245",
--       entrance = { name = "Entrance", floor = 1, x = 0.5, y = 0.9, status = "verified-client" },
--       bosses = { { id = 1, name = "…", floor = 1, x = 0.4123, y = 0.2231, status = "verified-client" } },
--   }
local handwritten = {
}

local VISIBLE = { ["verified-client"] = true, ["verified-source-registration"] = true }

function Markers:Get(instanceID)
    if not ns.IsID(instanceID) then return nil end
    local generated, manual = ns.GeneratedBosses and ns.GeneratedBosses[instanceID], handwritten[instanceID]
    if not manual then return generated end
    if not generated then return manual end
    local merged = { layouts = {}, bosses = {}, entrance = manual.entrance or generated.entrance, source = manual.source,
        verifiedBuild = manual.verifiedBuild, identity = generated.identity }
    for floor, signature in pairs(generated.layouts or {}) do merged.layouts[floor] = signature end
    for floor, signature in pairs(manual.layouts or {}) do merged.layouts[floor] = signature end
    local overridden = {}
    for _, boss in ipairs(manual.bosses or {}) do overridden[boss.id] = true; merged.bosses[#merged.bosses + 1] = boss end
    for _, boss in ipairs(generated.bosses or {}) do
        if not overridden[boss.id] then merged.bosses[#merged.bosses + 1] = boss end
    end
    return merged
end

function Markers:ValidPoint(point)
    return type(point) == "table" and ns.IsNumber(point.x) and ns.IsNumber(point.y)
        and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1
end

function Markers:ShowApproximate()
    if ns.db and type(ns.db.approximate) == "boolean" then return ns.db.approximate end
    return false -- approximate pins are shown only after /dlmap approximate on
end

-- Whether a boss/entrance record may be drawn right now (status gate).
function Markers:Visible(record)
    if not self:ValidPoint(record) then return false end
    if VISIBLE[record.status or "verified-client"] then return true end
    return record.status == "approximate" and self:ShowApproximate()
end

-- Counts for the window footer: { placed = n, hidden = n (approximate in normal mode), unplaced = n, names = {…} }.
function Markers:Summary(instanceID)
    local data, summary = self:Get(instanceID), { placed = 0, hidden = 0, unplaced = 0, unplacedNames = {}, total = 0 }
    for _, boss in ipairs(data and data.bosses or {}) do
        summary.total = summary.total + 1
        if boss.status == "unresolved" or not self:ValidPoint(boss) then
            summary.unplaced = summary.unplaced + 1
            summary.unplacedNames[#summary.unplacedNames + 1] = boss.name
        elseif self:Visible(boss) then summary.placed = summary.placed + 1
        else summary.hidden = summary.hidden + 1 end
    end
    return summary
end

-- Returns the list of problems with an instance's marker data (empty = valid).
function Markers:Validate(instanceID)
    local entry, problems = self:Get(instanceID), {}
    if not entry then return { "no marker data" } end
    if type(entry.layouts) ~= "table" then problems[#problems + 1] = "missing layout signatures" end
    if entry.entrance and not self:ValidPoint(entry.entrance) then problems[#problems + 1] = "invalid entrance" end
    for index, boss in ipairs(entry.bosses or {}) do
        if type(boss.name) ~= "string" then problems[#problems + 1] = "boss #" .. index .. " has no name" end
        if boss.status ~= "unresolved" then
            if not self:ValidPoint(boss) then problems[#problems + 1] = "invalid boss #" .. index end
            if type(boss.floor) ~= "number" or not (entry.layouts and entry.layouts[boss.floor]) then
                problems[#problems + 1] = "boss #" .. index .. " floor has no layout signature"
            end
        end
    end
    return problems
end
