# October 1 beta regression: 70124 provenance used as an exact runtime gate

## Direct local and user runtime evidence

- The user is inside a party instance, **Ragefire Chasm / InstanceID 389**.
  Best UiMapID and render UiMapID are nil, and the normal window shows no map.
- `E:\World of Warcraft\.build.info` now reports **1.60.1.70170**,
  product `wow_classic_beta`, build config
  **`d3f2837397a016e380ea51c4e1e78d1d`**, CDN config
  **`7bfef39ed156aa00019d651013213326`**.
- Installed `E:\World of Warcraft\_classic_beta_\WowB.exe` file/product versions
  both report **1.60.1.70170**; a WowB process is running from that path.
- The addon TOC remains **16001**. The actual client `GetBuildInfo()` interface
  return must be captured through `/dlmap debug`; this harness cannot run Lua
  inside the live WoW process. No loose `_classic_beta_/.build.info` exists;
  the storage-root `.build.info` above is the installation's build record.

This is not a conclusion from synthetic tests alone: it combines the reported
in-game instance state, actual installed build, installed source, and the exact
rejection condition. New diagnostic output is still needed to record the complete
live call trace after reload.

## Exact old rejection path

```text
/dlmap
  -> DungeonWindow:Open()
  -> Core.Refresh("open")
  -> MapDetector:Detect()
     instanceID = 389, supportedInstance = true
     UiMapID = nil, hasNativeArt = false
     -> MapRegistry:GetVerified(389, currentVersion, currentBuild)
        entry = maps[389] (found), sourceType = blizzard-wmo-minimap
        old gate: version == entry.version AND build == entry.build
        verified source = 1.60.1.70124; installed build = 1.60.1.70170
        build equality = false -> returned nil
     WMOComposition was not called; selected renderer stayed "none"
  -> DungeonWindow:Update()
     no ShowWMO call -> generic no-map message
```

The previous reason remained `no-current-uimapid`, obscuring the later registry
rejection. A nil UiMap is expected for RFC and was not the actual rejection cause.
`/dlmap scan composite canonical` also had its own exact 70124 gate, so on today's
build it could refuse before loading any texture. This is a **resolver/compatibility
regression**, independently of whether an asset might also have changed.

## Architecture correction

The registry now stores **verifiedVersion / verifiedBuild / verifiedInterface**
as provenance. They remain **1.60.1 / 70124 / 16001**, not changed to 70170.

`MapRegistry:Compatibility()` classifies a matching build as `verified`, a newer
numeric build as `newer-unverified`, and other differing/unknown provenance as
unverified. Known, accepted metadata remains eligible for a numeric texture-load
attempt. There is no list of accepted beta builds and no build-equality rejection.
Concrete rejection examples are missing registry metadata, an unaccepted
transform, unsupported source type, layout failure or a rejected texture request.

The normal resolution order remains native Dungeon UiMap → known InstanceID →
no map. The RFC composite and RFC tile probe use the same compatibility policy.
The Ruins diagnostic-only metadata remains separate; no dungeon was added to
production. The accepted canonical calculation, MOGI coordinates, 19 FileDataIDs,
crop offsets, UVs, min-Z order and sizing are untouched.

`/dlmap debug` now reports actual `GetBuildInfo()` values and the detector's
runtime decision table: lookup key, entry found, source type, verification/current
builds, compatibility/allowed/reason, native availability, selected renderer,
fallbackSelected, and selection/rejection reason. An existing normal window adds
its actual renderer-attempt/return result, including the failing FileDataID on
SetTexture refusal. Texture requests accepted is not proof of visible pixels.

Expected decision for the reported RFC state on 70170 (not yet captured from
the live client):

```text
lookupKey=389 registryEntry=found source=blizzard-wmo-minimap
verifiedBuild=70124 currentBuild=70170
compatibility=newer-unverified allowed=true
rendererSelected=WMO minimap fallbackSelected=true
```

## Exact-build online metadata comparison

Ran the existing native metadata parser through the new read-only wrapper:

```powershell
python .\scripts\Compare-RfcBuild.py 1.60.1.70170
```

The provider's version/product/build/CDN configs match the local installation.
Version-scoped results:

- Map **389** is still `OrgrimmarInstance` / Ragefire Chasm, WDT **789981**.
- WDT MD5 **`9a430840a3bfbce513ff5a529b0de3b2`**, SHA256
  **`6b79236566873ed9a54797dbbe50374b609ab0476691f2f2a26b7ec1149cf3f3`**
  match the 70124 baseline; MODF still references root WMO **109483**.
- Root WMO MD5 **`18c9698976d1d0935ceb10f1f42674dd`**, SHA256
  **`d111b096f05f3446f8026613333b4357b580b3343e96602410a8e5f6e7379ecd`**
  match the baseline exactly.
- All twelve MOGI flags/bounds and GFID group references **109484–109495** match.
- All nineteen IDs **213056–213074** return recognized BLP2 headers with the same
  native dimensions. Only the **20-byte headers** were read, not image pixels.

**No investigated identifier or WMO geometry change was found.** Texture pixel
equality, local CASC-byte equality and actual Lua rendering on 70170 are not proven
by this comparison. No asset or map metadata was regenerated/modified, and no
native artwork file was saved. The earlier verified-build snapshot is preserved.

Sources: [Map 389 on 70170](https://wago.tools/db2/Map/csv?build=1.60.1.70170&filter%5BID%5D=389),
[provider build](https://wago.tools/api/builds/wow_classic_beta/latest),
[70170 WDT](https://wago.tools/api/casc/789981?version=1.60.1.70170),
[70170 root](https://wago.tools/api/casc/109483?version=1.60.1.70170).

## Focused validation and next client commands

`Validate.py --resolver-only` passed under Lua 5.1 for matching/newer/later/older
build fallback attempts, unchanged provenance, native priority, unknown-instance
rejection, explicit debug decisions, unblocked canonical diagnostic, unchanged
canonical object/geometry/IDs, and precise texture-refusal reporting.
`--composite-only` also passed the existing canonical transform regressions.
These are synthetic checks, not live-client rendering results.

While still in RFC, run:

```text
/reload
/dlmap debug
/dlmap scan composite canonical
```

Confirm the diagnostic still draws all nineteen textures with accepted geometry
on 70170. Then run:

```text
/dlmap
```

Opening `/dlmap` closes the diagnostic foreground. If anything fails, run
`/dlmap debug` again while the normal window remains open and send the resolver
and renderer-attempt lines. No M-key integration or release packaging is enabled.
