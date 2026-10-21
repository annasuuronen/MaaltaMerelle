"""Focused offline-only tests; no CSC or existing hydrology suite reruns."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import offline_plan as plan

MATRIX = Path(__file__).with_name("test_matrix.csv")


class MatrixSafetyTests(unittest.TestCase):
    def test_four_exact_areas_and_known_low_limit(self):
        data = json.loads(plan.build_plan(MATRIX))
        self.assertEqual(set(data["areas"]), {"NATURAL", "LOW", "MODERATE", "HIGH"})
        self.assertFalse(data["execution_enabled"])
        self.assertFalse(data["user_approval_granted"])
        self.assertEqual(data["NATIONAL"], "LOCKED")
        self.assertEqual(data["MODERATE"], "REVIEW_REQUIRED")
        rows = {r["test_id"]: r for r in data["tests"]}
        self.assertEqual(rows["LOW_BOUNDARY_14"]["read_value_limit"], "56")
        self.assertIn("DEM_UNVERIFIED", rows["HIGH_INPUT"]["input_identity"])
        self.assertTrue(all(r["technical_status"] == "NOT_RUN" for r in rows.values()))

    def altered(self, mutator):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "tampered.csv"
            with MATRIX.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream))
            mutator(rows)
            with path.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=plan.FIELDS)
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaises(ValueError):
                plan.build_plan(path)

    def test_area_confusion_is_rejected(self):
        self.altered(lambda rows: rows[0].update(area_id="TEST_SULKU_11"))

    def test_fifth_area_is_rejected(self):
        self.altered(lambda rows: rows[0].update(area="NATIONAL"))

    def test_promoted_pass_is_rejected(self):
        self.altered(lambda rows: rows[0].update(technical_status="PASS"))

    def test_approval_bypass_is_rejected(self):
        self.altered(lambda rows: rows[0].update(approval_status="APPROVED"))

    def test_unverified_high_dem_stays_unverified(self):
        self.altered(lambda rows: rows[-1].update(input_identity="HIGH_DEM_VERIFIED"))

    def test_receiver_limit_increase_rejected(self):
        self.altered(lambda rows: next(row for row in rows if row["test_id"] == "LOW_BOUNDARY_14").update(read_value_limit="57"))

    def test_duplicate_id_rejected(self):
        self.altered(lambda rows: rows[-1].update(test_id=rows[0]["test_id"]))

    def test_determinism_and_digest(self):
        b1 = plan.build_plan(MATRIX)
        b2 = plan.build_plan(MATRIX)
        self.assertEqual(b1, b2)
        self.assertEqual(hashlib.sha256(b1).hexdigest(), hashlib.sha256(b2).hexdigest())

    def test_write_once_never_overwrites(self):
        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "plan.json"
            plan.write_once(target, b"first")
            with self.assertRaises(FileExistsError):
                plan.write_once(target, b"second")
            self.assertEqual(target.read_bytes(), b"first")

    def test_cli_plan_twice_fails_without_modification(self):
        with tempfile.TemporaryDirectory() as td:
            script = str(Path(plan.__file__))
            cmd = [sys.executable, script, "plan", "--out", td]
            first = subprocess.run(cmd, capture_output=True, text=True, check=False)
            self.assertEqual(first.returncode, 0, first.stderr)
            before = (Path(td)/"plan.json").read_bytes()
            second = subprocess.run(cmd, capture_output=True, text=True, check=False)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(before, (Path(td)/"plan.json").read_bytes())
            digest = hashlib.sha256(before).hexdigest()
            self.assertEqual((Path(td)/"plan.sha256").read_text(encoding="ascii"), digest + "  plan.json\n")


if __name__ == "__main__":
    unittest.main()
