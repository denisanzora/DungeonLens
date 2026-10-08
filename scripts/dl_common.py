"""Shared rules for the DungeonLens offline tooling (single source of truth for floors)."""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
FOREVER_BUILD = "1.60.1.70245"
MIN_DIRECT_FLOOR_COVERAGE = 90.0  # percent of tiled groups Blizzard's UiMapAssignment must place directly


def load(path):
    with open(os.path.join(GEN, path), encoding="utf-8") as handle:
        return json.load(handle)


def main_wmo(discovery):
    wmos = [w for w in discovery["wmos"] if any(g["tiles"] for g in w["groups"])]
    return max(wmos, key=lambda w: sum(len(g["tiles"]) for g in w["groups"])) if wmos else None


def chosen_floors(floors_info, wmo_groups):
    """Floors for a single-WMO map: Blizzard's when >1 and >=90% of groups matched directly,
    otherwise one floor holding every tiled group. wmo_groups: {index: group}."""
    retail = floors_info.get("floors") or []
    if len(retail) > 1 and floors_info.get("directCoveragePercent", 0) >= MIN_DIRECT_FLOOR_COVERAGE:
        return [{"floor": f["floor"], "uiMapID": f["uiMapID"], "source": "blizzard-retail-uimap-assignment",
                 "groups": sorted(set(f["matchedGroups"] + f["inferredGroups"]))} for f in retail]
    return [{"floor": 1, "uiMapID": retail[0]["uiMapID"] if len(retail) == 1 else None, "source": "single-floor",
             "groups": sorted(wmo_groups)}]


def lua_report():
    """Run the REAL addon Lua (under Lua 5.1 via lupa) and return what it would draw:
    {"layouts": [...], "bosses": {id: [...]}, "entries": {id: {...}}}."""
    from lupa.lua51 import LuaRuntime
    root = os.path.dirname(HERE)
    lua = LuaRuntime(unpack_returned_tuples=True)
    toc = open(os.path.join(root, "DungeonLens.toc"), encoding="utf-8").read()
    files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
    lua.globals().AddonFiles = lua.table_from(files)
    lua.globals().AddonSources = lua.table_from({n: open(os.path.join(root, n), encoding="utf-8").read() for n in files})
    lua.globals().LayoutSmokeSource = open(os.path.join(HERE, "LayoutSmoke.lua"), encoding="utf-8").read()
    lua.globals().ValidationFocus = "layout"
    lua.execute(open(os.path.join(HERE, "Smoke.lua"), encoding="utf-8").read())
    g = lua.globals()

    def plain(value):
        if hasattr(value, "items"):
            keys = list(value.keys())
            if keys and all(isinstance(k, (int, float)) for k in keys):
                return [plain(value[k]) for k in sorted(keys)]
            return {k: plain(v) for k, v in value.items()}
        return value

    return {"layouts": plain(g.LayoutReport), "bosses": {int(k): plain(v) for k, v in g.BossReport.items()},
            "entries": {int(k): plain(v) for k, v in g.EntryReport.items()}}


def manifest_item(map_id):
    with open(os.path.join(HERE, "registry-manifest.json"), encoding="utf-8") as handle:
        return next((e for e in json.load(handle)["entries"] if e["instanceID"] == map_id), None)


def build_floors(map_id, discovery, floors_info):
    """Floors/pages exactly as the registry generator emits them. Each floor carries its own WMO
    (`wmo`) and raw MOGI group indexes (`groups`): a single WMO split into Blizzard floors, or
    several WMOs as pages (e.g. Scarlet Monastery wings)."""
    item = manifest_item(map_id)
    if item and item["source"] == "wmo-pages":
        floors = []
        for k, root_id in enumerate(item["wmoRoots"]):
            wmo = next(w for w in discovery["wmos"] if w["rootFileDataID"] == root_id)
            floors.append({"floor": k + 1, "uiMapID": None, "source": "wmo-page", "wmo": wmo,
                           "groups": sorted(g["index"] for g in wmo["groups"] if g["tiles"])})
        return floors
    if item and item.get("wmoRoot"):
        wmo = next(w for w in discovery["wmos"] if w["rootFileDataID"] == item["wmoRoot"])
    else:
        wmo = main_wmo(discovery)
    groups = {g["index"]: g for g in wmo["groups"] if g["tiles"]}
    floors = chosen_floors(floors_info, groups)
    for f in floors:
        f["wmo"] = wmo
    return floors


def frame_for(wmo):
    """((origin_x, origin_y), yaw_degrees, z_offset) of a WMO in the instance world frame.
    ADT placement (file x, y(up), z) -> world origin (17066.666 - z, 17066.666 - x); global WMOs sit at the origin.
    Proven by Fit-Frames.py: local = Rot(180 - yaw) * (world - origin) puts 100% of spawns on painted pixels."""
    placements = wmo.get("placements")
    if placements:
        p = placements[0]
        return (17066.666 - p["position"][2], 17066.666 - p["position"][0]), p["rotation"][1], p["position"][1]
    return (0.0, 0.0), 0.0, 0.0
