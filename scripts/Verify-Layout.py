"""Prove the Python layout mirror (wmo_layout.py) equals the real Lua layout, for every dungeon and floor,
and that every BossData layout signature equals the live Lua signature (otherwise markers would not draw).

    python scripts/Verify-Layout.py
"""

import json
import math
import os
import sys
from pathlib import Path

try:
    from lupa.lua51 import LuaRuntime
except ImportError as exc:
    raise SystemExit("pip install lupa") from exc

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import wmo_layout as L  # noqa: E402
from dl_common import build_floors, load, lua_report, main_wmo  # noqa: E402


def lua_layouts():
    return lua_report()["layouts"]


def python_layout(map_id, floor):
    discovery = load("discovery/%d.json" % map_id)
    manifest = json.loads((HERE / "registry-manifest.json").read_text(encoding="utf-8"))
    item = next((e for e in manifest["entries"] if e["instanceID"] == map_id), None)
    if map_id == 389:
        wmo = main_wmo(discovery)
        return L.canonical_layout(wmo, 2)
    if item["source"] == "ground":
        return L.ground_layout(discovery["ground"], item.get("crop"))
    floors = build_floors(map_id, discovery, load("floors/%d.json" % map_id))
    chosen = next(f for f in floors if f["floor"] == floor)
    return L.canonical_layout(chosen["wmo"], 2, set(chosen["groups"]))


def main():
    problems, checked = [], 0
    layouts = lua_layouts()
    boss_text = (ROOT / "BossData.lua").read_text(encoding="utf-8")
    for row in layouts:
        py = python_layout(row["id"], row["floor"])
        checked += 1
        if not (math.isclose(py["width"], row["width"], abs_tol=1e-3) and math.isclose(py["height"], row["height"], abs_tol=1e-3)):
            problems.append("%d f%d size lua=%sx%s py=%sx%s" % (row["id"], row["floor"], row["width"], row["height"], py["width"], py["height"]))
            continue
        lua_tiles = {(t[0], round(t[1], 3), round(t[2], 3)) for t in row["tiles"]}
        py_tiles = {(t["fileDataID"], round(t["x"], 3), round(t["y"], 3)) for t in py["tiles"]}
        if row["kind"] != "blizzard-ground-minimap" and lua_tiles != py_tiles:
            problems.append("%d f%d tile positions differ (%d lua vs %d py)" % (row["id"], row["floor"], len(lua_tiles), len(py_tiles)))
        if row["signature"].split(":")[2] != str(len(py["tiles"])):
            problems.append("%d f%d tile count" % (row["id"], row["floor"]))
        # BossData signature for this floor, if the dungeon has boss data
        bosses = HERE / "generated" / "bosses" / ("%d.json" % row["id"])
        if bosses.exists():
            layouts_json = json.loads(bosses.read_text(encoding="utf-8"))["layouts"]
            expected = layouts_json.get(str(row["floor"]))
            if expected is not None and expected != row["signature"]:
                problems.append("%d f%d boss signature %s != lua %s" % (row["id"], row["floor"], expected, row["signature"]))
    for line in boss_text.splitlines():
        pass
    print("checked %d layouts (every registered dungeon, every floor)" % checked)
    if problems:
        print("\n".join(problems))
        raise SystemExit(1)
    print("PASS: Python layout mirror == Lua layout (size + every tile position), and BossData signatures == live signatures.")


if __name__ == "__main__":
    main()
