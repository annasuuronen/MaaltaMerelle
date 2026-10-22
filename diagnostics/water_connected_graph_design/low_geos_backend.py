"""Bounded, read-only GeoPackage geometry queries via the GEOS C API.

Uses Python stdlib SQLite for GPKG geometry blobs, GEOS for topology/metric
operations. Requires libgeos_c available with the GDAL module. Does not depend
on Spatialite SQL functions, Python GDAL, shapely, R, or third-party Python.
"""
from __future__ import annotations

import atexit
import ctypes as C
from ctypes.util import find_library
from functools import lru_cache
import math
from pathlib import Path
import sqlite3
import struct
from urllib.parse import quote

CELL_IDS = (10007129, 10031127, 15389414, 15401414, 23211319, 23355315, 23373314)
LAKE_IDS = (1892, 1894, 3181)
SIZES = {"lakes": 24, "river_areas": 5, "river_lines": 30}


def require(ok, message):
    if not ok:
        raise ValueError("STOP: " + message)


def center(c):
    z = c - 1
    return 199001 + 2 * (z % 6000), 6910999 - 2 * (z // 6000)


def decode_gpkg_wkb(blob):
    require(isinstance(blob, bytes) and 13 <= len(blob) <= 30_000_000, "GPKG_BLOB_SIZE")
    require(blob[:2] == b"GP" and blob[2] == 0, "GPKG_MAGIC_VERSION")
    flags = blob[3]
    require(flags & 0xD0 == 0, "GPKG_FLAGS_UNSUPPORTED")
    envelope = (flags >> 1) & 7
    require(envelope in (0, 1, 2, 3, 4), "GPKG_ENVELOPE_UNSUPPORTED")
    srs = struct.unpack("<i" if flags & 1 else ">i", blob[4:8])[0]
    require(srs == 3067, "GPKG_GEOMETRY_SRS_NOT_3067")
    offset = 8 + (0, 32, 48, 48, 64)[envelope]
    require(len(blob) >= offset + 5 and blob[offset] in (0, 1), "GPKG_WKB_INVALID")
    return blob[offset:]


def point_wkb(x, y):
    require(math.isfinite(x) and math.isfinite(y), "BAD_POINT_COORD")
    return b"\x01" + struct.pack("<I2d", 1, x, y)


class Geos:
    def __init__(self):
        self.lib = None
        for path in (find_library("geos_c"), "libgeos_c.so.1", "libgeos_c.so"):
            if not path:
                continue
            try:
                self.lib = C.CDLL(path)
                break
            except OSError:
                pass
        require(self.lib is not None, "GEOS_C_NOT_AVAILABLE_IN_GDAL_ENV")
        lib = self.lib
        specs = {
            "GEOS_init_r": (C.c_void_p, []),
            "GEOS_finish_r": (None, [C.c_void_p]),
            "GEOSGeomFromWKB_buf_r": (C.c_void_p, [C.c_void_p, C.c_void_p, C.c_size_t]),
            "GEOSGeom_destroy_r": (None, [C.c_void_p, C.c_void_p]),
            "GEOSArea_r": (C.c_int, [C.c_void_p, C.c_void_p, C.POINTER(C.c_double)]),
            "GEOSDistance_r": (C.c_int, [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_double)]),
            "GEOSisValid_r": (C.c_byte, [C.c_void_p, C.c_void_p]),
            "GEOSIntersects_r": (C.c_byte, [C.c_void_p, C.c_void_p, C.c_void_p]),
            "GEOSTouches_r": (C.c_byte, [C.c_void_p, C.c_void_p, C.c_void_p]),
        }
        for name, (ret, args) in specs.items():
            require(hasattr(lib, name), "MISSING_GEOS_API_" + name)
            f = getattr(lib, name)
            f.restype, f.argtypes = ret, args
        self.ctx = lib.GEOS_init_r()
        require(bool(self.ctx), "GEOS_CONTEXT_FAILED")
        self.geom_handles = []
        self.closed = False

    def geom(self, wkb):
        data = C.create_string_buffer(wkb)
        pointer = self.lib.GEOSGeomFromWKB_buf_r(self.ctx, C.cast(data, C.c_void_p), len(wkb))
        require(bool(pointer), "GEOS_PARSE_WKB_FAILED")
        self.geom_handles.append(pointer)
        return pointer

    def measure(self, name, a, b=None):
        if name in ("valid", "intersects", "touches"):
            fn = {"valid": "GEOSisValid_r", "intersects": "GEOSIntersects_r", "touches": "GEOSTouches_r"}[name]
            ret = getattr(self.lib, fn)(self.ctx, a, *([b] if b is not None else []))
            require(ret in (0, 1), "GEOS_" + name.upper() + "_ERROR")
            return int(ret)
        value = C.c_double()
        fn = {"distance": "GEOSDistance_r", "area": "GEOSArea_r"}[name]
        ret = getattr(self.lib, fn)(self.ctx, a, *([b] if b is not None else []), C.byref(value))
        require(ret == 1 and math.isfinite(value.value), "GEOS_" + name.upper() + "_ERROR")
        return value.value

    def close(self):
        if not self.closed:
            for g in reversed(self.geom_handles):
                self.lib.GEOSGeom_destroy_r(self.ctx, g)
            self.lib.GEOS_finish_r(self.ctx)
            self.closed = True


class Store:
    def __init__(self, gpkg):
        self.geos = Geos()
        self.records = {}
        try:
            p = Path(gpkg)
            require(p.is_file() and not p.is_symlink(), "SOURCE_GPKG_NOT_REGULAR_FILE")
            uri = "file:" + quote(str(p.resolve()), safe="/") + "?mode=ro&immutable=1"
            con = sqlite3.connect(uri, uri=True, timeout=4)
            try:
                con.execute("PRAGMA query_only=ON")
                info = {name: (srs, geom) for name, srs, geom in
                        con.execute("SELECT table_name,srs_id,geometry_type_name FROM gpkg_geometry_columns")}
                for name, n in SIZES.items():
                    require(name in info and info[name][0] == 3067, "WRONG_GPKG_LAYER_SRS")
                    count = con.execute('SELECT COUNT(*) FROM "' + name + '"').fetchone()[0]
                    require(count == n, "GPKG_LAYER_COUNT_CHANGED_" + name)
                    cols = "objectid,korkeus_m,geom" if name == "lakes" else "geom"
                    rows = con.execute('SELECT ' + cols + ' FROM "' + name + '" LIMIT ' + str(n + 1)).fetchall()
                    require(len(rows) == n, "GPKG_ROW_COUNT_CHANGED_" + name)
                    chosen = []
                    for row in rows:
                        if name == "lakes":
                            ident, height, blob = row
                            if ident is None or not math.isfinite(float(ident)) or int(ident) != ident:
                                continue
                            lake_id = int(ident)
                            if lake_id not in LAKE_IDS:
                                continue
                            if height is not None:
                                require(math.isfinite(float(height)), "LAKE_HEIGHT_NONFINITE")
                            chosen.append((lake_id, "NA" if height is None else str(float(height)),
                                           self.geos.geom(decode_gpkg_wkb(blob))))
                        else:
                            chosen.append(self.geos.geom(decode_gpkg_wkb(row[0])))
                    if name == "lakes":
                        require(len(chosen) == 3 and {r[0] for r in chosen} == set(LAKE_IDS),
                                "LAKE_IDS_NOT_UNIQUE")
                    else:
                        require(len(chosen) == n, "RIVER_GEOM_COUNT_CHANGED")
                    self.records[name] = chosen
            finally:
                con.close()
            for lake_id, height, geom in self.records["lakes"]:
                require(self.geos.measure("valid", geom) == 1,
                        "INVALID_LAKE_GEOMETRY_" + str(lake_id))
        except Exception:
            self.geos.close()
            raise

    def query(self, label):
        g = self.geos
        lakes = {key: (height, geom) for key, height, geom in self.records["lakes"]}
        if label == "LAKE_INFO":
            return [{"lake_id": str(k), "lake_height_m": lakes[k][0],
                     "area_m2": str(round(g.measure("area", lakes[k][1]), 1)),
                     "geom_valid": "1"} for k in LAKE_IDS]
        if label == "LAKE_PAIR":
            a, b = lakes[1894][1], lakes[1892][1]
            return [{"distance_m": str(round(g.measure("distance", a, b), 2)),
                     "touches": str(g.measure("touches", a, b)),
                     "intersects": str(g.measure("intersects", a, b))}]
        if label == "CELL_LAKE":
            results = []
            for cell in CELL_IDS:
                p = g.geom(point_wkb(*center(cell)))
                for lake_id in LAKE_IDS:
                    lake = lakes[lake_id][1]
                    results.append({"cell": str(cell), "lake_id": str(lake_id),
                                    "distance_m": str(round(g.measure("distance", lake, p), 2)),
                                    "inside": str(g.measure("intersects", lake, p))})
            return results
        if label in ("river_areas", "river_lines"):
            results = []
            for cell in CELL_IDS:
                p = g.geom(point_wkb(*center(cell)))
                best = min(g.measure("distance", p, w) for w in self.records[label])
                results.append({"cell": str(cell), "min_distance_m": str(round(best, 2))})
            return results
        if label == "SYKE_POINT_LAKE":
            p = g.geom(point_wkb(209277.1, 6907673.6))
            return [{"lake_id": str(k),
                     "distance_m": str(round(g.measure("distance", lakes[k][1], p), 2)),
                     "intersects": str(g.measure("intersects", lakes[k][1], p))}
                    for k in LAKE_IDS]
        raise ValueError("STOP: UNKNOWN_GEOMETRY_STAGE " + label)

    def close(self):
        self.geos.close()


@lru_cache(maxsize=1)
def _store(path):
    s = Store(path)
    atexit.register(s.close)
    return s


def query(gpkg, label):
    return _store(str(gpkg)).query(label)
