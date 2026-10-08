"""Read native WDT/WMO metadata in memory from Wago's versioned CASC endpoint.

Standard library only. No CASC software installation or client changes. No
artwork/files are written. BLP inspection reads only the 20-byte image header.
"""

import argparse
import hashlib
import json
import math
import struct
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BUILD = "1.60.1.70124"
PRODUCT = "wow_classic_beta"
BUILD_CONFIG = "dd3dfc2881c407299f46c2aaf34c130b"
CDN_CONFIG = "43061ca8e9f0e2603c8ab50bcae97c2d"


def native_file(file_id, version=BUILD, header_only=False):
    # Wago documents product as selecting the latest build. Use version ONLY
    # for an exact-build request, never combine the two selectors.
    url = f"https://wago.tools/api/casc/{file_id}?" + urlencode({"version": version})
    headers = {"User-Agent": "DungeonLens-placement-metadata/0.1"}
    if header_only:
        headers["Range"] = "bytes=0-19"
    try:
        with urlopen(Request(url, headers=headers), timeout=30) as response:
            limit = 20 if header_only else 5 * 1024 * 1024
            data = response.read(limit if header_only else limit + 1)
            if len(data) > limit:
                raise ValueError("Native metadata file exceeds size limit")
            evidence = {"url": url, "httpStatus": response.status, "bytesRead": len(data),
                        "headers": {key: value for key, value in response.headers.items()
                                    if key.lower() in ("content-type", "content-length", "content-range",
                                                       "content-disposition", "etag", "last-modified")}}
            if not header_only:
                evidence.update(md5=hashlib.md5(data).hexdigest(), sha256=hashlib.sha256(data).hexdigest())
            return data, evidence
    except HTTPError as exc:
        return None, {"url": url, "httpStatus": exc.code}


def chunks(data):
    result = {}
    offset = 0
    while offset < len(data):
        if len(data) - offset < 8:
            raise ValueError("Truncated chunk header")
        magic, size = struct.unpack_from("<4sI", data, offset)
        offset += 8
        if offset + size > len(data):
            raise ValueError("Truncated chunk payload")
        name = magic[::-1].decode("ascii")
        if name in result:
            raise ValueError("Duplicate metadata chunk: " + name)
        result[name] = data[offset:offset + size]
        offset += size
    return result


def parse_root(data):
    values = chunks(data)
    if len(values.get("MVER", b"")) != 4 or len(values.get("MOHD", b"")) < 64:
        raise ValueError("Not a supported root WMO")
    version = struct.unpack("<I", values["MVER"])[0]
    if version != 17:
        raise ValueError("Unverified WMO layout version")
    count = struct.unpack_from("<I", values["MOHD"], 4)[0]
    if count == 0 or count > 512:
        raise ValueError("Invalid WMO group count")
    mogi = values.get("MOGI", b"")
    if len(mogi) != count * 32:
        raise ValueError("MOGI count/stride mismatch")
    names = values.get("MOGN", b"")
    groups = []
    for index in range(count):
        row = struct.unpack_from("<I6fi", mogi, index * 32)
        if not all(math.isfinite(value) for value in row[1:7]):
            raise ValueError("Non-finite MOGI bounds")
        if any(row[1 + axis] > row[4 + axis] for axis in range(3)):
            raise ValueError("Reversed MOGI bounds")
        name = None
        if 0 <= row[7] < len(names):
            name = names[row[7]:].split(b"\0", 1)[0].decode("cp1252")
        groups.append({"groupIndex": index, "flags": row[0], "flagsHex": hex(row[0]),
                       "minimum": list(row[1:4]), "maximum": list(row[4:7]), "name": name})
    gfids = values.get("GFID", b"")
    if gfids and len(gfids) >= count * 4:
        for group, file_id in zip(groups, struct.unpack_from(f"<{count}I", gfids)):
            group["groupFileDataID"] = file_id
    mesh_minimum = [min(group["minimum"][axis] for group in groups) for axis in range(3)]
    mesh_maximum = [max(group["maximum"][axis] for group in groups) for axis in range(3)]
    return {"version": version, "groupCount": count, "chunkNames": list(values), "groups": groups,
            "meshBounds": {"minimum": mesh_minimum, "maximum": mesh_maximum,
                           "extent": [mesh_maximum[axis] - mesh_minimum[axis] for axis in range(3)]}}


def parse_wdt(data):
    values = chunks(data)
    report = {"chunkNames": list(values)}
    if "MWMO" in values:
        report["MWMOPaths"] = [item.decode("ascii") for item in values["MWMO"].split(b"\0") if item]
    modf = values.get("MODF", b"")
    if modf:
        if len(modf) != 64:
            raise ValueError("Expected one global WDT MODF record")
        report["globalMODF"] = {
            "nameOrFileID": struct.unpack_from("<I", modf)[0],
            "position": list(struct.unpack_from("<3f", modf, 8)),
            "rotation": list(struct.unpack_from("<3f", modf, 20)),
            "flags": struct.unpack_from("<H", modf, 56)[0],
        }
    return report


def json_metadata(url):
    with urlopen(Request(url, headers={"User-Agent": "DungeonLens-placement-metadata/0.1"}), timeout=30) as response:
        return json.loads(response.read(5 * 1024 * 1024))


def parse_blp_header(header):
    if len(header) != 20 or header[:4] != b"BLP2" or struct.unpack_from("<I", header, 4)[0] != 1:
        raise ValueError("Unverified BLP header")
    width, height = struct.unpack_from("<II", header, 12)
    if width == 0 or height == 0:
        raise ValueError("Invalid native image dimensions")
    return {"magic": "BLP2", "width": width, "height": height}


def main(provenance_only=False):
    report = {"requestedBuild": BUILD, "product": PRODUCT, "rootCandidateFileDataID": 109483}
    build = json_metadata(f"https://wago.tools/api/builds/{PRODUCT}/latest")
    report["providerBuild"] = build
    report["providerMatchesInstalledBuild"] = (build.get("version") == BUILD and build.get("product") == PRODUCT
        and build.get("build_config") == BUILD_CONFIG and build.get("cdn_config") == CDN_CONFIG)
    root, report["rootResponse"] = native_file(109483)
    if root is not None:
        report["rootWMO"] = parse_root(root)
    control, report["invalidVersionControl"] = native_file(109483, "0.0.0.0")
    report["invalidVersionReturnedSameRoot"] = control is not None and control == root
    older, report["knownVersionControl"] = native_file(109483, "1.13.0.28211")
    report["knownVersionControlMatchesCatalog"] = older is not None and hashlib.md5(older).hexdigest() == "55eb044562adccf8b36251cd2a86b74e"
    wdt, report["wdtResponse"] = native_file(789981)
    if wdt is not None:
        report["wdt"] = parse_wdt(wdt)
    report["tileHeaderSamples"] = []
    for file_id in (() if provenance_only else range(213056, 213075)):
        header, evidence = native_file(file_id, header_only=True)
        if header is not None and len(header) == 20 and header[:4] == b"BLP2":
            evidence.update(fileDataID=file_id, **parse_blp_header(header))
        else:
            evidence.update(fileDataID=file_id, recognizedBLP2Header=False)
        report["tileHeaderSamples"].append(evidence)
    report["versionScopedSourceValidated"] = (report["providerMatchesInstalledBuild"]
        and root is not None and report["rootResponse"]["httpStatus"] == 200
        and report["invalidVersionControl"]["httpStatus"] == 400 and report["knownVersionControlMatchesCatalog"]
        and report.get("wdt", {}).get("globalMODF", {}).get("nameOrFileID") == 109483
        and report.get("wdt", {}).get("globalMODF", {}).get("flags", 0) & 8 != 0)
    report["localByteEqualityVerified"] = False
    report["placementReady"] = False
    report["provenanceNote"] = "Version-scoped online source, separate from local byte equality. MOGI/BLP sizes do not supply exact raster density or padding."
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provenance-only", action="store_true", help="skip the already-sampled nineteen BLP headers")
    main(parser.parse_args().provenance_only)
