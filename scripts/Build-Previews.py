"""Offline visual QA: render every dungeon (every floor) with boss pins, plus a contact sheet.

The layouts and boss markers are NOT recomputed here: they are taken from the real addon Lua running
under Lua 5.1 (dl_common.lua_report), so previews show exactly what /dlmap draws. Tiles come from the
exact-build Blizzard data (cached under scripts/.cache, git-ignored). Output defaults to ./previews
(git-ignored: it contains Blizzard artwork and must never be committed or shipped).

    python scripts/Build-Previews.py                 # previews/index.html + one PNG per dungeon/floor
    python scripts/Build-Previews.py --out D:\\qa     # elsewhere
"""

import argparse
import html
import io
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago, slug  # noqa: E402
from dl_common import FOREVER_BUILD, load, lua_report  # noqa: E402
import wmo_layout as L  # noqa: E402

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("Pillow is required: pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAPS = [389, 3065, 2999, 43, 36, 33, 34, 48, 90, 47, 189, 129, 70, 2998]
MAX_EDGE = 1400
STATUS_COLOR = {"verified-client": (60, 200, 90), "verified-source-registration": (220, 40, 40),
                "approximate": (255, 160, 30)}


def font(size):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def compose(wago, layout_tiles, width, height):
    sheet = Image.new("RGBA", (int(math.ceil(width)), int(math.ceil(height))), (6, 8, 12, 255))
    for t in layout_tiles:  # list order == draw order (ascending min-Z), as in the addon
        blob = wago.file(t["fdid"])
        if blob:
            tile = Image.open(io.BytesIO(blob)).convert("RGBA")
            uv = t.get("uv")
            if uv and tuple(uv) != (0, 0, 1, 1):  # cropped ground tile: draw only the visible part (u0, v0, u1, v1)
                tile = tile.crop((round(uv[0] * tile.width), round(uv[1] * tile.height), round(uv[2] * tile.width), round(uv[3] * tile.height)))
            sheet.alpha_composite(tile, (int(round(t["x"])), int(round(t["y"]))))
    return sheet


def fit(sheet):
    if max(sheet.size) > MAX_EDGE:
        f = MAX_EDGE / max(sheet.size)
        sheet = sheet.resize((max(1, int(sheet.width * f)), max(1, int(sheet.height * f))), Image.LANCZOS)
    return sheet


def draw_pins(sheet, bosses, floor, number_offset=0):
    """Pins in normalized coordinates of this floor's canvas; labels outlined, placed to avoid overlaps."""
    draw = ImageDraw.Draw(sheet)
    radius = max(9, int(min(sheet.size) / 55))
    label_font = font(max(12, int(radius * 1.35)))
    pins = []
    for index, boss in enumerate(bosses, 1):
        if boss.get("x") is None or boss.get("status") == "unresolved" or (boss.get("floor") or 1) != floor:
            continue
        pins.append((index, boss, boss["x"] * sheet.width, boss["y"] * sheet.height))
    boxes = [(x - radius, y - radius, x + radius, y + radius) for _, _, x, y in pins]

    def free(box, own):
        return (box[0] >= 0 and box[1] >= 0 and box[2] <= sheet.width and box[3] <= sheet.height and
                all(box[2] < o[0] or box[0] > o[2] or box[3] < o[1] or box[1] > o[3] for i, o in enumerate(boxes) if i != own))
    drawn = []
    for slot, (index, boss, x, y) in enumerate(pins):
        color = STATUS_COLOR.get(boss["status"], (200, 200, 200))
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (235,), outline=(255, 255, 255), width=2)
        draw.text((x, y), str(index), fill=(255, 255, 255), font=font(max(10, int(radius * 1.1))), anchor="mm", stroke_width=1,
                  stroke_fill=(0, 0, 0))
        label = boss["name"] + ("  (approx.)" if boss["status"] == "approximate" else "")
        w, h = draw.textlength(label, font=label_font), label_font.size * 1.2
        gap = radius + 4
        options = [("lm", (x + gap, y), (x + gap, y - h / 2, x + gap + w, y + h / 2)),
                   ("rm", (x - gap, y), (x - gap - w, y - h / 2, x - gap, y + h / 2)),
                   ("mb", (x, y - gap), (x - w / 2, y - gap - h, x + w / 2, y - gap)),
                   ("mt", (x, y + gap), (x - w / 2, y + gap, x + w / 2, y + gap + h))]
        choice = next((o for o in options if free(o[2], slot)), options[0])
        draw.text(choice[1], label, fill=(255, 255, 255), font=label_font, anchor=choice[0], stroke_width=2, stroke_fill=(0, 0, 0))
        boxes.append(choice[2])
        drawn.append(boss["name"])
    return drawn


def page_previews(wago, discovery, out, map_id):
    """Maps that are not generated: show each placed WMO as its own page (unplaced), for human review."""
    pages = []
    for wmo in sorted(discovery["wmos"], key=lambda w: -sum(len(g["tiles"]) for g in w["groups"])):
        tiles = sum(len(g["tiles"]) for g in wmo["groups"])
        if tiles < 6:
            continue
        layout = L.canonical_layout(wmo, (wmo.get("rho") or {}).get("best") or 2)
        sheet = fit(L.render(wago, layout, background=(6, 8, 12, 255)))
        name = "%d-%s-page-%d.png" % (map_id, slug(discovery["name"]), len(pages) + 1)
        sheet.convert("RGB").save(os.path.join(out, name))
        pages.append({"file": name, "caption": "%s - %d tiles, yaw %s" % (
            (wmo.get("rootPath") or str(wmo["rootFileDataID"])).split("/")[-1], tiles,
            wmo["placements"][0]["rotation"][1] if wmo.get("placements") else 0)})
    return pages


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join(ROOT, "previews"))
    args = parser.parse_args()
    out = args.out
    os.makedirs(out, exist_ok=True)
    for stale in os.listdir(out):  # never leave images from a previous layout behind
        if stale.endswith((".png", ".html")):
            os.remove(os.path.join(out, stale))
    wago = Wago(FOREVER_BUILD)
    report = lua_report()
    by_id = {}
    for row in report["layouts"]:
        by_id.setdefault(row["id"], []).append(row)
    cards = []
    for map_id in MAPS:
        discovery = load("discovery/%d.json" % map_id)
        bosses_json = load("bosses/%d.json" % map_id)
        floors_json = load("floors/%d.json" % map_id)
        entry = report["entries"].get(map_id)
        card = {"id": map_id, "name": discovery["name"], "images": [], "warnings": [], "bosses": bosses_json["bosses"],
                "notes": bosses_json.get("notes", []), "entry": entry}
        base = "%d-%s" % (map_id, slug(discovery["name"]))
        if entry:
            lua_bosses = report["bosses"].get(map_id, [])
            for layout in sorted(by_id[map_id], key=lambda r: r["floor"]):
                tiles = [{"fdid": t[0], "x": t[1], "y": t[2], "w": t[3], "h": t[4], "uv": t[6:10] if len(t) >= 10 else None}
                         for t in layout["tiles"]]
                sheet = fit(compose(wago, tiles, layout["width"], layout["height"]))
                # pins only when the live signature matches, exactly like the addon
                valid = [b for b in lua_bosses if b.get("layout") == layout["signature"]]
                drawn = draw_pins(sheet, lua_bosses and valid, layout["floor"]) if valid else []
                name = base + ("-floor-%d" % layout["floor"] if entry["floors"] > 1 else "") + ".png"
                sheet.convert("RGB").save(os.path.join(out, name))
                card["images"].append({"file": name, "caption": ("Floor %d of %d" % (layout["floor"], entry["floors"])
                                                                if entry["floors"] > 1 else "Single floor"),
                                       "signature": layout["signature"], "pins": drawn, "tiles": len(tiles)})
            if entry["stackDepth"] > 1 and entry["floors"] == 1:
                card["warnings"].append("%d vertically stacked WMO-group levels are drawn flattened (no Blizzard floor data for this layout)"
                                        % entry["stackDepth"])
            if map_id == 36:
                card["warnings"].append("incomplete: the ship area (Smite, Greenskin, Cookie, VanCleef) has no minimap tiles in build 70245; "
                                        "second WMO az_deadmines_d (6 tiles) omitted")
            if map_id == 189:
                card["warnings"].append("each wing is its own page (separate WMOs ~1000 yd apart), as in Blizzard's own per-wing maps")
            if map_id == 43:
                card["warnings"].append("Forever's Wailing Caverns WMO is new; Blizzard's retail floor/pin data does not apply")
            if not entry["verified"]:
                card["warnings"].append("candidate: generated from client data, not yet accepted in-game")
        else:
            card["pages"] = page_previews(wago, discovery, out, map_id)
            ground = discovery.get("ground") or {}
            if ground.get("contentTileCount"):
                sheet = fit(L.render(wago, L.ground_layout(ground), background=(6, 8, 12, 255)))
                name = "%d-%s-ground-reference.png" % (map_id, slug(discovery["name"]))
                sheet.convert("RGB").save(os.path.join(out, name))
                card["pages"].append({"file": name, "caption": "ground-tile reference: outdoor terrain scenario with %d content tiles "
                                      "(contains artefacts: a broken tile top-left, duplicated tiles bottom-right)" % ground["contentTileCount"]})
            card["warnings"].append("NOT GENERATED: no single dungeon map identified (many small cave WMOs + ground tiles)")
        if floors_json.get("status") == "no-retail-floor-data" and entry and entry["floors"] == 1 and entry["stackDepth"] > 1:
            card["warnings"].append("no Blizzard floor data: floor separation unverified")
        counts = {}
        for b in bosses_json["bosses"]:
            counts[b["status"]] = counts.get(b["status"], 0) + 1
        card["counts"] = counts
        cards.append(card)
        print("%5d %-26s images=%d pages=%d warnings=%d" % (map_id, discovery["name"], len(card["images"]), len(card.get("pages", [])),
                                                         len(card["warnings"])))
    write_index(out, cards)


def badge(text, kind="neutral"):
    return '<span class="badge %s">%s</span>' % (kind, html.escape(text))


def loot_cell(row):
    """Expandable loot list for one boss (outside the PNGs, which stay uncluttered)."""
    if row is None or not (row["items"] or row["unverifiedItems"]):
        return "<em>No verified loot yet</em>"
    parts = []
    for item in row["items"]:
        parts.append("<li><b>%s</b> <small>#%d - %s - %s%s</small></li>" % (
            html.escape(item["name"]), item["itemID"], html.escape(item["slot"]), html.escape(item["confidence"]),
            " - Forever-new" if item["foreverNew"] else ""))
    body = "<ul class='loot'>%s</ul>" % "".join(parts) if parts else "<em>no verified items</em>"
    if row["unverifiedItems"]:
        body += "<div class='unv'>Listed for Forever but ID unverified (not shipped): %s</div>" % html.escape(
            ", ".join(u["name"] for u in row["unverifiedItems"]))
    return "<details><summary>Loot (%d)%s</summary>%s</details>" % (len(row["items"]), " + unverified" if row["unverifiedItems"] else "", body)


def write_index(out, cards):
    loot_rows = {(r["map"], r["encounterID"]): r for r in json.load(open(os.path.join(HERE, "generated", "loot", "all.json"), encoding="utf-8"))}
    rows = []
    for c in cards:
        e = c["entry"]
        status = ("ACCEPTED" if e and e["verified"] else "candidate") if e else "not generated"
        source = ({"blizzard-wmo-minimap": "WMO minimap", "blizzard-ground-minimap": "ground minimap"}[e["sourceType"]]) if e else "-"
        counts = c["counts"]
        placed = counts.get("verified-source-registration", 0) + counts.get("verified-client", 0)
        total = len(c["bosses"])
        head = "".join([
            badge(status, "ok" if e and e["verified"] else ("warn" if e else "bad")),
            badge(source), badge("%d floor%s" % (e["floors"], "" if e["floors"] == 1 else "s") if e else "pages"),
            badge("bosses: %d/%d verified-source, %d approximate, %d unresolved" % (
                placed, total, counts.get("approximate", 0), counts.get("unresolved", 0)),
                "ok" if placed == total and total else ("warn" if placed else "bad"))])
        imgs = "".join('<figure><a href="%s"><img loading="lazy" src="%s"></a><figcaption>%s<br><small>%s%s</small></figcaption></figure>' % (
            html.escape(i["file"]), html.escape(i["file"]), html.escape(i["caption"]),
            html.escape(i["signature"] + " - %d tiles" % i["tiles"]),
            (" - pins: " + html.escape(", ".join(i["pins"]))) if i["pins"] else "") for i in c["images"])
        imgs += "".join('<figure class="page"><a href="%s"><img loading="lazy" src="%s"></a><figcaption>unplaced page: %s</figcaption></figure>'
                        % (html.escape(p["file"]), html.escape(p["file"]), html.escape(p["caption"])) for p in c.get("pages", []))
        warn = "".join("<li>%s</li>" % html.escape(w) for w in c["warnings"])
        table = ["<table><tr><th>#</th><th>Boss</th><th>Status</th><th>Conf.</th><th>Floor</th><th>x, y</th><th>Sources / notes</th><th>Loot</th></tr>"]
        for n, b in enumerate(c["bosses"], 1):
            srcs = []
            for s in b.get("sources", []):
                if s["type"] == "server-spawn-db":
                    srcs.append("spawn DB (%d row%s)" % (s["spawnRows"], "" if s["spawnRows"] == 1 else "s"))
                else:
                    srcs.append("retail Journal pin")
            if "agreementYards" in b:
                srcs.append("agree %.0f yd" % b["agreementYards"])
            srcs += b.get("notes", [])
            table.append("<tr class='%s'><td>%d</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
                b["status"], n, html.escape(b["name"]), html.escape(b["status"]), html.escape(b["confidence"]),
                b.get("floor", "-"), ("%.3f, %.3f" % (b["x"], b["y"])) if "x" in b and b["status"] != "unresolved" else "-",
                html.escape("; ".join(srcs)), loot_cell(loot_rows.get((c["id"], b["id"])))))
        table.append("</table>")
        rows.append('<section id="m%d"><h2>%s <small>InstanceID %d</small></h2><div class="badges">%s</div>%s<div class="figs">%s</div>'
                    '<details open><summary>Bosses, provenance and loot (%d)</summary>%s</details></section>' % (
                        c["id"], html.escape(c["name"]), c["id"], head, ("<ul class='warn'>%s</ul>" % warn) if warn else "", imgs,
                        total, "".join(table)))
    nav = " ".join('<a href="#m%d">%s</a>' % (c["id"], html.escape(c["name"])) for c in cards)
    generated = sum(1 for c in cards if c["entry"])
    placed_any = sum(1 for c in cards if c["counts"].get("verified-source-registration", 0) + c["counts"].get("verified-client", 0))
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DungeonLens map QA</title><style>
:root{color-scheme:dark;--bg:#0b0e14;--card:#131824;--fg:#dfe6f2;--mut:#8b97ab;--ok:#2e9e57;--warn:#d68a1c;--bad:#c0392b}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,Segoe UI,sans-serif}
header{padding:20px 24px;border-bottom:1px solid #222a3a}h1{margin:0 0 6px;font-size:22px}p{margin:4px 0;color:var(--mut)}
nav{padding:10px 24px;display:flex;flex-wrap:wrap;gap:6px 14px;position:sticky;top:0;background:var(--bg);border-bottom:1px solid #222a3a;z-index:5}
nav a{color:#8db4ff;text-decoration:none;font-size:13px}section{margin:18px 24px;padding:16px;background:var(--card);border-radius:10px}
h2{margin:0 0 8px;font-size:18px}h2 small{color:var(--mut);font-weight:400;font-size:13px;margin-left:8px}
.badge{display:inline-block;padding:2px 9px;border-radius:99px;background:#243049;margin:0 6px 6px 0;font-size:12px}
.badge.ok{background:var(--ok)}.badge.warn{background:var(--warn);color:#161000}.badge.bad{background:var(--bad)}
.warn{margin:6px 0 10px;padding-left:20px;color:#ffc76b}.figs{display:flex;flex-wrap:wrap;gap:14px;margin:10px 0}
figure{margin:0;max-width:640px}figure img{max-width:100%;height:auto;border-radius:6px;background:#06080c;display:block}
figcaption{color:var(--mut);font-size:12px;margin-top:4px}figure.page img{opacity:.85}
table{border-collapse:collapse;width:100%;margin-top:8px;font-size:12.5px}th,td{padding:4px 8px;border-bottom:1px solid #222a3a;text-align:left;vertical-align:top}
ul.loot{margin:4px 0;padding-left:18px}.unv{color:#ffc76b;font-size:12px}tr.approximate td{color:#ffc76b}tr.unresolved td{color:#ff8a80}summary{cursor:pointer;color:#8db4ff}
</style></head><body><header><h1>DungeonLens map QA - build @@BUILD@@</h1>
<p>@@GEN@@ of 14 Forever dungeons have generated maps; @@PLACED@@ have boss markers. Previews are rendered from the addon's own Lua layout and Blizzard
exact-build tiles - no need to enter a dungeon to check static layout. Red pins = source-registered, orange = approximate (development only).</p>
<p>Open any of these in game from anywhere: <code>/dlmap list</code>, <code>/dlmap show &lt;id|name&gt;</code>, or the Dungeons dropdown.</p></header>
<nav>@@NAV@@</nav>@@ROWS@@</body></html>"""
    page = (page.replace("@@BUILD@@", FOREVER_BUILD).replace("@@GEN@@", str(generated)).replace("@@PLACED@@", str(placed_any))
            .replace("@@NAV@@", nav).replace("@@ROWS@@", "".join(rows)))
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    print("wrote", os.path.join(out, "index.html"))


if __name__ == "__main__":
    main()
