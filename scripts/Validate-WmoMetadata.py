"""Focused offline checks of the metadata parser and recorded RFC evidence."""

import importlib.util
import json
from pathlib import Path
import struct
import sys
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True
directory = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("dungeonlens_wmo_metadata", directory / "Inspect-WmoMetadata.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
snapshot = json.loads((directory / "RFC-WMO-70124.json").read_text(encoding="utf-8"))
assert snapshot["build"] == module.BUILD and snapshot["buildConfig"] == module.BUILD_CONFIG
assert snapshot["cdnConfig"] == module.CDN_CONFIG and snapshot["rootFileDataID"] == 109483
assert snapshot["wdtGlobalMODF"]["nameOrFileID"] == snapshot["rootFileDataID"]
assert snapshot["wdtGlobalMODF"]["flags"] & 8
assert snapshot["provenance"]["versionScopedSourceValidated"]
assert snapshot["placement"]["ready"] is False and snapshot["placement"]["productionVerified"] is False
assert snapshot["placement"]["pixelsPerWorldUnit"] == 2 and snapshot["placement"]["developmentCompositeReady"] is True


def chunk(name, data):
    return name.encode("ascii")[::-1] + struct.pack("<I", len(data)) + data


header = bytearray(64)
struct.pack_into("<I", header, 4, 12)
mogi = b"".join(struct.pack("<I6fi", group["flags"], *group["minimum"], *group["maximum"], -1)
                for group in snapshot["groups"])
gfids = struct.pack("<12I", *(group["groupFileDataID"] for group in snapshot["groups"]))
prefix = chunk("MVER", struct.pack("<I", 17)) + chunk("MOHD", header)
fixture = prefix + chunk("MOGI", mogi) + chunk("GFID", gfids)
parsed = module.parse_root(fixture)
assert parsed["groupCount"] == 12
for expected, actual in zip(snapshot["groups"], parsed["groups"]):
    for key in ("groupIndex", "flags", "minimum", "maximum", "groupFileDataID"):
        assert actual[key] == expected[key]
assert parsed["meshBounds"]["minimum"] == snapshot["placement"]["meshMinimum"]
assert parsed["meshBounds"]["maximum"] == snapshot["placement"]["meshMaximum"]


def rejects(callback):
    try:
        callback()
    except ValueError:
        return
    raise AssertionError("Malformed or unverified metadata was accepted")


rejects(lambda: module.chunks(fixture[:-1]))
rejects(lambda: module.chunks(chunk("MVER", b"1234") * 2))
rejects(lambda: module.parse_root(prefix + chunk("MOGI", mogi[:-32])))
bad_mogi = bytearray(mogi)
struct.pack_into("<f", bad_mogi, 4, float("nan"))
rejects(lambda: module.parse_root(prefix + chunk("MOGI", bad_mogi)))
struct.pack_into("<f", bad_mogi, 4, 99999)
rejects(lambda: module.parse_root(prefix + chunk("MOGI", bad_mogi)))
rejects(lambda: module.parse_root(chunk("MVER", struct.pack("<I", 18)) + chunk("MOHD", header) + chunk("MOGI", mogi)))
assert len(snapshot["tileDimensions"]) == 19
for image in snapshot["tileDimensions"]:
    blp_header = b"BLP2" + struct.pack("<I4BII", 1, 2, 8, 7, 1, image["width"], image["height"])
    dimensions = module.parse_blp_header(blp_header)
    assert (dimensions["width"], dimensions["height"]) == (image["width"], image["height"])
rejects(lambda: module.parse_blp_header(blp_header[:19]))

# Independently compare current MOGI extents against stitched native rasters.
dimensions_by_id = {image["fileDataID"]: image for image in snapshot["tileDimensions"]}
rasters = []
def next_power_of_two(value):
    power = 1
    while power < value:
        power *= 2
    return power
for group in snapshot["groups"]:
    tiles = [tile for tile in snapshot["minimapTiles"] if tile["groupIndex"] == group["groupIndex"]]
    width = max(tile["localX"] * 256 + dimensions_by_id[tile["fileDataID"]]["width"] for tile in tiles)
    height = max(tile["localY"] * 256 + dimensions_by_id[tile["fileDataID"]]["height"] for tile in tiles)
    doubled_x = 2 * (group["maximum"][0] - group["minimum"][0])
    doubled_y = 2 * (group["maximum"][1] - group["minimum"][1])
    predicted = (next_power_of_two(doubled_x), next_power_of_two(doubled_y))
    assert (width, height) == predicted, f"Raster relationship failed for group {group['groupIndex']}"
    rasters.append((group["minimum"][0] * 2, group["minimum"][1] * 2, width, height))
    print(f"PASS group {group['groupIndex']:03d}: doubled extent={doubled_x:.9f}x{doubled_y:.9f}, predicted/observed={width}x{height}")
minimum_x, minimum_y = min(row[0] for row in rasters), min(row[1] for row in rasters)
maximum_x, maximum_y = max(row[0] + row[2] for row in rasters), max(row[1] + row[3] for row in rasters)
print(f"Trial raster envelope: min=({minimum_x!r},{minimum_y!r}) max=({maximum_x!r},{maximum_y!r})")
print(f"Normalized dimensions: {maximum_x - minimum_x!r}x{maximum_y - minimum_y!r}")
assert snapshot["placement"]["trialEnvelope"] == {"minX": minimum_x, "minY": minimum_y, "maxX": maximum_x,
    "maxY": maximum_y, "width": maximum_x - minimum_x, "height": maximum_y - minimum_y}

# Canonical extents are independently rebuilt from nineteen logical cells,
# never from native crop dimensions or the prior complete-group envelope.
groups_by_index = {group["groupIndex"]: group for group in snapshot["groups"]}
logical_cells = [(groups_by_index[tile["groupIndex"]]["minimum"][0] * 2 + tile["localX"] * 256,
                  groups_by_index[tile["groupIndex"]]["minimum"][1] * 2 + tile["localY"] * 256)
                 for tile in snapshot["minimapTiles"]]
cell_min_x, cell_min_y = min(cell[0] for cell in logical_cells), min(cell[1] for cell in logical_cells)
cell_max_x, cell_max_y = max(cell[0] + 256 for cell in logical_cells), max(cell[1] + 256 for cell in logical_cells)
canonical_envelope = {"minX": cell_min_x, "minY": cell_min_y, "maxX": cell_max_x, "maxY": cell_max_y,
                      "width": cell_max_x - cell_min_x, "height": cell_max_y - cell_min_y}
assert snapshot["placement"]["canonical"]["logicalEnvelope"] == canonical_envelope
assert snapshot["placement"]["canonical"]["runtimeVerified"] is True
assert snapshot["placement"]["productionRegistryEnabled"] is True and snapshot["placement"]["normalViewerAccepted"] is False
print(f"Canonical logical-cell envelope: {canonical_envelope}; equals prior trial: {canonical_envelope == snapshot['placement']['trialEnvelope']}")

# Verify the exact-version selector and strict header-only read boundary.
requests = []
class Response:
    status = 200
    headers = {}
    def __enter__(self): return self
    def __exit__(self, *_): pass
    def read(self, count):
        assert count == 20, "Header request read beyond image metadata"
        return blp_header
def open_mock(request, timeout):
    requests.append(request)
    return Response()
module.urlopen = open_mock
_, evidence = module.native_file(213074, header_only=True)
assert parse_qs(urlparse(requests[0].full_url).query) == {"version": [module.BUILD]}
assert requests[0].get_header("Range") == "bytes=0-19" and evidence["bytesRead"] == 20
print("PASS: RFC metadata snapshot, twelve MOGI boxes/GFIDs, union bounds, varying BLP sizes, corrupt-data rejection, exact-version selector and header-only access; no network or artwork output.")
