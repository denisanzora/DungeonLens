# Ruins of Lordaeron map-source investigation

Date: 2026-09-30. Target: Forever **1.60.1.70124**, Interface **16001**.
This is research plus temporary diagnostics. The ordinary viewer still uses its
native UiMap renderer and existing fallback message. No permanent map registry,
map asset, M integration or release archive is introduced by this iteration.

## 1. Actual client evidence supplied by the user

Inside **Ruins of Lordaeron**:

| Value | Observed result |
| --- | --- |
| `IsInInstance()` | true, party |
| `GetInstanceInfo()` name / return 8 | Ruins of Lordaeron / **2999** |
| `C_Map.GetBestMapForUnit("player")` | nil |
| Detector current UiMap / render map | nil / nil |
| Ordinary viewer | Correct missing-native-map message |

This is a missing-UiMap-selection case, not failure to render valid UiMap art.
The original detector does not call child/group APIs without a UiMapID; empty
diagnostic relations therefore do not establish that no other UiMap exists.

## 2. Identifier namespaces

- **InstanceID / world MapID:** `GetInstanceInfo()` return 8 identifies the
  running dungeon's map definition. Public client `Map.db2` independently
  identifies **Map.ID 2999** as the Forever dungeon. This is not a unique copy,
  group session, or saved-instance lockout ID.
- **UiMapID:** `C_Map.GetMapInfo(id).mapID` belongs to `UiMap.db2`. It identifies
  a UI map, possibly a zone, floor, orphan map or different UI system. The field
  name `mapID` does not turn it into a world MapID.
- **UiMapArtID:** identifies artwork for a UiMap. It is neither ID above.
- **FileDataID:** identifies an individual CASC file, such as a WDT or BLP.
- `Map.db2.MapType` and `UiMap.db2.Type` are different enums. Map 2999's
  `MapType=1` is not `Enum.UIMapType.World` evidence.

The future render registry should be keyed by the observed **InstanceID**.
Never feed 2999 to a UiMap-argument API because it is an InstanceID. The scanner
skips this numeric collision unless a current UiMap-returning API or returned
hierarchy record independently establishes that number as a UiMapID.

## 3. Build-specific DB2 discovery

Read-only public client-data exports from Wago.Tools were inspected and audited
with `python .\scripts\Inspect-MapMetadata.py`. This script uses only the Python
standard library, fetches CSV/file metadata, prints JSON to stdout, and never
downloads artwork or executable code. These are community-hosted Blizzard data
exports, not an official Blizzard API or local CASC extraction.

The unfiltered **1.60.1.70124** exports contain:

- **60 UiMap rows**, maximum UiMapID **2665**.
- **Zero Dungeon-type UiMaps**, and no row named Ruins of Lordaeron.
- **61 UiMapAssignment rows**, all joining an exported UiMap.
- **Zero assignments with world MapID 2999**.
- Positive controls: Azeroth UiMap 947 and Durotar UiMap 1411 assigned to world
  Map 1 are present. Empty filtered responses alone were not used as proof.

**Conclusion:** no corresponding Ruins of Lordaeron dungeon UiMap exists in
these build-specific base DB2 exports. The on-client scan remains necessary to
check for runtime/hotfix differences. This is stronger evidence than a nil
best-map result, but is not a claim to have enumerated every possible client
hotfix or future build.

### Credible-looking records that must not be substituted

| UiMapID | Name | Type / parent | DB2 art ID | Identity evidence / decision |
| --- | --- | --- | --- | --- |
| **908** | Ruins of Lordaeron | Orphan 6 / parent 13 in Mainline 12.1.5.69848 | 933 in that Mainline build | Absent from Forever's UiMap export. Exact Mainline assignment links to **world Map 1760**, directory `LordaeronScenario`; reject for dungeon 2999. |
| **1420** | Tirisfal Glades | Zone 3 / parent 1415 in Forever | 2126 | Assignment points to **world Map 0**, Area 85; outdoor geography, not dungeon 2999. |
| **1458** | Undercity | Zone 3 / parent 1415 in Forever | 2163 | Assignment points to **world Map 0**, Area 1497; city geography, not dungeon 2999. |

The historical **world Map 572**, directory **`PVPLordaeron`**, is the Ruins of
Lordaeron **arena** (`InstanceType=4`) in Mainline. It is not a UiMapID or the
Forever dungeon. Do not describe UiMap 908 as that arena: the inspected modern
assignment for 908 actually points to the separate scenario map 1760.

Art IDs above are DB2 metadata, **not observed Forever C_Map returns**. Actual
`GetMapArtLayers` / `GetMapArtLayerTextures` behavior for the probe candidates has
not yet been sampled in this client. `/dlmap scan` reports those results rather
than claiming that the metadata is drawable.

### Temporary UiMap scan

`/dlmap scan`:

1. Captures build, locale, running InstanceID, best UiMap and the independent
   `C_Minimap.GetUiMapID()` result, all guarded.
2. Queries `GetMapChildrenInfo(root, nil, true)` for roots actually supplied by
   best-map/minimap/fallback-world-map APIs; no root is guessed from InstanceID.
3. Probes UiMap IDs **1..4096** in finite batches of 50, using one-shot timers.
   This covers the complete published 70124 ID range, including orphans.
   Returned hierarchy IDs beyond that range are also inspected.
4. Reports every Dungeon-type, current/minimap, localized-name-match or
   Lordaeron-name candidate, plus the three explicit reference checks above
   when the running InstanceID is 2999. Each report includes UiMapID, name,
   type, parent, art ID, layer dimensions and returned positive texture IDs.
5. If available, samples `GetWorldPosFromMapPos(candidateUiMapID, center)`.
   Its `continentID` return is a **world Map/InstanceID**, including valid 0.
   This samples map metadata, not player coordinates, and never auto-selects a map.
6. Retains one diagnostic snapshot at `DungeonLensDB.diagnostics.lastScan`.
   It is never consumed by the detector or renderer.

The scan stops when finished, explicitly cancelled, or the instance identity
changes. There is no continuous polling. Errors/restrictions and scan scope are
reported; a bounded scan alone is not proof of global absence. A matching name
and drawable artwork are not sufficient identity evidence.

## 4. World Map 2999 and native minimap files

The exact `Map.db2` row for **1.60.1.70124** reports:

```text
ID              2999
Directory       2999
MapName         Ruins of Lordaeron
MapType         1
InstanceType    1 (party)
ParentMapID     -1
WdtFileDataID   7255103
```

The file catalog independently resolves **7255103** to:

```text
world/maps/2999/2999.wdt
```

It also lists exactly **nine** normal minimap BLPs under the matching directory,
with Forever-beta file history. These identifiers were read from metadata, not
constructed from guessed paths or taken from another addon's registry:

| Tile X | Tile Y | FileDataID | Blizzard logical filename |
| --- | --- | --- | --- |
| 30 | 27 | **7255712** | `world/minimaps/2999/map30_27.blp` |
| 31 | 27 | **7255718** | `world/minimaps/2999/map31_27.blp` |
| 32 | 27 | **7255724** | `world/minimaps/2999/map32_27.blp` |
| 30 | 28 | **7255730** | `world/minimaps/2999/map30_28.blp` |
| 31 | 28 | **7255736** | `world/minimaps/2999/map31_28.blp` |
| 32 | 28 | **7255742** | `world/minimaps/2999/map32_28.blp` |
| 30 | 29 | **7255748** | `world/minimaps/2999/map30_29.blp` |
| 31 | 29 | **7255754** | `world/minimaps/2999/map31_29.blp` |
| 32 | 29 | **7255760** | `world/minimaps/2999/map32_29.blp` |

Known tile-coordinate footprint: **X 30..32, Y 27..29**, a complete **3×3** grid;
half-open tile bounds **[30,33) × [27,30)**. There are no holes in that catalog
rectangle. File history records initial versions in build 69876 and changes to
six tiles in build 70009; it is a history/catalog, not a per-build membership
manifest. Current local presence and loadability are still unverified.

**Not yet established:** BLP native pixel widths/heights, current content hashes,
WDT MAIN/MAID associations, verified screen-axis orientation, visible-art crop,
playable bounds, or any WMO interior/floor overlays. Do not label this footprint
as exact dungeon playable bounds. The standard ADT tile size is 1600/3 yards;
a 3×3 rectangle would span 1600×1600 yards if that standard ground layout applies.
That format-derived calculation is not a verified dungeon coordinate transform.

## 5. Storage and direct Lua rendering

Modern WoW stores these assets in **CASC**. Lua cannot open arbitrary CASC/DB2/
WDT files, enumerate raw files, decode BLP bytes, or stitch pixels through the
documented addon APIs. `C_Minimap`'s inspected Forever documentation exposes a
UiMapID and view/ground-texture settings, but no raw terrain tile inventory.

The relevant client-data path is:

```text
Map.ID / GetInstanceInfo return 8
  -> Map.WdtFileDataID
  -> WDT MAIN (terrain occupancy) and MAID (file references)
  -> MAID entry's minimapTexture FileDataID
  -> BLP file in CASC
```

WDT `mapTexture` is a separate terrain/LOD texture reference; it must not be
mistaken for `minimapTexture`. MAID has 4096 fixed records with eight uint32 file
references per record. Actual coordinate indexing must be checked against the
extracted WDT and catalog filenames, rather than copying C_Map tile ordering.
WMO-only/interior maps use different minimap/group references and transforms;
those must be discovered separately if required.

**Direct rendering is a viable API route, not yet a runtime-confirmed result.**
`Texture:SetTexture(FileDataID)` can ask the client to load a native BLP without a
UiMap or any bundled copy. Numeric IDs are preferred because modern CASC may
not preserve addressable names. A known logical filename is not proof that Lua
name lookup works. SetTexture's return/recorded ID alone also does not prove
successful asset loading; the documented method often returns true for invalid
IDs, and textures load asynchronously.

`/dlmap scan tiles` therefore opens a temporary **contact sheet** on the
target build, outside combat, selecting the registered current InstanceID.
For InstanceID 2999 it requests the original nine
listed FileDataIDs and one exact-path control for `map31_28.blp`. After two
seconds it samples optional `IsObjectLoaded` / `GetTextureFileID` methods and
saves `DungeonLensDB.diagnostics.lastTileProbe`. It never modifies the normal
map window, selection or SavedVariables geometry. Its 80×80 cells are arbitrary
preview sizes, not claims about native BLP dimensions or a stitched map.
The development-only registry also supports [RFC / InstanceID 389](MAP-DATA-389.md)
using separate WMO group-local panels. The Ruins FileDataIDs and coordinates
listed above have not changed.

## 6. Local CASC access boundary — stopped before installing tools

The installation still reports **1.60.1.70124**. `Data/data/` contains CASC
`data.NNN` archives and `.idx` files. No loose `.wdt` or `Map.db2` was found.
No CASC reader was found on PATH, in the user profile, Program Files locations,
or E: in the searches performed. Python CASC modules checked were unavailable.
**No extractor, executable, package or library was installed this iteration.**

An existing **Pillow 10.2.0 BLP plugin** is present. It could decode/stitch exported
BLPs if their actual encoding is supported; that has not been tested on these
files. CASC file access is the current local extraction blocker.

To resolve exact current dimensions/layout, the required next access is:

- A reviewed **CascLib-based reader** (or CASCExplorer using an appropriate
  reader), explicitly supporting the installed root/product and **FileDataID**
  lookup. CascLib documents `CASC_OPEN_BY_FILEID` and strict data checking.
- Open **`E:\World of Warcraft`**, select product **`wow_classic_beta`**, locale
  **enUS** and the build from `.build.info`. Root includes both `.build.info`
  and `Data/`; `_classic_beta_` alone is not the archive-storage root.
- Read **7255103** and the nine BLP IDs listed above into a separate development
  output directory, never into the client. Inspect WDT MAIN/MAID and BLP2 header
  Width/Height (offsets 0x0C/0x10), and record exact hashes.
- If local UiMap/assignment verification is desired, read their DB2 files with
  a reader supporting the build's WDC layout and WoWDBDefs definitions; include
  applicable hotfix data rather than assuming base DB2 equals all runtime state.

That reader/data access has not been authorized as a new installation. Local
extraction stops here as requested. Public metadata is sufficient to identify
concrete candidates for the client texture probe without installing it.

## 7. Proposed permanent fallback architecture — not implemented

```text
Detect current instance
  GetInstanceInfo() -> instanceID
  |
  +-- valid current Dungeon UiMap + complete native layer?
  |     -> existing C_Map renderer (preferred)
  |
  +-- verified DungeonLensMaps[instanceID] entry for this client/build?
  |     -> render verified client minimap FileDataIDs with recorded geometry
  |        OR render a locally generated map asset, if needed/authorized
  |
  +-- otherwise -> existing no-map message
```

Registry identity is **InstanceID first**. Each entry needs:

- Display name (label only), client flavor, source build(s), verification state.
- Explicit source kind: `client-minimap-filedata`, `native-uimap` when independently
  proved, or `generated-client-minimap`; never infer kind/ID from a name.
- Separately named world MapID, directory, WDT FileDataID/content hash and
  provenance. For this case those first three identifiers are 2999, `2999`, 7255103.
- Actual tile `(x,y,FileDataID)` list, occupancy and tile-coordinate bounds.
- Native image dimensions, axis order/flips/rotation, content pixel extent,
  display aspect and any crop/padding UVs, obtained from data and validated.
- Explicit floor/group identity and transforms if applicable. A terrain tile
  coordinate is not a UiMap floor, and nine tiles do not establish floor count.
- Verified load/visual results and behavior for unsupported/changed builds.

The nine researched IDs are currently held **only in Diagnostics.lua** for the
probe. There is no active `DungeonLensMaps[2999]` entry. Diagnostic snapshots
must never become trusted render metadata automatically.

### Is offline stitching required?

**Not established, and should not be the first choice.** If the tile probe shows
the nine BLPs can load, a validated tile catalog can be distributed as metadata
only; normal UI textures can assemble them at runtime. Offline CASC/WDT auditing
may still be needed to produce correct geometry, but it need not produce artwork.

If direct native loading is genuinely unavailable, our own utility could read
the local WDT and BLPs, decode them, place tiles at verified coordinates, preserve
orientation/crop, and emit a flat map. A conditional proposed output is:

```text
Maps/RuinsOfLordaeron.tga
```

Use a WoW-supported texture format and verified dimensions. For example, choose
power-of-two padded TGA dimensions from the actual stitched content, record
content versus padded size and UVs, and retain the original aspect ratio. No
particular output pixel size is specified yet. A floor/asset set may be necessary
if data establishes interiors; do not flatten overlapping floors by guessing.

Such a utility must record input build/hashes and a reproducible manifest.
It must obtain no other creator's finished image, screenshot, map or addon code.
Generating an image from Blizzard files does **not** make the underlying artwork
ours. Blizzard's addon policy does not establish a blanket extracted-art
redistribution license; any bundled generated asset remains conditional on the
relevant distribution permissions. Direct runtime references avoid bundling
that artwork. No extraction/stitching/distribution permission is claimed here.

## 8. Commands to run now, while still inside Ruins of Lordaeron

```text
/reload
/dlmap scan
```

Wait for **`Scan complete`**, and send its candidate lines and summary. Then,
outside combat:

```text
/dlmap scan tiles
```

Wait at least two seconds. Report which numbered tiles visibly show actual
terrain, which are green/blank, and whether the **path control** matches FileDataID
7255736. Include the one-shot chat samples. The preview can be closed with X/ESC
or `/dlmap scan stop`; that command also cancels an active UiMap scan.

The ordinary `/dlmap` should still show its previous fallback for this dungeon.
The next architecture decision depends on the tile probe's actual rendering,
not on SetTexture returning true.

## Sources

- [Forever Map row 2999](https://wago.tools/db2/Map/csv?build=1.60.1.70124&filter%5BID%5D=2999)
- [Complete Forever UiMap export](https://wago.tools/db2/UiMap/csv?build=1.60.1.70124)
- [Complete Forever UiMapAssignment export](https://wago.tools/db2/UiMapAssignment/csv?build=1.60.1.70124)
- [WDT file metadata](https://wago.tools/files?search=7255103)
- [2999 minimap file metadata](https://wago.tools/files?search=world%2Fminimaps%2F2999%2F)
- [Mainline name-collision UiMap](https://wago.tools/db2/UiMap/csv?build=12.1.5.69848&filter%5BName_lang%5D=Ruins%20of%20Lordaeron)
- [Mainline assignments containing 908 — compare exact numeric IDs](https://wago.tools/db2/UiMapAssignment/csv?build=12.1.5.69848&filter%5BUiMapID%5D=908)
- [Mainline Map 1760](https://wago.tools/db2/Map/csv?build=12.1.5.69848&filter%5BID%5D=1760)
- [Mainline Map query containing 572 — compare exact numeric IDs](https://wago.tools/db2/Map/csv?build=12.1.5.69848&filter%5BID%5D=572)
- [Tirisfal art metadata](https://wago.tools/db2/UiMapXMapArt/csv?build=1.60.1.70124&filter%5BUiMapID%5D=1420)
- [Undercity art metadata](https://wago.tools/db2/UiMapXMapArt/csv?build=1.60.1.70124&filter%5BUiMapID%5D=1458)
- [Mainline 908 art metadata](https://wago.tools/db2/UiMapXMapArt/csv?build=12.1.5.69848&filter%5BUiMapID%5D=908)
- [WoWDBDefs Map definition](https://github.com/wowdev/WoWDBDefs/blob/master/definitions/Map.dbd)
- [WoWDBDefs UiMapAssignment definition](https://github.com/wowdev/WoWDBDefs/blob/master/definitions/UiMapAssignment.dbd)
- [Forever C_Map API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
- [Forever C_Minimap API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MinimapDocumentation.lua)
- [GetWorldPosFromMapPos return namespace](https://warcraft.wiki.gg/wiki/API_C_Map.GetWorldPosFromMapPos)
- [Texture:SetTexture, supported assets and return-value limitation](https://warcraft.wiki.gg/wiki/API_Texture_SetTexture)
- [WDT structure](https://wowdev.wiki/WDT), [ADT layout](https://wowdev.wiki/ADT), [BLP format](https://wowdev.wiki/BLP)
- [CascLib reader/API](https://github.com/ladislav-zezula/CascLib), [FileDataID flags](https://github.com/ladislav-zezula/CascLib/blob/master/src/CascLib.h)
- [Blizzard UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534)
