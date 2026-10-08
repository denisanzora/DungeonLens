"""Resolve scraped Forever loot (item NAMES) to numeric itemIDs and join them to boss/encounter identities.

Item IDs are resolved ONLY against Blizzard client tables:
  * Forever build 1.60.1.70245 `Item` (an ID must exist here), names from Forever `ItemSparse`;
  * names missing there (Forever's export omits ~12.6k names) fall back to Classic Era 1.15.9.70003 `ItemSparse`.
A name must map to exactly one ID after filtering by quality and inventory slot; ambiguous or unknown names are NOT guessed:
they are recorded as unresolved and never shipped.

Bosses are joined to the encounter identity used by BossData.lua (DungeonEncounter ID) by normalized name (+ explicit aliases).

    python scripts/Resolve-Loot.py     -> generated/loot/<map>.json, generated/loot/summary.json
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wago_client import Wago  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
BIG = 200 * 1024 * 1024
QUALITY = {"poor": 0, "common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5}
# site slot word -> acceptable InventoryType values (Blizzard enum)
SLOTS = {"head": {1}, "neck": {2}, "shoulder": {3}, "shirt": {4}, "chest": {5, 20}, "waist": {6}, "legs": {7}, "feet": {8},
         "wrist": {9}, "hands": {10}, "finger": {11}, "trinket": {12}, "one-hand": {13}, "main hand": {13, 21}, "off hand": {13, 22, 14, 23},
         "shield": {14}, "back": {16}, "two-hand": {17}, "held in off-hand": {23}, "ranged": {15, 25, 26}, "wand": {26}, "thrown": {25},
         "relic": {28}, "ammo": {24}, "bag": {18}, "tabard": {19}}
# Forever encounter name <-> source boss name differences (normalized). Anything not listed must match exactly.
ALIASES = {"gelihast": ["geilhast"], "sneedsshredder": ["sneed"], "baelog": ["thelostdwarves"], "erictheswift": ["thelostdwarves"],
           "olaf": ["thelostdwarves"]}  # source name (normalized) -> Forever encounter names it contributes to


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def main():
    forever, era = Wago("1.60.1.70245"), Wago("1.15.9.70003")
    f_item = {r["ID"]: r for r in forever.db2("Item", limit=BIG)}
    f_sparse = {r["ID"]: r for r in forever.db2("ItemSparse", limit=BIG)}
    e_sparse = {r["ID"]: r for r in era.db2("ItemSparse", limit=BIG)}
    names = {}
    for source, table in (("forever", f_sparse), ("classic-era", e_sparse)):
        for item_id, row in table.items():
            if item_id in f_item:
                names.setdefault(norm(row["Display_lang"]), {}).setdefault(item_id, (source, row))

    def candidates(name, quality, slot):
        """IDs for a name. Quality is compared only against FOREVER's own rows: Classic Era rows carry Classic quality,
        and Forever has revised dungeon item quality (e.g. Cursed Felblade: green in Classic, blue in Forever)."""
        pool = names.get(norm(name), {})
        word = slot.split(",")[0].strip().lower()
        slot_ok = [(i, o, r) for i, (o, r) in pool.items() if word not in SLOTS or int(f_item[i]["InventoryType"]) in SLOTS[word]]
        forever_q = [c for c in slot_ok if c[1] == "forever" and int(c[2]["OverallQualityID"]) == QUALITY.get(quality, -1)]
        if len(forever_q) == 1:
            return forever_q  # Forever's own row agrees with the Forever page (also resolves old-vs-reissued duplicates)
        if forever_q:
            return forever_q
        return [c for c in slot_ok if c[1] != "forever" or QUALITY.get(quality) is None]

    # name -> itemID taken from foreverdb.net item links (Forever-new items have no name in the client tables). An ID is only used when it
    # exists in Forever's Item table and its InventoryType fits the slot the loot listing gives; it also breaks Classic-vs-reissue ties.
    with open(os.path.join(GEN, "loot", "foreverdb-ids.json"), encoding="utf-8") as handle:
        fdb_ids = {norm(name): int(item_id) for name, item_id in json.load(handle)["ids"].items()}

    def foreverdb_candidate(name, slot, found):
        item_id = fdb_ids.get(norm(name))
        if item_id is None:
            return None
        if found:  # name is known to the client tables: only accept the foreverdb ID if it is one of the candidates
            return next((c for c in found if int(c[0]) == item_id), None)
        row = f_item.get(item_id) if item_id in f_item else f_item.get(str(item_id))
        word = slot.split(",")[0].strip().lower()
        if row is None or (word in SLOTS and int(row["InventoryType"]) not in SLOTS[word]):
            return None
        return (item_id, "foreverdb", None)

    # boss identities (the same ones BossData.lua uses)
    boss_ids = {}
    for path in os.listdir(os.path.join(GEN, "bosses")):
        data = json.load(open(os.path.join(GEN, "bosses", path), encoding="utf-8"))
        boss_ids[data["mapID"]] = {norm(b["name"]): b for b in data["bosses"]}

    summary = {"maps": {}}
    for path in sorted(os.listdir(os.path.join(GEN, "loot"))):
        if not path.startswith("source-"):
            continue
        source = json.load(open(os.path.join(GEN, "loot", path), encoding="utf-8"))
        map_id = source["map"]
        known = boss_ids.get(map_id, {})
        result = {"map": map_id, "source": source["source"], "bosses": [], "unmatchedSourceBosses": [], "unresolvedItems": []}
        matched = set()
        for page in source["pages"]:
            for entry in page["bosses"]:
                if entry["boss"] is None:
                    continue  # dungeon-wide / unattributed lists are not boss loot
                key = norm(entry["boss"])
                boss = known.get(key)
                for alias in ALIASES.get(key, []):
                    boss = boss or known.get(alias)
                if boss is None and key == "geilhast":
                    boss = known.get("gelihast")
                if boss is None:
                    result["unmatchedSourceBosses"].append({"boss": entry["boss"], "items": len(entry["items"]), "page": page["slug"]})
                    continue
                matched.add(boss["id"])
                items = []
                for item in entry["items"]:
                    found = candidates(item["name"], item["quality"], item["slot"])
                    # Classic ID vs Forever reissue (2173xx) of the same name/slot, neither with a Forever name row to decide: the
                    # listing marks the item as not Forever-new, so take the original Classic ID (the one foreverdb.net lists).
                    old = [c for c in found if int(c[0]) < 100000]
                    if len(found) == 2 and len(old) == 1 and not item["forever_new"] and all(int(c[0]) >= 217000 for c in found if c not in old):
                        found = old
                    fdb = foreverdb_candidate(item["name"], item["slot"], found)
                    if fdb is not None:
                        found = [fdb]
                    if len(found) == 1:
                        item_id, origin, row = found[0]
                        items.append({"itemID": int(item_id), "name": item["name"], "slot": item["slot"], "quality": item["quality"],
                                      "foreverNew": item["forever_new"], "sourcePercent": item["sourcePercent"],
                                      "idSource": ("foreverdb.net item link + Forever Item table (exists, slot fits)" if origin == "foreverdb"
                                                     else "Forever Item table + %s item name" % origin)})
                    else:
                        result["unresolvedItems"].append({"boss": entry["boss"], "name": item["name"], "reason":
                                                          "no ID in client tables" if not found else "ambiguous: %s" % [c[0] for c in found]})
                result["bosses"].append({"encounterID": boss["id"], "boss": boss["name"], "sourceBoss": entry["boss"], "page": page["slug"],
                                         "sourceItemCount": len(entry["items"]), "items": items})
        result["bossesWithoutSourceEntry"] = [b["name"] for b in known.values() if b["id"] not in matched]
        with open(os.path.join(GEN, "loot", "%d.json" % map_id), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(result, handle, indent=1, sort_keys=True)
            handle.write("\n")
        placed = sum(1 for b in result["bosses"] if b["items"])
        summary["maps"][map_id] = {"bossesWithLoot": placed, "items": sum(len(b["items"]) for b in result["bosses"]),
                                   "unresolvedItems": len(result["unresolvedItems"]), "unmatchedSourceBosses": len(result["unmatchedSourceBosses"]),
                                   "bossesWithoutSourceEntry": len(result["bossesWithoutSourceEntry"])}
        print(map_id, summary["maps"][map_id], "| unmatched source bosses:", [b["boss"] for b in result["unmatchedSourceBosses"]],
              "| no source entry:", result["bossesWithoutSourceEntry"])
        for u in result["unresolvedItems"]:
            print("      unresolved:", u)
    with open(os.path.join(GEN, "loot", "summary.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(summary, handle, indent=1, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main()
