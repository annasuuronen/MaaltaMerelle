"""S2E: bounded synthetic record validation, never source authentication.

Pure stdlib; no files, processes, network, signatures, raster values or hooks.
Canonical bytes identify a record locally, not a producer or a historical run.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256
import json
import re
from uuid import UUID

SCHEMA = "maaltamerelle.forward-provenance.v1"
MAX_BYTES = 65536
MAX_DEPTH = 10
MAX_VALUES = 4096
MAX_STRING = 512
MAX_ARTIFACTS = 32
MAX_EVENTS = 8
RASTERS = {"LAND_WATER", "POINTER", "WATER_CLASS", "LAKE_ID"}
F_OUTPUTS = {"02F_ROUTES", "02F_EDGES", "02F_SUMMARY", "02F_QA"}
C_OUTPUTS = {"02C_ZERO_CELLS", "02C_WATER_NEIGHBORS"}
ROLES = RASTERS | F_OUTPUTS | C_OUTPUTS | {"CANDIDATE_EDGES"}
STATES = {"COMPLETE", "INCOMPLETE", "STOP", "NOT_RUN"}
LOCKS = {"NATIONAL": "LOCKED", "MODERATE": "REVIEW_REQUIRED",
         "hydrological_validation": "NOT_ASSESSED", "channel_interpretation": "NOT_ASSESSED",
         "routing_authorized": False, "outlet_selection": "UNASSIGNED",
         "producer_lineage_status": "NOT_ASSESSED", "source_authentication": "NOT_ASSESSED"}


@dataclass(frozen=True, order=True)
class Reason:
    code: str
    path: str


@dataclass(frozen=True)
class Record:
    schema_version: str
    run_id: str
    attempt_id: str
    declared_status: str
    artifact_ids: tuple[str, ...]
    event_ids: tuple[str, ...]
    canonical_json: bytes
    content_sha256: str


@dataclass(frozen=True)
class ValidationResult:
    schema_status: str
    disposition: str
    declared_status: str | None = None
    completeness_status: str = "NOT_ASSESSED"
    reasons: tuple[Reason, ...] = ()
    record: Record | None = None
    checksum_status: str = "NOT_ASSESSED"
    producer_lineage_status: str = field(default="NOT_ASSESSED", init=False)
    source_authentication: str = field(default="NOT_ASSESSED", init=False)
    historical_02f_status: str = field(default="STOP", init=False)
    RUNTIME_INPUT_LINEAGE: str = field(default="NOT_ASSESSED", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)


class _Invalid(Exception):
    def __init__(self, code: str, path: str):
        self.reason = Reason(code, path)


def _need(ok: bool, code: str, path: str) -> None:
    if not ok:
        raise _Invalid(code, path)


def _keys(x: object, keys: set[str], path: str) -> None:
    _need(type(x) is dict, "OBJECT_REQUIRED", path)
    _need(set(x) == keys, "MISSING_OR_UNKNOWN_FIELDS", path)


def _const(x: object, expected: object, path: str, code: str = "INVALID_CONSTANT") -> None:
    _need(type(x) is type(expected) and x == expected, code, path)


def _enum(x: object, choices: set[str], path: str) -> None:
    _need(type(x) is str and x in choices, "UNSUPPORTED_ENUM", path)


def _int(x: object, path: str, low: int = 0, high: int = 2**53 - 1) -> None:
    _need(type(x) is int and low <= x <= high, "EXACT_INTEGER_REQUIRED", path)


def _id(x: object, path: str) -> None:
    _need(type(x) is str and re.fullmatch(r"[a-z][a-z0-9_-]{0,47}", x) is not None,
          "INVALID_ID", path)


def _uuid(x: object, path: str) -> None:
    _need(type(x) is str and len(x) == 36, "INVALID_UUID4", path)
    try:
        _need(str(UUID(x)) == x and UUID(x).version == 4,
              "INVALID_UUID4", path)
    except (ValueError, AttributeError):
        raise _Invalid("INVALID_UUID4", path) from None


def _digest(x: object, path: str, length: int = 64) -> None:
    _need(type(x) is str and re.fullmatch(r"[0-9a-f]{" + str(length) + r"}", x) is not None
          and x != "0" * length, "INVALID_DIGEST", path)


def _list(x: object, maximum: int, path: str) -> None:
    _need(type(x) is list and len(x) <= maximum, "COLLECTION_LIMIT_OR_TYPE", path)


def _unique_ids(items: list, path: str) -> None:
    for x in items:
        _id(x, path)
    _need(len(set(items)) == len(items), "DUPLICATE_ID", path)


def _walk(x: object, depth: int = 0, count: list[int] | None = None) -> None:
    """Bound in-memory inputs before serialization; reject all JSON floats."""
    if count is None:
        count = [0]
    count[0] += 1
    _need(count[0] <= MAX_VALUES and depth <= MAX_DEPTH, "RESOURCE_LIMIT", "json")
    if type(x) is dict:
        _need(len(x) <= 32, "RESOURCE_LIMIT", "json.object")
        for key, value in x.items():
            _need(type(key) is str, "STRING_KEY_REQUIRED", "json.key")
            _walk(key, depth + 1, count)
            _walk(value, depth + 1, count)
    elif type(x) is list:
        _need(len(x) <= 128, "RESOURCE_LIMIT", "json.array")
        for value in x:
            _walk(value, depth + 1, count)
    elif type(x) is str:
        _need(len(x) <= MAX_STRING and all(32 <= ord(c) <= 126 for c in x),
              "NONCANONICAL_TEXT", "json.string")
    elif type(x) is int:
        _need(abs(x) <= 2**53 - 1, "INTEGER_RANGE", "json.number")
    else:
        _need(x is None or type(x) is bool, "UNSUPPORTED_JSON_VALUE", "json.value")


def _pairs(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        _need(key not in result, "DUPLICATE_JSON_KEY", "json.object")
        result[key] = value
    return result


def _nonfinite(_: str) -> None:
    raise _Invalid("NONFINITE_JSON_NUMBER", "json.number")


def _decode(raw: str | bytes) -> object:
    _need(type(raw) in (str, bytes), "JSON_TEXT_REQUIRED", "json")
    _need(len(raw) <= MAX_BYTES, "RESOURCE_LIMIT", "json.bytes")
    if type(raw) is bytes:
        try:
            raw = raw.decode("utf-8", errors="strict")
        except UnicodeError:
            raise _Invalid("INVALID_UTF8", "json") from None
    _need(len(raw.encode("utf-8")) <= MAX_BYTES, "RESOURCE_LIMIT", "json.bytes")
    # Scan depth before invoking the recursive stdlib JSON parser.
    depth = 0
    quoted = escaped = False
    for c in raw:
        if quoted:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c in "[{":
            depth += 1
            _need(depth <= MAX_DEPTH, "RESOURCE_LIMIT", "json.depth")
        elif c in "]}":
            depth -= 1
    try:
        return json.loads(raw, object_pairs_hook=_pairs, parse_constant=_nonfinite)
    except (ValueError, RecursionError):
        raise _Invalid("INVALID_JSON", "json") from None


def _measurement(x: dict, path: str) -> None:
    _keys(x, {"state", "sha256", "size_bytes"}, path)
    _enum(x["state"], {"NOT_RUN", "NO_FILE_REPRESENTATION", "DECLARED", "MEASURED_SIMULATED"}, path)
    if x["state"] in {"NOT_RUN", "NO_FILE_REPRESENTATION"}:
        _need(x["sha256"] is None and x["size_bytes"] is None, "UNKNOWN_IS_NOT_ZERO", path)
    else:
        _digest(x["sha256"], path + ".sha256")
        _int(x["size_bytes"], path + ".size_bytes", 1, 2**40)


def _present(x: dict) -> bool:
    return x["state"] in {"DECLARED", "MEASURED_SIMULATED"}


def _grid(g: dict) -> None:
    _keys(g, {"grid_id", "epsg", "rows", "cols", "geotransform", "cell_index_base",
              "row_col_index_base", "pointer_scheme", "esri_pntr"}, "grid")
    _id(g["grid_id"], "grid.grid_id")
    _const(g["epsg"], 3067, "grid.epsg")
    for key in ("rows", "cols"):
        _int(g[key], "grid." + key, 1, 6000)
    _list(g["geotransform"], 6, "grid.geotransform")
    _need(len(g["geotransform"]) == 6, "INVALID_GRID", "grid.geotransform")
    for v in g["geotransform"]:
        _int(v, "grid.geotransform", -100_000_000, 100_000_000)
    a = g["geotransform"]
    _need(a[1:3] == [2, 0] and a[4:] == [0, -2], "INVALID_GRID", "grid.geotransform")
    _const(g["cell_index_base"], 1, "grid.cell_index_base")
    _const(g["row_col_index_base"], 0, "grid.row_col_index_base")
    _const(g["pointer_scheme"], "WHITEBOX_D8", "grid.pointer_scheme", "POINTER_CONVENTION")
    _const(g["esri_pntr"], False, "grid.esri_pntr", "POINTER_CONVENTION")


def _raster(x: dict, role: str, grid_id: str) -> None:
    _keys(x, {"grid_id", "dtype", "nodata", "logical_encoding"}, "artifact.raster")
    _const(x["grid_id"], grid_id, "artifact.raster.grid_id", "GRID_SCOPE_MISMATCH")
    _const(x["logical_encoding"], "synthetic.logical.v1", "artifact.raster.logical_encoding")
    ranges = {"Float64": (-2**53 + 1, 2**53 - 1), "Float32": (-2**24, 2**24),
              "Int32": (-2**31, 2**31 - 1), "UInt16": (0, 65535), "Byte": (0, 255)}
    _enum(x["dtype"], set(ranges), "artifact.raster.dtype")
    if role == "POINTER":
        _const(x["dtype"], "Float64", "artifact.raster.dtype", "POINTER_DTYPE")
    nd = x["nodata"]
    _keys(nd, {"kind", "value"}, "artifact.raster.nodata")
    _enum(nd["kind"], {"FINITE", "R_NA", "NAN", "NONE"}, "artifact.raster.nodata.kind")
    if nd["kind"] == "FINITE":
        _int(nd["value"], "artifact.raster.nodata.value", *ranges[x["dtype"]])
        _need(not (role == "POINTER" and nd["value"] == 0) and
              not (role == "WATER_CLASS" and nd["value"] in {1, 2, 3}) and
              not (role == "LAKE_ID" and nd["value"] > 0), "INVALID_NODATA", "artifact.raster.nodata")
    else:
        _need(nd["value"] is None, "INVALID_NODATA", "artifact.raster.nodata.value")
        _need(nd["kind"] not in {"R_NA", "NAN"} or x["dtype"].startswith("Float"),
              "INVALID_NODATA", "artifact.raster.nodata.dtype")


def _artifact(a: dict, root: dict) -> None:
    _keys(a, {"artifact_id", "run_id", "attempt_id", "role", "source_type", "production",
              "producer_event_id", "predecessor", "uri", "file", "logical", "raster"}, "artifact")
    _id(a["artifact_id"], "artifact.artifact_id")
    for key in ("run_id", "attempt_id"):
        _const(a[key], root[key], "artifact." + key, "RUN_SCOPE_MISMATCH")
    _enum(a["role"], ROLES, "artifact.role")
    _enum(a["source_type"], {"SOURCE_DATASET", "DERIVED_FILE", "IN_MEMORY", "EXISTING_UNVERIFIED"}, "artifact.source_type")
    _enum(a["production"], {"SOURCE", "PRODUCED", "REUSED"}, "artifact.production")
    _measurement(a["file"], "artifact.file")
    _measurement(a["logical"], "artifact.logical")
    _need(a["logical"]["state"] != "NO_FILE_REPRESENTATION", "INVALID_MEASUREMENT_ROLE", "artifact.logical")
    if a["source_type"] == "IN_MEMORY":
        _need(a["uri"] is None and a["file"]["state"] == "NO_FILE_REPRESENTATION",
              "MEMORY_IS_NOT_FILE", "artifact")
    else:
        uri = a["uri"]
        _need(type(uri) is str and uri.startswith("synthetic:/") and len(uri) <= 256,
              "SYNTHETIC_URI_REQUIRED", "artifact.uri")
        parts = uri[len("synthetic:/"):].split("/")
        _need(all(p not in {"", ".", ".."} and re.fullmatch(r"[a-zA-Z0-9_-][a-zA-Z0-9_.-]{0,63}", p)
                  for p in parts), "UNSAFE_URI", "artifact.uri")
        _need(a["file"]["state"] != "NO_FILE_REPRESENTATION", "INVALID_MEASUREMENT_ROLE", "artifact.file")
    if a["role"] in RASTERS:
        _raster(a["raster"], a["role"], root["grid"]["grid_id"])
    else:
        _need(a["raster"] is None and a["source_type"] != "IN_MEMORY" and
              a["logical"]["state"] == "NOT_RUN", "INVALID_ARTIFACT_ROLE", "artifact")
    if a["production"] == "PRODUCED":
        _need(a["source_type"] in {"DERIVED_FILE", "IN_MEMORY"} and a["predecessor"] is None,
              "PRODUCTION_ROLE_MISMATCH", "artifact")
        _need(a["role"] in {"POINTER"} | F_OUTPUTS | C_OUTPUTS,
              "PRODUCTION_ROLE_MISMATCH", "artifact.role")
        _id(a["producer_event_id"], "artifact.producer_event_id")
    else:
        _need(a["producer_event_id"] is None, "PRODUCTION_ROLE_MISMATCH", "artifact.producer_event_id")
        if a["production"] == "SOURCE":
            _need(a["source_type"] in {"SOURCE_DATASET", "IN_MEMORY"} and a["predecessor"] is None,
                  "PRODUCTION_ROLE_MISMATCH", "artifact")
            _need(a["role"] in {"LAND_WATER", "WATER_CLASS", "LAKE_ID", "CANDIDATE_EDGES"},
                  "PRODUCTION_ROLE_MISMATCH", "artifact.role")
        else:
            _const(a["source_type"], "EXISTING_UNVERIFIED", "artifact.source_type", "PRODUCTION_ROLE_MISMATCH")
            _const(a["role"], "POINTER", "artifact.role", "PRODUCTION_ROLE_MISMATCH")
            p = a["predecessor"]
            if p is not None:
                _keys(p, {"run_id", "attempt_id", "event_id", "manifest_sha256"}, "artifact.predecessor")
                _uuid(p["run_id"], "predecessor.run_id"); _uuid(p["attempt_id"], "predecessor.attempt_id")
                _need(len({p["run_id"], p["attempt_id"], root["run_id"], root["attempt_id"]}) == 4,
                      "RUN_SCOPE_MISMATCH", "artifact.predecessor")
                _id(p["event_id"], "predecessor.event_id")
                _digest(p["manifest_sha256"], "predecessor.manifest_sha256")


def _event(e: dict, root: dict, position: int) -> None:
    _keys(e, {"event_id", "run_id", "attempt_id", "sequence", "role", "status", "started_tick",
              "ended_tick", "inputs", "outputs", "depends_on", "bindings"}, "event")
    _id(e["event_id"], "event.event_id")
    for key in ("run_id", "attempt_id"):
        _const(e[key], root[key], "event." + key, "RUN_SCOPE_MISMATCH")
    _int(e["sequence"], "event.sequence", 1, MAX_EVENTS)
    _const(e["sequence"], position, "event.sequence", "EVENT_SEQUENCE")
    _enum(e["role"], {"PRODUCE_D8", "REUSE_POINTER", "AUDIT_02C", "TRACE_02F"}, "event.role")
    _enum(e["status"], STATES, "event.status")
    for key in ("started_tick", "ended_tick"):
        if e[key] is not None:
            _int(e[key], "event." + key)
    if e["status"] == "NOT_RUN":
        _need(e["started_tick"] is None and e["ended_tick"] is None and not e["bindings"],
              "LIFECYCLE_ORDER", "event.NOT_RUN")
    else:
        _need(e["started_tick"] is not None, "LIFECYCLE_ORDER", "event.started_tick")
        if e["status"] == "COMPLETE":
            _need(e["ended_tick"] is not None, "LIFECYCLE_ORDER", "event.ended_tick")
        if e["ended_tick"] is not None:
            _need(e["ended_tick"] >= e["started_tick"], "LIFECYCLE_ORDER", "event.ticks")
    for key in ("inputs", "outputs", "depends_on"):
        _list(e[key], 8, "event." + key); _unique_ids(e[key], "event." + key)
    _need(not (set(e["inputs"]) & set(e["outputs"])), "DOUBLE_PRODUCTION", "event")
    _list(e["bindings"], 4, "event.bindings")


def _links(root: dict) -> list[Reason]:
    artifacts = {a["artifact_id"]: a for a in root["artifacts"]}
    events = {e["event_id"]: e for e in root["events"]}
    pending: list[Reason] = []
    produced: dict[str, str] = {}
    seen: set[str] = set()
    previous_end = None
    for e in root["events"]:
        path = "events." + e["event_id"]
        _need(set(e["depends_on"]) <= seen, "DEPENDENCY_ORDER", path)
        if e["status"] == "COMPLETE":
            _need(all(events[d]["status"] == "COMPLETE" for d in e["depends_on"]),
                  "INCOMPLETE_DEPENDENCY", path)
        if e["started_tick"] is not None:
            _need(previous_end is None or e["started_tick"] >= previous_end,
                  "LIFECYCLE_ORDER", path)
        if e["ended_tick"] is not None:
            previous_end = e["ended_tick"]
        _need(set(e["inputs"] + e["outputs"]) <= set(artifacts), "MISSING_ARTIFACT", path)
        ins = [artifacts[k] for k in e["inputs"]]
        outs = [artifacts[k] for k in e["outputs"]]
        shapes = {
            "PRODUCE_D8": ({"LAND_WATER"}, {"POINTER"}),
            "REUSE_POINTER": ({"POINTER"}, set()),
            "TRACE_02F": ({"POINTER", "WATER_CLASS", "LAKE_ID", "CANDIDATE_EDGES"}, F_OUTPUTS),
            "AUDIT_02C": (RASTERS, C_OUTPUTS),
        }
        expected_in, expected_out = shapes[e["role"]]
        _need({a["role"] for a in ins} == expected_in and len(ins) == len(expected_in) and
              {a["role"] for a in outs} == expected_out and len(outs) == len(expected_out),
              "STAGE_ROLE_MISMATCH", path)
        for a in ins:
            if a["production"] == "PRODUCED":
                _need(a["producer_event_id"] in e["depends_on"] and
                      produced.get(a["artifact_id"]) == a["producer_event_id"],
                      "PRODUCER_LINK_MISMATCH", path)
            if a["production"] == "REUSED":
                reuse = [events[d] for d in e["depends_on"] if events[d]["role"] == "REUSE_POINTER"]
                _need(e["role"] == "REUSE_POINTER" or any(a["artifact_id"] in d["inputs"] for d in reuse),
                      "REUSE_LINK_MISSING", path)
                if a["predecessor"] is None:
                    pending.append(Reason("MISSING_CLAIMED_PRODUCER_LINK", a["artifact_id"]))
        for a in outs:
            _need(a["production"] == "PRODUCED" and a["producer_event_id"] == e["event_id"] and
                  a["artifact_id"] not in produced, "PRODUCER_LINK_MISMATCH", path)
            produced[a["artifact_id"]] = e["event_id"]
            if e["status"] != "COMPLETE":
                _need(a["file"]["state"] in {"NOT_RUN", "NO_FILE_REPRESENTATION"} and
                      a["logical"]["state"] == "NOT_RUN",
                      "UNFINISHED_OUTPUT_MEASURED", path)
        bound: set[str] = set()
        for b in e["bindings"]:
            _keys(b, {"artifact_id", "logical_sha256", "logical_size_bytes", "snapshot_id", "guard",
                      "before_sha256", "after_sha256"}, path + ".binding")
            _id(b["artifact_id"], path + ".binding.artifact_id")
            _need(b["artifact_id"] in e["inputs"] and b["artifact_id"] not in bound,
                  "BINDING_ARTIFACT_MISMATCH", path)
            a = artifacts[b["artifact_id"]]
            _need(a["role"] in RASTERS, "BINDING_ARTIFACT_MISMATCH", path)
            _digest(b["logical_sha256"], path + ".binding.logical_sha256")
            _int(b["logical_size_bytes"], path + ".binding.logical_size_bytes", 1, 2**40)
            _need(_present(a["logical"]) and b["logical_sha256"] == a["logical"]["sha256"] and
                  b["logical_size_bytes"] == a["logical"]["size_bytes"], "EFFECTIVE_INPUT_MISMATCH", path)
            _enum(b["guard"], {"SNAPSHOT_CLAIM", "ENDPOINT_HASHES_ONLY", "NOT_ASSESSED"}, path + ".guard")
            for key in ("before_sha256", "after_sha256"):
                if b[key] is not None:
                    _digest(b[key], path + "." + key)
            if b["before_sha256"] is not None and b["after_sha256"] is not None:
                _need(b["before_sha256"] == b["after_sha256"], "SOURCE_MUTATION_CLAIM", path)
            version = a["logical"] if a["source_type"] == "IN_MEMORY" else a["file"]
            for key in ("before_sha256", "after_sha256"):
                if b[key] is not None:
                    _need(_present(version) and b[key] == version["sha256"],
                          "SOURCE_VERSION_MISMATCH", path)
            if b["guard"] == "SNAPSHOT_CLAIM":
                _id(b["snapshot_id"], path + ".snapshot_id")
            else:
                _need(b["snapshot_id"] is None, "GUARD_SNAPSHOT_MISMATCH", path)
                pending.append(Reason("IMMUTABLE_BINDING_NOT_RECORDED", b["artifact_id"]))
            bound.add(b["artifact_id"])
        if e["status"] == "COMPLETE":
            required = {a["artifact_id"] for a in ins if a["role"] in RASTERS}
            for key in sorted(required - bound):
                pending.append(Reason("EFFECTIVE_INPUT_BINDING_MISSING", key))
            for a in ins + outs:
                needed = a["logical"] if a["source_type"] == "IN_MEMORY" else a["file"]
                if not _present(needed):
                    pending.append(Reason("ARTIFACT_IDENTITY_MISSING", a["artifact_id"]))
        seen.add(e["event_id"])
    for a in artifacts.values():
        if a["production"] == "PRODUCED":
            _need(produced.get(a["artifact_id"]) == a["producer_event_id"],
                  "PRODUCER_LINK_MISMATCH", "artifacts." + a["artifact_id"])
    referenced = {key for e in events.values() for key in e["inputs"] + e["outputs"]}
    _need(set(artifacts) == referenced, "ORPHAN_ARTIFACT", "artifacts")
    if root["status"] == "COMPLETE":
        roles = {e["role"] for e in events.values()}
        if "TRACE_02F" not in roles or not roles & {"PRODUCE_D8", "REUSE_POINTER"}:
            pending.append(Reason("REQUIRED_STAGE_MISSING", "events"))
        if any(e["status"] != "COMPLETE" for e in events.values()):
            pending.append(Reason("INCOMPLETE_STAGE", "events"))
    else:
        pending.append(Reason("RUN_" + root["status"], "status"))
    if root["status"] == "NOT_RUN":
        _need(all(e["status"] == "NOT_RUN" for e in events.values()), "LIFECYCLE_ORDER", "status")
    return pending


def _validate(value: object, used_run_ids: tuple[str, ...]) -> ValidationResult:
    _walk(value)
    _keys(value, {"schema_version", "evidence_kind", "repository", "commit_sha", "run_id", "attempt_id",
                  "status", "grid", "artifacts", "events", "witness"} | set(LOCKS), "record")
    _const(value["schema_version"], SCHEMA, "schema_version", "UNKNOWN_SCHEMA_VERSION")
    _const(value["evidence_kind"], "SYNTHETIC", "evidence_kind", "SYNTHETIC_ONLY")
    _const(value["repository"], "annasuuronen/MaaltaMerelle", "repository")
    _digest(value["commit_sha"], "commit_sha", 40)
    for key, expected in LOCKS.items():
        _const(value[key], expected, key, "FORBIDDEN_SCIENCE_OR_AUTHENTICATION_CLAIM")
    _need(value["witness"] is None, "EXTERNAL_WITNESS_NOT_IMPLEMENTED", "witness")
    _uuid(value["run_id"], "run_id"); _uuid(value["attempt_id"], "attempt_id")
    _need(value["run_id"] != value["attempt_id"], "RUN_ID_REUSE", "attempt_id")
    _need(type(used_run_ids) is tuple and len(used_run_ids) <= 128, "INVALID_PRIOR_ID_CONTEXT", "used_run_ids")
    for key in used_run_ids:
        _uuid(key, "used_run_ids")
    _need(not ({value["run_id"], value["attempt_id"]} & set(used_run_ids)), "RUN_ID_REUSE", "run_id")
    _enum(value["status"], STATES, "status")
    _grid(value["grid"])
    _list(value["artifacts"], MAX_ARTIFACTS, "artifacts")
    _list(value["events"], MAX_EVENTS, "events")
    for a in value["artifacts"]:
        _artifact(a, value)
    for i, e in enumerate(value["events"], 1):
        _event(e, value, i)
    artifact_ids = [a["artifact_id"] for a in value["artifacts"]]
    event_ids = [e["event_id"] for e in value["events"]]
    _unique_ids(artifact_ids + event_ids, "identities")
    artifact_roles = [a["role"] for a in value["artifacts"]]
    _need(len(artifact_roles) == len(set(artifact_roles)), "CONFLICTING_ARTIFACT_ROLE", "artifacts")
    _need(not (set(artifact_ids + event_ids) & {value["run_id"], value["attempt_id"]}),
          "DUPLICATE_ID", "identities")
    roles = [e["role"] for e in value["events"]]
    _need(len(roles) == len(set(roles)) and not {"PRODUCE_D8", "REUSE_POINTER"} <= set(roles),
          "DUPLICATE_STAGE_ROLE", "events")
    uris = [a["uri"] for a in value["artifacts"] if a["uri"] is not None]
    _need(len(uris) == len(set(uris)), "ARTIFACT_URI_ALIAS", "artifacts")
    reasons = tuple(sorted(set(_links(value))))
    canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("ascii")
    _need(len(canonical) <= MAX_BYTES, "RESOURCE_LIMIT", "canonical_json")
    record = Record(SCHEMA, value["run_id"], value["attempt_id"], value["status"],
                    tuple(artifact_ids), tuple(event_ids), canonical, sha256(canonical).hexdigest())
    measurements = [a[k]["state"] for a in value["artifacts"] for k in ("file", "logical")]
    checksum = ("SIMULATED_MEASUREMENTS_RECORDED" if "MEASURED_SIMULATED" in measurements
                else "CLAIMS_ONLY" if "DECLARED" in measurements else "NOT_ASSESSED")
    return ValidationResult("SCHEMA_VALID", "STOP" if reasons else "RECORDED_UNVERIFIED", value["status"],
                            "COMPLETE_CLAIM" if not reasons else value["status"] if value["status"] != "COMPLETE" else "INCOMPLETE",
                            reasons, record, checksum)


def validate_record(value: object, *, used_run_ids: tuple[str, ...] = ()) -> ValidationResult:
    """Validate JSON-shaped in-memory claims; caller ID context is not a registry."""
    try:
        return _validate(value, used_run_ids)
    except _Invalid as exc:
        return ValidationResult("STOP", "STOP", reasons=(exc.reason,))


def validate_json(raw: str | bytes, *, used_run_ids: tuple[str, ...] = ()) -> ValidationResult:
    """Strict UTF-8 JSON parsing with duplicate/depth/size guards; never open a path."""
    try:
        return _validate(_decode(raw), used_run_ids)
    except _Invalid as exc:
        return ValidationResult("STOP", "STOP", reasons=(exc.reason,))
    except UnicodeError:
        return ValidationResult("STOP", "STOP", reasons=(Reason("INVALID_UTF8", "json"),))
