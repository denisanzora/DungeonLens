"""Shared read-only Wago metadata client for the DungeonLens tooling.

Standard library only. Every request is pinned to one explicit client build
(`version=` for CASC file bytes, `build=` for DB2 CSV). Responses are cached on
disk under scripts/.cache/<build>/ (git-ignored) so repeated runs are cheap and
deterministic. Nothing here writes game artwork into the repository: BLP files
are only ever header-sniffed (20 bytes) unless a caller explicitly asks for the
bytes for a throwaway preview in a temp directory.
"""

import csv
import hashlib
import io
import json
import os
import re
import time
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

PRODUCT = "wow_classic_beta"
UA = "DungeonLens-discovery/0.2"
CACHE_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
DEFAULT_BUILD_INFO = r"E:\World of Warcraft\.build.info"
MAX_BYTES = 8 * 1024 * 1024


def installed_build(path=DEFAULT_BUILD_INFO):
    """Return (version, buildKeyHex) from the local Battle.net .build.info."""
    with open(path, encoding="utf-8") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]
    header = [column.split("!")[0] for column in lines[0].split("|")]
    for line in lines[1:]:
        row = dict(zip(header, line.split("|")))
        if row.get("Product") == PRODUCT and row.get("Active") == "1":
            return row["Version"], row["Build Key"]
    raise ValueError("No active " + PRODUCT + " row in " + path)


class Wago:
    def __init__(self, build, use_cache=True):
        self.build = build
        self.use_cache = use_cache
        self.dir = os.path.join(CACHE_ROOT, build)
        os.makedirs(self.dir, exist_ok=True)
        self.requests = []

    # -- transport -------------------------------------------------------
    def _cache_path(self, key, ext):
        digest = hashlib.sha1(key.encode()).hexdigest()[:20]
        return os.path.join(self.dir, digest + ext)

    def _get(self, url, headers=None, limit=MAX_BYTES, retries=3):
        request = Request(url, headers={"User-Agent": UA, **(headers or {})})
        last = None
        for attempt in range(retries):
            try:
                with urlopen(request, timeout=60) as response:
                    data = response.read(limit + 1)
                    if len(data) > limit and "Range" not in (headers or {}):
                        raise ValueError("Response exceeded size limit: " + url)
                    return response.status, data
            except HTTPError as exc:
                if exc.code in (400, 404):
                    return exc.code, b""
                last = exc
            except URLError as exc:
                last = exc
            time.sleep(1.5 * (attempt + 1))
        raise RuntimeError("Request failed: " + url + " " + str(last))

    # -- build provenance ------------------------------------------------
    def latest_build(self):
        status, data = self._get("https://wago.tools/api/builds/%s/latest" % PRODUCT)
        return json.loads(data)

    # -- DB2 --------------------------------------------------------------
    def db2(self, name, limit=MAX_BYTES):
        path = self._cache_path("db2/" + name, ".csv")
        if self.use_cache and os.path.exists(path):
            text = open(path, encoding="utf-8").read()
        else:
            url = "https://wago.tools/db2/%s/csv?%s" % (name, urlencode({"build": self.build}))
            status, data = self._get(url, limit=limit)
            text = data.decode("utf-8-sig")
            if status != 200 or text.lstrip().startswith("<") or not text.strip():
                raise ValueError("DB2 export unavailable: %s (HTTP %s)" % (name, status))
            open(path, "w", encoding="utf-8").write(text)
        return list(csv.DictReader(io.StringIO(text)))

    # -- CASC bytes --------------------------------------------------------
    def file(self, fdid, header_only=False):
        """Return bytes of a FileDataID at this exact build, or None on 404."""
        path = self._cache_path(("hdr/" if header_only else "full/") + str(fdid), ".bin")
        if self.use_cache and os.path.exists(path):
            blob = open(path, "rb").read()
            return None if blob == b"\x00MISSING" else blob
        url = "https://wago.tools/api/casc/%d?%s" % (fdid, urlencode({"version": self.build}))
        headers = {"Range": "bytes=0-19"} if header_only else None
        status, data = self._get(url, headers)
        if status == 200 or status == 206:
            data = data[:20] if header_only else data
            open(path, "wb").write(data)
            return data
        if status in (400, 404):
            open(path, "wb").write(b"\x00MISSING")
            return None
        raise RuntimeError("Unexpected HTTP %s for %s" % (status, url))

    def file_prefix(self, fdid, length):
        """First `length` bytes of a file (cached), or None on 404."""
        path = self._cache_path("pfx%d/%d" % (length, fdid), ".bin")
        if self.use_cache and os.path.exists(path):
            blob = open(path, "rb").read()
            return None if blob == b"\x00MISSING" else blob
        url = "https://wago.tools/api/casc/%d?%s" % (fdid, urlencode({"version": self.build}))
        status, data = self._get(url, {"Range": "bytes=0-%d" % (length - 1)})
        if status in (200, 206):
            data = data[:length]
            open(path, "wb").write(data)
            return data
        if status in (400, 404):
            open(path, "wb").write(b"\x00MISSING")
            return None
        raise RuntimeError("Unexpected HTTP %s for %s" % (status, url))

    # -- file catalog (names/history only; NOT build membership proof) -----
    def catalog(self, search, max_pages=400):
        key = "files/" + search
        path = self._cache_path(key, ".json")
        if self.use_cache and os.path.exists(path):
            return json.load(open(path, encoding="utf-8"))
        result, total = [], None
        for page in range(1, max_pages + 1):
            url = "https://wago.tools/files?" + urlencode({"search": search, "page": page})
            status, data = self._get(url)
            parser = _Inertia()
            parser.feed(data.decode("utf-8"))
            if parser.page is None:
                raise ValueError("File catalog page unreadable: " + url)
            listing = parser.page["props"]["files"]
            total = listing["total"]
            result.extend(listing["data"])
            if not listing["next_page_url"]:
                break
        else:
            raise ValueError("File catalog pagination limit reached for " + search)
        if len(result) != total:
            raise ValueError("Incomplete file catalog for %r: %d of %d" % (search, len(result), total))
        json.dump(result, open(path, "w", encoding="utf-8"))
        return result

    def catalog_prefix(self, prefix):
        """Catalog entries whose filename starts with prefix (case-insensitive)."""
        lowered = prefix.lower()
        return [entry for entry in self.catalog(prefix) if entry["filename"].lower().startswith(lowered)]

    def path_of(self, fdid):
        """Listfile name for a FileDataID, or None when the listfile has none."""
        for entry in self.catalog(str(fdid)):
            if entry["fdid"] == fdid:
                return entry["filename"]
        return None


class _Inertia(HTMLParser):
    page = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "div" and values.get("id") == "app" and "data-page" in values:
            self.page = json.loads(values["data-page"])


def blp_header(blob):
    import struct
    if blob is None or len(blob) < 20 or blob[:4] != b"BLP2":
        raise ValueError("Unrecognized BLP header")
    width, height = struct.unpack_from("<II", blob, 12)
    return width, height


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
