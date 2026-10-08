# Boss / entrance marker authoring

Markers are drawn by `Overlay.lua` in **normalized map space**: `(0,0)` is the top-left of the
rendered map canvas and `(1,1)` its bottom-right, independent of window size. The canvas is the
bounding box of the composed tiles, so coordinates are tied to a **layout signature**
(`wmo:<w>x<h>:<tiles>` / `ground:<w>x<h>:<tiles>`, from `WMOComposition:Signature`). If the map
layout ever changes, markers with the old signature are not drawn.

## Provenance rules

- Boss/entrance coordinates are facts about *Forever*, which can alter legacy dungeons. They are
  authored on the live client with the tool below and recorded with who/when/build.
- No coordinates, art or code are imported from other addons or databases.
- Boss data now ships: `BossData.lua` is **generated** (`Build-Bosses.py` -> `Generate-Registry.py`) from Forever's DungeonEncounter table plus
  public spawn data and Blizzard retail Journal pins, registered to the layout; see `BOSS-PROVENANCE.md`. Statuses are
  `verified-client` > `verified-source-registration` (high/medium) > `approximate` (development only) > `unresolved`.
- `MarkerData.lua` holds the hand-written layer: entries confirmed in-game with the tool below (status `verified-client`) replace the
  generated record for the same boss id. Schema uses one layout signature **per floor**: `layouts = { [1] = "wmo:...:f1", ... }`.

## Workflow (development mode)

1. Open the dungeon: `/dlmap show <name|id>` works from anywhere (or `/dlmap` inside it). Authoring uses the displayed floor.
2. `/dlmap author on` - prints the layout signature and enables click capture.
3. `/dlmap author boss Hogger`, then click the map where the boss is (a plain click records `Point N`).
   `/dlmap author entrance`, then click for the entrance.
4. Each click prints `x=0.4123 y=0.2231` and a paste-ready line; the marker appears at once and is
   stored in SavedVariables (`DungeonLensDB.authoring[instanceID]`, tagged with the signature).
5. `/dlmap author list` prints every point as `MarkerData.lua` lines; `undo`, `clear`, `off` also exist. Replace the printed `id`
   (a running number) with the boss's DungeonEncounter ID from `BOSS-PROVENANCE.md` so the hand-verified record overrides the generated one.
6. Paste the lines into `MarkerData.lua`:

```lua
[34] = {
    layouts = { [1] = "wmo:531x795:26" }, source = "in-game authoring, <name>, <date>", verifiedBuild = "1.60.1.70245",
    entrance = { name = "Entrance", floor = 1, x = 0.5000, y = 0.9000, status = "verified-client" },
    bosses = { { id = 2756, name = "Targorr the Dread", floor = 1, x = 0.4123, y = 0.2231, status = "verified-client" } },
},
```

Authoring points (yellow) never leave SavedVariables and are stored per floor signature; shipped boss markers use the built-in raid-target skull.
Every marker has a `floor` (default 1) and the overlay draws only the current floor's markers. Floors are Blizzard's own for Gnomeregan (4),
Shadowfang Keep (7), Blackfathom Deeps (3), Uldaman (2) and the four Scarlet Monastery wings; other dungeons have one floor.
