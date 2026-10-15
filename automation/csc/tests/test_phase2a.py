"""Phase 2A: synthetic local files and synthetic, host-injected grants ONLY."""

import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

CSC = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CSC))
from phase2a import contracts as c

NOW = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
DOCS = CSC.parents[1] / "docs/csc/phase2a"


class Phase2ATests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "reports").mkdir()
        self.raw = b"synthetic,value\nfixture,52\n"
        (self.root / "reports/qa.csv").write_bytes(self.raw)
        self.candidates = {"schema_version": "2a.1", "kind": "candidates",
                           "root_id": c.ROOT_ID, "safety": dict(c.SAFETY),
                           "files": [{"relative_path": "reports/qa.csv", "purpose": "SYNTHETIC ONLY"}]}
        self.inventory = c.unchecked_inventory(self.candidates)
        self.allowlist = {"schema_version": "2a.1", "kind": "allowlist", "root_id": c.ROOT_ID,
                          "safety": dict(c.SAFETY), "request_id": "00000000-0000-4000-8000-00000000002a",
                          "repository": c.REPOSITORY, "branch": c.BRANCH, "source_commit": "a" * 40,
                          "package_sha256": "b" * 64, "csc_root": c.CSC_ROOT,
                          "operation": "INVENTORY_LOCAL_REPORTS", "output_path": "local/inventory.json",
                          "candidates_sha256": c.digest(self.candidates),
                          "inventory_sha256": c.digest(self.inventory),
                          "valid_from_utc": "2026-10-15T11:00:00Z", "expires_at_utc": "2026-10-15T13:00:00Z",
                          "max_total_bytes": 1024,
                          "files": [{"relative_path": "reports/qa.csv", "max_bytes": 1024,
                                     "expected_size_bytes": None, "sha256_expected": None, "job_id": None}]}
        self.repin()

    def repin(self):
        self.allowlist["candidates_sha256"] = c.digest(self.candidates)
        self.allowlist["inventory_sha256"] = c.digest(self.inventory)
        context = ("request_id", "repository", "branch", "source_commit", "package_sha256",
                   "csc_root", "operation", "output_path", "root_id", "safety", "schema_version")
        self.request = {key: copy.deepcopy(self.allowlist[key]) for key in context}
        self.request.update(kind="request", allowlist_sha256=c.digest(self.allowlist),
                            files=[{"relative_path": f["relative_path"]} for f in self.allowlist["files"]])
        self.trust = c.TrustStore({self.request["request_id"]: (c.digest(self.allowlist), self.root)},
                                 frozenset({"12345", "12345_0.batch"}))

    def verify_mode(self):
        self.inventory["files"][0].update(status="AVAILABLE", size_bytes=len(self.raw),
                                         sha256_measured=hashlib.sha256(self.raw).hexdigest(),
                                         observed_at_utc="2026-10-15T10:00:00Z", evidence_ref="synthetic-only")
        self.allowlist["operation"] = "VERIFY_LOCAL_REPORTS"
        self.allowlist["files"][0].update(expected_size_bytes=len(self.raw), sha256_expected=hashlib.sha256(self.raw).hexdigest(), job_id="12345")
        self.repin()

    def check(self, trust=True):
        return c.check_request(self.candidates, self.inventory, self.allowlist, self.request,
                               self.trust if trust else None, now=NOW)

    def observe(self):
        return c.check_local(self.candidates, self.inventory, self.allowlist, self.request, self.trust, now=NOW)

    def test_supplied_ten_candidates_are_only_unchecked(self):
        candidates = c.candidates_from_csv((DOCS / "candidates.csv").read_bytes())
        self.assertEqual(len(candidates["files"]), 10)
        inventory = c.unchecked_inventory(candidates)
        self.assertEqual(inventory, c.load_json((DOCS / "inventory.not-checked.json").read_bytes()))
        for f in inventory["files"]:
            self.assertEqual(f["status"], "NOT_CHECKED")
            self.assertIsNone(f["size_bytes"])
            self.assertIsNone(f["sha256_measured"])
            self.assertIsNone(f["observed_at_utc"])

    def test_schema_is_valid(self):
        schema = json.loads((CSC / "phase2a/contracts.schema.json").read_text())
        c.Draft202012Validator.check_schema(schema)

    def test_missing_independent_approval_denies_before_filesystem(self):
        with patch.object(c, "_open_directory", side_effect=AssertionError("report touched")):
            with self.assertRaises(c.Rejected):
                c.check_local(self.candidates, self.inventory, self.allowlist, self.request, now=NOW)

    def test_empty_trust_store_denies(self):
        self.trust = c.TrustStore()
        with self.assertRaises(c.Rejected):
            self.check()

    def test_self_approval_fields_are_not_authority(self):
        for document in (self.request, self.allowlist):
            for key, value in (("approved", True), ("approval_record_ref", "approval:self")):
                document[key] = value
                with self.assertRaises(c.Rejected):
                    self.check()
                del document[key]

    def test_same_file_claiming_approval_is_not_independent(self):
        self.request["allowlist_sha256"] = c.digest(self.allowlist)
        with self.assertRaises(c.Rejected):
            self.check(trust=False)

    def test_exact_stat_check_without_byte_reads(self):
        with patch("builtins.open", side_effect=AssertionError("bytes read")):
            result = self.observe()
        f = result["files"][0]
        self.assertEqual(f["status"], "AVAILABLE")
        self.assertEqual(f["size_bytes"], len(self.raw))
        self.assertIsNone(f["sha256_measured"])
        self.assertEqual(self.inventory["files"][0]["status"], "NOT_CHECKED")
        self.assertEqual(result["safety"], c.SAFETY)

    def test_approved_synthetic_byte_verification(self):
        self.verify_mode()
        result = self.observe()
        self.assertEqual(result["files"][0]["sha256_measured"], hashlib.sha256(self.raw).hexdigest())
        self.assertEqual(result["safety"]["technical_qa"], "NOT_EVALUATED")

    def test_unresolved_size_and_hash_cannot_authorize_bytes(self):
        self.allowlist["operation"] = "VERIFY_LOCAL_REPORTS"
        self.repin()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_missing_file_is_not_unchecked(self):
        (self.root / "reports/qa.csv").unlink()
        self.assertEqual(self.observe()["files"][0]["status"], "MISSING")

    def test_inaccessible_file_is_unreadable_not_missing(self):
        original = c.os.open
        def denied(path, *args, **kwargs):
            if path == "qa.csv":
                raise PermissionError
            return original(path, *args, **kwargs)
        with patch.object(c.os, "open", side_effect=denied):
            self.assertEqual(self.observe()["files"][0]["status"], "UNREADABLE")

    def test_inaccessible_root_does_not_invent_missing_files(self):
        with patch.object(c, "_open_directory", side_effect=PermissionError):
            with self.assertRaises(c.Rejected):
                self.observe()
        self.assertEqual(self.inventory["files"][0]["status"], "NOT_CHECKED")

    def test_statuses_are_distinct_and_require_evidence(self):
        for state in c.STATES:
            doc = copy.deepcopy(self.inventory)
            f = doc["files"][0]
            f["status"] = state
            if state != "NOT_CHECKED":
                with self.assertRaises(c.Rejected):
                    c.validate(doc, "inventory")
                f.update(observed_at_utc="2026-10-15T12:00:00Z", evidence_ref="synthetic-only")
                if state == "AVAILABLE":
                    f["size_bytes"] = 0
            self.assertEqual(c.validate(doc, "inventory")["files"][0]["status"], state)

    def test_unavailable_states_cannot_contain_measurements(self):
        for state in c.STATES - {"AVAILABLE"}:
            doc = copy.deepcopy(self.inventory)
            doc["files"][0].update(status=state, size_bytes=1)
            with self.assertRaises(c.Rejected):
                c.validate(doc, "inventory")

    def test_unsafe_paths_and_rasters_rejected(self):
        for path in ("../qa.csv", "/tmp/qa.csv", "reports/../qa.csv", "reports//qa.csv", "reports/./qa.csv",
                     "reports/*.csv", "qa?.csv", "{qa,audit}.csv", "qa_<jobid>.log", "reports\\qa.csv",
                     "report.tif", "report.TIF", "report.vrt", "report.gpkg", "report.nc", "~/.ssh/id_rsa",
                     "qa.csv\x00", "qa%2F.csv", "qa.csv;echo", "qa.csv\n"):
            with self.subTest(path=path), self.assertRaises(c.Rejected):
                c.safe_path(path)

    def test_unlisted_file_rejected(self):
        self.request["files"][0]["relative_path"] = "reports/other.csv"
        with self.assertRaises(c.Rejected):
            self.check()

    def test_duplicate_paths_rejected_in_each_contract(self):
        for kind, original in (("candidates", self.candidates), ("inventory", self.inventory),
                               ("allowlist", self.allowlist), ("request", self.request)):
            doc = copy.deepcopy(original)
            doc["files"].append(copy.deepcopy(doc["files"][0]))
            with self.assertRaises(c.Rejected):
                c.validate(doc, kind)

    def test_file_symlink_rejected(self):
        target = self.root / "other.csv"
        target.write_bytes(self.raw)
        path = self.root / "reports/qa.csv"
        path.unlink()
        path.symlink_to(target)
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_parent_symlink_rejected(self):
        (self.root / "reports").rename(self.root / "other")
        (self.root / "reports").symlink_to(self.root / "other", target_is_directory=True)
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_root_and_root_ancestor_symlink_rejected(self):
        for suffix in ("", "/reports"):
            link = self.root / "linked"
            if not link.exists():
                link.symlink_to(self.root, target_is_directory=True)
            self.trust.pins[self.request["request_id"]] = (c.digest(self.allowlist), str(link) + suffix)
            self.trust.used.clear()
            with self.assertRaises(c.Rejected):
                self.observe()

    def test_fifo_and_directory_rejected_without_blocking(self):
        path = self.root / "reports/qa.csv"
        path.unlink()
        os.mkfifo(path)
        with self.assertRaises(c.Rejected):
            self.observe()
        self.trust.used.clear()
        path.unlink()
        path.mkdir()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_oversized_file_rejected_before_byte_open(self):
        self.allowlist["files"][0]["max_bytes"] = 1
        self.repin()
        with patch.object(c.os, "fdopen", side_effect=AssertionError("bytes opened")):
            with self.assertRaises(c.Rejected):
                self.observe()

    def test_total_size_cap(self):
        self.allowlist["max_total_bytes"] = 1
        self.repin()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_global_caps_cannot_be_raised(self):
        for key, value in (("max_total_bytes", c.MAX_TOTAL + 1),):
            self.allowlist[key] = value
            with self.assertRaises(c.Rejected):
                self.check()
        self.allowlist["max_total_bytes"] = c.MAX_TOTAL
        self.allowlist["files"][0]["max_bytes"] = c.MAX_FILE + 1
        with self.assertRaises(c.Rejected):
            self.check()

    def test_checksum_mismatch(self):
        self.verify_mode()
        (self.root / "reports/qa.csv").write_bytes(self.raw.replace(b"52", b"53"))
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_exact_size_mismatch(self):
        self.verify_mode()
        (self.root / "reports/qa.csv").write_bytes(self.raw + b"changed")
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_measured_inventory_cannot_be_replaced_by_expected_hash(self):
        self.verify_mode()
        self.inventory["files"][0]["sha256_measured"] = None
        self.repin()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_request_and_allowlist_have_exact_file_sets(self):
        self.candidates["files"].append({"relative_path": "reports/other.csv", "purpose": "synthetic"})
        self.inventory = c.unchecked_inventory(self.candidates)
        self.repin()
        self.request["files"].append({"relative_path": "reports/other.csv"})
        with self.assertRaises(c.Rejected):
            self.check()

    def test_candidate_binding_cannot_be_replaced(self):
        self.candidates["files"][0]["purpose"] = "changed"
        with self.assertRaises(c.Rejected):
            self.check()

    def test_invalid_calendar_and_reversed_validity_window(self):
        for start, end in (("2026-02-30T11:00:00Z", "2026-10-15T13:00:00Z"),
                           ("2026-10-15T13:00:00Z", "2026-10-15T11:00:00Z")):
            self.allowlist.update(valid_from_utc=start, expires_at_utc=end)
            self.repin()
            with self.assertRaises(c.Rejected):
                self.check()

    def test_raster_disguised_as_csv_is_rejected(self):
        self.raw = b"II*\x00" + b"X" * 12
        (self.root / "reports/qa.csv").write_bytes(self.raw)
        self.verify_mode()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_unknown_job_id(self):
        self.allowlist["files"][0]["job_id"] = "99999"
        self.repin()
        with self.assertRaises(c.Rejected):
            self.check()

    def test_known_array_job_and_step(self):
        self.allowlist["files"][0]["job_id"] = "12345_0.batch"
        self.repin()
        self.check()

    def test_dynamic_log_cannot_hide_an_unknown_job_in_its_name(self):
        for doc in (self.candidates, self.inventory, self.allowlist):
            doc["files"][0]["relative_path"] = "reports/qa_99999.log"
        self.inventory["candidates_sha256"] = c.digest(self.candidates)
        self.repin()
        with self.assertRaises(c.Rejected):
            self.check()
        self.allowlist["files"][0]["job_id"] = "12345"
        self.repin()
        with self.assertRaises(c.Rejected):
            self.check()

    def test_commit_package_and_context_bindings(self):
        for key, value in (("source_commit", "c" * 40), ("package_sha256", "d" * 64),
                           ("branch", "main"), ("repository", "other/repo"),
                           ("csc_root", "/tmp"), ("root_id", "OTHER"),
                           ("output_path", "elsewhere/inventory.json")):
            old = self.request[key]
            self.request[key] = value
            with self.subTest(key=key), self.assertRaises(c.Rejected):
                self.check()
            self.request[key] = old

    def test_allowlist_tampering_cannot_reapprove_itself(self):
        self.allowlist["files"][0]["max_bytes"] += 1
        self.request["allowlist_sha256"] = c.digest(self.allowlist)
        with self.assertRaises(c.Rejected):
            self.check()

    def test_inventory_binding_mismatch(self):
        self.inventory["files"][0]["status"] = "OUT_OF_SCOPE"
        self.inventory["files"][0].update(observed_at_utc="2026-10-15T12:00:00Z", evidence_ref="synthetic")
        with self.assertRaises(c.Rejected):
            self.check()

    def test_expired_future_and_reused_approvals(self):
        for when in (datetime(2026, 10, 15, 10, tzinfo=timezone.utc), datetime(2026, 10, 15, 13, tzinfo=timezone.utc)):
            with self.assertRaises(c.Rejected):
                c.check_request(self.candidates, self.inventory, self.allowlist, self.request, self.trust, now=when)
        self.observe()
        with self.assertRaises(c.Rejected):
            self.observe()

    def test_failed_attempt_consumes_approval(self):
        self.allowlist["max_total_bytes"] = 1
        self.repin()
        with self.assertRaises(c.Rejected):
            self.observe()
        self.assertIn(self.request["request_id"], self.trust.used)

    def test_transfer_and_other_operations_always_rejected(self):
        for operation in ("TRANSFER_REPORTS", "READ_EXISTING_CSC_REPORTS", "SUBMIT", "NATIONAL", "SSH"):
            self.allowlist["operation"] = operation
            self.repin()
            with self.assertRaises(c.Rejected):
                self.check()

    def test_safety_invariants_cannot_be_promoted(self):
        for key, value in (("moderate_status", "PASS"), ("moderate_lakes", 0),
                           ("national", "UNLOCKED"), ("scientific_acceptance", "ACCEPTED"),
                           ("technical_qa", "PASS"), ("scheduler_state", "COMPLETED")):
            doc = copy.deepcopy(self.inventory)
            doc["safety"][key] = value
            with self.assertRaises(c.Rejected):
                c.validate(doc, "inventory")

    def test_duplicate_json_keys_and_complexity_limits(self):
        for raw in (b'{"approved":false,"approved":true}', b'{"x":{"a":1,"a":2}}',
                    b'{"x":NaN}', b'{"x":1e999}', b'{"x":1.0}', b'\xff', b'[' * 25 + b']' * 25,
                    b' ' * (c.MAX_JSON + 1)):
            with self.assertRaises(c.Rejected):
                c.load_json(raw)

    def test_csv_cannot_promote_unverified_candidates(self):
        raw = (DOCS / "candidates.csv").read_bytes()
        for altered in (raw.replace(b"NOT_CHECKED", b"AVAILABLE", 1), raw.replace(b",NO", b",YES", 1),
                        raw.replace(b",sha256_measured,", b",sha256_measured,sha256_measured,", 1)):
            with self.assertRaises(c.Rejected):
                c.candidates_from_csv(altered)

    def test_cli_never_authorizes_operations(self):
        result = subprocess.run([sys.executable, str(CSC / "phase2a/check.py"), "candidate-csv", str(DOCS / "candidates.csv")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["authorization"], "NOT_GRANTED")

    def test_zero_discovered_tests_fail(self):
        result = subprocess.run([sys.executable, str(CSC / "tests/run_tests.py"), "--pattern", "no_tests_phase2a_*.py"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn("zero tests", result.stderr)
