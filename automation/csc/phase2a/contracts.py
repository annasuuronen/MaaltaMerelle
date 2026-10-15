"""Strict offline contracts and a fail-closed local report verifier.

TrustStore is injected by a trusted host, never constructed from a manifest.
The CLI cannot install approvals. Local checks return observations, never bytes.
No scheduler state, technical QA PASS or scientific acceptance is inferred.
"""

import csv
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry
from referencing.exceptions import NoSuchResource


ROOT_ID = "CSC_HYDRO_4BBF22B"
CSC_ROOT = "/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02"
REPOSITORY = "annasuuronen/MaaltaMerelle"
BRANCH = "baseline-no-structures"
MAX_FILE = 5 * 1024 * 1024
MAX_TOTAL = 25 * 1024 * 1024
MAX_JSON = 1024 * 1024
STATES = {"NOT_CHECKED", "MISSING", "UNREADABLE", "AVAILABLE", "OUT_OF_SCOPE"}
SAFETY = {
    "moderate_lakes": 52,
    "moderate_status": "REVIEW_REQUIRED",
    "reason": "POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE",
    "national": "LOCKED",
    "scientific_acceptance": "NOT_GRANTED",
    "technical_qa": "NOT_EVALUATED",
    "scheduler_state": "UNKNOWN",
}
CSV_FIELDS = ["root_id", "relative_path", "purpose", "expected_status",
              "verified_exists", "size_bytes", "sha256_measured", "transfer_approved"]


class Rejected(ValueError):
    """A rejected contract or operation; messages do not echo report contents."""


def digest(value):
    """Domain-specific canonical JSON: contracts use strings, ints and null only."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def load_json(raw):
    if not isinstance(raw, bytes) or len(raw) > MAX_JSON:
        raise Rejected("Control document exceeds its byte limit.")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Rejected("Duplicate JSON key.")
            result[key] = value
        return result

    def invalid(_):
        raise Rejected("Nonfinite number.")

    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_constant=invalid)
        stack = [(result, 0)]
        nodes = 0
        while stack:
            value, depth = stack.pop()
            nodes += 1
            if depth > 20 or nodes > 20000 or isinstance(value, float):
                raise Rejected("Control document complexity or numeric type rejected.")
            if isinstance(value, dict):
                stack.extend((child, depth + 1) for child in value.values())
            elif isinstance(value, list):
                stack.extend((child, depth + 1) for child in value)
        return result
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Rejected("Invalid strict JSON document.") from error


def safe_path(path):
    if not isinstance(path, str) or len(path) > 512:
        raise Rejected("Unsafe report path.")
    parts = path.split("/")
    if any(not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*", part) for part in parts):
        raise Rejected("Unsafe report path.")
    if Path(parts[-1]).suffix not in {".csv", ".txt", ".log", ".json", ".jobid"} and parts[-1] not in {"jobid", "slurm_jobid"}:
        raise Rejected("Not a small report path; raster and binary paths are forbidden.")
    return parts


def _time(value):
    try:
        if not isinstance(value, str) or not value.endswith("Z"):
            raise ValueError
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise Rejected("Invalid UTC timestamp.") from error


def validate(document, kind):
    if kind not in {"candidates", "inventory", "allowlist", "request"}:
        raise Rejected("Unknown contract kind.")
    try:
        load_json(json.dumps(document, allow_nan=False).encode())
    except (TypeError, ValueError, RecursionError) as error:
        raise Rejected("Invalid control document.") from error
    schema = json.loads(Path(__file__).with_name("contracts.schema.json").read_text())

    def deny_remote(uri):
        raise NoSuchResource(ref=uri)

    validator = Draft202012Validator(
        {"$ref": "#/$defs/" + kind, "$defs": schema["$defs"]},
        format_checker=FormatChecker(), registry=Registry(retrieve=deny_remote))
    if next(validator.iter_errors(document), None) is not None:
        raise Rejected("Contract schema rejected the document.")
    seen = set()
    for item in document["files"]:
        path = item["relative_path"]
        safe_path(path)
        if path in seen:
            raise Rejected("Duplicate exact path.")
        seen.add(path)
        if kind == "inventory":
            state = item["status"]
            measured = (item["size_bytes"], item["sha256_measured"])
            if state == "NOT_CHECKED":
                if any(value is not None for value in (*measured, item["observed_at_utc"], item["evidence_ref"])):
                    raise Rejected("Unchecked item cannot contain observations.")
            elif item["observed_at_utc"] is None or not item["evidence_ref"]:
                raise Rejected("Observation requires time and evidence.")
            if state != "AVAILABLE" and any(value is not None for value in measured):
                raise Rejected("Unavailable item cannot contain size or measured checksum.")
            if state == "AVAILABLE" and item["size_bytes"] is None:
                raise Rejected("Available item requires an observed size.")
            if item["observed_at_utc"] is not None:
                _time(item["observed_at_utc"])
    if kind == "allowlist":
        if _time(document["valid_from_utc"]) >= _time(document["expires_at_utc"]):
            raise Rejected("Invalid approval validity window.")
        total = 0
        for item in document["files"]:
            if document["operation"] == "VERIFY_LOCAL_REPORTS" and (item["expected_size_bytes"] is None or item["sha256_expected"] is None):
                raise Rejected("Byte verification requires exact size and checksum.")
            if item["expected_size_bytes"] is not None:
                if item["expected_size_bytes"] > item["max_bytes"]:
                    raise Rejected("Expected size exceeds file limit.")
                total += item["expected_size_bytes"]
        if total > document["max_total_bytes"]:
            raise Rejected("Expected total exceeds package limit.")
    return document


def candidates_from_csv(raw):
    if len(raw) > MAX_JSON:
        raise Rejected("Candidate CSV too large.")
    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8"), newline=""), strict=True)
        if reader.fieldnames != CSV_FIELDS:
            raise Rejected("Unexpected CSV columns.")
        files = []
        for row in reader:
            if (set(row) != set(CSV_FIELDS) or row["root_id"] != ROOT_ID or
                    row["expected_status"] != "EXPECTED_UNVERIFIED" or
                    row["verified_exists"] != "NOT_CHECKED" or
                    row["size_bytes"] != "" or row["sha256_measured"] != "" or
                    row["transfer_approved"] != "NO"):
                raise Rejected("Candidate CSV contains observations or approval claims.")
            files.append({"relative_path": row["relative_path"], "purpose": row["purpose"]})
    except (UnicodeError, csv.Error) as error:
        raise Rejected("Invalid candidate CSV.") from error
    return validate({"schema_version": "2a.1", "kind": "candidates", "root_id": ROOT_ID,
                     "safety": dict(SAFETY), "files": files}, "candidates")


def unchecked_inventory(candidates):
    validate(candidates, "candidates")
    return validate({"schema_version": "2a.1", "kind": "inventory", "root_id": ROOT_ID,
                     "candidates_sha256": digest(candidates), "safety": dict(SAFETY),
                     "files": [{"relative_path": f["relative_path"], "status": "NOT_CHECKED",
                                "size_bytes": None, "sha256_measured": None,
                                "observed_at_utc": None, "evidence_ref": None}
                               for f in candidates["files"]]}, "inventory")


@dataclass
class TrustStore:
    """Host-owned policy, separate from every untrusted contract.

    pins: request_id -> (digest of complete approved allowlist, local mirror root).
    No JSON/CSV/CLI loader is provided. Empty by default. Tests inject synthetic
    grants. This in-memory one-shot ledger is NOT production approval storage.
    """

    pins: dict = field(default_factory=dict)
    known_job_ids: frozenset = frozenset()
    used: set = field(default_factory=set)


def check_request(candidates, inventory, allowlist, request, trust=None, *, now=None):
    """Check a local operation before any report path is touched."""
    for document, kind in ((candidates, "candidates"), (inventory, "inventory"),
                           (allowlist, "allowlist"), (request, "request")):
        validate(document, kind)
    if not isinstance(trust, TrustStore) or request["request_id"] not in trust.pins:
        raise Rejected("No independent approval; operation denied.")
    approved_digest, local_root = trust.pins[request["request_id"]]
    if digest(allowlist) != approved_digest or request["allowlist_sha256"] != approved_digest:
        raise Rejected("Approval does not bind this exact allowlist.")
    if request["request_id"] in trust.used:
        raise Rejected("Approval already consumed.")
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None or not (_time(allowlist["valid_from_utc"]) <= now < _time(allowlist["expires_at_utc"])):
        raise Rejected("Approval not currently valid.")
    for key in ("request_id", "operation", "repository", "branch", "source_commit",
                "package_sha256", "root_id", "csc_root", "output_path"):
        if request[key] != allowlist[key]:
            raise Rejected("Request escaped approved context.")
    safe_path(request["output_path"])
    if inventory["candidates_sha256"] != digest(candidates) or allowlist["candidates_sha256"] != digest(candidates) or allowlist["inventory_sha256"] != digest(inventory):
        raise Rejected("Inventory/candidate binding mismatch.")
    candidate_paths = {f["relative_path"] for f in candidates["files"]}
    inventory_paths = {f["relative_path"] for f in inventory["files"]}
    allowed = {f["relative_path"]: f for f in allowlist["files"]}
    requested = {f["relative_path"] for f in request["files"]}
    if inventory_paths != candidate_paths or not set(allowed) <= candidate_paths or requested != set(allowed):
        raise Rejected("Request does not match the approved exact file set.")
    observations = {f["relative_path"]: f for f in inventory["files"]}
    for item in allowlist["files"]:
        job = item["job_id"]
        if job is not None and job not in trust.known_job_ids:
            raise Rejected("Unknown job ID.")
        name = Path(item["relative_path"]).name
        if name.endswith(".log") and name != "resume.log":
            match = re.fullmatch(r"(?:probe|qa|audit|job|compare|hydro)_([1-9][0-9]*(?:_[0-9]+)?)\.log", name)
            if match is None or job is None or match[1] != job.split(".")[0]:
                raise Rejected("Dynamic log requires an exact known job-ID binding.")
        observation = observations[item["relative_path"]]
        if request["operation"] == "VERIFY_LOCAL_REPORTS":
            if observation["status"] != "AVAILABLE" or observation["size_bytes"] != item["expected_size_bytes"] or observation["sha256_measured"] != item["sha256_expected"]:
                raise Rejected("Verified-byte request lacks matching measured inventory.")
    return Path(local_root)


def _open_directory(path):
    """Absolute component walk, including every ancestor of the local root."""
    path = os.fspath(path)
    if not path.startswith("/") or any(p in {"", ".", ".."} for p in path[1:].split("/")):
        raise Rejected("Local root must be an exact absolute directory.")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path[1:].split("/"):
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def _observe(root_fd, item, operation, timestamp):
    parts = safe_path(item["relative_path"])
    directory = os.dup(root_fd)
    result = {"relative_path": item["relative_path"], "status": "NOT_CHECKED",
              "size_bytes": None, "sha256_measured": None,
              "observed_at_utc": timestamp, "evidence_ref": "LOCAL_CHECK_ONLY"}
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        # O_PATH inspects symlinks/FIFOs without opening or reading their target.
        meta_fd = os.open(parts[-1], os.O_PATH | os.O_NOFOLLOW, dir_fd=directory)
        try:
            metadata = os.fstat(meta_fd)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > item["max_bytes"]:
                raise Rejected("Not a regular bounded report; no data was read.")
            if item["expected_size_bytes"] is not None and metadata.st_size != item["expected_size_bytes"]:
                raise Rejected("Observed size differs from the approved exact size.")
            if operation == "VERIFY_LOCAL_REPORTS":
                fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
                with os.fdopen(fd, "rb") as stream:
                    before = os.fstat(stream.fileno())
                    if not stat.S_ISREG(before.st_mode) or (before.st_dev, before.st_ino, before.st_size) != (metadata.st_dev, metadata.st_ino, item["expected_size_bytes"]):
                        raise Rejected("Report changed before verification.")
                    read_limit = item["expected_size_bytes"] + 1
                    prefix = stream.read(min(4, read_limit))
                    if prefix in {b"II*\x00", b"MM\x00*", b"II+\x00", b"MM\x00+"}:
                        raise Rejected("Raster content is forbidden even under a report name.")
                    raw = prefix + stream.read(read_limit - len(prefix))
                    try:
                        raw.decode("utf-8")
                        if b"\x00" in raw:
                            raise ValueError
                    except (UnicodeError, ValueError) as error:
                        raise Rejected("Only UTF-8 text reports can be verified.") from error
                    after = os.fstat(stream.fileno())
                    if (len(raw) != item["expected_size_bytes"] or len(raw) > item["max_bytes"] or
                            hashlib.sha256(raw).hexdigest() != item["sha256_expected"] or
                            (before.st_size, before.st_mtime_ns, before.st_ctime_ns) !=
                            (after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
                        raise Rejected("Report size, checksum or stability mismatch.")
                    result["sha256_measured"] = hashlib.sha256(raw).hexdigest()
            result.update(status="AVAILABLE", size_bytes=metadata.st_size)
        finally:
            os.close(meta_fd)
    except FileNotFoundError:
        result["status"] = "MISSING"
    except PermissionError:
        result["status"] = "UNREADABLE"
    except OSError as error:
        raise Rejected("Unsafe or unreadable local layout.") from error
    finally:
        os.close(directory)
    return result


def check_local(candidates, inventory, allowlist, request, trust=None, *, now=None):
    """Local checker only. No copy, remote access, scheduler query or QA parsing.

    Consume approval on the attempt, including failure. Unavailable root is an
    error, never evidence that individual files are MISSING. Use only synthetic
    fixtures in phase 2A. Future CSC use requires a separately reviewed adapter.
    """
    root = check_request(candidates, inventory, allowlist, request, trust, now=now)
    trust.used.add(request["request_id"])
    try:
        root_fd = _open_directory(root)
    except OSError as error:
        raise Rejected("Root not checked; no file observations made.") from error
    try:
        timestamp = (now or datetime.now(timezone.utc)).isoformat().replace("+00:00", "Z")
        files = [_observe(root_fd, item, request["operation"], timestamp) for item in allowlist["files"]]
        if sum(f["size_bytes"] or 0 for f in files) > allowlist["max_total_bytes"]:
            raise Rejected("Total report size exceeds approved cap.")
    finally:
        os.close(root_fd)
    result = unchecked_inventory(candidates)
    observed = {f["relative_path"]: f for f in files}
    result["files"] = [observed.get(f["relative_path"], f) for f in result["files"]]
    return validate(result, "inventory")
