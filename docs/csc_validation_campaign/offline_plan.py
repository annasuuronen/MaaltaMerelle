#!/usr/bin/env python3
"""Offline, fail-closed four-area CSC test plan. No job or network operations."""
import argparse
import csv
import hashlib
import json
import os
import re
from pathlib import Path

BASE_SHA = "7050b582edab3195669529f366b4f5a2915488c6"
AREAS = {
    "NATURAL": "E0560000_N7690000",
    "LOW": "E200000_N6900000",
    "MODERATE": "E0510000_N7620000",
    "HIGH": "TEST_SULKU_11",
}
FIELDS = (
    "test_id", "area", "area_id", "question", "source_ref", "source_sha",
    "evidence_class", "test_kind", "input_identity", "input_check",
    "read_value_limit", "resource_estimate", "dependencies", "responsible",
    "success_criterion", "stop_criterion", "approval_status", "technical_status",
    "scientific_status", "blocking_gate",
)
EVIDENCE = {
    "NOT_ASSESSED", "REPORTED_LOCAL_PASS", "DOCUMENTED_CSC_OBSERVATION",
    "REPORTED_CSC_FAILURE", "CI_FIXTURE_ONLY",
}
GATES = {
    "USER_APPROVAL_REQUIRED", "CSC_LOGIN_BLOCKED", "INPUT_IDENTITY_REQUIRED",
    "SCIENTIFIC_REVIEW_REQUIRED", "EXISTING_EVIDENCE_ONLY",
}
SHA40 = re.compile(r"[0-9a-f]{40}\Z")
ID = re.compile(r"[A-Z0-9][A-Z0-9_-]{2,79}\Z")


def load_matrix(path):
    raw = Path(path).read_bytes()
    with Path(path).open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError("unexpected CSV schema")
        rows = list(reader)
    if not rows:
        raise ValueError("empty campaign")
    ids = set()
    seen_areas = set()
    for row in rows:
        test_id, area = row["test_id"], row["area"]
        if any(value is None or not value.strip() for value in row.values()):
            raise ValueError(f"empty required field: {test_id}")
        if not ID.fullmatch(test_id) or test_id in ids:
            raise ValueError(f"duplicate or invalid test ID: {test_id}")
        ids.add(test_id)
        if area not in AREAS or row["area_id"] != AREAS[area]:
            raise ValueError(f"invalid test area or ID: {test_id}")
        seen_areas.add(area)
        if not SHA40.fullmatch(row["source_sha"]):
            raise ValueError(f"un-pinned source commit: {test_id}")
        if row["evidence_class"] not in EVIDENCE:
            raise ValueError(f"unknown evidence class: {test_id}")
        if row["test_kind"] not in {"EXISTING_EVIDENCE", "PROPOSED"}:
            raise ValueError(f"invalid test kind: {test_id}")
        if row["approval_status"] != "USER_APPROVAL_REQUIRED":
            raise ValueError(f"approval bypass attempted: {test_id}")
        if row["technical_status"] != "NOT_RUN" or row["scientific_status"] != "NOT_ASSESSED":
            raise ValueError(f"unverified result promoted to accepted status: {test_id}")
        if row["blocking_gate"] not in GATES:
            raise ValueError(f"invalid blocking gate: {test_id}")
        if row["resource_estimate"] != "NOT_ESTIMATED":
            raise ValueError(f"unsupported resource estimate: {test_id}")
        if row["read_value_limit"] != ("56" if test_id == "LOW_BOUNDARY_14" else "NOT_ESTIMATED"):
            raise ValueError(f"unapproved raster read scope: {test_id}")
        if test_id == "LOW_BOUNDARY_14" and area != "LOW":
            raise ValueError("locked receiver test mapped to wrong area")
        if test_id.startswith("HIGH_") and row["area_id"] != "TEST_SULKU_11":
            raise ValueError("HIGH must identify TEST_SULKU_11")
        if area == "HIGH" and "DEM_UNVERIFIED" not in row["input_identity"]:
            raise ValueError("HIGH input DEM must remain unverified")
    if seen_areas != set(AREAS):
        raise ValueError(f"expected four areas, got {sorted(seen_areas)}")
    return raw, sorted(rows, key=lambda row: row["test_id"])


def build_plan(matrix_path):
    raw, rows = load_matrix(matrix_path)
    matrix_sha = hashlib.sha256(raw).hexdigest()
    plan = {
        "schema_version": 1,
        "kind": "OFFLINE_DRY_RUN_ONLY",
        "repository": "annasuuronen/MaaltaMerelle",
        "baseline_commit": BASE_SHA,
        "input_identity_verified": False,
        "csc_connection_verified": False,
        "resource_allocation_verified": False,
        "user_approval_granted": False,
        "execution_enabled": False,
        "hydrological_validation": "NOT_ASSESSED",
        "channel_interpretation": "NOT_ASSESSED",
        "MODERATE": "REVIEW_REQUIRED",
        "NATIONAL": "LOCKED",
        "matrix_sha256": matrix_sha,
        "areas": AREAS,
        "tests": [dict(row, dry_run_id=hashlib.sha256(
            (matrix_sha + ":" + row["test_id"]).encode("ascii")
        ).hexdigest()[:16], execution_state="NOT_RUN") for row in rows],
    }
    data = (json.dumps(plan, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")
    return data


def write_once(path, data):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "wb") as target:
        target.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("validate", "plan"))
    parser.add_argument("--matrix", type=Path, default=Path(__file__).with_name("test_matrix.csv"))
    parser.add_argument("--out", type=Path, help="pre-existing empty output directory for plan")
    args = parser.parse_args()
    try:
        data = build_plan(args.matrix)
        if args.action == "validate":
            if args.out is not None:
                raise ValueError("--out is only for plan")
            print("VALID_OFFLINE_MATRIX; NO CSC EXECUTION")
            return
        if args.out is None or not args.out.is_dir():
            raise ValueError("plan requires an existing output directory")
        plan_path, hash_path = args.out / "plan.json", args.out / "plan.sha256"
        if plan_path.exists() or hash_path.exists():
            raise FileExistsError("plan artifacts already exist; overwrite forbidden")
        digest = hashlib.sha256(data).hexdigest()
        write_once(plan_path, data)
        write_once(hash_path, (digest + "  plan.json\n").encode("ascii"))
        print("OFFLINE_ONLY; plan digest:", digest)
    except (ValueError, OSError, UnicodeError) as exc:
        parser.exit(2, f"BLOCKED: {exc}\n")


if __name__ == "__main__":
    main()
