"""Generate MapData.lua (runtime registry data) from scripts/generated/discovery/*.json.

Deterministic: same discovery input -> byte-identical output. The runtime addon never needs
Python; it only loads the generated Lua table. Entries are emitted as candidates
(verified = false) until an in-game visual acceptance is recorded.

    python scripts/Generate-Registry.py            # write MapData.lua
    python scripts/Generate-Registry.py --check    # fail if MapData.lua is stale; cross-check RFC 389
"""

import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dl_common import chosen_floors, frame_for  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STRIDE = 256


def num(value):
    if isinstance(value, int):
        return str(value)
    text = repr(float(value))
    return text[:-2] if text.endswith(".0") else text


def next_pow2(value):
    power = 1
    while power < value:
        power *= 2
    return power


def raster_edge(value):
    """Same rule as Discover-Dungeons.py and WMOComposition.lua."""
    if value <= STRIDE:
        return max(32, next_pow2(value))
    return int(math.ceil(value / STRIDE - 1e-9)) * STRIDE


def load(map_id):
    with open(os.path.join(HERE, "generated", "discovery", "%d.json" % map_id), encoding="utf-8") as handle:
        return json.load(handle)


def load_floors(map_id):
    with open(os.path.join(HERE, "generated", "floors", "%d.json" % map_id), encoding="utf-8") as handle:
        return json.load(handle)


def provenance(report, extra):
    with open(os.path.join(HERE, "generated", "inventory.json"), encoding="utf-8") as handle:
        inventory = json.load(handle)["provenance"]
    lines = ['            discoveredBuild = "%s", buildConfig = "%s",' % (report["build"], inventory["providerBuildConfig"]),
             '            wdtFileDataID = %d, evidence = "scripts/generated/discovery/%d.json",' % (
                 report["wdtFileDataID"], report["mapID"])]
    return "\n".join(lines + extra)


def fr(wmo):
    (ox, oy), yaw, zoff = frame_for(wmo)
    return "{ originX = %s, originY = %s, yaw = %s, zOffset = %s }" % (num(round(ox, 4)), num(round(oy, 4)), num(yaw), num(round(zoff, 4)))


def check_wmo(report, wmo):
    rho = wmo["rho"] or {}
    tiled = [g for g in wmo["groups"] if g["tiles"]]
    if not tiled or rho.get("matchedGroups") != rho.get("tiledGroups"):
        raise SystemExit("Map %d WMO %d is not generator-safe: rho=%s" % (report["mapID"], wmo["rootFileDataID"], rho))
    for g in tiled:  # catalog names absent at this build are ignorable; a hole inside a group is not
        have = {(t["x"], t["y"]) for t in g["tiles"]}
        if len(have) != (max(x for x, _ in have) + 1) * (max(y for _, y in have) + 1):
            raise SystemExit("Map %d WMO %d group %d has a tile-grid hole" % (report["mapID"], wmo["rootFileDataID"], g["index"]))
        width = max(t["x"] * STRIDE + t["width"] for t in g["tiles"])
        height = max(t["y"] * STRIDE + t["height"] for t in g["tiles"])  # the runtime re-checks this; fail early here
        assert width == raster_edge(rho["best"] * (g["maximum"][0] - g["minimum"][0]))
        assert height == raster_edge(rho["best"] * (g["maximum"][1] - g["minimum"][1]))
    return rho, tiled


def wmo_entry(report, roots, noun=None, labels=None):
    """One WMO (floors from Blizzard data) or several WMOs as pages (each its own floor/wing)."""
    wmos = [next(w for w in report["wmos"] if w["rootFileDataID"] == r) for r in roots]
    paged = len(wmos) > 1
    groups, floors, tile_total, depth = [], [], 0, 1
    rho = None
    for k, wmo in enumerate(wmos):
        rho_k, tiled = check_wmo(report, wmo)
        rho = rho or rho_k
        assert rho_k["best"] == rho["best"], "pages must share rho"
        offset = 1000 * k  # page-qualified group index; single-WMO maps keep the raw MOGI index
        for g in tiled:
            groups.append((g, g["index"] + offset))
        tile_total += sum(len(g["tiles"]) for g in tiled)
        depth = max(depth, wmo["floors"]["maxStackDepth"])
        if paged:
            floors.append({"floor": k + 1, "uiMapID": None, "source": "wmo-page", "groups": [g["index"] + offset for g in tiled],
                           "frame": fr(wmo),
                           "label": labels[k] if labels else None})
        else:
            floors = chosen_floors(load_floors(report["mapID"]), {g["index"]: g for g in tiled})
    out = ["    [%d] = {" % report["mapID"],
           "        instanceID = %d, worldMapID = %d, displayName = %s," % (
               report["mapID"], report["mapID"], json.dumps(report["name"])),
           '        sourceType = "blizzard-wmo-minimap", verified = false, status = "candidate",',
           "        rho = %s, logicalBlockWidth = %d, logicalBlockHeight = %d, tileCount = %d," % (
               num(rho["best"]), STRIDE, STRIDE, tile_total),
           "        stackDepth = %d, floorSource = %s,%s" % (depth, json.dumps(floors[0]["source"]),
                                                           (" floorNoun = %s," % json.dumps(noun)) if noun else ""),
           "        provenance = {",
           provenance(report, ['            rootFileDataID = %d, rootMD5 = "%s", rootPath = %s,' % (
               roots[0], wmos[0]["rootMD5"], json.dumps(wmos[0]["rootPath"]))]
               + (['            pageRoots = { %s },' % ", ".join(str(r) for r in roots)] if paged else [])),
           "        },"]
    if not paged:  # world-frame placement of the WMO: lets the addon project a world position onto the canvas
        out.append("        frame = %s," % fr(wmos[0]))
    out.append("        groups = {")
    for g, index in groups:
        tiles = ", ".join("{ %d, %d, %d, %d, %d }" % (t["fileDataID"], t["x"], t["y"], t["width"], t["height"])
                          for t in g["tiles"])
        out.append("            { index = %d, minimum = { %s }, maximum = { %s }, tiles = { %s } }," % (
            index, ", ".join(num(v) for v in g["minimum"]), ", ".join(num(v) for v in g["maximum"]), tiles))
    out.append("        },")
    if len(floors) > 1:
        out.append("        floors = {")
        for f in floors:
            out.append("            { floor = %d,%s%s%s groups = { %s } }," % (
                f["floor"], (" uiMapID = %d," % f["uiMapID"]) if f["uiMapID"] else "",
                (" label = %s," % json.dumps(f["label"])) if f.get("label") else "",
                (" frame = %s," % f["frame"]) if f.get("frame") else "", ", ".join(str(i) for i in f["groups"])))
        out.append("        },")
    return "\n".join(out + ["    },"])


def ground_entry(report, crop=None):
    content = [t for t in report["ground"]["tiles"] if t["uniform"] is False]
    if not content:
        raise SystemExit("Map %d has no non-uniform ground tiles" % report["mapID"])
    sizes = {(t["width"], t["height"]) for t in content}
    if len(sizes) != 1 or next(iter(sizes))[0] != next(iter(sizes))[1]:
        raise SystemExit("Map %d ground tiles are not one square size: %s" % (report["mapID"], sizes))
    size = next(iter(sizes))[0]
    xs, ys = [t["x"] for t in content], [t["y"] for t in content]
    out = ["    [%d] = {" % report["mapID"],
           "        instanceID = %d, worldMapID = %d, displayName = %s," % (
               report["mapID"], report["mapID"], json.dumps(report["name"])),
           '        sourceType = "blizzard-ground-minimap", verified = false, status = "candidate",',
           "        tileSize = %d, gridMinX = %d, gridMinY = %d, columns = %d, rows = %d, tileCount = %d," % (
               size, min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, len(content))]
    if crop:  # the dungeon is a part of the terrain grid, in grid pixels
        out.append("        crop = { x = %d, y = %d, width = %d, height = %d }," % (crop["x"], crop["y"], crop["width"], crop["height"]))
    out += [
           "        provenance = {",
           provenance(report, ['            note = "ADT minimap textures from the WDT MAID table; blank backdrop tiles excluded.",']),
           "        },",
           "        tiles = {"]
    for t in content:
        out.append("            { %d, %d, %d }," % (t["fileDataID"], t["x"], t["y"]))
    return "\n".join(out + ["        },", "    },"])


def generate():
    with open(os.path.join(HERE, "registry-manifest.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    blocks = []
    for item in sorted(manifest["entries"], key=lambda e: e["instanceID"]):
        report = load(item["instanceID"])
        if item["source"] == "ground":
            blocks.append(ground_entry(report, item.get("crop")))
        else:
            blocks.append(wmo_entry(report, item.get("wmoRoots") or [item["wmoRoot"]], item.get("floorNoun"), item.get("floorLabels")))
    return ("-- GENERATED by scripts/Generate-Registry.py from scripts/generated/discovery/*.json. DO NOT EDIT.\n"
            "-- Entries are candidates (verified = false) until visually accepted in-game; see CHANGELOG.\n"
            "local _, ns = ...\nns.GeneratedMaps = {\n" + "\n".join(blocks) + "\n}\n"
            "-- Known Forever dungeons without a generated map yet (shown by /dlmap list).\n"
            "ns.UnavailableMaps = {\n" + "".join(
                "    [%d] = { name = %s, reason = %s },\n" % (u["instanceID"], json.dumps(u["name"]), json.dumps(u["reason"]))
                for u in sorted(manifest.get("unavailable", []), key=lambda u: u["instanceID"])) + "}\n")


def boss_data():
    """BossData.lua: placed bosses (and unplaced names) for every dungeon that has a generated map."""
    lines = ["-- GENERATED by scripts/Generate-Registry.py from scripts/generated/bosses/*.json. DO NOT EDIT.",
             "-- Statuses: verified-client | verified-source-registration | approximate | unresolved (no x/y).",
             "-- Full per-boss provenance: scripts/BOSS-PROVENANCE.md and scripts/generated/bosses/<id>.json.",
             "local _, ns = ...", "ns.GeneratedBosses = {"]
    with open(os.path.join(HERE, "registry-manifest.json"), encoding="utf-8") as handle:
        manifest_ids = [e["instanceID"] for e in json.load(handle)["entries"]]  # ground maps too: bosses listed without positions
    for map_id in sorted(manifest_ids + [389]):
        path = os.path.join(HERE, "generated", "bosses", "%d.json" % map_id)
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if not data["bosses"]:
            continue
        lines.append("    [%d] = {" % map_id)
        lines.append("        identity = %s, positions = %s," % (json.dumps("DungeonEncounter.db2 build " + data["foreverBuild"]),
                     json.dumps("public server spawn DB + Blizzard retail Journal pins, registered to the Blizzard-native layout")))
        lines.append("        layouts = { %s }," % ", ".join("[%s] = %s" % (k, json.dumps(v)) for k, v in sorted(data["layouts"].items())))
        lines.append("        bosses = {")
        for b in data["bosses"]:
            parts = ["id = %d" % b["id"], "name = %s" % json.dumps(b["name"]), "status = %s" % json.dumps(b["status"])]
            if "x" in b and b["status"] != "unresolved":
                parts += ["floor = %d" % b["floor"], "x = %s" % num(b["x"]), "y = %s" % num(b["y"]),
                          "confidence = %s" % json.dumps(b["confidence"])]
            lines.append("            { %s }," % ", ".join(parts))
        lines += ["        },", "    },"]
    lines.append("}")
    return "\n".join(lines) + "\n"


def check_rfc():
    """Rediscovered RFC 389 data must equal the hand-verified MapRegistry.lua entry."""
    wmo = load(389)["wmos"][0]
    with open(os.path.join(ROOT, "MapRegistry.lua"), encoding="utf-8") as handle:
        text = handle.read()
    registry = re.findall(r"\{ (\d{6}), (\d), (\d), (\d+), (\d+) \}", text)
    found = [tuple(str(v) for v in (t["fileDataID"], t["x"], t["y"], t["width"], t["height"]))
             for g in wmo["groups"] for t in g["tiles"]]
    assert sorted(found) == sorted(registry), "RFC tile tuples differ from MapRegistry.lua"
    assert wmo["rootMD5"] == "18c9698976d1d0935ceb10f1f42674dd" and wmo["rho"]["best"] == 2
    bounds = re.findall(r"minimum = \{ ([-\d.]+), ([-\d.]+), ([-\d.]+) \},\s*maximum = \{ ([-\d.]+), ([-\d.]+), ([-\d.]+) \}", text)
    ours = [tuple(g["minimum"] + g["maximum"]) for g in wmo["groups"] if g["tiles"]]
    assert len(bounds) == len(ours) == 12
    for a, b in zip(bounds, ours):
        assert all(math.isclose(float(x), y, rel_tol=1e-6, abs_tol=1e-4) for x, y in zip(a, b)), (a, b)
    print("RFC 389 cross-check OK: 19 tiles, 12 group bounds, rho=2, root MD5 identical to the hand-verified registry.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = generate()
    outputs = {os.path.join(ROOT, "MapData.lua"): text, os.path.join(ROOT, "BossData.lua"): boss_data()}
    if args.check:
        check_rfc()
        for target, expected in outputs.items():
            with open(target, encoding="utf-8") as handle:
                assert handle.read() == expected, os.path.basename(target) + " is stale; rerun Generate-Registry.py"
        print("MapData.lua and BossData.lua are current.")
    else:
        for target, content in outputs.items():
            with open(target, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(content)
            print("wrote", target, len(content), "bytes")
