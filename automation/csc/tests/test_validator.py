"""Local contract tests; every manifest, job and QA claim here is synthetic.

These tests do not connect to CSC, submit jobs or validate any hydrology result.
The only subprocesses are this checkout's Python validator and test runner.
"""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TESTS = Path(__file__).resolve().parent
CSC = TESTS.parent
FIXTURES = TESTS / "fixtures"
SPEC = importlib.util.spec_from_file_location("csc_phase1_validator", CSC / "validate_manifest.py")
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


def manifest_fixture():
    return json.loads((FIXTURES / "synthetic_manifest.json").read_text(encoding="utf-8"))


def report_fixture(manifest=None):
    manifest = manifest or manifest_fixture()
    report = json.loads((FIXTURES / "synthetic_report.json").read_text(encoding="utf-8"))
    report["manifest_fingerprint"] = validator.fingerprint_manifest(manifest)
    return report


class ContractAssertions(unittest.TestCase):
    def assertRejected(self, result):
        self.assertEqual(result["status"], "REJECTED", result)
        self.assertEqual(result["authorization"], "NOT_GRANTED", result)
        self.assertEqual(result["scientific_acceptance"], "NOT_GRANTED", result)
        self.assertTrue(result["errors"], result)

    def assertStructurallyValid(self, result):
        self.assertEqual(result["status"], "CONTRACT_VALID", result)
        self.assertEqual(result["authorization"], "NOT_GRANTED", result)
        self.assertEqual(result["scientific_acceptance"], "NOT_GRANTED", result)
        self.assertFalse(result["errors"], result)


class StrictJSONTests(ContractAssertions):
    def test_valid_utf8_object(self):
        self.assertEqual(validator.load_json_bytes(b'{"synthetic":true}'), {"synthetic": True})

    def test_duplicate_keys_at_any_level_are_rejected(self):
        for raw in (b'{"run_type":"READ_EXISTING_CSC_REPORTS","run_type":"NATIONAL"}',
                    b'{"outer":{"a":0,"a":1}}'):
            with self.subTest(raw=raw), self.assertRaises(validator.ValidationError):
                validator.load_json_bytes(raw)

    def test_nonfinite_numbers_are_rejected(self):
        for number in (b"NaN", b"Infinity", b"-Infinity", b"1e9999"):
            with self.subTest(number=number), self.assertRaises(validator.ValidationError):
                validator.load_json_bytes(b'{"number":' + number + b"}")

    def test_invalid_utf8_and_malformed_json_are_rejected(self):
        for raw in (b'{"a":"\xff"}', b'{"a":', b'{"a":1} trailing'):
            with self.subTest(raw=raw), self.assertRaises(validator.ValidationError):
                validator.load_json_bytes(raw)

    def test_nonobject_document_is_rejected(self):
        for raw in (b"[]", b"null", b"42", b'"manifest"'):
            with self.subTest(raw=raw):
                self.assertRejected(validator.validate_manifest(validator.load_json_bytes(raw)))

    def test_oversized_document_is_rejected(self):
        with self.assertRaises(validator.ValidationError):
            validator.load_json_bytes(b'{"large":"' + b"x" * 1048576 + b'"}')

    def test_excessively_deep_document_is_rejected_safely(self):
        raw = b'{"nested":' * 3000 + b"0" + b"}" * 3000
        with self.assertRaises(validator.ValidationError):
            validator.load_json_bytes(raw)


class ManifestTests(ContractAssertions):
    def setUp(self):
        self.manifest = manifest_fixture()

    def test_ready_manifest_is_structurally_valid_but_never_authorized(self):
        before = copy.deepcopy(self.manifest)
        self.assertStructurallyValid(validator.validate_manifest(self.manifest))
        self.assertEqual(self.manifest, before, "Validation must not rewrite input evidence")

    def test_reported_digest_is_not_promoted_to_measured(self):
        self.manifest["inputs"][0]["checksum_basis"] = "REPORTED"
        self.assertStructurallyValid(validator.validate_manifest(self.manifest))
        self.assertEqual(self.manifest["inputs"][0]["checksum_basis"], "REPORTED")

    def test_missing_required_field_is_rejected(self):
        for field in ("run_type", "commit_sha", "slurm_caps", "inputs", "parameters"):
            doc = copy.deepcopy(self.manifest)
            del doc[field]
            with self.subTest(field=field):
                self.assertRejected(validator.validate_manifest(doc))

    def test_draft_missing_digest_is_incomplete_not_authorized(self):
        self.manifest["request_state"] = "DRAFT"
        self.manifest["approval_record_ref"] = None
        self.manifest["inputs"][0]["sha256"] = None
        self.manifest["inputs"][0]["checksum_basis"] = "UNKNOWN"
        result = validator.validate_manifest(self.manifest)
        self.assertEqual(result["status"], "DRAFT_INCOMPLETE", result)
        self.assertEqual(result["authorization"], "NOT_GRANTED")

    def test_national_and_unknown_run_types_are_rejected(self):
        for run_type in ("NATIONAL", "RUN_NATIONAL", "MODERATE", "sbatch", "UNKNOWN"):
            self.manifest["run_type"] = run_type
            with self.subTest(run_type=run_type):
                self.assertRejected(validator.validate_manifest(self.manifest))

    def test_arbitrary_commands_and_forged_approval_are_rejected(self):
        for location, field, value in (
            ((), "command", "sbatch dangerous.sh"),
            ((), "shell", "touch /tmp/csc-never-execute"),
            ((), "approved", True),
            (("parameters",), "command", "rm -rf /"),
            (("slurm_caps",), "submit_command", "sbatch"),
            (("inputs", 0), "command", "curl https://example.invalid"),
        ):
            doc = copy.deepcopy(self.manifest)
            target = doc
            for key in location:
                target = target[key]
            target[field] = value
            with self.subTest(location=location, field=field):
                self.assertRejected(validator.validate_manifest(doc))

    def test_other_repository_or_branch_is_rejected(self):
        for field, value in (("repository", "elsewhere/project"), ("repository_id", 1),
                             ("branch", "main"), ("branch", "EIFFEL")):
            doc = copy.deepcopy(self.manifest)
            doc[field] = value
            with self.subTest(field=field, value=value):
                self.assertRejected(validator.validate_manifest(doc))

    def test_bad_commit_and_checksum_are_rejected(self):
        for value in ("short", "g" * 40, "F" * 40, "a" * 39, "a" * 41):
            self.manifest["commit_sha"] = value
            with self.subTest(commit=value):
                self.assertRejected(validator.validate_manifest(self.manifest))
        self.manifest = manifest_fixture()
        for value in ("short", "g" * 64, "A" * 64, "a" * 63, "a" * 65):
            self.manifest["inputs"][0]["sha256"] = value
            with self.subTest(digest=value):
                self.assertRejected(validator.validate_manifest(self.manifest))

    def test_unsafe_paths_and_raster_reads_are_rejected(self):
        paths = ("/scratch/report.csv", "../report.csv", "reports/../report.csv",
                 "reports/./report.csv", "reports//report.csv", "reports\\report.csv",
                 "C:/report.csv", "reports/%2e%2e/report.csv", "reports/qa.csv\n",
                 "reports/$(sbatch).csv", "reports/*.csv", "reports/water.tif")
        for path in paths:
            self.manifest["inputs"][0]["storage_ref"]["relative_path"] = path
            with self.subTest(path=path):
                self.assertRejected(validator.validate_manifest(self.manifest))

    def test_historical_job_id_report_filenames_are_allowed(self):
        for name in ("compare.jobid", "qa.jobid", "resume.jobid", "jobid", "slurm_jobid"):
            self.manifest["inputs"][0]["storage_ref"]["relative_path"] = "reports/" + name
            with self.subTest(name=name):
                self.assertStructurallyValid(validator.validate_manifest(self.manifest))
                report = report_fixture(self.manifest)
                report["sources"][0]["storage_ref"]["relative_path"] = "reports/" + name
                self.assertStructurallyValid(validator.validate_report(report, self.manifest))

    def test_duplicate_input_identifiers_are_rejected(self):
        self.manifest["inputs"].append(copy.deepcopy(self.manifest["inputs"][0]))
        self.assertRejected(validator.validate_manifest(self.manifest))

    def test_all_submission_capabilities_remain_zero(self):
        for field in self.manifest["slurm_caps"]:
            doc = copy.deepcopy(self.manifest)
            doc["slurm_caps"][field] = True if field == "submission_enabled" else 1
            with self.subTest(field=field):
                self.assertRejected(validator.validate_manifest(doc))

    def test_integer_caps_cannot_be_boolean(self):
        for field in self.manifest["slurm_caps"]:
            if field == "submission_enabled":
                continue
            doc = copy.deepcopy(self.manifest)
            doc["slurm_caps"][field] = False
            with self.subTest(field=field):
                self.assertRejected(validator.validate_manifest(doc))

    def test_invalid_calendar_date_is_rejected(self):
        self.manifest["created_at_utc"] = "2026-02-30T08:00:00Z"
        self.assertRejected(validator.validate_manifest(self.manifest))

    def test_total_limit_cannot_be_smaller_than_per_file_limit(self):
        self.manifest["parameters"]["max_total_bytes"] = 1
        self.assertRejected(validator.validate_manifest(self.manifest))


class FingerprintTests(ContractAssertions):
    def test_same_semantics_ignore_identity_time_approval_and_input_order(self):
        first = manifest_fixture()
        second_input = copy.deepcopy(first["inputs"][0])
        second_input["input_id"] = "synthetic-second"
        second_input["storage_ref"]["relative_path"] = "reports/synthetic-second.csv"
        first["inputs"].append(second_input)
        second = copy.deepcopy(first)
        second["inputs"].reverse()
        second["run_id"] = "00000000-0000-4000-8000-000000000099"
        second["created_at_utc"] = "2026-10-15T09:00:00Z"
        second["approval_record_ref"] = "approval:another-synthetic-reference"
        second["request_state"] = "DRAFT"
        self.assertEqual(validator.fingerprint_manifest(first), validator.fingerprint_manifest(second))
        self.assertRegex(validator.fingerprint_manifest(first), r"^[0-9a-f]{64}$")

    def test_real_semantic_changes_change_fingerprint(self):
        first = manifest_fixture()
        fingerprint = validator.fingerprint_manifest(first)
        for location, key, value in (
            ((), "commit_sha", "1" * 40),
            (("inputs", 0), "input_id", "synthetic-other"),
            (("inputs", 0), "sha256", "1" * 64),
            (("parameters",), "max_file_bytes", 1024),
            ((), "parameters_version", "existing_reports/v2"),
        ):
            second = copy.deepcopy(first)
            target = second
            for part in location:
                target = target[part]
            target[key] = value
            with self.subTest(location=location, key=key):
                self.assertNotEqual(fingerprint, validator.fingerprint_manifest(second))


class ReportTests(ContractAssertions):
    def setUp(self):
        self.manifest = manifest_fixture()
        self.report = report_fixture(self.manifest)

    def test_completed_d8_pass_retains_moderate_review_and_all_52_lakes(self):
        before = copy.deepcopy(self.report)
        self.assertStructurallyValid(validator.validate_report(self.report, self.manifest))
        self.assertEqual(self.report, before)
        self.assertEqual(self.report["jobs"][0]["scheduler_state"], "COMPLETED")
        self.assertEqual(self.report["jobs"][0]["exit_code"]["raw"], "0:0")
        self.assertEqual(self.report["technical_qa"]["status"], "PASS")
        self.assertEqual(self.report["diagnostics"]["positive_threshold_no_component_lakes"], 52)
        self.assertEqual(self.report["scientific_review_state"], "REVIEW_REQUIRED")
        self.assertTrue(self.report["needs_review"])
        self.assertIn("POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE", self.report["review_reasons"])

    def test_scientific_approval_cannot_be_forged(self):
        for state in ("PASS", "APPROVED", "HYDROLOGICALLY_VALID"):
            self.report["scientific_review_state"] = state
            with self.subTest(state=state):
                self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_needs_review_cannot_be_removed(self):
        self.report["needs_review"] = False
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_moderate_review_reason_is_mandatory(self):
        self.report["review_reasons"] = ["SCIENTIFIC_REVIEW_NOT_PERFORMED"]
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_known_moderate_keeps_shoreline_reason_for_zero_or_unknown_count(self):
        for test_id in ("MODERATE", "E0510000_N7620000", "MODERATE_E0510000_N7620000"):
            for count in (0, None):
                doc = copy.deepcopy(self.report)
                doc["diagnostics"].update(test_id=test_id, positive_threshold_no_component_lakes=count)
                with self.subTest(test_id=test_id, count=count):
                    self.assertStructurallyValid(validator.validate_report(doc, self.manifest))
                    doc["review_reasons"] = ["SCIENTIFIC_REVIEW_NOT_PERFORMED"]
                    self.assertRejected(validator.validate_report(doc, self.manifest))

    def test_moderate_cannot_claim_not_assessed_without_review_required(self):
        self.report["scientific_review_state"] = "NOT_ASSESSED"
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_mismatched_manifest_binding_is_rejected(self):
        for field, value in (("run_id", "00000000-0000-4000-8000-000000000099"),
                             ("commit_sha", "1" * 40),
                             ("manifest_fingerprint", "1" * 64)):
            doc = copy.deepcopy(self.report)
            doc[field] = value
            with self.subTest(field=field):
                self.assertRejected(validator.validate_report(doc, self.manifest))

    def test_unknown_source_and_digest_mismatch_are_rejected(self):
        for field, value in (("source_id", "unknown-source"), ("sha256", "1" * 64)):
            doc = copy.deepcopy(self.report)
            doc["sources"][0][field] = value
            with self.subTest(field=field):
                self.assertRejected(validator.validate_report(doc, self.manifest))

    def test_duplicate_source_identifiers_are_rejected(self):
        self.report["sources"].append(copy.deepcopy(self.report["sources"][0]))
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_evidence_cannot_reference_nonexistent_source(self):
        self.report["technical_qa"]["checks"][0]["evidence_refs"][0]["source_id"] = "absent-source"
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_job_times_and_exit_code_must_be_consistent(self):
        for field, value in (("ended_at_utc", "2026-10-14T09:00:00Z"),
                             ("exit_code", {"status": 0, "signal": 0, "raw": "1:0"})):
            doc = copy.deepcopy(self.report)
            doc["jobs"][0][field] = value
            with self.subTest(field=field):
                self.assertRejected(validator.validate_report(doc, self.manifest))

    def test_asserted_scheduler_state_requires_available_bound_evidence(self):
        for state in ("COMPLETED", "FAILED", "TIMEOUT", "NOT_SUBMITTED"):
            doc = copy.deepcopy(self.report)
            doc["jobs"][0]["scheduler_state"] = state
            doc["jobs"][0]["scheduler_state_raw"] = state
            doc["jobs"][0]["evidence_refs"] = []
            doc["technical_qa"] = {"status": "NOT_RUN", "checks": []}
            with self.subTest(state=state, source="absent"):
                self.assertRejected(validator.validate_report(doc, self.manifest))
            doc["jobs"][0]["evidence_refs"] = [
                {"source_id": "synthetic-qa", "locator": "synthetic fixture only"}
            ]
            doc["sources"][0]["availability"] = "NOT_CHECKED"
            with self.subTest(state=state, source="unchecked"):
                self.assertRejected(validator.validate_report(doc, self.manifest))

    def test_expected_and_reported_artifact_hashes_are_not_observed_evidence(self):
        artifact = {
            "artifact_id": "synthetic-storage-raster",
            "storage_ref": {"root_id": "CSC_HYDRO_4BBF22B", "relative_path": "rasters/WATER_STORAGE.tif"},
            "sha256_expected": "a" * 64,
            "sha256_reported": "a" * 64,
            "sha256_observed": None,
            "evidence_refs": [{"source_id": "synthetic-qa", "locator": "synthetic fixture only"}],
        }
        self.report["output_artifacts"] = [artifact]
        self.assertStructurallyValid(validator.validate_report(self.report, self.manifest))
        self.assertIsNone(artifact["sha256_observed"])
        artifact["sha256_observed"] = "a" * 64
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_artifact_digest_mismatch_requires_and_preserves_explicit_review(self):
        self.report["output_artifacts"] = [{
            "artifact_id": "synthetic-mismatched-raster",
            "storage_ref": {"root_id": "CSC_HYDRO_4BBF22B", "relative_path": "rasters/WATER_STORAGE.tif"},
            "sha256_expected": "a" * 64,
            "sha256_reported": "b" * 64,
            "sha256_observed": None,
            "evidence_refs": [{"source_id": "synthetic-qa", "locator": "synthetic fixture only"}],
        }]
        self.assertRejected(validator.validate_report(self.report, self.manifest))
        self.report["review_reasons"].append("ARTIFACT_CHECKSUM_MISMATCH")
        before = copy.deepcopy(self.report)
        result = validator.validate_report(self.report, self.manifest)
        self.assertStructurallyValid(result)
        self.assertIn("ARTIFACT_CHECKSUM_MISMATCH", result["review_reasons"])
        self.assertTrue(result["needs_review"])
        self.assertEqual(self.report, before)

    def test_unchecked_source_is_not_falsely_reported_as_missing(self):
        self.report["sources"][0].update(
            availability="NOT_CHECKED", sha256=None, checksum_basis="UNKNOWN", size_bytes=None
        )
        self.report["technical_qa"] = {"status": "NOT_RUN", "checks": []}
        self.report["jobs"] = []
        self.assertStructurallyValid(validator.validate_report(self.report, self.manifest))
        self.report["missing_files"] = ["synthetic-qa"]
        self.assertRejected(validator.validate_report(self.report, self.manifest))

    def test_pass_requires_available_evidence_and_nonempty_checks(self):
        self.report["technical_qa"]["checks"] = []
        self.assertRejected(validator.validate_report(self.report, self.manifest))
        self.report = report_fixture(self.manifest)
        self.report["sources"][0]["availability"] = "NOT_CHECKED"
        self.assertRejected(validator.validate_report(self.report, self.manifest))


class LocalBundleTests(ContractAssertions):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="csc-synthetic-bundle-")
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name)
        self.root = self.bundle / "CSC_HYDRO_4BBF22B"
        self.file = self.root / "reports" / "synthetic-qa.csv"
        self.file.parent.mkdir(parents=True)
        self.file.write_bytes((FIXTURES / "synthetic-qa.csv").read_bytes())
        self.manifest = manifest_fixture()
        self.report = report_fixture(self.manifest)
        self.report["sources"][0]["checksum_basis"] = "MEASURED"

    def test_exact_local_report_bytes_are_verified(self):
        self.assertStructurallyValid(validator.validate_manifest(self.manifest, bundle_root=self.bundle))
        self.assertStructurallyValid(validator.validate_report(self.report, self.manifest, bundle_root=self.bundle))

    def test_bundle_with_no_available_sources_never_claims_content_verification(self):
        self.report["sources"][0].update(
            availability="NOT_CHECKED", sha256=None, checksum_basis="UNKNOWN", size_bytes=None
        )
        self.report["technical_qa"] = {"status": "NOT_RUN", "checks": []}
        self.report["jobs"] = []
        result = validator.validate_report(self.report, self.manifest, bundle_root=self.bundle)
        self.assertStructurallyValid(result)
        self.assertEqual(result["content_verification"], "NOT_CHECKED")
        self.assertEqual(result["verified_source_count"], 0)

    def test_mixed_bundle_reports_only_the_verified_available_subset(self):
        item = copy.deepcopy(self.manifest["inputs"][0])
        item["input_id"] = "synthetic-not-checked"
        item["storage_ref"]["relative_path"] = "reports/not-checked.csv"
        self.manifest["inputs"].append(item)
        source = copy.deepcopy(self.report["sources"][0])
        source.update(source_id="synthetic-not-checked", availability="NOT_CHECKED",
                      sha256=None, checksum_basis="UNKNOWN", size_bytes=None)
        source["storage_ref"]["relative_path"] = "reports/not-checked.csv"
        self.report["sources"].append(source)
        self.report["manifest_fingerprint"] = validator.fingerprint_manifest(self.manifest)
        result = validator.validate_report(self.report, self.manifest, bundle_root=self.bundle)
        self.assertStructurallyValid(result)
        self.assertEqual(result["content_verification"], "VERIFIED_AVAILABLE_REPORTS")
        self.assertEqual(result["verified_source_count"], 1)

    def test_wrong_content_with_well_formed_digest_is_rejected(self):
        self.file.write_bytes(b"synthetic changed bytes\n")
        self.assertRejected(validator.validate_manifest(self.manifest, bundle_root=self.bundle))
        self.assertRejected(validator.validate_report(self.report, self.manifest, bundle_root=self.bundle))

    def test_source_size_mismatch_is_rejected(self):
        self.report["sources"][0]["size_bytes"] += 1
        self.assertRejected(validator.validate_report(self.report, self.manifest, bundle_root=self.bundle))

    def test_directory_is_not_a_report_file(self):
        self.file.unlink()
        self.file.mkdir()
        self.assertRejected(validator.validate_manifest(self.manifest, bundle_root=self.bundle))

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_symlink_file_cannot_escape_bundle(self):
        target = self.bundle / "outside.csv"
        target.write_bytes(self.file.read_bytes())
        self.file.unlink()
        self.file.symlink_to(target)
        self.assertRejected(validator.validate_manifest(self.manifest, bundle_root=self.bundle))

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_symlink_parent_cannot_escape_bundle(self):
        reports = self.file.parent
        self.file.unlink()
        reports.rmdir()
        external = self.bundle / "outside-reports"
        external.mkdir()
        (external / "synthetic-qa.csv").write_bytes((FIXTURES / "synthetic-qa.csv").read_bytes())
        reports.symlink_to(external, target_is_directory=True)
        self.assertRejected(validator.validate_manifest(self.manifest, bundle_root=self.bundle))

    def test_per_file_limit_is_enforced_before_reading(self):
        self.manifest["parameters"]["max_file_bytes"] = 1
        self.assertRejected(validator.validate_manifest(self.manifest, bundle_root=self.bundle))

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX FIFOs unavailable")
    def test_fifo_is_rejected_without_waiting_for_a_writer(self):
        self.file.unlink()
        os.mkfifo(self.file)
        # A separate Python process and deadline also protect the test suite
        # against regressions to a blocking open on a non-regular source.
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(CSC / "validate_manifest.py"),
             "--kind", "manifest", str(FIXTURES / "synthetic_manifest.json"),
             "--bundle-root", str(self.bundle)],
            text=True, capture_output=True, timeout=5, check=False,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRejected(json.loads(result.stdout))


class DriverTests(ContractAssertions):
    def test_fixture_digest_size_and_fingerprint_are_consistent(self):
        data = (FIXTURES / "synthetic-qa.csv").read_bytes()
        manifest = manifest_fixture()
        stored_report = json.loads((FIXTURES / "synthetic_report.json").read_text(encoding="utf-8"))
        self.assertEqual(hashlib.sha256(data).hexdigest(), manifest["inputs"][0]["sha256"])
        self.assertEqual(stored_report["sources"][0]["sha256"], manifest["inputs"][0]["sha256"])
        self.assertEqual(stored_report["sources"][0]["size_bytes"], len(data))
        self.assertEqual(stored_report["manifest_fingerprint"], validator.fingerprint_manifest(manifest))

    def test_zero_discovered_tests_exit_with_failure(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(TESTS / "run_tests.py"), "--pattern", "test_DOES_NOT_EXIST.py"],
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("zero tests", result.stderr)

    def test_schema_only_cli_is_local_and_succeeds(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(CSC / "validate_manifest.py"), "--schemas-only"],
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cli_valid_manifest_returns_no_authorization(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(CSC / "validate_manifest.py"), "--kind", "manifest",
             str(FIXTURES / "synthetic_manifest.json")],
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertStructurallyValid(payload)

    def test_cli_report_fixture_retains_review(self):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(CSC / "validate_manifest.py"), "--kind", "report",
             str(FIXTURES / "synthetic_report.json"), "--manifest", str(FIXTURES / "synthetic_manifest.json")],
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertStructurallyValid(payload)
        self.assertTrue(payload["needs_review"])
        self.assertEqual(payload["scientific_review_state"], "REVIEW_REQUIRED")


if __name__ == "__main__":
    unittest.main()
