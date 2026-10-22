#!/usr/bin/env python3
"""Small synthetic-only WATER_CONNECTED graph contract oracle.

Does not read RANTA10/DEM/D8/CSC files and DOES NOT select real outlets.
No code in this file may be called a physical hydrology validation.
"""
from __future__ import annotations
from collections import defaultdict, deque
from dataclasses import dataclass
from fractions import Fraction


class GraphContractError(ValueError):
    pass


@dataclass(frozen=True)
class Node:
    key: str
    kind: str  # LAND, LAKE, RIVER_REACH, BOUNDARY
    owned_cells: tuple[int, ...] = ()


@dataclass(frozen=True)
class Arc:
    source: str
    target: str
    kind: str  # LAND_D8, LAKE_OUTLET, RIVER_LINK, BOUNDARY_EXIT
    fraction: Fraction = Fraction(1, 1)


@dataclass(frozen=True)
class Candidate:
    lake_id: int
    spill_group_id: int
    source_cell: int
    receiver_cell: int
    evidence_status: str
    route_status: str
    outlet_selection: str = "UNASSIGNED"
    needs_review: bool = False
    corner_only_contact: bool = False
    geometry_reviewed: bool = False
    provenance_verified: bool = False
    full_downstream_verified: bool = False


def candidate_preflight(x: Candidate) -> tuple[str, tuple[str, ...]]:
    """Diagnostic readiness only; never selects an outlet or makes an Arc."""
    reasons = []
    if x.outlet_selection != "UNASSIGNED":
        raise GraphContractError("existing 02E outlet_selection must remain UNASSIGNED")
    if any(c <= 0 for c in (x.lake_id, x.spill_group_id, x.source_cell, x.receiver_cell)):
        raise GraphContractError("invalid candidate identifiers")
    if x.evidence_status != "EXTERNAL_EVIDENCE":
        reasons.append("NO_CLEAR_EXTERNAL_EVIDENCE")
    if x.needs_review:
        reasons.append("SOURCE_REVIEW_REQUIRED")
    if x.route_status in {"RETURNS_TO_ORIGIN_LAKE", "D8_CYCLE"}:
        reasons.append("RETURN_OR_CYCLE")
    elif x.route_status in {"STEP_LIMIT", "D8_ZERO_INTERIOR", "D8_DOMAIN_EXIT", "LAKE_ID_MISSING", "D8_POINTER_NA", "D8_POINTER_INVALID", "START_OUTSIDE_RASTER"}:
        reasons.append("INCOMPLETE_OR_INVALID_ROUTE")
    elif x.route_status not in {"REACHES_OTHER_LAKE", "REACHES_RIVER_LINE", "REACHES_RIVER_AREA"}:
        reasons.append("ROUTE_STATUS_NOT_SUPPORTED")
    if x.corner_only_contact:
        reasons.append("CORNER_ONLY_CONTACT")
    if not x.geometry_reviewed:
        reasons.append("UNREVIEWED_RANTA10_GEOMETRY")
    if not x.provenance_verified:
        reasons.append("UNVERIFIED_PROVENANCE")
    if not x.full_downstream_verified:
        reasons.append("FIRST_WATER_IS_NOT_FULL_CONNECTION")
    return ("REVIEW_REQUIRED", tuple(reasons)) if reasons else ("READY_FOR_SEPARATE_APPROVAL", ())


def synthetic_accumulation(nodes: list[Node], arcs: list[Arc], *, split_mode: bool = False,
                           enforce_boundary_terminals: bool = True) -> dict:
    """Oracle for hypothetical *already approved* synthetic arcs.

    Cell area = 4 m^2. Every raster cell has one owner. No implied real approval,
    no external inflow and no loss factors. Results are local-only.
    """
    allowed_kinds = {"LAND", "LAKE", "RIVER_REACH", "BOUNDARY"}
    allowed_arc_kinds = {"LAND_D8", "LAKE_OUTLET", "RIVER_LINK", "BOUNDARY_EXIT"}
    by_key = {}
    owners = {}
    for node in nodes:
        if node.key in by_key or not node.key or node.kind not in allowed_kinds:
            raise GraphContractError("duplicate node ID or invalid kind")
        if node.kind == "BOUNDARY" and node.owned_cells:
            raise GraphContractError("boundary cannot own local cells")
        by_key[node.key] = node
        for cell in node.owned_cells:
            if type(cell) is not int or cell <= 0 or cell > 36000000 or cell in owners:
                raise GraphContractError("invalid, duplicated or multiply owned cell")
            owners[cell] = node.key
    if not by_key:
        raise GraphContractError("empty graph")
    out = defaultdict(list)
    indeg = dict.fromkeys(by_key, 0)
    seen = set()
    for arc in arcs:
        if arc.source not in by_key or arc.target not in by_key:
            raise GraphContractError("arc endpoint missing")
        if arc.kind not in allowed_arc_kinds or arc.source == arc.target:
            raise GraphContractError("invalid arc kind or self-loop")
        if (arc.source, arc.target) in seen:
            raise GraphContractError("duplicate arc to same receiver")
        seen.add((arc.source, arc.target))
        if not isinstance(arc.fraction, Fraction) or not (0 < arc.fraction <= 1):
            raise GraphContractError("invalid or unproven allocation fraction")
        source_kind = by_key[arc.source].kind
        if source_kind == "BOUNDARY":
            raise GraphContractError("boundary must be terminal")
        if {"LAND_D8":"LAND", "LAKE_OUTLET":"LAKE", "RIVER_LINK":"RIVER_REACH"}.get(arc.kind) not in {source_kind, None}:
            raise GraphContractError("source node and edge kind mismatch")
        if arc.kind == "BOUNDARY_EXIT" and by_key[arc.target].kind != "BOUNDARY":
            raise GraphContractError("boundary exit must reach boundary node")
        out[arc.source].append(arc)
        indeg[arc.target] += 1
    for key, node in by_key.items():
        edges = out[key]
        if not edges:
            if enforce_boundary_terminals and node.kind != "BOUNDARY":
                raise GraphContractError("nonboundary terminal with no validated outlet")
            continue
        if len(edges) == 1:
            if edges[0].fraction != 1:
                raise GraphContractError("one outlet must transmit full contribution")
        else:
            if not (split_mode and node.kind == "LAKE" and
                    all(e.kind == "LAKE_OUTLET" for e in edges) and
                    sum((e.fraction for e in edges), Fraction()) == 1):
                raise GraphContractError("ambiguous multiple outlets / split not explicitly allocated")
    received = {key: Fraction(len(node.owned_cells)*4, 1) for key, node in by_key.items()}
    queue = deque(sorted(k for k, v in indeg.items() if v == 0))
    done = 0
    while queue:
        src = queue.popleft()
        done += 1
        for arc in out[src]:
            received[arc.target] += received[src]*arc.fraction
            indeg[arc.target] -= 1
            if indeg[arc.target] == 0:
                queue.append(arc.target)
    if done != len(by_key):
        raise GraphContractError("D8 or waterbody graph cycle")
    local_total = Fraction(len(owners)*4, 1)
    terminal_sum = sum((received[key] for key in by_key if not out[key]), Fraction())
    if local_total != terminal_sum:
        raise GraphContractError("mass conservation violated")
    return {
        "scope": "SYNTHETIC_LOCAL_ONLY_NO_EXTERNAL_INFLOW",
        "local_unique_cell_area_m2": local_total,
        "received_area_m2": received,
        "terminal_area_m2": terminal_sum,
        "n_cells": len(owners),
        "hydrological_validation": "NOT_ASSESSED",
        "NATIONAL": "LOCKED",
    }