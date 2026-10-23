"""S2C: standalone LOW small-CSV and gdalinfo-only preflight. No pixel API.

Original files are inspected only on a later operator invocation. Tests use a
separate explicit synthetic scope. Native manifests cannot prove runtime 02F
input lineage; metadata completeness never enables S2B or a hydrological route.
"""
import argparse
import csv
from dataclasses import asdict, dataclass, field
from decimal import Decimal
from hashlib import sha256
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time

PARENT_SHA = "b461b4cd85ce8c4e5f94de320830c136c450265a"
PROJECT = Path("/scratch/project_2004707/pienvedet/csc_validation_4bbf22b")
RUN_RELATIVE = Path("hydro_01_02/runs/E200000_N6900000")
RUN = PROJECT / RUN_RELATIVE
TILE = "E200000_N6900000"
WINDOW = (3293, 3844, 52, 73)  # Future scope reference ONLY, never a GDAL argument.
HISTORIC_02F = "402fdbf16cb41eaa6a3ad2180cc4d3af8534e32cff299d73eacec8dc5c187db5"
SMALL_LIMIT = 2 * 1024 * 1024
OUT_LIMIT, ERR_LIMIT, REPORT_LIMIT = 1024 * 1024, 32768, 65536
CSV_FILES = (("manifest", "01_inputs/01_input_manifest.csv"),
             ("qa", "01_inputs/01_input_QA.csv"),
             ("routes", "02_baseline/02F_water_connected_route_evidence.csv"),
             ("neighbors", "02_baseline/02C_zero_pointer_water_neighbors.csv"),
             ("zero_cells", "02_baseline/02C_zero_pointer_cells.csv"))
MANIFEST_KEYS = ("pipeline_version", "run_mode", "test_id", "pointer_scheme", "cell_size_m",
                 "stream_threshold_ha", "dem", "ranta10_gpkg", "lake_id_raster", "river_area_raster",
                 "river_line_raster", "water_class_raster", "water_mask_raster", "lake_elevation_raster")
QA_VALUES = dict(dem_cols=6000, dem_rows=6000, dem_res_x=2, dem_res_y=2,
                 xmin=199000, xmax=211000, ymin=6899000, ymax=6911000)
QA_KEYS = tuple(QA_VALUES) + ("ranta10_lakes", "ranta10_river_areas", "ranta10_river_lines",
                            "lake_heights_valid", "lake_heights_missing", "lake_ids_raster")
ROUTE_FIELDS = ("route_id", "start_receiver_cell", "origin_lake_objectid", "terminal_cell",
                "terminal_water_class", "terminal_lake_objectid", "route_steps", "route_status")
NEIGHBOR_FIELDS = ("component_id", "source_cell", "water_cell", "water_class", "lake_objectid", "water_z_m")
ZERO_FIELDS = ("cell", "component_id", "x", "y", "z_m", "raster_edge")
# Pinned summary metadata; no intermediate chains or neighbor positions invented.
EXPECTED = ((11,23337318,21), (14,23343318,22), (15,23343319,22),
            (16,23343320,23), (18,23349320,23), (20,23355321,24))
TERMINAL = 23211319
STAGES = ("PATH_SCOPE", "SMALL_FILE_VERSIONS", "MANIFEST_SCHEMA", "INPUT_QA",
          "CSV_IDENTITIES", "GDAL_VERSION", "RASTER_METADATA", "RUNTIME_INPUT_LINEAGE")
METADATA_FLAGS = ("-json", "-nomd", "-noct", "-norat", "-nogcp", "-if", "GTiff")


class Stop(ValueError):
    pass


def need(condition, reason):
    if not condition:
        raise Stop(reason)


def safe_path(value):
    need(type(value) is str and 0 < len(value) <= 1024 and Path(value).is_absolute(), "ABSOLUTE_PATH_REQUIRED")
    need(".." not in Path(value).parts and not any(c in value for c in "\x00\r\n"), "UNSAFE_PATH")
    for part in Path(value).parts:
        need(not re.fullmatch(r"E[0-9]+_N[0-9]+", part) or part == TILE, "OTHER_TILE_FORBIDDEN")
    return Path(value)


def hash_text(value):
    need(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value), "INVALID_SHA256")
    return value


@dataclass(frozen=True)
class Request:
    project: str = str(PROJECT)
    kind: str = "ORIGINAL_METADATA_ONLY"
    expected_hashes: tuple = ()

    def __post_init__(self):
        p = safe_path(self.project)
        if self.kind == "ORIGINAL_METADATA_ONLY":
            need(p == PROJECT, "FIXED_ORIGINAL_LOW_ROOT_REQUIRED")
        else:
            need(self.kind == "SYNTHETIC" and p.parent == Path(tempfile.gettempdir()) and
                 p.name.startswith("mm-s2c-synthetic-"), "EXPLICIT_SYNTHETIC_SCOPE_REQUIRED")
        need(type(self.expected_hashes) is tuple and len(self.expected_hashes) <= 5, "HASH_BINDING_LIMIT")
        names = []
        for pair in self.expected_hashes:
            need(type(pair) is tuple and len(pair) == 2 and pair[0] in dict(CSV_FILES), "FIXED_CSV_BINDING_REQUIRED")
            names.append(pair[0])
            hash_text(pair[1])
        need(len(set(names)) == len(names), "DUPLICATE_HASH_BINDING")

    @property
    def run(self):
        return Path(self.project) / RUN_RELATIVE

    @property
    def allowed_root(self):
        # A manifest can name SOURCE_TEST_ROOT outside csc_validation_4bbf22b,
        # but never outside this project or another explicit E/N tile.
        return PROJECT.parent if self.kind == "ORIGINAL_METADATA_ONLY" else Path(self.project)


@dataclass(frozen=True)
class Version:
    path: str
    size_bytes: int
    mtime_ns: int
    ctime_ns: int
    device: int
    inode: int


def version(request, path):
    p = safe_path(str(path))
    need(p.is_relative_to(request.allowed_root) and p != request.allowed_root, "PATH_OUTSIDE_PROJECT")
    for component in reversed((p,) + tuple(p.parents)):
        need(not stat.S_ISLNK(os.lstat(component).st_mode), "SYMLINK_OR_ANCESTOR")
    info = os.lstat(p)
    need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size > 0, "REGULAR_UNALIASED_FILE_REQUIRED")
    return Version(str(p), info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_dev, info.st_ino)


def unchanged(request, recorded):
    need(version(request, recorded.path) == recorded, "SOURCE_CHANGED_DURING_PREFLIGHT")


def read_small(request, path):
    recorded = version(request, path)
    need(recorded.size_bytes <= SMALL_LIMIT, f"SMALL_FILE_SIZE_LIMIT path={recorded.path} bytes={recorded.size_bytes}")
    fd = os.open(recorded.path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        current = os.fstat(fd)
        need((current.st_dev,current.st_ino,current.st_size,current.st_mtime_ns,current.st_ctime_ns) ==
             (recorded.device,recorded.inode,recorded.size_bytes,recorded.mtime_ns,recorded.ctime_ns), "FILE_REPLACED_BEFORE_READ")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(SMALL_LIMIT + 1)
        need(len(raw) == recorded.size_bytes, "SMALL_FILE_SIZE_CHANGED")
    finally:
        os.close(fd)
    unchanged(request, recorded)
    return raw, recorded, sha256(raw).hexdigest()


def table(raw, expected_fields, label):
    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")), strict=True)
        fields = tuple(reader.fieldnames or ())
        need(len(fields) <= 32 and all(len(f) <= 128 for f in fields), "CSV_HEADER_RESOURCE_LIMIT " + label)
        need(fields == expected_fields,
             f"CSV_SCHEMA {label}: actual_fieldnames={json.dumps(fields)} expected={json.dumps(expected_fields)}")
        rows = []
        for row in reader:
            need(None not in row and all(v is not None and len(v) <= 1024 for v in row.values()), "CSV_ROW_WIDTH_OR_FIELD_SIZE")
            rows.append(row)
            need(len(rows) <= 20000, "CSV_FANOUT_LIMIT")
        need(rows, "EMPTY_CSV " + label)
        return rows
    except (UnicodeError, csv.Error) as exc:
        raise Stop("CSV_PARSE " + label + ": " + str(exc)[:100]) from None


def key_values(raw, field, expected, label):
    rows = table(raw, (field, "value"), label)
    need(len(rows) <= 32 and all(len(r[field]) <= 128 for r in rows), "KEY_VALUE_FANOUT_LIMIT")
    mapping = {r[field]: r["value"] for r in rows}
    need(len(mapping) == len(rows), "DUPLICATE_KEY " + label)
    need(set(mapping) == set(expected),
         f"NATIVE_KEYS {label}: actual={json.dumps(tuple(mapping))} expected={json.dumps(expected)}")
    return mapping


def integer(value, null=False, maximum=2147483647):
    if null and value in ("", "NA", "NaN"):
        return None
    need(type(value) is str and len(value) <= 10 and re.fullmatch(r"[0-9]+", value), "EXACT_CSV_INTEGER")
    result = int(value)
    need(result <= maximum, "CSV_INTEGER_RANGE")
    return result


def finite(value):
    need(type(value) is str and len(value) <= 64 and re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", value), "FINITE_CSV_NUMBER")
    need(math.isfinite(float(value)), "NONFINITE_CSV_NUMBER")
    return Decimal(value)


def center(cell):
    need(1 <= cell <= 36000000, "CELL_OUTSIDE_LOW")
    row,col = divmod(cell-1,6000)
    return 199001+2*col, 6910999-2*row


def identities(route_raw, neighbor_raw, zero_raw):
    routes = table(route_raw, ROUTE_FIELDS, "02F")
    ids = [integer(row["route_id"]) for row in routes]
    need(all(ids) and len(set(ids)) == len(ids), "DUPLICATE_OR_INVALID_ROUTE_ID")
    chosen = []
    expected_by_id = {rid:(start,steps) for rid,start,steps in EXPECTED}
    for row in routes:
        rid = integer(row["route_id"])
        if rid not in expected_by_id:
            continue
        start,steps = expected_by_id[rid]
        recovered = tuple(integer(row[key], key.startswith("terminal_") and key != "terminal_cell")
                          for key in ROUTE_FIELDS[:-1]) + (row["route_status"],)
        need(recovered == (rid,start,1894,TERMINAL,None,None,steps,"D8_ZERO_INTERIOR"),
             "CONTRADICTORY_02F_IDENTITY route_id=" + str(rid))
        chosen.append(recovered)
    need(len(chosen) == 6, "MISSING_PINNED_ROUTE")
    neighbors = table(neighbor_raw, NEIGHBOR_FIELDS, "02C_neighbors")
    selected = []
    for row in neighbors:
        if integer(row["component_id"]) != 274:
            continue
        source,water,klass,lake = (integer(row[k]) for k in ("source_cell","water_cell","water_class","lake_objectid"))
        need((source,klass,lake) == (TERMINAL,1,1892), "CONTRADICTORY_02C_IDENTITY")
        center(water)
        r,c = divmod(source-1,6000)
        wr,wc = divmod(water-1,6000)
        need(max(abs(r-wr),abs(c-wc)) == 1, "NONADJACENT_02C_NEIGHBOR")
        finite(row["water_z_m"])  # Existing CSV schema check, never emitted as a pixel value.
        selected.append((274,source,water,klass,lake))
    need(len(selected) == 3 and len({r[2] for r in selected}) == 3, "02C_EXACT_THREE_UNIQUE_NEIGHBORS")
    zeros = table(zero_raw, ZERO_FIELDS, "02C_zero_cells")
    cells = [integer(row["cell"]) for row in zeros]
    need(all(cells) and len(cells) == len(set(cells)), "DUPLICATE_ZERO_CELL")
    terminal = [row for row in zeros if integer(row["cell"]) == TERMINAL]
    need(len(terminal) == 1, "MISSING_TERMINAL_ZERO_RECORD")
    row = terminal[0]
    need(integer(row["component_id"]) == 274 and (finite(row["x"]),finite(row["y"])) == center(TERMINAL) and
         row["raster_edge"] == "FALSE", "CONTRADICTORY_TERMINAL_ZERO_RECORD")
    finite(row["z_m"])
    return tuple(sorted(chosen)), tuple(sorted(selected)), len(routes)


def unique_json(pairs):
    out = {}
    for k,v in pairs:
        need(k not in out, "DUPLICATE_GDAL_JSON_KEY")
        out[k] = v
    return out


def metadata(raw, role):
    def invalid(value):
        raise Stop("NONFINITE_GDAL_JSON")
    try:
        m = json.loads(raw, object_pairs_hook=unique_json, parse_constant=invalid)
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise Stop("INVALID_GDAL_JSON: " + str(exc)[:100]) from None
    need(type(m) is dict, "GDAL_JSON_OBJECT_REQUIRED")
    need(m.get("driverShortName") == "GTiff" and m.get("size") == [6000,6000] and
         all(type(v) is int for v in m["size"]), "DRIVER_OR_DIMENSIONS")
    transform = m.get("geoTransform")
    need(transform == [199000,2,0,6911000,0,-2] and
         all(type(v) in (int,float) and math.isfinite(v) for v in transform), "GEOTRANSFORM_OR_RESOLUTION")
    crs = m.get("coordinateSystem", {})
    need(type(crs) is dict and type(crs.get("wkt")) is str and
         re.search(r'ID\["EPSG",\s*3067\]\]\s*$',crs["wkt"]) and
         crs.get("dataAxisToSRSAxisMapping") == [1,2], "CRS_OR_AXIS_MAPPING")
    proj = m.get("stac", {}).get("proj:projjson", {})
    need(proj.get("type") == "ProjectedCRS" and proj.get("id") == {"authority":"EPSG","code":3067}, "PROJJSON_CRS")
    conversion = proj.get("conversion", {})
    need(conversion.get("method", {}).get("id") == {"authority":"EPSG","code":9807}, "PROJECTION_METHOD")
    parameters = conversion.get("parameters", [])
    observed = {(p.get("id", {}).get("code"),p.get("unit")):p.get("value") for p in parameters}
    need(len(parameters) == 5 and all(type(p.get("value")) in (int,float) and math.isfinite(p["value"]) for p in parameters) and observed == {(8801,"degree"):0,(8802,"degree"):27,(8805,"unity"):0.9996,
                                             (8806,"metre"):500000,(8807,"metre"):0}, "PROJECTION_PARAMETERS")
    base = proj.get("base_crs", {})
    ellipsoid = base.get("datum", {}).get("ellipsoid", {})
    need(base.get("id") in ({"authority":"EPSG","code":4258},{"authority":"EPSG","code":10690}) and
         ellipsoid.get("semi_major_axis") == 6378137 and ellipsoid.get("inverse_flattening") == 298.257222101,
         "BASE_CRS_OR_ELLIPSOID")
    axes = proj.get("coordinate_system", {}).get("axis", [])
    need(len(axes) == 2 and [(v.get("direction"),v.get("unit")) for v in axes] == [("east","metre"),("north","metre")],
         "PROJECTED_UNITS_OR_AXES")
    corners = m.get("cornerCoordinates", {})
    need(corners.get("upperLeft") == [199000,6911000] and corners.get("lowerRight") == [211000,6899000] and
         corners.get("center") == [205000,6905000], "EXTENT_OR_CENTER")
    bands = m.get("bands", [])
    need(type(bands) is list and len(bands) == 1 and type(bands[0]) is dict and bands[0].get("band") == 1, "BAND_COUNT")
    band = bands[0]
    dtype = band.get("type")
    allowed = ("Byte","UInt16","Int16","UInt32","Int32","Float32","Float64")
    need(dtype in allowed and (role != "pointer" or dtype == "Float64"), "DTYPE_OR_POINTER_NOT_FLT8S")
    need(type(band.get("scale",1)) in (int,float) and type(band.get("offset",0)) in (int,float) and
         band.get("scale",1) == 1 and band.get("offset",0) == 0 and not band.get("mask") and not band.get("overviews"),
         "SCALE_OFFSET_MASK_OR_OVERVIEW")
    nd = band.get("noDataValue")
    if nd == "NaN":
        need(dtype in ("Float32","Float64"), "NAN_IN_INTEGER_BAND")
    else:
        need(type(nd) in (int,float) and math.isfinite(nd), "EXPLICIT_FINITE_OR_NAN_NODATA_REQUIRED")
        ranges = {"Byte":(0,255),"UInt16":(0,65535),"Int16":(-32768,32767),
                  "UInt32":(0,4294967295),"Int32":(-2147483648,2147483647)}
        if dtype in ranges:
            lo,hi = ranges[dtype]
            need(nd == int(nd) and lo <= nd <= hi, "NODATA_DTYPE_RANGE")
        need(not (role == "pointer" and nd == 0), "AMBIGUOUS_ZERO_POINTER_NODATA")
        need(not (role == "water_class" and nd in (1,2,3)), "VALID_WATER_CLASS_AS_NODATA")
        need(not (role == "lake_id" and nd > 0), "POSITIVE_LAKE_ID_AS_NODATA")
    # No arrays/stats/minmax/histograms appear in this result.
    return dtype, nd, sha256(crs["wkt"].encode()).hexdigest()


class InfoOnly:
    """Hard command whitelist; capped pipes while subprocess.run waits."""
    def __init__(self, executable, sources):
        p = safe_path(executable)
        need(p.name == "gdalinfo", "GDALINFO_ONLY")
        self.executable = str(p)
        self.sources = tuple(sources)
        need(len(self.sources) == 3 and len(set(self.sources)) == 3, "THREE_EXACT_METADATA_SOURCES")
        self.calls, self.stdout_bytes = 0, 0
        self.deadline = time.monotonic()+40

    def command(self, args):
        args = tuple(args)
        allowed = ((self.executable,"--version"),) + tuple((self.executable,)+METADATA_FLAGS+(s,) for s in self.sources)
        need(args in allowed, "METADATA_COMMAND_WHITELIST")
        need(self.calls < 4 and time.monotonic() < self.deadline, "METADATA_RESOURCE_BUDGET")
        self.calls += 1
        streams = []
        for cap in (OUT_LIMIT,ERR_LIMIT):
            readfd,writefd = os.pipe()
            state = {"data":bytearray(),"overflow":False,"error":False}
            def collect(fd=readfd,limit=cap,state=state):
                try:
                    while True:
                        chunk = os.read(fd,8192)
                        if not chunk:break
                        if len(state["data"])+len(chunk)>limit:
                            state["overflow"] = True
                            break
                        state["data"].extend(chunk)
                except OSError:
                    state["error"] = True
                finally:os.close(fd)
            thread = threading.Thread(target=collect,daemon=True)
            thread.start()
            streams.append((writefd,state,thread))
        failure = None
        try:
            result = subprocess.run(args,shell=False,stdin=subprocess.DEVNULL,stdout=streams[0][0],stderr=streams[1][0],
                                    timeout=max(0.001,min(10,self.deadline-time.monotonic())),check=False,close_fds=True,cwd="/",
                                    env={"PATH":os.defpath,"LC_ALL":"C","GDAL_PAM_ENABLED":"NO",
                                         "GDAL_DISABLE_READDIR_ON_OPEN":"EMPTY_DIR","GDAL_DRIVER_PATH":"disable",
                                         "GDAL_CACHEMAX":"32","GDAL_NUM_THREADS":"1","PROJ_NETWORK":"OFF"})
        except subprocess.TimeoutExpired:failure = "GDALINFO_TIMEOUT"
        except (OSError,ValueError):failure = "GDALINFO_EXECUTION_FAILURE"
        finally:
            for fd,_,_ in streams:os.close(fd)
            for _,_,thread in streams:thread.join(timeout=1)
        need(not any(t.is_alive() for _,_,t in streams),"PIPE_TIMEOUT")
        need(not any(v["overflow"] for _,v,_ in streams),"GDALINFO_OUTPUT_SIZE_LIMIT")
        need(not any(v["error"] for _,v,_ in streams),"PIPE_READ_ERROR")
        need(failure is None,failure)
        need(result.returncode == 0 and not streams[1][1]["data"],"GDALINFO_EXIT_OR_WARNING")
        raw = bytes(streams[0][1]["data"])
        self.stdout_bytes += len(raw)
        return raw


@dataclass(frozen=True)
class CSVVersion:
    role: str
    version: Version
    sha256: str
    fieldnames: tuple


@dataclass(frozen=True)
class Raster:
    role: str
    version: Version
    path_basis: str
    dtype: str
    nodata: int | float | str
    epsg: int
    geotransform: tuple
    crs_wkt_sha256: str
    raster_content_sha256: str = field(default="NOT_CHECKED",init=False)
    raster_values: str = field(default="NOT_RUN",init=False)
    source_status: str = field(default="PRESENT_METADATA_ONLY",init=False)
    band_count: int = field(default=1,init=False)
    width: int = field(default=6000,init=False)
    height: int = field(default=6000,init=False)
    resolution_m: tuple = field(default=(2,2),init=False)
    extent: tuple = field(default=(199000,211000,6899000,6911000),init=False)
    first_cell_center: tuple = field(default=(199001,6910999),init=False)
    last_cell_center: tuple = field(default=(210999,6899001),init=False)


@dataclass(frozen=True)
class Report:
    kind: str
    metadata_status: str
    stages: tuple
    error: str | None
    csv_versions: tuple
    manifest_entries: tuple
    raster_metadata: tuple
    selected_routes: tuple
    selected_neighbors: tuple
    full_route_count: int
    historic_02f_sha256_match: bool | None
    gdal_version: str
    gdal_stdout_bytes: int
    code_lineage_reference: str = field(default=PARENT_SHA,init=False)
    overall_status: str = field(default="STOP",init=False)
    stop_reason: str = field(default="RUNTIME_PRODUCER_LINK_UNVERIFIED_NO_PIXEL_PERMISSION",init=False)
    RUNTIME_INPUT_LINEAGE: str = field(default="NOT_ASSESSED",init=False)
    RUNTIME_PRODUCER_COMMIT: str = field(default="UNKNOWN",init=False)
    SOURCE_AUTHENTICATION: str = field(default="NOT_ASSESSED",init=False)
    raster_pixel_reads: int = field(default=0,init=False)
    future_window: tuple = field(default=WINDOW,init=False)
    S2A_REPLAY: str = field(default="NOT_RUN",init=False)
    TRUE_02F_CONTINUITY: str = field(default="NOT_RUN",init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED",init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED",init=False)
    NATIONAL: str = field(default="LOCKED",init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED",init=False)
    routing_authorized: bool = field(default=False,init=False)
    outlet_selection: str = field(default="UNASSIGNED",init=False)


def preflight(request=Request(), executable=None):
    need(type(request) is Request,"TYPED_REQUEST_REQUIRED")
    stages = dict.fromkeys(STAGES,"NOT_RUN")
    stage = STAGES[0]
    csv_versions,entries,rasters,routes,neighbors = [],(),[],(),()
    count, historic, gdal_version = 0,None,"NOT_RUN"
    runner = None
    error = None
    try:
        if request.kind == "SYNTHETIC":
            p = os.lstat(request.project)
            need(stat.S_ISDIR(p.st_mode) and p.st_uid == os.getuid() and stat.S_IMODE(p.st_mode)&0o077 == 0,
                 "PRIVATE_SYNTHETIC_DIRECTORY_REQUIRED")
        paths = {name:request.run/relative for name,relative in CSV_FILES}
        for p in paths.values():version(request,p)
        stages[stage] = "PASS"
        stage = "SMALL_FILE_VERSIONS"
        blobs = {}
        for role,path in paths.items():
            raw,snapshot,digest = read_small(request,path)
            # Record the actual headers even when a later schema check STOPs.
            try:fieldnames = tuple(next(csv.reader(io.StringIO(raw.decode("utf-8-sig")))))
            except (StopIteration,csv.Error,UnicodeError):fieldnames = ()
            if len(fieldnames) > 32 or any(len(f) > 128 for f in fieldnames):
                fieldnames = ("HEADER_EXCEEDS_RESOURCE_LIMIT",)
            csv_versions.append(CSVVersion(role,snapshot,digest,fieldnames))
            need(role not in dict(request.expected_hashes) or dict(request.expected_hashes)[role] == digest,
                 "EXPECTED_CSV_SHA256_MISMATCH " + role)
            blobs[role] = raw
        historic = next(c.sha256 for c in csv_versions if c.role == "routes") == HISTORIC_02F
        stages[stage] = "PASS"
        stage = "MANIFEST_SCHEMA"
        rows = table(blobs["manifest"],("key","value"),"01_manifest")
        entries = tuple((r["key"],r["value"]) for r in rows[:32])
        manifest = key_values(blobs["manifest"],"key",MANIFEST_KEYS,"01_manifest")
        need(manifest["pipeline_version"] == "2.0-baseline-no-structures" and manifest["run_mode"] in ("LOCAL_TEST","CSC_TEST") and
             manifest["test_id"] == TILE and manifest["pointer_scheme"] == "whitebox" and finite(manifest["cell_size_m"]) == 2,
             "NATIVE_MANIFEST_LOW_CONFIGURATION")
        # Do not derive SOURCE_TEST_ROOT from the DEM or execute R config.
        water,lake = safe_path(manifest["water_class_raster"]),safe_path(manifest["lake_id_raster"])
        need(water.parent == lake.parent and water.name == "ranta10_water_class.tif" and lake.name == "ranta10_lake_id.tif",
             "MANIFEST_VS_REVIEWED_SOURCE_TEST_ROOT_CONTRACT")
        pointer = request.run/"02_baseline/d8_pointer_land_water_FLT8S.tif"
        sources = (("pointer",pointer,"REVIEWED_02B_CODE_PATH_CANDIDATE"),
                   ("water_class",water,"01_MANIFEST_CLAIM_NOT_RUNTIME_AUTHENTICATED"),
                   ("lake_id",lake,"01_MANIFEST_CLAIM_NOT_RUNTIME_AUTHENTICATED"))
        snapshots = tuple(version(request,p) for _,p,_ in sources)
        need(len({(v.device,v.inode) for v in snapshots}) == 3,"ALIASED_RASTER_SOURCES")
        stages[stage] = "PASS"
        stage = "INPUT_QA"
        qa = key_values(blobs["qa"],"item",QA_KEYS,"01_QA")
        need(all(finite(qa[k]) == v for k,v in QA_VALUES.items()),"INPUT_QA_LOW_GEOMETRY")
        for key in QA_KEYS[len(QA_VALUES):]:integer(qa[key])
        stages[stage] = "PASS"
        stage = "CSV_IDENTITIES"
        routes,neighbors,count = identities(blobs["routes"],blobs["neighbors"],blobs["zero_cells"])
        stages[stage] = "PASS"
        stage = "GDAL_VERSION"
        executable = executable or shutil.which("gdalinfo")
        need(executable is not None,"GDALINFO_NOT_LOADED_MODULE_GDAL_3_12_2")
        runner = InfoOnly(executable,tuple(v.path for v in snapshots))
        raw = runner.command((runner.executable,"--version")).decode("ascii").strip()
        need(len(raw) <= 256 and len(raw.splitlines()) == 1 and re.match(r'^GDAL 3\.12\.2(?:[ ,]|$)',raw),"GDAL_3_12_2_REQUIRED")
        gdal_version = raw
        stages[stage] = "PASS"
        stage = "RASTER_METADATA"
        for (role,_,basis),snapshot in zip(sources,snapshots):
            unchanged(request,snapshot)
            raw = runner.command((runner.executable,)+METADATA_FLAGS+(snapshot.path,))
            dtype,nd,wkt_hash = metadata(raw,role)
            unchanged(request,snapshot)
            rasters.append(Raster(role,snapshot,basis,dtype,nd,3067,(199000,2,0,6911000,0,-2),wkt_hash))
        for observed in csv_versions:unchanged(request,observed.version)
        need(time.monotonic() <= runner.deadline,"METADATA_TOTAL_TIMEOUT")
        stages[stage] = "PASS"
        stage = "RUNTIME_INPUT_LINEAGE"
        stages[stage] = "STOP"  # Native schemas have no verifiable 02F producer link.
    except (Stop,OSError,UnicodeError,TypeError,KeyError,AttributeError,OverflowError) as exc:
        error = str(exc)
        stages[stage] = "STOP"
    return Report(request.kind,"PASS" if error is None else "STOP",tuple(stages.items()),error,
                  tuple(csv_versions),entries,tuple(rasters),routes,neighbors,count,historic,
                  gdal_version,runner.stdout_bytes if runner else 0)


def framed(report):
    need(type(report) is Report,"REPORT_REQUIRED")
    body = json.dumps(asdict(report),sort_keys=True,separators=(",",":"),allow_nan=False)
    body = body.replace("===", "\\u003d\\u003d\\u003d")
    if len(body.encode()) > REPORT_LIMIT:
        # Still emit one framed, locked STOP on adversarial report amplification.
        compact = asdict(report)
        for key in ("csv_versions","manifest_entries","raster_metadata","selected_routes","selected_neighbors"):
            compact[key] = []
        compact.update(metadata_status="STOP", error="COMPACT_REPORT_SIZE_LIMIT_DETAILS_OMITTED",
                       stages=tuple((s,"STOP" if s == "PATH_SCOPE" else "NOT_RUN") for s in STAGES))
        body = json.dumps(compact,sort_keys=True,separators=(",",":"),allow_nan=False)
    # Preserve untrusted field text after JSON decoding, but never let it
    # inject a second visible framing marker into the transport.
    body = body.replace("===", "\\u003d\\u003d\\u003d")
    return "=== TULOKSET ALKAVAT ===\n"+body+"\n=== TULOKSET LOPPUVAT ===\n"


class Parser(argparse.ArgumentParser):
    def error(self,message):
        raise Stop("CLI_ARGUMENTS: "+message)


def main(argv=None):
    parser = Parser(add_help=False)
    parser.add_argument("--expect-02f-sha256")
    def timed_out(signum, frame):
        raise Stop("TOTAL_PREFLIGHT_TIMEOUT")
    old_handler = signal.signal(signal.SIGALRM, timed_out)
    old_alarm = signal.alarm(60)
    try:
        args = parser.parse_args(argv)
        bindings = () if args.expect_02f_sha256 is None else (("routes",hash_text(args.expect_02f_sha256)),)
        report = preflight(Request(expected_hashes=bindings))
    except Stop as exc:
        report = Report("ORIGINAL_METADATA_ONLY","STOP",tuple((s,"STOP" if s == "PATH_SCOPE" else "NOT_RUN") for s in STAGES),
                        str(exc),(),(),(),(),(),0,None,"NOT_RUN",0)
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)
        if old_alarm:
            signal.alarm(old_alarm)
    sys.stdout.write(framed(report))
    return 2  # Metadata-only STOP, never an authorization/success signal for replay.


if __name__ == "__main__":
    raise SystemExit(main())
