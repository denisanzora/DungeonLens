# DungeonLens

A dungeon browser for **World of Warcraft: Forever** (beta 1.60.1, Interface 16001). Open it from the minimap and see every Forever
dungeon: its map, bosses, loot, recommended levels and where the entrance is - from anywhere in the world, without entering the dungeon.

> Not affiliated with or endorsed by Blizzard Entertainment. DungeonLens bundles no Blizzard artwork: maps are drawn from your own
> game client's minimap files at runtime.

## Features

- **Minimap button** - left-click opens/closes the browser, right-click opens the map of the dungeon you are standing in, drag to move it.
- **All 14 Forever dungeons** with their recommended level range (Lv 13-18 ... Lv 41-51). Thirteen have maps; Excavation Site: Wetlands
  stays in the list as "Unavailable" until a usable map exists.
- **Dungeon maps** with floor / wing navigation where the dungeon has several levels (Gnomeregan, Shadowfang Keep, Blackfathom Deeps,
  Uldaman, Scarlet Monastery). Built from the client's own minimap art.
- **ENTRANCE card** (top left of a map): the zone and coordinates of the entrance, and **Show on world map**, which opens that zone's
  world map and places a map pin.
- **BOSSES table** (top right): every boss in the dungeon with how many loot items are known. Click a boss (or its marker on the map)
  to see its loot; hover an item for the normal in-game tooltip.
- **Boss markers** on the map for the dungeons where positions are known.
- **Learns from your play** (see below): bosses you have looted get a marker, and items you have seen drop appear under **SEEN BY YOU**.

## Installation

1. Download the latest `DungeonLens-x.y.z.zip` from the [Releases](../../releases) page.
2. Unzip it so the `DungeonLens` folder ends up in your Forever install's AddOns directory, for example
   `World of Warcraft\_classic_beta_\Interface\AddOns\DungeonLens`. The file `DungeonLens.toc` must sit directly inside that folder.
3. Start the game and make sure DungeonLens is enabled in the AddOns list. Click the minimap button or type `/dlmap`.

## Commands

| Command | Action |
| --- | --- |
| `/dlmap` | Open the dungeon browser (the minimap button does the same). |
| `/dlmap minimap on` / `off` / `reset` | Show, hide, or reset the position of the minimap button. |
| `/dlmap show <name or id>` | Open a dungeon's map directly, e.g. `/dlmap show Deadmines`. |
| `/dlmap list`, `/dlmap floor <n>`, `/dlmap close` | List dungeons, change floor, close the window. |
| `/dlmap lootexport` | Print the loot items and boss positions the addon has learned from your kills (see below). |
| `/dlmap debug` | Technical status, useful for bug reports. |

Developer commands (`/dlmap author`, `probe`, `player`, `scan`, `approximate`, `candidates`) are described in `scripts/MANUAL-TESTS.md`.

## How it learns, and how you can help

Some Forever-only content has no published data yet, so DungeonLens records what it sees while you play. Everything stays in your own
saved variables; nothing is sent anywhere.

- **Loot:** when you kill a boss and loot its corpse, the items are saved for that boss and listed under **SEEN BY YOU** in its loot panel.
- **Boss positions:** the spot where you looted a boss is saved, and bosses without a verified marker get a blue-tinted marker there.
- **Sharing:** run `/dlmap lootexport` and send the output (with the dungeon name) to the maintainer. That is how unverified items and
  missing boss positions get turned into verified data in the next release.

## Known limitations

- **Maps are generated from client data and checked offline**; most have not been visually accepted in the game yet. If a map looks
  wrong (blank or solid-green tiles, wrong orientation, wrong crop), report the dungeon, your build and the `/dlmap debug` output.
- **Loot is only shown where its item IDs could be verified.** Bosses without verified loot show "No verified loot yet". No drop rates are
  shown, because the available sources do not measure them for Forever.
- **Boss markers:** The Hall of Thanes and Ruins of Lordaeron have no verified boss positions yet (only the ones you learn by looting).
- **Entrances** come from the client's own corpse-run positions. Ruins of Lordaeron's is inferred from a new Forever trigger, and The Hall of
  Thanes is zone-level only (Ironforge).
- Built for Forever **1.60.1** (build 70245). On other builds the addon tries the same file IDs and shows a message if they fail to load.
- Whether `UnitPosition` and boss-kill events behave the same in every Forever dungeon is still being confirmed; if markers or loot are not
  learned after a kill, please report it.

## Credits and data sources

DungeonLens source is original. Facts it relies on come from public sources, used as data only:

- **Wago.Tools** - exports of the game's client tables (maps, UI map bounds, boss encounters, item tables).
- **foreverdb.net** - dungeon level ranges and Forever item IDs; **wowtbc.gg** - Forever boss loot listings;
  **wowforever.wclbox.com** - cross-checking.
- **AzerothCore** - creature spawn coordinates used to place boss markers (facts only; no code or database is redistributed).
- **Blizzard Entertainment** - the game, its client data and artwork, referenced by file ID at runtime.

Provenance for every dataset is in `scripts/`: [loot](scripts/LOOT-PROVENANCE.md), [bosses](scripts/BOSS-PROVENANCE.md),
[dungeons](scripts/DUNGEON-INVENTORY.md), [floors](scripts/FLOOR-INVESTIGATION.md), [frame proof](scripts/FRAME-FIT.md).

## Development

The repository root is the installable addon folder; there are no external runtime dependencies or libraries. To work on it with live
reloads, link it into the game with `scripts/Install-Dev.ps1` (pass `-GamePath "X:\World of Warcraft\_classic_beta_"` if needed) and use `/reload`.

```powershell
python -m pip install lupa==2.6
python .\scripts\Validate.py              # Lua 5.1 smoke tests with synthetic WoW API stubs (use --multi-only etc. for focused runs)
python .\scripts\Verify-Layout.py         # Python layout mirror vs the Lua layout
python .\scripts\Build-Previews.py        # offline previews of every map (writes previews/, git-ignored: contains Blizzard art)
```

Generated data (`MapData.lua`, `BossData.lua`, `LootData.lua`, `DungeonEntrances.lua`) is built by the scripts in `scripts/`
(`Generate-Registry.py`, `Build-Bosses.py`, `Build-Loot.py`, `Build-Entrances.py`). Raw inputs that are not stored in the repository -
creature spawn dumps and scraped loot pages - are recreated with `scripts/External-Spawns.py` and `scripts/Scrape-Loot.py`.
The in-game acceptance checklist is `scripts/MANUAL-TESTS.md`; API findings are in `scripts/API-NOTES.md`.

### Release packaging

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1 -CheckOnly        # verify the ZIP payload only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1 -InGameValidated   # write dist/DungeonLens-<version>.zip
```

The archive is an explicit allowlist of the addon's runtime files under `DungeonLens/`; scripts, notes and generated research data are
excluded, and the script verifies entry names and SHA256 payloads.

## License

MIT - see [LICENSE](LICENSE). Game data and artwork remain the property of Blizzard Entertainment.
