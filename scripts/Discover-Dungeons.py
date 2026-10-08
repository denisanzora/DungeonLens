"""DungeonLens map-discovery pipeline (read-only, standard library only).

For every Forever dungeon it joins, for ONE explicit client build:

  Map.db2 / UiMap.db2 / UiMapAssignment.db2   -> identity + native-UiMap check
  WDT (CASC)                                  -> terrain tile table (MAID) or global WMO (MODF)
  ADT obj0 (CASC)                             -> WMOs placed on terrain maps (MODF)
  root WMO (CASC)                             -> MOGI group bounds, GFID group ids
  file catalog                                -> WMO-minimap names (<prefix><group>_<x>_<y>.blp)
  BLP header (CASC, 20 bytes)                 -> per-tile native dimensions + build membership

and classifies the map as A native UiMap / B ground minimap / C WMO minimap /
D mixed / E nothing usable. Output is deterministic JSON (no timestamps) so a
diff between builds shows real data changes only.

    python scripts/Discover-Dungeons.py                  # all 14 Forever dungeons, installed build
    python scripts/Discover-Dungeons.py --maps 389,3065  # subset
    python scripts/Discover-Dungeons.py --all-instances  # also probe every other instance-type Map row
"""

import argparse
import concurrent.futures
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago, blp_header, installed_build, PRODUCT  # noqa: E402

# Dungeons Blizzard lists as available in the Forever beta (Oct 1 notes). The
# names are NOT trusted: every entry is verified against Map.db2 for the build.
FOREVER_DUNGEONS = [389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70, 2998]
UI_MAP_TYPE_DUNGEON = 4
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated")
STRIDE = 256  # logical block edge used by WoW minimap tiles


# ---------------------------------------------------------------- parsing
def chunk_list(data):
    """Tolerant chunk reader: returns [(name, payload)] preserving duplicates."""
    out, offset = [], 0
    while offset + 8 <= len(data):
        magic, size = struct.unpack_from("<4sI", data, offset)
        offset += 8
        if offset + size > len(data):
            raise ValueError("Truncated chunk")
        out.append((magic[::-1].decode("ascii", "replace"), data[offset:offset + size]))
        offset += size
    return out


def chunk_map(data):
    return {name: payload for name, payload in chunk_list(data)}


def parse_wdt(data):
    chunks = chunk_map(data)
    for needed in ("MPHD", "MAIN"):
        if needed not in chunks:
            raise ValueError("WDT missing " + needed)
    flags = struct.unpack_from("<I", chunks["MPHD"], 0)[0]
    main = chunks["MAIN"]
    if len(main) != 64 * 64 * 8:
        raise ValueError("Unexpected MAIN size")
    maid = chunks.get("MAID", b"")
    if maid and len(maid) != 64 * 64 * 32:
        raise ValueError("Unexpected MAID size")
    tiles = []
    for index in range(4096):
        has_adt = struct.unpack_from("<I", main, index * 8)[0] & 1
        if not has_adt:
            continue
        ids = struct.unpack_from("<8I", maid, index * 32) if maid else (0,) * 8
        # MAID words: root, obj0, obj1, tex0, lod, map, map_n, minimap  (word 7 proven
        # against the file catalog for Hall of Thanes: 81/81 tiles).
        tiles.append({"x": index % 64, "y": index // 64, "rootADT": ids[0], "obj0ADT": ids[1],
                      "minimapFileDataID": ids[7]})
    global_wmo = None
    modf = chunks.get("MODF", b"")
    if modf:
        if len(modf) != 64:
            raise ValueError("Expected one global MODF record")
        name_or_id, _unique = struct.unpack_from("<II", modf, 0)
        record_flags = struct.unpack_from("<H", modf, 56)[0]
        global_wmo = {"fileDataID": name_or_id, "isFileDataID": bool(record_flags & 8),
                      "position": list(struct.unpack_from("<3f", modf, 8))}
    return {"mphdFlags": flags, "usesGlobalWMO": bool(flags & 1), "tiles": tiles, "globalWMO": global_wmo,
            "chunks": [name for name, _ in chunk_list(data)]}


def parse_modf(data):
    placements = []
    for name, payload in chunk_list(data):
        if name != "MODF":
            continue
        if len(payload) % 64:
            raise ValueError("MODF size not a multiple of 64")
        for offset in range(0, len(payload), 64):
            name_id, unique = struct.unpack_from("<II", payload, offset)
            pos = struct.unpack_from("<3f", payload, offset + 8)
            rot = struct.unpack_from("<3f", payload, offset + 20)
            flags = struct.unpack_from("<H", payload, offset + 56)[0]
            scale = struct.unpack_from("<H", payload, offset + 62)[0]
            placements.append({"nameOrFileID": name_id, "uniqueID": unique, "isFileDataID": bool(flags & 8),
                               "position": [round(v, 4) for v in pos], "rotation": [round(v, 4) for v in rot],
                               "scale": scale or 1024})
    return placements


def parse_root_wmo(data):
    chunks = chunk_map(data)
    if len(chunks.get("MVER", b"")) != 4 or len(chunks.get("MOHD", b"")) < 64:
        raise ValueError("Not a root WMO")
    if struct.unpack("<I", chunks["MVER"])[0] != 17:
        raise ValueError("Unverified WMO version")
    count = struct.unpack_from("<I", chunks["MOHD"], 4)[0]
    mogi = chunks.get("MOGI", b"")
    if not 0 < count <= 1024 or len(mogi) != count * 32:
        raise ValueError("MOGI count/stride mismatch")
    gfid = chunks.get("GFID", b"")
    gfids = struct.unpack_from("<%dI" % count, gfid) if len(gfid) >= count * 4 else [None] * count
    names = chunks.get("MOGN", b"")
    groups = []
    for index in range(count):
        row = struct.unpack_from("<I6fi", mogi, index * 32)
        if not all(math.isfinite(v) for v in row[1:7]) or any(row[1 + a] > row[4 + a] for a in range(3)):
            raise ValueError("Invalid MOGI bounds")
        name = None
        if 0 <= row[7] < len(names):
            name = names[row[7]:].split(b"\0", 1)[0].decode("cp1252")
        groups.append({"index": index, "flags": row[0], "minimum": list(row[1:4]), "maximum": list(row[4:7]),
                       "groupFileDataID": gfids[index], "name": name})
    return {"groupCount": count, "groups": groups}


# ------------------------------------------------------------- discovery
def next_pow2(value):
    power = 1
    while power < value:
        power *= 2
    return power


def raster_edge(value):
    """Native stitched-raster edge for a WMO group extent (already multiplied by rho).
    BLPs are >=32 px; up to one 256 px cell they are powers of two; larger groups are
    whole 256 px cells. Fits 760/760 tiled groups in all 14 dungeons' WMOs (build 70245);
    RFC (the accepted entry) satisfies this and the older plain next-power-of-two rule."""
    if value <= STRIDE:
        return max(32, next_pow2(value))
    return int(math.ceil(value / STRIDE - 1e-9)) * STRIDE


def wmo_minimap_prefix(path):
    """world/wmo/<dir>/<name>.wmo  ->  world/minimaps/wmo/<dir>/<name>_  (RFC-validated rule)."""
    lowered = path.lower()
    if not lowered.startswith("world/wmo/") or not lowered.endswith(".wmo"):
        return None
    return "world/minimaps/wmo/" + lowered[len("world/wmo/"):-4] + "_"


def probe_tiles(wago, fdids):
    """BLP2 header for each FileDataID at the pinned build. Returns {fdid: (w,h)|None}."""
    def one(fdid):
        header = wago.file(fdid, header_only=True)
        return fdid, (blp_header(header) if header else None)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(one, sorted(set(fdids))))


def discover_wmo(wago, root_fdid):
    info = {"rootFileDataID": root_fdid, "rootPath": wago.path_of(root_fdid)}
    blob = wago.file(root_fdid)
    if blob is None:
        info["error"] = "root WMO absent at this build"
        return info
    info["rootMD5"] = __import__("hashlib").md5(blob).hexdigest()
    root = parse_root_wmo(blob)
    info["groupCount"] = root["groupCount"]
    prefix = wmo_minimap_prefix(info["rootPath"]) if info["rootPath"] else None
    info["minimapPrefix"] = prefix
    groups = {g["index"]: dict(g, tiles=[]) for g in root["groups"]}
    if prefix:
        import re
        pattern = re.compile(re.escape(prefix) + r"(\d+)_(\d+)_(\d+)\.blp$", re.I)
        entries = [e for e in wago.catalog_prefix(prefix) if pattern.fullmatch(e["filename"])]
        sizes = probe_tiles(wago, [e["fdid"] for e in entries])
        for entry in entries:
            match = pattern.fullmatch(entry["filename"])
            group, x, y = (int(v) for v in match.groups())
            if group not in groups or sizes[entry["fdid"]] is None:
                info.setdefault("rejectedTiles", []).append(entry["filename"])
                continue
            width, height = sizes[entry["fdid"]]
            groups[group]["tiles"].append({"fileDataID": entry["fdid"], "x": x, "y": y, "width": width,
                                           "height": height, "path": entry["filename"]})
    for group in groups.values():
        group["tiles"].sort(key=lambda t: (t["x"], t["y"]))
    # WMOAreaTable group ID (MOGP+56) of every tiled group: the key Blizzard's UiMapAssignment uses
    # to assign groups to dungeon floors.
    def group_id(index):
        fdid = groups[index].get("groupFileDataID")
        blob = wago.file_prefix(fdid, 128) if fdid else None
        offset = 0
        while blob and offset + 8 <= len(blob):
            magic, size = struct.unpack_from("<4sI", blob, offset)
            offset += 8
            if magic[::-1] == b"MOGP":
                return struct.unpack_from("<I", blob, offset + 56)[0] if offset + 60 <= len(blob) else None
            offset += size
        return None
    tiled_indexes = [i for i in groups if groups[i]["tiles"]]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for index, wmo_group_id in zip(tiled_indexes, pool.map(group_id, tiled_indexes)):
            groups[index]["wmoGroupID"] = wmo_group_id
    info["groups"] = [groups[i] for i in sorted(groups)]
    info["rho"] = fit_rho(info["groups"])
    info["floors"] = estimate_floors(info["groups"])
    return info


def fit_rho(groups):
    """Find a scale rho with stitched raster == raster_edge(rho * extent) for every tiled group."""
    tiled = [g for g in groups if g["tiles"]]
    if not tiled:
        return None
    result = {}
    for rho in (0.5, 1, 2, 4, 8):
        hits = 0
        for g in tiled:
            width = max(t["x"] * STRIDE + t["width"] for t in g["tiles"])
            height = max(t["y"] * STRIDE + t["height"] for t in g["tiles"])
            ok = (width == raster_edge(rho * (g["maximum"][0] - g["minimum"][0]))
                  and height == raster_edge(rho * (g["maximum"][1] - g["minimum"][1])))
            hits += ok
        result[str(rho)] = hits
    best = max(result, key=lambda k: (result[k], -float(k)))
    return {"best": float(best) if float(best) != int(float(best)) else int(float(best)),
            "matchedGroups": result[best], "tiledGroups": len(tiled), "allCandidates": result}


def estimate_floors(groups):
    """Cluster tiled groups into vertical bands: groups whose XY footprints overlap
    (>=25% of the smaller) but whose Z-ranges do not overlap are different floors.
    Heuristic only; floor *boundaries* still need visual confirmation."""
    tiled = [g for g in groups if g["tiles"]]
    if not tiled:
        return {"count": 0, "bands": []}

    def overlap_xy(a, b):
        w = min(a["maximum"][0], b["maximum"][0]) - max(a["minimum"][0], b["minimum"][0])
        h = min(a["maximum"][1], b["maximum"][1]) - max(a["minimum"][1], b["minimum"][1])
        if w <= 0 or h <= 0:
            return 0.0
        area = lambda g: (g["maximum"][0] - g["minimum"][0]) * (g["maximum"][1] - g["minimum"][1])
        return w * h / min(area(a), area(b))

    def z_overlap(a, b):
        return min(a["maximum"][2], b["maximum"][2]) - max(a["minimum"][2], b["minimum"][2])

    stacked_pairs = [(a["index"], b["index"]) for i, a in enumerate(tiled) for b in tiled[i + 1:]
                     if overlap_xy(a, b) >= 0.25 and z_overlap(a, b) <= 0]
    # Depth = longest chain of strictly-stacked groups per footprint column.
    zs = sorted((g["minimum"][2] + g["maximum"][2]) / 2 for g in tiled)
    return {"stackedGroupPairs": stacked_pairs, "maxStackDepth": _depth(tiled, overlap_xy, z_overlap),
            "zMin": min(g["minimum"][2] for g in tiled), "zMax": max(g["maximum"][2] for g in tiled),
            "zMidpoints": [round(z, 2) for z in zs]}


def _depth(groups, overlap_xy, z_overlap):
    best = 1
    for seed in groups:
        column = [g for g in groups if overlap_xy(seed, g) >= 0.25]
        column.sort(key=lambda g: g["minimum"][2])
        level, top = 0, -math.inf
        for g in column:
            if g["minimum"][2] >= top:  # strictly above everything chosen so far
                level += 1
                top = g["maximum"][2]
        best = max(best, level)
    return best


def tile_is_uniform(wago, fdid):
    """True when a decoded minimap tile is one flat colour (empty terrain backdrop).
    Needs Pillow; returns None when it is unavailable or the tile cannot be decoded."""
    try:
        import io
        from PIL import Image
        blob = wago.file(fdid)
        if blob is None:
            return None
        extrema = Image.open(io.BytesIO(blob)).convert("RGB").getextrema()
        return all(low == high for low, high in extrema)
    except Exception:
        return None


def discover_ground(wago, wdt):
    tiles = wdt["tiles"]
    with_minimap = [t for t in tiles if t["minimapFileDataID"]]
    sizes = probe_tiles(wago, [t["minimapFileDataID"] for t in with_minimap])
    out = []
    for t in with_minimap:
        size = sizes[t["minimapFileDataID"]]
        if size is None:
            continue
        out.append({"fileDataID": t["minimapFileDataID"], "x": t["x"], "y": t["y"], "width": size[0], "height": size[1]})
    out.sort(key=lambda t: (t["y"], t["x"]))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        flags = list(pool.map(lambda t: tile_is_uniform(wago, t["fileDataID"]), out))
    for t, uniform in zip(out, flags):
        t["uniform"] = uniform
    info = {"adtTileCount": len(tiles), "tileCount": len(out), "tiles": out}
    if out:
        xs, ys = [t["x"] for t in out], [t["y"] for t in out]
        have = {(t["x"], t["y"]) for t in out}
        info["bounds"] = {"minX": min(xs), "maxX": max(xs), "minY": min(ys), "maxY": max(ys)}
        info["gridColumns"] = max(xs) - min(xs) + 1
        info["gridRows"] = max(ys) - min(ys) + 1
        info["missingCoordinates"] = [[x, y] for y in range(min(ys), max(ys) + 1)
                                      for x in range(min(xs), max(xs) + 1) if (x, y) not in have]
        info["tileDimensions"] = sorted({"%dx%d" % (t["width"], t["height"]) for t in out})
        info["adtTilesWithoutMinimap"] = len(tiles) - len(out)
        content = [t for t in out if t["uniform"] is False]
        info["contentTileCount"] = len(content)
        if content:
            cx, cy = [t["x"] for t in content], [t["y"] for t in content]
            info["contentBounds"] = {"minX": min(cx), "maxX": max(cx), "minY": min(cy), "maxY": max(cy)}
    return info


def discover_placed_wmos(wago, wdt):
    """WMOs placed on terrain tiles (obj0 MODF), deduplicated by FileDataID."""
    def one(tile):
        if not tile["obj0ADT"]:
            return []
        blob = wago.file(tile["obj0ADT"])
        return [dict(p, tile=[tile["x"], tile["y"]]) for p in parse_modf(blob)] if blob else []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        placements = [p for batch in pool.map(one, wdt["tiles"]) for p in batch]
    return placements


def classify(map_row, native, ground, wmo, placed_wmos):
    wmo_tiles = sum(len(g["tiles"]) for w in wmo for g in w["groups"])
    ground_tiles = ground["tileCount"] if ground else 0
    if native:
        return "A", "native-uimap"
    if ground_tiles and wmo_tiles:
        return "D", "mixed-ground-and-wmo-minimaps"
    if wmo_tiles:
        depth = max((w["floors"].get("maxStackDepth", 1) for w in wmo), default=1)
        return ("D", "wmo-multi-floor") if depth > 1 else ("C", "wmo-minimap")
    if ground_tiles:
        return "B", "ground-minimap"
    return "E", "no-usable-native-data-discovered"


def analyse_map(wago, map_row, ui_maps, assignments):
    map_id = int(map_row["ID"])
    report = {"mapID": map_id, "instanceID": map_id, "name": map_row["MapName_lang"], "directory": map_row["Directory"],
              "mapType": int(map_row["MapType"]), "instanceType": int(map_row["InstanceType"]),
              "maxPlayers": int(map_row["MaxPlayers"]), "wdtFileDataID": int(map_row["WdtFileDataID"])}
    ui_ids = [int(a["UiMapID"]) for a in assignments if int(a["MapID"]) == map_id]
    dungeon_ui = [u for u in ui_maps if int(u["ID"]) in ui_ids and int(u["Type"]) == UI_MAP_TYPE_DUNGEON]
    report["uiMapAssignments"] = sorted(ui_ids)
    report["nativeDungeonUiMaps"] = [int(u["ID"]) for u in dungeon_ui]
    wdt_bytes = wago.file(report["wdtFileDataID"])
    if wdt_bytes is None:
        report.update(classification="E", classificationReason="wdt-absent-at-build")
        return report
    wdt = parse_wdt(wdt_bytes)
    report["wdt"] = {"usesGlobalWMO": wdt["usesGlobalWMO"], "adtTileCount": len(wdt["tiles"]), "chunks": wdt["chunks"],
                     "mphdFlags": wdt["mphdFlags"]}
    ground, wmos, placed = None, [], []
    if wdt["globalWMO"] and wdt["globalWMO"]["isFileDataID"]:
        report["wdt"]["globalWMO"] = wdt["globalWMO"]
        wmos.append(discover_wmo(wago, wdt["globalWMO"]["fileDataID"]))
        report["layout"] = "global-wmo"
    else:
        report["layout"] = "terrain"
        ground = discover_ground(wago, wdt)
        placements = discover_placed_wmos(wago, wdt)
        by_id = {}
        for p in placements:
            if p["isFileDataID"]:
                by_id.setdefault(p["nameOrFileID"], []).append(p)
        for fdid in sorted(by_id):
            info = discover_wmo(wago, fdid)
            seen, unique = set(), []
            for p in by_id[fdid]:  # a WMO straddling ADT tiles is listed once per tile
                if p["uniqueID"] not in seen:
                    seen.add(p["uniqueID"])
                    unique.append({"uniqueID": p["uniqueID"], "position": p["position"], "rotation": p["rotation"],
                                   "scale": p["scale"]})
            info["placements"] = unique
            if any(g["tiles"] for g in info.get("groups", [])):
                wmos.append(info)
            else:
                placed.append({"rootFileDataID": fdid, "rootPath": info.get("rootPath"), "placementCount": len(by_id[fdid]),
                               "hasMinimaps": False})
        report["placedWMOCountWithoutMinimaps"] = len(placed)
        report["placedWMOsWithoutMinimaps"] = placed[:50]
    report["ground"] = ground
    report["wmos"] = wmos
    letter, reason = classify(map_row, report["nativeDungeonUiMaps"], ground, wmos, placed)
    report["classification"], report["classificationReason"] = letter, reason
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", help="client build (default: installed build from .build.info)")
    parser.add_argument("--maps", help="comma-separated Map IDs (default: the 14 Forever dungeons)")
    parser.add_argument("--all-instances", action="store_true", help="also probe other instance-type Map rows")
    parser.add_argument("--out", default=OUT_DIR)
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    local_version, local_key = installed_build()
    build = args.build or local_version
    wago = Wago(build, use_cache=not args.no_cache)
    latest = wago.latest_build()
    provenance = {"requestedBuild": build, "installedBuild": local_version, "installedBuildKey": local_key,
                  "providerLatest": latest.get("version"), "providerBuildConfig": latest.get("build_config"),
                  "buildKeyMatchesProvider": latest.get("version") == build and latest.get("build_config") == local_key}
    # Version-scoped CASC must actually serve this build and reject a bogus one.
    control = Wago("0.0.0.0", use_cache=False)
    provenance["bogusVersionRejected"] = control.file(789981, header_only=True) is None
    if not wago.file(789981, header_only=True):
        raise SystemExit("Wago cannot serve build " + build)

    maps = {int(r["ID"]): r for r in wago.db2("Map")}
    ui_maps, assignments = wago.db2("UiMap"), wago.db2("UiMapAssignment")
    assert any(int(a["UiMapID"]) == 1411 and int(a["MapID"]) == 1 for a in assignments), "positive control failed"
    wanted = [int(v) for v in args.maps.split(",")] if args.maps else list(FOREVER_DUNGEONS)
    if args.all_instances:
        wanted += sorted(i for i, r in maps.items() if r["InstanceType"] in ("1", "2") and i not in wanted)
    os.makedirs(os.path.join(args.out, "discovery"), exist_ok=True)

    summary = []
    for map_id in wanted:
        if map_id not in maps:
            print("Map %d: NOT PRESENT in build %s" % (map_id, build))
            summary.append({"mapID": map_id, "present": False})
            continue
        report = analyse_map(wago, maps[map_id], ui_maps, assignments)
        report["build"] = build
        with open(os.path.join(args.out, "discovery", "%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(report, handle, indent=1, sort_keys=True)
            handle.write("\n")
        ground = report.get("ground") or {}
        wmo_tiles = sum(len(g["tiles"]) for w in report.get("wmos", []) for g in w["groups"])
        row = {"mapID": map_id, "present": True, "name": report["name"], "directory": report["directory"],
               "instanceType": report["instanceType"], "wdtFileDataID": report["wdtFileDataID"],
               "layout": report.get("layout"), "nativeUiMaps": report["nativeDungeonUiMaps"],
               "classification": report["classification"], "reason": report["classificationReason"],
               "groundTiles": ground.get("tileCount", 0), "wmoTiles": wmo_tiles,
               "wmoRoots": [w["rootFileDataID"] for w in report.get("wmos", [])],
               "maxStackDepth": max([w["floors"].get("maxStackDepth", 1) for w in report.get("wmos", []) if "floors" in w] or [0])}
        summary.append(row)
        print("%5d %-28s %s %-34s ground=%-3d wmoTiles=%-4d depth=%d" % (
            map_id, report["name"], row["classification"], row["reason"], row["groundTiles"], wmo_tiles, row["maxStackDepth"]))
    with open(os.path.join(args.out, "inventory.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump({"provenance": provenance, "dungeons": summary}, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(json.dumps(provenance, indent=1))


if __name__ == "__main__":
    main()
