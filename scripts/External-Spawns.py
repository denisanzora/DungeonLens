"""Extract instance creature spawn coordinates for our dungeons from a public server database dump.

Source (facts only - numbers and names; nothing is redistributed): AzerothCore `acore_world`
tables `creature` and `creature_template` (https://github.com/azerothcore/azerothcore-wotlk).
Its spawn positions are in the instance's world coordinate system, the same frame the WMO/ADT
placement data lives in, so they can be registered against our Blizzard-native composites
mathematically (see Build-Bosses.py).

    python scripts/External-Spawns.py            # downloads (cached) and writes generated/spawns/<map>.json
"""

import json
import os
import re
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache", "external")
OUT = os.path.join(HERE, "generated", "spawns")
BASE = "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/master/data/sql/base/db_world/"
MAPS = {389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70, 2998}


def fetch(name):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        request = urllib.request.Request(BASE + name, headers={"User-Agent": "DungeonLens-discovery/0.3"})
        with urllib.request.urlopen(request, timeout=600) as response, open(path, "wb") as handle:
            handle.write(response.read())
    return path


def columns(text):
    block = text.split("CREATE TABLE", 1)[1].split(") ENGINE", 1)[0].split("(", 1)[1]
    return [m.group(1) for m in re.finditer(r"^\s*`([^`]+)`", block, re.M)]


TOKEN = re.compile(r"'(?:[^'\\]|\\.|'')*'|NULL|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def rows(text):
    """Yield value tuples (as token lists) from every INSERT INTO ... VALUES statement."""
    for statement in re.finditer(r"INSERT INTO `[^`]+` VALUES\s*(.*?);\r?\n", text, re.S):
        body, depth, start, in_str, i = statement.group(1), 0, 0, False, 0
        while i < len(body):
            ch = body[i]
            if in_str:
                if ch == "\\":
                    i += 1
                elif ch == "'":
                    if body[i + 1:i + 2] == "'":
                        i += 1
                    else:
                        in_str = False
            elif ch == "'":
                in_str = True
            elif ch == "(":
                if depth == 0:
                    start = i + 1
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    yield TOKEN.findall(body[start:i])
            i += 1


def unquote(token):
    return token[1:-1].replace("\\'", "'").replace("''", "'") if token.startswith("'") else token


def main():
    template_text = open(fetch("creature_template.sql"), encoding="utf-8", errors="replace").read()
    tcols = columns(template_text)
    id_i, name_i = tcols.index("entry"), tcols.index("name")
    names = {}
    for row in rows(template_text):
        if len(row) == len(tcols):
            names[int(row[id_i])] = unquote(row[name_i])
    text = open(fetch("creature.sql"), encoding="utf-8", errors="replace").read()
    cols = columns(text)
    idx = {name: cols.index(name) for name in ("id1", "map", "position_x", "position_y", "position_z", "orientation")}
    per_map = {m: [] for m in MAPS}
    for row in rows(text):
        if len(row) != len(cols):
            continue
        map_id = int(row[idx["map"]])
        if map_id in MAPS:
            entry = int(row[idx["id1"]])
            per_map[map_id].append({"entry": entry, "name": names.get(entry), "x": float(row[idx["position_x"]]),
                                    "y": float(row[idx["position_y"]]), "z": float(row[idx["position_z"]])})
    os.makedirs(OUT, exist_ok=True)
    for map_id, spawns in per_map.items():
        spawns.sort(key=lambda s: (s["entry"], s["x"], s["y"], s["z"]))
        with open(os.path.join(OUT, "%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump({"map": map_id, "source": "azerothcore-wotlk db_world creature/creature_template (master)",
                       "spawns": spawns}, handle, indent=0, sort_keys=True)
            handle.write("\n")
        print(map_id, len(spawns), "spawns")


if __name__ == "__main__":
    main()
