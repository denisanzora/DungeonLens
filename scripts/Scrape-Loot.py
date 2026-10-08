"""Fetch and parse Forever-specific dungeon loot tables (public factual data) -> generated/loot/source-<slug>.json

Source: wowtbc.gg "Warcraft Forever" loot tables (https://wowtbc.gg/warcraftforever/loot-tables/dungeons/<slug>/), a
Forever-specific database that flags items new to Forever. Only facts (boss, item name, slot, quality, the source's
own drop % and `new` flag) are recorded; no artwork or text is copied. Pages are cached under scripts/.cache/external.

    python scripts/Scrape-Loot.py
"""

import html
import json
import os
import re
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache", "external", "loot")
OUT = os.path.join(HERE, "generated", "loot")
BASE = "https://wowtbc.gg/warcraftforever/loot-tables/dungeons/%s/"
# our MapID -> source page slugs (Scarlet Monastery is one page per wing there)
PAGES = {
    389: ["ragefire-chasm"], 3065: ["hall-of-thanes"], 2999: ["ruins-of-lordaeron"], 43: ["wailing-caverns"],
    36: ["the-deadmines"], 33: ["shadowfang-keep"], 34: ["the-stockade"], 48: ["blackfathom-deeps"], 90: ["gnomeregan"],
    47: ["razorfen-kraul"], 189: ["scarlet-monastery-graveyard", "scarlet-monastery-library", "scarlet-monastery-armory",
                                  "scarlet-monastery-cathedral"],
    129: ["razorfen-downs"], 70: ["uldaman"], 2998: ["excavation-site-wetlands"],
}


def fetch(slug):
    path = os.path.join(CACHE, slug + ".html")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        request = urllib.request.Request(BASE % slug, headers={"User-Agent": "Mozilla/5.0 DungeonLens-research"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        open(path, "wb").write(data)
        time.sleep(2.0)
    return open(path, encoding="utf-8", errors="replace").read()


def strip(text):
    return html.unescape(re.sub(r"<[^>]+>", "", text)).strip()


def parse(page):
    start = page.index("loot__forever__dungeon__title")
    body = page[start:]
    bosses = []
    # boss wrappers
    for wrapper in re.split(r'<div class="database__boss__wrapper">', body)[1:]:
        header = re.search(r'database__boss__wrapper__header">(.*?)</h3>', wrapper)
        boss = {"boss": strip(header.group(1)) if header else None, "items": []}
        for block in re.split(r'<div class="database__item">', wrapper)[1:]:
            name = re.search(r'database__item__name ([a-z]+)">(.*?)</div>', block, re.S)
            slot = re.search(r'database__item__slot">(.*?)(?:<div class="database__item__percent">\(([^)]*)\)</div>)?</div>', block, re.S)
            if not name:
                continue
            raw = name.group(2)
            slot_text = strip(slot.group(1)) if slot else ""
            percent = slot.group(2) if slot and slot.group(2) else None
            boss["items"].append({"name": strip(re.sub(r"<span[^>]*>.*?</span>", "", raw)), "quality": name.group(1),
                                  "forever_new": "forever__new" in raw, "slot": slot_text, "sourcePercent": percent})
        bosses.append(boss)
    return bosses


def main():
    os.makedirs(OUT, exist_ok=True)
    for map_id, slugs in PAGES.items():
        result = {"map": map_id, "source": "wowtbc.gg/warcraftforever", "pages": []}
        for slug in slugs:
            page = fetch(slug)
            result["pages"].append({"slug": slug, "url": BASE % slug, "bosses": parse(page)})
        with open(os.path.join(OUT, "source-%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(result, handle, indent=1, sort_keys=True)
            handle.write("\n")
        print(map_id, [(p["slug"], [(b["boss"], len(b["items"])) for b in p["bosses"]]) for p in result["pages"]])


if __name__ == "__main__":
    main()
