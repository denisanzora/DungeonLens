"""Read-only public client metadata audit. No artwork, binaries or CASC extraction.

Uses Python's standard library. Writes results to stdout only. File-catalog
history is not proof that an asset is present/drawable in the installed build.
"""

import argparse
import csv
import io
import json
import re
from html.parser import HTMLParser
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BUILD = "1.60.1.70124"
sources = []

# Historical WDT association, independently documented; current-build WDT
# membership must still be checked. Never infer a WMO prefix from a map name.
WMO_MINIMAP_PREFIXES = {
    389: "world/minimaps/wmo/dungeon/kl_orgrimmarlavadungeon/lavadungeon_",
}


def fetch(path, parameters):
    url = "https://wago.tools/" + path + "?" + urlencode(parameters)
    sources.append(url)
    request = Request(url, headers={"User-Agent": "DungeonLens-metadata-investigation/0.1"})
    with urlopen(request, timeout=30) as response:
        data = response.read(5 * 1024 * 1024 + 1)
    if len(data) > 5 * 1024 * 1024:
        raise ValueError("Metadata response exceeded the audit size limit")
    return data.decode("utf-8-sig")


def table(name, build=BUILD, **filters):
    text = fetch("db2/" + name + "/csv", {"build": build, **filters})
    if not text.strip():
        return []
    if text.lstrip().startswith("<"):
        raise ValueError("DB2 endpoint returned HTML instead of CSV: " + name)
    return list(csv.DictReader(io.StringIO(text)))


class InertiaPage(HTMLParser):
    page = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "div" and values.get("id") == "app" and "data-page" in values:
            self.page = json.loads(values["data-page"])


def files(search, page_only=None):
    result = []
    for page in ([page_only] if page_only is not None else range(1, 11)):
        parser = InertiaPage()
        parser.feed(fetch("files", {"search": search, "page": page}))
        if parser.page is None:
            raise ValueError("File endpoint has no readable metadata page")
        listing = parser.page["props"]["files"]
        if page_only is not None:
            return listing  # Explicit partial page retains total/next-page evidence.
        result.extend(listing["data"])
        if not listing["next_page_url"]:
            if len(result) != listing["total"]:
                raise ValueError("Incomplete file-catalog pagination")
            return result
    raise ValueError("File metadata pagination limit reached")


def coordinate_grid(tiles):
    coordinates = {(item["tileX"], item["tileY"]) for item in tiles}
    if not coordinates:
        return None
    xs, ys = zip(*coordinates)
    return {"minTileX": min(xs), "maxTileX": max(xs), "minTileY": min(ys), "maxTileY": max(ys),
            "columns": max(xs) - min(xs) + 1, "rows": max(ys) - min(ys) + 1,
            "missingCoordinates": [[x, y] for y in range(min(ys), max(ys) + 1)
                                   for x in range(min(xs), max(xs) + 1) if (x, y) not in coordinates],
            "nativePixelDimensions": None, "installedBuildMembershipVerified": False}


def main(map_id=2999):
    if map_id <= 0:
        raise ValueError("Map ID must be positive")
    world_maps = table("Map", **{"filter[ID]": map_id})
    exact_maps = [row for row in world_maps if int(row["ID"]) == map_id]
    if len(exact_maps) != 1:
        raise ValueError(f"Expected exactly one world Map row for {map_id}")
    world = exact_maps[0]
    ui_maps = table("UiMap")
    assignments = table("UiMapAssignment")
    # Positive controls: a nonempty full table and a known outdoor assignment.
    ui_ids = {int(row["ID"]) for row in ui_maps}
    if 947 not in ui_ids or not any(int(row["UiMapID"]) == 1411 and int(row["MapID"]) == 1 for row in assignments):
        raise ValueError("Full DB2 export positive controls failed; do not infer absence")
    unjoined = sorted({int(row["UiMapID"]) for row in assignments} - ui_ids)
    directory = world["Directory"]
    pattern = re.compile(r"world/minimaps/" + re.escape(directory) + r"/map(\d+)_(\d+)\.blp$", re.I)
    catalog = files("world/minimaps/" + directory + "/")
    prefix = WMO_MINIMAP_PREFIXES.get(map_id)
    wmo_pattern = None
    if not catalog and prefix:
        catalog = files(prefix)
        wmo_pattern = re.compile(re.escape(prefix) + r"(\d+)_(\d+)_(\d+)\.blp$", re.I)
    minimaps = []
    for entry in catalog:
        match = (wmo_pattern or pattern).fullmatch(entry["filename"])
        if match and any(item["product"] == "wow_classic_beta" for item in entry["chashes"]):
            group = int(match[1]) if wmo_pattern else None
            x, y = (int(match[2]), int(match[3])) if wmo_pattern else (int(match[1]), int(match[2]))
            minimaps.append({"fileDataID": entry["fdid"], "path": entry["filename"],
                             "tileX": x, "tileY": y, "wmoGroup": group, "history": entry["chashes"]})
    minimaps.sort(key=lambda item: (item["wmoGroup"] or 0, item["tileY"], item["tileX"]))
    # WMO-local coordinates repeat across groups; there is no global tile grid.
    grid = None if wmo_pattern else coordinate_grid(minimaps)
    group_grids = [{"wmoGroup": group, **coordinate_grid([item for item in minimaps if item["wmoGroup"] == group])}
                   for group in sorted({item["wmoGroup"] for item in minimaps})] if wmo_pattern else []
    wdt_id = int(world["WdtFileDataID"])
    wdt_files = [entry for entry in files(str(wdt_id)) if entry["fdid"] == wdt_id]
    context_ids = {2999: (1420, 1458), 389: (1454,)}.get(map_id, ())
    report = {
        "build": BUILD, "worldMapID": map_id, "worldMap": world,
        "uiMapCount": len(ui_maps), "maxUiMapID": max(ui_ids),
        "dungeonUiMaps": [row for row in ui_maps if int(row["Type"]) == 4],
        "sameNamedUiMaps": [row for row in ui_maps if row["Name_lang"] == world["MapName_lang"]],
        "assignmentCount": len(assignments), "unjoinedAssignmentUiMapIDs": unjoined,
        "assignmentsToWorldMap": [row for row in assignments if int(row["MapID"]) == map_id],
        "contextMaps": [row for row in ui_maps if int(row["ID"]) in context_ids],
        "contextAssignments": [row for row in assignments if int(row["UiMapID"]) in context_ids],
        "wdtFileMetadata": wdt_files, "minimapFileMetadata": minimaps, "grid": grid,
        "minimapLayoutKind": "wmo-group-local" if wmo_pattern else "ground-grid",
        "wmoMinimapPrefix": prefix if wmo_pattern else None, "wmoGroupGrids": group_grids,
        "sources": sources,
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map_id", type=int, nargs="?", default=2999, help="world Map/InstanceID (default: 2999)")
    parser.add_argument("--file-search", help="query only file-catalog metadata; useful for WMO minimap discovery")
    parser.add_argument("--file-page", type=int, help="inspect one explicit catalog page, with pagination metadata")
    args = parser.parse_args()
    if args.file_page is not None and (not args.file_search or args.file_page < 1):
        parser.error("--file-page requires --file-search and a positive page number")
    if args.file_search:
        print(json.dumps({"files": files(args.file_search, args.file_page), "sources": sources}, indent=2))
    else:
        main(args.map_id)
