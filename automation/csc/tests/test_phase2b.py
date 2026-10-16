"""Synthetic-only integration tests. They never connect to CSC or other hosts."""

import copy
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest

CSC = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CSC))
from phase2a import contracts as c
from phase2b import synthetic_adapter as s

NOW = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
CSV = CSC.parents[1] / "docs/csc/phase2a/candidates.csv"
MISSING_PATH = "moderate_resume_20261014_v2/run/02_baseline/02D8_final_spill_evidence.csv"


class SyntheticAdapterTests(unittest.TestCase):
    def setUp(self):
        self.candidates = c.candidates_from_csv(CSV.read_bytes())
        self.inventory = c.unchecked_inventory(self.candidates)
        self.allowlist = {
            "schema_version": "2a.1", "kind": "allowlist", "root_id": c.ROOT_ID,
            "safety": dict(c.SAFETY),
            "request_id": "00000000-0000-4000-8000-00000000002b",
            "repository": c.REPOSITORY, "branch": c.BRANCH,
            "source_commit": "a" * 40, "package_sha256": "b" * 64,
            "csc_root": c.CSC_ROOT, "operation": "INVENTORY_LOCAL_REPORTS",
            "output_path": "synthetic/reports.json",
            "candidates_sha256": c.digest(self.candidates),
            "inventory_sha256": c.digest(self.inventory),
            "valid_from_utc": "2026-10-15T11:00:00Z",
            "expires_at_utc": "2026-10-15T13:00:00Z",
            "max_total_bytes": 10000,
            "files": [{"relative_path": f["relative_path"], "expected_size_bytes": None,
                       "sha256_expected": None, "max_bytes": 1000, "job_id": None}
                      for f in self.candidates["files"]],
        }
        self.repin()
        self.entries = {path: s.SyntheticEntry("AVAILABLE", 12) for path in s.PILOT_PATHS}
        self.entries[MISSING_PATH] = s.SyntheticEntry("MISSING")
        self.provider = s.SyntheticMetadataProvider(self.entries)

    def repin(self):
        keys = ("schema_version", "root_id", "safety", "request_id", "repository",
                "branch", "source_commit", "package_sha256", "csc_root",
                "operation", "output_path")
        self.request = {k: copy.deepcopy(self.allowlist[k]) for k in keys}
        self.request["kind"] = "request"
        self.request["allowlist_sha256"] = c.digest(self.allowlist)
        self.request["files"] = [{"relative_path": f["relative_path"]}
                                 for f in self.allowlist["files"]]
        self.trust = c.TrustStore({self.request["request_id"]:
                                   (c.digest(self.allowlist), "/synthetic/never-opened")})

    def run_sim(self, trust=True, provider=None):
        return s.simulate_inventory(self.candidates, self.inventory, self.allowlist,
                                    self.request, self.trust if trust else None,
                                    self.provider if provider is None else provider, now=NOW)

    def test_exact_ten_paths_match_phase2a(self):
        self.assertEqual({x["relative_path"] for x in self.candidates["files"]}, s.PILOT_PATHS)
        self.assertEqual(len(s.PILOT_PATHS), 10)

    def test_nine_available_one_missing_is_explicitly_synthetic(self):
        result = self.run_sim()
        self.assertEqual(result["mode"], "SYNTHETIC_ONLY")
        self.assertFalse(result["csc_observations"])
        self.assertEqual(result["authorization"], "NO_LIVE_CSC_AUTHORIZATION")
        self.assertEqual(result["transfer"], "FORBIDDEN")
        self.assertEqual(result["total_simulated_bytes"], 108)
        rows = result["inventory"]["files"]
        self.assertEqual(sum(r["status"] == "AVAILABLE" for r in rows), 9)
        self.assertEqual(sum(r["status"] == "MISSING" for r in rows), 1)
        self.assertEqual(next(r for r in rows if r["relative_path"] == MISSING_PATH)["status"], "MISSING")
        self.assertTrue(all(r["evidence_ref"] == "SYNTHETIC_FIXTURE_ONLY_NOT_CSC" for r in rows))
        self.assertTrue(all(r["sha256_measured"] is None for r in rows))
        self.assertEqual(result["inventory"]["safety"], c.SAFETY)

    def test_denied_without_independent_pin(self):
        with self.assertRaises(c.Rejected):
            self.run_sim(trust=False)
        with self.assertRaises(c.Rejected):
            s.simulate_inventory(self.candidates, self.inventory, self.allowlist,
                                 self.request, c.TrustStore(), self.provider, now=NOW)

    def test_consumed_once_even_when_rerun(self):
        self.run_sim()
        with self.assertRaises(c.Rejected):
            self.run_sim()

    def test_no_real_provider_allowed(self):
        class RealProvider:
            def observe(self, path):
                raise AssertionError("MUST NEVER CONNECT")
        with self.assertRaises(c.Rejected):
            self.run_sim(provider=RealProvider())

    def test_subclass_backend_not_accepted(self):
        class Derived(s.SyntheticMetadataProvider):
            pass
        with self.assertRaises(c.Rejected):
            self.run_sim(provider=Derived(self.entries))

    def test_any_missing_fixture_path_is_rejected(self):
        self.entries.pop(MISSING_PATH)
        with self.assertRaises(c.Rejected):
            s.SyntheticMetadataProvider(self.entries)

    def test_unlisted_extra_fixture_path_is_rejected(self):
        self.entries["other/qa.csv"] = s.SyntheticEntry("AVAILABLE", 10)
        with self.assertRaises(c.Rejected):
            s.SyntheticMetadataProvider(self.entries)

    def test_bad_fixture_states_rejected(self):
        for state in ("NOT_CHECKED", "OUT_OF_SCOPE", "PASS", "UNKNOWN"):
            with self.subTest(state=state):
                entries = dict(self.entries)
                entries[MISSING_PATH] = s.SyntheticEntry(state)
                with self.assertRaises(c.Rejected):
                    s.SyntheticMetadataProvider(entries)

    def test_unavailable_cannot_claim_size(self):
        entries = dict(self.entries)
        entries[MISSING_PATH] = s.SyntheticEntry("MISSING", 1)
        with self.assertRaises(c.Rejected):
            s.SyntheticMetadataProvider(entries)

    def test_sizes_cannot_be_negative_float_boolean_or_over_cap(self):
        for size in (-1, 1.5, True, c.MAX_FILE + 1):
            entries = dict(self.entries)
            entries[MISSING_PATH] = s.SyntheticEntry("AVAILABLE", size)
            with self.subTest(size=size), self.assertRaises(c.Rejected):
                s.SyntheticMetadataProvider(entries)

    def test_approved_per_file_limit_enforced(self):
        self.allowlist["files"][0]["max_bytes"] = 1
        self.repin()
        with self.assertRaises(c.Rejected):
            self.run_sim()
        self.assertIn(self.request["request_id"], self.trust.used)

    def test_approved_total_limit_enforced(self):
        self.allowlist["max_total_bytes"] = 50
        self.repin()
        with self.assertRaises(c.Rejected):
            self.run_sim()

    def test_wrong_operation_rejected(self):
        self.allowlist["operation"] = "VERIFY_LOCAL_REPORTS"
        for file in self.allowlist["files"]:
            file["expected_size_bytes"] = 12
            file["sha256_expected"] = "a" * 64
        self.repin()
        with self.assertRaises(c.Rejected):
            self.run_sim()

    def test_modified_source_or_allowlist_cannot_self_approve(self):
        self.request["source_commit"] = "c" * 40
        with self.assertRaises(c.Rejected):
            self.run_sim()
        self.request["source_commit"] = "a" * 40
        self.allowlist["files"][0]["max_bytes"] = 20
        self.request["allowlist_sha256"] = c.digest(self.allowlist)
        with self.assertRaises(c.Rejected):
            self.run_sim()

    def test_extra_candidate_is_denied(self):
        self.candidates["files"].append({"relative_path": "extra/test.csv", "purpose": "fake"})
        self.inventory = c.unchecked_inventory(self.candidates)
        self.allowlist["candidates_sha256"] = c.digest(self.candidates)
        self.allowlist["inventory_sha256"] = c.digest(self.inventory)
        self.repin()
        with self.assertRaises(c.Rejected):
            self.run_sim()

    def test_unreadable_distinct_from_missing(self):
        entries = dict(self.entries)
        entries[MISSING_PATH] = s.SyntheticEntry("UNREADABLE")
        result = self.run_sim(provider=s.SyntheticMetadataProvider(entries))
        self.assertEqual(next(r for r in result["inventory"]["files"]
                              if r["relative_path"] == MISSING_PATH)["status"], "UNREADABLE")

    def test_no_synthetic_observation_mutates_initial_inventory(self):
        self.run_sim()
        self.assertTrue(all(r["status"] == "NOT_CHECKED" for r in self.inventory["files"]))


if __name__ == "__main__":
    unittest.main()
