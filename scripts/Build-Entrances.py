"""Build DungeonEntrances.lua: where each dungeon's entrance is on the world map (zone UiMapID + normalized x/y).

Sources (Forever build 1.60.1.70245 client tables via Wago):
  * Map.db2 CorpseMapID/Corpse_0/Corpse_1 = the continent position outside the entrance (where the corpse run starts); cross-checked
    against AzerothCore's "<dungeon> Instance Start" teleport targets (within ~10 yd).
  * UiMapAssignment Region_0..5 = world bounds of each zone's UiMap. Zone bounds are overlapping rectangles, so the zone is named per
    dungeon in ZONE below (game knowledge) and the script checks that the point lies inside that zone's bounds. Normalized position
    (0..1, left->right, top->bottom):
        x = (Region_4 - worldY) / (Region_4 - Region_1)        y = (Region_3 - worldX) / (Region_3 - Region_0)
    World X is north and world Y is west. Sanity: Ragefire Chasm lands at Orgrimmar 52.9/48.9 and Scarlet Monastery at Tirisfal 85.1/31.4.
Forever-only dungeons have no corpse position; they are listed in EXTRA with the evidence for each:
  * Ruins of Lordaeron: AreaTrigger 3547 (continent 0, 1642.1, 239.8, 62.6) sits at the keep of the walled city and at the WMO's own height
    offset (62.5); the guides place the entrance just inside the front gate, up stairs, before the keep.
  * The Hall of Thanes / Excavation Site: no coordinate in any client table; zone-level only (or nothing).

    python scripts/Build-Entrances.py [--check]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from wago_client import Wago  # noqa: E402

BUILD = "1.60.1.70245"
BIG = 200 * 1024 * 1024
OUT = os.path.join(ROOT, "DungeonEntrances.lua")
MAPS = [389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70]  # dungeons with a map window (2998 has none)

# The zone map each entrance belongs to (UiMapIDs from the Forever client). Validated against the zone's world bounds when built.
ZONE = {389: 1454, 43: 1413, 36: 1436, 33: 1421, 34: 1453, 48: 1440, 90: 1426, 47: 1413, 189: 1420, 129: 1413, 70: 1418, 2999: 1420}

# Forever-only dungeons: explicit evidence instead of a corpse position.
EXTRA = {
    2999: {"continent": 0, "world": (1642.1, 239.8), "source": "Forever AreaTrigger 3547 (keep of the walled city)",
           "note": "Just inside the front gate of the ruined city, up the stairs on your left before the keep."},
    3065: {"uiMapID": 1455, "source": "foreverdb.net / wowforever.wclbox.com: Old Ironforge's deepest level (no coordinates published)",
           "note": "Old Ironforge, deepest level. The exact entrance is not known yet."},
}
NOTES = {389: "In the Cleft of Shadow, below Orgrimmar."}


def lua_string(text):
    return json.dumps(text, ensure_ascii=False)


def build():
    wago = Wago(BUILD)
    corpse = {int(r["ID"]): r for r in wago.db2("Map", limit=BIG)}
    uimaps = {int(r["ID"]): r for r in wago.db2("UiMap", limit=BIG)}
    zones = []
    for r in wago.db2("UiMapAssignment", limit=BIG):
        u = int(r["UiMapID"])
        if uimaps.get(u, {}).get("Type") == "3":  # zone (cities included)
            x0, y0, x1, y1 = (float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"]))
            zones.append({"ui": u, "name": uimaps[u]["Name_lang"], "map": int(r["MapID"]), "x0": x0, "y0": y0, "x1": x1, "y1": y1,
                          "area": (x1 - x0) * (y1 - y0)})

    def locate(map_id, continent, wx, wy):
        z = next(c for c in zones if c["ui"] == ZONE[map_id])
        if z["map"] != continent or not (z["x0"] <= wx <= z["x1"] and z["y0"] <= wy <= z["y1"]):
            raise SystemExit("%s (UiMap %d) does not contain map %d's entrance (continent %d, %.1f, %.1f)" % (z["name"], z["ui"], map_id, continent, wx, wy))
        return z, (z["y1"] - wy) / (z["y1"] - z["y0"]), (z["x1"] - wx) / (z["x1"] - z["x0"])

    entries = {}
    for map_id in MAPS:
        extra = EXTRA.get(map_id)
        if extra and "uiMapID" in extra:  # zone only
            entries[map_id] = {"uiMapID": extra["uiMapID"], "zone": uimaps[extra["uiMapID"]]["Name_lang"], "source": extra["source"],
                               "note": extra["note"]}
            continue
        if extra:
            continent, (wx, wy) = extra["continent"], extra["world"]
            source, note = extra["source"], extra["note"]
        else:
            row = corpse[map_id]
            continent, wx, wy = int(row["CorpseMapID"]), float(row["Corpse_0"]), float(row["Corpse_1"])
            if continent < 0:
                raise SystemExit("map %d has no corpse position and no EXTRA entry" % map_id)
            source, note = "Forever Map.db2 corpse-run position (continent %d, %.1f, %.1f)" % (continent, wx, wy), NOTES.get(map_id)
        zone, x, y = locate(map_id, continent, wx, wy)
        entries[map_id] = {"uiMapID": zone["ui"], "zone": zone["name"], "x": round(x, 4), "y": round(y, 4), "source": source, "note": note}
    return entries


def render(entries):
    lines = ["-- GENERATED by scripts/Build-Entrances.py (Forever build %s). DO NOT EDIT." % BUILD,
             "-- Entrance of each dungeon on the world map: zone UiMapID plus normalized x/y (0..1, left->right, top->bottom).",
             "-- Entries without x/y are zone-level only (the exact entrance is not known). Provenance: scripts/Build-Entrances.py.",
             "local _, ns = ...", "ns.DungeonEntrances = {"]
    for map_id in sorted(entries):
        e = entries[map_id]
        parts = ["uiMapID = %d" % e["uiMapID"], "zone = %s" % lua_string(e["zone"])]
        if "x" in e:
            parts += ["x = %.4f" % e["x"], "y = %.4f" % e["y"]]
        if e.get("note"):
            parts.append("note = %s" % lua_string(e["note"]))
        lines.append("    [%d] = { %s }, -- %s" % (map_id, ", ".join(parts), e["source"]))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    text = render(build())
    if "--check" in sys.argv:
        assert open(OUT, encoding="utf-8").read().replace("\r\n", "\n") == text, "DungeonEntrances.lua is stale"
        print("entrances are current")
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(text)


if __name__ == "__main__":
    main()
