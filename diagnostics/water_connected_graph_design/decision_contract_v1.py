"""S1.0: pure, immutable evidence classification; never hydrological approval.

Only normalized in-memory records are accepted. Provenance checks establish
internal consistency, not authenticity of files, measurements or caller claims.
"""
from collections.abc import Mapping
from dataclasses import dataclass, field, fields, is_dataclass
import json
import math
import re

DECISION_STATES = ("OBSERVED", "CANDIDATE", "REVIEW_REQUIRED", "REJECTED", "NOT_ASSESSED")


class SchemaStop(ValueError):
    """Fail closed, without returning a partial decision or grouped result."""
    def __init__(self, reason_code, path):
        self.reason_code, self.path = reason_code, path
        super().__init__(f"SCHEMA_STOP:{reason_code}:{path}")


def _stop(code, path):
    raise SchemaStop(code, path)


def _mapping(value, required, optional=(), path="observation"):
    if not isinstance(value, Mapping):
        _stop("MAPPING_REQUIRED", path)
    if any(type(key) is not str for key in value):
        _stop("STRING_KEYS_REQUIRED", path)
    if set(value) - set(required) - set(optional) or set(required) - set(value):
        _stop("MISSING_OR_UNKNOWN_FIELDS", path)
    return value


def _text(value, path):
    if type(value) is not str or not value or value.strip() != value or len(value) > 512:
        _stop("NONEMPTY_CANONICAL_TEXT_REQUIRED", path)
    return value


def _enum(value, choices, path):
    if type(value) is not str or value not in choices:
        _stop("UNKNOWN_ENUM", path)
    return value


def _identity(value, path):
    value = _text(value, path)
    if value == "UNKNOWN":
        _stop("REQUIRED_IDENTITY_UNKNOWN", path)
    return value


def _integer(value, path, maximum=2**53-1, minimum=1):
    if type(value) is not int or not minimum <= value <= maximum:
        _stop("EXACT_INTEGER_REQUIRED", path)
    return value


def _number(value, path, nonnegative=False):
    if type(value) not in (int, float):
        _stop("FINITE_NUMBER_REQUIRED", path)
    try:
        result = float(value)
    except (OverflowError, ValueError):
        _stop("FINITE_NUMBER_REQUIRED", path)
    if not math.isfinite(result) or (nonnegative and result < 0):
        _stop("FINITE_NUMBER_REQUIRED", path)
    return 0.0 if result == 0 else result


def _optional(value, function, path):
    return None if value is None else function(value, path)


def _boolean(value, path):
    if value is not None and type(value) is not bool:
        _stop("BOOLEAN_OR_NULL_REQUIRED", path)
    return value


def _sequence(value, path, maximum=4096):
    if type(value) not in (list, tuple) or len(value) > maximum:
        _stop("BOUNDED_SEQUENCE_REQUIRED", path)
    return value


@dataclass(frozen=True)
class Grid:
    grid_id: str
    epsg: int
    nrow: int
    ncol: int
    resolution_m: float
    xmin: float
    xmax: float
    ymin: float
    ymax: float


def _grid(value, path):
    value = _mapping(value, tuple(f.name for f in fields(Grid)), path=path)
    grid_id = _identity(value["grid_id"], path+".grid_id")
    if type(value["epsg"]) is not int or value["epsg"] != 3067:
        _stop("EPSG_3067_REQUIRED", path)
    nr, nc = (_integer(value[k], path+"."+k) for k in ("nrow", "ncol"))
    if nr*nc > 2**53-1 or _number(value["resolution_m"], path+".resolution_m") != 2:
        _stop("TWO_METRE_SAFE_GRID_REQUIRED", path)
    box = tuple(_number(value[k], path+"."+k) for k in ("xmin", "xmax", "ymin", "ymax"))
    xmin, xmax, ymin, ymax = box
    if (max(abs(x) for x in box) >= 2**52 or xmax-xmin != 2*nc or ymax-ymin != 2*nr):
        _stop("BBOX_GRID_MISMATCH", path)
    return Grid(grid_id, 3067, nr, nc, 2.0, *box)


@dataclass(frozen=True)
class Source:
    source_path_or_id: str
    source_version: str
    source_role: str
    kind: str
    used_in_build_or_candidate_review: object
    reference_role: str
    shared_lineage: object
    verification_state: str


def _source(value):
    p = "provenance.sources"
    value = _mapping(value, tuple(f.name for f in fields(Source)), path=p)
    sid = _identity(value["source_path_or_id"], p+".source_path_or_id")
    version = _text(value["source_version"], p+".source_version")
    role = _enum(value["source_role"], ("INPUT", "AUXILIARY", "INDEPENDENT_REFERENCE"), p+".source_role")
    kind = _enum(value["kind"], ("DEM", "D8", "RANTA10", "SYKE_OUTLETS", "SYKE_CATCHMENTS", "OTHER"), p+".kind")
    used, shared = value["used_in_build_or_candidate_review"], value["shared_lineage"]
    for name, flag in (("used_in_build_or_candidate_review", used), ("shared_lineage", shared)):
        if type(flag) is not bool and not (type(flag) is str and flag == "UNKNOWN"):
            _stop("BOOLEAN_OR_EXPLICIT_UNKNOWN_REQUIRED", p+"."+name)
    reference = _enum(value["reference_role"], ("INPUT", "AUXILIARY_CONCORDANCE", "HELD_OUT_COMPARISON", "REFERENCE_USE_UNKNOWN"), p+".reference_role")
    verified = _enum(value["verification_state"], ("VERIFIED", "UNKNOWN"), p+".verification_state")
    if ((role == "INPUT" and reference != "INPUT") or
            (role != "INPUT" and reference == "INPUT") or
            (role == "INDEPENDENT_REFERENCE" and reference != "HELD_OUT_COMPARISON") or
            (reference == "HELD_OUT_COMPARISON" and
             (role != "INDEPENDENT_REFERENCE" or used is not False or shared is not False or
              version == "UNKNOWN" or verified != "VERIFIED"))):
        _stop("SOURCE_ROLE_OR_HOLDOUT_CONFLICT", p)
    return Source(sid, version, role, kind, used, reference, shared, verified)


@dataclass(frozen=True)
class Provenance:
    manifest_sha256: str
    manifest_state: str
    producer_commit: str
    evidence_version: str
    algorithm_version: str
    grid: Grid
    sources: tuple


def _provenance(value, grid):
    p = "provenance"
    value = _mapping(value, tuple(f.name for f in fields(Provenance)), path=p)
    for key, length in (("manifest_sha256", 64), ("producer_commit", 40)):
        if type(value[key]) is not str or not re.fullmatch(r"[0-9a-f]{"+str(length)+r"}", value[key]):
            _stop("INVALID_PROVENANCE_DIGEST", p+"."+key)
    state = _enum(value["manifest_state"], ("CURRENT", "UNKNOWN", "STALE"), p+".manifest_state")
    if state == "STALE":
        _stop("STALE_MANIFEST", p)
    if _grid(value["grid"], p+".grid") != grid:
        _stop("MANIFEST_GRID_CONFLICT", p+".grid")
    sources = tuple(sorted((_source(x) for x in _sequence(value["sources"], p+".sources", 64)),
                           key=lambda x: x.source_path_or_id))
    if not sources or len({s.source_path_or_id for s in sources}) != len(sources):
        _stop("MISSING_OR_DUPLICATE_SOURCE", p+".sources")
    return Provenance(value["manifest_sha256"], state, value["producer_commit"],
                      _identity(value["evidence_version"], p+".evidence_version"),
                      _identity(value["algorithm_version"], p+".algorithm_version"), grid, sources)


@dataclass(frozen=True)
class ReceiverClaim:
    receiver_type: str
    receiver_id: int
    source_path_or_id: str


@dataclass(frozen=True)
class Impossibility:
    source_path_or_id: str
    evidence_id: str
    criterion: str
    statement: str


@dataclass(frozen=True)
class Evidence:
    water_classes: object = None
    classification_02c: object = None
    component_status: str = "NOT_ASSESSED"
    footprint_intersects: object = None
    center_intersects: object = None
    mapped_line_present: object = None
    syke_point_match: object = None
    same_catchment: object = None
    directed_hypothesis: object = None
    proposes_functioning_outflow: object = None
    claims_continuous: object = None
    tile_crossing: str = "NOT_ASSESSED"
    height_difference_m: object = None
    height_uncertainty_m: object = None
    separation_m: object = None
    independence_state: str = "NOT_ASSESSED"
    receiver_claims: tuple = ()
    impossibility: object = None


def _evidence(value, provenance):
    p = "evidence"
    value = _mapping(value, (), tuple(f.name for f in fields(Evidence)), p)
    normalized = {}
    for name in ("footprint_intersects", "center_intersects", "mapped_line_present", "syke_point_match",
                 "same_catchment", "directed_hypothesis", "proposes_functioning_outflow", "claims_continuous"):
        normalized[name] = _boolean(value.get(name), p+"."+name)
    for name in ("height_difference_m", "height_uncertainty_m", "separation_m"):
        x = value.get(name)
        normalized[name] = None if x is None else _number(x, p+"."+name, name != "height_difference_m")
    classes = value.get("water_classes")
    if classes is not None:
        classes = tuple(sorted(_integer(x, p+".water_classes", 3) for x in _sequence(classes, p+".water_classes", 64)))
    normalized["water_classes"] = classes
    cl = value.get("classification_02c")
    normalized["classification_02c"] = None if cl is None else _enum(cl, (
        "SAFE_LAKE_CONNECTOR", "INTERIOR_REVIEW", "LAKE_ONLY", "RIVER_AREA_ONLY", "RIVER_LINE_ONLY", "MIXED", "NOT_ASSESSED"), p+".classification_02c")
    for name, choices in (("component_status", ("OBSERVED", "ABSENT", "NOT_ASSESSED")),
                          ("tile_crossing", ("NOT_ASSESSED", "NOT_PRESENT", "UNVERIFIED", "REPORTED_VERIFIED")),
                          ("independence_state", ("NOT_ASSESSED", "COMPARISON_REPORTED"))):
        normalized[name] = _enum(value.get(name, "NOT_ASSESSED"), choices, p+"."+name)
    by_source = {s.source_path_or_id: s for s in provenance.sources}
    claims = []
    for claim in _sequence(value.get("receiver_claims", ()), p+".receiver_claims", 64):
        claim = _mapping(claim, ("receiver_type", "receiver_id", "source_path_or_id"), path=p+".receiver_claims")
        source = _text(claim["source_path_or_id"], p+".receiver_claims.source_path_or_id")
        if source not in by_source:
            _stop("UNBOUND_EVIDENCE_SOURCE", p+".receiver_claims")
        claims.append(ReceiverClaim(_enum(claim["receiver_type"], ("LAKE", "RIVER_AREA", "RIVER_LINE"), p),
                                    _integer(claim["receiver_id"], p), source))
    normalized["receiver_claims"] = tuple(sorted(claims, key=lambda x: (x.receiver_type, x.receiver_id, x.source_path_or_id)))
    proof = value.get("impossibility")
    if proof is not None:
        proof = _mapping(proof, tuple(f.name for f in fields(Impossibility)), path=p+".impossibility")
        proof = Impossibility(*(_text(proof[k.name], p+".impossibility."+k.name) for k in fields(Impossibility)))
        if proof.source_path_or_id not in by_source:
            _stop("UNBOUND_EVIDENCE_SOURCE", p+".impossibility")
        if proof.criterion != "EXPLICIT_PHYSICAL_CONTRADICTION":
            _stop("EXPLICIT_IMPOSSIBILITY_CRITERION_REQUIRED", p+".impossibility")
    normalized["impossibility"] = proof
    if normalized["independence_state"] == "COMPARISON_REPORTED" and not any(
            s.reference_role == "HELD_OUT_COMPARISON" for s in provenance.sources):
        _stop("INDEPENDENCE_CLAIM_CONFLICT", p)
    kinds = {s.kind for s in provenance.sources}
    if (classes is not None or cl not in (None, "NOT_ASSESSED") or
            normalized["footprint_intersects"] is not None or normalized["center_intersects"] is not None) and "RANTA10" not in kinds:
        _stop("RANTA10_SOURCE_REQUIRED", p)
    if ((normalized["syke_point_match"] is True and "SYKE_OUTLETS" not in kinds) or
            (normalized["same_catchment"] is True and "SYKE_CATCHMENTS" not in kinds)):
        _stop("AUXILIARY_SOURCE_REQUIRED", p)
    return Evidence(**normalized)


@dataclass(frozen=True)
class Observation:
    observation_id: str
    region_id: str
    grid: Grid
    provenance: Provenance
    origin_lake_id: object
    source_cell: object
    start_receiver_cell: object
    terminal_cell: object
    component_id: object
    receiver_type: str
    receiver_id: object
    route_id: object
    route_status: str
    route_geometry: str
    steps: object
    evidence: Evidence
    schema_version: str = field(default="s1.0", init=False)


def validate_observation(mapping):
    """Return a detached deeply immutable record, or raise SchemaStop."""
    required = ("schema_version", "observation_id", "region_id", "grid", "provenance")
    optional = tuple(f.name for f in fields(Observation) if f.name not in required)
    x = _mapping(mapping, required, optional)
    _enum(x["schema_version"], ("s1.0",), "schema_version")
    grid = _grid(x["grid"], "grid")
    provenance = _provenance(x["provenance"], grid)
    values = {k: _identity(x[k], k) for k in ("observation_id", "region_id")}
    values.update(grid=grid, provenance=provenance)
    for name in ("origin_lake_id", "component_id", "receiver_id"):
        values[name] = _optional(x.get(name), _integer, name)
    for name in ("source_cell", "start_receiver_cell", "terminal_cell"):
        values[name] = _optional(x.get(name), lambda a, p: _integer(a, p, grid.nrow*grid.ncol), name)
    values["route_id"] = _optional(x.get("route_id"), _identity, "route_id")
    values["steps"] = _optional(x.get("steps"), lambda a, p: _integer(a, p, minimum=0), "steps")
    values["receiver_type"] = _enum(x.get("receiver_type", "UNKNOWN"), ("UNKNOWN", "LAKE", "RIVER_AREA", "RIVER_LINE"), "receiver_type")
    values["route_status"] = _enum(x.get("route_status", "NOT_ASSESSED"), (
        "NOT_ASSESSED", "D8_ZERO_INTERIOR", "D8_ZERO_AT_RASTER_EDGE", "RETURNS_TO_ORIGIN_LAKE", "D8_CYCLE", "D8_DOMAIN_EXIT", "STEP_LIMIT",
        "REACHES_OTHER_LAKE", "REACHES_RIVER_AREA", "REACHES_RIVER_LINE", "LAKE_ID_MISSING",
        "D8_POINTER_NA", "D8_POINTER_INVALID"), "route_status")
    values["route_geometry"] = _enum(x.get("route_geometry", "NOT_ASSESSED"),
                                      ("NOT_ASSESSED", "SUMMARY_ONLY", "FULL_CHAIN_REPORTED"), "route_geometry")
    evidence = _evidence(x.get("evidence", {}), provenance)
    if ((values["receiver_type"] == "UNKNOWN" and values["receiver_id"] is not None) or
        (evidence.component_status == "OBSERVED" and values["component_id"] is None) or
        (evidence.component_status == "ABSENT" and values["component_id"] is not None)):
        _stop("IDENTITY_EVIDENCE_CONFLICT", "observation")
    has_route = values["route_status"] != "NOT_ASSESSED" or values["route_id"] is not None
    if has_route and any(values[k] is None for k in ("route_id", "origin_lake_id", "source_cell", "start_receiver_cell", "steps")):
        _stop("REQUIRED_ROUTE_IDENTITY_MISSING", "observation")
    if evidence.directed_hypothesis is True and any(values[k] is None for k in (
            "origin_lake_id", "source_cell", "start_receiver_cell")):
        _stop("REQUIRED_HYPOTHESIS_IDENTITY_MISSING", "observation")
    if not has_route and (values["steps"] is not None or values["route_geometry"] != "NOT_ASSESSED"):
        _stop("ROUTE_GEOMETRY_WITHOUT_IDENTITY", "observation")
    if has_route and not any(s.kind == "D8" for s in provenance.sources):
        _stop("D8_SOURCE_REQUIRED", "provenance.sources")
    return Observation(**values, evidence=evidence)


def _validated(observation):
    if type(observation) is not Observation:
        _stop("VALIDATED_OBSERVATION_REQUIRED", "observation")
    # Frozen constructors are not proof that the caller ran our validator.
    return validate_observation(to_plain_mapping(observation))


def _key(obs, cell):
    return (obs.region_id, obs.grid.grid_id, obs.provenance.manifest_sha256, obs.origin_lake_id, cell)


@dataclass(frozen=True)
class Decision:
    case_key: tuple
    case_type: str
    decision_state: str
    reason_codes: tuple
    reason_evidence: tuple
    evidence_gaps: tuple
    source_roles: tuple
    provenance: Provenance
    observation: Observation
    schema_version: str = field(default="s1.0", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    route_chain_assessment: str = field(default="NOT_ASSESSED", init=False)
    independent_validation_state: str = field(default="NOT_ASSESSED", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)

    def __post_init__(self):
        _enum(self.decision_state, DECISION_STATES, "decision_state")


def classify(observation):
    """Classify evidence; no numerical national thresholds or route generation."""
    o = _validated(observation)
    e = o.evidence
    reasons, gaps = {}, set()
    review = False
    def reason(code, *paths):
        reasons.setdefault(code, set()).update(paths)
    directed = e.directed_hypothesis is True
    known_receiver = o.receiver_type != "UNKNOWN" and (o.receiver_type != "LAKE" or o.receiver_id is not None)
    candidate = directed and o.origin_lake_id is not None and known_receiver
    raw = (e.water_classes is not None or e.classification_02c not in (None, "NOT_ASSESSED") or
           e.component_status != "NOT_ASSESSED" or any(v is not None for v in
           (e.footprint_intersects,e.center_intersects,e.mapped_line_present,e.syke_point_match,e.same_catchment,
            e.height_difference_m,e.separation_m)) or o.route_status != "NOT_ASSESSED")
    if (e.water_classes is not None and len(set(e.water_classes)) > 1) or e.classification_02c == "MIXED":
        reason("MIXED_WATER_NEIGHBORS", "evidence.water_classes", "evidence.classification_02c")
        review = True
    if e.classification_02c == "INTERIOR_REVIEW":
        reason("SOURCE_02C_REVIEW", "evidence.classification_02c"); review = True
    if o.route_status in ("D8_ZERO_INTERIOR", "D8_ZERO_AT_RASTER_EDGE"):
        reason("LAND_D8_ZERO_TERMINAL", "route_status", "terminal_cell")
        review |= directed or e.proposes_functioning_outflow is True or e.claims_continuous is True
    if e.component_status == "ABSENT":
        reason("COMPONENTLESS_OBSERVATION", "evidence.component_status", "component_id")
    if e.footprint_intersects is True and e.center_intersects is False:
        reason("BOUNDARY_FOOTPRINT_ONLY", "evidence.footprint_intersects", "evidence.center_intersects")
    if e.mapped_line_present is False:
        reason("MAPPED_LINE_GAP", "evidence.mapped_line_present")
        gaps.add("PHYSICAL_LINE_CONTINUITY_NOT_ASSESSED")
    if e.syke_point_match is True or e.same_catchment is True:
        reason("SYKE_AUXILIARY_MATCH", "evidence.syke_point_match", "evidence.same_catchment")
    if o.route_geometry == "SUMMARY_ONLY":
        reason("ROUTE_GEOMETRY_SUMMARY_ONLY", "route_geometry")
    if o.route_id is not None or directed:
        gaps.update(("INTERMEDIATE_CHAIN_NOT_ASSESSED", "D8_CONTINUITY_NOT_ASSESSED", "HEIGHT_CONSTRAINTS_NOT_ASSESSED"))
    # S1 has no intermediate-cell-chain verifier. An external FULL label is
    # retained, but cannot clear review of a continuity claim.
    if e.claims_continuous is True:
        reason("UNSUPPORTED_CONTINUITY_CLAIM", "evidence.claims_continuous", "route_geometry")
        review = True
    if e.proposes_functioning_outflow is True:
        reason("OUTFLOW_PROPOSAL_REQUIRES_REVIEW", "evidence.proposes_functioning_outflow")
        review = True
    if o.route_status in ("D8_DOMAIN_EXIT", "D8_ZERO_AT_RASTER_EDGE") or e.tile_crossing in ("UNVERIFIED", "REPORTED_VERIFIED"):
        reason("TILE_CROSSING_UNVERIFIED", "route_status", "evidence.tile_crossing")
        gaps.add("NEIGHBOR_TILE_CONNECTION_NOT_ASSESSED"); review = True
    if o.route_status in ("D8_CYCLE", "RETURNS_TO_ORIGIN_LAKE") or (
            directed and o.receiver_type == "LAKE" and o.receiver_id == o.origin_lake_id and o.origin_lake_id is not None):
        reason("CYCLE_OR_RETURN", "route_status", "receiver_id", "origin_lake_id"); review = True
    if o.route_status in ("STEP_LIMIT", "D8_POINTER_NA", "D8_POINTER_INVALID", "LAKE_ID_MISSING"):
        reason("ROUTE_UNRESOLVED", "route_status"); review = True
    receivers = {(c.receiver_type, c.receiver_id) for c in e.receiver_claims}
    if o.receiver_id is not None:
        receivers.add((o.receiver_type,o.receiver_id))
    if len(receivers) > 1:
        reason("CONTRADICTORY_RECEIVERS", "evidence.receiver_claims", "receiver_id", "receiver_type"); review = True
    if directed and (o.origin_lake_id is None or not known_receiver):
        reason("HYPOTHESIS_IDENTITY_UNRESOLVED", "origin_lake_id", "receiver_id", "receiver_type")
        gaps.add("DIRECTED_ENDPOINT_NOT_ASSESSED"); review = True
    if o.receiver_type in ("RIVER_AREA", "RIVER_LINE") and o.receiver_id is None:
        gaps.add("RECEIVER_FEATURE_ID_NOT_ASSESSED")
    if e.component_status == "NOT_ASSESSED" and o.component_id is None:
        gaps.add("COMPONENT_NOT_ASSESSED")
    if e.height_difference_m is not None and e.height_uncertainty_m is None:
        reason("LOW_GRADIENT_UNCERTAIN", "evidence.height_difference_m", "evidence.height_uncertainty_m")
        gaps.add("HEIGHT_UNCERTAINTY_NOT_ASSESSED")
        review |= directed or e.proposes_functioning_outflow is True
    independent = any(s.reference_role == "HELD_OUT_COMPARISON" for s in o.provenance.sources)
    if not independent or e.independence_state != "COMPARISON_REPORTED":
        reason("INDEPENDENCE_UNVERIFIED", "provenance.sources", "evidence.independence_state")
        gaps.add("INDEPENDENT_COMPARISON_NOT_ASSESSED")
    if o.provenance.manifest_state == "UNKNOWN" or any(s.source_version == "UNKNOWN" or
            s.verification_state == "UNKNOWN" or s.shared_lineage == "UNKNOWN" or
            s.used_in_build_or_candidate_review == "UNKNOWN" for s in o.provenance.sources):
        reason("PROVENANCE_UNRESOLVED", "provenance"); gaps.add("SOURCE_HISTORY_NOT_ASSESSED")
    if e.impossibility is not None:
        reason("DOCUMENTED_IMPOSSIBILITY", "evidence.impossibility")
        source = next(s for s in o.provenance.sources if s.source_path_or_id == e.impossibility.source_path_or_id)
        if source.reference_role != "HELD_OUT_COMPARISON" or source.kind != "OTHER":
            reason("IMPOSSIBILITY_REFERENCE_UNVERIFIED", "evidence.impossibility", "provenance.sources")
            gaps.add("IMPOSSIBILITY_REFERENCE_NOT_ASSESSED"); review = True
        # A negative report conflicting with a positive claim needs review.
        if directed or e.claims_continuous is True or e.proposes_functioning_outflow is True:
            reason("CONTRADICTORY_EVIDENCE", "evidence.impossibility", "evidence.directed_hypothesis",
                   "evidence.claims_continuous", "evidence.proposes_functioning_outflow")
            review = True
    # Explicit impossibility is a specific negative report, not an inference
    # from missing lines/points. Scientific approval remains NOT_ASSESSED.
    state = ("REVIEW_REQUIRED" if review else "REJECTED" if e.impossibility is not None
             else "CANDIDATE" if candidate else "OBSERVED" if raw else "NOT_ASSESSED")
    kind = ("LAKE_TO_LAKE_HYPOTHESIS" if directed and o.receiver_type == "LAKE" else
            "WATER_RECEIVER_HYPOTHESIS" if directed else "ROUTE_OBSERVATION" if o.route_id is not None else "SOURCE_OBSERVATION")
    key = _key(o, o.start_receiver_cell) if o.route_id is not None or directed else (o.region_id,o.grid.grid_id,o.observation_id)
    return Decision(key,kind,state,tuple(sorted(reasons)),
                    tuple((k,tuple(sorted(v))) for k,v in sorted(reasons.items())),tuple(sorted(gaps)),
                    tuple((s.source_path_or_id,s.source_role) for s in o.provenance.sources),o.provenance,o)


@dataclass(frozen=True)
class RouteGroup:
    case_key: tuple
    route_ids: tuple
    observation_ids: tuple
    source_cells: tuple
    record_count: int
    decision_state: str
    reason_codes: tuple


@dataclass(frozen=True)
class TerminalGroup:
    terminal_key: tuple
    case_keys: tuple
    route_ids: tuple
    record_count: int
    reason_codes: tuple


@dataclass(frozen=True)
class GroupedRoutes:
    cases: tuple
    terminals: tuple
    observations: tuple
    input_record_count: int
    unique_route_count: int
    unknown_terminal_route_keys: tuple
    reason_codes: tuple
    schema_version: str = field(default="s1.0", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    independent_route_count: object = field(default=None, init=False)
    flow_accumulation: str = field(default="NOT_COMPUTED", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)


def _sort(value):
    return json.dumps(to_plain_mapping(value), sort_keys=True, separators=(",", ":"), allow_nan=False)


def group_routes(records):
    """Group summaries and exact replays, never complete censored chains."""
    inputs = tuple(_validated(x) if type(x) is Observation else validate_observation(x)
                   for x in _sequence(records, "records"))
    identities, versions, routes, cases, terminals = {}, {}, {}, {}, {}
    for o in inputs:
        if o.route_id is None:
            _stop("ROUTE_RECORD_REQUIRED", "records")
        obs_key = (o.region_id,o.grid.grid_id,o.observation_id)
        if obs_key in identities and identities[obs_key] != o:
            _stop("OBSERVATION_ID_CONFLICT", "records")
        identities[obs_key] = o
        scope = (o.region_id,o.grid.grid_id)
        if scope in versions and versions[scope] != o.provenance:
            _stop("SOURCE_VERSION_CONFLICT", "records")
        versions[scope] = o.provenance
        route_key = (*scope,o.route_id)
        # 02F traces begin at start_receiver_cell. Several original shore
        # source_cell edges and evidence interpretations may cite that trace.
        payload = (o.origin_lake_id,o.start_receiver_cell,o.terminal_cell,
                   o.route_status,o.steps,o.route_geometry)
        if route_key in routes and routes[route_key] != payload:
            _stop("ROUTE_ID_CONFLICT", "records")
        routes[route_key] = payload
        cases.setdefault(_key(o,o.start_receiver_cell), []).append(o)
        if o.terminal_cell is not None:
            terminals.setdefault(_key(o,o.terminal_cell), []).append(o)
    grouped = []
    for key, rows in sorted(cases.items(), key=lambda x: _sort(x[0])):
        traces = {(o.terminal_cell,o.route_status,o.steps,o.route_geometry) for o in rows}
        if len(traces) != 1:
            _stop("ORIGIN_RECEIVER_TRACE_CONFLICT", "records")
        decisions = tuple(classify(o) for o in rows)
        receivers = {(o.receiver_type,o.receiver_id) for o in rows if o.receiver_id is not None}
        reasons = set(code for d in decisions for code in d.reason_codes)
        if len(receivers) > 1:
            reasons.add("CONTRADICTORY_RECEIVERS")
        if any(d.decision_state == "REJECTED" for d in decisions) and any(
                o.evidence.directed_hypothesis is True or o.evidence.claims_continuous is True or
                o.evidence.proposes_functioning_outflow is True for o in rows):
            reasons.add("CONTRADICTORY_EVIDENCE")
        order = ("REVIEW_REQUIRED", "REJECTED", "CANDIDATE", "OBSERVED", "NOT_ASSESSED")
        state = "REVIEW_REQUIRED" if reasons.intersection(("CONTRADICTORY_RECEIVERS", "CONTRADICTORY_EVIDENCE")) else next(
            s for s in order if any(d.decision_state==s for d in decisions))
        grouped.append(RouteGroup(key,tuple(sorted({o.route_id for o in rows})),
                                 tuple(sorted({o.observation_id for o in rows})),
                                 tuple(sorted({o.source_cell for o in rows})),len(rows),state,tuple(sorted(reasons))))
    terminal_groups = []
    all_codes = set()
    for key, rows in sorted(terminals.items(), key=lambda x: _sort(x[0])):
        keys = tuple(sorted({_key(o,o.start_receiver_cell) for o in rows},key=_sort))
        codes = ("MULTIPLE_STARTS_ONE_TERMINAL",) if len(keys)>1 else ()
        all_codes.update(codes)
        terminal_groups.append(TerminalGroup(key,keys,tuple(sorted({o.route_id for o in rows})),len(rows),codes))
    unknown = tuple(sorted({(o.region_id,o.grid.grid_id,o.route_id) for o in inputs if o.terminal_cell is None}))
    return GroupedRoutes(tuple(grouped),tuple(terminal_groups),tuple(sorted(identities.values(),key=_sort)),
                         len(inputs),len(routes),unknown,tuple(sorted(all_codes)))


def to_plain_mapping(result):
    """Detached JSON-compatible values; canonical record and sequence order."""
    if is_dataclass(result) and not isinstance(result, type):
        if type(result) not in (Grid, Source, Provenance, ReceiverClaim, Impossibility, Evidence,
                                Observation, Decision, RouteGroup, TerminalGroup, GroupedRoutes):
            _stop("SERIALIZATION_TYPE_FORBIDDEN", "result")
        if type(result) in (Decision, RouteGroup):
            _enum(result.decision_state, DECISION_STATES, "result.decision_state")
        if type(result) in (Decision, GroupedRoutes):
            if result.routing_authorized is not False:
                _stop("OUTPUT_AUTHORIZATION_FORBIDDEN", "result.routing_authorized")
            for name, expected in (("outlet_selection", "UNASSIGNED"), ("NATIONAL", "LOCKED"),
                                   ("MODERATE", "REVIEW_REQUIRED"), ("hydrological_validation", "NOT_ASSESSED"),
                                   ("channel_interpretation", "NOT_ASSESSED")):
                _enum(getattr(result, name), (expected,), "result."+name)
        if type(result) is Decision:
            for name in ("route_chain_assessment", "independent_validation_state"):
                _enum(getattr(result, name), ("NOT_ASSESSED",), "result."+name)
        if type(result) is GroupedRoutes and (result.independent_route_count is not None or result.flow_accumulation != "NOT_COMPUTED"):
            _stop("UNSUPPORTED_GROUP_INFERENCE", "result")
        return {f.name: to_plain_mapping(getattr(result,f.name)) for f in fields(result)}
    if type(result) is tuple:
        return [to_plain_mapping(x) for x in result]
    if result is None or type(result) in (str, int, bool):
        return result
    if type(result) is float and math.isfinite(result):
        return result
    _stop("SERIALIZATION_TYPE_FORBIDDEN", "result")
