"""Developer preview: render discovered minimap tiles to PNG files (Pillow required).

Reads scripts/generated/discovery/<mapID>.json, fetches the BLP bytes for that exact build
into the git-ignored scripts/.cache, and composes them with the SAME canonical WMO layout
as WMOComposition.lua (per-group raw origin = MOGI min * rho, 256-px logical cells, Y flip,
ascending min-Z draw order) or the ground grid (x right, y down).

Output goes to --out (default: the system temp dir). Previews are for human review only and
must never be committed or shipped: they contain Blizzard artwork.

    python scripts/Preview-Map.py 36 --out C:\\temp\\previews
"""

import argparse
import io
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago, installed_build  # noqa: E402

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Pillow is required for previews: pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
STRIDE = 256


def load_tile(wago, fdid):
    blob = wago.file(fdid)
    if blob is None:
        return None
    return Image.open(io.BytesIO(blob)).convert("RGBA")


def render_ground(wago, ground):
    b = ground["bounds"]
    size = max(t["width"] for t in ground["tiles"])
    sheet = Image.new("RGBA", (ground["gridColumns"] * size, ground["gridRows"] * size), (0, 0, 0, 255))
    for t in ground["tiles"]:
        img = load_tile(wago, t["fileDataID"])
        if img:
            sheet.alpha_composite(img, ((t["x"] - b["minX"]) * size, (t["y"] - b["minY"]) * size))
    return sheet


def wmo_layout(wmo, rho):
    tiles, minx, miny, maxx, maxy = [], 1e18, 1e18, -1e18, -1e18
    ordered = sorted((g for g in wmo["groups"] if g["tiles"]), key=lambda g: (g["minimum"][2], g["index"]))
    for g in ordered:
        for t in g["tiles"]:
            ax = g["minimum"][0] * rho + t["x"] * STRIDE
            ay = g["minimum"][1] * rho + t["y"] * STRIDE
            tiles.append((ax, ay, t))
            minx, miny = min(minx, ax), min(miny, ay)
            maxx, maxy = max(maxx, ax + STRIDE), max(maxy, ay + STRIDE)
    return tiles, minx, miny, maxx, maxy


def render_wmo(wago, wmo, rho=2, scale=1.0):
    tiles, minx, miny, maxx, maxy = wmo_layout(wmo, rho)
    sheet = Image.new("RGBA", (int(maxx - minx), int(maxy - miny)), (0, 0, 0, 255))
    for ax, ay, t in tiles:
        img = load_tile(wago, t["fileDataID"])
        if not img:
            continue
        x = ax - minx
        y = (maxy - STRIDE - ay) + (STRIDE - t["height"])
        sheet.alpha_composite(img, (int(round(x)), int(round(y))))
    if scale != 1.0:
        sheet = sheet.resize((max(1, int(sheet.width * scale)), max(1, int(sheet.height * scale))))
    return sheet


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("map_id", type=int)
    parser.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "dungeonlens-previews"))
    parser.add_argument("--wmo", type=int, help="only this root WMO FileDataID")
    parser.add_argument("--max-edge", type=int, default=2200)
    args = parser.parse_args()
    report = json.load(open(os.path.join(HERE, "generated", "discovery", "%d.json" % args.map_id), encoding="utf-8"))
    wago = Wago(report["build"])
    os.makedirs(args.out, exist_ok=True)

    def save(img, name):
        if max(img.size) > args.max_edge:
            f = args.max_edge / max(img.size)
            img = img.resize((int(img.width * f), int(img.height * f)))
        path = os.path.join(args.out, name)
        img.convert("RGB").save(path)
        print(path, img.size)

    if report.get("ground") and report["ground"]["tileCount"] and not args.wmo:
        save(render_ground(wago, report["ground"]), "%d-ground.png" % args.map_id)
    for wmo in report["wmos"]:
        if args.wmo and wmo["rootFileDataID"] != args.wmo:
            continue
        if sum(len(g["tiles"]) for g in wmo["groups"]) < 6 and not args.wmo:
            continue  # skip tiny filler buildings in bulk mode
        rho = (wmo.get("rho") or {}).get("best") or 2
        save(render_wmo(wago, wmo, rho), "%d-wmo-%d.png" % (args.map_id, wmo["rootFileDataID"]))


if __name__ == "__main__":
    main()
