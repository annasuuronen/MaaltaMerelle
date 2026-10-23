"""G5A: bounded, synthetic-only partition QA around the existing graph oracle.

No I/O, raster access, physical edge approval or production accumulation.
Independent verification enumerates weighted paths from each owned cell; it is
intentionally unsuitable for large graphs. All returned collections are tuples.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from fractions import Fraction

from graph_oracle import Arc, GraphContractError, Node, synthetic_accumulation

MAX_NODES = 20
MAX_CELLS = 64
MAX_ARCS = 64
MAX_TRANSFERS = 64
MAX_HALOS = 128
MAX_PATH_STATES = 20_000
MAX_FRACTION_BITS = 256


class Status(str, Enum):
    PASS = "PASS"  # synthetic mathematical parity only
    STOP = "STOP"
    UNKNOWN = "UNKNOWN"


@dataclass(frozen=True)
class Halo:
    cell: int
    node: str
    owner_tile: str


@dataclass(frozen=True)
class Tile:
    key: str
    mask_cells: tuple[int, ...]
    halos: tuple[Halo, ...] = ()


@dataclass(frozen=True)
class OwnedNode:
    key: str
    kind: str
    owner_tile: str
    cells: tuple[int, ...] = ()
    terminal_role: str | None = None


@dataclass(frozen=True)
class FlowArc:
    source: str
    target: str
    kind: str
    fraction: Fraction | None = Fraction(1)
    provenance_status: str = "SYNTHETIC_EXPLICIT"


@dataclass(frozen=True)
class Transfer:
    transfer_id: str
    upstream_tile: str
    downstream_tile: str
    from_node: str
    to_node: str
    from_cell: int
    to_cell: int
    provenance_status: str = "SYNTHETIC_EXPLICIT"
    claimed_area_m2: Fraction | None = None
    injected_area_m2: Fraction = Fraction(0)


@dataclass(frozen=True)
class Upstream:
    target: str
    source_cells: tuple[int, ...] = ()
    area_m2: Fraction | None = None


@dataclass(frozen=True)
class Fixture:
    tiles: tuple[Tile, ...]
    nodes: tuple[OwnedNode, ...]
    arcs: tuple[FlowArc, ...]
    transfers: tuple[Transfer, ...] = ()
    upstream: tuple[Upstream, ...] = ()
    split_mode: bool = False
    resolution_m: Fraction = Fraction(2)


@dataclass(frozen=True, order=True)
class Finding:
    code: str
    detail: str


@dataclass(frozen=True)
class Receipt:
    transfer_id: str
    from_node: str
    to_node: str
    area_m2: Fraction


@dataclass(frozen=True)
class TileBalance:
    tile: str
    owned_area_m2: Fraction
    incoming_m2: Fraction
    outgoing_m2: Fraction
    terminal_m2: Fraction


@dataclass(frozen=True)
class Reconciliation:
    status: Status
    findings: tuple[Finding, ...] = ()
    owned_area_m2: Fraction | None = None
    terminal_area_m2: Fraction | None = None
    complete_area_m2: Fraction | None = None
    oracle_received_m2: tuple[tuple[str, Fraction], ...] = ()
    path_received_m2: tuple[tuple[str, Fraction], ...] = ()
    receipts: tuple[Receipt, ...] = ()
    tile_balances: tuple[TileBalance, ...] = ()
    boundary_roles: tuple[tuple[str, str | None], ...] = ()
    path_states: int = 0
    scope: str = field(default="SYNTHETIC_OWNED_AREA_ONLY", init=False)
    NATIONAL: str = field(default="LOCKED", init=False)
    MODERATE: str = field(default="REVIEW_REQUIRED", init=False)
    hydrological_validation: str = field(default="NOT_ASSESSED", init=False)
    channel_interpretation: str = field(default="NOT_ASSESSED", init=False)
    routing_authorized: bool = field(default=False, init=False)


class _Stop(Exception):
    def __init__(self, code: str, detail: str):
        self.finding = Finding(code, detail)


def _require(ok: bool, code: str, detail: str) -> None:
    if not ok:
        raise _Stop(code, detail)


def _key(x: object) -> bool:
    return type(x) is str and 0 < len(x) <= 128 and x.isprintable()


def _cell(x: object) -> bool:
    return type(x) is int and 0 < x <= 36_000_000


def _fraction(x: object) -> bool:
    return (type(x) is Fraction and
            max(abs(x.numerator).bit_length(), x.denominator.bit_length())
            <= MAX_FRACTION_BITS)


def _records(value: object, cls: type, limit: int) -> None:
    _require(type(value) is tuple, "INVALID_SCHEMA", "records must be immutable tuples")
    _require(len(value) <= limit, "RESOURCE_LIMIT", cls.__name__)
    _require(all(type(v) is cls for v in value), "INVALID_SCHEMA", cls.__name__)


def _cycle_check(nodes: dict[str, OwnedNode], out: dict[str, list[FlowArc]]) -> None:
    """Sidecar cycle diagnostics distinguish local from cross-partition cycles."""
    done: set[str] = set()
    active: list[str] = []

    def visit(key: str) -> None:
        if key in active:
            cycle = active[active.index(key):]
            code = ("CROSS_TILE_CYCLE" if len({nodes[k].owner_tile for k in cycle}) > 1
                    else "GRAPH_CYCLE")
            raise _Stop(code, ",".join(sorted(cycle)))
        if key in done:
            return
        active.append(key)
        for arc in sorted(out[key], key=lambda a: a.target):
            visit(arc.target)
        active.pop()
        done.add(key)

    for key in sorted(nodes):
        visit(key)


def reconcile(fixture: Fixture) -> Reconciliation:
    """Return PASS/UNKNOWN/STOP; never authorize a physical routing connection.

    PASS means only exact closed synthetic area parity. UNKNOWN numbers are
    lower bounds for represented owned cells, excluding unknown external area.
    Malformed schemas, contradictions and bounds return STOP with no numbers.
    """
    try:
        return _reconcile(fixture)
    except _Stop as exc:
        return Reconciliation(Status.STOP, (exc.finding,))
    except GraphContractError as exc:
        return Reconciliation(Status.STOP, (Finding("ORACLE_CONTRACT_ERROR", str(exc)),))


def _reconcile(f: Fixture) -> Reconciliation:
    _require(type(f) is Fixture, "INVALID_SCHEMA", "Fixture required")
    _records(f.tiles, Tile, 2)
    _records(f.nodes, OwnedNode, MAX_NODES)
    _records(f.arcs, FlowArc, MAX_ARCS)
    _records(f.transfers, Transfer, MAX_TRANSFERS)
    _records(f.upstream, Upstream, MAX_NODES)
    _require(type(f.split_mode) is bool, "INVALID_SCHEMA", "split_mode")
    _require(_fraction(f.resolution_m) and f.resolution_m == 2,
             "INVALID_RESOLUTION", "only exact 2 m cells are supported")
    _require(bool(f.tiles) and bool(f.nodes), "INVALID_SCHEMA", "empty fixture")
    tiles: dict[str, Tile] = {}
    mask_owner: dict[int, str] = {}
    for tile in f.tiles:
        _require(_key(tile.key) and tile.key not in tiles, "INVALID_TILE", "tile ID")
        _require(type(tile.mask_cells) is tuple, "INVALID_SCHEMA", "mask_cells")
        _require(len(tile.mask_cells) <= MAX_CELLS, "RESOURCE_LIMIT", "mask cells")
        _records(tile.halos, Halo, MAX_HALOS)
        for cell in tile.mask_cells:
            _require(_cell(cell), "INVALID_CELL", "mask cell")
            _require(cell not in mask_owner, "DUPLICATE_CELL_OWNERSHIP", "mask cell")
            mask_owner[cell] = tile.key
        tiles[tile.key] = tile
    _require(len(mask_owner) <= MAX_CELLS, "RESOURCE_LIMIT", "total mask cells")
    _require(sum(len(t.halos) for t in f.tiles) <= MAX_HALOS,
             "RESOURCE_LIMIT", "total halo references")
    nodes: dict[str, OwnedNode] = {}
    owner: dict[int, tuple[str, str]] = {}
    roles = {"SYNTHETIC_TERMINAL", "TILE_BOUNDARY", "COAST", None}
    for node in f.nodes:
        _require(_key(node.key) and node.key not in nodes, "INVALID_NODE", "node ID")
        _require(_key(node.owner_tile) and node.owner_tile in tiles,
                 "OWNERSHIP_MISMATCH", "node tile")
        _require(type(node.kind) is str and node.kind in
                 {"LAND", "LAKE", "RIVER_REACH", "BOUNDARY"}, "INVALID_NODE", "kind")
        _require(type(node.cells) is tuple, "INVALID_SCHEMA", "node cells")
        _require(len(node.cells) <= MAX_CELLS, "RESOURCE_LIMIT", "node cells")
        _require(node.terminal_role is None or type(node.terminal_role) is str,
                 "INVALID_SCHEMA", "terminal role")
        _require(node.terminal_role in roles and
                 (node.kind == "BOUNDARY" or node.terminal_role is None),
                 "INVALID_NODE", "terminal role")
        _require(node.kind != "BOUNDARY" or not node.cells,
                 "BOUNDARY_OWNS_AREA", node.key)
        _require(node.kind not in {"LAND", "LAKE"} or bool(node.cells),
                 "OWNERSHIP_MISMATCH", "land/lake needs physical cells")
        for cell in node.cells:
            _require(_cell(cell), "INVALID_CELL", "owned cell")
            _require(cell not in owner, "DUPLICATE_CELL_OWNERSHIP", "owned cell")
            owner[cell] = (node.key, node.owner_tile)
        nodes[node.key] = node
    _require(len(owner) <= MAX_CELLS, "RESOURCE_LIMIT", "unique cells")
    _require(bool(owner), "OWNERSHIP_MISMATCH", "no physical cell contributions")
    _require({c: t for c, (_, t) in owner.items()} == mask_owner,
             "MASK_OWNERSHIP_MISMATCH", "mask != owned physical cells")
    for tile in f.tiles:
        seen_halos: set[int] = set()
        for halo in tile.halos:
            _require(_cell(halo.cell) and _key(halo.node) and _key(halo.owner_tile),
                     "INVALID_SCHEMA", "halo identity")
            _require(halo.cell not in seen_halos, "DUPLICATE_HALO", "repeated reference")
            _require(halo.owner_tile != tile.key and
                     owner.get(halo.cell) == (halo.node, halo.owner_tile),
                     "HALO_OWNERSHIP_MISMATCH", "halo must reference a remote owner")
            seen_halos.add(halo.cell)
    arcs: dict[tuple[str, str], FlowArc] = {}
    out: dict[str, list[FlowArc]] = {k: [] for k in nodes}
    for arc in f.arcs:
        _require(_key(arc.source) and _key(arc.target) and
                 arc.source in nodes and arc.target in nodes,
                 "MISSING_ENDPOINT", "arc endpoint")
        pair = (arc.source, arc.target)
        _require(pair not in arcs, "DUPLICATE_ARC", "/".join(pair))
        _require(arc.provenance_status == "SYNTHETIC_EXPLICIT",
                 "UNSUPPORTED_ROUTING_EVIDENCE", "S1/02F observations are not active arcs")
        _require(type(arc.kind) is str and arc.kind in
                 {"LAND_D8", "LAKE_OUTLET", "RIVER_LINK", "BOUNDARY_EXIT"},
                 "INVALID_ARC", "arc kind")
        expected = {"LAND_D8": "LAND", "LAKE_OUTLET": "LAKE", "RIVER_LINK": "RIVER_REACH"}
        _require(nodes[arc.source].kind != "BOUNDARY" and
                 (arc.kind not in expected or nodes[arc.source].kind == expected[arc.kind]) and
                 (arc.kind != "BOUNDARY_EXIT" or nodes[arc.target].kind == "BOUNDARY"),
                 "INVALID_ARC", "source/target kind mismatch")
        _require(_fraction(arc.fraction) and 0 < arc.fraction <= 1,
                 "INVALID_FLOW_SPLIT", "exact positive Fraction required")
        arcs[pair] = arc
        out[arc.source].append(arc)
    for key, edges in out.items():
        if edges:
            _require(sum((e.fraction for e in edges), Fraction()) == 1 and
                     (len(edges) == 1 or (f.split_mode and nodes[key].kind == "LAKE" and
                                         all(e.kind == "LAKE_OUTLET" for e in edges))),
                     "INVALID_FLOW_SPLIT", key)
    _cycle_check(nodes, out)
    cross = {pair: a for pair, a in arcs.items()
             if nodes[a.source].owner_tile != nodes[a.target].owner_tile}
    transfers: dict[tuple[str, str], Transfer] = {}
    ids: set[str] = set()
    for tr in f.transfers:
        _require(_key(tr.transfer_id), "INVALID_TRANSFER", "transfer ID")
        _require(all(_key(x) for x in (tr.upstream_tile, tr.downstream_tile,
                                      tr.from_node, tr.to_node)),
                 "INVALID_TRANSFER", "transfer endpoints")
        pair = (tr.from_node, tr.to_node)
        _require(tr.transfer_id not in ids and pair not in transfers,
                 "MISSING_OR_DUPLICATE_TRANSFER", "repeated transfer identity or arc")
        _require(pair in cross, "MISSING_OR_DUPLICATE_TRANSFER", "unmatched/conflicting transfer")
        _require(tr.provenance_status == "SYNTHETIC_EXPLICIT",
                 "UNSUPPORTED_ROUTING_EVIDENCE", "transfer provenance")
        _require(_cell(tr.from_cell) and _cell(tr.to_cell),
                 "INVALID_TRANSFER", "transfer physical cells")
        _require(owner.get(tr.from_cell) == (tr.from_node, tr.upstream_tile) and
                 owner.get(tr.to_cell) == (tr.to_node, tr.downstream_tile),
                 "OWNERSHIP_MISMATCH", "transfer cells/tiles/nodes disagree")
        _require(_fraction(tr.injected_area_m2), "INVALID_TRANSFER", "injected area")
        _require(tr.injected_area_m2 == 0, "SHARED_UPSTREAM_COUNTED_TWICE",
                 "seam flux is derived, never injected in addition to owned cells")
        _require(tr.claimed_area_m2 is None or
                 (_fraction(tr.claimed_area_m2) and tr.claimed_area_m2 >= 0),
                 "INVALID_TRANSFER", "claimed area")
        transfers[pair] = tr
        ids.add(tr.transfer_id)
    _require(set(transfers) == set(cross), "MISSING_OR_DUPLICATE_TRANSFER", "missing seam transfer")
    unknown: list[Finding] = []
    for upstream in f.upstream:
        _require(_key(upstream.target) and upstream.target in nodes,
                 "MISSING_ENDPOINT", "upstream target")
        _require(type(upstream.source_cells) is tuple and len(upstream.source_cells) <= MAX_CELLS
                 and all(_cell(c) for c in upstream.source_cells),
                 "INVALID_SCHEMA", "upstream source cells")
        _require(not any(c in owner for c in upstream.source_cells),
                 "SHARED_UPSTREAM_COUNTED_TWICE", "owned cells cannot be external input")
        _require(upstream.area_m2 is None, "EXTERNAL_AREA_NOT_SUPPORTED",
                 "G5A models unknown imports, not measured external injections")
        unknown.append(Finding("UPSTREAM_UNKNOWN", upstream.target))
    for key, node in sorted(nodes.items()):
        if not out[key]:
            if node.kind != "BOUNDARY":
                unknown.append(Finding("MISSING_OUTLET", key))
            elif node.terminal_role in {None, "TILE_BOUNDARY"}:
                unknown.extend((Finding("TILE_BOUNDARY_UNRESOLVED", key),
                                Finding("BOUNDARY_NOT_COAST", key)))
    # The existing topological algorithm is invoked once as the global contract.
    global_result = synthetic_accumulation(
        [Node(n.key, n.kind, tuple(sorted(n.cells))) for n in sorted(f.nodes, key=lambda n: n.key)],
        [Arc(a.source, a.target, a.kind, a.fraction) for _, a in sorted(arcs.items())],
        split_mode=f.split_mode, enforce_boundary_terminals=False)

    # Structurally independent, bounded brute-force weighted-path accounting.
    # Every physical cell starts with 4 m² exactly once. Halos start no paths.
    received = {key: Fraction() for key in nodes}
    flux = {pair: Fraction() for pair in cross}
    states = 0
    for cell, (origin, _) in sorted(owner.items()):
        stack = [(origin, Fraction(1))]
        terminal_weight = Fraction()
        while stack:
            key, weight = stack.pop()
            states += 1
            _require(states <= MAX_PATH_STATES, "RESOURCE_LIMIT", "weighted path states")
            received[key] += 4 * weight
            if not out[key]:
                terminal_weight += weight
            for arc in sorted(out[key], key=lambda a: a.target):
                next_weight = weight * arc.fraction
                if (key, arc.target) in flux:
                    flux[key, arc.target] += 4 * next_weight
                stack.append((arc.target, next_weight))
        _require(terminal_weight == 1, "SHARED_UPSTREAM_COUNTED_TWICE",
                 "per-cell terminal path weights must sum to one")
    _require(received == global_result["received_area_m2"], "PARITY_MISMATCH",
             "weighted paths != graph oracle")
    terminal = sum((received[k] for k in nodes if not out[k]), Fraction())
    total = Fraction(4 * len(owner))
    _require(terminal == total == global_result["terminal_area_m2"],
             "AREA_CONSERVATION_FAILURE", "terminal area != unique owned area")
    receipts = []
    for pair, tr in sorted(transfers.items(), key=lambda item: item[1].transfer_id):
        area = flux[pair]
        _require(area == global_result["received_area_m2"][pair[0]] * arcs[pair].fraction,
                 "PARITY_MISMATCH", "independent seam flux != oracle fraction")
        _require(tr.claimed_area_m2 is None or tr.claimed_area_m2 == area,
                 "TRANSFER_AREA_MISMATCH", tr.transfer_id)
        receipts.append(Receipt(tr.transfer_id, *pair, area))
    balances = []
    for tile in sorted(tiles):
        local = Fraction(4 * sum(t == tile for _, t in owner.values()))
        incoming = sum((flux[p] for p, tr in transfers.items() if tr.downstream_tile == tile), Fraction())
        outgoing = sum((flux[p] for p, tr in transfers.items() if tr.upstream_tile == tile), Fraction())
        ends = sum((received[k] for k, n in nodes.items()
                    if n.owner_tile == tile and not out[k]), Fraction())
        _require(local + incoming - outgoing == ends, "TILE_BALANCE_FAILURE", tile)
        balances.append(TileBalance(tile, local, incoming, outgoing, ends))
    return Reconciliation(
        status=Status.UNKNOWN if unknown else Status.PASS,
        findings=tuple(sorted(set(unknown))), owned_area_m2=total,
        terminal_area_m2=terminal, complete_area_m2=None if unknown else total,
        oracle_received_m2=tuple(sorted(global_result["received_area_m2"].items())),
        path_received_m2=tuple(sorted(received.items())), receipts=tuple(receipts),
        tile_balances=tuple(balances),
        boundary_roles=tuple(sorted((n.key, n.terminal_role) for n in f.nodes if n.kind == "BOUNDARY")),
        path_states=states)
