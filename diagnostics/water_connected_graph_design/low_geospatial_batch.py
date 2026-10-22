#!/usr/bin/env python3
"""Read-only LOW 02C ↔ RANTA10 geometry bundle. No raster or model operations."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
import math
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

CELLS = {
    10007129: (108, 3181),
    10031127: (109, 3181),
    15389414: (235, 3181),
    15401414: (236, 3181),
    23211319: (274, 1892),  # also used by lake 1894
    23355315: (276, 1894),
    23373314: (277, 1894),
}
LAKES = (1892, 1894, 3181)
XMIN, YMAX, NCOLS, NROWS, RES = 199000, 6911000, 6000, 6000, 2
ZERO_NEIGHBOR_FILE = "02C_zero_pointer_water_neighbors.csv"
COMPONENT_FILE = "02C_shore_component_classification.csv"


def require(cond: bool, message: str) -> None:
    if not cond:
        raise ValueError("STOP: " + message)


def center(cell: int) -> tuple[int, int]:
    require(1 <= cell <= NCOLS * NROWS, "CELL_ID_OUT_OF_RANGE")
    zero = cell - 1
    return XMIN + RES * (zero % NCOLS) + RES // 2, YMAX - RES * (zero // NCOLS) - RES // 2


def parse_features(raw: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in raw.splitlines():
        if re.match(r"^OGRFeature\([^)]*\):\d+$", line.strip()):
            current = {}
            result.append(current)
        elif current is not None:
            match = re.match(r"^\s+([\w]+)\s+\([^)]*\)\s*=\s*(.*)$", line)
            if match:
                current[match[1]] = match[2].strip()
    return result


def expect_files(gpkg: Path, baseline: Path) -> None:
    for f in (gpkg, baseline / ZERO_NEIGHBOR_FILE, baseline / COMPONENT_FILE):
        require(f.is_file() and not f.is_symlink(), "MISSING_OR_SYMLINK_FILE: " + str(f))
    require(gpkg.stat().st_size <= 500_000_000, "GPKG_SIZE_LIMIT")
    for f in (baseline / ZERO_NEIGHBOR_FILE, baseline / COMPONENT_FILE):
        require(0 < f.stat().st_size <= 15_000_000, "CSV_SIZE_LIMIT: " + f.name)
    require(subprocess.run(["which", "ogrinfo"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode == 0, "OGRINFO_NOT_LOADED")
    # SQLite metadata only; do not query any full geometry blobs.
    try:
        con = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True, timeout=5)
        layers = dict(con.execute("SELECT table_name, srs_id FROM gpkg_geometry_columns").fetchall())
        counts = {k: con.execute('SELECT COUNT(*) FROM "' + k + '"').fetchone()[0] for k in ("lakes", "river_areas", "river_lines")}
        con.close()
    except sqlite3.Error as e:
        raise ValueError("STOP: GPKG_METADATA_ERROR: " + str(e)) from e
    require(all(layers.get(k) == 3067 for k in counts), "GPKG_SRS_NOT_3067")
    require(counts == {"lakes": 24, "river_areas": 5, "river_lines": 30}, "GPKG_LAYER_COUNTS_CHANGED: " + str(counts))
    print("RANTA10_METADATA_COUNTS", counts, "SRS=3067")


def ogr(gpkg: Path, statement: str, expected_rows: int | None, label: str) -> list[dict[str, str]]:
    cmd = ["ogrinfo", "-ro", "-q", "-geom=NO", "-dialect", "SQLite", "-sql", statement, str(gpkg)]
    try:
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=18, check=False)
    except subprocess.TimeoutExpired as e:
        raise ValueError("STOP: OGR_TIMEOUT: " + label) from e
    require(process.returncode == 0, "OGR_FAILED: " + label + " " + process.stderr[:350].replace("\n", " "))
    require("ERROR" not in process.stderr.upper(), "OGR_ERROR: " + label + " " + process.stderr[:350].replace("\n", " "))
    rows = parse_features(process.stdout)
    if expected_rows is not None:
        require(len(rows) == expected_rows, f"OGR_ROW_COUNT_{label}: expected {expected_rows}, got {len(rows)}")
    return rows


def finite_number(row: dict[str, str], key: str) -> float:
    require(key in row and row[key] != "(null)", "MISSING_NUMBER: " + key)
    try:
        value = float(row[key])
    except ValueError as e:
        raise ValueError("STOP: BAD_NUMBER: " + key) from e
    require(math.isfinite(value), "NONFINITE: " + key)
    return value


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        require(bool(reader.fieldnames), "CSV_HEADER_MISSING: " + path.name)
        rows = list(reader)
    require(len(rows) <= 200_000, "CSV_ROW_LIMIT: " + path.name)
    return rows


def grid_cte() -> str:
    entries = ",".join(f"({cell},{center(cell)[0]},{center(cell)[1]})" for cell in CELLS)
    return "WITH pts(cell,x,y) AS (VALUES " + entries + ") "


def csv_diagnostic(baseline: Path) -> None:
    chosen = set(c for c, _ in CELLS.values())
    comps = csv_rows(baseline / COMPONENT_FILE)
    require({"component_id", "connector_status", "water_signature", "target_lake_objectid", "n_zero_cells", "lake_objectids"}.issubset(comps[0]), "COMPONENT_CSV_SCHEMA")
    comp_by_id = {}
    for c in comps:
        cid = int(c["component_id"])
        require(cid not in comp_by_id, "DUPLICATE_COMPONENT_ID")
        comp_by_id[cid] = c
    require(chosen.issubset(comp_by_id), "MISSING_02C_COMPONENT")
    print("02C_COMPONENT_STATUS: component,status,target_lake,lake_objectids,signature,n_zero_cells,terminal_minus_water_m")
    for cid in sorted(chosen):
        c = comp_by_id[cid]
        print(cid, c["connector_status"], c["target_lake_objectid"] or "NA", c["lake_objectids"] or "NA", c["water_signature"], c["n_zero_cells"], c.get("terminal_minus_water_m", "UNKNOWN"))
    neighbors = csv_rows(baseline / ZERO_NEIGHBOR_FILE)
    require({"component_id", "source_cell", "water_cell", "water_class", "lake_objectid"}.issubset(neighbors[0]), "NEIGHBOR_CSV_SCHEMA")
    agg = Counter()
    unique = defaultdict(set)
    for r in neighbors:
        cid = int(r["component_id"])
        if cid in chosen:
            k = (cid, r["water_class"], r["lake_objectid"] or "NA")
            agg[k] += 1
            unique[k].add(r["water_cell"])
    require(all(any(k[0] == c for k in agg) for c in chosen), "MISSING_COMPONENT_NEIGHBORS")
    print("02C_WATER_NEIGHBORS: component,water_class,lake_id,neighbor_pairs,distinct_water_cells")
    for k, n in sorted(agg.items()):
        print(*k, n, len(unique[k]))


def run(gpkg: Path, baseline: Path) -> None:
    expect_files(gpkg, baseline)
    failures: list[str] = []
    print("=== TULOKSET ALKAVAT ===", flush=True)

    def step(label: str, action) -> None:
        try:
            action()
        except (OSError, ValueError, KeyError, IndexError) as exc:
            failures.append(label)
            print(f"TEST_{label}=STOP: {str(exc)[:400]}", flush=True)
        else:
            print(f"TEST_{label}=PASS", flush=True)

    step("02C_COMPONENT_AND_WATER_NEIGHBORS", lambda: csv_diagnostic(baseline))

    def lake_info() -> None:
        lakes = ogr(gpkg,
            "SELECT CAST(objectid AS INTEGER) AS lake_id, korkeus_m AS lake_height_m, "
            "ROUND(ST_Area(geom),1) AS area_m2, ST_IsValid(geom) AS geom_valid "
            "FROM lakes WHERE CAST(objectid AS INTEGER) IN (1892,1894,3181) ORDER BY lake_id",
            3, "LAKE_INFO")
        require([int(finite_number(r,"lake_id")) for r in lakes] == list(LAKES), "LAKE_ID_MISMATCH")
        print("RANTA10_LAKES: lake_id,korkeus_m,polygon_area_m2,geom_valid")
        for r in lakes:
            print(r["lake_id"], r["lake_height_m"], r["area_m2"], r["geom_valid"])

    step("LAKE_INFO", lake_info)

    def lake_pair() -> None:
        pair = ogr(gpkg,
            "SELECT ROUND(ST_Distance(a.geom,b.geom),2) AS distance_m, "
            "ST_Touches(a.geom,b.geom) AS touches, ST_Intersects(a.geom,b.geom) AS intersects "
            "FROM lakes a JOIN lakes b ON CAST(a.objectid AS INTEGER)=1894 "
            "AND CAST(b.objectid AS INTEGER)=1892",
            1, "LAKE_PAIR")
        print("LAKE_1894_VS_1892: distance_m,touches,intersects")
        print(pair[0]["distance_m"], pair[0]["touches"], pair[0]["intersects"])

    step("LAKE_1894_TO_1892_GEOMETRY", lake_pair)

    def cell_lake() -> None:
        result = ogr(gpkg, grid_cte() +
            "SELECT pts.cell AS cell, CAST(l.objectid AS INTEGER) AS lake_id, "
            "ROUND(ST_Distance(l.geom,MakePoint(pts.x,pts.y,3067)),2) AS distance_m, "
            "ST_Intersects(l.geom,MakePoint(pts.x,pts.y,3067)) AS inside "
            "FROM pts CROSS JOIN lakes l WHERE CAST(l.objectid AS INTEGER) IN (1892,1894,3181) "
            "ORDER BY pts.cell,lake_id", 21, "CELL_LAKE")
        require(Counter(int(r["cell"]) for r in result) == Counter({c:3 for c in CELLS}), "CELL_LAKE_JOIN")
        print("CELL_VS_LAKES: cell,component,origin_lake,reference_lake,distance_m,point_intersects")
        for r in result:
            cell = int(r["cell"])
            dist = finite_number(r,"distance_m")
            require(dist >= 0, "NEGATIVE_GEOMETRY_DISTANCE")
            print(cell, *CELLS[cell], r["lake_id"], f"{dist:.2f}", r["inside"])

    step("SEVEN_CELLS_VS_THREE_LAKES", cell_lake)

    def river_distance(layer: str) -> None:
        data = ogr(gpkg, grid_cte() +
            f"SELECT pts.cell AS cell, ROUND(MIN(ST_Distance(w.geom,MakePoint(pts.x,pts.y,3067))),2) AS min_distance_m "
            f"FROM pts CROSS JOIN {layer} w GROUP BY pts.cell ORDER BY pts.cell",
            7, layer)
        require({int(r["cell"]) for r in data} == set(CELLS), "RIVER_DISTANCE_CELL_SET")
        print("NEAREST_" + layer.upper() + ": cell,min_distance_m")
        for r in data:
            dist = finite_number(r,"min_distance_m")
            require(dist >= 0, "NEGATIVE_RIVER_DISTANCE")
            print(r["cell"], f"{dist:.2f}")

    step("RIVER_AREA_DISTANCE", lambda: river_distance("river_areas"))
    step("RIVER_LINE_DISTANCE", lambda: river_distance("river_lines"))

    def syke_near_lakes() -> None:
        syke = ogr(gpkg,
            "SELECT CAST(objectid AS INTEGER) AS lake_id, "
            "ROUND(ST_Distance(geom,MakePoint(209277.1,6907673.6,3067)),2) AS distance_m, "
            "ST_Intersects(geom,MakePoint(209277.1,6907673.6,3067)) AS intersects "
            "FROM lakes WHERE CAST(objectid AS INTEGER) IN (1892,1894,3181) ORDER BY lake_id",
            3, "SYKE_POINT_LAKE")
        print("SYKE_7025519_VS_LAKES: lake_id,distance_m,intersects (reported point xy rounded to 0.1m)")
        for r in syke:
            print(r["lake_id"], r["distance_m"], r["intersects"])

    step("SYKE_7025519_GEOMETRY", syke_near_lakes)
    print("NOTE: All results are geometric/auxiliary evidence, NOT validated outlets or flow direction.")
    print("SCIENCE_LOCKS: NATIONAL=LOCKED MODERATE=REVIEW_REQUIRED hydrological_validation=NOT_ASSESSED")
    print("BATCH_STATUS=" + ("PARTIAL" if failures else "PASS") + " FAILED_STAGES=" + (",".join(failures) if failures else "NONE"))
    print("=== TULOKSET LOPPUVAT ===", flush=True)
    require(not failures, "PARTIAL_RESULTS: " + ",".join(failures))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gpkg", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.gpkg, args.baseline)
    except (ValueError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
