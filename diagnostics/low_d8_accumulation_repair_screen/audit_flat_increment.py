#!/usr/bin/env python3
"""Offline-only forensic check of Whitebox flat-increment compatibility.

Reads only two previously exported, SHA256-locked CSVs. No raster I/O or network.
Compatible increments alone do not prove hydrological correctness or provenance.
"""
import argparse
import csv
import hashlib
import json
import math
import sys
import unittest
from collections import Counter
from pathlib import Path

EXPECTED_SHA256 = {
    "raw.csv": "83a11896163380ba02c65acf1305560d70fab6f6d9e052fcb8ab71c1800977aa",
    "centers.csv": "362f60c4dcc6bbdc8db13e8963949c23c3cc71f9222b1b0ac63242695082b019",
}
GRID = 6000
D8 = {1: (-1, 1), 2: (0, 1), 4: (1, 1), 8: (1, 0),
      16: (1, -1), 32: (0, -1), 64: (-1, -1), 128: (-1, 0)}
CANDIDATE_INCREMENT_M = 3e-7
MATCH_TOLERANCE_M = 5e-8
NEAR_FLAT_TOLERANCE_M = 1e-6


def require(condition, reason):
    if not condition:
        raise ValueError("STOP: " + reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path, fields, max_rows):
    require(path.is_file() and path.stat().st_size <= max_rows * 160 + 200,
            "MISSING_OR_OVERSIZED_" + path.name)
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        require(reader.fieldnames == fields, "CSV_FIELDS_CHANGED_" + path.name)
        rows = list(reader)
    require(len(rows) == max_rows, "CSV_ROW_COUNT_" + path.name)
    return rows


def rowcol(cell_id):
    require(isinstance(cell_id, int) and 1 <= cell_id <= GRID * GRID,
            "INVALID_CELL_ID")
    return (cell_id - 1) // GRID + 1, (cell_id - 1) % GRID + 1


def analyze(centers, raw, expected_center_ids, expected_raw_ids):
    require(len(centers) == 256 and len(raw) == 2304, "UNEXPECTED_INPUT_ROWS")
    center_ids = []
    for c in centers:
        r, col, cell = int(c["row"]), int(c["col"]), int(c["cell_id"])
        require(1 <= r <= GRID and 1 <= col <= GRID and cell == (r-1)*GRID+col,
                "CENTER_COORDINATE_INCONSISTENT")
        center_ids.append(cell)
    require(center_ids == list(expected_center_ids), "CENTER_DESIGN_CHANGED")
    sample = {}
    for x, expected_id in zip(raw, expected_raw_ids):
        cell = int(x["cell_id"])
        require(cell == expected_id and cell not in sample, "RAW_SAMPLE_ORDER_CHANGED")
        sample[cell] = (float(x["pointer"]), float(x["z"]), float(x["water_class"]))
    require(len(sample) == 2304, "RAW_SAMPLE_DUPLICATED")
    n_land = n_water = n_no_data = n_downhill = 0
    nearly_flat = []
    for cell in center_ids:
        row, col = rowcol(cell)
        pointer, z, wc = sample[cell]
        if not math.isfinite(z):
            n_no_data += 1
            continue
        if wc in (1., 2., 3.):
            n_water += 1
            continue
        require(math.isnan(wc), "SOURCE_WATER_CLASS_UNEXPECTED")
        n_land += 1
        require(math.isfinite(pointer) and pointer in D8, "INVALID_LAND_POINTER")
        dr, dc = D8[int(pointer)]
        rr, cc = row+dr, col+dc
        require(1 <= rr <= GRID and 1 <= cc <= GRID, "OFF_GRID_RECEIVER")
        next_id = (rr-1)*GRID+cc
        require(next_id in sample, "MISSING_RECEIVER_VALUE")
        _, to_z, to_wc = sample[next_id]
        require(math.isfinite(to_z) and math.isnan(to_wc),
                "TARGET_NOT_FINITE_LAND")
        delta = to_z-z
        require(delta < 0., "NON_DOWNHILL_POINTER")
        if abs(delta) <= NEAR_FLAT_TOLERANCE_M:
            nearly_flat.append(delta)
        else:
            n_downhill += 1
    require((n_land,n_water,n_no_data,n_downhill,len(nearly_flat)) ==
            (236,7,13,117,119), "AGGREGATE_VS_REPORTED_TRANSCRIPT_MISMATCH")
    matches = 0
    histogram = Counter()
    residuals = []
    for d in nearly_flat:
        k = round(abs(d)/CANDIDATE_INCREMENT_M)
        residual = abs(abs(d) - k*CANDIDATE_INCREMENT_M)
        residuals.append(residual)
        if k >= 1 and residual <= MATCH_TOLERANCE_M:
            histogram[str(k)] += 1
            matches += 1
        else:
            histogram["not_close_to_integer_multiple"] += 1
    return {
        "scope": "PREVIOUSLY_EXPORTED_CSV_ONLY_NO_RASTER_READ",
        "land_centres": n_land,
        "near_flat_strict_downhill": len(nearly_flat),
        "steeper_downhill": n_downhill,
        "source_water": n_water,
        "source_nodata": n_no_data,
        "equal_or_uphill_in_sample": 0,
        "near_flat_min_dz_m": min(nearly_flat),
        "near_flat_max_dz_m": max(nearly_flat),
        "candidate_increment_m": CANDIDATE_INCREMENT_M,
        "candidate_step_multiples": dict(sorted(histogram.items())),
        "near_flat_compatible_with_candidate_count": matches,
        "near_flat_not_compatible_count": len(nearly_flat)-matches,
        "max_abs_step_residual_m": max(residuals),
        "candidate_not_proven": True,
        "whitebox_binary_and_input_dem_max": "UNKNOWN",
        "physical_terrain_slope": "NOT_ASSESSED",
        "route_continuity": "NOT_ASSESSED",
        "flow_accumulation": "NOT_COMPUTED",
        "hydrological_validation": "NOT_ASSESSED",
        "channel_interpretation": "NOT_ASSESSED",
        "MODERATE": "REVIEW_REQUIRED",
        "NATIONAL": "LOCKED",
    }


def analyze_files(folder):
    raw_path, centers_path = (folder / name for name in ("raw.csv", "centers.csv"))
    for p in (raw_path, centers_path):
        require(p.is_file() and sha(p) == EXPECTED_SHA256[p.name],
                "REPORTED_SHA256_MISMATCH_" + p.name)
    import audit as original
    expected_centers, expected_ids = original.cells_design()
    require(len(expected_ids) == 2304, "ORIGINAL_DESIGN_REQUEST_MISMATCH")
    centers = read_csv(centers_path, ["row","col","cell_id"], 256)
    raw = read_csv(raw_path, ["cell_id","pointer","z","water_class"], 2304)
    result = analyze(centers, raw, [x[2] for x in expected_centers], expected_ids)
    result["raw_csv_sha256"] = EXPECTED_SHA256["raw.csv"]
    result["centers_csv_sha256"] = EXPECTED_SHA256["centers.csv"]
    result["input_integrity"] = "OPERATOR_REPORTED_HASH_MATCHES_ON_CURRENT_FILES"
    return result


class SyntheticCases(unittest.TestCase):
    def test_id_roundtrip(self):
        for p in (1, 6000, 6001, 36000000):
            r,c=rowcol(p)
            self.assertEqual((r-1)*GRID+c,p)

    def test_invalid_ids_fail(self):
        for p in (-1,0,36000001,1.5,"12"):
            with self.subTest(p=p), self.assertRaises(ValueError):
                rowcol(p)

    def test_d8_mapping_unique(self):
        self.assertEqual(len(set(D8.values())),8)
        self.assertEqual(D8[128],(-1,0))
        self.assertEqual(D8[8],(1,0))

    def test_candidate_increment_formula_2m_2digits(self):
        diag_ceil = math.ceil(math.hypot(2,2))
        digits = 2
        self.assertAlmostEqual(10**(digits-9)*diag_ceil,3e-7)

    def test_float_compatibility_near_multiples(self):
        for k in (1,2,3):
            d=k*CANDIDATE_INCREMENT_M + 1e-16
            self.assertLess(abs(d-k*CANDIDATE_INCREMENT_M),MATCH_TOLERANCE_M)
        self.assertGreater(abs(4.2e-7-CANDIDATE_INCREMENT_M),MATCH_TOLERANCE_M)

    def test_hash_pins_are_valid(self):
        self.assertEqual(len(EXPECTED_SHA256),2)
        self.assertTrue(all(len(x)==64 and all(ch in "0123456789abcdef" for ch in x)
                            for x in EXPECTED_SHA256.values()))

    @staticmethod
    def synthetic_fixture():
        centres = []
        records = {}
        for i in range(256):
            r, c = 10 + 4*(i//16), 10 + 4*(i%16)
            cell = (r-1)*GRID+c
            centres.append({"row":str(r), "col":str(c), "cell_id":str(cell)})
            for dr in (-1,0,1):
                for dc in (-1,0,1):
                    rc = (r+dr-1)*GRID+(c+dc)
                    records[rc] = {"cell_id":str(rc),"pointer":"2",
                                   "z":"99","water_class":"NaN"}
            if i < 13:
                records[cell]["z"] = "NaN"
            elif i < 20:
                records[cell]["water_class"] = "1"
            else:
                records[cell]["z"] = "100"
                records[cell+1]["z"] = "99.9999997" if i < 139 else "99"
        ids = sorted(records)
        return centres, [records[z] for z in ids], ids

    def test_full_synthetic_256_centre_classifier(self):
        centers, raw, ids = self.synthetic_fixture()
        result=analyze(centers,raw,[int(c["cell_id"]) for c in centers],ids)
        self.assertEqual(result["near_flat_strict_downhill"],119)
        self.assertEqual(result["steeper_downhill"],117)
        self.assertEqual(result["source_nodata"],13)
        self.assertEqual(result["source_water"],7)
        self.assertEqual(result["near_flat_compatible_with_candidate_count"],119)
        self.assertEqual(result["candidate_step_multiples"],{"1":119})

    def test_negative_integration_rejects_bad_receiver_or_order(self):
        centers, raw, ids = self.synthetic_fixture()
        mutated = [dict(x) for x in raw]
        mutated[0]["cell_id"] = str(int(mutated[0]["cell_id"])+2)
        with self.assertRaises(ValueError):
            analyze(centers,mutated,[int(c["cell_id"]) for c in centers],ids)
        mutated = [dict(x) for x in raw]
        land_center = int(centers[20]["cell_id"])
        for entry in mutated:
            if int(entry["cell_id"])==land_center+1:
                entry["z"]="101"
                break
        with self.assertRaises(ValueError):
            analyze(centers,mutated,[int(c["cell_id"]) for c in centers],ids)

    def test_missing_file_fail_closed(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                analyze_files(Path(temp))


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--work-dir", type=Path, help="existing SCREEN_WORK from prior CSC run")
    cli.add_argument("--selftest", action="store_true")
    args = cli.parse_args()
    if args.selftest:
        suite=unittest.defaultTestLoader.loadTestsFromTestCase(SyntheticCases)
        result=unittest.TextTestRunner(stream=sys.stdout,verbosity=2).run(suite)
        print(f"OFFLINE_TESTS={result.testsRun} "
              f"PASS={result.testsRun-len(result.failures)-len(result.errors)} "
              f"FAIL={len(result.failures)+len(result.errors)}")
        return 0 if result.wasSuccessful() and result.testsRun==9 else 1
    require(args.work_dir is not None, "WORK_DIR_REQUIRED")
    report=analyze_files(args.work_dir)
    print("=== TULOKSET ALKAVAT ===")
    print(json.dumps(report,indent=2,sort_keys=True))
    print("=== TULOKSET LOPPUVAT ===")
    return 0


if __name__=="__main__":
    try: sys.exit(main())
    except (ValueError, OSError, OverflowError) as e:
        print(str(e) if str(e).startswith("STOP:") else "STOP: " + str(e),
              file=sys.stderr)
        sys.exit(1)
