#!/usr/bin/env python3
"""CSV-only preselection of up to two spatially separated 02B contacts/class.

Read-only; NO raster access, DEM/D8 changes, writes or CSC batch jobs.
Requires the existing LOW 6000x6000 01_input_QA and 02B CSV producer schemas.
"""
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 -I -B preselect_low_02b_csv.py BASELINE_DIR")
base = Path(sys.argv[1]).resolve(strict=True)


def guarded(path, limit):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise SystemExit("MISSING_LINK_OR_OVERSIZED: " + str(path))
    return path


report = guarded(base / "02B_land_to_first_water_entries.csv", 64 * 1024**2)
qa_path = guarded(base.parent / "01_inputs" / "01_input_QA.csv", 65536)
with qa_path.open(newline="", encoding="utf-8-sig") as handle:
    reader = csv.DictReader(handle)
    headers = reader.fieldnames or []
    if not {"item", "value"} <= set(headers) or len(headers) != len(set(headers)):
        raise SystemExit("BAD_01_QA_SCHEMA: expected unique item,value columns")
    rows = list(reader)
    keys = [record["item"] for record in rows]
    if len(keys) != len(set(keys)):
        raise SystemExit("DUPLICATE_01_QA_KEYS")
    qa = {record["item"]: record["value"] for record in rows}
try:
    nr, nc = int(float(qa["dem_rows"])), int(float(qa["dem_cols"]))
except (KeyError, ValueError, OverflowError) as exc:
    raise SystemExit("BAD_GRID_QA: " + str(exc))
if (nr, nc) != (6000, 6000):
    raise SystemExit("UNEXPECTED_LOCKED_LOW_GRID")

codes = {1, 2, 4, 8, 16, 32, 64, 128}
required = {
    "source_cell", "receiver_cell", "d8_code", "water_class",
    "source_x", "source_y",
}


def integer(record, field, number):
    try:
        value = float(record[field])
        if not math.isfinite(value) or not value.is_integer():
            raise ValueError("not a finite integer")
        return int(value)
    except (TypeError, ValueError, KeyError, OverflowError) as exc:
        raise SystemExit(f"BAD_02B_ROW {number}, {field}: {exc}")


def candidates():
    with report.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        headers = rows.fieldnames or []
        if not required <= set(headers) or len(headers) != len(set(headers)):
            raise SystemExit("BAD_02B_SCHEMA")
        for number, record in enumerate(rows, 2):
            s = integer(record, "source_cell", number)
            t = integer(record, "receiver_cell", number)
            d8 = integer(record, "d8_code", number)
            kind = integer(record, "water_class", number)
            if not (1 <= s <= nr * nc and 1 <= t <= nr * nc
                    and d8 in codes and kind in (1, 2, 3)):
                raise SystemExit(f"INVALID_02B_ROW {number}")
            row, col = divmod(s - 1, nc)
            row += 1
            col += 1
            # Keep first experiment away from tile boundary. Not an outlet filter.
            if 51 <= row <= nr - 50 and 51 <= col <= nc - 50:
                yield kind, s, t, d8, row, col


# Pass 1: observed spatial centroid of eligible contacts by class.
stats = {i: [0, 0, 0] for i in (1, 2, 3)}
for kind, s, t, d8, row, col in candidates():
    stat = stats[kind]
    stat[0] += 1
    stat[1] += row
    stat[2] += col

# Pass 2: nearest actual 02B contact to each class centroid.
first = {}
for item in candidates():
    kind, s, t, d8, row, col = item
    n, sumrow, sumcol = stats[kind]
    score = ((row - sumrow / n)**2 + (col - sumcol / n)**2, s, t)
    if kind not in first or score < first[kind][0]:
        first[kind] = score, item

# Pass 3: farthest eligible distinct receiver >=100m (50 cells) from first.
second = {}
for item in candidates():
    kind, s, t, d8, row, col = item
    if kind not in first:
        continue
    a = first[kind][1]
    sqdist = (row - a[4])**2 + (col - a[5])**2
    if s == a[1] or t == a[2] or sqdist < 50**2:
        continue
    score = (-sqdist, s, t)
    if kind not in second or score < second[kind][0]:
        second[kind] = score, item

print("========== TULOKSET ALKAVAT ==========")
print("MODE CSV_ONLY_READ_ONLY; GRID", nr, nc, "INTERIOR_MARGIN_CELLS 50")
print("SELECTION nearest class centroid; then farthest >=100m distinct receiver")
for kind in (1, 2, 3):
    print("WATER_CLASS", kind, "ELIGIBLE", stats[kind][0])
    for label, selections in (("CENTROID", first), ("FARTHEST", second)):
        if kind not in selections:
            print(" ", label, "NOT_AVAILABLE")
            continue
        _, (_, s, t, d8, row, col) = selections[kind]
        print(" ", label, "SOURCE", s, "RECEIVER", t, "D8", d8,
              "ROW", row, "COL", col)
print("LIMITATION CSV-only positions; no raster continuity or ditch identity")
print("MODERATE REVIEW_REQUIRED; NATIONAL LOCKED")
print("========== TULOKSET LOPPUVAT ==========")
