# Spawn-database frame <-> composite transform (build 1.60.1.70245)

Closed form, no fitted parameters: `local = Rot(180 deg - yaw) * (world - origin)`, canvas = `(local.x*rho - minX, maxY - local.y*rho)`.
Every creature spawn of the instance is projected; a point counts as a hit if painted minimap pixels lie within 6 px of it.

| Dungeon | WMO(s) / yaw | Spawns | On content (all) | Spawns inside WMO footprint | On content (footprint) | Chance level | Best axis-aligned alternative |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ragefire Chasm | 109483 / 0 | 132 | 100.0% | 132 | 100.0% | 32% | 100% |
| Wailing Caverns | 7952328 / 0 | 312 | 100.0% | 312 | 100.0% | 35% | 100% |
| Deadmines | 108483 / 269 | 213 | 69.5% | 148 | 100.0% | 15% | 70% |
| Shadowfang Keep | 109971 / 68.5 | 216 | 55.1% | 216 | 55.1% | 12% | 47% |
| Stormwind Stockade | 108631 / 0 | 93 | 100.0% | 93 | 100.0% | 16% | 100% |
| Blackfathom Deeps | 109197 / 0 | 212 | 100.0% | 212 | 100.0% | 17% | 100% |
| Gnomeregan | 109621 / 0 | 404 | 100.0% | 404 | 100.0% | 25% | 100% |
| Razorfen Kraul | 109523 / 227 | 191 | 100.0% | 191 | 100.0% | 36% | 81% |
| Scarlet Monastery | 7958652, 7958653, 7958654, 7958650 / 0, 0, 0, 0 | 340 | 100.0% | 340 | 100.0% | 22% | 28% |
| Razorfen Downs | 109503 / 0 | 263 | 100.0% | 263 | 100.0% | 44% | 100% |
| Uldaman | 109782 / 0 | 317 | 100.0% | 317 | 100.0% | 20% | 100% |

Notes:
- Hall of Thanes, Ruins of Lordaeron and Excavation Site have no spawn data in any public source used: the frame cannot be tested
  there and their bosses are unresolved.
- Deadmines: all 148 spawns inside the main WMO footprint land on content; the rest are in the ship/outdoor areas, which have no
  minimap tiles in this build.
- Shadowfang Keep: the interior WMO covers only the keep; the other ~45% of its spawns are courtyard/outdoor. The 55% hit rate is only
  4.6x chance and the best axis-aligned alternative is close, so this map's frame is NOT proven by containment alone. It is supported
  instead by two independent Blizzard retail Journal pins (Baron Silverlaine, Commander Springvale) agreeing with the spawn-derived
  positions, including the retail floor. Single-source SFK bosses are therefore medium confidence at best.
- Scarlet Monastery: each of 340 spawns lands in exactly one wing page (100+94+79+67); the alternative frames reach only 28%.
