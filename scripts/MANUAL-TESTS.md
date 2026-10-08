# DungeonLens v0.1 manual acceptance checklist

Status: **full checklist pending**. The user has verified the missing-UiMap
fallback in Ruins of Lordaeron (InstanceID 2999, build 70124), all RFC numeric
textures and the RFC canonical transform. Normal-viewer/lifecycle acceptance is
still pending. Local smoke checks use synthetic data;
they cannot establish Forever compatibility or a dungeon support list.

Record the build, locale, dungeon name and `/dlmap debug` output for each instance.
Dungeon IDs and UiMapIDs are different; include both. A FileDataID list is not
proof that a client successfully loaded those art assets.

1. **First install / outside login:** restart the currently running client,
   enable DungeonLens in the character-selection AddOns list, and log in
   outside an instance. No automatic map window should appear on a fresh profile.
2. **Outside diagnostics:** run `/dlmap debug`. Confirm build/interface,
   `inside=false`, current map metadata, and no Lua errors. Missing/restricted
   fields should say `nil`, `unavailable`, `error`, or `<restricted>`.
3. **Outside window:** run `/dlmap`. It should explain that you are outside a
   dungeon/raid. Close with X, reopen and press ESC. Also try `/dlmap close`.
4. **Dungeon transition:** enter an accessible dungeon with the window open.
   Confirm the title/status updates; run `/dlmap debug`.
5. **Instance diagnostics:** record instance name/type/ID, best UiMapID,
   map type, render map, art/layer dimensions and tile IDs. Confirm that a
   Dungeon map is returned or there is a Dungeon ancestor. Never accept a
   nearby outdoor zone or arbitrary child as the current instance.
6. **Dungeon viewer:** run `/dlmap`. If native art is returned, confirm that
   the title and artwork identify the dungeon you entered. If there is no
   usable art, confirm the exact fallback message and development IDs.
7. **Art geometry:** drag the header; resize from the bottom-right control.
   Try wide and tall windows. Landmarks must keep their proportions, tiles
   must stay in order and aligned, and the last row/column must be cropped
   correctly. Solid-green/blank tiles despite returned IDs are a failed
   native-art-loading test; report IDs and locale.
8. **Save open state:** leave the window open in a distinctive position/size;
   run `/reload`. It should reopen at that position/size and refresh the
   current instance. Run `/dlmap debug` to check saved geometry.
9. **Save closed state:** run `/dlmap close`, then `/reload`. It should stay
   closed. Reopen and confirm geometry is retained. Log out/quit/restart once
   too; this checks Forever's across-session SavedVariables behavior.
10. **Leave the dungeon:** with the window open, leave. It should clear dungeon
    artwork and report that you are outside. Enter another dungeon if possible;
    stale art/name/IDs from the previous instance must not persist.
11. **Normal world map:** press M outside, inside a supported instance, and
    inside one without artwork. It should behave exactly as Blizzard normally
    does; M-key integration is disabled in this build. Close DungeonLens first
    if it visually overlaps the regular world map.
12. **Multiple floors:** if a multi-floor dungeon is accessible, run
    `/dlmap debug` before/after changing floor. Record best UiMapID, child/group
    IDs and `relativeHeightIndex`. An open window should follow the current map
    if the client emits the supported transition events. There are intentionally
    no Previous/Next controls until those relationships are verified. If it
    updates only after `/dlmap`, record that event-delivery failure.
13. **Missing-art instance:** if one is found, open with `/dlmap` and confirm:
    `No native dungeon map is available for this instance yet.` Development
    instance/map IDs must appear below. Repeated opens/debugs must not emit Lua
    errors. Ruins of Lordaeron / InstanceID 2999 is a verified missing-UiMap case;
    its client minimap textures are being investigated separately.
14. **Combat:** with an existing window open, enter/leave combat. Reading,
    closing and reopening it should work; starting a drag/resize should be
    disabled during combat. If combat begins during a drag/resize, motion must
    stop. On a fresh reload with no window created, try `/dlmap` in combat:
    creation is deferred, `/dlmap close` cancels it, and leaving combat opens a
    still-requested window. Check for interface-blocked/taint messages.
15. **Raid / optional position investigation:** repeat steps 4–9 in a raid if
    available. For position evidence, run `/dlmap debug` several times after
    movement, floor changes and combat. A marker is absent even if one sample
    works. Do not enable it on the strength of a single sample.

Acceptance: all applicable core tests must pass on the recorded build, including
at least one genuinely rendered dungeon. Mark inaccessible optional cases as
untested, not passed. After acceptance, use the packaging command in README.md.

Current investigation probes: inside RFC (389) or Ruins of Lordaeron (2999), run
`/reload`, then `/dlmap scan tiles` outside combat. The current InstanceID selects
the appropriate metadata; RFC uses nineteen tiles in separate WMO-local groups.
Record API output, actual visible/green/blank tiles and raw X/Y orientation.
`/dlmap scan stop` cancels discovery and closes the contact sheet.
These are temporary diagnostics, not completed fallback-map support; release
packaging remains on hold during this investigation.

RFC canonical trial: run `/reload`, then `/dlmap scan composite canonical` outside
combat. Check whether corridors and walls join, including thin connectors.
Blue outlines are logical cells; gold outlines are smaller bottom-left native
content. Confirm local Y=1 appears above Y=0 in groups 001/003/004, cropped sizes
are not stretched, transparency remains visible and higher min-Z geometry draws
on top. Check shown dimensions/rho, ESC/stop and leaving the instance. Old
normal/flipy commands remain comparison controls; their screenshots were not
accepted. Do not hand-tune positions to force a near-match.

## Next test: RFC normal-viewer promotion

While still inside RFC, run `/reload`, then `/dlmap`.

1. Confirm title **DungeonLens - Ragefire Chasm** and the accepted clean map.
   No cell/content outlines, group labels, coordinates, rho or dimensions should
   appear in the normal viewport, even with development tools enabled.
2. Resize wide/tall and drag outside combat. Confirm unchanged proportions,
   centered fit, alpha and corridor joins; report actual seams without adjusting
   any group metadata.
3. Close/reopen with X, ESC and `/dlmap close` / `/dlmap`. Confirm geometry and map.
4. Leave open, `/reload`, and confirm restored visibility/size/position and RFC.
5. Enter/leave combat with the window already created. Reopen it and confirm no
   taint/blocked-action message; dragging/sizing stays disabled in combat. A first
   creation request in combat is still deferred until combat ends.
6. Leave RFC and enter an unsupported instance when available. RFC textures must
   disappear; unsupported instances get the existing no-map message. Ruins/2999
   is explicitly not promoted.
7. `/dlmap debug` should report source `blizzard-wmo-minimap` inside RFC with nil
   UiMapID. A real native Dungeon UiMap, if one becomes available, must win.
8. Development scan/tile/composite commands remain independent. Opening `/dlmap`
   closes their visual foreground and shows only the ordinary viewer.

M remains the Blizzard map binding. Approve the clean RFC screenshot before
investigating M integration. No release packaging is part of this test.

## October 1 / build 70170 regression check

While still in RFC, `/reload`, then `/dlmap debug`. Record the actual GetBuildInfo
version/build/interface and resolver lines. Expect lookupKey=389, registry found,
verifiedBuild=70124, currentBuild=70170, compatibility=newer-unverified,
allowed=true and renderer WMO minimap. Before judging map-data changes, run
`/dlmap scan composite canonical` and confirm all nineteen tiles/geometry still
render. Then `/dlmap` should display the clean RFC map. A second `/dlmap debug`
with the normal window open records the actual renderer attempt and any rejected
FileDataID. Keep this visual result separate from online metadata comparison.

## Click-through UI (v0.1.1 development)

After `/reload`, the only command needed is **`/dlmap`**. Static layout is checked offline (`previews/index.html`); in game only
live-client behaviour needs eyes.

1. `/dlmap`: the "Forever Dungeons" list opens, 14 rows, Excavation Site greyed "Unavailable". Hover highlights a row; the wheel scrolls
   if the window is short.
2. Click **Ragefire Chasm**: the accepted map with four skull pins; hover a pin for the boss name. No diagnostic text.
3. Click **< Dungeons**: the list returns instantly; the window keeps its position and size.
4. Click **Gnomeregan**: `<  Floor 1 of 4  >` appears in the header; click `>`: the map and the pins change (Electrocutioner on floor 2,
   Thermaplugg on floor 4). **Scarlet Monastery** pages through Graveyard / Library / Armory / Cathedral.
5. Click through several dungeons and back repeatedly: no stale tiles or pins, no flicker of the previous map.
6. Resize the window in the list and in a map: rows and map both follow; pins stay on their spots.
7. **X** or **ESC** closes; `/dlmap` reopens to the list. Excavation Site does nothing when clicked.
8. Look for missing/green/black tiles that `previews/` PNGs do not show (only the live client can fail to draw a texture).
9. Optional, needs a dungeon: `/dlmap probe`, then `/dlmap player on` (see API-NOTES).

## Minimap button

1. After `/reload` a round book icon sits on the minimap's lower-left rim. Left-click opens the dungeon browser, left-click again closes it.
2. Drag it around the rim (it follows the cursor, stays on the edge); `/reload` and check it keeps its place. If you use a square minimap or a
   minimap-button collector addon, check it sits correctly / is collected.
3. Inside a dungeon right-click it: the window opens straight on that dungeon's map. Outside, right-click opens the browser.
4. `/dlmap minimap off` hides it, `/dlmap minimap on` shows it, `/dlmap minimap reset` puts it back at the default spot.

## Entrance card (top left of an open dungeon)

1. `/dlmap`, click **Ragefire Chasm**: the top-left card reads `Orgrimmar  53.0, 48.9`. Click **Show on world map**: the world map opens on
   Orgrimmar with a pin near the Cleft of Shadow (check it is where the entrance really is; report the pin's coordinates if it is off).
2. Try **Wailing Caverns** (The Barrens 47.7, 35.0), **Scarlet Monastery** (Tirisfal Glades 85.1, 31.4), **Razorfen Downs** (The Barrens 50.9, 92.9)
   and **Ruins of Lordaeron** (Tirisfal Glades 61.8, 72.9, at the keep of the ruined city). **The Hall of Thanes** opens Ironforge with no pin.
3. If the world map does not open or no pin appears, the card prints the zone and coordinates to chat instead; report which of the two happened.

## Boss table (top right of an open dungeon)

1. `/dlmap`, click **Ragefire Chasm**: a **BOSSES** table appears at the top right with Oggleflint, Taragaman the Hungerer, Jergosh the Invoker and
   Bazzalan, each with "N items" or "no loot yet". It must not hide the map's bosses or the floor buttons (check a narrow window too).
2. Click a name: the loot panel replaces the table; **< Bosses** brings the table back. Open **The Hall of Thanes**: no pins, but the table lists
   its four bosses and Durgen Dirgehammer shows his item. In **Gnomeregan** on floor 1, click Electrocutioner 6000: the map jumps to floor 2.

## Boss loot (v0.1.1 development)

After `/reload`: `/dlmap`, then
1. Click **Ragefire Chasm**; hover **Taragaman the Hungerer**: the tooltip says "Click to view loot". Click the pin.
2. A panel opens on the right: Cursed Felblade, Crystalline Cuffs, Subterranean Cape, with icons and quality-coloured names.
3. Hover an item: Blizzard's normal item tooltip appears. (If an item was not cached, its name/icon may first appear generic and then fill in.)
4. **Close** (or click empty map) returns to the map; the map never closes. Click **Jergosh the Invoker**: Cavedweller Bracers, Robe of
   Evocation, Chanting Blade. Click **Oggleflint**: "No verified loot yet" (his Forever-new drops have no verified item IDs yet).
5. **Gnomeregan**: go to floor 2, click Electrocutioner 6000, press `>`: the panel closes with the floor change.
6. Open another dungeon (e.g. **Deadmines**) and click a boss. Report any item row stuck on a generic name/icon after a few seconds
   and any wrong boss->item association.

## Seen by you (in-game, needs a real boss kill)

1. Kill any boss that shows "No verified loot yet" (e.g. Oggleflint) and loot the corpse.
2. `/dlmap`, open that dungeon, click the boss: a **SEEN BY YOU** section lists what dropped; hover shows the normal item tooltip.
3. Loot trash after the boss: it must not appear. `/dlmap lootexport` prints the encounter ID and item IDs.
4. Boss positions (Hall of Thanes / Ruins of Lordaeron, which have no verified pins): after looting the boss's corpse, reopen the map. The boss
   shows a **blue** skull where you stood; hover says "Where you looted it (not verified)"; click opens its loot panel. If no pin appears, run
   `/dlmap lootexport`: a `dungeon .. encounter ..` line means the position was stored but did not land on the map (report the numbers);
   no line means `UnitPosition` returned nothing readable in that dungeon.
5. If nothing is recorded after a kill, report whether `ENCOUNTER_END` fired (`/etl` or `/run print(...)`); the fallback is the 5-minute window.
