"""Fail-closed, in-memory simulation for CSC report inventory integration.

This module can ONLY simulate the ten fixed candidate paths. It has no
networking, filesystem, subprocess, credential handling or file transfer.
It cannot produce an observation claiming to come from the real CSC.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from types import MappingProxyType

from phase2a import contracts as c


PILOT_PATHS = frozenset({
    "d8_value_qa_20261014/qa.jobid",
    "d8_value_qa_20261014/results/qa.csv",
    "moderate_02d4_audit_20261014/job_id.txt",
    "moderate_02d4_audit_20261014/summary.csv",
    "moderate_02d4_audit_20261014/lake_audit.csv",
    "moderate_resume_20261014_v2/resume.jobid",
    "moderate_resume_20261014_v2/validated_d8_report.csv",
    "moderate_resume_20261014_v2/run/02_baseline/02D_lake_depression_component_summary.csv",
    "moderate_resume_20261014_v2/run/02_baseline/02D_spill_group_diagnostic.csv",
    "moderate_resume_20261014_v2/run/02_baseline/02D8_final_spill_evidence.csv",
})


@dataclass(frozen=True)
class SyntheticEntry:
    """Declared FAKE result, never a real CSC observation."""

    status: str
    size_bytes: int | None = None


class SyntheticMetadataProvider:
    """Exact-type simulation provider; no filesystem or network method exists."""

    def __init__(self, entries):
        if type(entries) is not dict or set(entries) != PILOT_PATHS:
            raise c.Rejected("Synthetic fixture does not match exact pilot paths.")
        for path, entry in entries.items():
            c.safe_path(path)
            if type(entry) is not SyntheticEntry:
                raise c.Rejected("Synthetic fixture type rejected.")
            if entry.status not in {"AVAILABLE", "MISSING", "UNREADABLE"}:
                raise c.Rejected("Synthetic fixture state rejected.")
            if entry.status == "AVAILABLE":
                if type(entry.size_bytes) is not int or not (0 <= entry.size_bytes <= c.MAX_FILE):
                    raise c.Rejected("Synthetic size exceeds allowed range.")
            elif entry.size_bytes is not None:
                raise c.Rejected("Unavailable synthetic entry cannot claim a size.")
        self._entries = MappingProxyType(dict(entries))

    def observe(self, path):
        # Only exact prevalidated fixture paths are accepted.
        return self._entries[path]


def simulate_inventory(candidates, inventory, allowlist, request, trust, provider, *, now=None):
    """Consume a synthetic approval and produce a clearly labeled fake inventory.

    2A's TrustStore and its one-shot set are still IN-MEMORY ONLY; never use
    this function as a live Roihu collector or an approval service.
    """
    if type(provider) is not SyntheticMetadataProvider:
        raise c.Rejected("Real or user-provided backends are not supported.")
    if type(trust) is not c.TrustStore:
        raise c.Rejected("Synthetic trust store required.")
    # check_request validates all 4 contracts, pinned exact allowlist,
    # expiration, operation, known job IDs, size caps and context hashes.
    c.check_request(candidates, inventory, allowlist, request, trust, now=now)
    if request["operation"] != "INVENTORY_LOCAL_REPORTS":
        raise c.Rejected("Only synthetic metadata inventory is supported.")
    paths = {entry["relative_path"] for entry in candidates["files"]}
    if paths != PILOT_PATHS or {entry["relative_path"] for entry in allowlist["files"]} != PILOT_PATHS:
        raise c.Rejected("Exactly ten pilot paths must be bound.")
    if any(item["expected_size_bytes"] is not None or item["sha256_expected"] is not None
           for item in allowlist["files"]):
        raise c.Rejected("Synthetic metadata cannot claim verified file bytes.")

    # Once attempted, synthetic authorization is consumed even on a failure.
    trust.used.add(request["request_id"])
    clock = now if now is not None else datetime.now(timezone.utc)
    if not isinstance(clock, datetime) or clock.tzinfo is None:
        raise c.Rejected("Timezone-aware UTC time required.")
    timestamp = clock.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    by_path = {item["relative_path"]: item for item in allowlist["files"]}
    observed = {}
    total = 0
    for path in sorted(PILOT_PATHS):
        entry = provider.observe(path)
        row = {"relative_path": path, "status": entry.status,
               "size_bytes": entry.size_bytes if entry.status == "AVAILABLE" else None,
               "sha256_measured": None, "observed_at_utc": timestamp,
               "evidence_ref": "SYNTHETIC_FIXTURE_ONLY_NOT_CSC"}
        if entry.status == "AVAILABLE":
            if entry.size_bytes > by_path[path]["max_bytes"]:
                raise c.Rejected("Synthetic file exceeds approved cap.")
            total += entry.size_bytes
        observed[path] = row
    if total > allowlist["max_total_bytes"] or total > c.MAX_TOTAL:
        raise c.Rejected("Synthetic total exceeds approved cap.")
    result = c.unchecked_inventory(candidates)
    result["files"] = [observed[f["relative_path"]] for f in result["files"]]
    c.validate(result, "inventory")
    return {"mode": "SYNTHETIC_ONLY", "csc_observations": False,
            "authorization": "NO_LIVE_CSC_AUTHORIZATION",
            "transfer": "FORBIDDEN", "files": len(PILOT_PATHS),
            "total_simulated_bytes": total, "inventory": result}
