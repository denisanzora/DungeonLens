"""Build boss marker data with full provenance.

Identity   : Forever DungeonEncounter.db2 (build 70245): names, encounter IDs, difficulties.
Coordinates: (1) public server-database spawn positions (External-Spawns.py), world frame;
             (2) Blizzard retail Encounter Journal pins (JournalEncounterXMapLoc + UiMapAssignment
                 region -> world), an independent second source where the encounter exists in retail.
Registration (proven, see Fit-Frames.py): WMO-local = Rot(180 - yaw) * (world - origin), where origin
and yaw come from the WMO's ADT placement (zero/zero for global-WMO dungeons). World -> canvas uses the
same canonical layout as the addon. Floors come from Discover-Floors.py (Blizzard floor membership)
and are chosen per boss by group containment.

Statuses: verified-client | verified-source-registration | approximate | unresolved
  verified-source-registration, high  : spawn AND retail pin agree (<= 35 yd, same floor)
  verified-source-registration, medium: one source, frame proven, floor resolved, point on painted pixels
  approximate                         : anything weaker (ambiguous spawn, source disagreement, off-content ...)
  unresolved                          : no coordinate source exists

    python scripts/Build-Bosses.py
"""

import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago  # noqa: E402
from dl_common import build_floors, frame_for, manifest_item  # noqa: E402
import wmo_layout as L  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN = os.path.join(HERE, "generated")
FOREVER_BUILD = "1.60.1.70245"
RETAIL_BUILD = "12.1.0.69933"
AGREE_YARDS = 35.0
MAPS = [389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70, 2998]
# Maps whose layout needs multi-WMO placement; bosses stay unresolved until those maps are generated.
DEFERRED = {2998}

# Name aliases between Forever encounter names and database/retail names (normalized).
ALIASES = {
    "geilhast": ["gelihast"], "gelihast": ["geilhast"],
    "cookie": ["captaincookie"], "captaincookie": ["cookie"],
    "thelostdwarves": ["baelog", "olaf", "ericthe swift", "ericthe"],  # trio encounter; any member marks the room
}


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def load(path):
    with open(os.path.join(GEN, path), encoding="utf-8") as handle:
        return json.load(handle)


def rot(dx, dy, degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return c * dx - s * dy, s * dx + c * dy


def world_to_local(frame, wx, wy):
    (ox, oy), yaw, _ = frame
    return rot(wx - ox, wy - oy, 180.0 - yaw)


def local_to_world(frame, lx, ly):
    (ox, oy), yaw, _ = frame
    dx, dy = rot(lx, ly, -(180.0 - yaw))
    return dx + ox, dy + oy


def encounters(forever):
    """Forever DungeonEncounter rows -> bosses per map (deduplicated by normalized name)."""
    out = {}
    for row in forever.db2("DungeonEncounter"):
        map_id = int(row["MapID"])
        if map_id not in MAPS:
            continue
        key = norm(row["Name_lang"])
        if key == "geilhast":
            key = "gelihast"
        boss = out.setdefault(map_id, {}).setdefault(key, {"name": row["Name_lang"], "encounterIDs": [], "difficulties": [],
                                                           "order": int(row["OrderIndex"])})
        boss["encounterIDs"].append(int(row["ID"]))
        boss["difficulties"].append(int(row["DifficultyID"]))
        boss["order"] = min(boss["order"], abs(int(row["OrderIndex"])))
    return out


def retail_pins(retail):
    ji = {r["ID"]: r for r in retail.db2("JournalInstance")}
    je = retail.db2("JournalEncounter")
    xl = retail.db2("JournalEncounterXMapLoc")
    ua = retail.db2("UiMapAssignment")
    regions = {}
    for r in ua:
        regions.setdefault(r["UiMapID"], [round(float(r["Region_%d" % i]), 4) for i in range(6)])
    pins = {}
    for e in je:
        inst = ji.get(e["JournalInstanceID"])
        if not inst:
            continue
        for loc in (x for x in xl if x["JournalEncounterID"] == e["ID"]):
            region = regions.get(loc["UiMapID"])
            u, v = float(loc["Map_0"]), float(loc["Map_1"])
            if not region or (u == 0.0 and v == 0.0):
                continue
            x0, y0, _, x1, y1, _ = region
            wx, wy = x1 - v * (x1 - x0), y1 - u * (y1 - y0)  # validated on Uldaman/Gnomeregan (Fit notes)
            pins.setdefault(int(inst["MapID"]), {}).setdefault(norm(e["Name_lang"]), []).append(
                {"journalEncounterID": int(e["ID"]), "dungeonEncounterID": int(e["DungeonEncounterID"]), "uiMapID": int(loc["UiMapID"]),
                 "mapX": u, "mapY": v, "worldX": round(wx, 2), "worldY": round(wy, 2)})
    return pins


def retail_layout_matches(retail, forever_root, map_id, cache={}):
    """Retail pins are only comparable when retail's WMO for this map is the same file as Forever's."""
    if map_id not in cache:
        import importlib.util
        spec = importlib.util.spec_from_file_location("dd", os.path.join(HERE, "Discover-Dungeons.py"))
        dd = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dd)
        row = next((r for r in retail.db2("Map") if int(r["ID"]) == map_id), None)
        blob = retail.file(int(row["WdtFileDataID"])) if row else None
        wdt = dd.parse_wdt(blob) if blob else None
        cache[map_id] = (wdt["globalWMO"]["fileDataID"] if wdt and wdt["globalWMO"] else None)
    return cache[map_id] is None or cache[map_id] == forever_root  # terrain maps: ADT WMOs assumed shared


def spawn_candidates(spawns, keys):
    found = [s for s in spawns if norm(s["name"]) in keys]
    clusters = []
    for s in found:
        for c in clusters:
            if math.hypot(c[0]["x"] - s["x"], c[0]["y"] - s["y"]) <= 30:
                c.append(s)
                break
        else:
            clusters.append([s])
    return found, clusters


def floor_of(world, floors):
    """Floor/page containing the world point. Each floor has its own WMO frame, so the point is
    projected into every floor's local space; group-bbox containment (incl. height) decides, smallest
    vertical distance wins. Returns (floor, how, (local_x, local_y))."""
    wx, wy, z = world
    scored = []
    for f in floors:
        lx, ly = world_to_local(f["frame"], wx, wy)
        zl = z - f["frame"][2]
        best = None
        for gi in f["groups"]:
            g = f["groupsMap"][gi]
            if (g["minimum"][0] - 2 <= lx <= g["maximum"][0] + 2 and g["minimum"][1] - 2 <= ly <= g["maximum"][1] + 2
                    and g["minimum"][2] - 6 <= zl <= g["maximum"][2] + 6):
                d = abs(zl - (g["minimum"][2] + g["maximum"][2]) / 2)
                best = d if best is None else min(best, d)
        if best is not None:
            scored.append((best, f["floor"], (lx, ly)))
    scored.sort(key=lambda t: (t[0], t[1]))
    if not scored:
        return None, "no-containing-group", None
    if len(scored) > 1 and scored[1][0] - scored[0][0] < 3.0:
        return scored[0][1], "ambiguous-between-floors-%s" % [t[1] for t in scored[:2]], scored[0][2]
    return scored[0][1], "group-containment", scored[0][2]


def painted(mask, px, py, radius=10):
    w, h = mask.size
    pixels = mask.load()
    ix, iy = int(round(px)), int(round(py))
    for dx in range(-radius, radius + 1, 2):
        for dy in range(-radius, radius + 1, 2):
            x, y = ix + dx, iy + dy
            if 0 <= x < w and 0 <= y < h and pixels[x, y]:
                return True
    return False


def signature(kind, layout, floor=None):
    sig = "%s:%dx%d:%d" % (kind, int(layout["width"] + 0.5), int(layout["height"] + 0.5), len(layout["tiles"]))
    return sig + (":f%d" % floor if floor else "")


def write_report(results):
    """scripts/BOSS-PROVENANCE.md: one row per boss with identity, coordinate source, space, confidence."""
    lines = ["# Boss marker provenance (build %s)" % FOREVER_BUILD, "",
             "Generated by `scripts/Build-Bosses.py`. **Identity** = Forever `DungeonEncounter.db2` (build %s). **Coordinates** = public server-database "
             "spawn rows (AzerothCore `acore_world`) and/or Blizzard retail Encounter Journal pins (build %s), both in the instance world frame "
             "(X north, Y west), registered to the Blizzard-native layout by `local = Rot(180 - yaw) * (world - origin)` -> canvas, a transform "
             "proven by `Fit-Frames.py` (100%% of every dungeon's spawns land on painted minimap pixels for 11 of 13 mapped dungeons; see "
             "`FRAME-FIT.md`). Floors come from Blizzard's floor assignment by group containment." % (FOREVER_BUILD, RETAIL_BUILD), "",
             "Statuses: **verified-source-registration** (high = spawn DB and retail pin agree within %d yd; medium = single source, floor resolved, "
             "point on painted pixels), **approximate** (development only), **unresolved** (no usable coordinate), **verified-client** (confirmed "
             "in-game with `/dlmap author`; none yet)." % AGREE_YARDS, "",
             "| Dungeon | Boss | Encounter ID | Identity | Coordinate source | Space -> canvas | Floor | Status | Confidence | Notes |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    totals = {}
    for r in results:
        for b in r["bosses"]:
            kinds = []
            for src in b.get("sources", []):
                kinds.append("spawn DB (%d row%s)" % (src["spawnRows"], "" if src["spawnRows"] == 1 else "s") if src["type"] == "server-spawn-db"
                             else "retail Journal pin")
            if "agreementYards" in b:
                kinds.append("agree %.0f yd" % b["agreementYards"])
            space = "world -> local -> floor %s canvas" % b["floor"] if b.get("floor") else "-"
            lines.append("| %s | %s | %s | DungeonEncounter | %s | %s | %s | %s | %s | %s |" % (
                r["name"], b["name"], ", ".join(str(i) for i in b["encounterIDs"]), "; ".join(kinds) or "none", space,
                b.get("floor", "-"), b["status"], b["confidence"], "; ".join(b.get("notes", [])) or ""))
            totals[b["status"]] = totals.get(b["status"], 0) + 1
    lines += ["", "Totals: " + ", ".join("%s %d" % (k, v) for k, v in sorted(totals.items())) + "."]
    with open(os.path.join(HERE, "BOSS-PROVENANCE.md"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    forever = Wago(FOREVER_BUILD)
    retail = Wago(RETAIL_BUILD)
    bosses_by_map = encounters(forever)
    pins = retail_pins(retail)
    frames = {}
    out_dir = os.path.join(GEN, "bosses")
    os.makedirs(out_dir, exist_ok=True)
    summary = []
    vectors, all_results = [], []
    for map_id in MAPS:
        discovery = load("discovery/%d.json" % map_id)
        floors_info = load("floors/%d.json" % map_id)
        spawns = load("spawns/%d.json" % map_id)["spawns"] if os.path.exists(os.path.join(GEN, "spawns", "%d.json" % map_id)) else []
        result = {"mapID": map_id, "name": discovery["name"], "foreverBuild": FOREVER_BUILD, "retailBuild": RETAIL_BUILD,
                  "identitySource": "DungeonEncounter.db2 build " + FOREVER_BUILD, "bosses": [], "layouts": {}, "notes": []}
        bosses = sorted(bosses_by_map.get(map_id, {}).values(), key=lambda b: (b["order"], b["name"]))
        use_ground = (manifest_item(map_id) or {}).get("source") == "ground"  # Ruins of Lordaeron is terrain; its Undercity WMO is not the dungeon
        layouts, masks, floors = {}, {}, []
        if use_ground:
            result["notes"].append("registry map is the ground-tile minimap; no boss coordinate source exists for this dungeon")
        elif map_id in DEFERRED:
            result["notes"].append("map layout not generated - coordinates withheld")
        else:
            floors = build_floors(map_id, discovery, floors_info)
        for f in floors:
            f["frame"] = frame_for(f["wmo"])
            f["groupsMap"] = {g["index"]: g for g in f["wmo"]["groups"] if g["tiles"]}
            layout = L.canonical_layout(f["wmo"], (f["wmo"].get("rho") or {}).get("best") or 2, set(f["groups"]))
            layouts[f["floor"]] = layout
            masks[f["floor"]] = L.content_mask(forever, layout)
            result["layouts"][str(f["floor"])] = signature("wmo", layout, f["floor"] if len(floors) > 1 else None)
        wmo = floors[0]["wmo"] if floors else None
        frame = floors[0]["frame"] if floors else None
        result["floors"] = [{"floor": f["floor"], "uiMapID": f["uiMapID"], "groupCount": len(f["groups"]),
                             "wmoRoot": f["wmo"]["rootFileDataID"], "source": f.get("source")} for f in floors]
        result["frame"] = {"origin": frame[0] if frame else None, "yaw": frame[1] if frame else None,
                           "formula": "local = Rot(180 - yaw) * (world - origin); canvas = (local.x*rho - minX, maxY - local.y*rho)",
                           "perFloorFrames": [{"floor": f["floor"], "origin": f["frame"][0], "yaw": f["frame"][1]} for f in floors]}
        for index, boss in enumerate(bosses, 1):
            keys = {norm(boss["name"])} | set(ALIASES.get(norm(boss["name"]), []))
            found, clusters = spawn_candidates(spawns, keys)
            pin_list = [p for k in keys for p in pins.get(map_id, {}).get(k, [])]
            if pin_list and wmo is not None and not retail_layout_matches(retail, wmo["rootFileDataID"], map_id):
                record_note = "retail pin ignored: retail uses a different WMO for this dungeon"
                pin_list = []
            else:
                record_note = None
            record = {"id": min(boss["encounterIDs"]), "encounterIDs": sorted(set(boss["encounterIDs"])), "name": boss["name"],
                      "difficulties": sorted(set(boss["difficulties"])), "order": index, "identitySource": result["identitySource"],
                      "sources": [], "status": "unresolved", "confidence": "none", "notes": []}
            if record_note:
                record["notes"].append(record_note)
            world = None
            if found:
                cluster = max(clusters, key=len)
                world = (sum(s["x"] for s in cluster) / len(cluster), sum(s["y"] for s in cluster) / len(cluster),
                         sum(s["z"] for s in cluster) / len(cluster))
                record["sources"].append({"type": "server-spawn-db", "origin": "azerothcore-wotlk db_world", "entries": sorted({s["entry"] for s in found}),
                                          "world": [round(v, 2) for v in world], "spawnRows": len(found), "clusters": len(clusters)})
                if len(clusters) > 1:
                    record["notes"].append("%d separate spawn clusters; used the largest" % len(clusters))
            pin_world = None
            if pin_list:
                pin = pin_list[0]
                pin_world = (pin["worldX"], pin["worldY"])
                record["sources"].append({"type": "blizzard-retail-journal-pin", "build": RETAIL_BUILD, "uiMapID": pin["uiMapID"],
                                          "mapXY": [round(pin["mapX"], 4), round(pin["mapY"], 4)], "world": list(pin_world)})
            record["worldPosition"] = None
            if wmo is None or map_id in DEFERRED:
                record["notes"].append("no generated map for this dungeon yet")
            elif world is None and pin_world is None:
                record["notes"].append("no coordinate source: not in the server database or in retail Encounter Journal")
            else:
                if world is None:
                    world = (pin_world[0], pin_world[1], None)
                z = world[2]
                if z is None:  # pin has no height: infer from the retail floor UiMap
                    pf = next((f for f in floors if f["uiMapID"] == pin_list[0]["uiMapID"]), floors[0])
                    zs = [(pf["groupsMap"][g]["minimum"][2] + pf["groupsMap"][g]["maximum"][2]) / 2 for g in pf["groups"]]
                    z = sum(zs) / len(zs) + pf["frame"][2]
                if len(floors) == 1:
                    floor, how = 1, "single-floor-map"
                    lx, ly = world_to_local(floors[0]["frame"], world[0], world[1])
                else:
                    floor, how, local = floor_of((world[0], world[1], z), floors)
                    lx, ly = local if local else (None, None)
                record["floorSource"] = how
                if floor is not None:
                    layout, mask = layouts[floor], masks[floor]
                    px, py = L.world_to_canvas(layout, lx, ly)
                    on_content = painted(mask, px, py)
                    in_canvas = 0 <= px <= layout["width"] and 0 <= py <= layout["height"]
                    record.update(floor=floor, x=round(px / layout["width"], 4), y=round(py / layout["height"], 4),
                                  worldPosition=[round(world[0], 2), round(world[1], 2), round(z, 2)], onContent=bool(on_content and in_canvas))
                    if not in_canvas:
                        for key in ("x", "y", "floor"):
                            record.pop(key, None)
                        record["status"], record["confidence"] = "unresolved", "none"
                        record["notes"].append("source position lies outside the generated map (that area has no minimap tiles in this build)")
                        result["bosses"].append(record)
                        continue
                    agree = None
                    if pin_world is not None and found:
                        agree = math.hypot(pin_world[0] - world[0], pin_world[1] - world[1])
                        record["agreementYards"] = round(agree, 1)
                        pin_floor = next((f["floor"] for f in floors if f["uiMapID"] == pin_list[0]["uiMapID"]), None)
                        if pin_floor is not None and pin_floor != floor:
                            record["notes"].append("retail pin is on floor %s, containment says %s" % (pin_floor, floor))
                            agree = None if agree <= AGREE_YARDS else agree
                    reasons = []
                    if how.startswith("ambiguous"):
                        reasons.append(how)
                    if not record["onContent"]:
                        reasons.append("projected point is not on painted minimap pixels")
                    if len(clusters) > 1:
                        reasons.append("multiple spawn clusters")
                    if found and pin_world is not None and (agree is None or agree > AGREE_YARDS):
                        reasons.append("spawn and retail pin disagree")
                    if not found:
                        reasons.append("single source (retail pin only)")
                    if reasons:
                        record["status"], record["confidence"] = "approximate", "low"
                        record["notes"].extend(reasons)
                    elif found and pin_world is not None:
                        record["status"], record["confidence"] = "verified-source-registration", "high"
                    else:
                        record["status"], record["confidence"] = "verified-source-registration", "medium"
                else:
                    record["status"], record["confidence"] = "approximate", "low"
                    record["notes"].append("floor unresolved: " + how)
                    record["worldPosition"] = [round(world[0], 2), round(world[1], 2), None]
            result["bosses"].append(record)
        counts = {}
        for b in result["bosses"]:
            counts[b["status"]] = counts.get(b["status"], 0) + 1
        result["counts"] = counts
        for b in result["bosses"]:
            if b["status"] != "unresolved" and b.get("worldPosition") and b.get("floor"):
                vectors.append({"map": map_id, "name": b["name"], "floor": b["floor"], "world": b["worldPosition"], "status": b["status"],
                                "x": b["x"], "y": b["y"]})
        with open(os.path.join(out_dir, "%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(result, handle, indent=1, sort_keys=True)
            handle.write("\n")
        summary.append((map_id, discovery["name"], len(bosses), counts))
        all_results.append(result)
        print("%5d %-26s bosses=%d %s floors=%d" % (map_id, discovery["name"], len(bosses), counts, len(floors)))
    with open(os.path.join(GEN, "projection-vectors.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(vectors, handle, indent=0, sort_keys=True)
        handle.write("\n")
    write_report(all_results)


if __name__ == "__main__":
    main()