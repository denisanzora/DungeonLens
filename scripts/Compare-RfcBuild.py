"""Read-only version-scoped RFC metadata comparison; no artwork files written.

This is supplementary source evidence, not an in-game texture-rendering test.
"""

import argparse
import csv
import importlib.util
import io
import json
from pathlib import Path
import sys
from urllib.parse import urlencode

sys.dont_write_bytecode = True
directory = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("dungeonlens_wmo_metadata", directory / "Inspect-WmoMetadata.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def main(version):
    baseline = json.loads((directory / "RFC-WMO-70124.json").read_text(encoding="utf-8"))
    provider = reader.json_metadata("https://wago.tools/api/builds/wow_classic_beta/latest")
    url = "https://wago.tools/db2/Map/csv?" + urlencode({"build": version, "filter[ID]": 389})
    with reader.urlopen(reader.Request(url, headers={"User-Agent": "DungeonLens-RFC-build-comparison/0.1"}), timeout=30) as response:
        records = list(csv.DictReader(io.StringIO(response.read(1024 * 1024).decode("utf-8-sig"))))
    world = next(row for row in records if int(row["ID"]) == 389)
    report = {"requestedVersion": version, "baselineVersion": baseline["build"], "providerBuild": provider,
              "mapRow": world, "mapSource": url, "baselineMetadataChanged": False,
              "inGameRenderingVerified": False}
    wdt, wdt_evidence = reader.native_file(int(world["WdtFileDataID"]), version)
    report["wdt"] = {"response": wdt_evidence}
    if wdt is None:
        print(json.dumps(report, indent=2)); return
    wdt_metadata = reader.parse_wdt(wdt)
    root_id = wdt_metadata.get("globalMODF", {}).get("nameOrFileID")
    report["wdt"].update(metadata=wdt_metadata, matchesBaselineHash=wdt_evidence["md5"] == baseline["wdtMD5"])
    root, root_evidence = reader.native_file(root_id, version)
    report["root"] = {"fileDataID": root_id, "response": root_evidence}
    if root is None:
        print(json.dumps(report, indent=2)); return
    root_metadata = reader.parse_root(root)
    report["root"].update(matchesBaselineHash=root_evidence["md5"] == baseline["rootMD5"],
                          groupCount=root_metadata["groupCount"],
                          groupFileDataIDs=[group.get("groupFileDataID") for group in root_metadata["groups"]])
    comparable = ("groupIndex", "flags", "minimum", "maximum", "groupFileDataID")
    report["mogiAndGroupIDsMatchBaseline"] = len(root_metadata["groups"]) == len(baseline["groups"]) and all(
        all(actual[key] == expected[key] for key in comparable)
        for actual, expected in zip(root_metadata["groups"], baseline["groups"]))
    report["tileHeaders"] = []
    for image in baseline["tileDimensions"]:
        header, evidence = reader.native_file(image["fileDataID"], version, header_only=True)
        result = {"fileDataID": image["fileDataID"], "response": evidence}
        if header is not None:
            try:
                dimensions = reader.parse_blp_header(header)
                result.update(dimensions, matchesBaselineSize=dimensions["width"] == image["width"] and dimensions["height"] == image["height"])
            except ValueError:
                result["recognizedHeader"] = False
        report["tileHeaders"].append(result)
    report["all19HeaderIDsAvailableWithSameDimensions"] = all(row.get("matchesBaselineSize") for row in report["tileHeaders"])
    report["pixelContentEqualityVerified"] = False
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="exact client version, for example 1.60.1.70170")
    main(parser.parse_args().version)
