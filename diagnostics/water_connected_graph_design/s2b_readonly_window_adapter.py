"""S2B synthetic-only, bounded GTiff -> Float64 AAIGrid stdout -> immutable S2A inputs.

No CLI, output-path argument, source writer, raster hash scan or real-data mode.
Original data require separately reviewed source authentication and authorization.
"""
from dataclasses import asdict, dataclass, field, fields
from hashlib import sha256
from decimal import Decimal
import csv
import io
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import threading
import time

import s2a_pure_d8_trace as s2a

Stop = s2a.Stop
GDAL_VERSION = "3.12.2"
WINDOW = (3293, 3844, 52, 73)
VALUE_COUNT = 3796
STDOUT_LIMIT = 1024 * 1024
STDERR_LIMIT = 32768
SMALL_FILE_LIMIT = 2 * 1024 * 1024
STAGES = ("INPUT_QA", "RESOURCE_BOUND", "CSV_PROVENANCE", "WINDOW_READ",
          "S2A_TRACE_PARITY", "WATER_NEIGHBOR_PARITY")
TYPES = {"Byte", "Int16", "UInt16", "Int32", "UInt32", "Float32", "Float64"}
ROLES = ("pointer", "water_class", "lake_id")


def require(ok, reason):
    if not ok:
        raise Stop(reason)


def exact_keys(value, keys):
    require(type(value) is dict and set(value) == set(keys), "UNKNOWN_OR_MISSING_FIELDS")


def hash_string(value):
    require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value), "INVALID_SHA256")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def json_value(raw):
    def forbidden(value):
        raise Stop("NONFINITE_JSON")
    try:
        return json.loads(raw, object_pairs_hook=unique_object, parse_constant=forbidden)
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise Stop("INVALID_JSON: " + str(exc)[:100]) from None


@dataclass(frozen=True)
class Request:
    root: str
    qa: str
    manifest: str
    provenance: str
    routes: str
    neighbors: str
    pointer: str
    water_class: str
    lake_id: str
    provenance_sha256: str
    evidence_kind: str = "SYNTHETIC"

    def __post_init__(self):
        hash_string(self.provenance_sha256)
        require(self.evidence_kind == "SYNTHETIC", "REAL_DATA_NOT_AUTHORIZED_IN_S2B_FIXTURE_PHASE")
        for name in ("root", "qa", "manifest", "provenance", "routes", "neighbors") + ROLES:
            p = getattr(self, name)
            require(type(p) is str and 0 < len(p) <= 1024 and Path(p).is_absolute(), "ABSOLUTE_PATH_REQUIRED")
            require(".." not in Path(p).parts and not any(ch in p for ch in "\x00\r\n"), "UNSAFE_PATH")
        root = Path(self.root)
        require(root.parent == Path(tempfile.gettempdir()) and root.name.startswith("mm-s2b-synthetic-"),
                "DISPOSABLE_SYNTHETIC_SCOPE_REQUIRED")
        require(len({getattr(self, name) for name in ("qa", "manifest", "provenance", "routes", "neighbors") + ROLES}) == 8,
                "DISTINCT_SOURCE_PATHS_REQUIRED")


@dataclass(frozen=True)
class Version:
    path: str
    size_bytes: int
    device: int
    inode: int
    mtime_ns: int
    ctime_ns: int


def file_version(root, path):
    p, scope = Path(path), Path(root)
    require(p.is_absolute() and ".." not in p.parts and p.is_relative_to(scope) and p != scope, "PATH_OUTSIDE_SCOPE")
    # Reject symlinks in ANY ancestor before handing a path to GDAL.
    for ancestor in reversed((p,) + tuple(p.parents)):
        require(not stat.S_ISLNK(os.lstat(ancestor).st_mode), "SYMLINK_SOURCE_OR_ANCESTOR")
    info = os.lstat(p)
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size > 0, "SOURCE_NOT_PRIVATE_REGULAR_FILE")
    return Version(str(p), info.st_size, info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns)


def unchanged(root, version):
    require(file_version(root, version.path) == version, "SOURCE_CHANGED_DURING_PREFLIGHT")


def small_file(root, path):
    version = file_version(root, path)
    require(version.size_bytes <= SMALL_FILE_LIMIT, "SMALL_FILE_SIZE_LIMIT")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require((info.st_dev, info.st_ino, info.st_size) == (version.device, version.inode, version.size_bytes),
                "SOURCE_CHANGED_BEFORE_READ")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(SMALL_FILE_LIMIT + 1)
        require(len(raw) == version.size_bytes and len(raw) <= SMALL_FILE_LIMIT, "SMALL_FILE_SIZE_CHANGED")
    finally:
        os.close(fd)
    unchanged(root, version)
    return raw, version, sha256(raw).hexdigest()


def csv_rows(raw, mandatory):
    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")), strict=True)
        names = reader.fieldnames
        require(names and len(set(names)) == len(names) and set(mandatory).issubset(names), "CSV_SCHEMA")
        result = []
        for row in reader:
            require(None not in row and all(v is not None for v in row.values()), "CSV_ROW_WIDTH")
            result.append(row)
            require(len(result) <= 20000, "CSV_ROW_LIMIT")
        require(result, "CSV_EMPTY")
        return result
    except (UnicodeError, csv.Error):
        raise Stop("CSV_PARSE") from None


def int_value(value, nullable=False):
    if nullable and value in ("", "NA", "NaN"):
        return None
    require(type(value) is str and len(value) <= 10 and re.fullmatch(r"[0-9]+", value), "CSV_EXACT_NONNEGATIVE_INTEGER")
    number = int(value)
    require(number <= s2a.MAX_LAKE_ID, "CSV_INTEGER_RANGE")
    return number


def original_rows(route_bytes, neighbor_bytes):
    required = tuple(f.name for f in fields(s2a.Summary))
    routes = csv_rows(route_bytes, required)
    ids = [int_value(r["route_id"]) for r in routes]
    require(len(set(ids)) == len(ids) and all(v > 0 for v in ids), "DUPLICATE_OR_INVALID_ROUTE_ID")
    selected = []
    for row in routes:
        if int_value(row["route_id"]) in (11, 14, 15, 16, 18, 20):
            values = {name: int_value(row[name], name in ("terminal_water_class", "terminal_lake_objectid"))
                      for name in required if name != "route_status"}
            selected.append(s2a.Summary(**values, route_status=row["route_status"]))
    selected = s2a.locked_summaries(selected)
    neighbors = csv_rows(neighbor_bytes, ("component_id", "source_cell", "water_cell", "water_class", "lake_objectid"))
    chosen = []
    for row in neighbors:
        if int_value(row["component_id"]) == 274:
            chosen.append(s2a.Neighbor(274, int_value(row["source_cell"]), int_value(row["water_cell"]),
                                      int_value(row["water_class"]), int_value(row["lake_objectid"], True)))
    require(len(chosen) == 3 and len({n.water_cell for n in chosen}) == 3, "02C_EXACT_THREE_NEIGHBORS")
    require(all((n.source_cell, n.water_class, n.lake_id) == (s2a.TERMINAL, 1, 1892) for n in chosen),
            "02C_CHANGED_SOURCE_CLASS_OR_LAKE")
    return selected, tuple(sorted(chosen, key=lambda n: n.water_cell))


class Runner:
    """subprocess.run with concurrent capped pipes, no unbounded capture_output.

    Close an overflowing pipe immediately; terminate/wait is still bounded by
    subprocess.run's timeout. No raster output or stderr is written to disk.
    """
    def __init__(self, timeout=10.0):
        require(type(timeout) in (int, float) and 0 < timeout <= 10, "PROCESS_TIMEOUT_BOUND")
        self.timeout = timeout
        self.bytes_read = 0
        self.calls = 0

    def run(self, args, limit=STDOUT_LIMIT, remaining=60):
        require(type(args) in (tuple, list) and args and all(type(a) is str for a in args), "ARGV_REQUIRED")
        require(Path(args[0]).is_absolute(), "ABSOLUTE_EXECUTABLE_REQUIRED")
        require(type(limit) is int and 1 <= limit <= STDOUT_LIMIT, "STDOUT_SIZE_BOUND")
        require(remaining > 0, "TOTAL_TIMEOUT")
        require(self.calls < 8, "GDAL_COMMAND_BUDGET")
        streams = []
        for cap in (limit, STDERR_LIMIT):
            readfd, writefd = os.pipe()
            state = {"data": bytearray(), "overflow": False, "error": False}
            def collect(fd=readfd, bound=cap, state=state):
                try:
                    while True:
                        chunk = os.read(fd, min(8192, bound + 1))
                        if not chunk:
                            break
                        if len(state["data"]) + len(chunk) > bound:
                            state["overflow"] = True
                            break
                        state["data"].extend(chunk)
                except OSError:
                    state["error"] = True
                finally:
                    os.close(fd)
            thread = threading.Thread(target=collect, daemon=True)
            thread.start()
            streams.append((writefd, state, thread))
        self.calls += 1
        failure = None
        try:
            result = subprocess.run(tuple(args), shell=False, stdin=subprocess.DEVNULL,
                                    stdout=streams[0][0], stderr=streams[1][0],
                                    timeout=min(self.timeout, remaining), cwd="/",
                                    env={"PATH": os.defpath, "LC_ALL": "C", "GDAL_PAM_ENABLED": "NO",
                                         "GDAL_DISABLE_READDIR_ON_OPEN": "EMPTY_DIR", "GDAL_DRIVER_PATH": "disable",
                                         "GDAL_CACHEMAX": "32", "GDAL_NUM_THREADS": "1", "PROJ_NETWORK": "OFF"},
                                    close_fds=True, check=False)
        except subprocess.TimeoutExpired:
            failure = "GDAL_TIMEOUT"
        except (OSError, ValueError):
            failure = "GDAL_EXECUTION_FAILED"
        finally:
            for fd, _, _ in streams:
                os.close(fd)
            for _, _, thread in streams:
                thread.join(timeout=1)
        require(not any(t.is_alive() for _, _, t in streams), "PIPE_COLLECTION_TIMEOUT")
        require(not any(st["overflow"] for _, st, _ in streams), "PROCESS_OUTPUT_SIZE_LIMIT")
        require(not any(st["error"] for _, st, _ in streams), "PIPE_READ_ERROR")
        require(failure is None, failure)
        require(result.returncode == 0, "GDAL_NONZERO_EXIT_NO_FALLBACK")
        require(not streams[1][1]["data"], "GDAL_WARNING_REQUIRES_REVIEW")
        raw = bytes(streams[0][1]["data"])
        self.bytes_read += len(raw)
        return raw


@dataclass(frozen=True)
class Tools:
    info: str = "/usr/bin/gdalinfo"
    translate: str = "/usr/bin/gdal_translate"

    def __post_init__(self):
        for value, name in ((self.info, "gdalinfo"), (self.translate, "gdal_translate")):
            require(type(value) is str and len(value) <= 1024 and Path(value).is_absolute() and
                    ".." not in Path(value).parts and Path(value).name == name and
                    not any(c in value for c in "\x00\r\n"), "EXPLICIT_TOOL_PATH_REQUIRED")


def info_args(tools, path):
    return (tools.info, "-json", "-nomd", "-noct", "-norat", "-nogcp", "-if", "GTiff", path)


def window_args(tools, path):
    return (tools.translate, "-q", "-if", "GTiff", "-of", "AAIGrid",
            "-co", "SIGNIFICANT_DIGITS=17", "-a_srs", "none", "-b", "1",
            "-srcwin", "3293", "3844", "52", "73", path, "/vsistdout/")


def nodata_spec(value):
    require(type(value) is dict and value.get("kind") in ("FINITE", "NAN"), "EXPLICIT_BAND_NODATA_REQUIRED")
    exact_keys(value, ("kind", "value") if value["kind"] == "FINITE" else ("kind",))
    if value["kind"] == "FINITE":
        require(type(value["value"]) in (int, float) and math.isfinite(value["value"]), "NODATA_NOT_FINITE")
    return value


def verify_metadata(raw, expected, role):
    info = json_value(raw)
    require(type(info) is dict, "RASTER_METADATA_OBJECT_REQUIRED")
    require(info.get("driverShortName") == "GTiff" and info.get("size") == [6000, 6000], "RASTER_DRIVER_OR_DIMENSIONS")
    require(info.get("geoTransform") == [199000, 2, 0, 6911000, 0, -2], "RASTER_AFFINE_OR_ORIGIN")
    crs = info.get("coordinateSystem", {})
    require(type(crs) is dict, "RASTER_CRS_OBJECT_REQUIRED")
    require(crs.get("dataAxisToSRSAxisMapping") == [1, 2] and
            re.search(r'ID\["EPSG",\s*3067\]\]\s*$', crs.get("wkt", "")), "RASTER_CRS")
    corners = info.get("cornerCoordinates", {})
    require(type(corners) is dict, "RASTER_CORNERS_OBJECT_REQUIRED")
    require(corners.get("upperLeft") == [199000, 6911000] and
            corners.get("lowerRight") == [211000, 6899000] and corners.get("center") == [205000, 6905000],
            "RASTER_EXTENT_OR_CENTER")
    bands = info.get("bands", [])
    require(type(bands) is list and len(bands) == 1 and type(bands[0]) is dict and bands[0].get("band") == 1, "RASTER_BAND_COUNT")
    band = bands[0]
    require(expected["dtype"] in TYPES and band.get("type") == expected["dtype"], "RASTER_DTYPE")
    require(band.get("scale", 1) == 1 and band.get("offset", 0) == 0 and not band.get("overviews"),
            "SCALE_OFFSET_OR_OVERVIEW_UNSUPPORTED")
    require(not band.get("mask"), "EXTERNAL_OR_INTERNAL_MASK_UNSUPPORTED")
    nd = nodata_spec(expected["nodata"])
    actual = band.get("noDataValue")
    if nd["kind"] == "NAN":
        require(actual == "NaN" and expected["dtype"] in ("Float32", "Float64"), "NODATA_MISMATCH")
    else:
        require(type(actual) in (int, float) and actual == nd["value"], "NODATA_MISMATCH")
        require(not (role == "pointer" and actual == 0), "ZERO_POINTER_CANNOT_BE_NODATA")
        require(not (role == "water_class" and actual in (1, 2, 3)), "WATER_CLASS_CANNOT_BE_NODATA")
        require(not (role == "lake_id" and actual > 0), "POSITIVE_LAKE_ID_CANNOT_BE_NODATA")
    return band["type"], json.dumps(nd, sort_keys=True, separators=(",", ":"))


NUMBER = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\Z")


def normalized_value(token, nd, role):
    require(len(token) <= 64, "NUMERIC_TOKEN_SIZE")
    if token.lower() in ("nan", "+nan", "-nan"):
        require(nd["kind"] == "NAN", "UNDECLARED_NAN")
        value = s2a.Missing.NAN
    else:
        require(NUMBER.fullmatch(token), "XYZ_VALUE_SYNTAX")
        number = float(token)
        require(math.isfinite(number), "XYZ_NONFINITE_OR_PRECISION")
        decimal = Decimal(token)
        if nd["kind"] == "FINITE" and number == nd["value"]:
            # A valid Float32/Float64 NoData sentinel may exceed 2**53.
            # Recognize it before applying S2A's finite-data magnitude cap.
            require(abs(number) > 2**53 or decimal == Decimal(str(nd["value"])), "XYZ_NUMERIC_ROUNDING")
            value = s2a.Missing.NULL
        else:
            require(abs(number) <= 2**53, "XYZ_NONFINITE_OR_PRECISION")
            # Never round a fractional pointer/lake ID into a valid integer
            # code or D8=0, including floating-point underflow.
            require(not number.is_integer() or decimal == int(number), "XYZ_NUMERIC_ROUNDING")
            value = number
    if not s2a.absent(value):
        if role == "lake_id":
            require(value == int(value) and 0 < value <= s2a.MAX_LAKE_ID, "INVALID_LAKE_ID")
        elif role == "water_class":
            require(value in (1, 2, 3), "INVALID_WATER_CLASS")
    return value


def parse_ascii(raw, nodata, role):
    """Strict AAIGrid stdout: six fixed headers, then exactly 73 rows x 52."""
    require(type(raw) is bytes and len(raw) <= STDOUT_LIMIT, "ASCII_SIZE_LIMIT")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeError:
        raise Stop("ASCII_NON_ASCII") from None
    require(len(lines) == 79, "ASCII_EXACT_HEADER_AND_ROWS")
    expected = (("ncols", 52), ("nrows", 73), ("xllcorner", 205586),
                ("yllcorner", 6903166), ("cellsize", 2))
    for line, (key, value) in zip(lines[:5], expected):
        pair = line.split()
        require(len(pair) == 2 and pair[0].lower() == key and len(pair[1]) <= 64 and
                NUMBER.fullmatch(pair[1]) and Decimal(pair[1]) == value, "ASCII_FIXED_WINDOW_HEADER")
    pair = lines[5].split()
    nd = nodata_spec(nodata)
    require(len(pair) == 2 and pair[0].lower() == "nodata_value", "ASCII_NODATA_HEADER")
    require(s2a.absent(normalized_value(pair[1], nd, role)), "ASCII_NODATA_MISMATCH")
    rows = []
    for line in lines[6:]:
        tokens = line.split()
        require(len(tokens) == 52, "ASCII_EXACT_ROW_WIDTH")
        rows.append(tuple(normalized_value(token, nd, role) for token in tokens))
    return tuple(rows)


def parse_xyz(raw, nodata, role):
    require(type(raw) is bytes and len(raw) <= STDOUT_LIMIT, "XYZ_SIZE_LIMIT")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeError:
        raise Stop("XYZ_NON_ASCII") from None
    require(len(lines) == VALUE_COUNT, "XYZ_EXACT_CELL_COUNT")
    nd = nodata_spec(nodata)
    values = []
    for index, line in enumerate(lines):
        parts = line.split()
        require(len(parts) == 3 and all(len(p) <= 64 for p in parts), "XYZ_THREE_BOUNDED_FIELDS")
        row, col = divmod(index, 52)
        ex, ey = s2a.center(s2a.cell_id(3844 + row, 3293 + col))
        require(NUMBER.fullmatch(parts[0]) and NUMBER.fullmatch(parts[1]), "XYZ_COORDINATE_SYNTAX")
        require((Decimal(parts[0]), Decimal(parts[1])) == (ex, ey), "XYZ_CENTER_ORDER_OR_ALIGNMENT")
        value = normalized_value(parts[2], nd, role)
        values.append(value)
    return tuple(tuple(values[r*52:(r+1)*52]) for r in range(73))


@dataclass(frozen=True)
class Source:
    role: str
    path: str
    size_bytes: int
    version: Version
    dtype: str
    nodata: str
    lineage_id: str
    declared_sha256: str
    actual_raster_sha256: str = field(default="NOT_CHECKED", init=False)


@dataclass(frozen=True)
class Report(s2a.Locks):
    diagnostic_result: str
    evidence_kind: str
    stages: tuple
    error: str | None
    gdal_version: str
    window: tuple
    values_returned: int
    stdout_bytes: int
    csv_versions: tuple
    sources: tuple[Source, ...]
    route_comparisons: tuple
    shared_cell_count: int
    in_memory_sha256: str | None
    SOURCE_AUTHENTICATION: str = field(default="NOT_ASSESSED", init=False)
    SOURCE_PROVENANCE: str = field(default="NOT_ASSESSED", init=False)
    real_raster_parity: str = field(default="NOT_ASSESSED", init=False)


def compact_json(report):
    require(type(report) is Report and report.diagnostic_result in ("PASS", "FAIL"), "REPORT_TYPE_OR_STATE")
    return json.dumps(asdict(report), sort_keys=True, separators=(",", ":"), allow_nan=False)


@dataclass(frozen=True)
class Result:
    report: Report
    data: s2a.WindowData | None
    traces: tuple[s2a.Trace, ...]


def preflight(request, tools=Tools()):
    """Synthetic scope only. Invalid evidence returns a locked FAIL report."""
    require(type(request) is Request and type(tools) is Tools, "REQUEST_AND_TOOLS_REQUIRED")
    stage = STAGES[0]
    stages = {s: "NOT_RUN" for s in STAGES}
    versions, sources, comparisons, traces = [], [], [], ()
    data = None
    error = None
    observed_version = "NOT_RUN"
    value_count = shared_count = 0
    runner = Runner()
    deadline = time.monotonic() + 60
    def command(args, limit=STDOUT_LIMIT):
        return runner.run(args, limit=limit, remaining=deadline-time.monotonic())
    try:
        require(WINDOW == (3293, 3844, 52, 73) and s2a.prove_low_window() == s2a.Window(), "FIXED_WINDOW_GUARD")
        scope = os.lstat(request.root)
        require(stat.S_ISDIR(scope.st_mode) and scope.st_uid == os.getuid() and
                stat.S_IMODE(scope.st_mode) & 0o077 == 0, "PRIVATE_FIXTURE_DIRECTORY_REQUIRED")
        snapshots = {name: file_version(request.root, getattr(request, name)) for name in
                     ("qa", "manifest", "provenance", "routes", "neighbors") + ROLES}
        require(len({(v.device, v.inode) for v in snapshots.values()}) == 8, "ALIASED_SOURCE_FILES")
        raw, _, digest = small_file(request.root, request.provenance)
        require(digest == request.provenance_sha256, "PROVENANCE_DOCUMENT_HASH_CHANGED")
        proof = json_value(raw)
        exact_keys(proof, ("schema_version", "evidence_kind", "producer_commit", "pointer_scheme", "esri_pntr", "files", "rasters"))
        require(proof["schema_version"] == "s2b.synthetic.v1" and proof["evidence_kind"] == "SYNTHETIC", "SYNTHETIC_PROVENANCE_REQUIRED")
        require(proof["pointer_scheme"] == "WHITEBOX_D8" and proof["esri_pntr"] is False, "WRONG_D8_CONVENTION")
        require(type(proof["producer_commit"]) is str and re.fullmatch(r"[0-9a-f]{40}", proof["producer_commit"]), "PRODUCER_COMMIT")
        exact_keys(proof["files"], ("qa", "manifest", "routes", "neighbors"))
        exact_keys(proof["rasters"], ROLES)
        stages[stage] = "PASS"
        stage = "RESOURCE_BOUND"
        for exe in (tools.info, tools.translate):
            version = command((exe, "--version"), 4096).decode("ascii").strip()
            require(re.match(r'^GDAL 3\.12\.2(?:[ ,]|$)', version), "GDAL_3_12_2_REQUIRED")
        observed_version = GDAL_VERSION
        stages[stage] = "PASS"
        stage = "CSV_PROVENANCE"
        payload = {}
        versions.append(("provenance", request.provenance, digest))
        for name in ("qa", "manifest", "routes", "neighbors"):
            binding = proof["files"][name]
            exact_keys(binding, ("path", "sha256"))
            require(binding["path"] == getattr(request, name), "EXPLICIT_FILE_PATH_MISMATCH")
            raw, _, digest = small_file(request.root, binding["path"])
            require(hash_string(binding["sha256"]) == digest, "CSV_FILE_HASH_CHANGED")
            payload[name] = raw
            versions.append((name, binding["path"], digest))
        qa_rows = csv_rows(payload["qa"], ("item", "value"))
        qa = {row["item"]: row["value"] for row in qa_rows}
        require(len(qa) == len(qa_rows), "DUPLICATE_QA_ITEM")
        expected_qa = dict(dem_cols=6000, dem_rows=6000, dem_res_x=2, dem_res_y=2,
                           xmin=199000, xmax=211000, ymin=6899000, ymax=6911000)
        require(all(name in qa and NUMBER.fullmatch(qa[name]) and float(qa[name]) == v
                    for name, v in expected_qa.items()), "INPUT_QA_GRID")
        manifest_rows = csv_rows(payload["manifest"], ("key", "value"))
        manifest = {row["key"]: row["value"] for row in manifest_rows}
        require(len(manifest) == len(manifest_rows), "DUPLICATE_MANIFEST_KEY")
        require(manifest.get("water_class_raster") == request.water_class and
                manifest.get("lake_id_raster") == request.lake_id and
                manifest.get("pointer_scheme") == "whitebox" and manifest.get("test_id") == "E200000_N6900000" and
                manifest.get("cell_size_m") == "2", "INPUT_MANIFEST_BINDING")
        summaries, neighbors = original_rows(payload["routes"], payload["neighbors"])
        stages[stage] = "PASS"
        stage = "WINDOW_READ"
        for role in ROLES:
            binding = proof["rasters"][role]
            exact_keys(binding, ("path", "size_bytes", "dtype", "nodata", "lineage_id", "sha256_claim"))
            path = getattr(request, role)
            version = snapshots[role]
            require(binding["path"] == path and Path(path).suffix.lower() in (".tif", ".tiff"), "EXPLICIT_GTIFF_PATH_BINDING")
            require(type(binding["size_bytes"]) is int and binding["size_bytes"] == version.size_bytes, "RASTER_SIZE_CHANGED")
            s2a.text_id(binding["lineage_id"], "lineage_id")
            hash_string(binding["sha256_claim"])
            unchanged(request.root, version)
            dtype, nd = verify_metadata(command(info_args(tools, path)), binding, role)
            unchanged(request.root, version)
            sources.append(Source(role, path, version.size_bytes, version, dtype, nd,
                                  binding["lineage_id"], binding["sha256_claim"]))
        # ALL metadata must pass before the first cell-value extraction.
        arrays = []
        for role in ROLES:
            unchanged(request.root, snapshots[role])
            output = command(window_args(tools, getattr(request, role)))
            arrays.append(parse_ascii(output, proof["rasters"][role]["nodata"], role))
            value_count += VALUE_COUNT
            unchanged(request.root, snapshots[role])
        for version in snapshots.values():
            unchanged(request.root, version)
        provenance = s2a.Provenance("SYNTHETIC", request.pointer, request.water_class, request.lake_id,
                                   "s2b.synthetic.v1", proof["producer_commit"], dict((v[0], v[2]) for v in versions)["routes"])
        data = s2a.WindowData(s2a.Grid(), s2a.Window(), provenance, *arrays)
        stages[stage] = "PASS"
        stage = "S2A_TRACE_PARITY"
        # A fixture CSV cannot have the original LOW SHA. Use actual CSV rows
        # and actual fixture hash with S2A's pure helpers, NEVER spoof audit_low's pin.
        traces = tuple(s2a.trace(data, row.route_id, row.start_receiver_cell, row.origin_lake_objectid) for row in summaries)
        for expected, recovered in zip(summaries, traces):
            actual = None if recovered.stop_reason else recovered.summary()
            mismatches = tuple(f.name for f in fields(s2a.Summary) if actual is None or
                               getattr(actual, f.name) != getattr(expected, f.name))
            comparisons.append((expected.route_id, recovered.route_status, recovered.route_steps,
                                recovered.terminal_cell, recovered.stop_reason, mismatches))
        require(all(not row[-1] and row[-2] is None for row in comparisons), "S2A_SUMMARY_PARITY")
        shared_count = len(s2a.aggregate(traces).shared_cells)
        stages[stage] = "PASS"
        stage = "WATER_NEIGHBOR_PARITY"
        require(s2a.neighbor_parity(data, neighbors), "02C_RASTER_NEIGHBOR_PARITY")
        stages[stage] = "PASS"
        require(time.monotonic() <= deadline, "TOTAL_TIMEOUT")
    except (Stop, OSError, UnicodeError, TypeError, KeyError, OverflowError) as exc:
        error = str(exc)[:256]
        stages[stage] = "STOP"
        if any(code in error for code in ("SIZE_LIMIT", "TIMEOUT", "COMMAND_BUDGET", "CSV_ROW_LIMIT")):
            stages["RESOURCE_BOUND"] = "STOP"
    report = Report("FAIL" if error else "PASS", "SYNTHETIC", tuple(stages.items()), error,
                    observed_version, WINDOW, value_count, runner.bytes_read, tuple(versions),
                    tuple(sources), tuple(comparisons), shared_count, data.content_sha256 if data else None)
    return Result(report, data, traces)
