#!/usr/bin/env python3
"""Synthetic subprocess regressions for the CSV-only LOW preselector."""
import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("preselect_low_02b_csv.py")


class PreselectSynthetic(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.base = root / "runs" / "E200000_N6900000" / "02_baseline"
        self.base.mkdir(parents=True)
        self.inputs = self.base.parent / "01_inputs"
        self.inputs.mkdir()
        self.qa = self.inputs / "01_input_QA.csv"
        self.table = self.base / "02B_land_to_first_water_entries.csv"
        with self.qa.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["item", "value"])
            writer.writeheader()
            writer.writerows([{"item": "dem_rows", "value": "6000"},
                              {"item": "dem_cols", "value": "6000"}])

    def write_entries(self, records):
        with self.table.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=[
                "source_cell", "receiver_cell", "d8_code", "water_class",
                "source_x", "source_y"])
            writer.writeheader()
            for wc, r, c in records:
                src = (r - 1) * 6000 + c
                writer.writerow({
                    "source_cell": src, "receiver_cell": src - 6000,
                    "d8_code": 128, "water_class": wc,
                    "source_x": c * 2, "source_y": r * 2})

    def call(self):
        return subprocess.run(
            [sys.executable, "-I", "-B", str(SCRIPT), str(self.base)],
            capture_output=True, text=True, check=False)

    def test_two_spatial_contacts_each_class(self):
        self.write_entries([
            (wc, r, c) for wc in (1, 2, 3)
            for r, c in ((27, 5400), (120, 350), (1000, 1200),
                         (3100, 4800), (5800, 3000))
        ])
        a = self.call()
        self.assertEqual(a.returncode, 0, a.stderr)
        self.assertEqual(a.stdout.count("CENTROID SOURCE"), 3)
        self.assertEqual(a.stdout.count("FARTHEST SOURCE"), 3)
        self.assertIn("WATER_CLASS 1 ELIGIBLE 4", a.stdout)
        self.assertNotIn("ROW 27 ", a.stdout)
        self.assertEqual(a.stdout, self.call().stdout)

    def test_empty_class_is_not_invented(self):
        self.write_entries([(1, 200, 200)])
        a = self.call()
        self.assertEqual(a.returncode, 0, a.stderr)
        self.assertIn("WATER_CLASS 2 ELIGIBLE 0", a.stdout)
        self.assertIn("WATER_CLASS 3 ELIGIBLE 0", a.stdout)
        self.assertEqual(a.stdout.count("FARTHEST NOT_AVAILABLE"), 3)

    def test_qa_schema_mismatch_is_explicit(self):
        self.write_entries([(1, 200, 200)])
        self.qa.write_text("key,value\ndem_rows,6000\ndem_cols,6000\n")
        a = self.call()
        self.assertNotEqual(a.returncode, 0)
        self.assertIn("BAD_01_QA_SCHEMA", a.stderr)

    def test_invalid_02b_class_is_rejected(self):
        self.write_entries([(4, 200, 200)])
        a = self.call()
        self.assertNotEqual(a.returncode, 0)
        self.assertIn("INVALID_02B_ROW", a.stderr)

    def test_symlinked_csv_is_rejected(self):
        original = self.base / "actual.csv"
        original.write_text(
            "source_cell,receiver_cell,d8_code,water_class,source_x,source_y\n")
        self.table.symlink_to(original)
        a = self.call()
        self.assertNotEqual(a.returncode, 0)
        self.assertIn("MISSING_LINK_OR_OVERSIZED", a.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
