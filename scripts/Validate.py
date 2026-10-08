"""Focused Lua 5.1 smoke checks; does not emulate the actual Forever client."""

import argparse
import ast
import json
from pathlib import Path

try:
    from lupa.lua51 import LuaRuntime
except ImportError as exc:
    raise SystemExit("Install development-only lupa with: python -m pip install lupa==2.6") from exc

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
focus = parser.add_mutually_exclusive_group()
focus.add_argument("--tiles-only", action="store_true", help="run only the focused development tile-probe checks")
focus.add_argument("--composite-only", action="store_true", help="run only the focused RFC experimental composite checks")
focus.add_argument("--production-only", action="store_true", help="run only RFC normal-viewer source, rendering and lifecycle regressions")
focus.add_argument("--multi-only", action="store_true", help="run only generated-registry, ground renderer, overlay and authoring checks")
focus.add_argument("--resolver-only", action="store_true", help="run only build-provenance/source-resolution regression checks")
args = parser.parse_args()
toc = (root / "DungeonLens.toc").read_text(encoding="utf-8")
assert "## Interface: 16001" in toc
assert "## SavedVariables: DungeonLensDB" in toc
files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
assert files == ["Core.lua", "MapData.lua", "MapRegistry.lua", "DungeonLevels.lua", "DungeonEntrances.lua", "WMOComposition.lua", "BossData.lua", "LootData.lua", "MarkerData.lua", "MapDetector.lua", "Overlay.lua",
                 "MapRenderer.lua", "DungeonWindow.lua", "SeenLoot.lua", "BossPanel.lua", "BossList.lua", "EntranceCard.lua", "MinimapButton.lua", "Authoring.lua", "PositionProbe.lua", "Diagnostics.lua", "CompositePreview.lua"]

lua = LuaRuntime(unpack_returned_tuples=True)
assert lua.eval("_VERSION") == "Lua 5.1"
lua.globals().AddonFiles = lua.table_from(files)
lua.globals().AddonSources = lua.table_from(
    {name: (root / name).read_text(encoding="utf-8") for name in files}
)
if args.tiles_only:
    lua.globals().ValidationFocus = "tiles"
    lua.globals().TileProbeSmokeSource = (root / "scripts" / "TileProbeSmoke.lua").read_text(encoding="utf-8")
if args.composite_only:
    lua.globals().ValidationFocus = "composite"
    lua.globals().CompositeSmokeSource = (root / "scripts" / "CompositeSmoke.lua").read_text(encoding="utf-8")
    lua.globals().ExpectedRFC = lua.table_from(json.loads((root / "scripts" / "RFC-WMO-70124.json").read_text(encoding="utf-8")), recursive=True)
if args.production_only:
    lua.globals().ValidationFocus = "production"
    lua.globals().ProductionSmokeSource = (root / "scripts" / "ProductionSmoke.lua").read_text(encoding="utf-8")
    lua.globals().ExpectedRFC = lua.table_from(json.loads((root / "scripts" / "RFC-WMO-70124.json").read_text(encoding="utf-8")), recursive=True)
if args.multi_only:
    lua.globals().ValidationFocus = "multi"
    lua.globals().MultiSmokeSource = (root / "scripts" / "MultiDungeonSmoke.lua").read_text(encoding="utf-8")
    lua.globals().ProjectionVectors = lua.table_from(
        json.loads((root / "scripts" / "generated" / "projection-vectors.json").read_text(encoding="utf-8")), recursive=True)
if args.resolver_only:
    lua.globals().ValidationFocus = "resolver"
    lua.globals().ResolverSmokeSource = (root / "scripts" / "ResolverSmoke.lua").read_text(encoding="utf-8")
lua.execute((root / "scripts" / "Smoke.lua").read_text(encoding="utf-8"))
metadata_script = root / "scripts" / "Inspect-MapMetadata.py"
ast.parse(metadata_script.read_text(encoding="utf-8"), filename=str(metadata_script))
print(f"PASS: TOC/load order, all {len(files)} Lua files compile and execute under Lua 5.1.")
print("PASS: read-only metadata audit Python syntax (no network used by this validation).")
print("In-game acceptance remains pending; the UI/API stubs are not Forever runtime evidence.")
