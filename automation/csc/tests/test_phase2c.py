"""Synthetic-only phase 2C receipt verification and atomic replay tests."""

import copy
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import uuid

CSC = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CSC))
from phase2a import contracts as c
from phase2b import synthetic_adapter as s
from phase2c import receipts as r

NOW = datetime(2026, 10, 16, 7, tzinfo=timezone.utc)
KEY = b"SYNTHETIC_TEST_MATERIAL_DO_NOT_USE_FOR_PRODUCTION"
COLLECTOR = "f" * 40
MISSING = "moderate_resume_20261014_v2/run/02_baseline/02D8_final_spill_evidence.csv"
AUTOMAC = object()


class MetadataReceiptTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.ledger = self.root / "requests.sqlite3"
        with sqlite3.connect(self.ledger):
            pass
        self.ledger.chmod(0o600)
        self.doc = {
            "schema_version": r.VERSION, "kind": "METADATA_RECEIPT",
            "request_id": str(uuid.UUID("00000000-0000-4000-8000-00000000002c")),
            "collector_commit": COLLECTOR, "root_id": c.ROOT_ID,
            "csc_root": c.CSC_ROOT, "observed_at_utc": "2026-10-16T06:59:00Z",
            "operation": "INVENTORY_LOCAL_REPORTS",
            "files": [{"relative_path": path,
                       "status": "MISSING" if path == MISSING else "AVAILABLE",
                       "size_bytes": None if path == MISSING else 5}
                      for path in sorted(s.PILOT_PATHS)],
        }

    def signed(self, document=None):
        d = self.doc if document is None else document
        raw = json.dumps(d, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=True).encode("ascii")
        return raw, hmac.new(KEY, r.DOMAIN + raw, hashlib.sha256).hexdigest()

    def accept(self, document=None, *, raw=None, mac=AUTOMAC,
               key=KEY, ledger=None, collector=COLLECTOR, now=NOW):
        if raw is None:
            raw, generated_mac = self.signed(document)
        else:
            generated_mac = hmac.new(KEY, r.DOMAIN + raw, hashlib.sha256).hexdigest()
        if mac is AUTOMAC:
            mac = generated_mac
        return r.accept_metadata_receipt(
            raw, mac, key, str(ledger or self.ledger),
            expected_collector_commit=collector, now=now)

    def test_success_is_redacted_and_not_scientific_pass(self):
        result = self.accept()
        self.assertEqual(result["counts"], {"AVAILABLE": 9, "MISSING": 1, "UNREADABLE": 0})
        self.assertEqual(result["total_available_bytes"], 45)
        self.assertEqual(result["receipt_authentication"], "HOST_HMAC_VERIFIED")
        self.assertEqual(result["human_approval"], "NOT_GRANTED")
        self.assertEqual(result["technical_qa"], "NOT_EVALUATED")
        self.assertEqual(result["scientific_acceptance"], "NOT_GRANTED")
        self.assertEqual(result["national"], "LOCKED")
        self.assertEqual(result["moderate_review"], "REVIEW_REQUIRED")
        self.assertEqual(result["report_contents"], "NOT_READ")
        self.assertEqual(set(result), {"status", "receipt_authentication", "human_approval",
            "report_contents", "csc_execution", "technical_qa", "scientific_acceptance",
            "moderate_review", "national", "files", "counts", "total_available_bytes"})
        with sqlite3.connect(self.ledger) as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM consumed_receipts").fetchone()[0], 1)

    def test_restart_replay_rejected(self):
        self.accept()
        with self.assertRaises(r.ReceiptRejected):
            self.accept()

    def test_parallel_replay_only_one_wins(self):
        raw, mac = self.signed()
        def attempt(_):
            try:
                self.accept(raw=raw, mac=mac)
                return "PASS"
            except r.ReceiptRejected:
                return "DENY"
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(attempt, (0, 1))), ["DENY", "PASS"])

    def test_replay_with_mutated_payload_same_id_denied(self):
        self.accept()
        altered = copy.deepcopy(self.doc)
        altered["files"][0]["size_bytes"] = 6
        with self.assertRaises(r.ReceiptRejected):
            self.accept(altered)

    def test_invalid_hmac_or_tampered_body_denied(self):
        raw, mac = self.signed()
        altered = raw.replace(b'"size_bytes":5', b'"size_bytes":6', 1)
        for data, signature in ((raw, "0" * 64), (altered, mac)):
            with self.assertRaises(r.ReceiptRejected):
                self.accept(raw=data, mac=signature)
        with sqlite3.connect(self.ledger) as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='consumed_receipts'").fetchone()[0], 0)

    def test_invalid_secret_is_not_accepted(self):
        for key in (None, b"", b"short", "environment-token"):
            with self.subTest(key_type=type(key)), self.assertRaises(r.ReceiptRejected):
                self.accept(key=key)

    def test_invalid_signature_format_denied(self):
        for mac in (None, "", "f" * 63, "G" * 64, "A" * 64):
            with self.subTest(mac=mac), self.assertRaises(r.ReceiptRejected):
                self.accept(mac=mac)

    def test_source_commit_must_be_independently_pinned(self):
        with self.assertRaises(r.ReceiptRejected):
            self.accept(collector="e" * 40)
        altered = copy.deepcopy(self.doc)
        altered["collector_commit"] = "e" * 40
        with self.assertRaises(r.ReceiptRejected):
            self.accept(altered)

    def test_unknown_fields_and_approval_claim_denied(self):
        for key in ("approved", "transfer", "raw_csv", "command", "token"):
            altered = copy.deepcopy(self.doc)
            altered[key] = True
            with self.subTest(key=key), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)
        altered = copy.deepcopy(self.doc)
        altered["files"][0]["scientific_pass"] = True
        with self.assertRaises(r.ReceiptRejected):
            self.accept(altered)

    def test_duplicate_json_keys_nonfinite_and_invalid_utf8_denied(self):
        for raw in (b'{"x":1,"x":2}', b'{"x":NaN}', b'\xff', b'{"x":1.5}'):
            with self.subTest(raw=raw), self.assertRaises(r.ReceiptRejected):
                self.accept(raw=raw)

    def test_wrong_and_duplicate_paths_denied(self):
        self.assertEqual({x["relative_path"] for x in self.doc["files"]}, s.PILOT_PATHS)
        for path in ("../private.csv", "/tmp/read.csv", "unlisted.csv", "data.tif"):
            altered = copy.deepcopy(self.doc)
            altered["files"][0]["relative_path"] = path
            with self.subTest(path=path), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)
        altered = copy.deepcopy(self.doc)
        altered["files"][0]["relative_path"] = altered["files"][1]["relative_path"]
        with self.assertRaises(r.ReceiptRejected):
            self.accept(altered)

    def test_exact_ten_entries_required(self):
        for count in (9, 11):
            altered = copy.deepcopy(self.doc)
            altered["files"] = altered["files"][:9] if count == 9 else altered["files"] + [altered["files"][0]]
            with self.subTest(count=count), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)

    def test_invalid_size_status_combination_denied(self):
        for status, size in (("PASS", None), ("NOT_CHECKED", None),
                            ("AVAILABLE", True), ("AVAILABLE", -1),
                            ("AVAILABLE", c.MAX_FILE + 1), ("MISSING", 1),
                            ("UNREADABLE", 0)):
            altered = copy.deepcopy(self.doc)
            altered["files"][0].update(status=status, size_bytes=size)
            with self.subTest(status=status, size=size), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)

    def test_total_cap_enforced(self):
        altered = copy.deepcopy(self.doc)
        for row in altered["files"]:
            row.update(status="AVAILABLE", size_bytes=3 * 1024 * 1024)
        with self.assertRaises(r.ReceiptRejected):
            self.accept(altered)

    def test_wrong_root_operation_kind_denied(self):
        for k, v in (("root_id", "OTHER"), ("csc_root", "/tmp"),
                     ("operation", "TRANSFER_REPORTS"),
                     ("kind", "QA_PASS"), ("schema_version", "INVALID")):
            altered = copy.deepcopy(self.doc)
            altered[k] = v
            with self.subTest(field=k), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)

    def test_expired_or_future_receipt_denied(self):
        for time in (NOW - timedelta(hours=2), NOW + timedelta(minutes=5)):
            altered = copy.deepcopy(self.doc)
            altered["observed_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ")
            with self.subTest(time=time), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)

    def test_bad_utc_timestamp_denied(self):
        for stamp in (None, "2026-10-16T07:00:00+03:00", "2026-02-30T07:00:00Z"):
            altered = copy.deepcopy(self.doc)
            altered["observed_at_utc"] = stamp
            with self.subTest(stamp=stamp), self.assertRaises(r.ReceiptRejected):
                self.accept(altered)

    def test_unprovisioned_or_symlink_ledger_denied(self):
        with self.assertRaises(r.ReceiptRejected):
            self.accept(ledger=self.root / "missing.sqlite3")
        target = self.root / "linked.sqlite3"
        target.symlink_to(self.ledger)
        with self.assertRaises(r.ReceiptRejected):
            self.accept(ledger=target)

    def test_world_writable_ledger_parent_denied(self):
        directory = self.root / "public"
        directory.mkdir()
        directory.chmod(0o777)
        target = directory / "ledger.sqlite3"
        with sqlite3.connect(target):
            pass
        target.chmod(0o600)
        with self.assertRaises(r.ReceiptRejected):
            self.accept(ledger=target)

    def test_ledger_file_permissions_denied(self):
        self.ledger.chmod(0o644)
        with self.assertRaises(r.ReceiptRejected):
            self.accept()

    def test_payload_size_limit_denied(self):
        with self.assertRaises(r.ReceiptRejected):
            self.accept(raw=b" " * (r.MAX_RECEIPT_BYTES + 1))


if __name__ == "__main__":
    unittest.main()
