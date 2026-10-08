# Ragefire Chasm / Map 389 — native tile probe evidence

Target build: **Forever 1.60.1.70124**, Interface **16001**.
Investigation began 2026-09-30. RFC's canonical transform is now user-accepted;
an RFC-only production fallback is enabled, with its normal-window test pending.

## Runtime evidence supplied by the user

October 1 incident: [build 70170 resolver evidence](BUILD-70170-REGRESSION.md).
Verification build 70124 is provenance, not a hard runtime requirement. The map
facts below are unchanged; exact-version 70170 metadata comparison found the same
root/WDT hashes, MOGI bounds, group references and nineteen texture header sizes.

- Inside a party instance named **Ragefire Chasm**, `GetInstanceInfo()` return 8
  is **389**.
- `C_Map.GetBestMapForUnit("player")` and `C_Minimap.GetUiMapID()` are both nil.
- `/dlmap scan`: root 947; ID range 1..4096; 60 records; zero candidates;
  4035 nil records; zero errors/restrictions/unavailable calls.
- The scan's numeric collision with InstanceID 389 is deliberately skipped:
  60 + 4035 = 4095 actual record probes. This is not an inferred UiMapID 389.
- Subsequent `/dlmap scan tiles` **visually verified all nineteen numeric IDs
  213056–213074 in this exact build**. Mostly transparent tiles still contained
  legitimate fragments. The path control for `lavadungeon_001_00_00.blp` did not
  visibly render, while numeric FileDataID 213057 did.

**Production representation: numeric FileDataIDs only.** RFC needs no extracted
or bundled BLP/PNG/TGA artwork. The existing path request is a negative diagnostic
control, not an asset-loading fallback or production dependency.

The user subsequently tested screenshots of both complete-group composite
trials (`normal` and `flipy`). **Neither is accepted as correct.** They remain
available for comparison. The subsequent per-logical-cell **canonical** screenshot
has now been accepted as the production-transform candidate. Its math and MOGI
metadata are frozen; the next screenshot target is the clean normal `/dlmap` path.

This agrees with the public base DB2 export: no Ragefire Chasm UiMap and no
UiMapAssignment with world MapID 389. Orgrimmar UiMap 1454 is assigned to world
Map 1 / Area 1637, not the running dungeon.

## Exact build-specific Map record

From the **1.60.1.70124** Map DB2 export, selecting exact numeric ID 389:

| Field | Value |
| --- | --- |
| ID | **389** |
| Directory | **OrgrimmarInstance** |
| MapName | **Ragefire Chasm** |
| MapType | 2 — a Map-table value, not a UiMap-type value |
| InstanceType | 1 (party) |
| AreaTableID | 2437 |
| ParentMapID | -1 |
| WdtFileDataID | **789981** |
| WDT catalog filename | **`world/maps/orgrimmarinstance/orgrimmarinstance.wdt`** |

InstanceID is the current dungeon identity; neither it nor the WDT FileDataID
is passed into a UiMap-argument API by the tile probe.

## Why the Map-directory minimap search is empty

The catalog search under `world/minimaps/OrgrimmarInstance/` returns **zero**
records. That alone does not establish absence of dungeon minimap artwork.

RFC is historically a **global-WMO instance**, rather than an ADT ground map.
Public technical documentation explicitly identifies the OrgrimmarInstance WDT's
WMO reference as:

```text
World/wmo/Dungeon/KL_OrgrimmarLavaDungeon/LavaDungeon.wmo
```

The catalog resolves that path to **FileDataID 109483**. The subsequent exact-build
online WDT inspection described below independently confirms the same FileDataID
in `MODF`, with flag `0x8` identifying a FileDataID reference. The historical
association is now corroborated by version-scoped native client-data bytes,
rather than promoted on name similarity. Local byte-for-byte equality remains
unverified because the installed CASC archives have not been extracted.

Other similarly named data were excluded: `orgrimmarraid/garroshcompound` and
`scenario/ragefire/ragefire_micro` belong to different contexts. Loading-screen,
LFG and `interface/worldmap/ragefire` images were not substituted for minimaps.

## Discovered Blizzard minimap records

Catalog prefix:

```text
world/minimaps/wmo/dungeon/kl_orgrimmarlavadungeon/
```

Exactly **19 BLP image records** were found, plus 19 `.blp.meta` companion
records. The companion metadata files are not textures and are excluded from
the diagnostic image requests.

Filename convention: `lavadungeon_<group>_<X>_<Y>.blp`.
The group is the **filename's WMO group ordinal**, not a UiMap floor or the
global `WMOAreaTable.WMOGroupID` identifier.

| Group | X | Y | FileDataID | Filename relative to the prefix |
| --- | --- | --- | --- | --- |
| 000 | 0 | 0 | **213056** | `lavadungeon_000_00_00.blp` |
| 001 | 0 | 0 | **213057** | `lavadungeon_001_00_00.blp` |
| 001 | 1 | 0 | **213059** | `lavadungeon_001_01_00.blp` |
| 001 | 0 | 1 | **213058** | `lavadungeon_001_00_01.blp` |
| 001 | 1 | 1 | **213060** | `lavadungeon_001_01_01.blp` |
| 002 | 0 | 0 | **213061** | `lavadungeon_002_00_00.blp` |
| 003 | 0 | 0 | **213062** | `lavadungeon_003_00_00.blp` |
| 003 | 0 | 1 | **213063** | `lavadungeon_003_00_01.blp` |
| 004 | 0 | 0 | **213064** | `lavadungeon_004_00_00.blp` |
| 004 | 1 | 0 | **213066** | `lavadungeon_004_01_00.blp` |
| 004 | 0 | 1 | **213065** | `lavadungeon_004_00_01.blp` |
| 004 | 1 | 1 | **213067** | `lavadungeon_004_01_01.blp` |
| 005 | 0 | 0 | **213068** | `lavadungeon_005_00_00.blp` |
| 006 | 0 | 0 | **213069** | `lavadungeon_006_00_00.blp` |
| 007 | 0 | 0 | **213070** | `lavadungeon_007_00_00.blp` |
| 008 | 0 | 0 | **213071** | `lavadungeon_008_00_00.blp` |
| 009 | 0 | 0 | **213072** | `lavadungeon_009_00_00.blp` |
| 010 | 0 | 0 | **213073** | `lavadungeon_010_00_00.blp` |
| 011 | 0 | 0 | **213074** | `lavadungeon_011_00_00.blp` |

### Bounds and sparsity

All coordinates are **group-local** and repeat between groups:

| Groups | Inclusive local bounds | Grid | Missing coordinates |
| --- | --- | --- | --- |
| 000, 002, 005–011 | X 0..0, Y 0..0 | 1×1 each | none |
| 001, 004 | X 0..1, Y 0..1 | 2×2 each | none |
| 003 | X 0..0, Y 0..1 | 1×2 | none |

Each group is a complete rectangle in the catalog. **The entire dungeon is
not a single verified rectangular or sparse global grid.** Collapsing all
nineteen records into X/Y 0..1 would overlap distinct groups incorrectly.
Global arrangement requires the WMO's group bounds (MOGI), applicable minimap
metadata and WDT placement. MOGI and WDT placement have now been read from the
validated version-scoped online source; raster mapping remains unresolved.

The file catalog is cross-product history. These IDs have Classic-family
versions, including 1.13.x, 2.5.x, 3.4.x and 4.4.x; that history does **not** prove
membership in build 1.60.1.70124. In particular, the string `wow_classic_beta`
also identifies older betas. The build-specific Map row is verified; these
native identifiers are additionally runtime-verified by the user. Texture
pathnames are not supported as the RFC production representation.

## Current-build root identity and raw metadata access

Native metadata was obtainable **without installing a CASC reader** using Python's
existing standard library and Wago.Tools' documented CASC endpoint. WDT/WMO bytes
were parsed in memory. For images, only the first **20 header bytes** were read;
no pixel data was inspected and no native artwork/binary file was saved.

Use an exact `version=` selector **without** `product=`. Wago documents `product`
as a latest-build selector; combining them caused the initial invalid-version
control to return a latest file. The corrected exact-version controls passed:

- Provider build **1.60.1.70124**, product `wow_classic_beta`, build config
  **`dd3dfc2881c407299f46c2aaf34c130b`**, CDN config
  **`43061ca8e9f0e2603c8ab50bcae97c2d`** match installed `.build.info`.
- `api/casc/109483?version=0.0.0.0` returns **HTTP 400**.
- The known older selector `version=1.13.0.28211` returns its catalog-matching
  MD5 **`55eb044562adccf8b36251cd2a86b74e`**, different from the target file.
- Target WDT **789981**, MD5 **`9a430840a3bfbce513ff5a529b0de3b2`**, has one
  global MODF: **FileDataID 109483**, flags **8**, position **(0,0,0)** and
  rotation **(0,0,0)**.
- Target root WMO **109483**, format version **17**, is **22,280 bytes**, MD5
  **`18c9698976d1d0935ceb10f1f42674dd`**, SHA256
  **`d111b096f05f3446f8026613333b4357b580b3343e96602410a8e5f6e7379ecd`**.
- Its MOHD declares **12 groups**; MOGI contains **12×32-byte records**. GFID
  explicitly identifies group files **109484–109495** for ordinals 000–011.
  Those IDs were read from GFID, not guessed from numeric adjacency.

This establishes **current-build online-source identity**, separately from local
byte equality. All full-precision metadata and provenance are recorded in
`scripts/RFC-WMO-70124.json`, which contains numbers/identifiers only and is not
an active render registry. Reproduce with `Inspect-WmoMetadata.py`; its
`--provenance-only` mode skips the already-measured image headers.

### MOGI bounds — root WMO object space

MOGI layout is uint32 flags, float32 min XYZ, float32 max XYZ, int32 name offset.
Values below are rounded to six decimals for readability; JSON retains the
full decoded float32 values.

| Group | Flags | Min X, Y, Z | Max X, Y, Z |
| --- | --- | --- | --- |
| 000 | `0x2000` | 66.596527, 4.691049, -43.970795 | 131.312576, 64.364502, 15.422065 |
| 001 | `0x2000` | 131.257034, -49.169914, -66.191437 | 317.361145, 108.500595, 8.461996 |
| 002 | `0x2000` | 63.389111, -106.855865, -24.365713 | 166.056412, 7.274646, 17.773199 |
| 003 | `0x2000` | 313.258759, -275.379059, -22.692408 | 416.285980, -126.526245, 32.186794 |
| 004 | `0x2000` | 161.413620, -266.063202, -39.819386 | 323.405640, -43.014858, 27.142178 |
| 005 | `0xA000` | -88.762314, -62.867249, -12.858303 | 20.272533, 4.349179, 58.909786 |
| 006 | `0xA000` | -63.037991, -188.248672, 26.591841 | -20.569921, -161.153732, 59.433556 |
| 007 | `0xA000` | -26.122662, -186.254425, 21.749601 | -5.730564, -154.523666, 44.537697 |
| 008 | `0xA000` | -97.461899, -159.754181, 3.202124 | 12.013967, -108.500763, 56.489956 |
| 009 | `0xA000` | -102.955666, -83.685333, -10.798361 | 21.380060, -55.481880, 57.293179 |
| 010 | `0xA000` | -99.325745, -116.605148, -7.869864 | 16.067955, -82.644295, 52.620766 |
| 011 | `0x2000` | -16.713949, -7.885947, -24.956156 | 67.561142, 78.933640, 17.044886 |

Union of all twelve mesh boxes in object space:

```text
minimum = (-102.9556655883789, -275.3790588378906, -66.19143676757812)
maximum = ( 416.2859802246094,  108.50059509277344, 59.433555603027344)
XY extent = (519.2416458129883, 383.87965393066406)
```

These are **mesh bounds**, not proven raster origins, padded image bounds or
cropped playable bounds. WDT's shared placement does not supply the per-group
minimap rasterization contract.

### Native minimap dimensions — measured, not assumed

The exact-version BLP2 headers report:

| FileDataID(s) | Width × height |
| --- | --- |
| 213056 | **256×128** |
| 213057–213068 | **256×256** each |
| 213069 | **128×64** |
| 213070 | **64×64** |
| 213071 | **256×128** |
| 213072 | **256×64** |
| 213073 | **256×128** |
| 213074 | **256×256** |

The old square contact-sheet cells were presentation geometry, not native image
dimensions. The composite now preserves each measured native width/height;
it never stretches a group raster to the mesh bounding box.

## Current-build rho evidence — all twelve groups checked

The observed stitched raster uses the maximum of `localX*256 + nativeWidth`
and `localY*256 + nativeHeight` across the group's measured tiles. Independently,
predict each dimension with `nextPowerOfTwo(2 * (meshMax - meshMin))`:

| Group | Doubled mesh extent X×Y | Predicted raster | Observed raster |
| --- | --- | --- | --- |
| 000 | 129.432098×119.346906 | 256×128 | 256×128 |
| 001 | 372.208221×315.341019 | 512×512 | 512×512 |
| 002 | 205.334602×228.261024 | 256×256 | 256×256 |
| 003 | 206.054443×297.705627 | 256×512 | 256×512 |
| 004 | 323.984039×446.096687 | 512×512 | 512×512 |
| 005 | 218.069695×134.432855 | 256×256 | 256×256 |
| 006 | 84.936138×54.189880 | 128×64 | 128×64 |
| 007 | 40.784195×63.461517 | 64×64 | 64×64 |
| 008 | 218.951731×102.506836 | 256×128 | 256×128 |
| 009 | 248.671452×56.406906 | 256×64 | 256×64 |
| 010 | 230.787399×67.921707 | 256×128 | 256×128 |
| 011 | 168.550182×173.639174 | 256×256 | 256×256 |

**12/12 match.** This is strong current-build evidence for the **rho=2 trial**,
derived from our own measured inputs rather than a historical implementation.
It is sufficient to proceed with visual falsification; it does not by itself
prove every origin, orientation, padding or production-use detail.

### Current MIT wow.export corroboration

Inspected `Kruithne/wow.export` main commit
**`c2fd7bde36a712be78a5da896c995b84fbfa2545`**, corresponding to current 0.2.19.
Its `src/js/wmo-minimap.js` reads `WMOMinimapTexture` metadata, uses 2 pixels
per world unit, starts groups at bbox minima multiplied by 2, and adds local
BlockX/BlockY steps of 256. Releases 0.2.18/0.2.19 added WMO preview/export,
world-space JSON sidecars and complete-export fixes.

The implementation was reviewed again at the same pinned commit. Its export
reverses **per-tile** global Y and bottom-left anchors smaller native images in
logical 256-pixel cells. That is not equivalent to either complete-group trial.
DungeonLens now independently reproduces these coordinate semantics in a third
development mode, `canonical`, while keeping unchanged texture UVs. No source
code was copied. Old group-only modes retain their original coordinate behavior.

Source was inspected as a technical reference only. No code, assets or exported
images were incorporated; wow.export was not installed. The user-supplied
historical Cartographer formula is corroboration only, not our data source.

## Implemented development composite transform

The old comparison calculation, now delegated to shared `WMOComposition.lua`, is:

```text
rho = 2
local stride = 256 pixels

groupRawX = MOGI.minimum.x * rho
groupRawY = MOGI.minimum.y * rho
groupWidth  = max(localX*256 + tileNativeWidth)
groupHeight = max(localY*256 + tileNativeHeight)

globalMinX = min(groupRawX)
globalMinY = min(groupRawY)
globalMaxX = max(groupRawX + groupWidth)
globalMaxY = max(groupRawY + groupHeight)

normalizedGroupX = groupRawX - globalMinX
normalGroupY     = groupRawY - globalMinY
flipyGroupY      = globalMaxY - (groupRawY + groupHeight)

tileX = normalizedGroupX + localX*256
tileY = selectedGroupY   + localY*256
```

Raw raster envelope, including actual raster sizes rather than mesh maxima:

```text
minX = -205.9113311767578
minY = -550.7581176757812
maxX =  882.5175170898438
maxY =  413.66017150878906
normalized width  = 1088.4288482666016 pixels
normalized height =  964.4182891845703 pixels
```

Group origins and normalized coordinates retain fractional values. A single
uniform scale fits the full shared canvas. Native alpha is retained, with no
opaque per-group fill. Thin raster-rectangle outlines and group ordinal labels
overlay the nineteen numeric-ID textures. Lower mesh Z draws first in both
modes solely to make transparent overlaps deterministic.

The two original comparison modes are:

- **normal:** group Y as measured minus global minimum.
- **flipy:** reflect each complete group raster rectangle within the same
  global envelope; local tile offsets remain unchanged.

Neither mode reverses local tile-Y order or vertically flips texture UVs. No
individual group screen coordinates are tuned. The display identifies its
mode, rho, dimensions and trial/development status. The user's screenshots have
now rejected both as final placement; they are retained as diagnostic controls.

The command is development-, build-, instance- and combat-gated. It creates a
separate window, registers ESC closing, closes on stale instance identity, and
does not feed the ordinary `/dlmap` renderer or its saved geometry.
`RFC-WMO-70124.json` keeps `productionVerified=false` and `ready=false` even
though `developmentCompositeReady=true`.

## Canonical logical-cell composite — next screenshot target

Every tile has a logical **256×256** placement cell, regardless of its native
BLP dimensions. Cell geometry must not shrink for cropped images:

```text
absX = group.minimum.x * 2 + localX * 256
absY = group.minimum.y * 2 + localY * 256

minX = min(absX)
minY = min(absY)
maxX = max(absX + 256)
maxY = max(absY + 256)

cellScreenX = absX - minX
cellScreenY = maxY - 256 - absY

contentX = cellScreenX
contentY = cellScreenY + (256 - nativeHeight)
drawWidth = nativeWidth
drawHeight = nativeHeight
UV = (0,1,0,1)
```

This places local Y=1 **256 screen-space pixels above** local Y=0 in groups
001, 003 and 004. It does not vertically flip image UVs. X crop remains left
anchored, and Y crop remains bottom anchored, never centered or stretched.

| Group | FileDataID | Native width×height | Content offset X,Y in logical cell |
| --- | --- | --- | --- |
| 000 | 213056 | 256×128 | **0,+128** |
| 006 | 213069 | 128×64 | **0,+192** |
| 007 | 213070 | 64×64 | **0,+192** |
| 008 | 213071 | 256×128 | **0,+128** |
| 009 | 213072 | 256×64 | **0,+192** |
| 010 | 213073 | 256×128 | **0,+128** |

Every other tile is 256×256 with offset **0,0**. Group 007 therefore has a
256×256 logical cell even though its actual visible-image region is 64×64.

Independently recomputing all nineteen logical-cell extents gives:

```text
minX = -205.9113311767578
minY = -550.7581176757812
maxX =  882.5175170898438
maxY =  413.66017150878906
width  = 1088.4288482666016
height =  964.4182891845703
```

The outer envelope is **exactly the same as the previous trial for these data**,
not assumed to be equal. Internal placement and logical geometry change. Group
001 and group 003's full-size cells still determine the outer Y envelope, while
the smaller cells expanded elsewhere do not exceed it.

Tiles are ordered by **ascending MOGI minimum Z**, with group number used only
to break an exact Z tie. Current back-to-front group order is:

```text
001 → 000 → 004 → 011 → 002 → 003 → 005 → 009 → 010 → 008 → 007 → 006
```

The runtime also assigns sorted group ranks to explicit ARTWORK draw sublevels
**-8..3**, ensuring higher-Z groups draw on top independently of texture-region
batching/reuse. Tiles in the same group share the same draw sublevel.

Canonical development appearance: blue outlines identify all nineteen logical
256×256 cells, labelled by group and local X/Y. Gold outlines identify the six
smaller native-content rectangles. There is no opaque per-cell fill; alpha is
preserved. One uniform fit scale applies to content, cell origins and the whole
canvas. Sparse crop outlines are hidden when switching back to an old mode.

## Next runtime composite test — stay inside RFC

Outside combat:

```text
/reload
/dlmap scan composite canonical
```

The old `/dlmap scan composite` and `/dlmap scan composite flipy` commands remain
comparison controls. The canonical screenshot has since been accepted; normal
production-path acceptance is the next gate described below.
Report whether corridors, walls and rooms join, especially groups
001/003/004 and the thin connector groups. Misalignment is evidence: distinguish
global Y, group-origin corner, local Y, padding/partial-image anchoring or another
transform. Do not respond to a near-match by hand-moving a group.
X/ESC or `/dlmap scan stop` closes the diagnostic.

Focused Lua 5.1 checks passed for canonical Y=1-before-Y=0 in groups 001/003/004,
all six crop-anchor offsets, actual native dimensions, logical 256×256 extents,
every overlapping-content pair's MOGI Z ordering, draw sublevels, unchanged UVs,
uniform fit, outline geometry/mode cleanup and an independently derived logical
envelope. Existing normal/flipy behavior, gates, stale cleanup and ordinary map
selection also pass. Canonical is now **user-accepted in game**. These earlier
static checks remain separate from that real-client evidence.

## Development-only probe behavior

`Diagnostics.lua` now has a private `TileProbeMaps` development registry:

- **2999:** original nine Ruins of Lordaeron FileDataIDs/coordinates and its
  original path control are preserved.
- **389:** the nineteen catalog-confirmed WMO minimap FileDataIDs above and
  one verified-filename control for **213057**.

`/dlmap scan tiles` selects by `GetInstanceInfo()` return 8, never by the
localized name or a guessed UiMap. It retains build/instance/development/combat
guards. Unknown IDs report exactly:

```text
No tile probe metadata is registered for InstanceID X.
```

The contact sheet places increasing raw X to the right and increasing raw Y
down within each group. Group panels are arranged separately by ordinal for
inspection; their positions do not claim world-map placement. Labels identify
each FileDataID and X/Y, with a group heading. A checkerboard reveals transparent
areas. Images use full UVs without guessed cropping or flipping.

The window scales down to fit the screen. Its **80×80 preview cells are UI
sizes**, not inferred BLP dimensions. Square native dimensions cannot be proved
from square preview cells; the exact native headers now measured above supply
those dimensions. The diagnostic display itself has not been turned into a map.

After two seconds, the command reports guarded `SetTexture`, `IsObjectLoaded`
and `GetTextureFileID` evidence. The diagnostic snapshot retains instance/name,
layout kind, each group/X/Y and the path-control comparison ID. Texture-loading
return values do not prove that valid terrain pixels are visible.

Switching probes clears old image regions and invalidates old callbacks. An
instance-transition event or delayed sample detects stale instance identity and
closes the old probe. The ordinary map window and its geometry are not used for
this contact sheet. The diagnostic command never adds to the production registry.

## RFC-only normal-viewer promotion

`MapRegistry.lua` holds one private, static production entry keyed by authoritative
`GetInstanceInfo()` InstanceID **389**. It records display name, separate world
MapID, source type `blizzard-wmo-minimap`, build 1.60.1.70124, root/WDT provenance,
rho=2, logical 256×256 block dimensions, all twelve unchanged MOGI min/max arrays
(including min-Z), and all nineteen unchanged numeric tile/local-X/local-Y/native
size tuples. It has no setters, texture pathname fallbacks or SavedVariables
storage. **2999 is not registered.**

`WMOComposition.lua` owns the single layout calculation extracted from the
accepted diagnostic implementation. No canonical equation changed. Both normal
production and `/dlmap scan composite canonical` receive the same cached canonical
layout object; texture geometry, full UVs and draw sublevels use the same shared
positioning routine. Calculated layouts copy bounding arrays and do not mutate
registry metadata. Normal/flipy remain diagnostic comparison modes only.

Detection/resolution order:

1. Real usable current Dungeon UiMap or documented Dungeon ancestor → native
   `C_Map` renderer.
2. Otherwise a known accepted InstanceID registry entry → shared canonical
   WMO-minimap layout/renderer. RFC's nil UiMapID is supported here.
3. Otherwise → original no-map message.

The detection table keeps `uiMapID`/`mapID` in the UiMap namespace; it does not set
either to 389. `renderSource`, `mapEntry` and `composition` identify the fallback.
Native UiMap presence wins even if the running InstanceID is registered.

The normal window shows **DungeonLens - Ragefire Chasm** and clean map content.
It creates no cell/content outlines, group labels, coordinates, rho/dimension
captions or development-composite chrome. Rendered normal maps also hide the
existing development-ID text, while `/dlmap debug` retains it in chat. Logical
envelope aspect remains **1088.4288482666016×964.4182891845703**, centered and fitted
with one uniform scale on every resize. Alpha and actual native dimensions remain.

Texture quality uses guarded, documented Forever `SetSnapToPixelGrid(false)` and
`SetTexelSnappingBias(0)` on addon-owned regions. Their absence is tolerated; no
new geometry rounding, overlap, crop, origin shift or UV change is introduced.
The same configuration applies to canonical diagnostics for a fair comparison.

The known nineteen-region WMO pool is allocated during the normal window's
outside-combat creation. Stable refreshes reuse layout and textures; existing
window reopen/instance changes during combat reuse those regions. First creation
in combat still defers. Close/ESC and transitions clear active texture IDs and
renderer source state. Detection is event-driven, not continuously polled.
Window position/size/visibility continue to use the existing SavedVariables path.

Focused `Validate.py --production-only` passed: RFC registry resolution with nil
UiMap, native-first priority, unknown/2999 no-map behavior, numeric-only textures,
shared canonical object/math, clean map subtree, unchanged crop/min-Z/aspect,
wide/tall fit, reopen/reload/SavedVariables, stale clears, provenance/compatibility,
combat pool reuse, optional-quality-API absence and independent diagnostic UI.
`--composite-only` also passed after extracting the shared calculator, preserving
the already-accepted transform. No broad suite or release packaging was run.

### Next in-game test while still in RFC

```text
/reload
/dlmap
```

Approve the clean normal-window screenshot and check the focused lifecycle steps
in `MANUAL-TESTS.md`. Remaining uncertainty is actual normal-frame seam/fit quality,
client combat behavior, event timing and SavedVariables persistence; static/mock
checks do not establish those results. **M remains disabled pending approval.**

## Existing contact-sheet test (numeric loadability now completed)

Outside combat, run only:

```text
/reload
/dlmap scan tiles
```

Wait at least two seconds. Inspect all nineteen numbered images and the path
control, and report:

1. Actual terrain versus green, black, blank or checkerboard for each FileDataID.
2. Whether all nineteen native IDs load, with the one-shot API output.
3. Whether the visible group fragments are recognizably RFC. Use the composite
   commands above for whole-dungeon joining evidence.
4. In group **001**, compare `213057 → 213059` horizontally.
5. Compare `213057 → 213058` vertically. Does increasing Y need reversal?
6. Do the 2×2 groups indicate swapped X/Y or another orientation issue?
7. Are blank regions legitimate transparency/padding rather than missing images?
   The checkerboard distinguishes transparency from opaque black but cannot
   establish why a missing/blank asset occurred.
8. Does the path control match FileDataID **213057**?
9. Do image proportions look plausible? Contact-sheet cells are fixed square;
   the composite uses the now-measured native dimensions instead.
10. Is there apparent outer padding/cropping to consider within each group?
    No crop is applied and no crop bounds are invented.

Close with X, ESC or `/dlmap scan stop`. Numeric loadability and the path-control
failure have now been reported by the user. The composite commands are the next
test for continuous placement/orientation rather than repeating loadability.

If still in RFC, `/dlmap scan tiles` can be used specifically to report whether
the group 001/004 vertical pairs line up with increasing Y down versus up; label
the observation as visual orientation evidence. It does not establish global
group placement or pixel density. No new software installation is requested.

## Reproducible metadata-only inspection

```powershell
python .\scripts\Inspect-MapMetadata.py 389
python .\scripts\Inspect-MapMetadata.py 2999
```

The original no-argument invocation still defaults to 2999. For 389, the audit
first checks the Map-directory ground prefix, then the explicitly documented
WMO prefix, parses group/X/Y and produces separate group bounds. It does not
download BLP/WDT bytes, other creators' maps, or executable tooling.

Optional `--file-search` / `--file-page` inspect public file metadata only.
A single-page result retains pagination metadata and is not presented as a
complete inventory. Local CASC extraction remains outside this investigation.

Focused `Validate.py --tiles-only` passed under Lua 5.1 for automatic RFC
selection, all image requests, coordinate placement, repeated-coordinate group
separation, preserved 2999 identifiers, path controls, unknown/build/combat gates,
optional-method failures and stale/cross-instance cleanup. This is static/mock
validation, separate from the user's now-confirmed real-client loading evidence.

## Sources

- [Build-specific Map 389 record](https://wago.tools/db2/Map/csv?build=1.60.1.70124&filter%5BID%5D=389)
- [WDT FileDataID metadata](https://wago.tools/files?search=789981) — use exact ID, not substring matches.
- [Map-directory minimap search](https://wago.tools/files?search=world%2Fminimaps%2FOrgrimmarInstance%2F)
- [WMO minimap file catalog](https://wago.tools/files?search=world%2Fminimaps%2Fwmo%2Fdungeon%2Fkl_orgrimmarlavadungeon%2Flavadungeon_)
- [Root WMO file metadata](https://wago.tools/files?search=world%2Fwmo%2Fdungeon%2Fkl_orgrimmarlavadungeon%2Flavadungeon.wmo)
- [Historical technical WDT-to-WMO description](https://www.iamcal.com/world-of-mapcraft/) — textual file-reference evidence only; no artwork or source was obtained.
- [Independent historical WDT reference](https://www.ownedcore.com/forums/world-of-warcraft/world-of-warcraft-bots-programs/wow-bots-questions-requests/489142-world-wmo-dungeon-wmo-file-position-scale.html)
- [WMO MOGI/group bounds format](https://wowdev.wiki/WMO#MOGI_chunk)
- [Complete build-specific UiMap data](https://wago.tools/db2/UiMap/csv?build=1.60.1.70124)
- [Complete build-specific UiMap assignments](https://wago.tools/db2/UiMapAssignment/csv?build=1.60.1.70124)
- [Wago API selector documentation](https://wago.tools/apis) — exact version versus latest product selector.
- [Provider build/hash metadata](https://wago.tools/api/builds/wow_classic_beta/latest)
- [Exact-version WDT bytes](https://wago.tools/api/casc/789981?version=1.60.1.70124)
- [Exact-version root WMO bytes](https://wago.tools/api/casc/109483?version=1.60.1.70124)
- [Root file identity metadata](https://wago.tools/api/info/109483)
- [Representative native image header source](https://wago.tools/api/casc/213069?version=1.60.1.70124) — only 20 bytes were read.
- [Pinned current wow.export WMO-minimap implementation](https://github.com/Kruithne/wow.export/blob/c2fd7bde36a712be78a5da896c995b84fbfa2545/src/js/wmo-minimap.js)
- [Pinned wow.export Maps integration](https://github.com/Kruithne/wow.export/blob/c2fd7bde36a712be78a5da896c995b84fbfa2545/src/js/modules/tab_maps.js)
- [wow.export MIT license](https://github.com/Kruithne/wow.export/blob/c2fd7bde36a712be78a5da896c995b84fbfa2545/LICENSE)
- [0.2.18 release](https://github.com/Kruithne/wow.export/releases/tag/0.2.18), [0.2.19 release](https://github.com/Kruithne/wow.export/releases/tag/0.2.19)
- [Draw sublevel order/range](https://warcraft.wiki.gg/wiki/API:Region_SetDrawLayer), [Forever SetDrawLayer signature](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleRegionAPIDocumentation.lua)
