#!/usr/bin/env python3
"""Offline CSC contract validation. No connection, collection or job submission.

CONTRACT_VALID is neither authorization nor proof of scientific validity.
Optional bundle verification reads only bounded, named local report files.
"""

import argparse
from datetime import datetime
from functools import lru_cache
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import sys

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry
from referencing.exceptions import NoSuchResource
import rfc8785


MAX_DOCUMENT_BYTES = 1_048_576
MAX_DEPTH = 20
MAX_NODES = 20_000
ROOT_ID = "CSC_HYDRO_4BBF22B"
SCHEMA_DIRECTORY = Path(__file__).resolve().parent
REPORT_SUFFIXES = {".log", ".txt", ".csv", ".json", ".jobid"}
JOB_ID_BASENAMES = {"jobid", "slurm_jobid"}


class ValidationError(ValueError):
    """A rejected input, without echoing potentially sensitive input values."""


def _bounded_tree(value):
    stack = [(value, 0)]
    nodes = 0
    while stack:
        item, depth = stack.pop()
        nodes += 1
        if depth > MAX_DEPTH or nodes > MAX_NODES:
            raise ValidationError("JSON nesting or node limit exceeded.")
        if isinstance(item, float) and not math.isfinite(item):
            raise ValidationError("Nonfinite JSON numbers are forbidden.")
        if isinstance(item, dict):
            if not all(isinstance(key, str) for key in item):
                raise ValidationError("JSON object keys must be strings.")
            stack.extend((child, depth + 1) for child in item.values())
        elif isinstance(item, list):
            stack.extend((child, depth + 1) for child in item)
        elif item is not None and not isinstance(item, (str, int, float, bool)):
            raise ValidationError("Unsupported JSON value type.")


def load_json_bytes(raw):
    if not isinstance(raw, bytes) or len(raw) > MAX_DOCUMENT_BYTES:
        raise ValidationError("JSON document exceeds the byte limit or is not bytes.")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValidationError("Duplicate JSON object key.")
            result[key] = value
        return result

    def reject_constant(_value):
        raise ValidationError("Nonfinite JSON numbers are forbidden.")

    try:
        document = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                              parse_constant=reject_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as error:
        if isinstance(error, ValidationError):
            raise
        raise ValidationError("Invalid UTF-8 JSON document.") from error
    _bounded_tree(document)
    return document


@lru_cache(maxsize=2)
def _schema(kind):
    names = {"manifest": "run_manifest.schema.json", "report": "report.schema.json"}
    if kind not in names:
        raise ValidationError("Unknown document kind.")
    schema = load_json_bytes(_read_bounded(SCHEMA_DIRECTORY / names[kind], MAX_DOCUMENT_BYTES))
    stack = [schema]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            for keyword in ("$ref", "$dynamicRef"):
                if keyword in node and (not isinstance(node[keyword], str) or
                                        not node[keyword].startswith("#/")):
                    raise ValidationError("Remote schema references are forbidden.")
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
    Draft202012Validator.check_schema(schema)
    return schema


def _schema_errors(document, kind):
    _bounded_tree(document)
    def deny_remote(uri):
        raise NoSuchResource(ref=uri)
    validator = Draft202012Validator(
        _schema(kind), format_checker=FormatChecker(), registry=Registry(retrieve=deny_remote)
    )
    errors = []
    for error in validator.iter_errors(document):
        # Do not echo rejected values or free-text log contents into CI output.
        path = "/".join(str(part) for part in error.absolute_path) or "<root>"
        errors.append(f"{path}: {error.validator} constraint failed")
        if len(errors) >= 100:
            break
    return errors


def _check_times(document):
    stack = [document]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            for key, value in node.items():
                if key.endswith("_utc") and value is not None:
                    try:
                        if not isinstance(value, str) or not value.endswith("Z"):
                            raise ValueError
                        datetime.fromisoformat(value.removesuffix("Z") + "+00:00")
                    except ValueError as error:
                        raise ValidationError("Invalid UTC calendar timestamp.") from error
                stack.append(value)
        elif isinstance(node, list):
            stack.extend(node)


def _check_storage_ref(reference, report_file=True):
    if reference["root_id"] != ROOT_ID:
        raise ValidationError("Unrecognized storage root.")
    path = reference["relative_path"]
    parts = path.split("/")
    if (not path or len(path) > 512 or
            any(not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*", part)
                for part in parts)):
        raise ValidationError("Unsafe relative storage path.")
    if report_file and (Path(parts[-1]).suffix not in REPORT_SUFFIXES and
                        parts[-1] not in JOB_ID_BASENAMES):
        raise ValidationError("Only named small report files can be read.")
    return [ROOT_ID, *parts]


def _unique(values, description):
    if len(values) != len(set(values)):
        raise ValidationError("Duplicate " + description + ".")


def _result(status, errors=(), **extra):
    return {
        "status": status,
        "authorization": "NOT_GRANTED",
        "scientific_acceptance": "NOT_GRANTED",
        "errors": list(errors),
        **extra,
    }


def fingerprint_manifest(document):
    """Semantic identity; physical locators/UUID/time/approval are not a job key.

    Paths remain bound separately by request_digest. A fingerprint never grants
    permission or performs deduplication against any remote scheduler.
    """
    semantic = {key: document[key] for key in (
        "schema_version", "repository", "repository_id", "branch", "commit_sha",
        "run_type", "template_id", "parameters_version", "parameters", "slurm_caps"
    )}
    inputs = document["inputs"]
    _unique([item["input_id"] for item in inputs], "input IDs")
    semantic["inputs"] = sorted(
        [{key: item[key] for key in ("input_id", "sha256", "checksum_basis", "required")}
         for item in inputs], key=lambda item: item["input_id"]
    )
    try:
        return hashlib.sha256(rfc8785.dumps(semantic)).hexdigest()
    except (ValueError, TypeError) as error:
        raise ValidationError("Manifest cannot be canonically encoded.") from error


def _read_bounded(path, limit):
    """Read a regular local JSON file without following the final symlink."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
            raise ValidationError("Not a regular file within the byte limit.")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValidationError("File exceeds the byte limit.")
        return data


def _read_bundle_file(bundle_root, reference, limit):
    """Walk with directory FDs: no symlink, FIFO, or path-escape traversal."""
    parts = _check_storage_ref(reference)
    directory = os.open(bundle_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            next_directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                     dir_fd=directory)
            os.close(directory)
            directory = next_directory
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                     dir_fd=directory)
        with os.fdopen(fd, "rb") as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
                raise ValidationError("Bundle source is not a bounded regular report file.")
            data = stream.read(limit + 1)
            if len(data) > limit:
                raise ValidationError("Bundle report exceeds the byte limit.")
            return data
    finally:
        os.close(directory)


def _verify_bundle(items, parameters, bundle_root, report=False):
    total = 0
    verified = 0
    for item in items:
        if report and item["availability"] != "AVAILABLE":
            continue
        raw = _read_bundle_file(bundle_root, item["storage_ref"],
                                parameters["max_file_bytes"])
        total += len(raw)
        if total > parameters["max_total_bytes"]:
            raise ValidationError("Bundle exceeds the total byte limit.")
        if item["sha256"] != hashlib.sha256(raw).hexdigest():
            raise ValidationError("Local report SHA256 does not match the declared digest.")
        if report and len(raw) != item["size_bytes"]:
            raise ValidationError("Local report size does not match the declared size.")
        verified += 1
    return verified


def validate_manifest(document, bundle_root=None):
    try:
        errors = _schema_errors(document, "manifest")
        if errors:
            return _result("REJECTED", errors)
        _check_times(document)
        _unique([item["input_id"] for item in document["inputs"]], "input IDs")
        locations = []
        unresolved = []
        for item in document["inputs"]:
            locations.append(tuple(_check_storage_ref(item["storage_ref"])))
            if item["sha256"] is None or item["checksum_basis"] == "UNKNOWN":
                unresolved.append("INPUT_CHECKSUM_UNRESOLVED:" + item["input_id"])
        _unique(locations, "input locations")
        limits = document["parameters"]
        if limits["max_total_bytes"] < limits["max_file_bytes"]:
            raise ValidationError("Total byte limit must cover the single-file limit.")
        if document["approval_record_ref"] is None:
            unresolved.append("APPROVAL_REFERENCE_MISSING")
        if document["request_state"] == "DRAFT":
            unresolved.append("REQUEST_IS_DRAFT")
        fingerprint = fingerprint_manifest(document)
        unsigned = {key: value for key, value in document.items() if key != "approval_record_ref"}
        digest = hashlib.sha256(rfc8785.dumps(unsigned)).hexdigest()
        if unresolved:
            return _result("DRAFT_INCOMPLETE", fingerprint=fingerprint,
                           request_digest=digest, unresolved_requirements=unresolved,
                           content_verification="NOT_CHECKED")
        if bundle_root is not None:
            _verify_bundle(document["inputs"], limits, bundle_root)
        return _result(
            "CONTRACT_VALID", fingerprint=fingerprint, request_digest=digest,
            content_verification="VERIFIED_LOCAL_REPORTS" if bundle_root is not None else "NOT_CHECKED",
            approval_record_state="DECLARED_NOT_AUTHENTICATED",
        )
    except (ValidationError, OSError, ValueError, TypeError, RecursionError):
        # No path contents, arbitrary rejected strings, or credentials in errors.
        return _result("REJECTED", ["Manifest semantic or local-file verification failed."])


def validate_report(document, manifest, bundle_root=None):
    try:
        errors = _schema_errors(document, "report")
        if errors:
            return _result("REJECTED", errors)
        manifest_result = validate_manifest(manifest)
        if manifest_result["status"] != "CONTRACT_VALID":
            raise ValidationError("Report requires a complete structurally valid manifest.")
        _check_times(document)
        for key in ("repository", "repository_id", "branch", "run_id", "commit_sha"):
            if document[key] != manifest[key]:
                raise ValidationError("Report identity does not match its manifest.")
        if document["manifest_fingerprint"] != manifest_result["fingerprint"]:
            raise ValidationError("Report fingerprint does not match its manifest.")
        inputs = {item["input_id"]: item for item in manifest["inputs"]}
        _unique([source["source_id"] for source in document["sources"]], "report source IDs")
        sources = {source["source_id"]: source for source in document["sources"]}
        if set(sources) != set(inputs):
            raise ValidationError("Every manifest input must have an explicit source state.")
        total_bytes = 0
        for key, source in sources.items():
            _check_storage_ref(source["storage_ref"])
            if source["storage_ref"] != inputs[key]["storage_ref"]:
                raise ValidationError("Report source locator disagrees with manifest.")
            if source["sha256"] is not None and source["sha256"] != inputs[key]["sha256"]:
                raise ValidationError("Report source digest disagrees with manifest.")
            if source["availability"] == "AVAILABLE":
                if source["sha256"] is None or source["size_bytes"] is None or source["checksum_basis"] == "UNKNOWN":
                    raise ValidationError("Available source requires a digest, size and checksum basis.")
                if source["size_bytes"] > manifest["parameters"]["max_file_bytes"]:
                    raise ValidationError("Source exceeds the manifest byte limit.")
                total_bytes += source["size_bytes"]
        if total_bytes > manifest["parameters"]["max_total_bytes"]:
            raise ValidationError("Report sources exceed the total byte limit.")
        _unique(document["missing_files"], "missing-file IDs")
        if set(document["missing_files"]) != {key for key, source in sources.items()
                                               if source["availability"] == "MISSING"}:
            raise ValidationError("MISSING must be distinguished from NOT_CHECKED and other states.")

        def check_refs(refs, require_available=False):
            for reference in refs:
                source = sources.get(reference["source_id"])
                if source is None or (require_available and source["availability"] != "AVAILABLE"):
                    raise ValidationError("Evidence reference has no available bound source.")

        jobs = document["jobs"]
        _unique([(job["job_id"], job["array_task_id"], job["step_id"]) for job in jobs], "job identities")
        for job in jobs:
            asserted_state = job["scheduler_state"] != "UNKNOWN"
            if asserted_state and not job["evidence_refs"]:
                raise ValidationError("A reported scheduler state needs a bound source.")
            check_refs(job["evidence_refs"], require_available=asserted_state)
            code = job["exit_code"]
            if code is not None and code["raw"] != f'{code["status"]}:{code["signal"]}':
                raise ValidationError("Raw exit code disagrees with status/signal.")
            start, end = job["started_at_utc"], job["ended_at_utc"]
            if start is not None and end is not None and datetime.fromisoformat(end) < datetime.fromisoformat(start):
                raise ValidationError("Job end precedes its start.")
        technical = document["technical_qa"]
        _unique([check["check_id"] for check in technical["checks"]], "technical check IDs")
        for check in technical["checks"]:
            _unique([metric["name"] for metric in check["metrics"]], "metric names")
            claimed_pass = check["status"] == "PASS"
            if claimed_pass and not check["evidence_refs"]:
                raise ValidationError("Technical PASS requires a bound evidence source.")
            check_refs(check["evidence_refs"], require_available=claimed_pass)
        if technical["status"] == "PASS" and (not technical["checks"] or
                any(check["status"] != "PASS" for check in technical["checks"])):
            raise ValidationError("Aggregate technical PASS requires nonempty passing checks.")
        for name in ("input_artifacts", "output_artifacts"):
            _unique([item["artifact_id"] for item in document[name]], "artifact IDs")
            for artifact in document[name]:
                _check_storage_ref(artifact["storage_ref"], report_file=False)
                check_refs(artifact["evidence_refs"])
                if artifact["sha256_observed"] is not None:
                    raise ValidationError("Phase 1 does not measure artifact bytes; preserve source hashes as reported.")
                expected, reported = artifact["sha256_expected"], artifact["sha256_reported"]
                if expected is not None and reported is not None and expected != reported:
                    if "ARTIFACT_CHECKSUM_MISMATCH" not in document["review_reasons"]:
                        raise ValidationError("A reported artifact digest mismatch needs an explicit review reason.")
        diagnostic = document["diagnostics"]
        count = diagnostic["positive_threshold_no_component_lakes"]
        moderate = diagnostic["test_id"] in {"MODERATE", "E0510000_N7620000", "MODERATE_E0510000_N7620000"}
        if moderate or (count is not None and count > 0):
            if document["scientific_review_state"] != "REVIEW_REQUIRED":
                raise ValidationError("Unresolved shoreline observations require scientific review.")
        if (moderate or (count is not None and count > 0)) and "POSITIVE_SHORE_THRESHOLD_NO_OBSERVED_RAISE" not in document["review_reasons"]:
            raise ValidationError("Component-free positive shore thresholds need their explicit review reason.")
        verified = 0
        if bundle_root is not None:
            verified = _verify_bundle(document["sources"], manifest["parameters"], bundle_root, report=True)
        verification = "NOT_CHECKED"
        if verified:
            verification = ("VERIFIED_LOCAL_REPORTS" if verified == len(sources)
                            else "VERIFIED_AVAILABLE_REPORTS")
        return _result(
            "CONTRACT_VALID", fingerprint=manifest_result["fingerprint"],
            content_verification=verification, verified_source_count=verified,
            scientific_review_state=document["scientific_review_state"],
            needs_review=document["needs_review"], review_reasons=list(document["review_reasons"]),
            evidence_authenticity="NOT_AUTHENTICATED",
        )
    except (ValidationError, OSError, ValueError, TypeError, RecursionError):
        return _result("REJECTED", ["Report semantic or local-file verification failed."])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", nargs="?", help="Local manifest or report JSON")
    parser.add_argument("--kind", choices=("manifest", "report"), default="manifest")
    parser.add_argument("--manifest", help="Manifest JSON required for report binding")
    parser.add_argument("--bundle-root", help="Optional local report bundle root; never a remote destination")
    parser.add_argument("--schemas-only", action="store_true")
    args = parser.parse_args(argv)
    if args.schemas_only and any((args.file, args.manifest, args.bundle_root)):
        parser.error("--schemas-only cannot read request or bundle files")
    if not args.schemas_only and (args.file is None or (args.kind == "report" and args.manifest is None)):
        parser.error("provide a document and, for reports, --manifest")
    try:
        if args.schemas_only:
            _schema("manifest")
            _schema("report")
            result = _result("SCHEMAS_VALID")
        else:
            document = load_json_bytes(_read_bounded(args.file, MAX_DOCUMENT_BYTES))
            if args.kind == "manifest":
                result = validate_manifest(document, bundle_root=args.bundle_root)
            else:
                manifest = load_json_bytes(_read_bounded(args.manifest, MAX_DOCUMENT_BYTES))
                result = validate_report(document, manifest, bundle_root=args.bundle_root)
    except (ValidationError, OSError, ValueError, RecursionError):
        result = _result("REJECTED", ["Document or schema could not be safely read/validated."])
    print(json.dumps(result, ensure_ascii=True, allow_nan=False, sort_keys=True))
    return {"CONTRACT_VALID": 0, "SCHEMAS_VALID": 0, "DRAFT_INCOMPLETE": 2}.get(result["status"], 1)


if __name__ == "__main__":
    sys.exit(main())
