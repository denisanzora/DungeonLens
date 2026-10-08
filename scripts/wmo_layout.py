"""Python mirror of WMOComposition.lua (canonical WMO layout) plus world<->canvas projection.

Used by the offline tooling only (previews, boss registration). The Lua file stays the single
source of truth at runtime; scripts/MultiDungeonSmoke.lua and Verify-Layout.py compare the two.

Canvas pixels: x right, y down, origin = top-left of the bounding box of the group's logical
256 px cells. A world/WMO-local point (wx, wy) lands at
    px = wx * rho - minX          py = maxY - wy * rho
(derived from tile.cellX = absX - minX and tile.cellY = maxY - stride - absY).
"""

import io
import math

STRIDE = 256


def canonical_layout(wmo, rho=2, group_indexes=None):
    """Tiles of the chosen groups (all tiled groups by default), z-sorted like the Lua."""
    groups = [g for g in wmo["groups"] if g["tiles"] and (group_indexes is None or g["index"] in group_indexes)]
    groups.sort(key=lambda g: (g["minimum"][2], g["index"]))
    tiles, min_x, min_y, max_x, max_y = [], math.inf, math.inf, -math.inf, -math.inf
    for rank, g in enumerate(groups, 1):
        raw_x, raw_y = g["minimum"][0] * rho, g["minimum"][1] * rho
        for t in g["tiles"]:
            abs_x, abs_y = raw_x + t["x"] * STRIDE, raw_y + t["y"] * STRIDE
            tiles.append({"fileDataID": t["fileDataID"], "absX": abs_x, "absY": abs_y, "width": t["width"],
                          "height": t["height"], "group": g["index"], "z": g["minimum"][2], "rank": rank})
            min_x, min_y = min(min_x, abs_x), min(min_y, abs_y)
            max_x, max_y = max(max_x, abs_x + STRIDE), max(max_y, abs_y + STRIDE)
    if not tiles:
        return None
    for t in tiles:
        t["x"] = t["absX"] - min_x
        t["y"] = (max_y - STRIDE - t["absY"]) + (STRIDE - t["height"])
    return {"rho": rho, "minX": min_x, "maxY": max_y, "width": max_x - min_x, "height": max_y - min_y,
            "tiles": tiles, "groups": [g["index"] for g in groups]}


def ground_layout(ground, crop=None):
    content = [t for t in ground["tiles"] if t.get("uniform") is False]
    size = content[0]["width"]
    xs, ys = [t["x"] for t in content], [t["y"] for t in content]
    cw, ch = (max(xs) - min(xs) + 1) * size, (max(ys) - min(ys) + 1) * size
    cx, cy = 0, 0
    if crop:
        cx, cy, cw, ch = crop["x"], crop["y"], crop["width"], crop["height"]
    tiles = []
    for t in content:
        col, row = t["x"] - min(xs), t["y"] - min(ys)
        left, top = max(col * size, cx), max(row * size, cy)
        right, bottom = min((col + 1) * size, cx + cw), min((row + 1) * size, cy + ch)
        if right > left and bottom > top:
            tiles.append({"fileDataID": t["fileDataID"], "x": left - cx, "y": top - cy, "width": right - left, "height": bottom - top,
                          "group": None, "z": 0, "rank": 0, "src": (left - col * size, top - row * size, right - col * size, bottom - row * size)})
    return {"rho": None, "width": cw, "height": ch, "tiles": tiles, "groups": []}


def world_to_canvas(layout, wx, wy):
    return wx * layout["rho"] - layout["minX"], layout["maxY"] - wy * layout["rho"]


def canvas_to_world(layout, px, py):
    return (px + layout["minX"]) / layout["rho"], (layout["maxY"] - py) / layout["rho"]


def render(wago, layout, background=(0, 0, 0, 255)):
    from PIL import Image
    sheet = Image.new("RGBA", (int(math.ceil(layout["width"])), int(math.ceil(layout["height"]))), background)
    for t in layout["tiles"]:
        blob = wago.file(t["fileDataID"])
        if blob:
            tile = Image.open(io.BytesIO(blob)).convert("RGBA")
            if t.get("src"):  # cropped ground tile: paste only the visible part
                tile = tile.crop(t["src"])
            sheet.alpha_composite(tile, (int(round(t["x"])), int(round(t["y"]))))
    return sheet


def content_mask(wago, layout):
    """Boolean-ish L image: 255 where any tile paints a non-transparent pixel."""
    from PIL import Image
    sheet = render(wago, layout, background=(0, 0, 0, 0))
    return sheet.getchannel("A").point(lambda v: 255 if v > 8 else 0)
