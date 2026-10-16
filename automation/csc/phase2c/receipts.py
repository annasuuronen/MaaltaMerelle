"""Offline verification of project-host CSC *metadata* receipts.

HMAC authenticates a message from an independently trusted host. It is NOT
human approval or scientific provenance. No CSC, network or transfer access.
The ledger is a prototype: its path and ownership must be enforced by the
project-controlled execution environment before any production deployment.
"""
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import uuid

from phase2a import contracts as c
from phase2b.synthetic_adapter import PILOT_PATHS

VERSION = "2c.1"
DOMAIN = b"MAALTAMERELLE_CSC_METADATA_RECEIPT_2C_V1\x00"
MAX_RECEIPT_BYTES = 65536
MAX_AGE = timedelta(hours=1)
MAX_CLOCK_SKEW = timedelta(minutes=2)
RECEIPT_KEYS = frozenset({"schema_version", "kind", "request_id", "collector_commit",
                          "root_id", "csc_root", "observed_at_utc", "operation", "files"})
FILE_KEYS = frozenset({"relative_path", "status", "size_bytes"})


class ReceiptRejected(ValueError):
    """No report contents or credentials in exceptions."""


def _utc(value):
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ReceiptRejected("Timestamp must use UTC and end in Z.")
    try:
        result = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise ReceiptRejected("Invalid UTC timestamp.") from error
    if result.utcoffset() != timedelta(0):
        raise ReceiptRejected("Timestamp not UTC.")
    return result


def _canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True,
                      separators=(",", ":"), allow_nan=False).encode("ascii")


def _validate(document, expected_collector_commit, now):
    if type(document) is not dict or set(document) != RECEIPT_KEYS:
        raise ReceiptRejected("Unexpected receipt fields.")
    if (document["schema_version"] != VERSION or
        document["kind"] != "METADATA_RECEIPT" or
        document["root_id"] != c.ROOT_ID or
        document["csc_root"] != c.CSC_ROOT or
        document["operation"] != "INVENTORY_LOCAL_REPORTS"):
        raise ReceiptRejected("Unexpected metadata scope.")
    if (not isinstance(expected_collector_commit, str) or
        re.fullmatch(r"[a-f0-9]{40}", expected_collector_commit) is None or
        document["collector_commit"] != expected_collector_commit):
        raise ReceiptRejected("Collector commit is not independently pinned.")
    try:
        identifier = str(uuid.UUID(document["request_id"]))
    except (ValueError, TypeError, AttributeError) as error:
        raise ReceiptRejected("Invalid request ID.") from error
    if identifier != document["request_id"]:
        raise ReceiptRejected("Request ID must be canonical.")
    if not isinstance(now, datetime) or now.tzinfo is None:
        raise ReceiptRejected("Trusted host clock must be aware.")
    age = now.astimezone(timezone.utc) - _utc(document["observed_at_utc"])
    if age > MAX_AGE or age < -MAX_CLOCK_SKEW:
        raise ReceiptRejected("Receipt expired or clock-skewed.")
    rows = document["files"]
    if type(rows) is not list or len(rows) != 10:
        raise ReceiptRejected("Receipt requires exactly ten entries.")
    seen, total = set(), 0
    for row in rows:
        if type(row) is not dict or set(row) != FILE_KEYS:
            raise ReceiptRejected("Unexpected receipt row fields.")
        path = row["relative_path"]
        c.safe_path(path)
        if path not in PILOT_PATHS or path in seen:
            raise ReceiptRejected("Unlisted or repeated path.")
        seen.add(path)
        state, size = row["status"], row["size_bytes"]
        if state not in ("AVAILABLE", "MISSING", "UNREADABLE"):
            raise ReceiptRejected("Unexpected file state.")
        if state == "AVAILABLE":
            if type(size) is not int or not (0 <= size <= c.MAX_FILE):
                raise ReceiptRejected("Size outside file cap.")
            total += size
        elif size is not None:
            raise ReceiptRejected("Unavailable file cannot contain size.")
    if seen != PILOT_PATHS or total > c.MAX_TOTAL:
        raise ReceiptRejected("File set or package exceeds scope.")
    return total


def _ledger_file(path):
    """Require a pre-provisioned, private, regular SQLite file.

    The project-owned host must additionally prevent symlink replacement
    races, restore/rollback attacks, and unapproved processes using this path.
    """
    path = Path(path)
    if not path.is_absolute() or path.suffix != ".sqlite3" or path.name in {"", ".", ".."}:
        raise ReceiptRejected("Trusted ledger path must be absolute.")
    try:
        parent_fd = c._open_directory(path.parent)
        try:
            parent = os.fstat(parent_fd)
            if not stat.S_ISDIR(parent.st_mode) or (parent.st_mode & 0o077):
                raise ReceiptRejected("Ledger directory is not private.")
            target = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
            if not stat.S_ISREG(target.st_mode) or (target.st_mode & 0o077):
                raise ReceiptRejected("Ledger file is not owner-only.")
        finally:
            os.close(parent_fd)
    except OSError as error:
        raise ReceiptRejected("Trusted ledger file unavailable.") from error
    return path


def accept_metadata_receipt(raw, mac_hex, host_key, ledger_path, *,
                            expected_collector_commit, now=None):
    """Authenticate a bounded metadata-only receipt; atomically consume UUID.

    The HMAC key and ledger path are injected by an external trusted host.
    This library does not fetch them from a CLI, JSON, env, CI or GitHub.
    """
    if type(raw) is not bytes or len(raw) > MAX_RECEIPT_BYTES:
        raise ReceiptRejected("Receipt too large.")
    if type(host_key) is not bytes or len(host_key) < 32:
        raise ReceiptRejected("Missing host authentication key.")
    if type(mac_hex) is not str or re.fullmatch(r"[a-f0-9]{64}", mac_hex) is None:
        raise ReceiptRejected("Invalid authenticator format.")
    try:
        data = c.load_json(raw)
        total = _validate(data, expected_collector_commit,
                          now if now is not None else datetime.now(timezone.utc))
        canonical = _canonical(data)
    except (c.Rejected, ValueError, TypeError, RecursionError) as error:
        raise ReceiptRejected("Malformed or unsafe receipt.") from error
    expected = hmac.new(host_key, DOMAIN + canonical, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, mac_hex):
        raise ReceiptRejected("Host authentication failed.")
    ledger = _ledger_file(ledger_path)
    try:
        conn = sqlite3.connect(str(ledger), timeout=5, isolation_level=None)
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute("CREATE TABLE IF NOT EXISTS consumed_receipts ("
                         "request_id TEXT PRIMARY KEY NOT NULL, "
                         "receipt_digest TEXT NOT NULL UNIQUE)")
            fingerprint = hashlib.sha256(DOMAIN + canonical).hexdigest()
            conn.execute("INSERT INTO consumed_receipts VALUES (?, ?)",
                         (data["request_id"], fingerprint))
            conn.execute("COMMIT")
        except BaseException:
            try:
                conn.execute("ROLLBACK")
            except sqlite3.Error:
                pass
            raise
        finally:
            conn.close()
    except sqlite3.IntegrityError as error:
        raise ReceiptRejected("Receipt request already consumed.") from error
    except (OSError, sqlite3.Error) as error:
        raise ReceiptRejected("Trusted ledger error; fail closed.") from error
    counts = {s: sum(row["status"] == s for row in data["files"])
              for s in ("AVAILABLE", "MISSING", "UNREADABLE")}
    return {"status": "HOST_METADATA_ATTESTATION_ACCEPTED",
            "receipt_authentication": "HOST_HMAC_VERIFIED",
            "human_approval": "NOT_GRANTED", "report_contents": "NOT_READ",
            "csc_execution": "NOT_PERFORMED_BY_THIS_MODULE",
            "technical_qa": "NOT_EVALUATED",
            "scientific_acceptance": "NOT_GRANTED",
            "moderate_review": "REVIEW_REQUIRED", "national": "LOCKED",
            "files": 10, "counts": counts, "total_available_bytes": total}
