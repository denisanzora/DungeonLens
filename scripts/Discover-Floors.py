"""Derive dungeon floors from Blizzard data (no guessing).

Blizzard's retail UiMapAssignment table assigns WMO groups (by WMOAreaTable group ID, the value in
each group file's MOGP header) to dungeon-floor UiMaps. For dungeons whose WMOs are unchanged in
Forever, the same group IDs exist in the Forever WMO, so floor membership transfers exactly. Coverage
is reported; groups that retail does not list are attached to a floor only when unambiguous and are
marked `inferred`. Dungeons without retail floor data are left single-floor ("unverified").

    python scripts/Discover-Floors.py [mapID ...]
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
FOREVER_BUILD = "1.60.1.70245"
RETAIL_BUILD = "12.1.0.69933"  # pinned: Blizzard retail Encounter Journal / UiMap data (provenance)
MAPS = [389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70, 2998]


def overlap_xy(a, b):
    w = min(a["maximum"][0], b["maximum"][0]) - max(a["minimum"][0], b["minimum"][0])
    h = min(a["maximum"][1], b["maximum"][1]) - max(a["minimum"][1], b["minimum"][1])
    return max(w, 0) * max(h, 0)


def floors_for(retail, uimaps, assignments, report):
    map_id = report["mapID"]
    rows = [r for r in assignments if int(r["MapID"]) == map_id and uimaps.get(r["UiMapID"], {}).get("Type") == "4"]
    if not rows:
        return {"status": "no-retail-floor-data", "floors": []}
    members = {}
    regions = {}
    for r in rows:
        members.setdefault(r["UiMapID"], set())
        if int(r["WMOGroupID"]):
            members[r["UiMapID"]].add(int(r["WMOGroupID"]))
        regions[r["UiMapID"]] = [round(float(r["Region_%d" % i]), 3) for i in range(6)]
    wmo = max(report["wmos"], key=lambda w: sum(len(g["tiles"]) for g in w["groups"]))
    tiled = [g for g in wmo["groups"] if g["tiles"]]
    by_id = {}
    for g in tiled:
        by_id.setdefault(g.get("wmoGroupID"), []).append(g)
    floors = []
    assigned = {}
    for ui_map, ids in members.items():
        hit = [g for gid in ids for g in by_id.get(gid, [])]
        for g in hit:
            assigned.setdefault(g["index"], []).append(ui_map)
        floors.append({"uiMapID": int(ui_map), "name": uimaps[ui_map]["Name_lang"], "retailRegion": regions[ui_map],
                       "retailMemberCount": len(ids), "matchedGroups": sorted(g["index"] for g in hit),
                       "matchedInForever": len(hit), "inferredGroups": []})
    # whole-map assignments (no group list) mean the UiMap covers every group
    if len(floors) == 1 and not members[str(floors[0]["uiMapID"])]:
        floors[0]["matchedGroups"] = sorted(g["index"] for g in tiled)
        floors[0]["matchedInForever"] = len(tiled)
        assigned = {g["index"]: [str(floors[0]["uiMapID"])] for g in tiled}
    multi = sorted(i for i, v in assigned.items() if len(v) > 1)
    unassigned = sorted(g["index"] for g in tiled if g["index"] not in assigned)
    # unambiguous inference only: nearest assigned group by xy overlap, then by z gap
    index = {g["index"]: g for g in tiled}
    for gi in list(unassigned):
        best, best_key = None, None
        for f in floors:
            for other in f["matchedGroups"]:
                o = index[other]
                key = (-overlap_xy(index[gi], o), abs((index[gi]["minimum"][2] + index[gi]["maximum"][2]) / 2
                                                       - (o["minimum"][2] + o["maximum"][2]) / 2))
                if best_key is None or key < best_key:
                    best, best_key = f, key
        if best is not None and best_key[0] < 0:
            best["inferredGroups"].append(gi)
            unassigned.remove(gi)
    for f in floors:
        used = [index[i] for i in f["matchedGroups"] + f["inferredGroups"]]
        f["zMin"] = round(min((g["minimum"][2] for g in used), default=0), 2)
        f["zMax"] = round(max((g["maximum"][2] for g in used), default=0), 2)
        f["meanZ"] = round(sum((g["minimum"][2] + g["maximum"][2]) / 2 for g in used) / max(len(used), 1), 2)
    floors.sort(key=lambda f: -f["meanZ"])  # floor 1 = highest (entrance side), as Blizzard numbers them
    for number, f in enumerate(floors, 1):
        f["floor"] = number
    covered = len(tiled) - len(unassigned)
    return {"status": "retail-uimap-assignment", "retailBuild": RETAIL_BUILD, "wmoRoot": wmo["rootFileDataID"],
            "tiledGroups": len(tiled), "directlyMatched": len(assigned), "multiFloorGroups": multi,
            "unassigned": unassigned, "coveragePercent": round(100.0 * covered / max(len(tiled), 1), 1),
            "directCoveragePercent": round(100.0 * len(assigned) / max(len(tiled), 1), 1), "floors": floors}


def main():
    retail = Wago(RETAIL_BUILD)
    uimaps = {r["ID"]: r for r in retail.db2("UiMap")}
    assignments = retail.db2("UiMapAssignment")
    os.makedirs(os.path.join(GEN, "floors"), exist_ok=True)
    wanted = [int(a) for a in sys.argv[1:]] or MAPS
    for map_id in wanted:
        with open(os.path.join(GEN, "discovery", "%d.json" % map_id), encoding="utf-8") as handle:
            report = json.load(handle)
        result = floors_for(retail, uimaps, assignments, report)
        result["mapID"], result["name"], result["foreverBuild"] = map_id, report["name"], FOREVER_BUILD
        with open(os.path.join(GEN, "floors", "%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(result, handle, indent=1, sort_keys=True)
            handle.write("\n")
        print("%5d %-26s %-24s floors=%d coverage=%s%% (direct %s%%) unassigned=%s multi=%s" % (
            map_id, report["name"], result["status"], len(result["floors"]), result.get("coveragePercent"),
            result.get("directCoveragePercent"), result.get("unassigned"), result.get("multiFloorGroups")))


if __name__ == "__main__":
    main()
