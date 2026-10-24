"""S2I-C mock only: supplied tiny bytes / ordered events, never a witness.

No source reader, filesystem, process, credential, signature or real-run API.
This deliberately does not import S2E/S2F/v2 from divergent draft lineages.
"""
from dataclasses import dataclass, field
from hashlib import sha256
import json
import re
from types import MappingProxyType
from uuid import UUID

SCHEMA = "mm.s2ic.synthetic-source-event-mock.v1"
ROLES = ("WATER_CLASS", "LAKE_ID", "POINTER", "CANDIDATE_EDGES")
STAGES = ("MOCK_START", "MOCK_FREEZE", "MOCK_CONSUME", "MOCK_CLOSE_OUTPUTS", "MOCK_FINISH")
OBSERVED_STAGES = frozenset(STAGES[1:4])
MAX_BYTES = 16384
MAX_SOURCE_BYTES = 256
MAX_TREE_VALUES = 3000
LOCKS = MappingProxyType({"NATIONAL": "LOCKED", "MODERATE": "REVIEW_REQUIRED",
         "hydrological_validation": "NOT_ASSESSED", "channel_interpretation": "NOT_ASSESSED",
         "routing_authorized": False, "outlet_selection": "UNASSIGNED",
         "HISTORIC_02F_EFFECTIVE_D8": "NOT_ASSESSED"})


@dataclass(frozen=True)
class SourceVersion:
    role: str
    source_id: str
    version_id: str
    generation: int
    raw: bytes


@dataclass(frozen=True)
class MockReference:
    """Caller-supplied synthetic expectations, NOT an independent trust root."""
    run_id: str
    attempt_id: str
    sources: tuple
    event_ids: tuple


@dataclass(frozen=True)
class Receipt:
    disposition: str
    reason: str
    canonical_record: bytes = b""
    content_sha256: str = ""
    observed_source_sha256: tuple = ()
    mock_transcript_status: str = "NOT_ASSESSED"
    schema: str = field(default=SCHEMA, init=False)
    evidence_kind: str = field(default="SYNTHETIC_MOCK", init=False)
    checksum_status: str = field(default="SUPPLIED_SYNTHETIC_BYTES_ONLY", init=False)
    producer_lineage_status: str = field(default="NOT_ASSESSED", init=False)
    source_authentication: str = field(default="NOT_ASSESSED", init=False)
    independent_witness: str = field(default="NOT_IMPLEMENTED", init=False)
    runtime_completion: str = field(default="NOT_ASSESSED", init=False)
    historical_02f_status: str = field(default="STOP", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    HISTORIC_02F_EFFECTIVE_D8: str = field(default="NOT_ASSESSED", init=False)


class _Stop(ValueError):
    pass


def _need(ok, code):
    if not ok:
        raise _Stop(code)


def _walk(x, depth=0, work=None):
    if work is None:
        work = [0]
    work[0] += 1
    _need(work[0] <= MAX_TREE_VALUES and depth <= 8, "TREE_BUDGET")
    if type(x) is dict:
        _need(len(x) <= 32, "TREE_BUDGET")
        for k, v in x.items():
            _need(type(k) is str, "STRING_KEYS_REQUIRED")
            _walk(k, depth + 1, work)
            _walk(v, depth + 1, work)
    elif type(x) is list:
        _need(len(x) <= 32, "TREE_BUDGET")
        for v in x:
            _walk(v, depth + 1, work)
    elif type(x) is str:
        _need(len(x) <= 128 and all(32 <= ord(c) <= 126 for c in x), "STRING_BUDGET_OR_ENCODING")
    elif type(x) is bytes:
        _need(len(x) <= MAX_SOURCE_BYTES, "SOURCE_BYTE_BUDGET")
    elif type(x) is int:
        _need(abs(x) <= 2147483647, "INTEGER_BUDGET")
    else:
        _need(x is None or type(x) is bool, "EXACT_BUILTIN_TYPES_REQUIRED")


def _keys(x, keys):
    _need(type(x) is dict and set(x) == set(keys), "MISSING_OR_UNKNOWN_FIELDS")


def _same(actual, expected, reason):
    _need(type(actual) is type(expected) and actual == expected, reason)


def _label(x):
    _need(type(x) is str and re.fullmatch(r"[a-z][a-z0-9_-]{0,47}", x) is not None, "INVALID_LOCAL_ID")
    _need(x not in {"latest", "current", "mutable", "head"}, "MUTABLE_ALIAS")


def _uuid(x):
    _need(type(x) is str and len(x) == 36, "INVALID_UUID4")
    try:
        value = UUID(x)
    except ValueError:
        raise _Stop("INVALID_UUID4") from None
    _need(str(value) == x and value.version == 4, "INVALID_UUID4")


def _normalize(x):
    if type(x) is bytes:
        return {"$mock_octets": x.hex()}
    if type(x) is list:
        return [_normalize(v) for v in x]
    if type(x) is dict:
        return {k: _normalize(v) for k, v in x.items()}
    return x


def _canonical(x):
    data = json.dumps(_normalize(x), sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    _need(len(data) <= MAX_BYTES, "CANONICAL_BYTE_BUDGET")
    return data


def _reference(ref):
    _need(type(ref) is MockReference, "MOCK_REFERENCE_REQUIRED")
    _uuid(ref.run_id)
    _uuid(ref.attempt_id)
    _need(ref.run_id != ref.attempt_id, "RUN_ATTEMPT_COLLISION")
    _need(type(ref.sources) is tuple and len(ref.sources) == 4, "REFERENCE_SOURCE_SCOPE")
    ids = set()
    versions = set()
    for role, source in zip(ROLES, ref.sources):
        _need(type(source) is SourceVersion, "REFERENCE_SOURCE_SCOPE")
        _same(source.role, role, "REFERENCE_ROLE_ORDER")
        _label(source.source_id)
        _label(source.version_id)
        _need(source.source_id not in ids and source.version_id not in versions, "REFERENCE_ALIAS")
        _need(type(source.generation) is int and 1 <= source.generation <= 1000, "GENERATION_SCOPE")
        _need(type(source.raw) is bytes and 1 <= len(source.raw) <= MAX_SOURCE_BYTES, "SOURCE_BYTE_BUDGET")
        ids.add(source.source_id)
        versions.add(source.version_id)
    _need(not ids.intersection(versions), "REFERENCE_ALIAS")
    _need(type(ref.event_ids) is tuple and len(ref.event_ids) == 5, "REFERENCE_EVENT_SCOPE")
    for event_id in ref.event_ids:
        _label(event_id)
    _need(len(set(ref.event_ids)) == 5 and not set(ref.event_ids).intersection(ids | versions), "REFERENCE_ALIAS")


def _observation(value, source):
    _keys(value, ("role", "source_id", "version_id", "generation", "raw"))
    for name in ("role", "source_id", "version_id", "generation"):
        _same(value[name], getattr(source, name), "SOURCE_VERSION_SUBSTITUTION")
    _same(value["raw"], source.raw, "OBSERVED_BYTES_SUBSTITUTION")


def review_mock(record, *, reference, used_ids=()):
    """Compare bounded supplied mock bytes/events to separate synthetic expectations.

    A positive receipt ALWAYS remains RECORDED_UNVERIFIED. There is no actual
    source access or trust enrollment, and no COMPLETE or VERIFIED decision.
    """
    try:
        _reference(reference)
        _need(type(used_ids) is tuple and len(used_ids) <= 128, "PRIOR_ID_BUDGET")
        for identity in used_ids:
            _uuid(identity)
        _need(len(set(used_ids)) == len(used_ids), "AMBIGUOUS_PRIOR_IDS")
        _need(reference.run_id not in used_ids and reference.attempt_id not in used_ids, "REUSED_ID")
        _walk(record)
        _keys(record, ("schema", "evidence_kind", "run_id", "attempt_id", "declared_status", "witness",
                       "sources", "events", "event_count", "transcript_sha256", "locks"))
        _same(record["schema"], SCHEMA, "UNKNOWN_SCHEMA")
        _same(record["evidence_kind"], "SYNTHETIC_MOCK", "REAL_RUN_FORBIDDEN")
        _same(record["run_id"], reference.run_id, "RUN_SCOPE")
        _same(record["attempt_id"], reference.attempt_id, "ATTEMPT_SCOPE")
        _same(record["declared_status"], "SIMULATED_COMPLETE", "FALSE_COMPLETION_CLAIM")
        _same(record["witness"], None, "WITNESS_NOT_IMPLEMENTED")
        _keys(record["locks"], LOCKS)
        for key, value in LOCKS.items():
            _same(record["locks"][key], value, "FORBIDDEN_SCIENTIFIC_CLAIM")
        _need(type(record["sources"]) is list and len(record["sources"]) == 4, "SOURCE_SCOPE")
        for claim, source in zip(record["sources"], reference.sources):
            _keys(claim, ("role", "source_id", "version_id", "generation", "declared_sha256",
                          "declared_size", "mutable_alias", "immutability"))
            for name in ("role", "source_id", "version_id", "generation"):
                _same(claim[name], getattr(source, name), "DECLARED_SOURCE_SUBSTITUTION")
            _same(claim["mutable_alias"], False, "MUTABLE_ALIAS")
            _same(claim["immutability"], "SIMULATED_ONLY", "FALSE_STORAGE_GUARANTEE")
            _same(claim["declared_sha256"], sha256(source.raw).hexdigest(), "DECLARED_DIGEST_MISMATCH")
            _same(claim["declared_size"], len(source.raw), "DECLARED_SIZE_MISMATCH")
        events = record["events"]
        _need(type(events) is list and len(events) == 5, "INCOMPLETE_EVENT_TRANSCRIPT")
        _same(record["event_count"], 5, "EVENT_COUNT")
        for index, (event, stage) in enumerate(zip(events, STAGES)):
            _keys(event, ("event_id", "sequence", "stage", "run_id", "attempt_id", "tick", "observed_sources"))
            _same(event["event_id"], reference.event_ids[index], "EVENT_ID_COLLISION_OR_SUBSTITUTION")
            _same(event["sequence"], index + 1, "EVENT_SEQUENCE")
            _same(event["stage"], stage, "STAGE_ORDER")
            _same(event["tick"], index, "MOCK_TICK_SEQUENCE")
            _same(event["run_id"], reference.run_id, "RUN_SCOPE")
            _same(event["attempt_id"], reference.attempt_id, "ATTEMPT_SCOPE")
            observed = event["observed_sources"]
            _need(type(observed) is list and len(observed) == (4 if stage in OBSERVED_STAGES else 0),
                  "SOURCE_OBSERVATION_MISSING_OR_EXTRA")
            if observed:
                for value, source in zip(observed, reference.sources):
                    _observation(value, source)
        _same(record["transcript_sha256"], sha256(_canonical(events)).hexdigest(), "CHANGED_TRANSCRIPT")
        canonical = _canonical(record)
        return Receipt("RECORDED_UNVERIFIED", "NONE", canonical, sha256(canonical).hexdigest(),
                       tuple((s.role, sha256(s.raw).hexdigest()) for s in reference.sources), "SIMULATED_CLOSED")
    except _Stop as error:
        return Receipt("STOP", str(error))
