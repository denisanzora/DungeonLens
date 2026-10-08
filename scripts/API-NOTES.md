# Forever API evidence — 2026-09-30

## Local installation evidence

- Client: `E:\World of Warcraft\_classic_beta_\WowB.exe`.
- Both executable version metadata and `E:\World of Warcraft\.build.info`
  report **1.60.1.70124**, product `wow_classic_beta`.
- `.flavor.info` also reports `wow_classic_beta`.
- `Interface\AddOns` was empty before the development install. There are no
  loose Blizzard FrameXML/API documentation files there. Client UI files are
  in CASC; no CASC extraction or other addon's files were used.
- A client process was running during initial development. This harness cannot
  execute Lua inside that process or observe instance transitions. The user has
  since supplied real Ruins of Lordaeron runtime evidence: party instance 2999,
  best UiMapID nil, and the correct no-map fallback. Native dungeon rendering
  has not yet been demonstrated.
  The user also supplied RFC evidence (party InstanceID 389): best/minimap UiMap
  nil; scan found 60 records and zero candidates with no API failures. See
  [the RFC investigation](MAP-DATA-389.md) for the WMO-local tile probe.
  The user subsequently confirmed all nineteen RFC numeric FileDataIDs visibly
  render while the pathname control fails. Exact-version online native metadata
  confirms root WMO 109483, its twelve MOGI boxes and varying BLP dimensions.
  This required no installed CASC reader. All twelve stitched rasters now match
  nextPowerOfTwo(2*extent), providing independent current-build rho=2 evidence.
  A development-only continuous composite tests bbox-min placement with normal
  and global group-flipy modes. Both screenshot trials were rejected. Canonical
  now independently reproduces the pinned wow.export tile-cell coordinate
  semantics: 256×256 logical cells, per-cell Y inversion, bottom-left native
  content and ascending min-Z draw sublevels. Canonical screenshot acceptance
  is now confirmed by the user's real screenshot. A private production registry
  promotes RFC/389 with verification provenance from build 70124. `WMOComposition.lua` shares the exact
  canonical layout and native texture positioning with the normal viewer;
  normal-window screenshot/lifecycle acceptance remains pending and M is disabled.

## Public Blizzard UI/API evidence

The public [Gethe/wow-ui-source `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever)
was inspected for API signatures and behavior only. Its observed HEAD was
`966519cf0ad2c10301ea011a88c14b25697c9687`. It is external source evidence,
not proof that every signature or return value works in the local build.
DungeonLens is independently written; no upstream source or art is bundled.

Sources:

- [MapDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
- [MapConstantsDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapConstantsDocumentation.lua)
- [InstanceDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/InstanceDocumentation.lua)
- [Blizzard_MapCanvasDetailLayer.lua](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua)
- [Blizzard_WorldMap.lua](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua)
- [GetPlayerMapPosition documentation](https://warcraft.wiki.gg/wiki/API_C_Map.GetPlayerMapPosition)
- [Secure posthook documentation](https://warcraft.wiki.gg/wiki/API_hooksecurefunc)

| API/data | Documented shape | DungeonLens use |
| --- | --- | --- |
| `GetBuildInfo()` | version, build, date, interface | Diagnostic only. |
| `IsInInstance()` | boolean, instance type | Authoritative instance presence, guarded. |
| `GetInstanceInfo()` | name, type, difficulty data; instance ID is return 8 | Authoritative dungeon identity; return 8 matches world Map.ID 2999 in this investigated build. It is not a UiMapID or a unique saved lockout ID. |
| `C_Map.GetBestMapForUnit("player")` | nullable UiMapID | Current map, not assumed to be a dungeon. |
| `C_Map.GetMapInfo(id)` | nullable details: `mapID`, `name`, `mapType`, `parentMapID` | Current map and bounded/cycle-checked ancestor chain. |
| `Enum.UIMapType.Dungeon` | Forever source lists Dungeon = 4 | Read the running enum; no numeric fallback. |
| `C_Map.GetMapArtID(id)` | may return nothing | Diagnostics and art metadata. |
| `C_Map.GetMapArtLayers(id)` | nullable array of layer/tile dimensions and scale ranges | Validate dimensions; select a complete layer. Layers are zoom resolutions, not floors. |
| `C_Map.GetMapArtLayerTextures(id, layerIndex)` | nullable array of numeric FileDataIDs; 1-based layer index | Require every expected tile. Source confirms row-major indexing. Crop edge padding; use uniform scaling. |
| `C_Map.GetMapChildrenInfo(id, dungeonType, false)` | nullable array of map details | Diagnostic candidates only; a zone child is not proof of the player's dungeon. |
| `C_Map.GetMapGroupID(id)` / `GetMapGroupMembersInfo(groupID)` | nullable group ID / members with `mapID`, `name`, `relativeHeightIndex` | Collect possible floors for diagnostics; navigation stays disabled. |
| `C_Map.GetPlayerMapPosition(id, "player")` | nullable vector2; `GetXY()` or `x`, `y` | One-shot diagnostic only; no live marker. |
| `issecretvalue(value)` | boolean, if supplied by client | Do not inspect/compare restricted values. Missing functions, exceptions, nils and unusable metadata are quiet in normal use. |

## Player position decision

The current wiki marks `GetPlayerMapPosition` **#noinstance**, with nil expected
in restricted instances. The Forever-generated API still lists the nullable
function. Neither fact establishes runtime availability in this beta's dungeons.
`/dlmap debug` reports one sample and whether its readable coordinates are
normalized. **The v0.1 player marker is omitted.** A future decision needs repeated
samples after movement, floor changes and combat, on the actual dungeon map ID.
No coordinate workaround or unrestricted-position bypass is used.

## M-key integration decision

**Disabled; not yet runtime-tested.** The `/dlmap` gate has not been passed in
game. A secure posthook runs after the original call and cannot cancel it or
replace its return value. Forever's World Map source registers a UIPanel and
triggers `WorldMapOnShow` after opening, and listens for `WORLD_MAP_OPEN`.
Observing those is a candidate for later investigation, not a safe way to cancel
the original M action. Hiding/reopening a Blizzard panel from an addon hook would
need client-specific combat, taint, toggle and fallback validation.

No bindings are replaced and no WorldMap functions or scripts are hooked in
v0.1. There is **no observed taint failure** to report, because interception has
not been attempted. M retains the client's normal behavior everywhere.

## Runtime questions still open

1. Does the best map become a Dungeon UiMapID in each Forever dungeon/raid?
2. Are returned tile IDs actually drawable (including locale-specific assets)?
   Nonzero FileDataIDs alone do not prove that the client's art assets load.
3. Do partial tiles match the documented dimensions in this build?
4. Do map-change/zone/WMO events deliver timely updates on floor transitions?
5. Are child/group relationships reliable enough for floor controls?
6. Does SavedVariables persistence work across reload and full client restart?
7. Are window show/hide, ESC, dragging and sizing correct during combat changes?

The manual checklist is the acceptance gate. No dungeon support list has been
invented. The user verified the missing-UiMap fallback in Ruins of Lordaeron;
RFC numeric textures and the canonical composition are now visually verified.
The normal RFC viewer screenshot and the full lifecycle checklist remain pending.

## Ruins of Lordaeron investigation

[Detailed map-source findings, identifier namespaces and proposed fallback](MAP-DATA-2999.md)
record the concrete InstanceID 2999 case. Build-specific public DB2 exports have
no corresponding UiMap/assignment, but nine Blizzard minimap BLP FileDataIDs were
identified under directory `2999`. Local extraction stopped at the missing CASC
reader boundary; no new tool was installed. Temporary `/dlmap scan` and
`/dlmap scan tiles` probes establish runtime UiMap and direct-texture evidence.
They do not alter ordinary viewer selection or implement a permanent registry.

That earlier diagnostic-only stage is now followed by the RFC-only promotion:
InstanceID 389 selects a known accepted production entry when native Dungeon UiMap
art is unavailable. InstanceID 2999 remains unregistered. World/InstanceID,
UiMapID and FileDataID are separate fields/namespaces throughout resolution.

### Texture quality in the shared renderer

The inspected Forever `SimpleTextureBaseAPI` documentation exposes
`SetSnapToPixelGrid(bool)` and `SetTexelSnappingBias(number)`. When the methods
exist on an addon-owned texture, guarded calls use `false` and `0` respectively
to retain fractional placement instead of independently snapping pieces. No
extra overlap, crop, UV flip, padding adjustment or guessed API is introduced.
Missing methods are tolerated; visual seam quality still needs the normal-viewer
runtime test. The known WMO texture pool is preallocated outside combat.

Source: [Forever texture API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua).

## October 1 build 70170 resolver regression

Local executable/build metadata now identify 1.60.1.70170. The prior registry
mistakenly compared current build exactly with the verified 70124 provenance,
returning nil for known InstanceID 389. The composite duplicated that gate.
Both are fixed without changing canonical math or any map identifier. Newer
builds are `newer-unverified` but eligible for numeric loading; debug output
records the actual lookup/compatibility/selection and renderer-refusal reasons.
Version-scoped online WDT/root hashes, all MOGI/GFID records and nineteen BLP
header IDs/dimensions match the original data. Live canonical/normal rendering
on 70170 still needs the user's confirmation.

[Full evidence and exact client commands](BUILD-70170-REGRESSION.md).

## Completed local checks

- All five runtime Lua files compiled and executed in a Lua 5.1 runtime.
- Synthetic smoke checks passed for map/instance identity, micro-map ancestry,
  zone-child rejection, nil/missing/error/restricted APIs, incomplete textures,
  invalid dimensions and cyclic parents.
- Renderer checks passed for row-major IDs, wide/tall proportional fit, partial
  edge-tile dimensions/UVs and client texture rejection.
- UI logic checks passed for commands, transition refreshes, ESC list
  registration, SavedVariables/reload modeling, combat interaction stop,
  deferred/cancelled opens and diagnostic position samples. There is no polling.
- The installed junction target and all six initial runtime file hashes were
  verified; repeat installation recognized the existing repository link.
- `Package.ps1 -CheckOnly` built and reread an in-memory ZIP: exactly six
  allowlisted runtime entries, all SHA256 payloads equal to repository files.
  The release acceptance gate was also verified. No ZIP was written to disk.

## Player position investigation (build 1.60.1.70245, October 7)

Method: Forever's generated API documentation (Gethe/wow-ui-source `forever`, signatures only) plus a
runtime probe, `/dlmap probe`, that calls every candidate through `pcall`/`issecretvalue` and records
results in `DungeonLensDB.positionProbe` (inside vs. outside an instance).

Static findings (docs; not proof of runtime behavior):

| Candidate | Documented | Usable for a dungeon player marker? |
| --- | --- | --- |
| `C_Map.GetPlayerMapPosition(uiMapID, unit)` | nilable `vector2`, "player and party members" | Needs a UiMapID. This build has **no Dungeon-type UiMap at all** (UiMap.db2: 60 rows, none type 4; no assignment for any dungeon Map). Nothing to pass. |
| `UnitPosition(unit)` | returns x, y, z, mapID | Instance-local **world coordinates**, not map-normalized. Even if readable, converting to our canvas needs the WMO placement transform and axis convention, which are not verified. Restricted in instances in the classic API family. |
| `C_Minimap.GetUiMapID()` / `GetViewRadius()` | nilable uiMapID / yards | The minimap-to-UiMap link is nil where no UiMap exists. A radius alone gives no position. |
| `UnitPositionFrame` (`FrameAPIUnitPositionFrame`) | Blizzard frame drawing unit dots on a UiMap | Requires `SetUiMapID`; same no-UiMap blocker. |
| `C_Map.GetWorldPosFromMapPos` / `GetMapPosFromWorldPos` | need a UiMapID / continent | Same blocker. |
| `MINIMAP_PING`, `GetPlayerFacing`, `GetUnitSpeed` | event / heading / speed | Not a position. Using them would be dead reckoning, which is excluded. |
| `C_Navigation.*` | distance/waypoint to a user-set waypoint | Not the player position. |

Conclusion for this iteration: **no legitimate source is established, so the player marker stays
disabled** (`ns.PlayerPosition.available = false`). A marker would be shown only after (1) `/dlmap probe`
proves a readable value inside a Forever dungeon and (2) the world-to-canvas transform is validated
against known landmarks. No keyboard inference, dead reckoning, memory access, external process or
restricted-API workaround is used.

Runtime evidence still needed: run `/dlmap probe` once outside and once inside a dungeon (MANUAL-TESTS.md)
and compare the two `positionProbe` records.

## Orientation observation (RFC is unchanged)

Hall of Thanes ships both a north-up ADT ground minimap and a WMO minimap set. Comparing renders shows the
canonical WMO composite (accepted for RFC: world X to the right, Y inverted per cell) is rotated about 90
degrees relative to the client's north-up ground orientation. RFC's accepted mapping is untouched. Marker
coordinates are defined against whatever the renderer draws, so they stay correct, but a future "rotate WMO
maps to north-up" option would invalidate WMO layout signatures.

## Player position, second pass (October 7): the world-to-canvas transform is now proven

This **supersedes** the earlier statement that `UnitPosition` values cannot be mapped onto the canvas. The instance world frame that
`UnitPosition` reports (X north, Y west, Z up, the same frame as ADT/WMO placement, spawn tables and Blizzard's UiMapAssignment regions)
maps onto a dungeon canvas by a closed form with no fitted parameters:

    local = Rot(180 deg - yaw) * (world - origin)      canvas = (local.x * rho - minX, maxY - local.y * rho)

`origin`/`yaw`/`zOffset` come from the WMO's ADT placement (global-WMO dungeons: origin 0, yaw 0). Evidence in `FRAME-FIT.md`: 9 of 11
dungeons put 100% of every creature spawn (up to 404 per dungeon, three different placement yaws, four wing WMOs) on painted minimap
pixels, versus 15-44% by chance; it also reproduces Blizzard's own retail Journal pins to ~1-2% of the map and every placed boss in
`MultiDungeonSmoke.lua` (Lua equals the Python pipeline to 2e-4). Shadowfang Keep is only weakly proven by containment (55%) and rests on two
retail-pin agreements.

What remains unknown is a **runtime** fact: whether `UnitPosition("player")` returns readable numbers inside Forever instances, and in which
axis order. DungeonLens therefore ships the projection but keeps the marker behind a development switch:

- `/dlmap player on` starts a 4 Hz check only while on; it is off by default and leaves no OnUpdate script when off.
- values must be plain finite numbers (no secrets/nil); the 4th return, if readable, must equal the instance ID;
- both axis orders are tested against the map's own group volumes (xy and height); the marker is drawn only if exactly one order lands
  inside the dungeon (otherwise nothing is drawn); after three well-separated unambiguous samples the order is remembered for the session;
- only in the live view of the instance the character is in; never in a preview; never estimated or dead-reckoned.

`/dlmap probe` prints the raw `UnitPosition` result, the projection, and every other candidate API for the record.
