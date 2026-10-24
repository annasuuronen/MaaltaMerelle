"""Tiny synthetic count/area crosswalk; not an R result loader or accumulator.

The frozen G5A reconciler is the only accumulation implementation invoked.
Hand-declared local counts are references, not observed 02G.3 output or lineage.
"""
from dataclasses import dataclass, field
from fractions import Fraction

from tile_accumulation_contract_v1 import Fixture, reconcile


@dataclass(frozen=True)
class LocalCount:
    node: str
    count: int


@dataclass(frozen=True)
class Reference:
    source_cells: tuple[int, ...]
    counts: tuple[LocalCount, ...]
    origin: str = "HAND_DECLARED_SYNTHETIC_REFERENCE"
    source_scope: str = "LOCAL_LAND_ONLY"
    external_import: str = "UNKNOWN"
    total_upstream_count: None = None
    count_unit_area_m2: Fraction = Fraction(4)


@dataclass(frozen=True)
class Crosswalk:
    status: str
    reason: str
    local_areas_m2: tuple[tuple[str, Fraction], ...] = ()
    underlying_g5a_status: str | None = None
    external_import: str = field(default="UNKNOWN", init=False)
    total_upstream_count: None = field(default=None, init=False)
    total_upstream_area_m2: None = field(default=None, init=False)
    reference_authentication: str = field(default="NOT_ASSESSED", init=False)
    actual_02g_invocation: str = field(default="NOT_RUN", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)
    routing_authorized: bool = field(default=False, init=False)
    outlet_selection: str = field(default="UNASSIGNED", init=False)
    HISTORIC_02F_EFFECTIVE_D8: str = field(default="NOT_ASSESSED", init=False)


def stop(reason):
    return Crosswalk("STOP", reason)


def compare_declared_reference(fixture, reference):
    """Check the common LAND-only prefix, retaining UNKNOWN outside inputs.

    This does not validate an R schema, cell census, D8 geometry or observed
    route. A downstream water cell must not silently become a source or a
    synthetic lake outlet. Divergent R integration remains a separate STOP.
    """
    if type(fixture) is not Fixture or type(reference) is not Reference:
        return stop("REFERENCE_SCHEMA")
    r = reference
    if (r.origin != "HAND_DECLARED_SYNTHETIC_REFERENCE" or
            r.source_scope != "LOCAL_LAND_ONLY"):
        return stop("REFERENCE_OR_SCOPE")
    if r.external_import != "UNKNOWN" or r.total_upstream_count is not None:
        return stop("UNKNOWN_IMPORT_NOT_ZERO_OR_TOTAL")
    if type(r.count_unit_area_m2) is not Fraction or r.count_unit_area_m2 != 4:
        return stop("EXACT_SOURCE_WEIGHT_4_REQUIRED")
    if (type(r.source_cells) is not tuple or not 1 <= len(r.source_cells) <= 11 or
            any(type(c) is not int or not 1 <= c <= 36_000_000 for c in r.source_cells) or
            len(set(r.source_cells)) != len(r.source_cells)):
        return stop("REFERENCE_SOURCES")
    if (type(r.counts) is not tuple or not 1 <= len(r.counts) <= 20 or
            any(type(x) is not LocalCount or type(x.node) is not str or
                not 1 <= len(x.node) <= 128 or type(x.count) is not int or
                not 0 <= x.count <= len(r.source_cells) for x in r.counts) or
            len({x.node for x in r.counts}) != len(r.counts)):
        return stop("REFERENCE_COUNTS")

    # Delegate full schema, ownership, transfer/cycle and mathematical QA to
    # the unchanged G5A implementation before reading its structured records.
    result = reconcile(fixture)
    if result.status == "STOP":
        return stop("G5A_STOP:" + result.findings[0].code)
    if any(n.kind not in ("LAND", "BOUNDARY") for n in fixture.nodes):
        return stop("NONLAND_OWNERSHIP_OR_ROUTING_NEEDS_REVIEW")
    if fixture.split_mode or any(a.fraction != 1 for a in fixture.arcs):
        return stop("SPLIT_NOT_02G_SINGLE_SUCCESSOR")
    cells = tuple(c for n in fixture.nodes for c in n.cells)
    if set(cells) != set(r.source_cells):
        return stop("SOURCE_POPULATION_MISMATCH")
    areas = dict(result.oracle_received_m2)
    if any(x.node not in areas for x in r.counts):
        return stop("REFERENCE_NODE_MISSING")
    if any(areas[x.node] != r.count_unit_area_m2*x.count for x in r.counts):
        return stop("LAND_COUNT_AREA_MISMATCH")
    return Crosswalk("LOCAL_COMPATIBLE_EXTERNAL_UNKNOWN", "COMMON_PREFIX_ONLY",
                     tuple(sorted((x.node, areas[x.node]) for x in r.counts)),
                     result.status.value)
